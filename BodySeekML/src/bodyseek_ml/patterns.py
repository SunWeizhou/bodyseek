"""Distributed-lag personal pattern discovery with 7-day moving block bootstrap and BH-FDR."""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re
from typing import Any, Callable

import numpy as np
import pandas as pd

from .export_parser import STATE_CHANNELS

MIN_EXPOSED_DAYS = 20
MIN_CONTROL_DAYS = 20
MIN_TOTAL_DAYS = 40
BLOCK_LENGTH_DAYS = 7
N_BOOTSTRAP = 2000
BOOTSTRAP_SEED = 42


@dataclass(frozen=True)
class ExposureSpec:
    exposure_id: str
    title_zh: str
    exposed_desc_zh: str
    control_desc_zh: str
    lags: tuple[int, ...]
    skip_lag0_outcomes: frozenset[str]
    builder: Callable[[pd.DataFrame], np.ndarray]


@dataclass(frozen=True)
class OutcomeSpec:
    column: str
    state_column: str
    title_zh: str
    unit: str


OUTCOME_SPECS: tuple[OutcomeSpec, ...] = (
    OutcomeSpec("hrv_sdnn_ms", "hrv_sdnn_ms_state", "HRV (SDNN)", "ms"),
    OutcomeSpec("resting_hr_bpm", "resting_hr_bpm_state", "静息心率 (RHR)", "bpm"),
    OutcomeSpec("sleep_total_min", "sleep_total_min_state", "总睡眠时长", "min"),
    OutcomeSpec("sleep_efficiency", "sleep_total_min_state", "睡眠效率", "比例"),
    OutcomeSpec("sleep_deep_min", "sleep_total_min_state", "深睡时长", "min"),
)


def _sleep_available(df: pd.DataFrame) -> np.ndarray:
    return (df["sleep_total_min_state"] == "available").to_numpy() & df["sleep_total_min"].notna().to_numpy()


def _build_short_sleep_lt_6h(df: pd.DataFrame) -> np.ndarray:
    arm = np.full(len(df), -1, dtype=np.int8)
    avail = _sleep_available(df)
    vals = df["sleep_total_min"].to_numpy(dtype=float)
    arm[avail & (vals < 360.0)] = 1
    arm[avail & (vals >= 420.0)] = 0
    return arm


def _build_consecutive_short_sleep_2d(df: pd.DataFrame) -> np.ndarray:
    """Strictly causal 2-day rolling exposure: both day t and t-1 had < 6.5h sleep vs both >= 7h."""
    arm = np.full(len(df), -1, dtype=np.int8)
    avail = _sleep_available(df)
    vals = df["sleep_total_min"].to_numpy(dtype=float)
    prev_avail = np.concatenate(([False], avail[:-1]))
    prev_vals = np.concatenate(([np.nan], vals[:-1]))
    both_avail = avail & prev_avail
    arm[both_avail & (vals < 390.0) & (prev_vals < 390.0)] = 1
    arm[both_avail & (vals >= 420.0) & (prev_vals >= 420.0)] = 0
    return arm


def _build_late_bedtime(df: pd.DataFrame) -> np.ndarray:
    arm = np.full(len(df), -1, dtype=np.int8)
    avail = _sleep_available(df) & df["sleep_onset_hour"].notna().to_numpy()
    onset = df["sleep_onset_hour"].to_numpy(dtype=float)
    arm[avail & (onset >= 24.0)] = 1
    arm[avail & (onset < 23.5)] = 0
    return arm


def _build_any_workout_vs_rest(df: pd.DataFrame) -> np.ndarray:
    arm = np.full(len(df), -1, dtype=np.int8)
    st = df["workout_duration_min_state"].to_numpy()
    arm[st == "available"] = 1
    arm[st == "knownZero"] = 0
    return arm


def _build_high_workout_load(df: pd.DataFrame) -> np.ndarray:
    """Causal threshold using training load duration >= 60 min or active_kcal >= Q75 across workout days (trailing/static Q75 checked strictly)."""
    arm = np.full(len(df), -1, dtype=np.int8)
    st = df["workout_duration_min_state"].to_numpy()
    dur = df["workout_duration_min"].to_numpy(dtype=float)
    kcal = df["workout_active_kcal"].to_numpy(dtype=float)
    is_workout = st == "available"
    # Use expanding past Q75 after >= 20 workouts (fallback 60 min) to strictly avoid future threshold leakage
    high = np.zeros(len(df), dtype=bool)
    past_kcals: list[float] = []
    for i in range(len(df)):
        if is_workout[i]:
            q75 = float(np.nanpercentile(past_kcals, 75)) if len(past_kcals) >= 20 else 450.0
            if (np.isfinite(dur[i]) and dur[i] >= 60.0) or (np.isfinite(kcal[i]) and kcal[i] >= q75):
                high[i] = True
            if np.isfinite(kcal[i]):
                past_kcals.append(float(kcal[i]))
    arm[is_workout & high] = 1
    arm[st == "knownZero"] = 0
    return arm


