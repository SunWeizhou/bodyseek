import BodySeekCore
import Foundation
import GRDB
import os

public enum DayMetricField: String, CaseIterable, Sendable {
    case hrvMs = "hrv_ms"
    case restingHeartRateBpm = "resting_hr_bpm"
    case respiratoryRateBrpm = "resp_rate_brpm"
    case wristTempDeltaC = "wrist_temp_delta_c"
    case oxygenSaturationPct = "spo2_pct"
    case walkingHeartRateAvgBpm = "walking_hr_avg_bpm"
    case vo2MaxMlKgMin = "vo2max_ml_kg_min"
    case heartRateRecovery1MinBpm = "hrr_1min_bpm"
    case bodyMassKg = "body_mass_kg"
    case physicalEffortKcalPerKgHr = "physical_effort_kcal_kg_hr"
    case sleepAsleepMinutes = "sleep_asleep_min"
    case sleepInBedMinutes = "sleep_in_bed_min"
    case deepMinutes = "sleep_deep_min"
    case remMinutes = "sleep_rem_min"
    case coreMinutes = "sleep_core_min"
    case awakeMinutes = "sleep_awake_min"
    case activeEnergyKcal = "active_energy_kcal"
    case exerciseMinutes = "exercise_minutes"
    case steps = "steps"
    case daytimeMeanHeartRateBpm = "daytime_mean_hr_bpm"
    case daytimeMaxHeartRateBpm = "daytime_max_hr_bpm"
    case hasAuthorizedHealthData = "has_authorized_health_data"
}

