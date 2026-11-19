"""Streaming Apple Health export parser aligned with BodySeekCore DayKey and SleepMergePolicy."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
import json
from pathlib import Path
import statistics
from typing import Any, IO
import xml.etree.ElementTree as ET
import zipfile

import numpy as np
import pandas as pd

from .dedup_audit import (
    SourceStats,
    build_dedup_audit,
    classify_source_kind,
    infer_activity_tier,
    infer_sleep_tier,
    normalize_source_name,
)

PHYSIOLOGICAL_CUTOVER_HOUR = 4
FEATURE_SPEC_VERSION = "m4a-feature-spec-v1"
SLEEP_MERGE_POLICY_VERSION = "sleep-merge-v1"
SLEEP_EPISODE_GAP_SECONDS = 90.0 * 60.0

VALID_TRUTH_STATES: tuple[str, ...] = ("available", "knownZero", "missing", "excluded")

MEDIAN_RECORD_TYPES: dict[str, str] = {
    "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": "hrv_sdnn_ms",
    "HKQuantityTypeIdentifierRestingHeartRate": "resting_hr_bpm",
    "HKQuantityTypeIdentifierRespiratoryRate": "respiratory_rate_rpm",
    "HKQuantityTypeIdentifierOxygenSaturation": "spo2_pct",
    "HKQuantityTypeIdentifierAppleSleepingWristTemperature": "wrist_temp_c",
    "HKQuantityTypeIdentifierWalkingHeartRateAverage": "walking_hr_avg_bpm",
    "HKQuantityTypeIdentifierVO2Max": "vo2_max",
    "HKQuantityTypeIdentifierHeartRateRecoveryOneMinute": "hr_recovery_1min_bpm",
    "HKQuantityTypeIdentifierBodyMass": "body_mass_kg",
    "HKQuantityTypeIdentifierPhysicalEffort": "physical_effort_mean",
    "HKQuantityTypeIdentifierWorkoutEffortScore": "effort_user_mean",
    "HKQuantityTypeIdentifierEstimatedWorkoutEffortScore": "effort_estimated_mean",
}

INTERVAL_SUM_TYPES: dict[str, str] = {
    "HKQuantityTypeIdentifierStepCount": "steps_count",
    "HKQuantityTypeIdentifierActiveEnergyBurned": "active_energy_kcal",
    "HKQuantityTypeIdentifierBasalEnergyBurned": "basal_energy_kcal",
    "HKQuantityTypeIdentifierTimeInDaylight": "time_in_daylight_min",
}

SLEEP_VALUE_TO_STAGE: dict[str, str] = {
    "HKCategoryValueSleepAnalysisAsleepDeep": "deep",
    "HKCategoryValueSleepAnalysisAsleepCore": "core",
    "HKCategoryValueSleepAnalysisAsleepREM": "rem",
    "HKCategoryValueSleepAnalysisAwake": "awake",
    "HKCategoryValueSleepAnalysisAsleepUnspecified": "asleep_unspecified",
    "HKCategoryValueSleepAnalysisAsleep": "asleep_unspecified",
    "HKCategoryValueSleepAnalysisInBed": "in_bed",
}

STAGE_SPECIFICITY: dict[str, int] = {
    "deep": 3,
    "core": 3,
    "rem": 3,
    "awake": 2,
    "asleep_unspecified": 1,
    "in_bed": 0,
}

PHYSIOLOGICAL_BOUNDS: dict[str, tuple[float, float]] = {
    "hrv_sdnn_ms": (1.0, 300.0),
    "resting_hr_bpm": (25.0, 200.0),
    "respiratory_rate_rpm": (4.0, 60.0),
    "spo2_pct": (70.0, 100.0),
    "wrist_temp_c": (25.0, 42.0),
    "walking_hr_avg_bpm": (30.0, 220.0),
    "vo2_max": (10.0, 95.0),
    "hr_recovery_1min_bpm": (0.0, 120.0),
    "body_mass_kg": (20.0, 250.0),
    "sleep_total_min": (30.0, 1200.0),
    "steps_count": (0.0, 150000.0),
    "active_energy_kcal": (0.0, 15000.0),
    "basal_energy_kcal": (0.0, 10000.0),
}

STATE_CHANNELS: tuple[tuple[str, str], ...] = (
    ("hrv_sdnn_ms", "hrv_sdnn_ms_state"),
    ("resting_hr_bpm", "resting_hr_bpm_state"),
    ("respiratory_rate_rpm", "respiratory_rate_rpm_state"),
    ("spo2_pct", "spo2_pct_state"),
    ("wrist_temp_c", "wrist_temp_c_state"),
    ("sleep_total_min", "sleep_total_min_state"),
    ("steps_count", "steps_count_state"),
    ("active_energy_kcal", "active_energy_kcal_state"),
    ("workout_duration_min", "workout_duration_min_state"),
    ("effort_user_mean", "effort_user_state"),
    ("effort_estimated_mean", "effort_estimated_state"),
)

_TZ_CACHE: dict[str, timezone] = {}


def _parse_tz(tz_str: str) -> timezone:
    cached = _TZ_CACHE.get(tz_str)
    if cached is not None:
        return cached
    sign = 1 if tz_str[0] == "+" else -1
    hours = int(tz_str[1:3])
    minutes = int(tz_str[3:5])
    tz = timezone(timedelta(hours=sign * hours, minutes=sign * minutes))
    _TZ_CACHE[tz_str] = tz
    return tz


def parse_hk_timestamp(raw: str) -> tuple[datetime, datetime, str]:
    """Parse Apple Health 'YYYY-MM-DD HH:MM:SS ±HHMM' into (aware_dt, local_naive_dt, phys_day_key)."""
    year = int(raw[0:4])
    month = int(raw[5:7])
    day = int(raw[8:10])
    hour = int(raw[11:13])
    minute = int(raw[14:16])
    second = int(raw[17:19])
    tz_part = raw[20:25] if len(raw) >= 25 else "+0000"
    tz = _parse_tz(tz_part)
    local_naive = datetime(year, month, day, hour, minute, second)
    aware = local_naive.replace(tzinfo=tz)
    shifted_date = (local_naive - timedelta(hours=PHYSIOLOGICAL_CUTOVER_HOUR)).date()
    return aware, local_naive, shifted_date.isoformat()


def _normalize_unit_value(metric_col: str, raw_value: float, unit: str | None) -> float | None:
    if not np.isfinite(raw_value):
        return None
    u = (unit or "").strip()
    if metric_col == "spo2_pct":
        return raw_value * 100.0 if raw_value <= 1.5 else raw_value
    if metric_col in {"active_energy_kcal", "basal_energy_kcal"}:
        if u.lower() == "kj":
            return raw_value * 0.2390057361
        return raw_value
    if metric_col == "body_mass_kg":
        if u.lower() in {"lb", "lbs"}:
            return raw_value * 0.45359237
        return raw_value
    if metric_col == "wrist_temp_c":
        if u.lower() == "degf":
            return (raw_value - 32.0) * (5.0 / 9.0)
        return raw_value
    if metric_col == "time_in_daylight_min":
        if u.lower() in {"s", "sec"}:
            return raw_value / 60.0
        if u.lower() in {"hr", "h"}:
            return raw_value * 60.0
        return raw_value
    return raw_value


def find_export_xml_entry(zf: zipfile.ZipFile) -> str:
    """Locate the main Apple Health export XML inside a zip, skipping export_cda.xml regardless of CP437 mojibake."""
    candidates = [
        name
        for name in zf.namelist()
        if name.lower().endswith(".xml")
        and not name.lower().endswith("export_cda.xml")
        and not name.startswith("__MACOSX/")
    ]
    if not candidates:
        raise FileNotFoundError("No Apple Health XML entry found in export zip archive")
    # Prefer the largest XML payload (export.xml is >> any companion XML)
    candidates.sort(key=lambda n: zf.getinfo(n).file_size, reverse=True)
    return candidates[0]


@dataclass(slots=True)
class SleepSample:
    start_ts: float
    end_ts: float
    start_local: datetime
    end_local: datetime
    end_day_key: str
    stage: str
    tier: int
    norm_source: str
    order_idx: int


@dataclass(slots=True)
class IntervalSample:
    start_ts: float
    end_ts: float
    value: float
    tier: int
    norm_source: str


@dataclass(slots=True)
class WorkoutSample:
    day_key: str
    start_ts: float
    end_ts: float
    duration_min: float
    active_kcal: float | None
    activity_type: str
    tier: int
    norm_source: str


def _merge_sleep_policy_v1(samples: list[SleepSample]) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    """Python mirror of BodySeekCore SleepMergePolicy (`sleep-merge-v1`)."""
    valid = [s for s in samples if s.end_ts > s.start_ts]
    if not valid:
        return {}, {
            "policy_version": SLEEP_MERGE_POLICY_VERSION,
            "raw_samples_count": len(samples),
            "days_with_sleep": 0,
            "days_with_in_bed_only": 0,
            "days_with_multi_source_overlap": 0,
            "raw_asleep_min_sum": 0.0,
            "dedup_asleep_min_sum": 0.0,
            "prevented_overcount_min": 0.0,
            "primary_source_counts": {},
        }

    valid.sort(key=lambda s: (s.start_ts, s.end_ts, s.order_idx))

    raw_asleep_by_day: dict[str, float] = defaultdict(float)
    raw_asleep_sources_by_day: dict[str, set[str]] = defaultdict(set)
    for s in valid:
        if s.stage != "in_bed":
            raw_min = (s.end_ts - s.start_ts) / 60.0
            if s.stage != "awake":
                raw_asleep_by_day[s.end_day_key] += raw_min
            raw_asleep_sources_by_day[s.end_day_key].add(s.norm_source)

    clusters: list[list[SleepSample]] = []
    cur: list[SleepSample] = []
    max_end = -1e18
    for s in valid:
        if not cur:
            cur = [s]
            max_end = s.end_ts
        elif s.start_ts - max_end <= SLEEP_EPISODE_GAP_SECONDS:
            cur.append(s)
            if s.end_ts > max_end:
                max_end = s.end_ts
        else:
            clusters.append(cur)
            cur = [s]
            max_end = s.end_ts
    if cur:
        clusters.append(cur)

    drafts_by_day: dict[str, list[dict[str, Any]]] = defaultdict(list)

    for cluster in clusters:
        boundaries = sorted({b for s in cluster for b in (s.start_ts, s.end_ts)})
        if len(boundaries) < 2:
            continue

        deep_sec = 0.0
        rem_sec = 0.0
        core_sec = 0.0
        awake_sec = 0.0
        unspec_sec = 0.0
        earliest_ts: float | None = None
        latest_ts: float | None = None
        dur_by_source: dict[str, float] = defaultdict(float)

        # Map ts -> local offset from sample endpoints for accurate clock conversion
        earliest_local: datetime | None = None
        latest_local: datetime | None = None
        first_asleep_local: datetime | None = None
        last_asleep_local: datetime | None = None
        wearable_start_ts: float | None = None
        wearable_end_ts: float | None = None
        has_wearable_asleep = False
        local_by_ts: dict[float, datetime] = {}
        for s in cluster:
            local_by_ts[s.start_ts] = s.start_local
            local_by_ts[s.end_ts] = s.end_local

        for idx in range(len(boundaries) - 1):
            t0 = boundaries[idx]
            t1 = boundaries[idx + 1]
            dt = t1 - t0
            if dt <= 0.5:
                continue
            winner: SleepSample | None = None
            winner_key = (-1, -1, -1)
            for s in cluster:
                if s.start_ts <= t0 and s.end_ts >= t1:
                    k = (s.tier, STAGE_SPECIFICITY[s.stage], -s.order_idx)
                    if winner is None or k > winner_key:
                        winner = s
                        winner_key = k
            if winner is None:
                continue
            t0_local = local_by_ts.get(t0) or (
                winner.start_local + timedelta(seconds=(t0 - winner.start_ts))
            )
            t1_local = local_by_ts.get(t1) or (
                winner.end_local - timedelta(seconds=(winner.end_ts - t1))
            )
            if earliest_ts is None:
                earliest_ts = t0
                earliest_local = t0_local
            latest_ts = t1
            latest_local = t1_local
            dur_by_source[winner.norm_source] += dt
            if winner.tier >= 2 and winner.stage != "in_bed":
                if wearable_start_ts is None:
                    wearable_start_ts = t0
                wearable_end_ts = t1
            if winner.stage in {"deep", "rem", "core", "asleep_unspecified"}:
                if first_asleep_local is None:
                    first_asleep_local = t0_local
                last_asleep_local = t1_local
                if winner.tier >= 2:
                    has_wearable_asleep = True
            if winner.stage == "deep":
                deep_sec += dt
            elif winner.stage == "rem":
                rem_sec += dt
            elif winner.stage == "core":
                core_sec += dt
            elif winner.stage == "awake":
                awake_sec += dt
            elif winner.stage == "asleep_unspecified":
                unspec_sec += dt

        if earliest_ts is None or latest_ts is None or earliest_local is None or latest_local is None:
            continue

        in_bed_span = max(0, round((latest_ts - earliest_ts) / 60.0))
        deep_min = round(deep_sec / 60.0)
        rem_min = round(rem_sec / 60.0)
        core_min = round(core_sec / 60.0)
        awake_min = round(awake_sec / 60.0)
        asleep_min = round((deep_sec + rem_sec + core_sec + unspec_sec) / 60.0)
        total_in_bed = max(in_bed_span, asleep_min + awake_min)
        wearable_span_min = (
            max(0, round((wearable_end_ts - wearable_start_ts) / 60.0))
            if (wearable_start_ts is not None and wearable_end_ts is not None)
            else 0
        )
        if asleep_min <= 0 and total_in_bed <= 0:
            continue

        day_key = (latest_local - timedelta(hours=PHYSIOLOGICAL_CUTOVER_HOUR)).date().isoformat()
        primary_source = max(dur_by_source.items(), key=lambda x: (x[1], x[0]))[0]
        drafts_by_day[day_key].append(
            {
                "start_ts": earliest_ts,
                "end_ts": latest_ts,
                "start_local": earliest_local,
                "end_local": latest_local,
                "first_asleep_local": first_asleep_local,
                "last_asleep_local": last_asleep_local,
                "has_wearable_asleep": has_wearable_asleep,
                "wearable_span_min": wearable_span_min,
                "asleep_min": asleep_min,
                "in_bed_min": total_in_bed,
                "deep_min": deep_min,
                "rem_min": rem_min,
                "core_min": core_min,
                "awake_min": awake_min,
                "primary_source": primary_source,
            }
        )

    per_day: dict[str, dict[str, Any]] = {}
    primary_source_counts: dict[str, int] = defaultdict(int)
    dedup_asleep_sum = 0.0
    days_with_sleep = 0
    days_with_in_bed_only = 0

    for day_key, drafts in drafts_by_day.items():
        primary = max(drafts, key=lambda d: (d["asleep_min"], d["in_bed_min"], -d["start_ts"]))
        total_asleep = sum(d["asleep_min"] for d in drafts)
        total_in_bed = sum(d["in_bed_min"] for d in drafts)

        if total_asleep <= 0:
            days_with_in_bed_only += 1
            per_day[day_key] = {
                "sleep_total_min": np.nan,
                "sleep_rem_min": np.nan,
                "sleep_deep_min": np.nan,
                "sleep_core_min": np.nan,
                "sleep_awake_min": np.nan,
                "sleep_in_bed_min": float(total_in_bed),
                "sleep_efficiency": np.nan,
                "sleep_onset_hour": np.nan,
                "sleep_wake_hour": np.nan,
                "sleep_episode_count": int(len(drafts)),
                "sleep_raw_asleep_min": float(raw_asleep_by_day.get(day_key, 0.0)),
            }
            continue

        days_with_sleep += 1
        if primary["has_wearable_asleep"] and primary["wearable_span_min"] > 0:
            denom = max(primary["wearable_span_min"], primary["asleep_min"] + primary["awake_min"])
            eff = min(1.0, max(0.0, primary["asleep_min"] / denom)) if denom > 0 else np.nan
        else:
            p_in_bed = primary["in_bed_min"]
            eff = min(1.0, max(0.0, primary["asleep_min"] / p_in_bed)) if p_in_bed > 0 else np.nan

        st = primary["first_asleep_local"] or primary["start_local"]
        en = primary["last_asleep_local"] or primary["end_local"]
        onset_hr = st.hour + st.minute / 60.0 + st.second / 3600.0
        if onset_hr < 18.0:
            onset_hr += 24.0
        wake_hr = en.hour + en.minute / 60.0 + en.second / 3600.0

        primary_source_counts[primary["primary_source"]] += 1
        dedup_asleep_sum += float(total_asleep)

        per_day[day_key] = {
            "sleep_total_min": float(total_asleep),
            "sleep_rem_min": float(primary["rem_min"]),
            "sleep_deep_min": float(primary["deep_min"]),
            "sleep_core_min": float(primary["core_min"]),
            "sleep_awake_min": float(primary["awake_min"]),
            "sleep_in_bed_min": float(total_in_bed),
            "sleep_efficiency": float(eff) if np.isfinite(eff) else np.nan,
            "sleep_onset_hour": float(onset_hr),
            "sleep_wake_hour": float(wake_hr),
            "sleep_episode_count": int(len(drafts)),
            "sleep_raw_asleep_min": float(raw_asleep_by_day.get(day_key, float(total_asleep))),
        }

    raw_total_sum = sum(raw_asleep_by_day.values())
    overlap_days = sum(1 for srcs in raw_asleep_sources_by_day.values() if len(srcs) >= 2)
    audit = {
        "policy_version": SLEEP_MERGE_POLICY_VERSION,
        "raw_samples_count": len(valid),
        "days_with_sleep": days_with_sleep,
        "days_with_in_bed_only": days_with_in_bed_only,
        "days_with_multi_source_overlap": overlap_days,
        "raw_asleep_min_sum": round(raw_total_sum, 1),
        "dedup_asleep_min_sum": round(dedup_asleep_sum, 1),
        "prevented_overcount_min": round(max(0.0, raw_total_sum - dedup_asleep_sum), 1),
        "primary_source_counts_raw": dict(sorted(primary_source_counts.items(), key=lambda x: -x[1])),
    }
    return per_day, audit


def _sweep_dedup_intervals(samples: list[IntervalSample]) -> tuple[float, float, bool]:
    """O(K log K) priority sweep-line deduplicating overlapping positive-duration samples."""
    raw_sum = sum(s.value for s in samples)
    positive: list[tuple[float, float, float, int]] = []
    zero_dur: list[IntervalSample] = []

    for s in samples:
        dt = s.end_ts - s.start_ts
        if dt > 0.0:
            positive.append((s.start_ts, s.end_ts, s.value / dt, s.tier))
        else:
            zero_dur.append(s)

    if not positive:
        seen_point: set[tuple[int, float]] = set()
        point_sum = 0.0
        for s in sorted(zero_dur, key=lambda x: (-x.tier, x.start_ts)):
            key = (int(round(s.start_ts)), round(s.value, 4))
            if key not in seen_point:
                seen_point.add(key)
                point_sum += s.value
        return point_sum, raw_sum, len(zero_dur) > len(seen_point)

    events: list[tuple[float, int, int]] = []
    rates: list[float] = []
    tiers: list[int] = []
    sources_per_idx: list[str] = []

    idx = 0
    for s in samples:
        dt = s.end_ts - s.start_ts
        if dt > 0.0:
            rates.append(s.value / dt)
            tiers.append(s.tier)
            sources_per_idx.append(s.norm_source)
            events.append((s.start_ts, 1, idx))
            events.append((s.end_ts, -1, idx))
            idx += 1

    events.sort(key=lambda e: (e[0], e[1]))
    active: set[int] = set()
    prev_ts: float | None = None
    dedup_sum = 0.0
    had_multi_source_overlap = False

    pos = 0
    n_events = len(events)
    while pos < n_events:
        curr_ts = events[pos][0]
        if prev_ts is not None and curr_ts > prev_ts and active:
            dt = curr_ts - prev_ts
            winner = max(active, key=lambda i: (tiers[i], -i))
            dedup_sum += rates[winner] * dt
            if len(active) > 1 and len({sources_per_idx[i] for i in active}) > 1:
                had_multi_source_overlap = True
        while pos < n_events and events[pos][0] == curr_ts:
            _, kind, seg_id = events[pos]
            if kind == 1:
                active.add(seg_id)
            else:
                active.discard(seg_id)
            pos += 1
        prev_ts = curr_ts

    return dedup_sum, raw_sum, had_multi_source_overlap


def _dedup_interval_channel(by_day: dict[str, list[IntervalSample]]) -> tuple[dict[str, float], dict[str, Any]]:
    dedup_by_day: dict[str, float] = {}
    raw_total = 0.0
    dedup_total = 0.0
    overlap_days = 0
    raw_sample_count = 0

    for day_key, samples in by_day.items():
        raw_sample_count += len(samples)
        d_val, r_val, overlapped = _sweep_dedup_intervals(samples)
        dedup_by_day[day_key] = d_val
        raw_total += r_val
        dedup_total += d_val
        if overlapped:
            overlap_days += 1

    audit = {
        "raw_samples_count": raw_sample_count,
        "days_present": len(dedup_by_day),
        "days_with_multi_source_overlap": overlap_days,
        "raw_sum": round(raw_total, 2),
        "dedup_sum": round(dedup_total, 2),
        "prevented_overcount_sum": round(max(0.0, raw_total - dedup_total), 2),
    }
    return dedup_by_day, audit


def _dedup_workouts(workouts: list[WorkoutSample]) -> tuple[dict[str, dict[str, Any]], int, int]:
    """Deduplicate overlapping multi-app workout logs (e.g., Apple Watch + Keep) by tier."""
    if not workouts:
        return {}, 0, 0
    ordered = sorted(workouts, key=lambda w: (-w.tier, w.start_ts, -w.duration_min))
    kept: list[WorkoutSample] = []
    by_day_kept: dict[str, list[WorkoutSample]] = defaultdict(list)

    for w in ordered:
        duplicate = False
        for existing in by_day_kept.get(w.day_key, []):
            overlap = min(w.end_ts, existing.end_ts) - max(w.start_ts, existing.start_ts)
            shorter = min(w.end_ts - w.start_ts, existing.end_ts - existing.start_ts)
            if shorter > 0 and overlap / shorter >= 0.75:
                duplicate = True
                break
        if not duplicate:
            kept.append(w)
            by_day_kept[w.day_key].append(w)

    per_day: dict[str, dict[str, Any]] = {}
    for day_key, items in by_day_kept.items():
        types_set = sorted({i.activity_type.replace("HKWorkoutActivityType", "") for i in items if i.activity_type})
        kcal_vals = [i.active_kcal for i in items if i.active_kcal is not None]
        per_day[day_key] = {
            "workout_count": int(len(items)),
            "workout_duration_min": float(sum(i.duration_min for i in items)),
            "workout_active_kcal": float(sum(kcal_vals)) if kcal_vals else np.nan,
            "has_strength_workout": int(any("StrengthTraining" in i.activity_type for i in items)),
            "has_badminton_workout": int(any("Badminton" in i.activity_type for i in items)),
            "has_running_workout": int(any("Running" in i.activity_type for i in items)),
            "workout_types": ",".join(types_set),
        }

    return per_day, len(workouts), len(kept)


def _open_xml_stream(source_path: Path) -> tuple[zipfile.ZipFile | None, IO[bytes]]:
    if source_path.suffix.lower() == ".zip":
        zf = zipfile.ZipFile(source_path, "r")
        entry = find_export_xml_entry(zf)
        return zf, zf.open(entry, "r")
    return None, source_path.open("rb")


def _apply_bounds_and_masks(df: pd.DataFrame) -> pd.DataFrame:
    """Apply physiological range exclusion checks and build explicit 4-state availability masks."""
    # Establish observed wear-day indicator (strictly excludes Workout-only manual entries without sensor signals)
    wear_cols = [c for c in ("hrv_sdnn_ms", "resting_hr_bpm", "sleep_total_min", "steps_count", "active_energy_kcal", "basal_energy_kcal") if c in df.columns]
    has_wear = pd.Series(False, index=df.index)
    for col in wear_cols:
        has_wear = has_wear | df[col].notna()

    # Check bounds for continuous sensor metrics
    for col, state_col in STATE_CHANNELS:
        if col not in df.columns:
            df[col] = np.nan
        states = np.full(len(df), "missing", dtype=object)
        vals = pd.to_numeric(df[col], errors="coerce")

        if col == "workout_duration_min":
            has_w = df["workout_count"].fillna(0) > 0
            states[has_w.to_numpy()] = "available"
            known_zero_mask = (~has_w) & has_wear
            states[known_zero_mask.to_numpy()] = "knownZero"
            df.loc[known_zero_mask, "workout_duration_min"] = 0.0
            df.loc[known_zero_mask, "workout_count"] = 0.0
            df.loc[known_zero_mask & df["workout_active_kcal"].isna(), "workout_active_kcal"] = 0.0
        else:
            present = vals.notna()
            states[present.to_numpy()] = "available"
            if col in PHYSIOLOGICAL_BOUNDS:
                lo, hi = PHYSIOLOGICAL_BOUNDS[col]
                oob = present & ((vals < lo) | (vals > hi))
                if oob.any():
                    states[oob.to_numpy()] = "excluded"
                    df.loc[oob, col] = np.nan

        df[state_col] = states

    # Reserved eating context mask per Blueprint V5 §11
    df["eating_context_state"] = "missing"
    return df


def build_feature_spec(df: pd.DataFrame) -> dict[str, Any]:
    """Emit versioned schema contract shared conceptually between Python M4 and iOS feature alignment."""
    return {
        "schema_version": FEATURE_SPEC_VERSION,
        "sleep_merge_policy_version": SLEEP_MERGE_POLICY_VERSION,
        "physiological_cutover_hour": PHYSIOLOGICAL_CUTOVER_HOUR,
        "missing_as_zero": False,
        "truth_states": list(VALID_TRUTH_STATES),
        "row_count": int(len(df)),
        "date_range": {
            "start_day_key": str(df["day_key"].iloc[0]) if len(df) else None,
            "end_day_key": str(df["day_key"].iloc[-1]) if len(df) else None,
        },
        "reserved_channels": {
            "eating_context_state": "Reserved eating rhythm mask (fixed 'missing' in M4a; populated once Diet module ships)."
        },
        "columns": {col: str(dtype) for col, dtype in df.dtypes.items()},
    }


def parse_export_to_features(
    export_path: str | Path,
    out_dir: str | Path,
) -> tuple[pd.DataFrame, dict[str, Any], dict[str, Any]]:
    """Stream-parse HealthKit export zip/xml into daily_features.parquet, feature_spec_m4a.json, and dedup_audit.json."""
    src = Path(export_path)
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    source_stats: dict[str, SourceStats] = {}
    median_buckets: dict[str, dict[str, list[float]]] = {
        col: defaultdict(list) for col in MEDIAN_RECORD_TYPES.values()
    }
    interval_buckets: dict[str, dict[str, list[IntervalSample]]] = {
        col: defaultdict(list) for col in INTERVAL_SUM_TYPES.values()
    }
    sleep_samples: list[SleepSample] = []
    workout_samples: list[WorkoutSample] = []
    activity_summaries: dict[str, dict[str, float]] = {}

    export_date_str: str | None = None
    locale_str: str | None = None
    total_elements_scanned = 0

    zf, stream = _open_xml_stream(src)
    try:
        depth = 0
        root: ET.Element | None = None
        for event, elem in ET.iterparse(stream, events=("start", "end")):
            if event == "start":
                if root is None:
                    root = elem
                    locale_str = elem.attrib.get("locale")
                depth += 1
                continue

            depth -= 1
            if depth != 1:
                continue

            total_elements_scanned += 1
            tag = elem.tag

            if tag == "ExportDate":
                export_date_str = elem.attrib.get("value")
            elif tag == "Record":
                attrib = elem.attrib
                rec_type = attrib.get("type", "")
                raw_source = attrib.get("sourceName", "")
                norm_source = normalize_source_name(raw_source)
                start_raw = attrib.get("startDate", "")
                iso_hint = start_raw[:10] if len(start_raw) >= 10 else None
                st_entry = source_stats.get(norm_source)
                if st_entry is None:
                    st_entry = SourceStats(
                        raw_name=raw_source,
                        normalized_name=norm_source,
                        kind=classify_source_kind(norm_source),
                    )
                    source_stats[norm_source] = st_entry
                st_entry.observe(iso_hint, is_workout=False)

                if rec_type in MEDIAN_RECORD_TYPES:
                    col = MEDIAN_RECORD_TYPES[rec_type]
                    try:
                        val = float(attrib.get("value", ""))
                    except ValueError:
                        val = float("nan")
                    norm_val = _normalize_unit_value(col, val, attrib.get("unit"))
                    if norm_val is not None and start_raw:
                        _, _, day_key = parse_hk_timestamp(start_raw)
                        median_buckets[col][day_key].append(norm_val)
                elif rec_type in INTERVAL_SUM_TYPES:
                    col = INTERVAL_SUM_TYPES[rec_type]
                    try:
                        val = float(attrib.get("value", ""))
                    except ValueError:
                        val = float("nan")
                    norm_val = _normalize_unit_value(col, val, attrib.get("unit"))
                    end_raw = attrib.get("endDate", start_raw)
                    if norm_val is not None and norm_val >= 0 and start_raw and end_raw:
                        start_dt, _, day_key = parse_hk_timestamp(start_raw)
                        end_dt, _, _ = parse_hk_timestamp(end_raw)
                        tier = infer_activity_tier(norm_source, attrib.get("device", ""))
                        interval_buckets[col][day_key].append(
                            IntervalSample(
                                start_ts=start_dt.timestamp(),
                                end_ts=max(start_dt.timestamp(), end_dt.timestamp()),
                                value=norm_val,
                                tier=tier,
                                norm_source=norm_source,
                            )
                        )
                elif rec_type == "HKCategoryTypeIdentifierSleepAnalysis":
                    stage = SLEEP_VALUE_TO_STAGE.get(attrib.get("value", ""))
                    end_raw = attrib.get("endDate", "")
                    if stage and start_raw and end_raw:
                        start_dt, start_local, _ = parse_hk_timestamp(start_raw)
                        end_dt, end_local, end_day_key = parse_hk_timestamp(end_raw)
                        tier = infer_sleep_tier(norm_source, attrib.get("device", ""), stage)
                        sleep_samples.append(
                            SleepSample(
                                start_ts=start_dt.timestamp(),
                                end_ts=end_dt.timestamp(),
                                start_local=start_local,
                                end_local=end_local,
                                end_day_key=end_day_key,
                                stage=stage,
                                tier=tier,
                                norm_source=norm_source,
                                order_idx=len(sleep_samples),
                            )
                        )
            elif tag == "Workout":
                attrib = elem.attrib
                raw_source = attrib.get("sourceName", "")
                norm_source = normalize_source_name(raw_source)
                start_raw = attrib.get("startDate", "")
                end_raw = attrib.get("endDate", start_raw)
                iso_hint = start_raw[:10] if len(start_raw) >= 10 else None
                st_entry = source_stats.get(norm_source)
                if st_entry is None:
                    st_entry = SourceStats(
                        raw_name=raw_source,
                        normalized_name=norm_source,
                        kind=classify_source_kind(norm_source),
                    )
                    source_stats[norm_source] = st_entry
                st_entry.observe(iso_hint, is_workout=True)

                if start_raw:
                    start_dt, _, day_key = parse_hk_timestamp(start_raw)
                    end_dt, _, _ = parse_hk_timestamp(end_raw) if end_raw else (start_dt, None, day_key)
                    try:
                        dur_raw = float(attrib.get("duration", "0"))
                    except ValueError:
                        dur_raw = 0.0
                    dur_unit = attrib.get("durationUnit", "min").lower()
                    if dur_unit in {"s", "sec"}:
                        dur_min = dur_raw / 60.0
                    elif dur_unit in {"hr", "h"}:
                        dur_min = dur_raw * 60.0
                    else:
                        dur_min = dur_raw

                    active_kcal: float | None = None
                    for child in elem:
                        if child.tag == "WorkoutStatistics" and child.attrib.get("type") == "HKQuantityTypeIdentifierActiveEnergyBurned":
                            try:
                                s_val = float(child.attrib.get("sum", ""))
                                conv = _normalize_unit_value("active_energy_kcal", s_val, child.attrib.get("unit"))
                                if conv is not None:
                                    active_kcal = (active_kcal or 0.0) + conv
                            except ValueError:
                                pass
                    if active_kcal is None and "totalEnergyBurned" in attrib:
                        try:
                            s_val = float(attrib["totalEnergyBurned"])
                            active_kcal = _normalize_unit_value(
                                "active_energy_kcal", s_val, attrib.get("totalEnergyBurnedUnit")
                            )
                        except ValueError:
                            pass

                    workout_samples.append(
                        WorkoutSample(
                            day_key=day_key,
                            start_ts=start_dt.timestamp(),
                            end_ts=max(start_dt.timestamp(), end_dt.timestamp()),
                            duration_min=max(0.0, dur_min),
                            active_kcal=active_kcal,
                            activity_type=attrib.get("workoutActivityType", ""),
                            tier=infer_activity_tier(norm_source, attrib.get("device", "")),
                            norm_source=norm_source,
                        )
                    )
            elif tag == "ActivitySummary":
                attrib = elem.attrib
                dc = attrib.get("dateComponents")
                if dc and len(dc) == 10:
                    entry: dict[str, float] = {}
                    for xml_k, out_k in (
                        ("activeEnergyBurned", "activity_summary_active_kcal"),
                        ("appleExerciseTime", "activity_summary_exercise_min"),
                        ("appleStandHours", "activity_summary_stand_hours"),
                    ):
                        raw_v = attrib.get(xml_k)
                        if raw_v is not None:
                            try:
                                entry[out_k] = float(raw_v)
                            except ValueError:
                                pass
                    if entry:
                        activity_summaries[dc] = entry

            elem.clear()
            if root is not None:
                root.clear()
    finally:
        stream.close()
        if zf is not None:
            zf.close()

    # Merge sleep and deduplicate interval / workout streams
    sleep_by_day, sleep_audit = _merge_sleep_policy_v1(sleep_samples)
    steps_by_day, steps_audit = _dedup_interval_channel(interval_buckets["steps_count"])
    active_kcal_by_day, energy_audit = _dedup_interval_channel(interval_buckets["active_energy_kcal"])
    basal_kcal_by_day, _ = _dedup_interval_channel(interval_buckets["basal_energy_kcal"])
    daylight_by_day, _ = _dedup_interval_channel(interval_buckets["time_in_daylight_min"])
    workouts_by_day, raw_workouts_n, dedup_workouts_n = _dedup_workouts(workout_samples)

    all_day_keys: set[str] = set()
    for bucket in median_buckets.values():
        all_day_keys.update(bucket.keys())
    all_day_keys.update(sleep_by_day.keys())
    all_day_keys.update(steps_by_day.keys())
    all_day_keys.update(active_kcal_by_day.keys())
    all_day_keys.update(basal_kcal_by_day.keys())
    all_day_keys.update(workouts_by_day.keys())
    all_day_keys.update(activity_summaries.keys())

    if not all_day_keys:
        df = pd.DataFrame(columns=["day_key"])
    else:
        min_day = date.fromisoformat(min(all_day_keys))
        max_day = date.fromisoformat(max(all_day_keys))
        calendar_days = [
            (min_day + timedelta(days=offset)).isoformat()
            for offset in range((max_day - min_day).days + 1)
        ]

        rows: list[dict[str, Any]] = []
        for dk in calendar_days:
            row: dict[str, Any] = {"day_key": dk}
            for col, bucket in median_buckets.items():
                vals = bucket.get(dk)
                row[col] = float(statistics.median(vals)) if vals else np.nan
            row["steps_count"] = float(steps_by_day[dk]) if dk in steps_by_day else np.nan
            row["active_energy_kcal"] = float(active_kcal_by_day[dk]) if dk in active_kcal_by_day else np.nan
            row["basal_energy_kcal"] = float(basal_kcal_by_day[dk]) if dk in basal_kcal_by_day else np.nan
            row["time_in_daylight_min"] = float(daylight_by_day[dk]) if dk in daylight_by_day else np.nan

            sl = sleep_by_day.get(dk)
            if sl:
                row.update(sl)
            else:
                for k in (
                    "sleep_total_min",
                    "sleep_rem_min",
                    "sleep_deep_min",
                    "sleep_core_min",
                    "sleep_awake_min",
                    "sleep_in_bed_min",
                    "sleep_efficiency",
                    "sleep_onset_hour",
                    "sleep_wake_hour",
                    "sleep_raw_asleep_min",
                ):
                    row[k] = np.nan
                row["sleep_episode_count"] = 0

            wk = workouts_by_day.get(dk)
            if wk:
                row.update(wk)
            else:
                row["workout_count"] = 0.0
                row["workout_duration_min"] = np.nan
                row["workout_active_kcal"] = np.nan
                row["has_strength_workout"] = 0
                row["has_badminton_workout"] = 0
                row["has_running_workout"] = 0
                row["workout_types"] = ""

            act = activity_summaries.get(dk)
            if act:
                row.update(act)
            else:
                row["activity_summary_active_kcal"] = np.nan
                row["activity_summary_exercise_min"] = np.nan
                row["activity_summary_stand_hours"] = np.nan

            rows.append(row)

        df = pd.DataFrame(rows)
        df = _apply_bounds_and_masks(df)

    # Cross-check ActivitySummary active calories vs Watch-deduplicated active energy
    if len(df):
        both = df["active_energy_kcal"].notna() & df["activity_summary_active_kcal"].notna()
        if both.any():
            diff = (df.loc[both, "active_energy_kcal"] - df.loc[both, "activity_summary_active_kcal"]).abs()
            energy_audit["activity_summary_overlap_days"] = int(both.sum())
            energy_audit["activity_summary_median_abs_diff_kcal"] = round(float(diff.median()), 1)

    dedup_audit = build_dedup_audit(
        source_stats=source_stats,
        sleep_audit=sleep_audit,
        steps_audit=steps_audit,
        energy_audit={**energy_audit, "workout_raw_count": raw_workouts_n, "workout_dedup_count": dedup_workouts_n},
        export_metadata={
            "export_date": export_date_str,
            "locale": locale_str,
            "top_elements_scanned": total_elements_scanned,
            "calendar_span_days": int(len(df)),
        },
    )

    spec = build_feature_spec(df)

    parquet_path = out / "daily_features.parquet"
    df.to_parquet(parquet_path, index=False)
    (out / "feature_spec_m4a.json").write_text(
        json.dumps(spec, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (out / "dedup_audit.json").write_text(
        json.dumps(dedup_audit, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    return df, spec, dedup_audit