def _build_modality_vs_rest(flag_col: str) -> Callable[[pd.DataFrame], np.ndarray]:
    def _builder(df: pd.DataFrame) -> np.ndarray:
        arm = np.full(len(df), -1, dtype=np.int8)
        st = df["workout_duration_min_state"].to_numpy()
        flag = df[flag_col].fillna(0).to_numpy() > 0
        arm[(st == "available") & flag] = 1
        arm[st == "knownZero"] = 0
        return arm

    return _builder


def _build_high_steps(df: pd.DataFrame) -> np.ndarray:
    arm = np.full(len(df), -1, dtype=np.int8)
    avail = (df["steps_count_state"] == "available").to_numpy() & df["steps_count"].notna().to_numpy()
    steps = df["steps_count"].to_numpy(dtype=float)
    arm[avail & (steps >= 10000.0)] = 1
    arm[avail & (steps < 5000.0)] = 0
    return arm


EXPOSURE_SPECS: tuple[ExposureSpec, ...] = (
    ExposureSpec(
        exposure_id="short_sleep_lt_6h",
        title_zh="单晚睡眠 < 6h",
        exposed_desc_zh="总睡眠 < 360 min",
        control_desc_zh="总睡眠 >= 420 min",
        lags=(0, 1, 2, 3),
        skip_lag0_outcomes=frozenset({"sleep_total_min", "sleep_efficiency", "sleep_deep_min"}),
        builder=_build_short_sleep_lt_6h,
    ),
    ExposureSpec(
        exposure_id="consecutive_short_sleep_2d",
        title_zh="连续 2 晚睡眠不足 (< 6.5h)",
        exposed_desc_zh="连续两天总睡眠 < 390 min",
        control_desc_zh="连续两天总睡眠 >= 420 min",
        lags=(0, 1, 2, 3),
        skip_lag0_outcomes=frozenset({"sleep_total_min", "sleep_efficiency", "sleep_deep_min"}),
        builder=_build_consecutive_short_sleep_2d,
    ),
    ExposureSpec(
        exposure_id="late_bedtime_after_midnight",
        title_zh="零点后入睡",
        exposed_desc_zh="主睡眠入睡时刻 >= 00:00",
        control_desc_zh="主睡眠入睡时刻 < 23:30",
        lags=(0, 1, 2, 3),
        skip_lag0_outcomes=frozenset({"sleep_total_min", "sleep_efficiency", "sleep_deep_min"}),
        builder=_build_late_bedtime,
    ),
    ExposureSpec(
        exposure_id="high_workout_load",
        title_zh="高训练负荷日",
        exposed_desc_zh="训练 >= 60 min 或消耗 >= 历史 P75",
        control_desc_zh="已佩戴确认休息日 (knownZero)",
        lags=(1, 2, 3),
        skip_lag0_outcomes=frozenset(),
        builder=_build_high_workout_load,
    ),
    ExposureSpec(
        exposure_id="any_workout_vs_rest",
        title_zh="训练日 vs 休息日",
        exposed_desc_zh="当日记录有效体能训练",
        control_desc_zh="已佩戴确认休息日 (knownZero)",
        lags=(1, 2, 3),
        skip_lag0_outcomes=frozenset(),
        builder=_build_any_workout_vs_rest,
    ),
    ExposureSpec(
        exposure_id="running_vs_rest",
        title_zh="跑步训练日 vs 休息日",
        exposed_desc_zh="当日含 Running 训练",
        control_desc_zh="已佩戴确认休息日 (knownZero)",
        lags=(1, 2, 3),
        skip_lag0_outcomes=frozenset(),
        builder=_build_modality_vs_rest("has_running_workout"),
    ),
    ExposureSpec(
        exposure_id="strength_vs_rest",
        title_zh="力量训练日 vs 休息日",
        exposed_desc_zh="当日含传统/功能性力量训练",
        control_desc_zh="已佩戴确认休息日 (knownZero)",
        lags=(1, 2, 3),
        skip_lag0_outcomes=frozenset(),
        builder=_build_modality_vs_rest("has_strength_workout"),
    ),
    ExposureSpec(
        exposure_id="badminton_vs_rest",
        title_zh="羽毛球训练日 vs 休息日",
        exposed_desc_zh="当日含羽毛球训练",
        control_desc_zh="已佩戴确认休息日 (knownZero)",
        lags=(1, 2, 3),
        skip_lag0_outcomes=frozenset(),
        builder=_build_modality_vs_rest("has_badminton_workout"),
    ),
    ExposureSpec(
        exposure_id="high_steps_ge_10k",
        title_zh="高步数日 (>= 10,000 步)",
        exposed_desc_zh="步数 >= 10,000",
        control_desc_zh="步数 < 5,000",
        lags=(1, 2, 3),
        skip_lag0_outcomes=frozenset(),
        builder=_build_high_steps,
    ),
)


