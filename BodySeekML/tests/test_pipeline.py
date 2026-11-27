"""Unit and integration tests for BodySeekML M4a pipeline."""

from __future__ import annotations

from datetime import date, timedelta
from pathlib import Path
import zipfile

import numpy as np
import pandas as pd
import pytest

from bodyseek_ml.cli import main as cli_main
from bodyseek_ml.export_parser import parse_export_to_features
from bodyseek_ml.patterns import (
    analyze_distributed_lag_patterns,
    assert_report_anonymized,
    benjamini_hochberg_fdr,
    render_personal_patterns_report,
)


def _write_export_zip(
    zip_path: Path,
    body_xml: str,
    xml_entry_name: str = "apple_health_export/σ»╝σç║.xml",
    owner_dob: str = "1999-01-01",
) -> None:
    xml_doc = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<HealthData locale="zh_CN">\n'
        ' <ExportDate value="2026-11-19 18:00:00 +0800"/>\n'
        f' <Me HKCharacteristicTypeIdentifierDateOfBirth="{owner_dob}" '
        'HKCharacteristicTypeIdentifierBiologicalSex="HKBiologicalSexMale" '
        'HKCharacteristicTypeIdentifierBloodType="HKBloodTypeNotSet" '
        'HKCharacteristicTypeIdentifierFitzpatrickSkinType="HKFitzpatrickSkinTypeNotSet" '
        'HKCharacteristicTypeIdentifierCardioFitnessMedicationsUse="None"/>\n'
        f"{body_xml}\n"
        "</HealthData>\n"
    )
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("apple_health_export/export_cda.xml", "<ClinicalDocument/>")
        zf.writestr(xml_entry_name, xml_doc.encode("utf-8"))


