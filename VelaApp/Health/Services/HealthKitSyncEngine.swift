import Foundation
import SwiftData
@preconcurrency import HealthKit

struct HealthSyncCursorState: Codable, Equatable {
    var lastSuccessfulSyncAt: Date?
    var pendingDirtyDayIdentifiers: Set<String> = []
}

struct HealthSyncPlan: Equatable {
    var rawRefreshDays: [Date]
    var scoreRecomputeDays: [Date]
}

struct HealthSyncPlanner {
    static func plan(
        requestedDays: Int,
        endingAt endDate: Date,
        cachedDays: Set<Date>,
        state: HealthSyncCursorState,
        forceRefreshRecentDays: Int,
        calendar: Calendar
    ) -> HealthSyncPlan {
        let endDay = calendar.startOfDay(for: endDate)
        let totalDays = max(requestedDays, 1) + 42
        let allDays = (0..<totalDays).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: endDay).map(calendar.startOfDay(for:))
        }
        let recentCutoff = calendar.date(
            byAdding: .day,
            value: -max(0, forceRefreshRecentDays - 1),
            to: endDay
        ) ?? endDay
        let cursorDay = state.lastSuccessfulSyncAt.map(calendar.startOfDay(for:))

        let rawDays = allDays.filter { day in
            let identifier = DailyHealthSummaryRecord.dayIdentifier(for: day, calendar: calendar)
            return !cachedDays.contains(day)
                || day >= recentCutoff
                || state.pendingDirtyDayIdentifiers.contains(identifier)
                || cursorDay.map { day >= $0 } == true
        }
        .sorted()

        let targetStart = calendar.date(
            byAdding: .day,
            value: -max(0, requestedDays - 1),
            to: endDay
        ) ?? endDay
        let scoreDays: [Date]
        if state.lastSuccessfulSyncAt == nil {
            scoreDays = allDays.filter { $0 >= targetStart }.sorted()
        } else if let earliestChanged = rawDays.first {
            scoreDays = allDays.filter { $0 >= min(earliestChanged, targetStart) }.sorted()
        } else {
            scoreDays = []
        }

        return HealthSyncPlan(rawRefreshDays: rawDays, scoreRecomputeDays: scoreDays)
    }
}

final class HealthSyncCursorStore {
    private let defaults: UserDefaults
    private let key = "vela.healthSync.cursor.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> HealthSyncCursorState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(HealthSyncCursorState.self, from: data) else {
            return HealthSyncCursorState()
        }
        return state
    }

    func save(_ state: HealthSyncCursorState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    func markDirty(_ date: Date, calendar: Calendar = .current) {
        var state = load()
        state.pendingDirtyDayIdentifiers.insert(
            DailyHealthSummaryRecord.dayIdentifier(for: date, calendar: calendar)
        )
        save(state)
    }
}

@MainActor
final class HealthKitSyncEngine {
    private let queryService: HealthQueryService
    private let modelContext: ModelContext
    private let calendar: Calendar
    private let cursorStore: HealthSyncCursorStore

    init(
        queryService: HealthQueryService,
        modelContext: ModelContext,
        calendar: Calendar = .current,
        cursorStore: HealthSyncCursorStore = HealthSyncCursorStore()
    ) {
        self.queryService = queryService
        self.modelContext = modelContext
        self.calendar = calendar
        self.cursorStore = cursorStore
    }

    func markDirty(_ date: Date) {
        cursorStore.markDirty(date, calendar: calendar)
    }

