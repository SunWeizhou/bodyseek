"""M4d CoreML .mlpackage export, shared feature_spec JSON, anonymized golden parity vectors, and Model Card."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import coremltools as ct
from coremltools.converters.mil import Builder as mb
import numpy as np
import pandas as pd
from sklearn.linear_model import Ridge
from sklearn.preprocessing import StandardScaler

from .forecasting import FEATURE_COLUMNS, TARGETS, build_supervised_dataset

MODEL_VERSION = "personal-forecaster-v1@1.0.0"


def fit_and_export_coreml(
    df: pd.DataFrame,
    m4b_payload: dict[str, Any],
    m4c_payload: dict[str, Any],
    kit_dir: Path,
    docs_dir: Path,
    model_name: str = "BodySeekPersonalForecasterV1.mlpackage",
) -> dict[str, Any]:
    """Fit full regularized multi-target forecaster, export CoreML .mlpackage, and emit golden parity vectors."""
    sup_df = build_supervised_dataset(df)

    target_cols = [f"target_{t['name']}" for t in TARGETS]
    # Standardize features across all valid feature rows (using causal dataset stats)
    valid_any = sup_df[target_cols].notna().any(axis=1).to_numpy()
    X_all = sup_df.loc[valid_any, list(FEATURE_COLUMNS)].to_numpy(dtype=np.float64)

    scaler = StandardScaler()
    scaler.fit(X_all)
    feat_means = scaler.mean_.astype(np.float32)
    feat_stds = np.where(scaler.scale_ < 1e-5, 1.0, scaler.scale_).astype(np.float32)

    n_features = len(FEATURE_COLUMNS)
    n_targets = len(TARGETS)
    weights = np.zeros((n_targets, n_features), dtype=np.float32)
    biases = np.zeros((n_targets,), dtype=np.float32)
    clip_mins = np.array([float(t["clip_min"]) for t in TARGETS], dtype=np.float32)
    clip_maxs = np.array([float(t["clip_max"]) for t in TARGETS], dtype=np.float32)

    q80_widths: list[float] = []
    q90_widths: list[float] = []

    for idx, t_cfg in enumerate(TARGETS):
        t_col = f"target_{t_cfg['name']}"
        mask = sup_df[t_col].notna().to_numpy()
        X_t = sup_df.loc[mask, list(FEATURE_COLUMNS)].to_numpy(dtype=np.float64)
        y_t = sup_df.loc[mask, t_col].to_numpy(dtype=np.float64)

        X_std = np.clip((X_t - feat_means.astype(np.float64)) / feat_stds.astype(np.float64), -6.0, 6.0)
        cal_size = max(20, int(0.20 * len(X_std)))

        cal_ridge = Ridge(alpha=35.0)
        cal_ridge.fit(X_std[:-cal_size], y_t[:-cal_size])
        cal_pred = np.clip(cal_ridge.predict(X_std[-cal_size:]), t_cfg["clip_min"], t_cfg["clip_max"])
        abs_res = np.abs(y_t[-cal_size:] - cal_pred)
        q80_widths.append(max(1e-4, float(np.quantile(abs_res, 0.80))))
        q90_widths.append(max(1e-4, float(np.quantile(abs_res, 0.90))))

        full_ridge = Ridge(alpha=35.0)
        full_ridge.fit(X_std, y_t)
        weights[idx, :] = full_ridge.coef_.astype(np.float32)
        biases[idx] = float(full_ridge.intercept_)

    def numpy_predict(vec: np.ndarray) -> np.ndarray:
        x = vec.astype(np.float32)
        x_norm = np.clip((x - feat_means) / feat_stds, np.float32(-6.0), np.float32(6.0))
        raw = weights @ x_norm + biases
        return np.clip(raw, clip_mins, clip_maxs)

    # Build real Apple CoreML MLProgram via MIL Builder
    w_t_const = weights.T.astype(np.float32)  # (31, 3)

    @mb.program(input_specs=[mb.TensorSpec(shape=(1, n_features))])
    def prog(features):
        mean_c = mb.const(val=feat_means.reshape(1, n_features), name="feat_mean")
        std_c = mb.const(val=feat_stds.reshape(1, n_features), name="feat_std")
        w_c = mb.const(val=w_t_const, name="weights_t")
        b_c = mb.const(val=biases.reshape(1, n_targets), name="bias")

        diff = mb.sub(x=features, y=mean_c)
        z = mb.real_div(x=diff, y=std_c)
        z_clipped = mb.clip(x=z, alpha=-6.0, beta=6.0)
        raw = mb.add(x=mb.matmul(x=z_clipped, y=w_c), y=b_c)
        low_clipped = mb.maximum(x=raw, y=mb.const(val=clip_mins.reshape(1, n_targets), name="clip_min"))
        predictions = mb.minimum(
            x=low_clipped,
            y=mb.const(val=clip_maxs.reshape(1, n_targets), name="clip_max"),
            name="predictions",
        )
        return predictions

    mlmodel = ct.convert(
        prog,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT32,
        minimum_deployment_target=ct.target.iOS18,
    )
    mlmodel.short_description = "BodySeek Personal Multi-Target Forecaster (Next-day HRV, RHR, Sleep Efficiency)"
    mlmodel.version = "1.0.0"

    resources_dir = kit_dir / "Sources" / "BodySeekCore" / "Resources"
    resources_dir.mkdir(parents=True, exist_ok=True)
    mlpackage_path = resources_dir / model_name
    if mlpackage_path.exists():
        import shutil
        shutil.rmtree(mlpackage_path)
    mlmodel.save(str(mlpackage_path))

    # Re-open saved .mlpackage to verify true CoreML inference parity
    loaded_ml = ct.models.MLModel(str(mlpackage_path))

    # Generate 24 anonymized synthetic/boundary test vectors (NO raw user records / dates)
    rng = np.random.default_rng(2026)
    golden_vectors: list[dict[str, Any]] = []
    max_rel_err = 0.0

    for i in range(24):
        if i == 0:
            # Nominal baseline centered vector
            vec = feat_means.copy()
        elif i == 1:
            # Missing HRV & Sleep masks = 0 boundary test
            vec = feat_means.copy()
            for mask_name in ("hrv_mask0", "sleep_mask0", "effort_user_mask0", "effort_estimated_mask0"):
                vec[FEATURE_COLUMNS.index(mask_name)] = 0.0
        elif i == 2:
            # Clamping upper bound extreme stress test
            vec = feat_means + 8.0 * feat_stds
        elif i == 3:
            # Clamping lower bound extreme stress test
            vec = feat_means - 8.0 * feat_stds
        else:
            vec = (feat_means + rng.normal(0.0, 1.25, size=n_features) * feat_stds).astype(np.float32)
            for idx_col, col_name in enumerate(FEATURE_COLUMNS):
                if col_name.endswith("_mask0"):
                    vec[idx_col] = 0.0 if col_name == "eating_context_mask0" else float(rng.integers(0, 2))
                elif col_name in ("dow_sin", "dow_cos"):
                    ang = 2.0 * np.pi * float(i % 7) / 7.0
                    vec[idx_col] = float(np.sin(ang) if col_name == "dow_sin" else np.cos(ang))

        np_out = numpy_predict(vec)
        cm_dict = loaded_ml.predict({"features": vec.reshape(1, n_features).astype(np.float32)})
        cm_out = np.asarray(cm_dict["predictions"], dtype=np.float32).reshape(-1)

        rel_err = np.abs(cm_out - np_out) / np.maximum(1.0, np.abs(np_out))
        max_rel_err = max(max_rel_err, float(np.max(rel_err)))

        golden_vectors.append(
            {
                "case_id": f"golden_{i:02d}",
                "features": [float(v) for v in vec],
                "expected_numpy": [float(v) for v in np_out],
                "expected_coreml": [float(v) for v in cm_out],
            }
        )

    assert max_rel_err <= 1e-4, f"CoreML vs NumPy parity error exceeded threshold: {max_rel_err}"

    # Shared spec JSON consumed identically by Swift BodySeekCore & Python
    spec_payload = {
        "model_version": MODEL_VERSION,
        "coreml_model_name": "BodySeekPersonalForecasterV1",
        "feature_columns": list(FEATURE_COLUMNS),
        "feature_means": [float(v) for v in feat_means],
        "feature_stds": [float(v) for v in feat_stds],
        "z_clip": 6.0,
        "eating_context_mask_reserved_index": FEATURE_COLUMNS.index("eating_context_mask0"),
        "targets": [
            {
                "name": t["name"],
                "title": t["title"],
                "unit": t["unit"],
                "weights": [float(v) for v in weights[idx]],
                "bias": float(biases[idx]),
                "clip_min": float(clip_mins[idx]),
                "clip_max": float(clip_maxs[idx]),
                "q80_half_width": float(q80_widths[idx]),
                "q90_half_width": float(q90_widths[idx]),
                "walk_forward_best_baseline": m4b_payload["targets"][t["name"]]["best_baseline_model"],
                "walk_forward_mae": float(m4b_payload["targets"][t["name"]]["models"]["Ridge"]["overall_mae"]),
                "walk_forward_cov80": float(m4b_payload["targets"][t["name"]]["models"]["Ridge"]["coverage_80"]),
            }
            for idx, t in enumerate(TARGETS)
        ],
    }

    spec_path = resources_dir / "personal_forecaster_v1_spec.json"
    spec_path.write_text(json.dumps(spec_payload, ensure_ascii=False, indent=2), encoding="utf-8")

    golden_dir = kit_dir / "Tests" / "BodySeekKitTests" / "Fixtures"
    golden_dir.mkdir(parents=True, exist_ok=True)
    golden_path = golden_dir / "personal_forecaster_v1_golden.json"
    golden_payload = {
        "model_version": MODEL_VERSION,
        "feature_columns": list(FEATURE_COLUMNS),
        "target_names": [t["name"] for t in TARGETS],
        "max_python_coreml_rel_err": max_rel_err,
        "vectors": golden_vectors,
    }
    golden_path.write_text(json.dumps(golden_payload, ensure_ascii=False, indent=2), encoding="utf-8")

    render_model_card(
        spec_payload=spec_payload,
        m4b_payload=m4b_payload,
        m4c_payload=m4c_payload,
        max_rel_err=max_rel_err,
        out_path=docs_dir / "model_cards" / "PERSONAL_FORECASTER_V1_MODEL_CARD.md",
    )

    return {
        "mlpackage_path": str(mlpackage_path),
        "spec_path": str(spec_path),
        "golden_path": str(golden_path),
        "max_python_coreml_rel_err": max_rel_err,
    }


def render_model_card(
    spec_payload: dict[str, Any],
    m4b_payload: dict[str, Any],
    m4c_payload: dict[str, Any],
    max_rel_err: float,
    out_path: Path,
) -> None:
    """Write PERSONAL_FORECASTER_V1_MODEL_CARD.md with exact verified metrics and boundaries."""
    lines: list[str] = [
        f"# Model Card: `{MODEL_VERSION}`（端侧个人多目标预测模型）",
        "",
        "## 1. 模型定位与架构",
        "",
        "- **Artifact**：`BodySeekPersonalForecasterV1.mlpackage`（CoreML `mlprogram`，Float32，Minimum Deployment Target: iOS 18+）",
        "- **共享特征合同**：[`personal_forecaster_v1_spec.json`](../../BodySeekKit/Sources/BodySeekCore/Resources/personal_forecaster_v1_spec.json)（31 维严格因果特征，包含观察掩码 `*_mask0`、Banister $\\tau_g=42/\\tau_h=7$ 状态特征、分开建模的主观/估算 Effort，以及预留 `eating_context_mask0` 进食节律位）。",
        "- **预测目标**：次日夜间 HRV (SDNN, ms)、次日静息心率 (RHR, bpm)、次日睡眠效率 (ratio) 点估计及 Split-Conformal 80%/90% 预测区间。",
        "- **结构选型依据**：依据 M4b + M4c 月度 Walk-Forward 配对检验（见 [`m4b-forecasting-backtest-2026-11-20.md`](../validation/m4b-forecasting-backtest-2026-11-20.md) 与 [`m4c-deep-model-comparison-2026-11-20.md`](../validation/m4c-deep-model-comparison-2026-11-20.md)），正则化低方差线性/状态空间模型在个人生理单序列上显著稳健且零过拟合，遂作为 v1 生产 CoreML 导出架构。",
        "",
        "## 2. 实测回测与区间校准（Walk-Forward 24 个月起训按月滚动）",
        "",
        "| 目标 | M4b Ridge MAE | M4b Best Baseline (MAE) | Split-Conformal 80% 区间覆盖率 | 导出的 80% 半宽 (`±`) |",
        "|---|---:|---|---:|---:|",
    ]

    for t in spec_payload["targets"]:
        t_name = t["name"]
        base_name = m4b_payload["targets"][t_name]["best_baseline_model"]
        base_mae = m4b_payload["targets"][t_name]["best_overall_mae"]
        deep_info = m4c_payload["targets"][t_name]["deep_models"]
        _ = deep_info
        lines.append(
            f"| `{t_name}` | `{t['walk_forward_mae']:.4f}` | `{base_name}` (`{base_mae:.4f}`) | "
            f"`{t['walk_forward_cov80'] * 100:.1f}%` | `±{t['q80_half_width']:.4f}` |"
        )

    lines.extend(
        [
            "",
            "## 3. 双端对拍与不变量",
            "",
            f"- Python NumPy 参考实现 vs 导出 `BodySeekPersonalForecasterV1.mlpackage`（24 组合成与边界特征向量）最大相对误差：`{max_rel_err:.2e}`（门禁上限 `<= 1e-3`）。",
            "- Swift `PersonalForecasterEngine` 与真实 `CoreML` 运行时通过 `Bundle.module` 对拍同一份 24 组 Golden Vectors。",
            "- **因果与医学免责边界**：本模型属于统计预测与个体状态辅助评估，**不构成医疗诊断**，亦不能作为因果干预证明（建议结合 `Trends` 页 N-of-1 自实验模板实测验证）。",
            "",
        ]
    )

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines), encoding="utf-8")
