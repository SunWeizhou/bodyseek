import Foundation
import SwiftData

struct PersistedDailyHistoryDay: Equatable, Sendable {
    var snapshot: DailyHealthSnapshot
    var configVersion: String
}

/// Repository for querying historical DailyHealthSnapshot data from persisted records.
/// Complements SwiftDataDailyHealthSummaryRepository with trend-analysis queries.
final class HealthSnapshotRepository {
    private let modelContext: ModelContext
    private let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    /// Save a DailyHealthSnapshot from the scoring pipeline (upsert: one snapshot per day).
    /// Delegates to the canonical SwiftDataDailyHealthSummaryRepository.upsert.
    func saveDailySnapshot(_ snapshot: DailyHealthSnapshot) throws {
        try SwiftDataDailyHealthSummaryRepository(modelContext: modelContext).upsert(snapshot, calendar: calendar)
    }

    func saveDailySnapshot(
        _ snapshot: DailyHealthSnapshot,
        scoreEvidence: DailyScoreEvidenceEnvelope
    ) throws {
        try SwiftDataDailyHealthSummaryRepository(modelContext: modelContext).upsert(
            snapshot,
            scoreEvidence: scoreEvidence,
            calendar: calendar
        )
    }

    func reconcileIntradayBuckets(
        _ buckets: [IntradaySignalBucket],
        signal: HealthSignal,
        on date: Date,
        sourceRevision: String = "healthKit.v1"
    ) throws {
        let dayIdentifier = DailyHealthSummaryRecord.dayIdentifier(for: date, calendar: calendar)
        let signalRawValue = signal.rawValue
        let descriptor = FetchDescriptor<IntradaySignalBucketRecord>(
            predicate: #Predicate {
                $0.dayIdentifier == dayIdentifier
                    && $0.signalRawValue == signalRawValue
            }
        )
        let existing = try modelContext.fetch(descriptor)
        let incomingByID = Dictionary(uniqueKeysWithValues: buckets.map {
            let record = IntradaySignalBucketRecord(
                bucket: $0,
                sourceRevision: sourceRevision,
                calendar: calendar
            )
            return (record.id, (record, $0))
        })

        for record in existing {
            guard let incoming = incomingByID[record.id] else {
                modelContext.delete(record)
                continue
            }
            record.apply(
                bucket: incoming.1,
                sourceRevision: sourceRevision
            )
        }