    /// Backfills and calculates metrics for the past N calendar days.
    /// This runs a two-pass synchronization to prevent empty baseline bootstrapping.
    func syncPastDays(
        _ days: Int,
        endingAt endDate: Date = Date(),
        forceRefreshRecentDays: Int? = nil
    ) async throws {
        let snapshotRepo = HealthSnapshotRepository(modelContext: modelContext, calendar: calendar)

        // Pass 1: Build and save the raw daily snapshots from HealthKit for the last (42 + days)
        // This ensures the database already has raw data for rolling baseline calculations in Pass 2!
        let totalDaysToSync = 42 + days
        let cachedSnapshots = (try? snapshotRepo.fetchSnapshots(days: totalDaysToSync, endingAt: endDate)) ?? []
        let cachedDays = Set(cachedSnapshots.map { calendar.startOfDay(for: $0.date) })
        let refreshWindow = forceRefreshRecentDays ?? min(days, 3)
        let cursorState = cursorStore.load()
        let plan = HealthSyncPlanner.plan(
            requestedDays: days,
            endingAt: endDate,
            cachedDays: cachedDays,
            state: cursorState,
            forceRefreshRecentDays: refreshWindow,
            calendar: calendar
        )
        var failedDayIdentifiers = Set<String>()

        for dayStart in plan.rawRefreshDays {
            // Build raw daily snapshot from HealthKit and local workouts
            let buildResult = await DailySnapshotBuilder.buildSnapshot(
                for: dayStart,
                queryService: queryService,
                calendar: calendar,
                modelContext: modelContext
            )
            let snapshot = buildResult.snapshot
            let dayIdentifier = DailyHealthSummaryRecord.dayIdentifier(for: dayStart, calendar: calendar)

            // 查询失败（区别于「无数据」）的组件必须让当天保持 dirty 以便重试，
            // 同时把失败写入诊断链（Trust Center 可见）。核心健康组件全部失败时
            // 没有可信数据：跳过持久化，避免用全空快照覆盖已有记录（审计 C2）。
            if !buildResult.queryFailures.isEmpty {
                failedDayIdentifiers.insert(dayIdentifier)
                PipelineDiagnosticsLogger.log(
                    modelContext: modelContext,
                    stage: "HealthKitSyncEngine.syncPastDays.queryFailures",
                    isSuccess: false,
                    summary: "Day \(dayStart) query failures: \(buildResult.queryFailures.map(\.rawValue).joined(separator: ",")). Marked dirty for retry."
                )
                if !buildResult.hasCoreData {
                    continue
                }
            }

            // Save the raw snapshot
            do {
                try snapshotRepo.saveDailySnapshot(snapshot)
                try WorkoutAggregationService.shared.aggregateDay(
                    date: dayStart,
                    modelContext: modelContext,
                    calendar: calendar
                )
                try modelContext.save()
            } catch {
                failedDayIdentifiers.insert(
                    DailyHealthSummaryRecord.dayIdentifier(for: dayStart, calendar: calendar)
                )
                PipelineDiagnosticsLogger.log(
                    modelContext: modelContext,
                    stage: "HealthKitSyncEngine.syncPastDays.saveRawSnapshot",
                    isSuccess: false,
                    summary: "Failed to save raw daily snapshot for \(dayStart).",
                    error: error
                )
            }
        }

        // 三年长线基准点（预拉取全量点集，在日循环中按各历史日 strict cutoff 过滤）：
        // 保证历史评分仅使用截至当天的已知数据，消除前视偏差（Lookahead bias），
        // 且两条评分路径的 Layer 3 修正语义一致。
        let allBaselinePoints = ((try? modelContext.fetch(FetchDescriptor<DailyHealthSummaryRecord>())) ?? [])
            .map(\.longTermBaselinePoint)

        // Pass 2: Calculate scores day-by-day, pulling correct rolling raw baselines
        for dayStart in plan.scoreRecomputeDays {
            // Load this day's snapshot from SwiftData
            let existingSnapshots: [DailyHealthSnapshot]
            do {
                existingSnapshots = try snapshotRepo.fetchSnapshots(days: 1, endingAt: dayStart)
            } catch {
                failedDayIdentifiers.insert(
                    DailyHealthSummaryRecord.dayIdentifier(for: dayStart, calendar: calendar)
                )
                PipelineDiagnosticsLogger.log(
                    modelContext: modelContext,
                    stage: "HealthKitSyncEngine.syncPastDays.fetchExistingSnapshot",
                    isSuccess: false,
                    summary: "Failed to fetch existing snapshot for \(dayStart).",
                    error: error
                )
                existingSnapshots = []
            }
            guard var snapshot = existingSnapshots.first(where: { calendar.isDate($0.date, inSameDayAs: dayStart) }) else { continue }
            
            // Fetch past 42 days of historical snapshots (which already have raw data from Pass 1!)
            let pastSnapshots: [DailyHealthSnapshot]
            do {
                pastSnapshots = try snapshotRepo.fetchSnapshots(days: 42, endingAt: dayStart)
            } catch {
                PipelineDiagnosticsLogger.log(
                    modelContext: modelContext,
                    stage: "HealthKitSyncEngine.syncPastDays.fetchHistory",
                    isSuccess: false,
                    summary: "Failed to fetch historical snapshots for \(dayStart).",
                    error: error
                )
                pastSnapshots = []
            }
            let historicalSnapshots = pastSnapshots.filter { !calendar.isDate($0.date, inSameDayAs: dayStart) }
            
            // 历史日的观测 cutoff：严格截止到该日末（或整体同步结束点 endDate），防止未来生理样本改变历史评分
            let dayEndOfDay = calendar.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? dayStart
            let dayCutoff = min(endDate, dayEndOfDay)

            let historicalBaselinePoints = allBaselinePoints.filter { $0.date <= dayCutoff }
            let dayLongTermReport = LongTermBaselineEngine.compute(
                points: historicalBaselinePoints,
                today: dayCutoff,
                calendar: calendar
            )

            // Run computation pipeline with dayCutoff
            let hkCharacteristics = (queryService as? HealthKitQueryService)?.queryCharacteristics()
            let pipeline = DailyHealthComputation(
                calendar: calendar,
                now: dayCutoff,
                profile: .current(
                    ageFallback: hkCharacteristics?.age,
                    biologicalSexFallback: hkCharacteristics?.biologicalSex
                )
            )
            let metrics = pipeline.compute(
                for: snapshot,
                history: historicalSnapshots,
                longTermBaselines: dayLongTermReport
            )

            snapshot = metrics.applying(to: snapshot)

            do {
                try snapshotRepo.saveDailySnapshot(
                    snapshot,
                    scoreEvidence: DailyScoreEvidenceEnvelope(
                        evidence: metrics,
                        persistedAt: endDate
                    )
                )
                try WorkoutAggregationService.shared.aggregateDay(
                    date: dayStart,
                    modelContext: modelContext,
                    calendar: calendar
                )
                try modelContext.save()
            } catch {
                // A failed score save must be retried. Mark the day dirty so the
                // cursor reconciliation below keeps it in pendingDirtyDayIdentifiers
                // instead of silently dropping it (which previously left the user
                // stuck on a stale/empty score for that day forever).
                failedDayIdentifiers.insert(
                    DailyHealthSummaryRecord.dayIdentifier(for: dayStart, calendar: calendar)
                )
                PipelineDiagnosticsLogger.log(
                    modelContext: modelContext,
                    stage: "HealthKitSyncEngine.syncPastDays.saveComputedSnapshot",
                    isSuccess: false,
                    summary: "Failed to save computed daily snapshot for \(dayStart).",
                    error: error
                )
            }
        }
        
        // Log a successful sync run
        PipelineDiagnosticsLogger.log(
            modelContext: modelContext,
            stage: "HealthKitSyncEngine.syncPastDays.completed",
            isSuccess: failedDayIdentifiers.isEmpty,
            summary: "Synced and computed metrics for past \(days) days. Failed days: \(failedDayIdentifiers.count)."
        )
        var completedState = cursorState
        // 有失败日时不得推进 lastSuccessfulSyncAt：否则下次同步会误认为数据已新鲜，
        // 失败日永远停留在脏状态（审计 C2）。
        if failedDayIdentifiers.isEmpty {
            completedState.lastSuccessfulSyncAt = endDate
        }
        let processedIdentifiers = Set(plan.rawRefreshDays.map {
            DailyHealthSummaryRecord.dayIdentifier(for: $0, calendar: calendar)
        })
        completedState.pendingDirtyDayIdentifiers.subtract(
            processedIdentifiers.subtracting(failedDayIdentifiers)
        )
        completedState.pendingDirtyDayIdentifiers.formUnion(failedDayIdentifiers)
        cursorStore.save(completedState)
        try? syncTrainingIntelligenceInsights(endingAt: endDate)

        // DailySummaryUseCase owns plan derivation after this method returns.
        // Calling DailyPlanRefreshCoordinator here would re-enter health sync and
        // create a sync -> plan -> sync feedback loop with continuous database writes.
    }