def test_cp437_zip_cutover_sleep_merge_steps_dedup_four_states_and_effort_separation(tmp_path: Path) -> None:
    zip_path = tmp_path / "export.zip"
    out_dir = tmp_path / "out"
    report_path = tmp_path / "report.md"

    records = [
        # Day 2025-10-01 via 04:00 physiological cutover (02:30 -> 2025-10-01)
        '<Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" sourceName="Alice‘s Apple\xa0Watch" unit="ms" startDate="2025-10-02 02:30:00 +0800" endDate="2025-10-02 02:31:00 +0800" value="64"/>',
        # Day 2025-10-02 via 04:00 boundary (04:00 -> 2025-10-02)
        '<Record type="HKQuantityTypeIdentifierHeartRateVariabilitySDNN" sourceName="Alice‘s Apple\xa0Watch" unit="ms" startDate="2025-10-02 04:00:00 +0800" endDate="2025-10-02 04:01:00 +0800" value="48"/>',
        '<Record type="HKQuantityTypeIdentifierRestingHeartRate" sourceName="Alice‘s Apple\xa0Watch" unit="count/min" startDate="2025-10-02 07:00:00 +0800" endDate="2025-10-02 07:01:00 +0800" value="56"/>',
        # Sleep overlap on 2025-10-02 morning: Watch 240m Core + 120m Deep (360m total) overlaps AutoSleep 360m + iPhone InBed 420m
        '<Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Alice‘s Apple\xa0Watch" startDate="2025-10-02 00:00:00 +0800" endDate="2025-10-02 04:00:00 +0800" value="HKCategoryValueSleepAnalysisAsleepCore"/>',
        '<Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Alice‘s Apple\xa0Watch" startDate="2025-10-02 04:00:00 +0800" endDate="2025-10-02 06:00:00 +0800" value="HKCategoryValueSleepAnalysisAsleepDeep"/>',
        '<Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="AutoSleep" startDate="2025-10-02 00:00:00 +0800" endDate="2025-10-02 06:00:00 +0800" value="HKCategoryValueSleepAnalysisAsleepUnspecified"/>',
        '<Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Bob De iPhone" startDate="2025-10-01 23:30:00 +0800" endDate="2025-10-02 06:30:00 +0800" value="HKCategoryValueSleepAnalysisInBed"/>',
        # Overlapping steps on 2025-10-02: Watch 600 steps + iPhone 580 steps on [10:00, 10:10], plus iPhone 400 steps on [12:00, 12:05] -> expect 1000
        '<Record type="HKQuantityTypeIdentifierStepCount" sourceName="Alice‘s Apple\xa0Watch" unit="count" startDate="2025-10-02 10:00:00 +0800" endDate="2025-10-02 10:10:00 +0800" value="600"/>',
        '<Record type="HKQuantityTypeIdentifierStepCount" sourceName="Bob De iPhone" unit="count" startDate="2025-10-02 10:00:00 +0800" endDate="2025-10-02 10:10:00 +0800" value="580"/>',
        '<Record type="HKQuantityTypeIdentifierStepCount" sourceName="Bob De iPhone" unit="count" startDate="2025-10-02 12:00:00 +0800" endDate="2025-10-02 12:05:00 +0800" value="400"/>',
        # SpO2 out-of-range on 2025-10-01 (40% < 70%) -> excluded
        '<Record type="HKQuantityTypeIdentifierOxygenSaturation" sourceName="Alice‘s Apple\xa0Watch" unit="%" startDate="2025-10-02 02:30:00 +0800" endDate="2025-10-02 02:31:00 +0800" value="0.40"/>',
        # SpO2 normal fraction on 2025-10-02 (0.97 -> 97.0%)
        '<Record type="HKQuantityTypeIdentifierOxygenSaturation" sourceName="Alice‘s Apple\xa0Watch" unit="%" startDate="2025-10-02 08:00:00 +0800" endDate="2025-10-02 08:01:00 +0800" value="0.97"/>',
        # Effort separation: User Effort on 2025-10-02 only, Estimated Effort on 2025-10-05 only (leaves 2025-10-03 & 2025-10-04 non-wear gaps)
        '<Record type="HKQuantityTypeIdentifierWorkoutEffortScore" sourceName="健身" unit="appleEffortScore" startDate="2025-10-02 19:00:00 +0800" endDate="2025-10-02 19:00:00 +0800" value="8"/>',
        '<Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="30" durationUnit="min" sourceName="Alice‘s Apple\xa0Watch" startDate="2025-10-02 18:30:00 +0800" endDate="2025-10-02 19:00:00 +0800"><WorkoutStatistics type="HKQuantityTypeIdentifierActiveEnergyBurned" sum="380" unit="kcal"/></Workout>',
        '<Record type="HKQuantityTypeIdentifierEstimatedWorkoutEffortScore" sourceName="Charlie‘s Apple\xa0Watch" unit="appleEffortScore" startDate="2025-10-05 18:00:00 +0800" endDate="2025-10-05 18:00:00 +0800" value="6"/>',
        '<Record type="HKQuantityTypeIdentifierRestingHeartRate" sourceName="Charlie‘s Apple\xa0Watch" unit="count/min" startDate="2025-10-05 08:00:00 +0800" endDate="2025-10-05 08:01:00 +0800" value="58"/>',
        # InBed-only night on 2025-10-06 without Watch sleep stages -> sleep_total_min_state must be "missing" (NOT "excluded")
        '<Record type="HKCategoryTypeIdentifierSleepAnalysis" sourceName="Bob De iPhone" startDate="2025-10-06 00:00:00 +0800" endDate="2025-10-06 06:30:00 +0800" value="HKCategoryValueSleepAnalysisInBed"/>',
    ]
    _write_export_zip(zip_path, "\n ".join(records))

    df, spec, audit = parse_export_to_features(zip_path, out_dir)
    assert spec["missing_as_zero"] is False
    assert (out_dir / "daily_features.parquet").exists()
    assert (out_dir / "feature_spec_m4a.json").exists()
    assert (out_dir / "dedup_audit.json").exists()

    by_day = df.set_index("day_key")
    # 6 calendar days (2025-10-01 .. 2025-10-06)
    assert list(by_day.index) == ["2025-10-01", "2025-10-02", "2025-10-03", "2025-10-04", "2025-10-05", "2025-10-06"]

    # 04:00 cutover check
    assert by_day.loc["2025-10-01", "hrv_sdnn_ms"] == pytest.approx(64.0)
    assert by_day.loc["2025-10-02", "hrv_sdnn_ms"] == pytest.approx(48.0)

    # Sleep merge overlap deduplication (Watch 360m beats AutoSleep & iPhone) + Watch onset/efficiency not distorted by iPhone InBed
    assert by_day.loc["2025-10-02", "sleep_total_min"] == pytest.approx(360.0)
    assert by_day.loc["2025-10-02", "sleep_deep_min"] == pytest.approx(120.0)
    assert by_day.loc["2025-10-02", "sleep_onset_hour"] == pytest.approx(24.0)
    assert by_day.loc["2025-10-02", "sleep_efficiency"] == pytest.approx(1.0)
    assert audit["sleep_dedup"]["days_with_multi_source_overlap"] == 1
    assert audit["sleep_dedup"]["days_with_in_bed_only"] == 1
    assert audit["sleep_dedup"]["prevented_overcount_min"] >= 360.0
    # InBed-only 2025-10-06 must stay "missing", not "excluded"
    assert by_day.loc["2025-10-06", "sleep_total_min_state"] == "missing"
    assert pd.isna(by_day.loc["2025-10-06", "sleep_total_min"])
    assert by_day.loc["2025-10-06", "sleep_in_bed_min"] == pytest.approx(390.0)

    # Steps sweep-line dedup (600 + 400 = 1000, NOT 1580)
    assert by_day.loc["2025-10-02", "steps_count"] == pytest.approx(1000.0)
    assert audit["steps_dedup"]["days_with_multi_source_overlap"] == 1

    # 4-state truth semantics:
    # 1) excluded (out-of-range SpO2 on 2025-10-01)
    assert by_day.loc["2025-10-01", "spo2_pct_state"] == "excluded"
    assert pd.isna(by_day.loc["2025-10-01", "spo2_pct"])
    assert by_day.loc["2025-10-02", "spo2_pct"] == pytest.approx(97.0)
    # 2) knownZero on wear days with no workout (2025-10-01 and 2025-10-05)
    assert by_day.loc["2025-10-01", "workout_duration_min_state"] == "knownZero"
    assert by_day.loc["2025-10-01", "workout_duration_min"] == pytest.approx(0.0)
    assert by_day.loc["2025-10-05", "workout_duration_min_state"] == "knownZero"
    # 3) missing on complete non-wear gap days (2025-10-03 & 2025-10-04) — NEVER coerced to 0
    assert by_day.loc["2025-10-03", "hrv_sdnn_ms_state"] == "missing"
    assert pd.isna(by_day.loc["2025-10-03", "hrv_sdnn_ms"])
    assert by_day.loc["2025-10-03", "workout_duration_min_state"] == "missing"
    assert pd.isna(by_day.loc["2025-10-03", "workout_duration_min"])
    # 4) reserved eating mask
    assert (df["eating_context_state"] == "missing").all()

    # Effort separation
    assert by_day.loc["2025-10-02", "effort_user_mean"] == pytest.approx(8.0)
    assert by_day.loc["2025-10-02", "effort_estimated_state"] == "missing"
    assert by_day.loc["2025-10-05", "effort_estimated_mean"] == pytest.approx(6.0)
    assert by_day.loc["2025-10-05", "effort_user_state"] == "missing"

    # Privacy-sanitized report rendering (must strip Alice/Bob/Charlie & DOB)
    findings = analyze_distributed_lag_patterns(df, out_dir)
    md = render_personal_patterns_report(df, audit, findings, report_path)
    for forbidden in ("Alice", "Bob", "Charlie", "1999-01-01", "DateOfBirth"):
        assert forbidden not in md
    assert "Apple Watch #1" in md
    assert "Apple Watch #2" in md
    assert "iPhone #1" in md

    with pytest.raises(ValueError, match="Privacy guard"):
        assert_report_anonymized(md + "\nLeak: Alice's watch", audit)

    # CLI exit check
    rc = cli_main(["run-m4a", "--export-zip", str(zip_path), "--out-dir", str(out_dir), "--report", str(report_path)])
    assert rc == 0