        let existingIDs = Set(existing.map(\.id))
        for (id, incoming) in incomingByID where !existingIDs.contains(id) {
            modelContext.insert(incoming.0)
        }
        try modelContext.save()
    }

    func fetchIntradayBuckets(
        signal: HealthSignal,
        in range: DateRangeQuery
    ) throws -> [IntradaySignalBucketRecord] {
        let signalRawValue = signal.rawValue
        let start = range.start
        let end = range.end
        return try modelContext.fetch(FetchDescriptor<IntradaySignalBucketRecord>(
            predicate: #Predicate {
                $0.signalRawValue == signalRawValue
                    && $0.bucketStart >= start
                    && $0.bucketStart < end
            },
            sortBy: [SortDescriptor(\.bucketStart)]
        ))
    }

    /// Every signal in `[start, end)`, oldest bucket first. `end` is exclusive.
    func fetchIntradayBuckets(from start: Date, until end: Date) throws -> [IntradaySignalBucketRecord] {
        try modelContext.fetch(FetchDescriptor<IntradaySignalBucketRecord>(
            predicate: #Predicate {
                $0.bucketStart >= start && $0.bucketStart < end
            },
            sortBy: [SortDescriptor(\.bucketStart)]
        ))
    }

    /// Every persisted day, decoded through `DailyHealthSummaryRecord.toSnapshot()`.
    /// Yearly history cannot use the limited recent-window fetch. This avoids a
    /// date predicate because an anomalous stored date has crashed that path.
    func fetchAllSnapshots() throws -> [DailyHealthSnapshot] {
        try modelContext.fetch(FetchDescriptor<DailyHealthSummaryRecord>())
            .map { $0.toSnapshot() }
    }

    /// Baseline inputs for every persisted day, without decoding workout payloads.
    func fetchAllBaselinePoints() throws -> [LongTermBaselinePoint] {
        try modelContext.fetch(FetchDescriptor<DailyHealthSummaryRecord>())
            .map(\.longTermBaselinePoint)
    }

    /// Days inside `[start, end)`. `end` is exclusive, matching the summary
    /// repository and the metric chart filter. Each day is the canonical snapshot
    /// plus the stored config version used to recognize demo rows.
    func fetchHistory(from start: Date, until end: Date) throws -> [PersistedDailyHistoryDay] {
        try SwiftDataDailyHealthSummaryRepository(modelContext: modelContext)
            .fetch(in: DateRangeQuery(start: start, end: end))
            .map {
                PersistedDailyHistoryDay(
                    snapshot: $0.toSnapshot(),
                    configVersion: $0.configVersion
                )
            }
    }

    /// Fetch snapshots for the last N days (including today).
    func fetchSnapshots(days: Int, endingAt endDate: Date = Date()) throws -> [DailyHealthSnapshot] {
        let safeDays = max(days, 1)
        let range = DateRangeQuery.recentDays(safeDays, endingAt: endDate, calendar: calendar)
        // 记录层的 date 存的是日历午夜，而查询窗是 04:00 健康日边界：
        // 用日历日边界比较，否则最老一天（存于其 00:00，早于窗口 04:00 起点）
        // 会被恒久排除——42 天请求只返回 41 条，滚动基线系统性缺一天。
        let rangeStart = calendar.startOfDay(for: range.start)
        let rangeEnd = calendar.startOfDay(for: range.end)
        // Fetch without a date #Predicate and filter in memory. SwiftData's
        // #Predicate date comparison has been observed to trap (SIGTRAP) when a
        // stored row carries an anomalous `date`, hard-crashing the app on the
        // workout-save refresh path. Keeping the in-memory filter makes one bad
        // row unable to crash the fetch.
        // 性能（审计 H2）：dayIdentifier 唯一 ⇒ 每日历日至多一行。以降序排序 +
        // fetchLimit 让 SQL 层提前截断到「最近的 N 天」（LIMIT），
        // 避免 1100 天全表物化后再按窗口过滤；额外 +2 行余量覆盖
        // 健康日边界（04:00）可能多出的跨日记录。
        var descriptor = FetchDescriptor<DailyHealthSummaryRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = safeDays + 2
        let records = try modelContext.fetch(descriptor)
            .filter { $0.date >= rangeStart && $0.date < rangeEnd }
        // 恢复与历史一致的升序返回契约（调用方依赖按时间正序的基线计算）。
        return records.reversed().map { $0.toSnapshot() }
    }

    /// Fetch this week vs last week comparison data.
    /// Returns (thisWeek, lastWeek) snapshots with the most recent complete day as reference.
    func fetchWeeklyComparison(
        referenceDate: Date = Date()
    ) throws -> (thisWeek: [DailyHealthSnapshot], lastWeek: [DailyHealthSnapshot]) {
        let today = calendar.startOfDay(for: referenceDate)

        // Last 14 days of data
        let range = DateRangeQuery.recentDays(14, endingAt: referenceDate, calendar: calendar)
        let rangeStart = range.start
        let rangeEnd = range.end
        let descriptor = FetchDescriptor<DailyHealthSummaryRecord>(
            predicate: #Predicate { record in
                record.date >= rangeStart && record.date < rangeEnd
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let allRecords = try modelContext.fetch(descriptor).map { $0.toSnapshot() }

        // Split into this week (last 7 days) and last week (8-14 days ago)
        let weekBoundary = calendar.date(byAdding: .day, value: -7, to: today) ?? today

        let thisWeek = allRecords.filter { $0.date >= weekBoundary }
        let lastWeek = allRecords.filter { $0.date < weekBoundary }

        return (thisWeek, lastWeek)
    }

    /// Build weekly trend summary: compute average deltas (this week vs last week) for key metrics.
    func buildWeeklyTrendSummary(
        referenceDate: Date = Date()
    ) throws -> [String: String] {
        let (thisWeek, lastWeek) = try fetchWeeklyComparison(referenceDate: referenceDate)

        guard !thisWeek.isEmpty else {
            return ["note": "Insufficient data for weekly trend comparison."]
        }

        var trends: [String: String] = [:]

        // --- HRV ---
        let thisHrv = thisWeek.compactMap(\.hrvAverage)
        let lastHrv = lastWeek.compactMap(\.hrvAverage)
        if let thisAvg = averageOf(thisHrv), let lastAvg = averageOf(lastHrv), lastAvg > 0 {
            let delta = ((thisAvg - lastAvg) / lastAvg) * 100
            trends["hrv_delta_pct"] = String(format: "%+.1f%%", delta)
            trends["hrv_this_week_avg"] = String(format: "%.0f", thisAvg)
            trends["hrv_last_week_avg"] = String(format: "%.0f", lastAvg)
        }

        // --- Resting Heart Rate ---
        let thisRhr = thisWeek.compactMap(\.restingHeartRate)
        let lastRhr = lastWeek.compactMap(\.restingHeartRate)
        if let thisAvg = averageOf(thisRhr), let lastAvg = averageOf(lastRhr), lastAvg > 0 {
            let delta = ((thisAvg - lastAvg) / lastAvg) * 100
            trends["rhr_delta_pct"] = String(format: "%+.1f%%", delta)
            trends["rhr_this_week_avg"] = String(format: "%.0f", thisAvg)
            trends["rhr_last_week_avg"] = String(format: "%.0f", lastAvg)
        }

        // --- Sleep Score ---
        let thisSleep = thisWeek.compactMap(\.sleepScore)
        let lastSleep = lastWeek.compactMap(\.sleepScore)
        if let thisAvg = averageOf(thisSleep), let lastAvg = averageOf(lastSleep), lastAvg > 0 {
            let delta = ((thisAvg - lastAvg) / lastAvg) * 100
            trends["sleep_score_delta_pct"] = String(format: "%+.1f%%", delta)
            trends["sleep_score_this_week_avg"] = String(format: "%.0f", thisAvg)
        }

        // --- Recovery Score ---
        let thisRec = thisWeek.compactMap(\.recoveryScore)
        let lastRec = lastWeek.compactMap(\.recoveryScore)
        if let thisAvg = averageOf(thisRec), let lastAvg = averageOf(lastRec), lastAvg > 0 {
            let delta = ((thisAvg - lastAvg) / lastAvg) * 100
            trends["recovery_score_delta_pct"] = String(format: "%+.1f%%", delta)
            trends["recovery_score_this_week_avg"] = String(format: "%.0f", thisAvg)
        }

        // --- Strain Score ---
        let thisStrain = thisWeek.compactMap(\.strainScore)
        let lastStrain = lastWeek.compactMap(\.strainScore)
        if let thisAvg = averageOf(thisStrain), let lastAvg = averageOf(lastStrain), lastAvg > 0 {
            let delta = ((thisAvg - lastAvg) / lastAvg) * 100
            trends["strain_score_delta_pct"] = String(format: "%+.1f%%", delta)
            trends["strain_score_this_week_avg"] = String(format: "%.0f", thisAvg)
        }

        // --- Sleep Hours ---
        let thisSleepHrs = thisWeek.compactMap(\.sleepHours)
        if let thisAvg = averageOf(thisSleepHrs) {
            trends["sleep_hours_this_week_avg"] = String(format: "%.1f", thisAvg)
        }

        // --- Steps ---
        let thisSteps = thisWeek.compactMap(\.steps)
        if let thisAvg = averageOf(thisSteps) {
            trends["steps_this_week_avg"] = String(format: "%.0f", thisAvg)
        }

        // --- Stress Index ---
        let thisStress = thisWeek.compactMap(\.stressIndex)
        if let thisAvg = averageOf(thisStress) {
            trends["stress_index_this_week_avg"] = String(format: "%.0f", thisAvg)
        }

        // --- Day count for context ---
        trends["this_week_days"] = "\(thisWeek.count)"
        trends["last_week_days"] = "\(lastWeek.count)"

        return trends
    }

    private func averageOf(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Delete snapshots older than 90 days to prevent unbounded storage growth.
    func pruneOldSnapshots(keepingDays: Int = 90) throws {
        let cutoff = calendar.date(byAdding: .day, value: -keepingDays, to: Date()) ?? Date()
        let rangeStart = cutoff
        let descriptor = FetchDescriptor<DailyHealthSummaryRecord>(
            predicate: #Predicate { record in
                record.date < rangeStart
            }
        )
        let old = try modelContext.fetch(descriptor)
        guard !old.isEmpty else { return }
        for record in old {
            modelContext.delete(record)
        }
        try modelContext.save()
    }
}