    private func syncTrainingIntelligenceInsights(endingAt endDate: Date) throws {
        let snapshots = try HealthSnapshotRepository(modelContext: modelContext, calendar: calendar)
            .fetchSnapshots(days: 60, endingAt: endDate)
        let strengthWorkouts = try modelContext.fetch(FetchDescriptor<StrengthWorkoutRecord>())
        let foodLogs = try modelContext.fetch(FetchDescriptor<FoodLogRecord>())
        let journalEntries = try modelContext.fetch(FetchDescriptor<JournalEntryRecord>())
        let service = TrainingResponseInsightService()
        _ = try service.captureTrainingResponses(
            modelContext: modelContext,
            snapshots: snapshots,
            workouts: strengthWorkouts,
            calendar: calendar
        )
        let responses = try modelContext.fetch(FetchDescriptor<TrainingResponseRecord>())
        _ = try service.persistWeeklyBodyReportIfNeeded(
            modelContext: modelContext,
            snapshots: snapshots,
            foodLogs: foodLogs,
            journalEntries: journalEntries,
            strengthWorkouts: strengthWorkouts,
            trainingResponses: responses,
            endingAt: endDate,
            calendar: calendar
        )
        _ = try service.persistMonthlyBodyReportIfNeeded(
            modelContext: modelContext,
            snapshots: snapshots,
            foodLogs: foodLogs,
            journalEntries: journalEntries,
            strengthWorkouts: strengthWorkouts,
            endingAt: endDate,
            calendar: calendar
        )
        _ = try service.proposeStableTrainingResponses(
            modelContext: modelContext,
            responses: responses
        )
    }
}