def test_distributed_lag_block_bootstrap_fdr_and_no_future_leakage(tmp_path: Path) -> None:
    rng = np.random.default_rng(123)
    n_days = 120
    start = date(2025, 1, 1)
    rows = []
    for i in range(n_days):
        # Leave a calendar gap on day 60 to test contiguous reindexing
        if i == 60:
            continue
        is_short = (i % 4 == 0)
        sleep_min = 320.0 if is_short else 450.0
        # Effect on lag 0 HRV (-14 ms) and lag 1 HRV (-8 ms)
        prev_short = ((i - 1) % 4 == 0)
        hrv = 65.0 - (14.0 if is_short else 0.0) - (8.0 if prev_short else 0.0) + float(rng.normal(0, 2.0))
        rows.append(
            {
                "day_key": (start + timedelta(days=i)).isoformat(),
                "hrv_sdnn_ms": hrv,
                "hrv_sdnn_ms_state": "available",
                "resting_hr_bpm": 55.0 + float(rng.normal(0, 1.5)),
                "resting_hr_bpm_state": "available",
                "respiratory_rate_rpm": 14.0,
                "respiratory_rate_rpm_state": "available",
                "spo2_pct": 97.5,
                "spo2_pct_state": "available",
                "wrist_temp_c": 35.5,
                "wrist_temp_c_state": "available",
                "sleep_total_min": sleep_min,
                "sleep_total_min_state": "available",
                "sleep_efficiency": 0.90,
                "sleep_deep_min": 80.0,
                "sleep_onset_hour": 23.0,
                "steps_count": 7000.0,
                "steps_count_state": "available",
                "active_energy_kcal": 400.0,
                "active_energy_kcal_state": "available",
                "workout_count": 0.0,
                "workout_duration_min": 0.0,
                "workout_duration_min_state": "knownZero",
                "workout_active_kcal": 0.0,
                "has_strength_workout": 0,
                "has_badminton_workout": 0,
                "has_running_workout": 0,
                "effort_user_mean": np.nan,
                "effort_user_state": "missing",
                "effort_estimated_mean": np.nan,
                "effort_estimated_state": "missing",
                "eating_context_state": "missing",
            }
        )

    df = pd.DataFrame(rows)
    payload = analyze_distributed_lag_patterns(df, tmp_path / "pat_out")
    by_id = {f["id"]: f for f in payload["findings"]}

    lag0 = by_id["short_sleep_lt_6h__lag0__hrv_sdnn_ms"]
    assert lag0["status"] == "candidate_for_confirmation"
    assert lag0["delta_mean"] < -10.0
    assert lag0["ci_95_high"] < 0.0
    assert lag0["q_value"] < 0.05
    assert lag0["causal_claim_allowed"] is False

    # Trivial lag0 self-sleep outcome must be excluded
    assert "short_sleep_lt_6h__lag0__sleep_total_min" not in by_id

    # BH-FDR monotonicity sanity check
    qs = benjamini_hochberg_fdr([0.001, 0.02, 0.04, 0.5])
    assert qs[0] <= qs[1] <= qs[2] <= qs[3]