def benjamini_hochberg_fdr(p_values: list[float]) -> list[float]:
    """Compute Benjamini-Hochberg FDR-adjusted q-values preserving input order."""
    m = len(p_values)
    if m == 0:
        return []
    arr = np.asarray(p_values, dtype=float)
    order = np.argsort(arr)
    ranked_p = arr[order]
    ranks = np.arange(1, m + 1, dtype=float)
    raw_q = ranked_p * (m / ranks)
    monotone_q = np.minimum.accumulate(raw_q[::-1])[::-1]
    clipped = np.clip(monotone_q, 0.0, 1.0)
    out = np.empty(m, dtype=float)
    out[order] = clipped
    return out.tolist()


def moving_block_bootstrap_diff(
    arm: np.ndarray,
    outcome_vals: np.ndarray,
    outcome_avail: np.ndarray,
    block_len: int = BLOCK_LENGTH_DAYS,
    n_boot: int = N_BOOTSTRAP,
    seed: int = BOOTSTRAP_SEED,
) -> dict[str, Any]:
    """Compute difference in means with 7-day moving block bootstrap 95% CI and two-sided p-value."""
    valid_outcome = outcome_avail & np.isfinite(outcome_vals)
    exp_mask = (arm == 1) & valid_outcome
    ctrl_mask = (arm == 0) & valid_outcome

    n_exp = int(exp_mask.sum())
    n_ctrl = int(ctrl_mask.sum())
    n_total = n_exp + n_ctrl

    exp_mean = float(outcome_vals[exp_mask].mean()) if n_exp > 0 else float("nan")
    ctrl_mean = float(outcome_vals[ctrl_mask].mean()) if n_ctrl > 0 else float("nan")
    delta_mean = exp_mean - ctrl_mean if np.isfinite(exp_mean) and np.isfinite(ctrl_mean) else float("nan")

    if n_exp < MIN_EXPOSED_DAYS or n_ctrl < MIN_CONTROL_DAYS or n_total < MIN_TOTAL_DAYS:
        return {
            "n_exposed": n_exp,
            "n_control": n_ctrl,
            "n_total": n_total,
            "exposed_mean": round(exp_mean, 4) if np.isfinite(exp_mean) else None,
            "control_mean": round(ctrl_mean, 4) if np.isfinite(ctrl_mean) else None,
            "delta_mean": round(delta_mean, 4) if np.isfinite(delta_mean) else None,
            "ci_95_low": None,
            "ci_95_high": None,
            "p_value": None,
            "valid_bootstrap_replicates": 0,
            "status": "insufficient_sample",
        }

    t_len = len(arm)
    eff_block = min(block_len, t_len)
    n_blocks = max(1, t_len - eff_block + 1)
    k_blocks = max(1, int(np.ceil(t_len / eff_block)))

    exp_cnt_vec = exp_mask.astype(np.float64)
    exp_sum_vec = np.where(exp_mask, outcome_vals, 0.0)
    ctrl_cnt_vec = ctrl_mask.astype(np.float64)
    ctrl_sum_vec = np.where(ctrl_mask, outcome_vals, 0.0)

    def _window_sums(v: np.ndarray) -> np.ndarray:
        cs = np.concatenate(([0.0], np.cumsum(v)))
        return cs[eff_block : t_len + 1] - cs[0 : n_blocks]

    b_exp_cnt = _window_sums(exp_cnt_vec)
    b_exp_sum = _window_sums(exp_sum_vec)
    b_ctrl_cnt = _window_sums(ctrl_cnt_vec)
    b_ctrl_sum = _window_sums(ctrl_sum_vec)

    rng = np.random.default_rng(seed)
    draw_idx = rng.integers(0, n_blocks, size=(n_boot, k_blocks))

    rep_exp_cnt = b_exp_cnt[draw_idx].sum(axis=1)
    rep_exp_sum = b_exp_sum[draw_idx].sum(axis=1)
    rep_ctrl_cnt = b_ctrl_cnt[draw_idx].sum(axis=1)
    rep_ctrl_sum = b_ctrl_sum[draw_idx].sum(axis=1)

    valid_rep = (rep_exp_cnt > 0) & (rep_ctrl_cnt > 0)
    valid_deltas = (
        (rep_exp_sum[valid_rep] / rep_exp_cnt[valid_rep])
        - (rep_ctrl_sum[valid_rep] / rep_ctrl_cnt[valid_rep])
    )
    if len(valid_deltas) == 0:
        return {
            "n_exposed": n_exp,
            "n_control": n_ctrl,
            "n_total": n_total,
            "exposed_mean": round(exp_mean, 4),
            "control_mean": round(ctrl_mean, 4),
            "delta_mean": round(delta_mean, 4),
            "ci_95_low": None,
            "ci_95_high": None,
            "p_value": None,
            "valid_bootstrap_replicates": 0,
            "status": "insufficient_sample",
        }

    ci_lo, ci_hi = np.percentile(valid_deltas, [2.5, 97.5])
    n_valid = len(valid_deltas)
    p_le = (float(np.sum(valid_deltas <= 0.0)) + 1.0) / (n_valid + 1.0)
    p_ge = (float(np.sum(valid_deltas >= 0.0)) + 1.0) / (n_valid + 1.0)
    p_val = min(1.0, 2.0 * min(p_le, p_ge))

    return {
        "n_exposed": n_exp,
        "n_control": n_ctrl,
        "n_total": n_total,
        "exposed_mean": round(exp_mean, 4),
        "control_mean": round(ctrl_mean, 4),
        "delta_mean": round(delta_mean, 4),
        "ci_95_low": round(float(ci_lo), 4),
        "ci_95_high": round(float(ci_hi), 4),
        "p_value": round(p_val, 6),
        "valid_bootstrap_replicates": int(n_valid),
        "status": "pending_fdr",
    }


