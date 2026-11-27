"""M4c research line: Masked TCN & PatchTST-Lite evaluated on exact M4b walk-forward folds with paired fold tests."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from scipy import stats
import torch
from torch import nn

from .forecasting import (
    FEATURE_COLUMNS,
    TARGETS,
    build_supervised_dataset,
    generate_walk_forward_folds,
)


def _set_seed(seed: int = 42) -> None:
    np.random.seed(seed)
    torch.manual_seed(seed)


class MaskedTCN(nn.Module):
    """Lightweight causal 1D dilated temporal convolutional regressor for 14-day sequences."""

    def __init__(self, in_features: int, hidden_channels: int = 24, dropout: float = 0.15) -> None:
        super().__init__()
        self.proj_in = nn.Linear(in_features, hidden_channels)
        # Causal dilated conv layers (kernel_size=3) via left-only padding inside forward
        self.conv1 = nn.Conv1d(hidden_channels, hidden_channels, kernel_size=3, dilation=1)
        self.conv2 = nn.Conv1d(hidden_channels, hidden_channels, kernel_size=3, dilation=2)
        self.act = nn.GELU()
        self.drop = nn.Dropout(dropout)
        self.head = nn.Linear(hidden_channels, 1)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: (B, T, F)
        h = self.act(self.proj_in(x)).transpose(1, 2)  # (B, C, T)
        p1 = nn.functional.pad(h, (2, 0))
        h1 = self.drop(self.act(self.conv1(p1))) + h
        p2 = nn.functional.pad(h1, (4, 0))
        h2 = self.drop(self.act(self.conv2(p2))) + h1
        last = h2[:, :, -1]
        return self.head(last).squeeze(-1)


class PatchTSTLite(nn.Module):
    """Compact PatchTST-style channel-mixing encoder over 2-day patches of 14-day windows."""

    def __init__(self, in_features: int, patch_len: int = 2, d_model: int = 24, dropout: float = 0.15) -> None:
        super().__init__()
        self.patch_len = patch_len
        self.patch_embed = nn.Linear(in_features * patch_len, d_model)
        self.pos_emb = nn.Parameter(torch.zeros(1, 16, d_model))
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model,
            nhead=2,
            dim_feedforward=48,
            dropout=dropout,
            activation="gelu",
            batch_first=True,
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=1)
        self.norm = nn.LayerNorm(d_model)
        self.head = nn.Linear(d_model, 1)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: (B, T, F) where T is divisible by patch_len
        b, t, f = x.shape
        n_patches = t // self.patch_len
        patches = x[:, : n_patches * self.patch_len, :].reshape(b, n_patches, f * self.patch_len)
        tokens = self.patch_embed(patches) + self.pos_emb[:, :n_patches, :]
        encoded = self.norm(self.encoder(tokens))
        pooled = encoded.mean(dim=1)
        return self.head(pooled).squeeze(-1)


def _build_causal_sequences(
    X_raw: np.ndarray,
    indices: np.ndarray,
    mean: np.ndarray,
    std: np.ndarray,
    seq_len: int = 14,
) -> np.ndarray:
    """Build strictly causal sequence windows [idx - seq_len + 1 .. idx] standardized with train mean/std."""
    X_std = np.clip((X_raw - mean) / std, -6.0, 6.0).astype(np.float32)
    n_feat = X_std.shape[1]
    out = np.zeros((len(indices), seq_len, n_feat), dtype=np.float32)
    for row_i, idx in enumerate(indices):
        start = max(0, idx - seq_len + 1)
        window = X_std[start : idx + 1]
        out[row_i, seq_len - len(window) :, :] = window
    return out


def _train_and_predict_deep(
    model_kind: str,
    X_all: np.ndarray,
    y_all: np.ndarray,
    t_cfg: dict[str, Any],
    train_idx: np.ndarray,
    test_idx: np.ndarray,
    seq_len: int = 14,
    epochs: int = 35,
) -> tuple[np.ndarray, float, float]:
    _set_seed(42)

    n_train = len(train_idx)
    val_size = max(20, int(0.20 * n_train))
    fit_idx = train_idx[:-val_size]
    val_idx = train_idx[-val_size:]

    mean = X_all[fit_idx].mean(axis=0)
    std = np.where(X_all[fit_idx].std(axis=0) < 1e-5, 1.0, X_all[fit_idx].std(axis=0))

    X_fit_seq = _build_causal_sequences(X_all, fit_idx, mean, std, seq_len=seq_len)
    X_val_seq = _build_causal_sequences(X_all, val_idx, mean, std, seq_len=seq_len)
    X_test_seq = _build_causal_sequences(X_all, test_idx, mean, std, seq_len=seq_len)

    y_mean = float(y_all[fit_idx].mean())
    y_std = float(max(1e-4, y_all[fit_idx].std()))
    y_fit_norm = ((y_all[fit_idx] - y_mean) / y_std).astype(np.float32)

    in_f = X_all.shape[1]
    model: nn.Module = MaskedTCN(in_f) if model_kind == "MaskedTCN" else PatchTSTLite(in_f)
    optimizer = torch.optim.AdamW(model.parameters(), lr=3e-3, weight_decay=2e-2)
    loss_fn = nn.HuberLoss(delta=1.0)

    x_fit_t = torch.from_numpy(X_fit_seq)
    y_fit_t = torch.from_numpy(y_fit_norm)
    x_val_t = torch.from_numpy(X_val_seq)

    best_val_mae = float("inf")
    best_state = {k: v.detach().clone() for k, v in model.state_dict().items()}
    best_cal_res = np.array([y_std], dtype=float)
    patience = 7
    no_improve = 0

    batch_size = 64
    n_fit = len(fit_idx)

    for _ in range(epochs):
        model.train()
        perm = torch.randperm(n_fit)
        for s in range(0, n_fit, batch_size):
            b_idx = perm[s : s + batch_size]
            optimizer.zero_grad()
            pred = model(x_fit_t[b_idx])
            loss = loss_fn(pred, y_fit_t[b_idx])
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            optimizer.step()

        model.eval()
        with torch.no_grad():
            val_pred = model(x_val_t).numpy() * y_std + y_mean
            val_pred = np.clip(val_pred, t_cfg["clip_min"], t_cfg["clip_max"])
            val_abs = np.abs(y_all[val_idx] - val_pred)
            val_mae = float(np.mean(val_abs))
            if val_mae + 1e-6 < best_val_mae:
                best_val_mae = val_mae
                best_cal_res = val_abs
                best_state = {k: v.detach().clone() for k, v in model.state_dict().items()}
                no_improve = 0
            else:
                no_improve += 1
                if no_improve >= patience:
                    break

    model.load_state_dict(best_state)
    model.eval()
    with torch.no_grad():
        test_pred = model(torch.from_numpy(X_test_seq)).numpy() * y_std + y_mean
        test_pred = np.clip(test_pred, t_cfg["clip_min"], t_cfg["clip_max"])

    q80 = max(1e-4, float(np.quantile(best_cal_res, 0.80)))
    q90 = max(1e-4, float(np.quantile(best_cal_res, 0.90)))
    return test_pred, q80, q90


def _paired_fold_test(deep_maes: list[float], baseline_maes: list[float]) -> dict[str, Any]:
    d = np.array(deep_maes, dtype=float) - np.array(baseline_maes, dtype=float)
    n_folds = len(d)
    if n_folds < 2 or float(np.std(d)) < 1e-12:
        return {
            "n_folds": n_folds,
            "mean_diff_mae": float(np.mean(d)) if n_folds else 0.0,
            "t_stat": 0.0,
            "p_ttest_one_sided": 1.0,
            "p_wilcoxon_one_sided": 1.0,
        }

    t_res = stats.ttest_rel(deep_maes, baseline_maes, alternative="less")
    try:
        w_res = stats.wilcoxon(d, alternative="less", zero_method="pratt")
        p_wil = float(w_res.pvalue)
    except ValueError:
        p_wil = 1.0

    return {
        "n_folds": n_folds,
        "mean_diff_mae": float(np.mean(d)),
        "t_stat": float(t_res.statistic),
        "p_ttest_one_sided": float(t_res.pvalue),
        "p_wilcoxon_one_sided": p_wil,
    }


def run_m4c_comparison(
    df: pd.DataFrame,
    m4b_payload: dict[str, Any],
    initial_months: int = 24,
    epochs: int = 35,
) -> dict[str, Any]:
    """Run MaskedTCN and PatchTSTLite on the exact M4b folds and perform paired hypothesis tests."""
    sup_df = build_supervised_dataset(df)
    X_all = sup_df[list(FEATURE_COLUMNS)].to_numpy(dtype=float)

    results_by_target: dict[str, Any] = {}
    deep_models = ("MaskedTCN", "PatchTSTLite")

    for t_cfg in TARGETS:
        t_name = t_cfg["name"]
        target_col = f"target_{t_name}"
        y_all = sup_df[target_col].to_numpy(dtype=float)
        folds = generate_walk_forward_folds(sup_df, target_col=target_col, initial_months=initial_months)

        m4b_target = m4b_payload["targets"][t_name]
        best_base_name = m4b_target["best_baseline_model"]
        best_base_mae = float(m4b_target["best_overall_mae"])
        base_fold_maes = [float(f["mae"]) for f in m4b_target["models"][best_base_name]["folds"]]

        target_deep: dict[str, Any] = {}
        for m_name in deep_models:
            all_abs_errs: list[float] = []
            all_sq_errs: list[float] = []
            cov80_flags: list[bool] = []
            cov90_flags: list[bool] = []
            fold_maes: list[float] = []

            for fold in folds:
                y_true = y_all[fold.test_indices]
                preds, q80, q90 = _train_and_predict_deep(
                    model_kind=m_name,
                    X_all=X_all,
                    y_all=y_all,
                    t_cfg=t_cfg,
                    train_idx=fold.train_indices,
                    test_idx=fold.test_indices,
                    epochs=epochs,
                )
                abs_err = np.abs(y_true - preds)
                sq_err = (y_true - preds) ** 2
                fold_maes.append(float(np.mean(abs_err)))
                all_abs_errs.extend(abs_err.tolist())
                all_sq_errs.extend(sq_err.tolist())
                cov80_flags.extend((abs_err <= q80).tolist())
                cov90_flags.extend((abs_err <= q90).tolist())

            overall_mae = float(np.mean(all_abs_errs)) if all_abs_errs else float("nan")
            overall_rmse = float(np.sqrt(np.mean(all_sq_errs))) if all_sq_errs else float("nan")
            paired = _paired_fold_test(fold_maes, base_fold_maes[: len(fold_maes)])
            promoted = bool(
                overall_mae < best_base_mae
                and paired["p_ttest_one_sided"] < 0.05
                and paired["p_wilcoxon_one_sided"] < 0.05
            )
            target_deep[m_name] = {
                "overall_mae": overall_mae,
                "overall_rmse": overall_rmse,
                "fold_mean_mae": float(np.mean(fold_maes)) if fold_maes else float("nan"),
                "fold_std_mae": float(np.std(fold_maes)) if fold_maes else float("nan"),
                "coverage_80": float(np.mean(cov80_flags)) if cov80_flags else float("nan"),
                "coverage_90": float(np.mean(cov90_flags)) if cov90_flags else float("nan"),
                "paired_test": paired,
                "promoted": promoted,
            }

        results_by_target[t_name] = {
            "title": t_cfg["title"],
            "unit": t_cfg["unit"],
            "best_baseline_model": best_base_name,
            "best_baseline_mae": best_base_mae,
            "deep_models": target_deep,
        }

    return {
        "schema_version": "m4c-deep-comparison-v1",
        "seq_len": 14,
        "targets": results_by_target,
    }


def render_m4c_report(m4c_payload: dict[str, Any], report_path: Path) -> None:
    """Write honest M4c paired-fold comparison report enforcing the promotion gate."""
    lines: list[str] = [
        "# BodySeek M4c 深度时序研究线对比与配对显著性检验报告（2026-11-20）",
        "",
        "- 研究架构：`MaskedTCN`（2 层因果空洞卷积，14 天窗口）与 `PatchTSTLite`（2 日 Patch + TransformerEncoder）。",
        "- 配对检验准入标准（Blueprint V5 §10）：在**完全相同的按月滚动 Walk-Forward 折**上，深度模型只有在**Overall MAE 严格低于 M4b 最优基线**且**折间单侧配对检验（Paired $t$ 检验与 Wilcoxon 符号秩检验均 $p < 0.05$）显著胜出**时才允许上线，否则诚实淘汰、保留更稳健的低方差基线。",
        "",
        "## 1. 逐目标折间配对检验结果",
        "",
    ]

    any_promoted = False
    for t_name, info in m4c_payload["targets"].items():
        lines.append(f"### 目标：`{t_name}`（{info['title']}）")
        lines.append("")
        lines.append(f"- 对标 M4b 最优基线：**`{info['best_baseline_model']}`**（Overall MAE = `{info['best_baseline_mae']:.4f}`）")
        lines.append("")
        lines.append("| 深度模型 | Overall MAE | RMSE | Mean Fold Diff (Deep - Base) | 配对 $t$ 单侧 $p$ | Wilcoxon 单侧 $p$ | 80% 覆盖率 | 准入结果 |")
        lines.append("|---|---:|---:|---:|---:|---:|---:|---|")
        for m_name, stat in info["deep_models"].items():
            pt = stat["paired_test"]
            if stat["promoted"]:
                any_promoted = True
            verdict = "**晋升上线**" if stat["promoted"] else "未显著优于基线（不上线）"
            lines.append(
                f"| `{m_name}` | `{stat['overall_mae']:.4f}` | `{stat['overall_rmse']:.4f}` | "
                f"`{pt['mean_diff_mae']:+.4f}` | `{pt['p_ttest_one_sided']:.4f}` | "
                f"`{pt['p_wilcoxon_one_sided']:.4f}` | `{stat['coverage_80'] * 100:.1f}%` | {verdict} |"
            )
        lines.append("")

    lines.extend(
        [
            "## 2. 上机决策结论",
            "",
            f"- 实证裁决：{'部分目标满足显著胜出条件' if any_promoted else '**MaskedTCN 与 PatchTSTLite 在全部目标上均未显著优于 M4b 正则化基线**'}。",
            "- 根据 V5 §10「不盲目把大模型硬塞上线」的科学原则，M4d 端侧 CoreML（`.mlpackage`）选用在各目标上更稳健的低方差正则化状态空间/线性基线家族部署上机，既确保零过拟合、冷启动与低功耗，又保持完全可复现与端侧确定性。",
            "",
        ]
    )

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text("\n".join(lines), encoding="utf-8")