def test_exposure_builders_have_zero_future_leakage() -> None:
    from bodyseek_ml.patterns import EXPOSURE_SPECS

    rng = np.random.default_rng(7)
    n_days = 80
    start = date(2025, 1, 1)
    base_rows = []
    for i in range(n_days):
        is_w = (i % 3 == 0)
        base_rows.append(
            {
                "day_key": (start + timedelta(days=i)).isoformat(),
                "sleep_total_min": float(350 + (i % 5) * 35),
                "sleep_total_min_state": "available",
                "sleep_onset_hour": 23.0 + (i % 3) * 0.8,
                "steps_count": float(4000 + (i % 4) * 2500),
                "steps_count_state": "available",
                "workout_duration_min": 65.0 if is_w else 0.0,
                "workout_duration_min_state": "available" if is_w else "knownZero",
                "workout_active_kcal": float(420 + rng.integers(0, 200)) if is_w else 0.0,
                "has_strength_workout": int(is_w and i % 2 == 0),
                "has_badminton_workout": int(is_w and i % 2 == 1),
                "has_running_workout": 0,
            }
        )
    df_full = pd.DataFrame(base_rows)
    cutoff = 50
    df_mutated = df_full.copy()
    df_mutated.loc[cutoff:, "sleep_total_min"] = 900.0
    df_mutated.loc[cutoff:, "workout_active_kcal"] = 2500.0
    df_mutated.loc[cutoff:, "workout_duration_min"] = 180.0

    for spec in EXPOSURE_SPECS:
        arm_full = spec.builder(df_full)[:cutoff]
        arm_mut = spec.builder(df_mutated)[:cutoff]
        assert np.array_equal(arm_full, arm_mut), f"Future leakage detected in {spec.exposure_id}"