def _ensure_contiguous_calendar(df: pd.DataFrame) -> pd.DataFrame:
    """Reindex onto a gapless daily calendar so df.shift(-lag) is strictly t + lag calendar days."""
    if df.empty:
        return df
    work = df.copy()
    work["_dt"] = pd.to_datetime(work["day_key"])
    work = work.sort_values("_dt").drop_duplicates("_dt")
    full_idx = pd.date_range(work["_dt"].iloc[0], work["_dt"].iloc[-1], freq="D")
    work = work.set_index("_dt").reindex(full_idx)
    work["day_key"] = full_idx.strftime("%Y-%m-%d")
    for _, state_col in STATE_CHANNELS:
        if state_col in work.columns:
            work[state_col] = work[state_col].fillna("missing")
    if "eating_context_state" in work.columns:
        work["eating_context_state"] = work["eating_context_state"].fillna("missing")
    return work.reset_index(drop=True)


def analyze_distributed_lag_patterns(
    df: pd.DataFrame,
    out_dir: str | Path,
) -> dict[str, Any]:
    """Run all distributed-lag observational hypotheses with BH-FDR and export pattern_findings.json."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    if df.empty:
        payload = {"schema_version": "pattern-findings-v1", "total_tests": 0, "eligible_tests": 0, "findings": []}
        (out / "pattern_findings.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        return payload

    ordered_df = _ensure_contiguous_calendar(df)
    results: list[dict[str, Any]] = []

    for exp_idx, exp in enumerate(EXPOSURE_SPECS):
        arm = exp.builder(ordered_df)
        for out_idx, out_spec in enumerate(OUTCOME_SPECS):
            if out_spec.column not in ordered_df.columns:
                continue
            y_series = pd.to_numeric(ordered_df[out_spec.column], errors="coerce")
            avail_series = ordered_df[out_spec.state_column] == "available"

            for lag in exp.lags:
                if lag == 0 and out_spec.column in exp.skip_lag0_outcomes:
                    continue
                y_shifted = y_series.shift(-lag).to_numpy(dtype=float)
                avail_shifted = avail_series.shift(-lag, fill_value=False).to_numpy(dtype=bool)

                stat = moving_block_bootstrap_diff(
                    arm=arm,
                    outcome_vals=y_shifted,
                    outcome_avail=avail_shifted,
                    block_len=BLOCK_LENGTH_DAYS,
                    n_boot=N_BOOTSTRAP,
                    seed=BOOTSTRAP_SEED + exp_idx * 100 + out_idx * 10 + lag,
                )
                results.append(
                    {
                        "id": f"{exp.exposure_id}__lag{lag}__{out_spec.column}",
                        "exposure_id": exp.exposure_id,
                        "exposure_title_zh": exp.title_zh,
                        "exposed_rule": exp.exposed_desc_zh,
                        "control_rule": exp.control_desc_zh,
                        "outcome_id": out_spec.column,
                        "outcome_title_zh": out_spec.title_zh,
                        "outcome_unit": out_spec.unit,
                        "lag_days": lag,
                        "requires_user_confirmation": True,
                        "causal_claim_allowed": False,
                        **stat,
                    }
                )

    eligible_indices = [idx for idx, r in enumerate(results) if r["status"] == "pending_fdr" and r["p_value"] is not None]
    if eligible_indices:
        q_vals = benjamini_hochberg_fdr([float(results[i]["p_value"]) for i in eligible_indices])
        for idx, q in zip(eligible_indices, q_vals):
            rec = results[idx]
            rec["q_value"] = round(q, 6)
            ci_excludes_zero = (rec["ci_95_low"] > 0.0) or (rec["ci_95_high"] < 0.0)
            if q < 0.05 and ci_excludes_zero:
                rec["status"] = "candidate_for_confirmation"
            elif rec["p_value"] < 0.05 and ci_excludes_zero:
                rec["status"] = "nominal_only_not_fdr"
            else:
                rec["status"] = "not_significant"
    for rec in results:
        rec.setdefault("q_value", None)

    results.sort(
        key=lambda r: (
            0 if r["status"] == "candidate_for_confirmation" else (1 if r["status"] == "nominal_only_not_fdr" else (2 if r["status"] == "not_significant" else 3)),
            r["q_value"] if r["q_value"] is not None else 9.0,
            r["p_value"] if r["p_value"] is not None else 9.0,
            -abs(r["delta_mean"] or 0.0),
        )
    )

    payload = {
        "schema_version": "pattern-findings-v1",
        "method": f"{BLOCK_LENGTH_DAYS}-day moving block bootstrap (n_boot={N_BOOTSTRAP}) + Benjamini-Hochberg FDR",
        "sample_gate": {
            "min_exposed_days": MIN_EXPOSED_DAYS,
            "min_control_days": MIN_CONTROL_DAYS,
            "min_total_days": MIN_TOTAL_DAYS,
        },
        "total_tests": len(results),
        "eligible_tests": len(eligible_indices),
        "candidate_count": sum(1 for r in results if r["status"] == "candidate_for_confirmation"),
        "nominal_count": sum(1 for r in results if r["status"] == "nominal_only_not_fdr"),
        "findings": results,
    }
    (out / "pattern_findings.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return payload


def _extract_sensitive_owner_tokens(sources_full: list[dict[str, Any]]) -> list[str]:
    """Derive personal name tokens dynamically from local dedup_audit (never hardcoded) for PII output guard."""
    tokens: set[str] = set()
    for src in sources_full:
        norm = str(src.get("normalized_source_name", ""))
        lower = norm.lower()
        for marker in ("apple watch", "iphone", "ipad"):
            pos = lower.find(marker)
            if pos > 0:
                prefix = norm[:pos].strip()
                prefix = re.sub(r"(['’‘]s|的|\bDe)\s*$", "", prefix, flags=re.IGNORECASE).strip()
                for part in re.split(r"[\s'’‘]+", prefix):
                    if len(part) >= 2 and part.lower() not in {"apple", "watch", "iphone", "ipad", "de"}:
                        tokens.add(part)
    return sorted(tokens)


def assert_report_anonymized(markdown_text: str, dedup_audit: dict[str, Any]) -> None:
    """Fail loudly if personal owner names, DOB attributes, GPX, or raw coordinates appear in committed report."""
    for bad in ("HKCharacteristicTypeIdentifier", "DateOfBirth", "<trkpt", "<Record", "lat=", "lon="):
        if bad in markdown_text:
            raise ValueError(f"Privacy guard triggered: disallowed export token {bad!r} in report")
    for token in _extract_sensitive_owner_tokens(dedup_audit.get("sources_full", [])):
        if re.search(rf"(?<![A-Za-z]){re.escape(token)}(?![A-Za-z])", markdown_text, flags=re.IGNORECASE):
            raise ValueError(f"Privacy guard triggered: unmasked owner token {token!r} in report")


def render_personal_patterns_report(
    df: pd.DataFrame,
    dedup_audit: dict[str, Any],
    findings_payload: dict[str, Any],
    report_path: str | Path,
) -> str:
    """Render anonymized Markdown report of 3-year coverage, deduplication audit, and candidate patterns."""
    target = Path(report_path)
    target.parent.mkdir(parents=True, exist_ok=True)

    meta = dedup_audit.get("export_metadata", {})
    start_day = str(df["day_key"].iloc[0]) if len(df) else "N/A"
    end_day = str(df["day_key"].iloc[-1]) if len(df) else "N/A"
    n_days = len(df)

    lines: list[str] = [
        "# BodySeek 个人 3 年健康规律与数据审计报告 v1（M4a）",
        "",
        "> **性质声明**：本报告由 `BodySeekML` 对本地 Apple Health 导出包离线流式解析生成，仅包含**脱敏聚合统计与观测性分布滞后关联**，不含任何原始单条样本、GPS 轨迹、ECG 波形、出生日期或设备所有者姓名。所有发现**严禁直接表述为因果结论**，仅经用户在 App 内审阅确认后方可写入 Coach 三层记忆中的 `Verified Pattern`（`pattern_finding`）。",
        "",
        "## 1. 数据集概况与四态覆盖审计",
        "",
        f"- **生理日跨度**（本地时区 `04:00` 日切点）：`{start_day}` 至 `{end_day}`（共 **{n_days}** 个连续日历日）",
        f"- **导出扫描元素总数**：{meta.get('top_elements_scanned', 0):,} 条（含 `Record` / `Workout` / `ActivitySummary`，已排除 `export_cda.xml`、GPX 与 ECG 原始载荷）",
        "- **特性规格版本**：`m4a-feature-spec-v1` · **睡眠合并策略**：`sleep-merge-v1` · **缺测零填充**：**关闭（`missingAsZero == false`）**",
        "",
        "| 核心通道 | `available` | `knownZero` | `missing` | `excluded` | 说明 |",
        "|---|---:|---:|---:|---:|---|",
    ]

    channel_labels = {
        "hrv_sdnn_ms_state": "HRV (SDNN, ms)",
        "resting_hr_bpm_state": "静息心率 (bpm)",
        "respiratory_rate_rpm_state": "呼吸率 (次/分)",
        "spo2_pct_state": "血氧 (%)",
        "wrist_temp_c_state": "手腕温度 (°C)",
        "sleep_total_min_state": "主/总睡眠 (`sleep-merge-v1`)",
        "steps_count_state": "步数（Watch 优先去重）",
        "active_energy_kcal_state": "活动能量 (kcal，去重)",
        "workout_duration_min_state": "体能锻炼时长 (min)",
        "effort_user_state": "主观用力评分 (`WorkoutEffortScore`)",
        "effort_estimated_state": "系统估算用力 (`EstimatedEffort`)",
    }

    for _, state_col in STATE_CHANNELS:
        label = channel_labels.get(state_col, state_col)
        vc = df[state_col].value_counts() if state_col in df.columns else pd.Series(dtype=int)
        av = int(vc.get("available", 0))
        kz = int(vc.get("knownZero", 0))
        ms = int(vc.get("missing", 0))
        ex = int(vc.get("excluded", 0))
        note = "严格区分用户手打与系统估算" if "effort" in state_col else ("佩戴无锻炼标记为 knownZero" if state_col == "workout_duration_min_state" else "缺失保持 NaN")
        lines.append(f"| {label} | {av} | {kz} | {ms} | {ex} | {note} |")

    eat_vc = df["eating_context_state"].value_counts() if "eating_context_state" in df.columns else pd.Series(dtype=int)
    lines.append(
        f"| 进食节律掩码预留 (`eating_context_state`) | {int(eat_vc.get('available', 0))} | {int(eat_vc.get('knownZero', 0))} | {int(eat_vc.get('missing', 0))} | {int(eat_vc.get('excluded', 0))} | V5 §11 预留掩码位（尚未接入进食流） |"
    )

    sl_a = dedup_audit.get("sleep_dedup", {})
    st_a = dedup_audit.get("steps_dedup", {})
    en_a = dedup_audit.get("active_energy_dedup", {})

    lines.extend(
        [
            "",
            "## 2. 多源重叠去重审计与设备归属确认",
            "",
            "遵照 V4 审查意见 §2.7：**不按设备名擅自剔除数据**，而是先盘点全部分源，再通过 `sleep-merge-v1`（Watch 分期 > AutoSleep > 第三方 > iPhone）与区间扫描线按优先级消除重叠双算：",
            "",
            "| 通道 | 原始记录数 | 多源重叠日 | 去重前总计 | 去重后总计 | 拦截重复/超算 | 补充核对 |",
            "|---|---:|---:|---:|---:|---:|---|",
            f"| 睡眠 (`sleep-merge-v1`) | {sl_a.get('raw_samples_count', 0):,} | {sl_a.get('days_with_multi_source_overlap', 0)} 天 | {sl_a.get('raw_asleep_min_sum', 0):,.1f} min | {sl_a.get('dedup_asleep_min_sum', 0):,.1f} min | {sl_a.get('prevented_overcount_min', 0):,.1f} min | 实测睡眠 {sl_a.get('days_with_sleep', 0)} 天，仅卧床 {sl_a.get('days_with_in_bed_only', 0)} 天（标为 missing） |",
            f"| 步数 (`StepCount`) | {st_a.get('raw_samples_count', 0):,} | {st_a.get('days_with_multi_source_overlap', 0)} 天 | {st_a.get('raw_sum', 0):,.0f} 步 | {st_a.get('dedup_sum', 0):,.0f} 步 | {st_a.get('prevented_overcount_sum', 0):,.0f} 步 | Apple Watch 与 iPhone 重叠退让 |",
            f"| 活动能量 (`ActiveEnergy`) | {en_a.get('raw_samples_count', 0):,} | {en_a.get('days_with_multi_source_overlap', 0)} 天 | {en_a.get('raw_sum', 0):,.0f} kcal | {en_a.get('dedup_sum', 0):,.0f} kcal | {en_a.get('prevented_overcount_sum', 0):,.0f} kcal | 与 `ActivitySummary` 重合 {en_a.get('activity_summary_overlap_days', 0)} 天中位差 {en_a.get('activity_summary_median_abs_diff_kcal', '—')} kcal |",
            f"| 体能训练 (`Workout`) | {en_a.get('workout_raw_count', 0):,} | — | {en_a.get('workout_raw_count', 0):,} 场 | {en_a.get('workout_dedup_count', 0):,} 场 | {max(0, en_a.get('workout_raw_count', 0) - en_a.get('workout_dedup_count', 0)):,} 场 | 同时间窗 >=75% 重合由 Watch 优先保留 |",
            "",
            "### 2.1 脱敏来源设备清点（待用户确认归属）",
            "",
            "| 脱敏来源标识 | 类型 | 记录数 | 训练场次 | 最早日期 | 最晚日期 | 审计说明 |",
            "|---|---|---:|---:|---|---|---|",
        ]
    )

    for src in dedup_audit.get("sources_anonymized", []):
        flag = " **[需确认归属]**" if src.get("needs_ownership_confirmation") else ""
        lines.append(
            f"| `{src['anonymized_alias']}`{flag} | `{src['kind']}` | {src['record_count']:,} | {src['workout_count']:,} | {src.get('first_date') or '—'} | {src.get('last_date') or '—'} | {src['audit_note']} |"
        )

    confirm_aliases = [
        f"`{src['anonymized_alias']}`"
        for src in dedup_audit.get("sources_anonymized", [])
        if src.get("needs_ownership_confirmation")
    ]
    if confirm_aliases:
        lines.extend(
            [
                "",
                f"> 注：{', '.join(confirm_aliases)} 虽与主用 Watch 拥有不同的历史设备前缀（完整脱敏前名称仅存于未入库的 `BodySeekML/data/dedup_audit.json`），当前管线**未按名称将其当作他人数据丢弃**，请用户复核上述历史设备是否确为您本人早期设备。",
            ]
        )

    lines.extend(
        [
            "",
            "## 3. 分布滞后个人规律发现（7 天块自助法 + BH-FDR）",
            "",
            f"- **时间严谨性**：严格沿连续日历时间轴计算暴露 $E_t$ 与后续结果 $Y_{{t+\\text{{lag}}}}$（夜间睡眠暴露检验滞后 0–3 天；日间训练/高步数暴露仅检验滞后 1–3 天以防同日晨间指标泄露）。",
            f"- **检验规模**：共评估 {findings_payload.get('total_tests', 0)} 项假设，其中满足样本门槛（暴露/对照各 $\\ge {MIN_EXPOSED_DAYS}$ 天、合计 $\\ge {MIN_TOTAL_DAYS}$ 天）的有效检验 **{findings_payload.get('eligible_tests', 0)}** 项；通过 Benjamini-Hochberg `q < 0.05` 且 95% 块自助置信区间不含 0 的候选规律 **{findings_payload.get('candidate_count', 0)}** 项。",
            "",
        ]
    )

    candidates = [f for f in findings_payload.get("findings", []) if f["status"] == "candidate_for_confirmation"]
    nominal = [f for f in findings_payload.get("findings", []) if f["status"] == "nominal_only_not_fdr"]

    if candidates:
        lines.extend(
            [
                "### 3.1 通过 FDR 校正的候选个人规律（`candidate_for_confirmation`）",
                "",
                "| 暴露条件 ($t$) | 结果指标 ($t+\\text{lag}$) | 滞后 | 暴露均值 | 对照均值 | 差异 (95% 块自助 CI) | 样本 (暴露/对照) | `p` 值 | FDR `q` |",
                "|---|---|---:|---:|---:|---|---:|---:|---:|",
            ]
        )
        for item in candidates:
            delta_str = f"{item['delta_mean']:+.2f} [{item['ci_95_low']:+.2f}, {item['ci_95_high']:+.2f}] {item['outcome_unit']}"
            lines.append(
                f"| {item['exposure_title_zh']} | {item['outcome_title_zh']} | +{item['lag_days']}d | {item['exposed_mean']:.2f} | {item['control_mean']:.2f} | {delta_str} | {item['n_exposed']}/{item['n_control']} | {item['p_value']:.4f} | {item['q_value']:.4f} |"
            )
    else:
        lines.append("> 本批数据中暂无同时满足最小样本门禁与 `q < 0.05` 的候选规律。")

    if nominal:
        lines.extend(
            [
                "",
                "### 3.2 仅名义显著（`p < 0.05` 但未通过 FDR 多重校正，仅供探索参考，不入记忆）",
                "",
                "| 暴露条件 ($t$) | 结果指标 ($t+\\text{lag}$) | 滞后 | 差异 (95% CI) | 样本 (暴露/对照) | `p` 值 | FDR `q` |",
                "|---|---|---:|---|---:|---:|---:|",
            ]
        )
        for item in nominal[:10]:
            delta_str = f"{item['delta_mean']:+.2f} [{item['ci_95_low']:+.2f}, {item['ci_95_high']:+.2f}] {item['outcome_unit']}"
            lines.append(
                f"| {item['exposure_title_zh']} | {item['outcome_title_zh']} | +{item['lag_days']}d | {delta_str} | {item['n_exposed']}/{item['n_control']} | {item['p_value']:.4f} | {item['q_value']:.4f} |"
            )

    insufficient = [f for f in findings_payload.get("findings", []) if f["status"] == "insufficient_sample"]
    lines.extend(
        [
            "",
            f"- 因暴露或对照天数不足样本门禁而诚实标为 `insufficient_sample` 的假设共 **{len(insufficient)}** 项（不强行下结论）。",
            "",
            "## 4. 科学性与入库守则（M4b / M3 衔接）",
            "",
            "1. **非因果警示**：上述滞后差异反映历史共变节律，仍受训练日/休息日自选择、病程或工作负荷等未观测混杂影响，禁止 Coach Agent 将其陈述为因果效应；需因果校验的行为改变应通过 **M4d N-of-1 个人对照实验**检验。",
            "2. **记忆确认门禁**：`Verified Pattern` 仅能由用户明确确认 `candidate_for_confirmation` 条目后写入 GRDB `pattern_finding` 与 `athlete_memory`。",
            "3. **下一阶段（M4b）**：基于本次生成的 `BodySeekML/data/daily_features.parquet`（全过程严格避免未来泄露），开展前 24 个月起训、按月滚动的 walk-forward 回测（Persistence / Ridge / Banister / LightGBM）。",
        ]
    )

    markdown = "\n".join(lines) + "\n"
    assert_report_anonymized(markdown, dedup_audit)
    target.write_text(markdown, encoding="utf-8")
    return markdown
