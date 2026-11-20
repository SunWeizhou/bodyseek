"""M4b walk-forward physiological forecasting pipeline (Persistence, Banister State-Space, Ridge, LightGBM)."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import lightgbm as lgb
import numpy as np
import pandas as pd
from sklearn.linear_model import Ridge
from sklearn.preprocessing import StandardScaler

TARGETS: tuple[dict[str, Any], ...] = (
    {
        "name": "hrv_sdnn_ms",
        "title": "次日夜间 HRV (SDNN)",
        "unit": "ms",
        "lag0_col": "hrv_lag0",
        "roll7_col": "hrv_roll7_mean",
        "roll28_col": "hrv_roll28_mean",
        "mask_col": "hrv_mask0",
        "clip_min": 10.0,
        "clip_max": 180.0,
    },
    {
        "name": "resting_hr_bpm",
        "title": "次日静息心率 (RHR)",
        "unit": "bpm",
        "lag0_col": "rhr_lag0",
        "roll7_col": "rhr_roll7_mean",
        "roll28_col": "rhr_roll28_mean",
        "mask_col": "rhr_mask0",
        "clip_min": 38.0,
        "clip_max": 110.0,
    },
    {
        "name": "sleep_efficiency",
        "title": "次日睡眠效率",
        "unit": "ratio",
        "lag0_col": "sleep_eff_lag0",
        "roll7_col": "sleep_eff_roll7_mean",
        "roll28_col": "sleep_eff_roll28_mean",
        "mask_col": "sleep_mask0",
        "clip_min": 0.50,
        "clip_max": 1.00,
    },
)

FEATURE_COLUMNS: tuple[str, ...] = (
    "hrv_lag0",
    "hrv_lag1",
    "hrv_roll7_mean",
    "hrv_roll28_mean",
    "hrv_mask0",
    "rhr_lag0",
    "rhr_lag1",
    "rhr_roll7_mean",
    "rhr_roll28_mean",
    "rhr_mask0",
    "sleep_total_min_lag0",
    "sleep_eff_lag0",
    "sleep_eff_roll7_mean",
    "sleep_eff_roll28_mean",
    "sleep_deep_min_lag0",
    "sleep_rem_min_lag0",
    "sleep_mask0",
    "active_kcal_lag0",
    "workout_min_lag0",
    "strain_acute7",
    "strain_chronic28",
    "acwr_ratio",
    "banister_fitness_42d",
    "banister_fatigue_7d",
    "effort_user_lag0",
    "effort_user_mask0",
    "effort_estimated_lag0",
    "effort_estimated_mask0",
    "eating_context_mask0",
    "dow_sin",
    "dow_cos",
)


def _causal_expanding_fill(series: pd.Series, default_val: float) -> pd.Series:
    """Fill missing values using only past rolling/expanding medians (strictly causal, zero future leakage)."""
    roll28 = series.rolling(window=28, min_periods=1).median()
    exp_med = series.expanding(min_periods=1).median()
    filled = series.combine_first(roll28).combine_first(exp_med).ffill()
    return filled.fillna(default_val)


def build_supervised_dataset(df: pd.DataFrame) -> pd.DataFrame:
    """Construct strictly causal day-t feature rows paired with day-(t+1) targets."""
    work = df.sort_values("day_key").reset_index(drop=True).copy()
    dates = pd.to_datetime(work["day_key"], format="%Y-%m-%d")

    def num_series(col: str, default: float = np.nan) -> pd.Series:
        if col in work.columns:
            return pd.to_numeric(work[col], errors="coerce")
        return pd.Series(np.full(len(work), default, dtype=float), index=work.index)

    hrv_raw = num_series("hrv_sdnn_ms")
    rhr_raw = num_series("resting_hr_bpm")
    sleep_min_raw = num_series("sleep_total_min")
    sleep_eff_raw = num_series("sleep_efficiency")
    sleep_deep_raw = num_series("sleep_deep_min")
    sleep_rem_raw = num_series("sleep_rem_min")
    active_kcal_raw = num_series("active_energy_kcal")
    workout_min_raw = num_series("workout_duration_min", 0.0).fillna(0.0)
    effort_user_raw = num_series("effort_user_mean")
    effort_est_raw = num_series("effort_estimated_mean")

    out = pd.DataFrame({"day_key": work["day_key"], "month_key": work["day_key"].str.slice(0, 7)})

    # Binary observation masks (1.0 = observed, 0.0 = missing/excluded)
    out["hrv_mask0"] = hrv_raw.notna().astype(float)
    out["rhr_mask0"] = rhr_raw.notna().astype(float)
    out["sleep_mask0"] = sleep_eff_raw.notna().astype(float)
    out["effort_user_mask0"] = effort_user_raw.notna().astype(float)
    out["effort_estimated_mask0"] = effort_est_raw.notna().astype(float)
    if "eating_context_state" in work.columns:
        out["eating_context_mask0"] = (work["eating_context_state"] == "available").astype(float)
    else:
        out["eating_context_mask0"] = 0.0

    # Causal rolling means BEFORE imputation
    hrv_r7 = hrv_raw.rolling(7, min_periods=1).mean()
    hrv_r28 = hrv_raw.rolling(28, min_periods=1).mean()
    rhr_r7 = rhr_raw.rolling(7, min_periods=1).mean()
    rhr_r28 = rhr_raw.rolling(28, min_periods=1).mean()
    seff_r7 = sleep_eff_raw.rolling(7, min_periods=1).mean()
    seff_r28 = sleep_eff_raw.rolling(28, min_periods=1).mean()

    out["hrv_lag0"] = _causal_expanding_fill(hrv_raw, 43.0)
    out["hrv_lag1"] = out["hrv_lag0"].shift(1).fillna(out["hrv_lag0"])
    out["hrv_roll7_mean"] = _causal_expanding_fill(hrv_r7, 43.0)
    out["hrv_roll28_mean"] = _causal_expanding_fill(hrv_r28, 43.0)

    out["rhr_lag0"] = _causal_expanding_fill(rhr_raw, 58.0)
    out["rhr_lag1"] = out["rhr_lag0"].shift(1).fillna(out["rhr_lag0"])
    out["rhr_roll7_mean"] = _causal_expanding_fill(rhr_r7, 58.0)
    out["rhr_roll28_mean"] = _causal_expanding_fill(rhr_r28, 58.0)

    out["sleep_total_min_lag0"] = _causal_expanding_fill(sleep_min_raw, 420.0)
    out["sleep_eff_lag0"] = _causal_expanding_fill(sleep_eff_raw, 0.94)
    out["sleep_eff_roll7_mean"] = _causal_expanding_fill(seff_r7, 0.94)
    out["sleep_eff_roll28_mean"] = _causal_expanding_fill(seff_r28, 0.94)
    out["sleep_deep_min_lag0"] = _causal_expanding_fill(sleep_deep_raw, 65.0)
    out["sleep_rem_min_lag0"] = _causal_expanding_fill(sleep_rem_raw, 85.0)

    out["active_kcal_lag0"] = _causal_expanding_fill(active_kcal_raw, 450.0)
    out["workout_min_lag0"] = workout_min_raw

    # Daily load impulse & Banister state-space filters (tau_g=42d, tau_h=7d)
    daily_load = out["active_kcal_lag0"] / 100.0 + out["workout_min_lag0"] * 0.12
    out["strain_acute7"] = daily_load.rolling(7, min_periods=1).mean()
    out["strain_chronic28"] = daily_load.rolling(28, min_periods=1).mean().clip(lower=0.5)
    out["acwr_ratio"] = (out["strain_acute7"] / out["strain_chronic28"]).clip(0.3, 2.5)

    decay_g = float(np.exp(-1.0 / 42.0))
    decay_h = float(np.exp(-1.0 / 7.0))
    g_vals = np.zeros(len(out), dtype=float)
    h_vals = np.zeros(len(out), dtype=float)
    load_arr = daily_load.to_numpy(dtype=float)
    for i, w_val in enumerate(load_arr):
        if i == 0:
            g_vals[i] = w_val
            h_vals[i] = w_val
        else:
            g_vals[i] = decay_g * g_vals[i - 1] + (1.0 - decay_g) * w_val
            h_vals[i] = decay_h * h_vals[i - 1] + (1.0 - decay_h) * w_val
    out["banister_fitness_42d"] = g_vals
    out["banister_fatigue_7d"] = h_vals

    # Effort separation: User Effort vs Apple Estimated Effort per V5 §10
    out["effort_user_lag0"] = _causal_expanding_fill(effort_user_raw, 7.0)
    out["effort_estimated_lag0"] = _causal_expanding_fill(effort_est_raw, 6.5)

    dow = dates.dt.day_of_week.to_numpy(dtype=float)
    out["dow_sin"] = np.sin(2.0 * np.pi * dow / 7.0)
    out["dow_cos"] = np.cos(2.0 * np.pi * dow / 7.0)

    next_dates = dates.shift(-1)
    is_consecutive_next_day = (next_dates - dates).dt.days == 1

    for t_cfg in TARGETS:
        col = t_cfg["name"]
        raw_next = num_series(col).shift(-1)
        out[f"target_{col}"] = np.where(is_consecutive_next_day, raw_next, np.nan)

    return out


@dataclass(frozen=True)
class WalkForwardFold:
    fold_month: str
    train_indices: np.ndarray
    test_indices: np.ndarray


def generate_walk_forward_folds(
    sup_df: pd.DataFrame,
    target_col: str,
    initial_months: int = 24,
    min_train_samples: int = 90,
    min_test_samples: int = 5,
) -> list[WalkForwardFold]:
    """Generate monthly expanding walk-forward folds starting after initial_months of data."""
    all_months = sorted(sup_df["month_key"].unique())
    start_idx = min(initial_months, max(1, len(all_months) // 2))
    eval_months = all_months[start_idx:]

    valid_mask = sup_df[target_col].notna().to_numpy()
    month_arr = sup_df["month_key"].to_numpy()
    folds: list[WalkForwardFold] = []

    for m in eval_months:
        train_idx = np.flatnonzero((month_arr < m) & valid_mask)
        test_idx = np.flatnonzero((month_arr == m) & valid_mask)
        if len(train_idx) >= min_train_samples and len(test_idx) >= min_test_samples:
            folds.append(WalkForwardFold(fold_month=m, train_indices=train_idx, test_indices=test_idx))

    return folds


def _conformal_half_widths(abs_residuals: np.ndarray) -> tuple[float, float]:
    if len(abs_residuals) == 0:
        return 1.0, 1.5
    q80 = float(np.quantile(abs_residuals, 0.80))
    q90 = float(np.quantile(abs_residuals, 0.90))
    return max(1e-4, q80), max(1e-4, q90)


def _predict_persistence(
    sup_df: pd.DataFrame,
    t_cfg: dict[str, Any],
    train_idx: np.ndarray,
    test_idx: np.ndarray,
) -> tuple[np.ndarray, float, float]:
    target_col = f"target_{t_cfg['name']}"
    lag0_col = t_cfg["lag0_col"]
    roll7_col = t_cfg["roll7_col"]
    mask_col = t_cfg["mask_col"]

    def pred_for(indices: np.ndarray) -> np.ndarray:
        sub = sup_df.iloc[indices]
        raw_pred = np.where(sub[mask_col].to_numpy() > 0.5, sub[lag0_col].to_numpy(), sub[roll7_col].to_numpy())
        return np.clip(raw_pred, t_cfg["clip_min"], t_cfg["clip_max"])

    train_preds = pred_for(train_idx)
    train_y = sup_df.iloc[train_idx][target_col].to_numpy(dtype=float)
    q80, q90 = _conformal_half_widths(np.abs(train_y - train_preds))
    return pred_for(test_idx), q80, q90


def _predict_banister(
    sup_df: pd.DataFrame,
    t_cfg: dict[str, Any],
    train_idx: np.ndarray,
    test_idx: np.ndarray,
) -> tuple[np.ndarray, float, float]:
    target_col = f"target_{t_cfg['name']}"
    banister_cols = [
        t_cfg["lag0_col"],
        t_cfg["roll7_col"],
        t_cfg["roll28_col"],
        t_cfg["mask_col"],
        "banister_fitness_42d",
        "banister_fatigue_7d",
        "sleep_total_min_lag0",
        "sleep_eff_lag0",
    ]
    X_all = sup_df[banister_cols].to_numpy(dtype=float)
    y_all = sup_df[target_col].to_numpy(dtype=float)

    n_train = len(train_idx)
    cal_size = max(20, int(0.20 * n_train))
    fit_idx = train_idx[:-cal_size]
    cal_idx = train_idx[-cal_size:]

    scaler = StandardScaler()
    model = Ridge(alpha=15.0)
    model.fit(scaler.fit_transform(X_all[fit_idx]), y_all[fit_idx])
    cal_preds = np.clip(model.predict(scaler.transform(X_all[cal_idx])), t_cfg["clip_min"], t_cfg["clip_max"])
    q80, q90 = _conformal_half_widths(np.abs(y_all[cal_idx] - cal_preds))

    model.fit(scaler.fit_transform(X_all[train_idx]), y_all[train_idx])
    test_preds = np.clip(model.predict(scaler.transform(X_all[test_idx])), t_cfg["clip_min"], t_cfg["clip_max"])
    return test_preds, q80, q90


def _predict_ridge(
    sup_df: pd.DataFrame,
    t_cfg: dict[str, Any],
    train_idx: np.ndarray,
    test_idx: np.ndarray,
) -> tuple[np.ndarray, float, float]:
    target_col = f"target_{t_cfg['name']}"
    X_all = sup_df[list(FEATURE_COLUMNS)].to_numpy(dtype=float)
    y_all = sup_df[target_col].to_numpy(dtype=float)

    n_train = len(train_idx)
    cal_size = max(20, int(0.20 * n_train))
    fit_idx = train_idx[:-cal_size]
    cal_idx = train_idx[-cal_size:]

    scaler = StandardScaler()
    model = Ridge(alpha=35.0)
    model.fit(scaler.fit_transform(X_all[fit_idx]), y_all[fit_idx])
    cal_preds = np.clip(model.predict(scaler.transform(X_all[cal_idx])), t_cfg["clip_min"], t_cfg["clip_max"])
    q80, q90 = _conformal_half_widths(np.abs(y_all[cal_idx] - cal_preds))

    model.fit(scaler.fit_transform(X_all[train_idx]), y_all[train_idx])
    test_preds = np.clip(model.predict(scaler.transform(X_all[test_idx])), t_cfg["clip_min"], t_cfg["clip_max"])
    return test_preds, q80, q90


def _predict_lightgbm(
    sup_df: pd.DataFrame,
    t_cfg: dict[str, Any],
    train_idx: np.ndarray,
    test_idx: np.ndarray,
) -> tuple[np.ndarray, float, float]:
    target_col = f"target_{t_cfg['name']}"
    X_all = sup_df[list(FEATURE_COLUMNS)].to_numpy(dtype=float)
    y_all = sup_df[target_col].to_numpy(dtype=float)

    n_train = len(train_idx)
    cal_size = max(20, int(0.20 * n_train))
    fit_idx = train_idx[:-cal_size]
    cal_idx = train_idx[-cal_size:]

    params = {
        "n_estimators": 55,
        "max_depth": 3,
        "num_leaves": 7,
        "learning_rate": 0.05,
        "min_child_samples": 18,
        "subsample": 0.8,
        "colsample_bytree": 0.8,
        "reg_alpha": 1.0,
        "reg_lambda": 5.0,
        "random_state": 42,
        "verbose": -1,
        "n_jobs": 1,
    }
    cal_model = lgb.LGBMRegressor(**params)
    cal_model.fit(X_all[fit_idx], y_all[fit_idx])
    cal_preds = np.clip(cal_model.predict(X_all[cal_idx]), t_cfg["clip_min"], t_cfg["clip_max"])
    q80, q90 = _conformal_half_widths(np.abs(y_all[cal_idx] - cal_preds))

    full_model = lgb.LGBMRegressor(**params)
    full_model.fit(X_all[train_idx], y_all[train_idx])
    test_preds = np.clip(full_model.predict(X_all[test_idx]), t_cfg["clip_min"], t_cfg["clip_max"])
    return test_preds, q80, q90


def run_m4b_walk_forward(df: pd.DataFrame, initial_months: int = 24) -> dict[str, Any]:
    """Run M4b walk-forward evaluation across Persistence, Banister, Ridge, and LightGBM."""
    sup_df = build_supervised_dataset(df)
    model_runners = {
        "Persistence": _predict_persistence,
        "Banister": _predict_banister,
        "Ridge": _predict_ridge,
        "LightGBM": _predict_lightgbm,
    }

    results_by_target: dict[str, Any] = {}

    for t_cfg in TARGETS:
        t_name = t_cfg["name"]
        target_col = f"target_{t_name}"
        folds = generate_walk_forward_folds(sup_df, target_col=target_col, initial_months=initial_months)

        model_fold_metrics: dict[str, list[dict[str, Any]]] = {m: [] for m in model_runners}
        model_all_errors: dict[str, list[float]] = {m: [] for m in model_runners}
        model_all_sq_errors: dict[str, list[float]] = {m: [] for m in model_runners}
        model_cov80: dict[str, list[bool]] = {m: [] for m in model_runners}
        model_cov90: dict[str, list[bool]] = {m: [] for m in model_runners}

        for fold in folds:
            y_true = sup_df.iloc[fold.test_indices][target_col].to_numpy(dtype=float)
            for m_name, runner in model_runners.items():
                preds, q80, q90 = runner(sup_df, t_cfg, fold.train_indices, fold.test_indices)
                abs_err = np.abs(y_true - preds)
                sq_err = (y_true - preds) ** 2
                in_80 = abs_err <= q80
                in_90 = abs_err <= q90

                model_fold_metrics[m_name].append(
                    {
                        "fold_month": fold.fold_month,
                        "n_train": int(len(fold.train_indices)),
                        "n_test": int(len(fold.test_indices)),
                        "mae": float(np.mean(abs_err)),
                        "rmse": float(np.sqrt(np.mean(sq_err))),
                        "cov80": float(np.mean(in_80)),
                        "cov90": float(np.mean(in_90)),
                    }
                )
                model_all_errors[m_name].extend(abs_err.tolist())
                model_all_sq_errors[m_name].extend(sq_err.tolist())
                model_cov80[m_name].extend(in_80.tolist())
                model_cov90[m_name].extend(in_90.tolist())

        summaries: dict[str, Any] = {}
        for m_name in model_runners:
            errs = np.array(model_all_errors[m_name], dtype=float)
            sq_errs = np.array(model_all_sq_errors[m_name], dtype=float)
            c80 = np.array(model_cov80[m_name], dtype=float)
            c90 = np.array(model_cov90[m_name], dtype=float)
            fold_maes = [f["mae"] for f in model_fold_metrics[m_name]]
            summaries[m_name] = {
                "overall_mae": float(np.mean(errs)) if len(errs) else float("nan"),
                "overall_rmse": float(np.sqrt(np.mean(sq_errs))) if len(sq_errs) else float("nan"),
                "fold_mean_mae": float(np.mean(fold_maes)) if fold_maes else float("nan"),
                "fold_std_mae": float(np.std(fold_maes)) if fold_maes else float("nan"),
                "coverage_80": float(np.mean(c80)) if len(c80) else float("nan"),
                "coverage_90": float(np.mean(c90)) if len(c90) else float("nan"),
                "total_eval_days": int(len(errs)),
                "fold_count": int(len(fold_maes)),
                "folds": model_fold_metrics[m_name],
            }

        best_model = min(summaries.keys(), key=lambda k: summaries[k]["overall_mae"])
        results_by_target[t_name] = {
            "title": t_cfg["title"],
            "unit": t_cfg["unit"],
            "best_baseline_model": best_model,
            "best_overall_mae": summaries[best_model]["overall_mae"],
            "models": summaries,
        }

    return {
        "schema_version": "m4b-walk-forward-v1",
        "feature_columns": list(FEATURE_COLUMNS),
        "targets": results_by_target,
    }


def render_m4b_report(m4b_payload: dict[str, Any], report_path: Path) -> None:
    """Write anonymized M4b walk-forward forecasting backtest report."""
    lines: list[str] = [
        "# BodySeek M4b 次日生理指标 Walk-Forward 回测报告（2026-11-20）",
        "",
        "- 验证协议：前 24 个月起训，按月滚动扩展窗口（Walk-Forward Validation），严格零未来数据泄露。",
        "- 缺失值原则：缺失/排除特征绝不当 0，采用历史因果中位数填充 + 显式二值观测掩码（`*_mask0`），并为饮食节律预留 `eating_context_mask0` 通道；主观 `effort_user_lag0` 与系统估算 `effort_estimated_lag0` 分离建模。",
        "- 对比模型：`Persistence`（最近观测延续）、`Banister`（42d 体能 / 7d 疲劳脉冲状态空间）、`Ridge`（带掩码 L2 线性回归）、`LightGBM`（梯度提升树）+ Split-Conformal 区间估计。",
        "",
        "## 1. 各目标汇总指标（Overall MAE / RMSE / 区间覆盖率）",
        "",
    ]

    for t_name, t_info in m4b_payload["targets"].items():
        lines.append(f"### 目标：`{t_name}`（{t_info['title']}，单位：`{t_info['unit']}`）")
        lines.append("")
        lines.append(f"- **最优基线模型**：`{t_info['best_baseline_model']}`（Overall MAE = `{t_info['best_overall_mae']:.4f}`）")
        lines.append("")
        lines.append("| 模型 | 评估折数 | 评估总天数 | Overall MAE | Fold Mean MAE (±SD) | Overall RMSE | 80% 区间覆盖率 | 90% 区间覆盖率 |")
        lines.append("|---|---:|---:|---:|---:|---:|---:|---:|")
        for m_name, m_stat in t_info["models"].items():
            marker = " **(Best)**" if m_name == t_info["best_baseline_model"] else ""
            lines.append(
                f"| `{m_name}`{marker} | {m_stat['fold_count']} | {m_stat['total_eval_days']} | "
                f"`{m_stat['overall_mae']:.4f}` | `{m_stat['fold_mean_mae']:.4f} ± {m_stat['fold_std_mae']:.4f}` | "
                f"`{m_stat['overall_rmse']:.4f}` | `{m_stat['coverage_80'] * 100:.1f}%` | `{m_stat['coverage_90'] * 100:.1f}%` |"
            )
        lines.append("")

    lines.extend(
        [
            "## 2. 结论与上线准入",
            "",
            "- 以上最优基线（按真实月度滚动 Overall MAE 客观评定）将作为 M4c 深度时序研究线（`MaskedTCN` / `PatchTSTLite`）的折间配对显著性检验对比门槛。",
            "- 本模型仅输出次日个人统计预测区间与波动校准参考，不作医学诊断或因果结论。",
            "",
        ]
    )

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text("\n".join(lines), encoding="utf-8")