final class DailySnapshotBuilder {
    /// HealthKit 快照的查询组件。用于区分「该组件无数据」与「该组件查询失败」。
    enum HealthSnapshotComponent: String, Equatable, CaseIterable, Sendable {
        case sleep
        case recovery
        case strain
        case body
        case extended
    }

    /// buildSnapshot 的返回：快照 + 失败的查询组件清单。
    /// 失败组件未被当成「无数据」吞掉——否则授权被拒/数据库异常会被静默
    /// 持久化为全空快照，并错误推进 lastSuccessfulSyncAt（审计 C2）。
    struct Result: Sendable {
        var snapshot: DailyHealthSnapshot
        var queryFailures: [HealthSnapshotComponent]
        var diagnostics: [HealthQueryDiagnostic] = []

        /// 核心健康组件（sleep/recovery/strain/body）是否至少有一个成功。
        /// 全部失败时没有可信数据，调用方不应持久化「无数据」快照覆盖已有记录。
        var hasCoreData: Bool {
            let core: Set<HealthSnapshotComponent> = [.sleep, .recovery, .strain, .body]
            return !core.isSubset(of: Set(queryFailures))
        }
    }

    @MainActor
    static func buildSnapshot(
        for date: Date,
        queryService: HealthQueryService,
        calendar: Calendar,
        modelContext: ModelContext? = nil
    ) async -> Result {
        let dayStart = calendar.startOfDay(for: date)
        let range = DateRangeQuery.singleDay(dayStart, calendar: calendar)

        // Query components independently。查询失败（区别于「无数据」）必须显式记录：
        // 授权被拒/参数错误不再被吞成空数据（仅 errorNoData 走空数据分支）。
        var queryFailures: [HealthSnapshotComponent] = []
        var diagnostics: [HealthQueryDiagnostic] = []

        let (sleepValue, sleepDiagnostic) = await queryComponent(
            .sleep, in: range
        ) { try await queryService.sleepSummary(in: range) }
        let sleep: SleepSummary? = sleepValue ?? nil
        if let sleepDiagnostic {
            diagnostics.append(sleepDiagnostic)
            if sleepDiagnostic.outcome.isFailure { queryFailures.append(.sleep) }
        }

        let (recoveryValue, recoveryDiagnostic) = await queryComponent(
            .recovery, in: range
        ) { try await queryService.recoveryMetrics(in: range) }
        let recovery: RecoveryMetricSummary? = recoveryValue
        if let recoveryDiagnostic {
            diagnostics.append(recoveryDiagnostic)
            if recoveryDiagnostic.outcome.isFailure { queryFailures.append(.recovery) }
        }

        let (strainValue, strainDiagnostic) = await queryComponent(
            .strain, in: range
        ) { try await queryService.strainSummary(in: range) }
        let strain: StrainActivitySummary? = strainValue
        if let strainDiagnostic {
            diagnostics.append(strainDiagnostic)
            if strainDiagnostic.outcome.isFailure { queryFailures.append(.strain) }
        }

        let (bodyValue, bodyDiagnostic) = await queryComponent(
            .body, in: range
        ) { try await queryService.bodyMetrics(in: range) }
        let body: BodyMetricsSummary? = bodyValue
        if let bodyDiagnostic {
            diagnostics.append(bodyDiagnostic)
            if bodyDiagnostic.outcome.isFailure { queryFailures.append(.body) }
        }

        let hkQueryService = queryService as? HealthKitQueryService
        let (extendedValue, extendedDiagnostic) = await queryComponent(
            .extended, in: range
        ) {
            if let hkQueryService {
                return try await hkQueryService.extendedMetrics(in: range)
            }
            return ExtendedHealthMetrics()
        }
        let extended: ExtendedHealthMetrics = extendedValue ?? ExtendedHealthMetrics()
        if let extendedDiagnostic {
            diagnostics.append(extendedDiagnostic)
            if extendedDiagnostic.outcome.isFailure { queryFailures.append(.extended) }
        }
        diagnostics.append(contentsOf: queryService.consumeDiagnostics())

        var snapshot = DailyHealthSnapshot(date: dayStart)
        if let modelContext {
            let dayIdentifier = DailyHealthSummaryRecord.dayIdentifier(for: dayStart, calendar: calendar)
            let descriptor = FetchDescriptor<DailyHealthSummaryRecord>(
                predicate: #Predicate<DailyHealthSummaryRecord> { $0.dayIdentifier == dayIdentifier }
            )
            if let existing = (try? modelContext.fetch(descriptor))?.first {
                snapshot = existing.toSnapshot()
            }
        }
        
        // Populate sleep
        if let sleep = sleep {
            snapshot.sleepHours = Double(sleep.totalSleepMinutes) / 60.0
            let rawEfficiency = sleep.stageMinutes[.inBed].map { inBed in
                inBed > 0 ? Double(sleep.totalSleepMinutes) / Double(inBed) : 0.85
            } ?? 0.85
            snapshot.sleepEfficiency = HealthUnitNormalizer.normalizeSleepEfficiency(rawEfficiency)
            
            let total = Double(sleep.totalSleepMinutes)
            if total > 0 {
                let rawDeep = (sleep.stageMinutes[.deep].map { Double($0) } ?? 0.0) / total
                let rawRem = (sleep.stageMinutes[.rem].map { Double($0) } ?? 0.0) / total
                snapshot.deepSleepPercent = HealthUnitNormalizer.normalizeSleepStagePercent(rawDeep)
                snapshot.remSleepPercent = HealthUnitNormalizer.normalizeSleepStagePercent(rawRem)
            }
            if let bedtime = sleep.bedtime { snapshot.bedtime = bedtime }
            if let wakeTime = sleep.wakeTime { snapshot.wakeTime = wakeTime }
            
            // Core Metrics v1.3 sub-metrics
            if let awake = sleep.stageMinutes[.awake].map({ Double($0) }) { snapshot.awakeMinutes = awake }
            let awakeEpisodes = sleep.segments.filter { $0.stage == .awake && $0.end.timeIntervalSince($0.start) >= 120 }.count
            if awakeEpisodes > 0 || snapshot.awakeEpisodeCount == nil { snapshot.awakeEpisodeCount = awakeEpisodes }
            if let deep = sleep.stageMinutes[.deep].map({ Double($0) }) { snapshot.deepSleepMinutes = deep }
            if let rem = sleep.stageMinutes[.rem].map({ Double($0) }) { snapshot.remSleepMinutes = rem }
        }

        // Populate recovery
        if let recovery = recovery {
            if let hrv = recovery.hrvMilliseconds { snapshot.hrvAverage = hrv }
            if let hrvRmssd = recovery.hrvRmssdMilliseconds { snapshot.hrvRmssdMilliseconds = hrvRmssd }
            if let rhr = recovery.restingHeartRate { snapshot.restingHeartRate = rhr }
            if let rr = recovery.respiratoryRate { snapshot.respiratoryRate = rr }
            snapshot.hrvObservedAt = recovery.hrvObservedAt
            snapshot.rhrObservedAt = recovery.rhrObservedAt
            snapshot.hrvObservedWindow = recovery.hrvObservedWindow
            snapshot.rhrObservedWindow = recovery.rhrObservedWindow
        }

        // Populate strain
        if let strain = strain {
            if let steps = strain.stepCount { snapshot.steps = steps }
            if let cal = strain.activeEnergyKilocalories { snapshot.activeCalories = cal }
            if let min = strain.exerciseMinutes { snapshot.activeMinutes = min }
            
            // Consolidate workouts using WorkoutAggregationService
            let aggregated: [WorkoutSummary]
            if let modelContext = modelContext {
                let deletedRecords = (try? modelContext.fetch(FetchDescriptor<DeletedWorkoutRecord>())) ?? []
                let blacklistedIDs = Set(deletedRecords.map(\.id))
                let filteredWorkouts = strain.workouts.filter { !blacklistedIDs.contains($0.id.uuidString) }

                try? WorkoutAggregationService.shared.upsertHealthKitWorkoutEvents(
                    filteredWorkouts,
                    on: dayStart,
                    modelContext: modelContext,
                    calendar: calendar
                )
                aggregated = WorkoutAggregationService.shared.aggregateWorkouts(
                    healthKitWorkouts: filteredWorkouts,
                    for: dayStart,
                    modelContext: modelContext,
                    calendar: calendar
                )
            } else {
                aggregated = strain.workouts
            }
            
            snapshot.workoutCount = aggregated.count
            snapshot.workoutDuration = aggregated.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) } / 60.0
            snapshot.workoutTypes = Set(aggregated.map(\.activityName)).sorted().joined(separator: ", ")
            snapshot.workouts = aggregated
        }

        // Populate body
        if let body = body {
            if let w = body.weightKilograms { snapshot.bodyWeight = w }
            if let fat = body.bodyFatPercentage { snapshot.bodyFatPercent = HealthUnitNormalizer.normalizeBodyFatPercentage(fat) }
            if let vo2 = body.vo2Max { snapshot.vo2Max = vo2 }
            if let bmi = extended.bmi { snapshot.bmi = bmi }
        }

        // Populate extended
        if let spo2 = extended.oxygenSaturation { snapshot.oxygenSaturation = HealthUnitNormalizer.normalizeOxygenSaturation(spo2) }
        snapshot.spo2ObservedAt = extended.oxygenSaturationObservedAt
        if let temp = extended.bodyTemperature { snapshot.wristTemperature = temp }

        return Result(snapshot: snapshot, queryFailures: queryFailures, diagnostics: diagnostics)
    }

    /// 执行单个 HealthKit 查询组件：无数据（benign）→ 返回 nil 且不记为失败；
    /// 真实查询错误（授权被拒、参数错误、数据库异常等）→ 返回 nil 且标记 failed。
    @MainActor
    private static func queryComponent<T>(
        _ component: HealthSnapshotComponent,
        in range: DateRangeQuery,
        _ operation: () async throws -> T
    ) async -> (value: T?, diagnostic: HealthQueryDiagnostic?) {
        do {
            return (try await operation(), nil)
        } catch {
            let outcome = HealthKitQueryOutcomeClassifier.classify(error)
            return (
                nil,
                HealthQueryDiagnostic(
                    component: component.rawValue,
                    outcome: outcome,
                    error: error
                )
            )
        }
    }
}