/// Typed, transactional repository over GRDB 7 covering all 15 V5 §5.2 tables and continuity stores.
public final class BodySeekRepository: Sendable {
    public let database: BodySeekDatabase
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "BodySeekRepository")

    public init(database: BodySeekDatabase) {
        self.database = database
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func encodeJSONString<T: Encodable>(_ value: T, label: String) throws -> String {
        let data = try makeEncoder().encode(value)
        guard let str = String(data: data, encoding: .utf8) else {
            throw BodySeekDatabaseError.invalidJSONEncoding(context: label)
        }
        return str
    }

    private static func decodeJSON<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw BodySeekDatabaseError.invalidJSONEncoding(context: "\(T.self)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Table Introspection

    public func existingTableNames() async throws -> Set<String> {
        try await database.writer.read { db in
            let rows = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"
            )
            return Set(rows)
        }
    }

    // MARK: - Sync Anchors

    public func loadSyncAnchor(type: String) async throws -> SyncAnchorState? {
        try await database.writer.read { db in
            try Self.loadSyncAnchorSync(db: db, type: type)
        }
    }

    public func saveSyncAnchor(_ state: SyncAnchorState) async throws {
        try await database.writer.write { db in
            try Self.saveSyncAnchorSync(db: db, state: state)
        }
    }

    static func loadSyncAnchorSync(db: Database, type: String) throws -> SyncAnchorState? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT type, anchor, backfill_cursor, updated_at FROM sync_anchor WHERE type = ?",
            arguments: [type]
        ) else {
            return nil
        }
        let cursorString: String? = row["backfill_cursor"]
        let updatedAtSec: Double = row["updated_at"]
        return SyncAnchorState(
            type: row["type"],
            anchorData: row["anchor"],
            backfillCursor: cursorString.flatMap(DayKey.init(isoString:)),
            updatedAt: Date(timeIntervalSince1970: updatedAtSec)
        )
    }

    static func saveSyncAnchorSync(db: Database, state: SyncAnchorState) throws {
        try db.execute(
            sql: """
            INSERT INTO sync_anchor (type, anchor, backfill_cursor, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(type) DO UPDATE SET
                anchor = excluded.anchor,
                backfill_cursor = excluded.backfill_cursor,
                updated_at = excluded.updated_at
            """,
            arguments: [
                state.type,
                state.anchorData,
                state.backfillCursor?.isoString,
                state.updatedAt.timeIntervalSince1970,
            ]
        )
    }

    // MARK: - Day Metrics, Hourly Metrics, Sleep & Workouts

    private static func invalidateComputedArtifactsSync(
        db: Database,
        dayKeys: Set<DayKey>,
        calendar: Calendar = .current
    ) throws {
        guard !dayKeys.isEmpty else { return }
        var affected = Set<String>()
        for key in dayKeys {
            let start = key.calendarDayStart(calendar: calendar)
            for offset in 0...28 {
                if let date = calendar.date(byAdding: .day, value: offset, to: start) {
                    affected.insert(DayKey.fromCalendarDay(date, calendar: calendar).isoString)
                }
            }
        }
        let affectedKeys = Array(affected)
        // Stay below conservative SQLite host-parameter limits on large backfills.
        let chunkSize = 500
        var offset = 0
        while offset < affectedKeys.count {
            let chunk = affectedKeys[offset..<min(offset + chunkSize, affectedKeys.count)]
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM day_computed_artifact WHERE day_key IN (\(placeholders))",
                arguments: StatementArguments(Array(chunk))
            )
            offset += chunk.count
        }
    }

    public func upsertDayMetrics(_ records: [DayMetricRecord]) async throws {
        guard !records.isEmpty else { return }
        try await database.writer.write { db in
            var dirtyKeys = Set<DayKey>()
            for record in records {
                dirtyKeys.insert(record.dayKey)
                let sourcesJSON = try Self.encodeJSONString(record.sources, label: "DayMetricRecord.sources")
                try db.execute(
                    sql: """
                    INSERT INTO day_metric (day_key, metric, value, state, reason, coverage, sources_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(day_key, metric) DO UPDATE SET
                        value = excluded.value,
                        state = excluded.state,
                        reason = excluded.reason,
                        coverage = excluded.coverage,
                        sources_json = excluded.sources_json
                    """,
                    arguments: [
                        record.dayKey.isoString,
                        record.metric,
                        record.value,
                        record.state.rawValue,
                        record.reason,
                        record.coverage,
                        sourcesJSON,
                    ]
                )
            }
            try Self.invalidateComputedArtifactsSync(db: db, dayKeys: dirtyKeys)
        }
    }

    public func upsertHourlyMetrics(_ records: [HourlyMetricRecord]) async throws {
        guard !records.isEmpty else { return }
        try await database.writer.write { db in
            for record in records {
                try db.execute(
                    sql: """
                    INSERT INTO hourly_metric (hour_start, metric, value, coverage)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(hour_start, metric) DO UPDATE SET
                        value = excluded.value,
                        coverage = excluded.coverage
                    """,
                    arguments: [
                        record.hourStart.timeIntervalSince1970,
                        record.metric,
                        record.value,
                        record.coverage,
                    ]
                )
            }
        }
    }

    public func loadHourlyMetrics(metric: String, from start: Date, to end: Date) async throws -> [HourlyMetricRecord] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT hour_start, metric, value, coverage
                FROM hourly_metric
                WHERE metric = ? AND hour_start >= ? AND hour_start <= ?
                ORDER BY hour_start ASC
                """,
                arguments: [metric, start.timeIntervalSince1970, end.timeIntervalSince1970]
            )
            return rows.map { row in
                HourlyMetricRecord(
                    hourStart: Date(timeIntervalSince1970: row["hour_start"]),
                    metric: row["metric"],
                    value: row["value"],
                    coverage: row["coverage"]
                )
            }
        }
    }

    public func saveSleepEpisodes(_ episodes: [MergedSleepEpisode], replacingDays days: Set<DayKey>) async throws {
        try await database.writer.write { db in
            for day in days {
                try db.execute(
                    sql: "DELETE FROM sleep_episode WHERE day_key = ?",
                    arguments: [day.isoString]
                )
            }
            for episode in episodes {
                let primarySourceJSON = try Self.encodeJSONString(episode.primarySource, label: "sleep.primarySource")
                let sourcesJSON = try Self.encodeJSONString(episode.sources, label: "sleep.sources")
                let stagesJSON = try Self.encodeJSONString(episode.segments, label: "sleep.segments")
                try db.execute(
                    sql: """
                    INSERT INTO sleep_episode (
                        id, day_key, start, end, is_primary, source, sources_json,
                        merge_policy_version, stages_json, asleep_minutes, in_bed_minutes,
                        deep_minutes, rem_minutes, core_minutes, awake_minutes, efficiency
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        day_key = excluded.day_key,
                        start = excluded.start,
                        end = excluded.end,
                        is_primary = excluded.is_primary,
                        source = excluded.source,
                        sources_json = excluded.sources_json,
                        merge_policy_version = excluded.merge_policy_version,
                        stages_json = excluded.stages_json,
                        asleep_minutes = excluded.asleep_minutes,
                        in_bed_minutes = excluded.in_bed_minutes,
                        deep_minutes = excluded.deep_minutes,
                        rem_minutes = excluded.rem_minutes,
                        core_minutes = excluded.core_minutes,
                        awake_minutes = excluded.awake_minutes,
                        efficiency = excluded.efficiency
                    """,
                    arguments: [
                        episode.id,
                        episode.dayKey.isoString,
                        episode.startDate.timeIntervalSince1970,
                        episode.endDate.timeIntervalSince1970,
                        episode.isPrimarySleep,
                        primarySourceJSON,
                        sourcesJSON,
                        episode.mergePolicyVersion.description,
                        stagesJSON,
                        episode.asleepMinutes,
                        episode.inBedMinutes,
                        episode.deepMinutes,
                        episode.remMinutes,
                        episode.coreMinutes,
                        episode.awakeMinutes,
                        episode.efficiency,
                    ]
                )
            }
        }
    }

    public func loadDeletedWorkoutUUIDs() async throws -> Set<String> {
        try await database.writer.read { db in
            try Self.deletedWorkoutUUIDs(in: db)
        }
    }

    private static func deletedWorkoutUUIDs(in db: Database) throws -> Set<String> {
        try Set(String.fetchAll(db, sql: "SELECT uuid FROM deleted_healthkit_workout"))
    }

    public func applyWorkoutDeletions(_ uuids: Set<String>) async throws -> Set<DayKey> {
        guard !uuids.isEmpty else { return [] }
        return try await database.writer.write { db in
            var affected: Set<DayKey> = []
            for uuid in uuids.map({ $0.lowercased() }) {
                let day = try String.fetchOne(db, sql: "SELECT day_key FROM workout WHERE lower(hk_uuid) = ?", arguments: [uuid])
                try db.execute(
                    sql: "INSERT OR IGNORE INTO deleted_healthkit_workout(uuid, day_key) VALUES (?, ?)",
                    arguments: [uuid, day]
                )
                let affectedDay = try String.fetchOne(db, sql: "SELECT day_key FROM deleted_healthkit_workout WHERE uuid = ?", arguments: [uuid])
                if let affectedDay, let key = DayKey(isoString: affectedDay) { affected.insert(key) }
                try db.execute(sql: "DELETE FROM workout WHERE lower(hk_uuid) = ?", arguments: [uuid])
            }
            return affected
        }
    }

    public func upsertWorkouts(_ workouts: [StoredWorkoutRecord], symbolByUUID: [String: String] = [:]) async throws {
        guard !workouts.isEmpty else { return }
        try await database.writer.write { db in
            let deleted = try Self.deletedWorkoutUUIDs(in: db)
            for workout in workouts where !deleted.contains(workout.hkUUID.lowercased()) {
                let dayKey = workout.start.physiologicalDayKey()
                let zonesJSON: String? = if let zones = workout.zones {
                    try Self.encodeJSONString(zones, label: "workout.zones")
                } else {
                    nil
                }
                let symbol = symbolByUUID[workout.hkUUID] ?? "figure.mixed.cardio"
                try db.execute(
                    sql: """
                    INSERT INTO workout (
                        hk_uuid, day_key, type, symbol_name, start, end, energy,
                        avg_hr, zones_json, effort_user, effort_estimated, review_state
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(hk_uuid) DO UPDATE SET
                        day_key = excluded.day_key,
                        type = excluded.type,
                        symbol_name = excluded.symbol_name,
                        start = excluded.start,
                        end = excluded.end,
                        energy = excluded.energy,
                        avg_hr = excluded.avg_hr,
                        zones_json = COALESCE(excluded.zones_json, workout.zones_json),
                        effort_user = COALESCE(excluded.effort_user, workout.effort_user),
                        effort_estimated = COALESCE(excluded.effort_estimated, workout.effort_estimated)
                    """,
                    arguments: [
                        workout.hkUUID,
                        dayKey.isoString,
                        workout.type,
                        symbol,
                        workout.start.timeIntervalSince1970,
                        workout.end.timeIntervalSince1970,
                        workout.energy,
                        workout.avgHR,
                        zonesJSON,
                        workout.effortUser,
                        workout.effortEstimated,
                        workout.reviewState.rawValue,
                    ]
                )
            }
        }
    }

    public func loadWorkouts(limit: Int? = nil) async throws -> [StoredWorkoutRecord] {
        try await database.writer.read { db in
            let sql = limit.map {
                "SELECT hk_uuid, type, start, end, energy, avg_hr, zones_json, effort_user, effort_estimated, review_state FROM workout ORDER BY start DESC LIMIT \($0)"
            } ?? "SELECT hk_uuid, type, start, end, energy, avg_hr, zones_json, effort_user, effort_estimated, review_state FROM workout ORDER BY start DESC"
            let rows = try Row.fetchAll(db, sql: sql)
            return try rows.map(Self.decodeWorkoutRow)
        }
    }

    private static func decodeWorkoutRow(_ row: Row) throws -> StoredWorkoutRecord {
        let zonesJSON: String? = row["zones_json"]
        let zones: WorkoutHeartRateZones? = try zonesJSON.map {
            try Self.decodeJSON($0, as: WorkoutHeartRateZones.self)
        }
        let reviewRaw: String = row["review_state"]
        return StoredWorkoutRecord(
            hkUUID: row["hk_uuid"],
            type: row["type"],
            start: Date(timeIntervalSince1970: row["start"]),
            end: Date(timeIntervalSince1970: row["end"]),
            energy: row["energy"],
            avgHR: row["avg_hr"],
            zones: zones,
            effortUser: row["effort_user"],
            effortEstimated: row["effort_estimated"],
            reviewState: WorkoutReviewState(rawValue: reviewRaw) ?? .unreviewed
        )
    }

    // MARK: - High-Level Raw Day + Computed Snapshot Persistence

    public func saveDailyRawMetrics(_ rawDays: [DailyRawMetrics], calendar: Calendar = .current) async throws {
        guard !rawDays.isEmpty else { return }
        try await database.writer.write { db in
            let deletedWorkoutUUIDs = try Self.deletedWorkoutUUIDs(in: db)
            var dirtyKeys = Set<DayKey>()
            for raw in rawDays {
                let dayKey = raw.dayKey ?? raw.date.physiologicalDayKey(cutoverHour: 4, timeZone: calendar.timeZone)
                dirtyKeys.insert(dayKey)
                let sources = raw.sourceNames.enumerated().map { idx, name in
                    SourceRef(name: name, priority: max(0, 100 - idx))
                }
                let sourcesJSON = try Self.encodeJSONString(sources, label: "DailyRawMetrics.sources")

                func upsertScalar(_ field: DayMetricField, _ value: Double?) throws {
                    let state: ObservationStateTag
                    let reason: String?
                    if let value {
                        state = (field == .activeEnergyKcal || field == .exerciseMinutes || field == .steps) && value == 0
                            ? .knownZero
                            : .available
                        reason = state == .knownZero ? "当日零活动" : nil
                    } else {
                        state = .missing
                        reason = "无样本"
                    }
                    try db.execute(
                        sql: """
                        INSERT INTO day_metric (day_key, metric, value, state, reason, coverage, sources_json)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(day_key, metric) DO UPDATE SET
                            value = excluded.value,
                            state = excluded.state,
                            reason = excluded.reason,
                            coverage = excluded.coverage,
                            sources_json = excluded.sources_json
                        """,
                        arguments: [
                            dayKey.isoString,
                            field.rawValue,
                            value,
                            state.rawValue,
                            reason,
                            value == nil ? 0.0 : 1.0,
                            sourcesJSON,
                        ]
                    )
                }

                try upsertScalar(.hrvMs, raw.hrvMs)
                try upsertScalar(.restingHeartRateBpm, raw.restingHeartRateBpm)
                try upsertScalar(.respiratoryRateBrpm, raw.respiratoryRateBrpm)
                try upsertScalar(.wristTempDeltaC, raw.wristTempDeltaC)
                try upsertScalar(.oxygenSaturationPct, raw.oxygenSaturationPct)
                try upsertScalar(.walkingHeartRateAvgBpm, raw.walkingHeartRateAvgBpm)
                try upsertScalar(.vo2MaxMlKgMin, raw.vo2MaxMlKgMin)
                try upsertScalar(.heartRateRecovery1MinBpm, raw.heartRateRecovery1MinBpm)
                try upsertScalar(.bodyMassKg, raw.bodyMassKg)
                try upsertScalar(.physicalEffortKcalPerKgHr, raw.physicalEffortKcalPerKgHr)
                try upsertScalar(.sleepAsleepMinutes, raw.sleepAsleepMinutes.map(Double.init))
                try upsertScalar(.sleepInBedMinutes, raw.sleepInBedMinutes.map(Double.init))
                try upsertScalar(.deepMinutes, raw.deepMinutes.map(Double.init))
                try upsertScalar(.remMinutes, raw.remMinutes.map(Double.init))
                try upsertScalar(.coreMinutes, raw.coreMinutes.map(Double.init))
                try upsertScalar(.awakeMinutes, raw.awakeMinutes.map(Double.init))
                try upsertScalar(.activeEnergyKcal, raw.activeEnergyKcal)
                try upsertScalar(.exerciseMinutes, raw.exerciseMinutes.map(Double.init))
                try upsertScalar(.steps, raw.steps.map(Double.init))
                try upsertScalar(.daytimeMeanHeartRateBpm, raw.daytimeMeanHeartRateBpm)
                try upsertScalar(.daytimeMaxHeartRateBpm, raw.daytimeMaxHeartRateBpm)
                try upsertScalar(.hasAuthorizedHealthData, raw.hasAuthorizedHealthData ? 1.0 : 0.0)

                if let sleepStart = raw.sleepStart, let sleepEnd = raw.sleepEnd, sleepEnd > sleepStart {
                    let stagesJSON = try Self.encodeJSONString(raw.sleepSegments, label: "raw.sleepSegments")
                    let primary = sources.first ?? SourceRef(name: "Apple 健康", priority: 100)
                    let primaryJSON = try Self.encodeJSONString(primary, label: "sleep.primary")
                    let episodeID = "\(dayKey.isoString)_\(Int(sleepStart.timeIntervalSince1970))"
                    let efficiency: Double? = if let asleep = raw.sleepAsleepMinutes, let inBed = raw.sleepInBedMinutes, inBed > 0 {
                        min(1.0, max(0.0, Double(asleep) / Double(inBed)))
                    } else {
                        nil
                    }
                    try db.execute(
                        sql: "DELETE FROM sleep_episode WHERE day_key = ?",
                        arguments: [dayKey.isoString]
                    )
                    try db.execute(
                        sql: """
                        INSERT INTO sleep_episode (
                            id, day_key, start, end, is_primary, source, sources_json,
                            merge_policy_version, stages_json, asleep_minutes, in_bed_minutes,
                            deep_minutes, rem_minutes, core_minutes, awake_minutes, efficiency
                        )
                        VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        arguments: [
                            episodeID,
                            dayKey.isoString,
                            sleepStart.timeIntervalSince1970,
                            sleepEnd.timeIntervalSince1970,
                            primaryJSON,
                            sourcesJSON,
                            AlgorithmVersion.sleepMergeV1.description,
                            stagesJSON,
                            raw.sleepAsleepMinutes ?? 0,
                            raw.sleepInBedMinutes ?? 0,
                            raw.deepMinutes ?? 0,
                            raw.remMinutes ?? 0,
                            raw.coreMinutes ?? 0,
                            raw.awakeMinutes ?? 0,
                            efficiency,
                        ]
                    )
                }

                for workout in raw.workouts {
                    let hkUUID = (workout.healthKitUUID ?? workout.id).uuidString
                    guard !deletedWorkoutUUIDs.contains(hkUUID.lowercased()) else { continue }
                    let zonesJSON: String? = if let z = workout.heartRateZones {
                        try Self.encodeJSONString(z, label: "workout.zones")
                    } else {
                        nil
                    }
                    let end = workout.endDate
                    try db.execute(
                        sql: """
                        INSERT INTO workout (
                            hk_uuid, day_key, type, symbol_name, start, end, energy,
                            avg_hr, zones_json, effort_user, effort_estimated, review_state
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(hk_uuid) DO UPDATE SET
                            day_key = excluded.day_key,
                            type = excluded.type,
                            symbol_name = excluded.symbol_name,
                            start = excluded.start,
                            end = excluded.end,
                            energy = excluded.energy,
                            avg_hr = excluded.avg_hr,
                            zones_json = excluded.zones_json,
                            effort_user = COALESCE(excluded.effort_user, workout.effort_user),
                            effort_estimated = COALESCE(excluded.effort_estimated, workout.effort_estimated)
                        """,
                        arguments: [
                            hkUUID,
                            dayKey.isoString,
                            workout.activityName,
                            workout.symbolName,
                            workout.startDate.timeIntervalSince1970,
                            end.timeIntervalSince1970,
                            workout.activeEnergyKcal,
                            workout.averageHeartRate,
                            zonesJSON,
                            workout.effortScore,
                            workout.estimatedEffortScore,
                            WorkoutReviewState.unreviewed.rawValue,
                        ]
                    )
                }
            }
            try Self.invalidateComputedArtifactsSync(db: db, dayKeys: dirtyKeys, calendar: calendar)
        }
    }

    public func loadRawDays(from startKey: DayKey? = nil, to endKey: DayKey? = nil, calendar: Calendar = .current) async throws -> [DailyRawMetrics] {
        try await database.writer.read { db in
            try Self.loadRawDaysSync(db: db, from: startKey, to: endKey, calendar: calendar)
        }
    }

    static func loadRawDaysSync(
        db: Database,
        from startKey: DayKey? = nil,
        to endKey: DayKey? = nil,
        calendar: Calendar = .current
    ) throws -> [DailyRawMetrics] {
        var metricSQL = "SELECT day_key, metric, value, state, sources_json FROM day_metric WHERE 1=1"
        var metricArgs: [DatabaseValueConvertible?] = []
        if let startKey {
            metricSQL += " AND day_key >= ?"
            metricArgs.append(startKey.isoString)
        }
        if let endKey {
            metricSQL += " AND day_key <= ?"
            metricArgs.append(endKey.isoString)
        }

        let metricRows = try Row.fetchAll(db, sql: metricSQL, arguments: StatementArguments(metricArgs))
        var scalarByDay: [String: [String: Double]] = [:]
        var sourcesByDay: [String: [String]] = [:]

        for row in metricRows {
            let key: String = row["day_key"]
            let metric: String = row["metric"]
            let val: Double? = row["value"]
            if let val {
                scalarByDay[key, default: [:]][metric] = val
            } else if scalarByDay[key] == nil {
                scalarByDay[key] = [:]
            }
            if sourcesByDay[key] == nil, let sourcesJSON: String = row["sources_json"] {
                let refs = try Self.decodeJSON(sourcesJSON, as: [SourceRef].self)
                if !refs.isEmpty {
                    sourcesByDay[key] = refs.map(\.name)
                }
            }
        }

        // Sleep episodes
        var sleepSQL = "SELECT day_key, start, end, is_primary, stages_json, asleep_minutes, in_bed_minutes, deep_minutes, rem_minutes, core_minutes, awake_minutes FROM sleep_episode WHERE 1=1"
        var sleepArgs: [DatabaseValueConvertible?] = []
        if let startKey {
            sleepSQL += " AND day_key >= ?"
            sleepArgs.append(startKey.isoString)
        }
        if let endKey {
            sleepSQL += " AND day_key <= ?"
            sleepArgs.append(endKey.isoString)
        }
        sleepSQL += " ORDER BY is_primary DESC, asleep_minutes DESC, start ASC"
        let sleepRows = try Row.fetchAll(db, sql: sleepSQL, arguments: StatementArguments(sleepArgs))

        struct DaySleepAggregate {
            var sleepStart: Date?
            var sleepEnd: Date?
            var segments: [SleepStageSegment] = []
            var asleepMinutes: Int = 0
            var inBedMinutes: Int = 0
            var deepMinutes: Int = 0
            var remMinutes: Int = 0
            var coreMinutes: Int = 0
            var awakeMinutes: Int = 0
        }
        var sleepByDay: [String: DaySleepAggregate] = [:]
        for row in sleepRows {
            let key: String = row["day_key"]
            let isPrimary: Bool = row["is_primary"]
            var agg = sleepByDay[key] ?? DaySleepAggregate()
            let start = Date(timeIntervalSince1970: row["start"])
            let end = Date(timeIntervalSince1970: row["end"])
            agg.asleepMinutes += row["asleep_minutes"] as Int
            agg.inBedMinutes += row["in_bed_minutes"] as Int
            if isPrimary || agg.sleepStart == nil {
                agg.sleepStart = start
                agg.sleepEnd = end
                agg.deepMinutes = row["deep_minutes"]
                agg.remMinutes = row["rem_minutes"]
                agg.coreMinutes = row["core_minutes"]
                agg.awakeMinutes = row["awake_minutes"]
                if let stagesJSON: String = row["stages_json"] {
                    agg.segments = try Self.decodeJSON(stagesJSON, as: [SleepStageSegment].self)
                }
            }
            sleepByDay[key] = agg
        }

        // Workouts
        var workoutSQL = "SELECT hk_uuid, day_key, type, symbol_name, start, end, energy, avg_hr, zones_json, effort_user, effort_estimated FROM workout WHERE 1=1"
        var workoutArgs: [DatabaseValueConvertible?] = []
        if let startKey {
            workoutSQL += " AND day_key >= ?"
            workoutArgs.append(startKey.isoString)
        }
        if let endKey {
            workoutSQL += " AND day_key <= ?"
            workoutArgs.append(endKey.isoString)
        }
        workoutSQL += " ORDER BY start ASC"
        let workoutRows = try Row.fetchAll(db, sql: workoutSQL, arguments: StatementArguments(workoutArgs))
        var workoutsByDay: [String: [WorkoutSummary]] = [:]
        for row in workoutRows {
            let dayKeyString: String = row["day_key"]
            let uuidString: String = row["hk_uuid"]
            let uuid = UUID(uuidString: uuidString) ?? UUID()
            let start = Date(timeIntervalSince1970: row["start"])
            let end = Date(timeIntervalSince1970: row["end"])
            let durationMin = max(1, Int((end.timeIntervalSince(start) / 60.0).rounded()))
            let zonesJSON: String? = row["zones_json"]
            let zones: WorkoutHeartRateZones? = try zonesJSON.map {
                try Self.decodeJSON($0, as: WorkoutHeartRateZones.self)
            }
            workoutsByDay[dayKeyString, default: []].append(
                WorkoutSummary(
                    id: uuid,
                    activityName: row["type"],
                    symbolName: row["symbol_name"],
                    startDate: start,
                    durationMinutes: durationMin,
                    activeEnergyKcal: row["energy"],
                    averageHeartRate: row["avg_hr"],
                    effortScore: row["effort_user"],
                    heartRateZones: zones,
                    estimatedEffortScore: row["effort_estimated"],
                    healthKitUUID: UUID(uuidString: uuidString),
                    recordedEndDate: end
                )
            )
        }

        let allDayKeyStrings = Set(scalarByDay.keys)
            .union(sleepByDay.keys)
            .union(workoutsByDay.keys)
            .sorted()

        var results: [DailyRawMetrics] = []
        results.reserveCapacity(allDayKeyStrings.count)

        for keyString in allDayKeyStrings {
            guard let dayKey = DayKey(isoString: keyString) else { continue }
            let scalars = scalarByDay[keyString] ?? [:]
            let sleepAgg = sleepByDay[keyString]
            let dayWorkouts = workoutsByDay[keyString] ?? []
            let authorizedVal = scalars[DayMetricField.hasAuthorizedHealthData.rawValue]
            let hasAuthorized = authorizedVal == nil ? true : (authorizedVal ?? 1.0) > 0.5

            results.append(
                DailyRawMetrics(
                    date: dayKey.startDate(cutoverHour: 4, timeZone: calendar.timeZone),
                    hrvMs: scalars[DayMetricField.hrvMs.rawValue],
                    restingHeartRateBpm: scalars[DayMetricField.restingHeartRateBpm.rawValue],
                    respiratoryRateBrpm: scalars[DayMetricField.respiratoryRateBrpm.rawValue],
                    wristTempDeltaC: scalars[DayMetricField.wristTempDeltaC.rawValue],
                    oxygenSaturationPct: scalars[DayMetricField.oxygenSaturationPct.rawValue],
                    sleepAsleepMinutes: sleepAgg?.asleepMinutes ?? scalars[DayMetricField.sleepAsleepMinutes.rawValue].map { Int($0.rounded()) },
                    sleepInBedMinutes: sleepAgg?.inBedMinutes ?? scalars[DayMetricField.sleepInBedMinutes.rawValue].map { Int($0.rounded()) },
                    deepMinutes: sleepAgg?.deepMinutes ?? scalars[DayMetricField.deepMinutes.rawValue].map { Int($0.rounded()) },
                    remMinutes: sleepAgg?.remMinutes ?? scalars[DayMetricField.remMinutes.rawValue].map { Int($0.rounded()) },
                    coreMinutes: sleepAgg?.coreMinutes ?? scalars[DayMetricField.coreMinutes.rawValue].map { Int($0.rounded()) },
                    awakeMinutes: sleepAgg?.awakeMinutes ?? scalars[DayMetricField.awakeMinutes.rawValue].map { Int($0.rounded()) },
                    sleepStart: sleepAgg?.sleepStart,
                    sleepEnd: sleepAgg?.sleepEnd,
                    sleepSegments: sleepAgg?.segments ?? [],
                    activeEnergyKcal: scalars[DayMetricField.activeEnergyKcal.rawValue],
                    exerciseMinutes: scalars[DayMetricField.exerciseMinutes.rawValue].map { Int($0.rounded()) },
                    steps: scalars[DayMetricField.steps.rawValue].map { Int($0.rounded()) },
                    workouts: dayWorkouts,
                    daytimeMeanHeartRateBpm: scalars[DayMetricField.daytimeMeanHeartRateBpm.rawValue],
                    daytimeMaxHeartRateBpm: scalars[DayMetricField.daytimeMaxHeartRateBpm.rawValue],
                    hasAuthorizedHealthData: hasAuthorized,
                    sourceNames: sourcesByDay[keyString] ?? [],
                    dayKey: dayKey,
                    walkingHeartRateAvgBpm: scalars[DayMetricField.walkingHeartRateAvgBpm.rawValue],
                    vo2MaxMlKgMin: scalars[DayMetricField.vo2MaxMlKgMin.rawValue],
                    heartRateRecovery1MinBpm: scalars[DayMetricField.heartRateRecovery1MinBpm.rawValue],
                    bodyMassKg: scalars[DayMetricField.bodyMassKg.rawValue],
                    physicalEffortKcalPerKgHr: scalars[DayMetricField.physicalEffortKcalPerKgHr.rawValue]
                )
            )
        }

        return results
    }

    public func saveComputedDays(_ days: [DailyComputedDay], computedAt: Date = Date()) async throws {
        guard !days.isEmpty else { return }
        try await database.writer.write { db in
            let nowEpoch = computedAt.timeIntervalSince1970
            for day in days {
                for kind in MetricKind.allCases {
                    let score = day.score(for: kind)
                    let stateTag: ObservationStateTag
                    switch score.availability {
                    case .available: stateTag = .available
                    case .knownZero: stateTag = .knownZero
                    case .missing: stateTag = .missing
                    case .excluded: stateTag = .excluded
                    }
                    let contributorsJSON = try Self.encodeJSONString(score.contributors, label: "score.contributors")
                    try db.execute(
                        sql: """
                        INSERT INTO score_snapshot (
                            day_key, kind, value, state, reason, baseline_delta,
                            badge, subtitle, contributors_json, algorithm_version, computed_at
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(day_key, kind, algorithm_version) DO UPDATE SET
                            value = excluded.value,
                            state = excluded.state,
                            reason = excluded.reason,
                            baseline_delta = excluded.baseline_delta,
                            badge = excluded.badge,
                            subtitle = excluded.subtitle,
                            contributors_json = excluded.contributors_json,
                            computed_at = excluded.computed_at
                        """,
                        arguments: [
                            day.dayKey.isoString,
                            kind.rawValue,
                            score.value,
                            stateTag.rawValue,
                            score.availability.reasonText,
                            score.baselineDelta,
                            score.badge,
                            score.subtitle,
                            contributorsJSON,
                            score.algorithmVersion.description,
                            nowEpoch,
                        ]
                    )
                }

                let curveJSON = try Self.encodeJSONString(day.energyCurve, label: "day.energyCurve")
                let stressJSON = try Self.encodeJSONString(day.stressTimeline, label: "day.stressTimeline")
                try db.execute(
                    sql: """
                    INSERT INTO day_computed_artifact (
                        day_key, date, energy_curve_json, stress_timeline_json,
                        factual_summary, evidence_summary, algorithm_version, computed_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(day_key) DO UPDATE SET
                        date = excluded.date,
                        energy_curve_json = excluded.energy_curve_json,
                        stress_timeline_json = excluded.stress_timeline_json,
                        factual_summary = excluded.factual_summary,
                        evidence_summary = excluded.evidence_summary,
                        algorithm_version = excluded.algorithm_version,
                        computed_at = excluded.computed_at
                    """,
                    arguments: [
                        day.dayKey.isoString,
                        day.date.timeIntervalSince1970,
                        curveJSON,
                        stressJSON,
                        day.factualSummary,
                        day.evidenceSummary,
                        day.algorithmVersion.description,
                        nowEpoch,
                    ]
                )
            }
        }
    }

    /// Loads cached `score-v2` computed days plus their raw inputs. SyncEngine uses this
    /// to reuse untouched days instead of recomputing the whole three-year window.
    public func loadComputedDays(
        from startKey: DayKey? = nil,
        to endKey: DayKey? = nil,
        calendar: Calendar = .current
    ) async throws -> [DailyComputedDay] {
        try await database.writer.read { db in
            let rawDays = try Self.loadRawDaysSync(db: db, from: startKey, to: endKey, calendar: calendar)
            return try Self.loadComputedDaysSync(
                db: db,
                rawDays: rawDays,
                from: startKey,
                to: endKey,
                algorithmVersion: .scoreV2
            )
        }
    }

    /// Same as `loadComputedDays(from:to:)` when the caller already loaded the raw days,
    /// avoiding a second full raw-day query during sync.
    public func loadComputedDays(
        rawDays: [DailyRawMetrics],
        from startKey: DayKey? = nil,
        to endKey: DayKey? = nil,
        algorithmVersion: AlgorithmVersion = .scoreV2
    ) async throws -> [DailyComputedDay] {
        try await database.writer.read { db in
            try Self.loadComputedDaysSync(
                db: db,
                rawDays: rawDays,
                from: startKey,
                to: endKey,
                algorithmVersion: algorithmVersion
            )
        }
    }

    static func loadComputedDaysSync(
        db: Database,
        rawDays: [DailyRawMetrics],
        from startKey: DayKey? = nil,
        to endKey: DayKey? = nil,
        algorithmVersion: AlgorithmVersion
    ) throws -> [DailyComputedDay] {
        var artifactSQL = """
            SELECT day_key, date, energy_curve_json, stress_timeline_json,
                   factual_summary, evidence_summary, algorithm_version
            FROM day_computed_artifact
            WHERE algorithm_version = ?
            """
        var artifactArgs: [DatabaseValueConvertible?] = [algorithmVersion.description]
        if let startKey {
            artifactSQL += " AND day_key >= ?"
            artifactArgs.append(startKey.isoString)
        }
        if let endKey {
            artifactSQL += " AND day_key <= ?"
            artifactArgs.append(endKey.isoString)
        }
        artifactSQL += " ORDER BY day_key ASC"
        let artifactRows = try Row.fetchAll(db, sql: artifactSQL, arguments: StatementArguments(artifactArgs))

        var scoreSQL = """
            SELECT day_key, kind, value, state, reason, baseline_delta, badge, subtitle,
                   contributors_json, algorithm_version
            FROM score_snapshot
            WHERE algorithm_version = ?
            """
        var scoreArgs: [DatabaseValueConvertible?] = [algorithmVersion.description]
        if let startKey {
            scoreSQL += " AND day_key >= ?"
            scoreArgs.append(startKey.isoString)
        }
        if let endKey {
            scoreSQL += " AND day_key <= ?"
            scoreArgs.append(endKey.isoString)
        }
        let scoreRows = try Row.fetchAll(db, sql: scoreSQL, arguments: StatementArguments(scoreArgs))
        var scoresByDay: [String: [String: MetricScore]] = [:]
        for row in scoreRows {
            guard let kind = MetricKind(rawValue: row["kind"]) else { continue }
            let stateRaw: String = row["state"]
            let reason: String? = row["reason"]
            let availability: MetricAvailability
            switch stateRaw {
            case "available": availability = .available
            case "knownZero": availability = .knownZero(reason: reason ?? "")
            case "missing": availability = .missing(reason: reason ?? "")
            case "excluded": availability = .excluded(reason: reason ?? "")
            default: continue
            }
            let contributors: [MetricContributor] = try Self.decodeJSON(row["contributors_json"] as String, as: [MetricContributor].self)
            scoresByDay[row["day_key"], default: [:]][kind.rawValue] = MetricScore(
                kind: kind,
                value: row["value"],
                availability: availability,
                badge: row["badge"],
                subtitle: row["subtitle"],
                baselineDelta: row["baseline_delta"],
                algorithmVersion: algorithmVersion,
                contributors: contributors
            )
        }

        let rawByKey = Dictionary(rawDays.map { ($0.dayKey?.isoString ?? "", $0) }, uniquingKeysWith: { first, _ in first })
        var result: [DailyComputedDay] = []
        result.reserveCapacity(artifactRows.count)
        for row in artifactRows {
            let key: String = row["day_key"]
            guard let raw = rawByKey[key],
                  let dayKey = DayKey(isoString: key),
                  let dayScores = scoresByDay[key],
                  let recovery = dayScores[MetricKind.recovery.rawValue],
                  let sleep = dayScores[MetricKind.sleep.rawValue],
                  let strain = dayScores[MetricKind.strain.rawValue],
                  let stress = dayScores[MetricKind.stress.rawValue],
                  let energy = dayScores[MetricKind.energy.rawValue]
            else { continue }
            let curve: [EnergyCurvePoint] = try Self.decodeJSON(row["energy_curve_json"] as String, as: [EnergyCurvePoint].self)
            let timeline: [StressTimelineBin] = try Self.decodeJSON(row["stress_timeline_json"] as String, as: [StressTimelineBin].self)
            result.append(DailyComputedDay(
                date: Date(timeIntervalSince1970: row["date"]),
                dayKey: dayKey,
                raw: raw,
                recovery: recovery,
                sleep: sleep,
                strain: strain,
                stress: stress,
                energy: energy,
                energyCurve: curve,
                stressTimeline: timeline,
                factualSummary: row["factual_summary"],
                evidenceSummary: row["evidence_summary"],
                algorithmVersion: algorithmVersion
            ))
        }
        return result
    }

    // MARK: - Check-ins, Plans, Memories, Patterns, Audits

    public func saveCheckIn(_ checkIn: DailyCheckIn) async throws {
        try await database.writer.write { db in
            try Self.saveCheckInSync(db: db, checkIn: checkIn)
        }
    }

    static func saveCheckInSync(db: Database, checkIn: DailyCheckIn) throws {
        let sorenessJSON = try Self.encodeJSONString(checkIn.soreness, label: "checkIn.soreness")
        try db.execute(
            sql: """
            INSERT INTO check_in (id, day_key, at, energy, mood, stress, soreness_json, note)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(day_key) DO UPDATE SET
                id = excluded.id,
                at = excluded.at,
                energy = excluded.energy,
                mood = excluded.mood,
                stress = excluded.stress,
                soreness_json = excluded.soreness_json,
                note = excluded.note
            """,
            arguments: [
                checkIn.id.uuidString,
                checkIn.dayKey.isoString,
                checkIn.recordedAt.timeIntervalSince1970,
                checkIn.energy,
                checkIn.mood,
                checkIn.stress,
                sorenessJSON,
                checkIn.note,
            ]
        )
    }

    public func loadCheckIns() async throws -> [DailyCheckIn] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, day_key, at, energy, mood, stress, soreness_json, note FROM check_in ORDER BY day_key DESC"
            )
            return try rows.compactMap { row in
                let idStr: String = row["id"]
                let dayKeyStr: String = row["day_key"]
                guard let id = UUID(uuidString: idStr), let dayKey = DayKey(isoString: dayKeyStr) else {
                    return nil
                }
                let sorenessJSON: String = row["soreness_json"]
                let soreness = try Self.decodeJSON(sorenessJSON, as: [BodyRegionMuscle: Int].self)
                return DailyCheckIn(
                    id: id,
                    dayKey: dayKey,
                    recordedAt: Date(timeIntervalSince1970: row["at"]),
                    energy: row["energy"],
                    mood: row["mood"],
                    stress: row["stress"],
                    soreness: soreness,
                    note: row["note"]
                )
            }
        }
    }

    public func savePlanItem(_ item: PlanItemRecord) async throws {
        try await database.writer.write { db in
            try Self.savePlanItemSync(db: db, item: item)
        }
    }

    static func savePlanItemSync(db: Database, item: PlanItemRecord) throws {
        try db.execute(
            sql: """
            INSERT INTO plan_item (id, day_key, kind, payload_json, state, origin)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                day_key = excluded.day_key,
                kind = excluded.kind,
                payload_json = excluded.payload_json,
                state = excluded.state,
                origin = excluded.origin
            """,
            arguments: [
                item.id.uuidString,
                item.dayKey.isoString,
                item.kind.rawValue,
                item.payloadJSON,
                item.state.rawValue,
                item.origin.rawValue,
            ]
        )
    }

    public func loadPlanItems(dayKey: DayKey) async throws -> [PlanItemRecord] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, day_key, kind, payload_json, state, origin FROM plan_item WHERE day_key = ?",
                arguments: [dayKey.isoString]
            )
            return rows.compactMap { row in
                guard let id = UUID(uuidString: row["id"]),
                      let key = DayKey(isoString: row["day_key"]),
                      let kind = PlanItemKind(rawValue: row["kind"]),
                      let state = PlanItemState(rawValue: row["state"]),
                      let origin = ActionProposal.Origin(rawValue: row["origin"])
                else {
                    return nil
                }
                return PlanItemRecord(
                    id: id,
                    dayKey: key,
                    kind: kind,
                    payloadJSON: row["payload_json"],
                    state: state,
                    origin: origin
                )
            }
        }
    }

    public func loadExperimentPlanItems() async throws -> [PlanItemRecord] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, day_key, kind, payload_json, state, origin FROM plan_item WHERE kind = ? ORDER BY day_key DESC",
                arguments: [PlanItemKind.experiment.rawValue]
            )
            return rows.compactMap { row in
                guard let id = UUID(uuidString: row["id"]),
                      let key = DayKey(isoString: row["day_key"]),
                      let kind = PlanItemKind(rawValue: row["kind"]),
                      let state = PlanItemState(rawValue: row["state"]),
                      let origin = ActionProposal.Origin(rawValue: row["origin"])
                else {
                    return nil
                }
                return PlanItemRecord(
                    id: id,
                    dayKey: key,
                    kind: kind,
                    payloadJSON: row["payload_json"],
                    state: state,
                    origin: origin
                )
            }
        }
    }

    // MARK: - Tiered Memory & AthleteMemoryItem Bridge

    public func saveTieredMemory(_ record: TieredMemoryRecord) async throws {
        try await database.writer.write { db in
            try Self.saveTieredMemorySync(db: db, record: record)
        }
    }

    static func saveTieredMemorySync(db: Database, record: TieredMemoryRecord) throws {
        try db.execute(
            sql: """
            INSERT INTO memory (id, tier, content, scope_json, confidence, expires_at, confirmed_at, retired_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                tier = excluded.tier,
                content = excluded.content,
                scope_json = excluded.scope_json,
                confidence = excluded.confidence,
                expires_at = excluded.expires_at,
                confirmed_at = excluded.confirmed_at,
                retired_at = excluded.retired_at
            """,
            arguments: [
                record.id.uuidString,
                record.tier.rawValue,
                record.content,
                record.scopeJSON,
                record.confidence,
                record.expiresAt?.timeIntervalSince1970,
                record.confirmedAt?.timeIntervalSince1970,
                record.retiredAt?.timeIntervalSince1970,
            ]
        )
    }

    public func loadTieredMemories(includeRetired: Bool = false) async throws -> [TieredMemoryRecord] {
        try await database.writer.read { db in
            let sql = includeRetired
                ? "SELECT id, tier, content, scope_json, confidence, expires_at, confirmed_at, retired_at FROM memory ORDER BY confirmed_at DESC"
                : "SELECT id, tier, content, scope_json, confidence, expires_at, confirmed_at, retired_at FROM memory WHERE retired_at IS NULL ORDER BY confirmed_at DESC"
            let rows = try Row.fetchAll(db, sql: sql)
            return rows.compactMap(Self.decodeMemoryRow)
        }
    }

    private static func ftsPhraseLiteral(_ query: String) -> String {
        let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func escapeLikePattern(_ query: String) -> String {
        query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    public func searchMemoriesFTS(query: String) async throws -> [TieredMemoryRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await database.writer.read { db in
            let rows: [Row]
            if trimmed.count >= 3 {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT m.id, m.tier, m.content, m.scope_json, m.confidence, m.expires_at, m.confirmed_at, m.retired_at
                    FROM memory m
                    JOIN memory_fts f ON m.rowid = f.rowid
                    WHERE memory_fts MATCH ? AND m.retired_at IS NULL
                    ORDER BY bm25(memory_fts)
                    """,
                    arguments: [Self.ftsPhraseLiteral(trimmed)]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id, tier, content, scope_json, confidence, expires_at, confirmed_at, retired_at
                    FROM memory
                    WHERE retired_at IS NULL AND content LIKE ? ESCAPE '\\'
                    ORDER BY confirmed_at DESC
                    """,
                    arguments: ["%\(Self.escapeLikePattern(trimmed))%"]
                )
            }
            return rows.compactMap(Self.decodeMemoryRow)
        }
    }

    public func searchWorkoutAnnotationsFTS(query: String) async throws -> [WorkoutAnnotationRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try await database.writer.read { db in
            let rows: [Row]
            if trimmed.count >= 3 {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT a.id, a.workout_uuid, a.raw_text, a.parser_version, a.confirmed_at
                    FROM workout_annotation a
                    JOIN workout_annotation_fts f ON a.rowid = f.rowid
                    WHERE workout_annotation_fts MATCH ?
                    ORDER BY bm25(workout_annotation_fts)
                    """,
                    arguments: [Self.ftsPhraseLiteral(trimmed)]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id, workout_uuid, raw_text, parser_version, confirmed_at
                    FROM workout_annotation
                    WHERE raw_text LIKE ? ESCAPE '\\'
                    ORDER BY confirmed_at DESC
                    """,
                    arguments: ["%\(Self.escapeLikePattern(trimmed))%"]
                )
            }
            return rows.compactMap { row in
                guard let id = UUID(uuidString: row["id"]) else { return nil }
                let versionParts = (row["parser_version"] as String).split(separator: "@", maxSplits: 1)
                let version = AlgorithmVersion(
                    id: String(versionParts.first ?? "workout-parser-v1"),
                    semver: versionParts.count > 1 ? String(versionParts[1]) : "1.0.0"
                )
                let confirmedEpoch: Double? = row["confirmed_at"]
                return WorkoutAnnotationRecord(
                    id: id,
                    workoutUUID: row["workout_uuid"],
                    rawText: row["raw_text"],
                    parserVersion: version,
                    confirmedAt: confirmedEpoch.map(Date.init(timeIntervalSince1970:))
                )
            }
        }
    }

    private static func decodeMemoryRow(_ row: Row) -> TieredMemoryRecord? {
        guard let id = UUID(uuidString: row["id"]),
              let tier = MemoryTier(rawValue: row["tier"])
        else {
            return nil
        }
        let exp: Double? = row["expires_at"]
        let conf: Double? = row["confirmed_at"]
        let ret: Double? = row["retired_at"]
        return TieredMemoryRecord(
            id: id,
            tier: tier,
            content: row["content"],
            scopeJSON: row["scope_json"],
            confidence: row["confidence"],
            expiresAt: exp.map(Date.init(timeIntervalSince1970:)),
            confirmedAt: conf.map(Date.init(timeIntervalSince1970:)),
            retiredAt: ret.map(Date.init(timeIntervalSince1970:))
        )
    }

    // MARK: - Continuity Bridges: AthleteMemoryItem, Templates, Sessions, Messages

    private struct LegacyMemoryScope: Codable {
        let category: AthleteMemoryCategory
    }

    public func loadAthleteMemories() async throws -> [AthleteMemoryItem] {
        let records = try await loadTieredMemories(includeRetired: false)
        return records.map { record in
            let decodedCat: AthleteMemoryCategory
            if let data = record.scopeJSON.data(using: .utf8), !record.scopeJSON.isEmpty, record.scopeJSON != "{}" {
                do {
                    decodedCat = try JSONDecoder().decode(LegacyMemoryScope.self, from: data).category
                } catch {
                    Self.logger.warning("Falling back category for memory \(record.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    decodedCat = record.tier == .activeConstraint ? .injury : .preference
                }
            } else {
                decodedCat = record.tier == .activeConstraint ? .injury : .preference
            }
            return AthleteMemoryItem(
                id: record.id,
                category: decodedCat,
                content: record.content,
                updatedAt: record.confirmedAt ?? Date()
            )
        }
    }

    public func saveAthleteMemory(_ item: AthleteMemoryItem) async throws {
        let tier: MemoryTier = (item.category == .injury) ? .activeConstraint : .profile
        let expiresAt: Date? = (item.category == .injury) ? item.updatedAt.addingTimeInterval(14 * 86_400) : nil
        let scopeJSON = try Self.encodeJSONString(LegacyMemoryScope(category: item.category), label: "AthleteMemoryScope")
        try await saveTieredMemory(
            TieredMemoryRecord(
                id: item.id,
                tier: tier,
                content: item.content,
                scopeJSON: scopeJSON,
                confidence: 1.0,
                expiresAt: expiresAt,
                confirmedAt: item.updatedAt,
                retiredAt: nil
            )
        )
    }

    public func deleteMemory(id: UUID) async throws {
        try await database.writer.write { db in
            try Self.retireMemorySync(db: db, memoryID: id, retiredAt: Date())
        }
    }

    static func retireMemorySync(db: Database, memoryID: UUID, retiredAt: Date) throws {
        try db.execute(
            sql: "UPDATE memory SET retired_at = ? WHERE id = ?",
            arguments: [retiredAt.timeIntervalSince1970, memoryID.uuidString]
        )
    }

    public func loadTemplates() async throws -> [WorkoutTemplate] {
        try await database.writer.write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM workout_template ORDER BY sort_order ASC")
            if rows.isEmpty {
                let defaults = ExerciseCatalog.defaultTemplates
                let encoder = JSONEncoder()
                let now = Date().timeIntervalSince1970
                for (idx, item) in defaults.enumerated() {
                    let payload = try encoder.encode(item)
                    try db.execute(
                        sql: "INSERT INTO workout_template (id, sort_order, updated_at, payload) VALUES (?, ?, ?, ?)",
                        arguments: [item.id.uuidString, idx, now, payload]
                    )
                }
                return defaults
            }
            let decoder = JSONDecoder()
            return try rows.map { row in
                let data: Data = row["payload"]
                return try decoder.decode(WorkoutTemplate.self, from: data)
            }
        }
    }

    public func saveTemplate(_ template: WorkoutTemplate) async throws {
        let payload = try JSONEncoder().encode(template)
        try await database.writer.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workout_template") ?? 0
            try db.execute(
                sql: """
                INSERT INTO workout_template (id, sort_order, updated_at, payload)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    updated_at = excluded.updated_at,
                    payload = excluded.payload
                """,
                arguments: [template.id.uuidString, count, Date().timeIntervalSince1970, payload]
            )
        }
    }

    public func loadSessions() async throws -> [LoggedWorkoutSession] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT payload FROM logged_workout_session ORDER BY completed_at DESC")
            let decoder = JSONDecoder()
            return try rows.map { row in
                try decoder.decode(LoggedWorkoutSession.self, from: row["payload"] as Data)
            }
        }
    }

    public func saveSession(_ session: LoggedWorkoutSession) async throws {
        let payload = try JSONEncoder().encode(session)
        try await database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO logged_workout_session (id, completed_at, payload)
                VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    completed_at = excluded.completed_at,
                    payload = excluded.payload
                """,
                arguments: [session.id.uuidString, session.completedAt.timeIntervalSince1970, payload]
            )
        }
    }

    private struct CoachMessageTraceMetadata: Codable {
        let memoryProposal: TieredMemoryRecord?
        let workoutAnnotationProposal: CoachWorkoutAnnotationProposal?
        let workoutAnnotationCandidates: [CoachWorkoutAnnotationCandidate]?
        let unverifiedNumbers: [String]
        let toolsInvoked: [String]
    }

    public func loadMessages(threadID: String = "default") async throws -> [CoachMessage] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT m.id, m.role, m.content, m.engine_label, m.evidence_metric, m.proposal_json, m.memory_note,
                       m.tool_trace_json, m.at, a.decision AS annotation_decision,
                       u.decision AS undo_decision
                FROM coach_message m
                LEFT JOIN action_audit a ON a.id = m.id
                LEFT JOIN action_audit u ON u.undo_of = m.id AND u.decision = 'undone'
                WHERE thread_id = ?
                ORDER BY at ASC
                """,
                arguments: [threadID]
            )
            let decoder = JSONDecoder()
            // Older builds stored successful Coach annotations without a message ID.
            let legacyAnnotations = try Row.fetchAll(db, sql: """
                SELECT proposal_json, decided_at FROM action_audit
                WHERE origin = 'agent' AND decision = 'applied'
                  AND json_extract(proposal_json, '$.kind') = 'annotateWorkout'
                """).compactMap { row -> (AnnotateWorkoutPayload, Date)? in
                    let action = try decoder.decode(ActionProposal.self, from: Data((row["proposal_json"] as String).utf8))
                    let payload = try action.decodePayload(AnnotateWorkoutPayload.self)
                    guard payload.coachAnnotationDecision == nil else { return nil }
                    return (payload, Date(timeIntervalSince1970: row["decided_at"]))
                }
            return try rows.compactMap { row in
                guard let id = UUID(uuidString: row["id"]),
                      let role = CoachMessage.Role(rawValue: row["role"])
                else {
                    return nil
                }
                let metricStr: String? = row["evidence_metric"]
                let metric = metricStr.flatMap(MetricKind.init(rawValue:))
                let proposalJSON: String? = row["proposal_json"]
                let proposal: WorkoutProposal? = try proposalJSON.map {
                    try decoder.decode(WorkoutProposal.self, from: Data($0.utf8))
                }
                let traceJSON: String? = row["tool_trace_json"]
                let trace: CoachMessageTraceMetadata? = try traceJSON.map {
                    try decoder.decode(CoachMessageTraceMetadata.self, from: Data($0.utf8))
                }
                let at = Date(timeIntervalSince1970: row["at"])
                let persistedDecision = (row["annotation_decision"] as String?).flatMap(ActionAuditDecision.init(rawValue:))
                let undoDecision = (row["undo_decision"] as String?).flatMap(ActionAuditDecision.init(rawValue:))
                let annotationDecision = undoDecision ?? persistedDecision ?? trace?.workoutAnnotationProposal.flatMap { proposal in
                    legacyAnnotations.contains { payload, decidedAt in
                        decidedAt >= at && payload.workoutUUID == proposal.workoutUUID
                            && payload.rawText == proposal.rawText
                            && payload.parserVersion == proposal.proposal.parserVersion
                            && payload.muscleLoads == proposal.muscleLoads
                    } ? .applied : nil
                }
                return CoachMessage(
                    id: id,
                    role: role,
                    text: row["content"],
                    engineLabel: row["engine_label"],
                    timestamp: at,
                    evidenceMetric: metric,
                    workoutProposal: proposal,
                    memorySavedNote: row["memory_note"],
                    memoryProposal: trace?.memoryProposal,
                    workoutAnnotationProposal: trace?.workoutAnnotationProposal,
                    workoutAnnotationCandidates: trace?.workoutAnnotationCandidates ?? [],
                    annotationDecision: annotationDecision,
                    unverifiedNumbers: trace?.unverifiedNumbers ?? [],
                    toolsInvoked: trace?.toolsInvoked ?? []
                )
            }
        }
    }

    public func appendMessage(_ msg: CoachMessage, threadID: String = "default") async throws {
        let proposalJSON: String? = if let proposal = msg.workoutProposal {
            try Self.encodeJSONString(proposal, label: "CoachMessage.proposal")
        } else {
            nil
        }
        let hasTrace = msg.memoryProposal != nil
            || msg.workoutAnnotationProposal != nil
            || !msg.workoutAnnotationCandidates.isEmpty
            || !msg.unverifiedNumbers.isEmpty
            || !msg.toolsInvoked.isEmpty
        let traceJSON: String? = if hasTrace {
            try Self.encodeJSONString(
                CoachMessageTraceMetadata(
                    memoryProposal: msg.memoryProposal,
                    workoutAnnotationProposal: msg.workoutAnnotationProposal,
                    workoutAnnotationCandidates: msg.workoutAnnotationCandidates.isEmpty ? nil : msg.workoutAnnotationCandidates,
                    unverifiedNumbers: msg.unverifiedNumbers,
                    toolsInvoked: msg.toolsInvoked
                ),
                label: "CoachMessage.trace"
            )
        } else {
            nil
        }
        try await database.writer.write { db in
            try Self.appendMessageSync(
                db: db,
                message: msg,
                proposalJSON: proposalJSON,
                traceJSON: traceJSON,
                threadID: threadID
            )
        }
    }

    static func appendMessageSync(
        db: Database,
        message: CoachMessage,
        proposalJSON: String?,
        traceJSON: String? = nil,
        threadID: String = "default"
    ) throws {
        try db.execute(
            sql: """
            INSERT INTO coach_message (
                id, thread_id, role, content, engine_label, evidence_metric,
                proposal_json, memory_note, tool_trace_json, at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                content = excluded.content,
                engine_label = excluded.engine_label,
                evidence_metric = excluded.evidence_metric,
                proposal_json = excluded.proposal_json,
                memory_note = excluded.memory_note,
                tool_trace_json = excluded.tool_trace_json,
                at = excluded.at
            """,
            arguments: [
                message.id.uuidString,
                threadID,
                message.role.rawValue,
                message.text,
                message.engineLabel,
                message.evidenceMetric?.rawValue,
                proposalJSON,
                message.memorySavedNote,
                traceJSON,
                message.timestamp.timeIntervalSince1970,
            ]
        )
    }

    public func clearMessages(threadID: String? = nil) async throws {
        try await database.writer.write { db in
            if let threadID {
                try db.execute(sql: "DELETE FROM coach_message WHERE thread_id = ?", arguments: [threadID])
            } else {
                try db.execute(sql: "DELETE FROM coach_message")
            }
        }
    }

    public func loadAuditEntries(limit: Int? = nil) async throws -> [ActionAuditEntry] {
        try await database.writer.read { db in
            var sql = """
                SELECT id, proposal_json, origin, decision, decided_at, affected_ids_json,
                       snapshot_version, snapshot_json, undo_of, undone_by
                FROM action_audit
                ORDER BY decided_at DESC
                """
            var arguments = StatementArguments()
            if let limit {
                sql += " LIMIT ?"
                arguments = StatementArguments([max(0, limit)])
            }
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return try rows.compactMap(Self.decodeAuditEntry)
        }
    }

    static func decodeAuditEntry(_ row: Row) throws -> ActionAuditEntry? {
        guard let id = UUID(uuidString: row["id"]),
              let origin = ActionProposal.Origin(rawValue: row["origin"]),
              let decision = ActionAuditDecision(rawValue: row["decision"])
        else {
            return nil
        }
        let affected = try Self.decodeJSON(row["affected_ids_json"] as String, as: [String].self)
        let undoOf: UUID? = (row["undo_of"] as String?).flatMap(UUID.init(uuidString:))
        let undoneBy: UUID? = (row["undone_by"] as String?).flatMap(UUID.init(uuidString:))
        return ActionAuditEntry(
            id: id,
            proposalJSON: row["proposal_json"],
            origin: origin,
            decision: decision,
            decidedAt: Date(timeIntervalSince1970: row["decided_at"]),
            affectedIDs: affected,
            snapshotVersion: (row["snapshot_version"] as Int?) ?? 1,
            snapshotJSON: row["snapshot_json"],
            undoOf: undoOf,
            undoneBy: undoneBy
        )
    }

    public func savePatternFinding(_ finding: PatternFindingRecord) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                INSERT INTO pattern_finding (id, statement, effect, ci_low, ci_high, n, method, model_version, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    statement = excluded.statement,
                    effect = excluded.effect,
                    ci_low = excluded.ci_low,
                    ci_high = excluded.ci_high,
                    n = excluded.n,
                    method = excluded.method,
                    model_version = excluded.model_version,
                    status = excluded.status
                """,
                arguments: [
                    finding.id.uuidString,
                    finding.statement,
                    finding.effect,
                    finding.ciLow,
                    finding.ciHigh,
                    finding.sampleSize,
                    finding.method,
                    finding.modelVersion,
                    finding.status.rawValue,
                ]
            )
        }
    }

    public func loadPatternFindings(status: PatternFindingStatus? = nil) async throws -> [PatternFindingRecord] {
        try await database.writer.read { db in
            let sql: String
            let args: StatementArguments
            if let status {
                sql = "SELECT id, statement, effect, ci_low, ci_high, n, method, model_version, status FROM pattern_finding WHERE status = ?"
                args = [status.rawValue]
            } else {
                sql = "SELECT id, statement, effect, ci_low, ci_high, n, method, model_version, status FROM pattern_finding"
                args = []
            }
            let rows = try Row.fetchAll(db, sql: sql, arguments: args)
            return rows.compactMap { row in
                guard let id = UUID(uuidString: row["id"]),
                      let statusVal = PatternFindingStatus(rawValue: row["status"])
                else {
                    return nil
                }
                return PatternFindingRecord(
                    id: id,
                    statement: row["statement"],
                    effect: row["effect"],
                    ciLow: row["ci_low"],
                    ciHigh: row["ci_high"],
                    sampleSize: row["n"],
                    method: row["method"],
                    modelVersion: row["model_version"],
                    status: statusVal
                )
            }
        }
    }

    public func loadMuscleLoads(workoutUUID: String) async throws -> [WorkoutMuscleLoadRecord] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT workout_uuid, muscle_id, role, load, algorithm_version FROM workout_muscle_load WHERE workout_uuid = ?",
                arguments: [workoutUUID]
            )
            return rows.compactMap { row in
                guard let muscle = BodyRegionMuscle(rawValue: row["muscle_id"]),
                      let role = MuscleLoadRole(rawValue: row["role"])
                else {
                    return nil
                }
                let verParts = (row["algorithm_version"] as String).split(separator: "@", maxSplits: 1)
                let version = AlgorithmVersion(
                    id: String(verParts.first ?? "recovery-heuristic-v1"),
                    semver: verParts.count > 1 ? String(verParts[1]) : "1.0.0"
                )
                return WorkoutMuscleLoadRecord(
                    workoutUUID: row["workout_uuid"],
                    muscle: muscle,
                    role: role,
                    load: row["load"],
                    algorithmVersion: version
                )
            }
        }
    }

    public func loadAllMuscleLoads(since: Date? = nil) async throws -> [WorkoutMuscleLoadRecord] {
        try await database.writer.read { db in
            let rows: [Row]
            if let since {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT l.workout_uuid, l.muscle_id, l.role, l.load, l.algorithm_version
                    FROM workout_muscle_load l
                    JOIN workout w ON w.hk_uuid = l.workout_uuid
                    WHERE w.end >= ?
                    ORDER BY w.end DESC
                    """,
                    arguments: [since.timeIntervalSince1970]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: "SELECT workout_uuid, muscle_id, role, load, algorithm_version FROM workout_muscle_load"
                )
            }
            return rows.compactMap { row in
                guard let muscle = BodyRegionMuscle(rawValue: row["muscle_id"]),
                      let role = MuscleLoadRole(rawValue: row["role"])
                else {
                    return nil
                }
                let verParts = (row["algorithm_version"] as String).split(separator: "@", maxSplits: 1)
                let version = AlgorithmVersion(
                    id: String(verParts.first ?? "recovery-heuristic-v1"),
                    semver: verParts.count > 1 ? String(verParts[1]) : "1.0.0"
                )
                return WorkoutMuscleLoadRecord(
                    workoutUUID: row["workout_uuid"],
                    muscle: muscle,
                    role: role,
                    load: row["load"],
                    algorithmVersion: version
                )
            }
        }
    }

    public func loadWorkoutAnnotations(workoutUUID: String? = nil) async throws -> [WorkoutAnnotationRecord] {
        try await database.writer.read { db in
            let rows: [Row]
            if let workoutUUID {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id, workout_uuid, raw_text, parser_version, confirmed_at
                    FROM workout_annotation
                    WHERE workout_uuid = ?
                    ORDER BY confirmed_at DESC
                    """,
                    arguments: [workoutUUID]
                )
            } else {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT id, workout_uuid, raw_text, parser_version, confirmed_at
                    FROM workout_annotation
                    ORDER BY confirmed_at DESC
                    """
                )
            }
            return rows.compactMap { row in
                guard let id = UUID(uuidString: row["id"]) else { return nil }
                let versionParts = (row["parser_version"] as String).split(separator: "@", maxSplits: 1)
                let version = AlgorithmVersion(
                    id: String(versionParts.first ?? "workout-parser-v1"),
                    semver: versionParts.count > 1 ? String(versionParts[1]) : "1.0.0"
                )
                let confirmedEpoch: Double? = row["confirmed_at"]
                return WorkoutAnnotationRecord(
                    id: id,
                    workoutUUID: row["workout_uuid"],
                    rawText: row["raw_text"],
                    parserVersion: version,
                    confirmedAt: confirmedEpoch.map(Date.init(timeIntervalSince1970:))
                )
            }
        }
    }

    @discardableResult
    public func applyAutoWorkoutAttribution(
        workoutUUID: String,
        loads: [WorkoutMuscleLoadRecord]
    ) async throws -> Bool {
        try await database.writer.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT review_state FROM workout WHERE hk_uuid = ?",
                arguments: [workoutUUID]
            ) else {
                return false
            }
            let currentState: String = row["review_state"]
            guard currentState == WorkoutReviewState.unreviewed.rawValue
                    || currentState == WorkoutReviewState.autoAttributed.rawValue
            else {
                // Never overwrite user-annotated or skipped workouts on dominant-hand change
                return false
            }

            try db.execute(
                sql: "DELETE FROM workout_muscle_load WHERE workout_uuid = ?",
                arguments: [workoutUUID]
            )
            for item in loads {
                try db.execute(
                    sql: """
                    INSERT INTO workout_muscle_load (workout_uuid, muscle_id, role, load, algorithm_version)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        workoutUUID,
                        item.muscle.rawValue,
                        item.role.rawValue,
                        item.load,
                        item.algorithmVersion.description,
                    ]
                )
            }
            try db.execute(
                sql: "UPDATE workout SET review_state = ? WHERE hk_uuid = ?",
                arguments: [WorkoutReviewState.autoAttributed.rawValue, workoutUUID]
            )
            return true
        }
    }

    // MARK: - Nutrition Sub-System (Profile, Targets, Food Library, Daily Logs)

    public func saveNutritionProfile(_ profile: NutritionProfile) async throws {
        try await database.writer.write { db in
            try Self.saveNutritionProfileSync(db: db, profile: profile)
        }
    }

    static func saveNutritionProfileSync(db: Database, profile: NutritionProfile) throws {
        let json = try encodeJSONString(profile, label: "NutritionProfile")
        try db.execute(
            sql: """
            INSERT INTO nutrition_profile (id, payload_json, updated_at)
            VALUES ('current', ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                payload_json = excluded.payload_json,
                updated_at = excluded.updated_at
            """,
            arguments: [json, profile.updatedAt.timeIntervalSince1970]
        )
    }

    public func loadNutritionProfile() async throws -> NutritionProfile? {
        try await database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT payload_json FROM nutrition_profile WHERE id = 'current'"
            ) else {
                return nil
            }
            return try Self.decodeJSON(row["payload_json"] as String, as: NutritionProfile.self)
        }
    }

    public func saveNutritionTargetPlan(_ plan: NutritionTargetPlan) async throws {
        try await database.writer.write { db in
            try Self.saveNutritionTargetPlanSync(db: db, plan: plan)
        }
    }

    static func saveNutritionTargetPlanSync(db: Database, plan: NutritionTargetPlan) throws {
        let json = try encodeJSONString(plan, label: "NutritionTargetPlan")
        try db.execute(
            sql: """
            INSERT INTO nutrition_target_plan (id, version, status, effective_from, payload_json, updated_at)
            VALUES ('current', ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                version = excluded.version,
                status = excluded.status,
                effective_from = excluded.effective_from,
                payload_json = excluded.payload_json,
                updated_at = excluded.updated_at
            """,
            arguments: [
                plan.targetVersion,
                plan.targetStatus.rawValue,
                plan.effectiveFrom?.isoString,
                json,
                plan.updatedAt.timeIntervalSince1970,
            ]
        )
    }

    public func loadNutritionTargetPlan() async throws -> NutritionTargetPlan? {
        try await database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT payload_json FROM nutrition_target_plan WHERE id = 'current'"
            ) else {
                return nil
            }
            return try Self.decodeJSON(row["payload_json"] as String, as: NutritionTargetPlan.self)
        }
    }

    public func seedStarterFoodLibraryIfNeeded() async throws {
        try await database.writer.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM food_library_item") ?? 0
            guard count == 0 else { return }
            let nowEpoch = Date().timeIntervalSince1970
            for item in NutritionCatalog.starterFoodItems {
                try Self.saveFoodLibraryItemSync(db: db, item: item, updatedAt: nowEpoch)
            }
        }
    }

    public func saveFoodLibraryItem(_ item: FoodLibraryItem) async throws {
        try await database.writer.write { db in
            try Self.saveFoodLibraryItemSync(db: db, item: item, updatedAt: Date().timeIntervalSince1970)
        }
    }

    static func saveFoodLibraryItemSync(db: Database, item: FoodLibraryItem, updatedAt: TimeInterval) throws {
        let json = try encodeJSONString(item, label: "FoodLibraryItem")
        let aliasesText = item.aliases.joined(separator: " ")
        try db.execute(
            sql: """
            INSERT INTO food_library_item (food_id, name, aliases_text, category, state, usable, payload_json, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(food_id) DO UPDATE SET
                name = excluded.name,
                aliases_text = excluded.aliases_text,
                category = excluded.category,
                state = excluded.state,
                usable = excluded.usable,
                payload_json = excluded.payload_json,
                updated_at = excluded.updated_at
            """,
            arguments: [
                item.foodID,
                item.name,
                aliasesText,
                item.category,
                item.stateDescription,
                item.usable,
                json,
                updatedAt,
            ]
        )
    }

    public func searchFoodLibrary(query: String) async throws -> [FoodLibraryItem] {
        try await seedStarterFoodLibraryIfNeeded()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await database.writer.read { db in
            let rows: [Row]
            if trimmed.isEmpty {
                rows = try Row.fetchAll(db, sql: "SELECT payload_json FROM food_library_item ORDER BY name ASC")
            } else if trimmed.count >= 3 {
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT i.payload_json
                    FROM food_library_item i
                    JOIN food_library_fts f ON i.rowid = f.rowid
                    WHERE food_library_fts MATCH ?
                    ORDER BY bm25(food_library_fts)
                    """,
                    arguments: [Self.ftsPhraseLiteral(trimmed)]
                )
            } else {
                let pattern = "%\(Self.escapeLikePattern(trimmed))%"
                rows = try Row.fetchAll(
                    db,
                    sql: """
                    SELECT payload_json
                    FROM food_library_item
                    WHERE name LIKE ? ESCAPE '\\' OR aliases_text LIKE ? ESCAPE '\\' OR category LIKE ? ESCAPE '\\'
                    ORDER BY name ASC
                    """,
                    arguments: [pattern, pattern, pattern]
                )
            }
            return try rows.map { try Self.decodeJSON($0["payload_json"] as String, as: FoodLibraryItem.self) }
        }
    }

    public func saveDailyNutritionLog(_ log: DailyNutritionLog) async throws {
        try await database.writer.write { db in
            try Self.saveDailyNutritionLogSync(db: db, log: log)
        }
    }

    static func saveDailyNutritionLogSync(db: Database, log: DailyNutritionLog) throws {
        let json = try encodeJSONString(log, label: "DailyNutritionLog")
        try db.execute(
            sql: """
            INSERT INTO daily_nutrition_log (day_key, diet_kcal, sport_kcal, surplus_kcal, day_complete, payload_json, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(day_key) DO UPDATE SET
                diet_kcal = excluded.diet_kcal,
                sport_kcal = excluded.sport_kcal,
                surplus_kcal = excluded.surplus_kcal,
                day_complete = excluded.day_complete,
                payload_json = excluded.payload_json,
                updated_at = excluded.updated_at
            """,
            arguments: [
                log.dayKey.isoString,
                log.dietKcal,
                log.sportKcal,
                log.calorieSurplusKcal,
                log.dietDayComplete,
                json,
                log.updatedAt.timeIntervalSince1970,
            ]
        )

        try db.execute(sql: "DELETE FROM meal_entry WHERE day_key = ?", arguments: [log.dayKey.isoString])
        for entry in log.entries {
            let entryJSON = try encodeJSONString(entry, label: "MealEntry")
            try db.execute(
                sql: """
                INSERT INTO meal_entry (
                    id, day_key, meal_type, food_id, food_name,
                    portion_amount, portion_unit, kcal, payload_json, recorded_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    entry.id.uuidString,
                    log.dayKey.isoString,
                    entry.mealType.rawValue,
                    entry.foodID,
                    entry.foodName,
                    entry.portionAmount,
                    entry.portionUnit,
                    entry.kcal,
                    entryJSON,
                    entry.recordedAt.timeIntervalSince1970,
                ]
            )
        }
    }

    static func loadDailyNutritionLogSync(db: Database, dayKey: DayKey) throws -> DailyNutritionLog? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT payload_json FROM daily_nutrition_log WHERE day_key = ?",
            arguments: [dayKey.isoString]
        ) else {
            return nil
        }
        return try decodeJSON(row["payload_json"] as String, as: DailyNutritionLog.self)
    }

    public func loadNutritionLogs(from startKey: DayKey? = nil, to endKey: DayKey? = nil) async throws -> [DailyNutritionLog] {
        try await database.writer.read { db in
            var sql = "SELECT payload_json FROM daily_nutrition_log WHERE 1=1"
            var args: [DatabaseValueConvertible?] = []
            if let startKey {
                sql += " AND day_key >= ?"
                args.append(startKey.isoString)
            }
            if let endKey {
                sql += " AND day_key <= ?"
                args.append(endKey.isoString)
            }
            sql += " ORDER BY day_key ASC"
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
            return try rows.map { try Self.decodeJSON($0["payload_json"] as String, as: DailyNutritionLog.self) }
        }
    }

    public func resetAll() async throws {
        try await database.writer.write { db in
            let tables = [
                "action_audit",
                "meal_entry",
                "daily_nutrition_log",
                "nutrition_target_plan",
                "nutrition_profile",
                "food_library_item",
                "workout_muscle_load",
                "workout_annotation",
                "workout",
                "deleted_healthkit_workout",
                "sleep_episode",
                "hourly_metric",
                "day_metric",
                "score_snapshot",
                "day_computed_artifact",
                "muscle_recovery",
                "check_in",
                "plan_item",
                "memory",
                "coach_message",
                "pattern_finding",
                "workout_template",
                "logged_workout_session",
                "sync_anchor",
            ]
            for table in tables {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }
}
