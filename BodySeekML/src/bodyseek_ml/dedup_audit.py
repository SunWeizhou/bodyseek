"""Source inventory, privacy-preserving device anonymization, and overlap deduplication audit."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

SAFE_GENERIC_APP_NAMES: frozenset[str] = frozenset(
    {
        "AutoSleep",
        "Bevel",
        "Zepp Life",
        "Keep",
        "米家",
        "训记",
        "健康",
        "Health",
        "健身",
        "Fitness",
        "番茄ToDo",
        "血氧",
        "移动心电图房颤提示软件",
        "手记",
        "时钟",
        "Clock",
    }
)


def normalize_source_name(raw_name: str | None) -> str:
    """Normalize NBSP/zero-width spaces and collapse whitespace in a HealthKit sourceName."""
    if not raw_name:
        return "Unknown Source"
    cleaned = raw_name.replace("\xa0", " ").replace("\u200b", "")
    return " ".join(cleaned.split()) or "Unknown Source"


def classify_source_kind(normalized_name: str) -> str:
    """Classify normalized HealthKit sourceName without excluding historical device names."""
    lower = normalized_name.lower()
    if "apple watch" in lower:
        return "apple_watch"
    if "iphone" in lower:
        return "iphone"
    if "ipad" in lower:
        return "ipad"
    if "autosleep" in lower:
        return "autosleep"
    if normalized_name in SAFE_GENERIC_APP_NAMES:
        return "system_health" if normalized_name in {"健康", "Health", "健身", "Fitness", "时钟", "Clock", "血氧", "手记", "移动心电图房颤提示软件"} else "third_party_app"
    return "third_party_app"


def infer_sleep_tier(normalized_name: str, device_str: str = "", stage: str = "") -> int:
    """Mirror Swift SleepSourceTier precedence: Watch (3) > AutoSleep (2) > 3P wearable (1) > iPhone/inBed (0)."""
    lower = normalized_name.lower()
    dev_lower = (device_str or "").lower()
    if "apple watch" in lower or "watch" in dev_lower:
        return 3
    if "autosleep" in lower:
        return 2
    if normalized_name in {"健康", "Health", "时钟", "Clock"} and stage in {"deep", "core", "rem"}:
        return 3
    if "iphone" in lower or normalized_name in {"健康", "Health", "时钟", "Clock"}:
        return 0
    return 1


def infer_activity_tier(normalized_name: str, device_str: str = "") -> int:
    """Priority tier for overlapping interval quantity samples (StepCount / ActiveEnergyBurned)."""
    lower = normalized_name.lower()
    dev_lower = (device_str or "").lower()
    if "apple watch" in lower or "watch" in dev_lower:
        return 3
    if "fitness" in lower or normalized_name in {"健身", "Keep", "训记"}:
        return 2
    if "zepp" in lower or "bevel" in lower or "autosleep" in lower or "米家" in lower:
        return 1
    return 0


class SourceAnonymizer:
    """Deterministically map personal device names (Watch/iPhone/iPad) to anonymous aliases for public reports."""

    def __init__(self) -> None:
        self._mapping: dict[str, str] = {}
        self._counters: dict[str, int] = {}

    def alias_for(self, raw_name: str, total_count_rank: int | None = None) -> str:
        norm = normalize_source_name(raw_name)
        if norm in self._mapping:
            return self._mapping[norm]

        kind = classify_source_kind(norm)
        if norm in SAFE_GENERIC_APP_NAMES:
            alias = norm
        elif kind == "apple_watch":
            idx = self._next_index("Apple Watch")
            alias = f"Apple Watch #{idx}"
        elif kind == "iphone":
            idx = self._next_index("iPhone")
            alias = f"iPhone #{idx}"
        elif kind == "ipad":
            idx = self._next_index("iPad")
            alias = f"iPad #{idx}"
        else:
            idx = self._next_index("Third-Party Source")
            alias = f"Third-Party Source #{idx}"

        self._mapping[norm] = alias
        return alias

    def _next_index(self, prefix: str) -> int:
        next_val = self._counters.get(prefix, 0) + 1
        self._counters[prefix] = next_val
        return next_val


@dataclass
class SourceStats:
    raw_name: str
    normalized_name: str
    kind: str
    record_count: int = 0
    workout_count: int = 0
    first_date: str | None = None
    last_date: str | None = None

    def observe(self, iso_date: str | None, is_workout: bool = False) -> None:
        if is_workout:
            self.workout_count += 1
        else:
            self.record_count += 1
        if iso_date and len(iso_date) == 10:
            if self.first_date is None or iso_date < self.first_date:
                self.first_date = iso_date
            if self.last_date is None or iso_date > self.last_date:
                self.last_date = iso_date


def build_dedup_audit(
    source_stats: dict[str, SourceStats],
    sleep_audit: dict[str, Any],
    steps_audit: dict[str, Any],
    energy_audit: dict[str, Any],
    export_metadata: dict[str, Any],
) -> dict[str, Any]:
    """Build both full local dedup audit (for gitignored JSON) and anonymized summary (for report)."""
    ordered = sorted(
        source_stats.values(),
        key=lambda s: (-(s.record_count + s.workout_count), s.normalized_name),
    )

    anonymizer = SourceAnonymizer()
    # Reserve indices deterministically in descending volume order
    for item in ordered:
        anonymizer.alias_for(item.raw_name)

    full_sources: list[dict[str, Any]] = []
    anonymized_sources: list[dict[str, Any]] = []

    watch_items = [s for s in ordered if s.kind == "apple_watch"]
    dominant_watch_prefix = _owner_prefix(watch_items[0].normalized_name) if watch_items else None

    for item in ordered:
        alias = anonymizer.alias_for(item.raw_name)
        needs_ownership_check = False
        note = ""
        if item.kind == "apple_watch":
            prefix = _owner_prefix(item.normalized_name)
            if dominant_watch_prefix and prefix != dominant_watch_prefix:
                needs_ownership_check = True
                note = "不同命名历史手表来源，管线按时间窗去重保留，请用户确认是否本人旧设备"
            else:
                note = "主用或同命名 Apple Watch"
        elif item.kind == "iphone":
            note = "手机来源；与手表时间窗重叠时由 sleep-merge-v1 / 步数优先级自动退让"
        elif item.kind == "autosleep":
            note = "AutoSleep 睡眠分析来源；无 Watch 原生分期或兼容补缺时参与合并"
        elif item.kind in {"system_health", "third_party_app"}:
            note = "三方/系统 App 来源，保留元数据并在睡眠/步数/能量处参与优先级去重"

        base_entry = {
            "kind": item.kind,
            "record_count": item.record_count,
            "workout_count": item.workout_count,
            "total_items": item.record_count + item.workout_count,
            "first_date": item.first_date,
            "last_date": item.last_date,
            "needs_ownership_confirmation": needs_ownership_check,
            "audit_note": note,
        }
        full_sources.append(
            {
                "raw_source_name": item.raw_name,
                "normalized_source_name": item.normalized_name,
                "anonymized_alias": alias,
                **base_entry,
            }
        )
        anonymized_sources.append(
            {
                "anonymized_alias": alias,
                **base_entry,
            }
        )

    return {
        "schema_version": "dedup-audit-v1",
        "export_metadata": export_metadata,
        "total_distinct_sources": len(ordered),
        "sources_full": full_sources,
        "sources_anonymized": anonymized_sources,
        "sleep_dedup": sleep_audit,
        "steps_dedup": steps_audit,
        "active_energy_dedup": energy_audit,
    }


def _owner_prefix(normalized_name: str) -> str:
    lower = normalized_name.lower()
    idx = lower.find("apple watch")
    return normalized_name[:idx].strip() if idx > 0 else normalized_name