// MARK: - Historical backfill（三年 Apple 健康历史回填）

/// 纯分块规划：目标 3 年、每块 90 天、避开正常同步窗口（最近 7 天）、游标可续传。
enum HistoricalBackfillPlanner {
    static let targetYears = 3
    static let chunkDays = 90
    // 联通专项批次 3：45 → 7。正常同步只覆盖最近 3-7 天，此前 45 天边界
    // 会让「未打开 App 的中间日」永久缺失（热力图/年度统计出现空洞）。
    // 回填是 create-only（已存在日跳过），与正常同步重叠没有覆盖风险。
    static let syncBoundaryDays = 7

    static func targetEarliest(today: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .year, value: -targetYears, to: calendar.startOfDay(for: today))
            ?? calendar.startOfDay(for: today)
    }

    static func syncBoundaryStart(today: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -syncBoundaryDays, to: calendar.startOfDay(for: today))
            ?? calendar.startOfDay(for: today)
    }

    /// 下一块 [start, end) 与处理后新游标；nil = 已全部回填。
    static func nextChunk(
        today: Date,
        cursor: Date?,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date, newCursor: Date)? {
        let earliest = targetEarliest(today: today, calendar: calendar)
        let boundary = syncBoundaryStart(today: today, calendar: calendar)
        let nextEnd = calendar.startOfDay(for: cursor ?? boundary)
        guard nextEnd > earliest else { return nil }
        let start = max(
            earliest,
            calendar.date(byAdding: .day, value: -chunkDays, to: nextEnd) ?? nextEnd
        )
        guard start < nextEnd else { return nil }
        return (start, nextEnd, start)
    }

    /// (已完成天数, 总天数)：总天数 = 同步边界到 3 年前。
    static func progress(
        today: Date,
        cursor: Date?,
        calendar: Calendar = .current
    ) -> (completed: Int, total: Int) {
        let earliest = targetEarliest(today: today, calendar: calendar)
        let boundary = syncBoundaryStart(today: today, calendar: calendar)
        let total = max(0, calendar.dateComponents([.day], from: earliest, to: boundary).day ?? 0)
        let nextEnd = calendar.startOfDay(for: cursor ?? boundary)
        let completed = max(0, calendar.dateComponents([.day], from: nextEnd, to: boundary).day ?? 0)
        return (min(completed, total), total)
    }
}