def _make_synthetic_multi_month_features(months: int = 18) -> pd.DataFrame:
    rng = np.random.default_rng(314)
    start = date(2024, 1, 1)
    n_days = months * 30
    rows = []
    hrv = 48.0
    rhr = 57.0
    for i in range(n_days):
        day = start + timedelta(days=i)
        workout_min = 45.0 if (i % 3 == 0) else 0.0
        sleep_min = 440.0 if (i % 4 != 0) else 350.0
        sleep_eff = 0.94 if (i % 4 != 0) else 0.86
        hrv = float(np.clip(0.55 * hrv + 0.45 * (42.0 + 0.03 * (sleep_min - 400.0) - 0.05 * workout_min) + rng.normal(0, 3.0), 25.0, 90.0))
        rhr = float(np.clip(0.5 * rhr + 0.5 * (58.0 - 0.02 * (hrv - 45.0)) + rng.normal(0, 1.5), 45.0, 75.0))
        rows.append(
            {
                "day_key": day.isoformat(),
                "hrv_sdnn_ms": hrv if (i % 9 != 0) else np.nan,
                "resting_hr_bpm": rhr if (i % 11 != 0) else np.nan,
                "sleep_total_min": sleep_min if (i % 7 != 0) else np.nan,
                "sleep_efficiency": sleep_eff if (i % 7 != 0) else np.nan,
                "sleep_deep_min": 65.0 if (i % 7 != 0) else np.nan,
                "sleep_rem_min": 90.0 if (i % 7 != 0) else np.nan,
                "active_energy_kcal": 450.0 + workout_min * 7.0,
                "workout_duration_min": workout_min,
                "effort_user_mean": 7.5 if workout_min > 0 and i % 2 == 0 else np.nan,
                "effort_estimated_mean": 6.5 if workout_min > 0 and i % 2 == 1 else np.nan,
                "eating_context_state": "missing",
            }
        )
    return pd.DataFrame(rows)


def test_supervised_features_have_zero_future_leakage() -> None:
    from bodyseek_ml.forecasting import FEATURE_COLUMNS, build_supervised_dataset

    df = _make_synthetic_multi_month_features(months=4)
    cutoff = 60
    df_mut = df.copy()
    df_mut.loc[cutoff:, "hrv_sdnn_ms"] = 140.0
    df_mut.loc[cutoff:, "resting_hr_bpm"] = 88.0
    df_mut.loc[cutoff:, "sleep_efficiency"] = 0.60
    df_mut.loc[cutoff:, "active_energy_kcal"] = 2800.0

    sup_full = build_supervised_dataset(df).iloc[:cutoff][list(FEATURE_COLUMNS)]
    sup_mut = build_supervised_dataset(df_mut).iloc[:cutoff][list(FEATURE_COLUMNS)]
    pd.testing.assert_frame_equal(sup_full, sup_mut)
    assert (sup_full["eating_context_mask0"] == 0.0).all()


def test_m4b_m4c_and_coreml_export_parity_end_to_end(tmp_path: Path) -> None:
    from bodyseek_ml.coreml_export import fit_and_export_coreml
    from bodyseek_ml.deep_models import render_m4c_report, run_m4c_comparison
    from bodyseek_ml.forecasting import render_m4b_report, run_m4b_walk_forward

    df = _make_synthetic_multi_month_features(months=18)
    m4b = run_m4b_walk_forward(df, initial_months=10)
    assert "hrv_sdnn_ms" in m4b["targets"]
    assert m4b["targets"]["hrv_sdnn_ms"]["models"]["Ridge"]["fold_count"] >= 4
    assert m4b["targets"]["hrv_sdnn_ms"]["models"]["Ridge"]["coverage_80"] > 0.4

    m4c = run_m4c_comparison(df, m4b, initial_months=10, epochs=6)
    assert "MaskedTCN" in m4c["targets"]["hrv_sdnn_ms"]["deep_models"]
    assert "PatchTSTLite" in m4c["targets"]["hrv_sdnn_ms"]["deep_models"]

    docs_dir = tmp_path / "docs"
    kit_dir = tmp_path / "BodySeekKit"
    render_m4b_report(m4b, docs_dir / "validation" / "m4b.md")
    render_m4c_report(m4c, docs_dir / "validation" / "m4c.md")
    export_info = fit_and_export_coreml(df, m4b, m4c, kit_dir=kit_dir, docs_dir=docs_dir)

    assert Path(export_info["mlpackage_path"]).exists()
    assert Path(export_info["spec_path"]).exists()
    assert Path(export_info["golden_path"]).exists()
    assert export_info["max_python_coreml_rel_err"] <= 1e-4