struct HistoricalBackfillProgress: Equatable {
    var completedDays: Int
    var totalDays: Int

    var percent: Double {
        totalDays > 0 ? min(1, Double(completedDays) / Double(totalDays)) : 0
    }

    var isComplete: Bool {
        totalDays > 0 && completedDays >= totalDays
    }
}

/// 回填执行器：每块并行聚合 8 组逐日 HealthKit 数据，只写「尚无记录」的
/// 历史日（create-only，绝不覆盖正常同步生成的记录），游标存 UserDefaults。
@MainActor
struct HistoricalBackfillService {
    let queryService: any HealthQueryService
    let modelContext: ModelContext
    let calendar: Calendar

    // 联通专项批次 3：游标键升版 v2——边界从 45 天收窄到 7 天后，
    // 已回填用户的重跑游标从头开始（create-only，只补缺口不覆盖）。
    private static let cursorKey = "vela.historicalBackfill.nextChunkEnd.v2"

    static func storedCursor(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: cursorKey) as? Date
    }

    static func storeCursor(_ date: Date?, defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: cursorKey)
    }

    struct ChunkResult {
        var insertedDays: Int
        var chunkStart: Date
        var chunkEnd: Date
        var isComplete: Bool
    }

    private enum BackfillError: Error {
        /// The legacy historical adapter still needs the concrete HealthKit
        /// aggregation helpers (`dailyAverages`, `dailySleep`, ...). Keep this
        /// narrow cast at that adapter boundary while the shared service seam
        /// remains protocol-typed for previews/tests.
        case concreteHealthKitProviderRequired
    }

    func runNextChunk() async throws -> ChunkResult {
        guard let queryService = queryService as? HealthKitQueryService else {
            throw BackfillError.concreteHealthKitProviderRequired
        }
        let today = calendar.startOfDay(for: Date())
        guard let chunk = HistoricalBackfillPlanner.nextChunk(
            today: today,
            cursor: Self.storedCursor(),
            calendar: calendar
        ) else {
            return ChunkResult(insertedDays: 0, chunkStart: today, chunkEnd: today, isComplete: true)
        }

        async let hrv = queryService.dailyAverages(
            identifier: .heartRateVariabilitySDNN,
            unit: HKUnit.secondUnit(with: .milli),
            start: chunk.start, end: chunk.end, calendar: calendar
        )
        async let rhr = queryService.dailyAverages(
            identifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: chunk.start, end: chunk.end, calendar: calendar
        )
        async let sleep = queryService.dailySleep(start: chunk.start, end: chunk.end, calendar: calendar)
        async let steps = queryService.dailySums(
            identifier: .stepCount, unit: .count(),
            start: chunk.start, end: chunk.end, calendar: calendar
        )
        async let energy = queryService.dailySums(
            identifier: .activeEnergyBurned, unit: .kilocalorie(),
            start: chunk.start, end: chunk.end, calendar: calendar
        )
        async let weight = queryService.dailyMostRecent(
            identifier: .bodyMass, unit: .gramUnit(with: .kilo),
            start: chunk.start, end: chunk.end, calendar: calendar
        )
        async let bodyFat = queryService.dailyMostRecent(
            identifier: .bodyFatPercentage, unit: .percent(),
            start: chunk.start, end: chunk.end, calendar: calendar
        )
        async let workouts = queryService.workoutSummaries(
            in: DateRangeQuery(start: chunk.start, end: chunk.end)
        )

        let hrvValues = (try? await hrv) ?? [:]
        let rhrValues = (try? await rhr) ?? [:]
        let sleepValues = (try? await sleep) ?? [:]
        let stepValues = (try? await steps) ?? [:]
        let energyValues = (try? await energy) ?? [:]
        let weightValues = (try? await weight) ?? [:]
        let bodyFatValues = (try? await bodyFat) ?? [:]
        let workoutSummaries = (try? await workouts) ?? []

        // 训练按日历日聚合（与 aggregateDay 语义一致）
        var countsByDay: [Date: Int] = [:]
        var durationByDay: [Date: Double] = [:]
        var typesByDay: [Date: Set<String>] = [:]
        for workout in workoutSummaries {
            let day = calendar.startOfDay(for: workout.start)
            countsByDay[day, default: 0] += 1
            durationByDay[day, default: 0] += workout.end.timeIntervalSince(workout.start) / 60.0
            typesByDay[day, default: []].insert(workout.activityName)
        }

        // 已存在的日（create-only）
        let all = (try? modelContext.fetch(FetchDescriptor<DailyHealthSummaryRecord>())) ?? []
        var existing = Set<String>()
        for record in all {
            let day = calendar.startOfDay(for: record.date)
            if day >= chunk.start, day < chunk.end {
                existing.insert(record.dayIdentifier)
            }
        }

        var inserted = 0
        var day = chunk.start
        while day < chunk.end {
            let identifier = DailyHealthSummaryRecord.dayIdentifier(for: day, calendar: calendar)
            if !existing.contains(identifier) {
                let sleepDay = sleepValues[day]
                modelContext.insert(DailyHealthSummaryRecord(
                    dayIdentifier: identifier,
                    date: day,
                    hrvAverage: hrvValues[day],
                    restingHeartRate: rhrValues[day],
                    sleepHours: sleepDay?.sleepHours,
                    steps: stepValues[day],
                    activeCalories: energyValues[day],
                    workoutCount: countsByDay[day],
                    workoutTypes: typesByDay[day].map { $0.sorted().joined(separator: ", ") },
                    workoutDuration: durationByDay[day],
                    bodyWeight: weightValues[day],
                    bodyFatPercent: bodyFatValues[day],
                    deepSleepMinutes: sleepDay?.deepMinutes,
                    remSleepMinutes: sleepDay?.remMinutes
                ))
                inserted += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        try modelContext.save()
        Self.storeCursor(chunk.newCursor)
        let done = HistoricalBackfillPlanner.progress(today: today, cursor: chunk.newCursor, calendar: calendar)
        return ChunkResult(
            insertedDays: inserted,
            chunkStart: chunk.start,
            chunkEnd: chunk.end,
            isComplete: done.completed >= done.total
        )
    }
}

/// 回填协调器：跨页面存活的任务驱动 + 进度发布（个人页入口观察）。
@MainActor
final class HistoricalBackfillCoordinator: ObservableObject {
    static let shared = HistoricalBackfillCoordinator()

    @Published private(set) var progress = HistoricalBackfillProgress(completedDays: 0, totalDays: 1)
    @Published private(set) var isRunning = false
    @Published var lastError: String?

    private var task: Task<Void, Never>?

    private init() {}

    var stateText: String {
        if progress.isComplete { return "已完成" }
        if isRunning { return "回填中 \(Int(progress.percent * 100))%" }
        if progress.completedDays > 0 { return "已完成 \(Int(progress.percent * 100))% · 点按继续" }
        return "未开始"
    }

    func refreshState(calendar: Calendar = .current) {
        let p = HistoricalBackfillPlanner.progress(
            today: Date(),
            cursor: HistoricalBackfillService.storedCursor(),
            calendar: calendar
        )
        progress = HistoricalBackfillProgress(completedDays: p.completed, totalDays: p.total)
    }

    func start(queryService: any HealthQueryService, modelContext: ModelContext, calendar: Calendar = .current) {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        refreshState(calendar: calendar)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let service = HistoricalBackfillService(
                    queryService: queryService,
                    modelContext: modelContext,
                    calendar: calendar
                )
                while true {
                    try Task.checkCancellation()
                    let result = try await service.runNextChunk()
                    self.refreshState(calendar: calendar)
                    if result.isComplete { break }
                }
                VelaAppState.shared.markLocalDataChanged()
            } catch is CancellationError {
                // 用户取消：游标已保存，下次从断点继续。
            } catch {
                self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
        isRunning = false
    }
}
