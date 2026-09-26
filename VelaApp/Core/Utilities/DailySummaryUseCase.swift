import Foundation
import SwiftData

enum ActiveStatusSettings {
    static let statusKey = "vela_active_status"
    static let durationKey = "vela_active_status_duration"
    static let expiresAtKey = "vela_active_status_expires_at"
    static let startedAtKey = "vela_active_status_started_at"
    private static let validStatuses: Set<String> = ["active", "sick", "injured", "resting"]

    static func update(
        status: String,
        duration: String,
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        defaults.set(status, forKey: statusKey)
        guard status != "active" else {
            defaults.removeObject(forKey: durationKey)
            defaults.removeObject(forKey: expiresAtKey)
            defaults.removeObject(forKey: startedAtKey)
            return
        }
        defaults.set(now, forKey: startedAtKey)
        defaults.set(duration, forKey: durationKey)
        if let expiresAt = expirationDate(for: duration, now: now, calendar: calendar) {
            defaults.set(expiresAt, forKey: expiresAtKey)
        } else {
            defaults.removeObject(forKey: expiresAtKey)
        }
    }

    static func resolveCurrentStatus(
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> String {
        guard defaults.object(forKey: statusKey) != nil else {
            return "active"
        }

        let storedStatus = defaults.string(forKey: statusKey) ?? "active"
        guard validStatuses.contains(storedStatus) else {
            defaults.set("active", forKey: statusKey)
            defaults.removeObject(forKey: expiresAtKey)
            return "active"
        }

        if let expiresAt = defaults.object(forKey: expiresAtKey) as? Date,
           expiresAt <= now {
            defaults.set("active", forKey: statusKey)
            defaults.removeObject(forKey: expiresAtKey)
            return "active"
        }
        return storedStatus
    }

    /// Resolve a status for a selected day without leaking a newer current
    /// status into historical BodyState calculations. Older installs may not
    /// have a start timestamp; in that case non-active status is conservatively
    /// limited to today until the user updates it again.
    static func resolveStatus(
        at date: Date,
        now: Date = Date(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) -> String {
        let storedStatus = defaults.string(forKey: statusKey) ?? "active"
        guard validStatuses.contains(storedStatus), storedStatus != "active" else {
            return "active"
        }

        // Dashboard dates are normally start-of-day values. Compare calendar
        // days rather than instants so a status started later today applies to
        // today's snapshot, while a newer status cannot leak into history.
        let selectedDay = calendar.startOfDay(for: date)
        if let startedAt = defaults.object(forKey: startedAtKey) as? Date {
            let startedDay = calendar.startOfDay(for: startedAt)
            guard startedDay <= selectedDay else { return "active" }
        } else if !calendar.isDate(selectedDay, inSameDayAs: now) {
            return "active"
        }

        if let expiresAt = defaults.object(forKey: expiresAtKey) as? Date,
           calendar.startOfDay(for: expiresAt) <= selectedDay {
            return "active"
        }
        return storedStatus
    }

    static func journalFlags(now: Date = Date(), defaults: UserDefaults = .standard) -> Set<String> {
        let status = resolveCurrentStatus(now: now, defaults: defaults)
        guard ["sick", "injured", "resting"].contains(status) else { return [] }
        return [status]
    }

    private static func expirationDate(for duration: String, now: Date, calendar: Calendar) -> Date? {
        if duration == "长期" {
            return nil
        }
        if duration == "明天之前" {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        }
        guard let days = Int(duration.replacingOccurrences(of: "天", with: "")) else {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        }
        return calendar.date(byAdding: .day, value: days, to: now)
    }
}

/// SwiftData-backed adapter for the pure HealthTrendEngine seam.
///
/// DailySummaryUseCase deliberately keeps this adapter at the persistence
/// boundary: the scoring module receives only value-typed snapshots and the
/// long-term report. The regular Daily Health Computation path continues to
/// use its bounded 180-day history; this provider is reserved for the Brief's
/// multi-scale (including 3y) trend context.
struct DailySummaryHealthTrendHistoryProvider: HealthTrendHistoryProvider {
    let snapshots: [DailyHealthSnapshot]
    let longTermBaselines: LongTermBaselineReport?

    init(
        snapshots: [DailyHealthSnapshot],
        longTermBaselines: LongTermBaselineReport? = nil
    ) {
        self.snapshots = snapshots
        self.longTermBaselines = longTermBaselines
    }

    func history(
        endingAt selectedDay: Date,
        calendar: Calendar
    ) -> HealthTrendInput {
        // Keep the adapter's payload bounded to the requested trend horizon.
        // The engine still applies its own exact horizon windows and missing
        // value gates; this only avoids carrying unrelated future/old rows
        // across the boundary.
        let selectedDayStart = calendar.startOfDay(for: selectedDay)
        let end = calendar.date(byAdding: .day, value: 1, to: selectedDayStart) ?? selectedDay
        let start = calendar.date(
            byAdding: .day,
            value: -HealthTrendHorizon.threeYears.windowDays,
            to: selectedDayStart
        ) ?? selectedDayStart
        let boundedSnapshots = snapshots.filter { snapshot in
            snapshot.date >= start && snapshot.date < end
        }
        return HealthTrendInput(
            snapshots: boundedSnapshots,
            longTermBaselines: longTermBaselines
        )
    }
}

@MainActor
final class DailySummaryUseCase {
    nonisolated static let debugDemoConfigVersion = "\(VelaAppMetadata.configVersion).debug-demo"

    private let queryService: any HealthQueryService
    private let authorizationService: any HealthAuthorizationProviding
    private let calendar: Calendar
    private let syncCoordinator: AppSyncCoordinator?

    init(
        queryService: any HealthQueryService = HealthKitQueryService(),
        authorizationService: any HealthAuthorizationProviding = HealthAuthorizationService(),
        calendar: Calendar = .current,
        syncCoordinator: AppSyncCoordinator? = nil
    ) {
        self.queryService = queryService
        self.authorizationService = authorizationService
        self.calendar = calendar
        self.syncCoordinator = syncCoordinator
    }

    static func isDemoDataSeedingEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains("-velaSeedDemoData")
    }

    /// Stable, read-only dashboard projection for simulator screenshots. Unlike
    /// demo seeding, this does not mutate SwiftData or depend on an empty store.
    static func isPreviewDashboardEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains("-velaPreviewDashboard")
    }

    nonisolated static func cachedSource(configVersion: String) -> DashboardSummary.DataSource {
        configVersion == debugDemoConfigVersion ? .preview : .cache
    }

    func loadDashboard(
        for date: Date = Date(),
        modelContext: ModelContext? = nil,
        syncDays: Int = 3,
        shouldSyncHealthData: Bool = true
    ) async throws -> DashboardSummary {
        let now = date
        #if DEBUG
        if Self.isPreviewDashboardEnabled() {
            return PreviewDataFactory.makeDashboard(date: now)
        }
        #endif
        // `now` is the selected dashboard day (and may be historical). Keep a
        // separate wall-clock instant for resolving the currently stored status.
        let statusEvaluationNow = Date()
        
        // 1. Do not fan out HealthKit reads before the user has seen the initial
        // authorization request. This keeps an empty first launch responsive.
        let shouldDeferHealthSync = await authorizationService.shouldDeferBackgroundSync()
        if shouldSyncHealthData, let modelContext, !shouldDeferHealthSync {
            let syncEngine = HealthKitSyncEngine(queryService: queryService, modelContext: modelContext, calendar: calendar)
            if let syncCoordinator {
                let succeeded = await syncCoordinator.runReporting(source: .healthKit, force: false) {
                    try await syncEngine.syncPastDays(syncDays, endingAt: now, forceRefreshRecentDays: syncDays)
                }
                if succeeded {
                    VelaEventService.shared.log(
                        modelContext: modelContext,
                        type: VelaProductEventType.healthSyncSucceeded,
                        title: "Health data sync succeeded",
                        metadata: ["days": syncDays]
                    )
                } else {
                    let description = syncCoordinator.sourceStatuses[.healthKit]?.lastErrorDescription ?? "Unknown error"
                    PipelineDiagnosticsLogger.log(
                        modelContext: modelContext,
                        stage: "DailySummaryUseCase.loadDashboard.syncPastDays",
                        isSuccess: false,
                        summary: "HealthKit background sync failed: \(description)"
                    )
                    VelaEventService.shared.log(
                        modelContext: modelContext,
                        type: VelaProductEventType.healthSyncFailed,
                        title: "Health data sync failed",
                        detail: description,
                        metadata: ["days": syncDays]
                    )
                }
            } else {
                do {
                    try await syncEngine.syncPastDays(syncDays, endingAt: now, forceRefreshRecentDays: syncDays)
                    VelaEventService.shared.log(
                        modelContext: modelContext,
                        type: VelaProductEventType.healthSyncSucceeded,
                        title: "Health data sync succeeded",
                        metadata: ["days": syncDays]
                    )
                } catch {
                    PipelineDiagnosticsLogger.log(
                        modelContext: modelContext,
                        stage: "DailySummaryUseCase.loadDashboard.syncPastDays",
                        isSuccess: false,
                        summary: "HealthKit background sync failed.",
                        error: error
                    )
                    VelaEventService.shared.log(
                        modelContext: modelContext,
                        type: VelaProductEventType.healthSyncFailed,
                        title: "Health data sync failed",
                        detail: error.localizedDescription,
                        metadata: ["days": syncDays]
                    )
                }
            }
        }
        
        // 2. Query today's snapshot and 180-day history from SwiftData (supports 7d, 30d, 6m multi-scale trends)
        let snapshots180: [DailyHealthSnapshot]
        if let modelContext {
            let snapshotRepo = HealthSnapshotRepository(modelContext: modelContext, calendar: calendar)
            do {
                snapshots180 = try snapshotRepo.fetchSnapshots(days: 180, endingAt: now)
            } catch {
                PipelineDiagnosticsLogger.log(
                    modelContext: modelContext,
                    stage: "DailySummaryUseCase.loadDashboard.fetchSnapshots",
                    isSuccess: false,
                    summary: "Failed to fetch 180-day snapshot history.",
                    error: error
                )
                snapshots180 = []
            }
        } else {
            snapshots180 = []
        }

        // 2b. 三年长线基准延后到确认今日快照存在后再计算：空启动/无今日数据时
        // 不必先全表抓 1100 天记录再返回空 dashboard。
        var allDailySummaryRecords: [DailyHealthSummaryRecord] = []
        var allDailySummarySnapshots: [DailyHealthSnapshot] = []
        
        // 3. Locate today's snapshot
        let todaySnapshot = snapshots180.first(where: { calendar.isDate($0.date, inSameDayAs: now) })
        
        // 4. Require today's snapshot with real HealthKit-synced data. A debug
        // demo seed is opt-in through a launch argument; a normal device must
        // never receive synthetic health records simply because it is empty.
        guard let snapshot = todaySnapshot,
              (snapshot.hrvAverage != nil || snapshot.restingHeartRate != nil || snapshot.sleepHours != nil) else {
            #if DEBUG
            if Self.isDemoDataSeedingEnabled(),
               let modelContext {
                let repo = SwiftDataDailyHealthSummaryRepository(modelContext: modelContext)
                let range = DateRangeQuery.recentDays(30, endingAt: now, calendar: calendar)
                let existing = (try? repo.fetch(in: range)) ?? []
                if existing.isEmpty {
                    seedMockDataIfNeeded(modelContext: modelContext, now: now)
                    let dayStart = calendar.startOfDay(for: now)
                    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                    if let record = (try? repo.fetch(in: DateRangeQuery(start: dayStart, end: dayEnd)))?.first {
                        return makeDashboardFromRecord(record, source: .preview)
                    }
                }
            }
            // No real data and no mock seed — return empty dashboard
            return DashboardSummary.empty(date: now)
            #else
            return DashboardSummary.empty(date: now)
            #endif
        }
        
        // 4b. 三年长线基准（Layer 1/2/3 同源）：全量每日记录只取一次，
        // 后面 BodyModelBuilder 复用同一份，避免重复全表 fetch。
        let longTermReport: LongTermBaselineReport
        if let modelContext {
            allDailySummaryRecords = (try? modelContext.fetch(FetchDescriptor<DailyHealthSummaryRecord>())) ?? []
            allDailySummarySnapshots = allDailySummaryRecords.map { $0.toSnapshot() }
            // 长线基准是纯统计计算（审计 H2）：值类型 points 在 MainActor 上准备好后
            // 移出主线程执行，视图与交互不被 1100 天聚合阻塞。
            let baselinePoints = allDailySummaryRecords.map(\.longTermBaselinePoint)
            let computationCalendar = calendar
            longTermReport = await Task.detached {
                LongTermBaselineEngine.compute(points: baselinePoints, today: now, calendar: computationCalendar)
            }.value
        } else {
            longTermReport = LongTermBaselineEngine.compute(points: [], today: now, calendar: calendar)
        }

        // 5. Build clean DailyHealthContext and historical rolling baselines from snapshots
        let baselineSnapshots = snapshots180.filter {
            !calendar.isDate($0.date, inSameDayAs: now)
        }
        let hrvHistory = baselineSnapshots.compactMap(\.hrvAverage)
        let rhrHistory = baselineSnapshots.compactMap(\.restingHeartRate)
        let respHistory = baselineSnapshots.compactMap(\.respiratoryRate)
        // Get raw workout list from HealthKit for the current day to preserve sample details
        let todayRange = DateRangeQuery.today(containing: now, calendar: calendar)
        let todayStrainSummary = try? await queryService.strainSummary(in: todayRange)
        let rawHKWorkouts = todayStrainSummary?.workouts ?? []
        // [1] 修复：前台路径与同步路径同一黑名单语义——删除过的训练不得复活。
        // 修复二合一：此前 upsertHealthKitWorkoutEvents 只在后台同步调用，
        // 前台刷新时当天 HK 训练不会落成事件（记录缺失当天训练）；
        // 现在过滤 + upsert + 合并都用同一份过滤后列表。
        let workouts: [WorkoutSummary]
        if let modelContext {
            let deletedRecords = (try? modelContext.fetch(FetchDescriptor<DeletedWorkoutRecord>())) ?? []
            let blacklistedIDs = Set(deletedRecords.map(\.id))
            let filteredWorkouts = rawHKWorkouts.filter { !blacklistedIDs.contains($0.id.uuidString) }
            try? WorkoutAggregationService.shared.upsertHealthKitWorkoutEvents(
                filteredWorkouts,
                on: now,
                modelContext: modelContext,
                calendar: calendar
            )
            workouts = WorkoutAggregationService.shared.aggregateWorkouts(
                healthKitWorkouts: filteredWorkouts,
                for: now,
                modelContext: modelContext,
                calendar: calendar
            )
        } else {
            workouts = rawHKWorkouts
        }
        let liveExtended = (try? await queryService.extendedMetrics(in: todayRange)) ?? ExtendedHealthMetrics()
        // VO2max 不持久化（DailyHealthSummaryRecord 无此字段，避免触碰 SwiftData
        // versioned schema）；live 路径直接查询，快照内存值作兜底。
        let liveBody = (try? await queryService.bodyMetrics(
            in: DateRangeQuery.recentDays(90, endingAt: now, calendar: calendar)
        )) ?? BodyMetricsSummary()
        if let modelContext {
            await refreshIntradayBuckets(
                in: todayRange,
                modelContext: modelContext
            )
        }
        
        // 「昨夜」= 主睡眠段结束时刻落在今天健康日窗口内的夜晚；
        // sleepSummary 内部会向前扩展查询窗以捕获前夜入睡段。
        let resolvedSleep = try? await queryService.sleepSummary(in: DateRangeQuery.today(containing: now, calendar: calendar))
        let profileWeight = UserProfileSettings.weightKilograms()
        let profileHeight = UserProfileSettings.heightCentimeters()
        // 手动设置的档案值优先，Apple 健康数据兜底；清空手填字段即回退 Apple 健康。
        let resolvedWeight = profileWeight ?? snapshot.bodyWeight
        var extendedMetrics = liveExtended
        extendedMetrics.age = UserProfileSettings.age() ?? extendedMetrics.age
        extendedMetrics.heightCm = profileHeight ?? extendedMetrics.heightCm
        extendedMetrics.biologicalSex = UserProfileSettings.biologicalSex() ?? extendedMetrics.biologicalSex
        extendedMetrics.bmi = snapshot.bmi
            ?? extendedMetrics.bmi
            ?? UserProfileSettings.bodyMassIndex(
                weightKilograms: resolvedWeight,
                heightCentimeters: extendedMetrics.heightCm
            )
        extendedMetrics.oxygenSaturation = snapshot.oxygenSaturation ?? extendedMetrics.oxygenSaturation
        extendedMetrics.bodyTemperature = snapshot.wristTemperature ?? extendedMetrics.bodyTemperature
        
        let recoveryMetrics = RecoveryMetricSummary(
            hrvMilliseconds: snapshot.hrvAverage,
            hrvRmssdMilliseconds: snapshot.hrvRmssdMilliseconds,
            restingHeartRate: snapshot.restingHeartRate,
            sleepHeartRate: nil,
            respiratoryRate: snapshot.respiratoryRate
        )
        
        let recoveryBaseline = RecoveryMetricSummary(
            hrvMilliseconds: hrvHistory.count >= 5 ? calculateMedian(hrvHistory) : nil,
            restingHeartRate: rhrHistory.count >= 5 ? PersonalBaselineEngine.recencyWeightedMean(rhrHistory) : nil,
            sleepHeartRate: nil,
            respiratoryRate: respHistory.count >= 5 ? PersonalBaselineEngine.recencyWeightedMean(respHistory) : nil
        )
        
        let context = DailyHealthContext(
            date: now,
            sleepSummary: resolvedSleep,
            recoveryMetrics: recoveryMetrics,
            recoveryBaseline: recoveryBaseline,
            strainToday: StrainActivitySummary(
                activeEnergyKilocalories: snapshot.activeCalories,
                exerciseMinutes: snapshot.activeMinutes ?? snapshot.workoutDuration,
                stepCount: snapshot.steps,
                workouts: workouts
            ),
            strainBaselineDaily: StrainActivitySummary(workouts: []),
            bodyMetrics: BodyMetricsSummary(
                vo2Max: liveBody.vo2Max ?? snapshot.vo2Max,
                weightKilograms: resolvedWeight,
                bodyFatPercentage: snapshot.bodyFatPercent,
                leanBodyMassKilograms: nil
            ),
            extendedMetrics: extendedMetrics
        )
        
        // 6. Run the unified computation pipeline. HealthKitSyncEngine uses the same entry point,
        // so background sync, dashboard and AI context read identical score semantics.
        var pipelineSnapshot = snapshot
        pipelineSnapshot.workouts = workouts
        pipelineSnapshot.workoutCount = workouts.count
        pipelineSnapshot.workoutDuration = workouts.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) / 60.0 }
        pipelineSnapshot.activeMinutes = snapshot.activeMinutes ?? pipelineSnapshot.workoutDuration
        pipelineSnapshot.sleepHours = pipelineSnapshot.sleepHours ?? context.sleepSummary.map { Double($0.totalSleepMinutes) / 60.0 }
        pipelineSnapshot.bedtime = pipelineSnapshot.bedtime ?? context.sleepSummary?.bedtime
        pipelineSnapshot.wakeTime = pipelineSnapshot.wakeTime ?? context.sleepSummary?.wakeTime
        pipelineSnapshot.awakeMinutes = pipelineSnapshot.awakeMinutes ?? context.sleepSummary?.stageMinutes[.awake].map { Double($0) }
        pipelineSnapshot.deepSleepMinutes = pipelineSnapshot.deepSleepMinutes ?? context.sleepSummary?.stageMinutes[.deep].map { Double($0) }
        pipelineSnapshot.remSleepMinutes = pipelineSnapshot.remSleepMinutes ?? context.sleepSummary?.stageMinutes[.rem].map { Double($0) }
        pipelineSnapshot.awakeEpisodeCount = pipelineSnapshot.awakeEpisodeCount ?? context.sleepSummary?.segments.filter { $0.stage == .awake && $0.end.timeIntervalSince($0.start) >= 120 }.count

        let historicalSnapshots = snapshots180.filter { !calendar.isDate($0.date, inSameDayAs: now) }
        // F10 修复：历史日评分用日末评估时刻（与同步引擎一致），
        // 避免 hoursSinceWake / 训练恢复窗口在午夜与日末之间漂移。
        let evaluationNow = calendar.isDateInToday(now)
            ? now
            : (calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now)
        // F1/M1 修复：前台重算必须携带与同步引擎一致的 HealthKit 年龄/性别兜底，
        // 否则覆盖持久化分数时会把「性别系数 / maxHR→年龄链」退回 unknown/other。
        let metrics = DailyHealthComputation(
            calendar: calendar,
            now: evaluationNow,
            profile: .current(
                ageFallback: extendedMetrics.age,
                biologicalSexFallback: extendedMetrics.biologicalSex
            )
        ).compute(
            for: pipelineSnapshot,
            history: historicalSnapshots,
            longTermBaselines: longTermReport
        )
        let sleepScore = metrics.sleepScore
        let resolvedSleepSummary = DashboardMetricProjection.resolvedSleepSummary(
            from: context,
            sleepScore: sleepScore.value
        )
        let recovery = metrics.recovery
        let strain = metrics.strain
        let stress = metrics.stress
        let energy = metrics.energy
        
        let healthAge = HealthAgeTrendEngine().calculate(
            from: DashboardMetricProjection.healthAge(
                from: context,
                recovery: recovery,
                sleepScore: sleepScore,
                strain: strain
            )
        )
        
        var activePlan: TrainingPlanRecord?
        var currentDailySummary: DailyHealthSummaryRecord?
        var planResolutionEvents: [WorkoutEventRecord] = []
        var recentWorkoutEvents: [WorkoutEventRecord] = []
        var recentStrengthWorkouts: [StrengthWorkoutRecord] = []
        var recentTrainingResponses: [TrainingResponseRecord] = []
        var todayFoodLogs: [FoodLogRecord] = []
        var recentJournalEntries: [JournalEntryRecord] = []
        var bodyModelState: BodyModelState? = nil
        var trainingPreference: TrainingPreferenceProfile? = nil
        if let modelContext {
            let activePlanFetch = FetchDescriptor<TrainingPlanRecord>(
                predicate: #Predicate<TrainingPlanRecord> { $0.isActive }
            )
            activePlan = (try? modelContext.fetch(activePlanFetch))?.first

            // TrainingDecisionKernel 需要与训练页相同的计划日解析事实：
            // 取计划开始以来的全部事件（不含未来），让已完成日/逾期日逻辑一致。
            if let activePlan {
                let selectedDayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
                let planEventStart = min(activePlan.startDate, selectedDayEnd)
                let planEventFetch = FetchDescriptor<WorkoutEventRecord>(
                    predicate: #Predicate<WorkoutEventRecord> {
                        $0.startedAt >= planEventStart && $0.startedAt < selectedDayEnd
                    },
                    sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
                )
                planResolutionEvents = (try? modelContext.fetch(planEventFetch)) ?? []
            }

            // BodyStateKernel 的近期活动证据始终使用真实近 48h 事件；
            // 计划解析事件和近期证据分开，避免有活跃计划时丢失计划开始前的近期活动。
            let recentEventStart = calendar.date(byAdding: .hour, value: -48, to: now) ?? now
            var recentEventFetch = FetchDescriptor<WorkoutEventRecord>(
                predicate: #Predicate<WorkoutEventRecord> {
                    $0.startedAt >= recentEventStart && $0.startedAt <= now
                },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            recentEventFetch.fetchLimit = 100
            recentWorkoutEvents = (try? modelContext.fetch(recentEventFetch)) ?? []

            let dayIdentifier = DailyHealthSummaryRecord.dayIdentifier(for: now, calendar: calendar)
            let summaryFetch = FetchDescriptor<DailyHealthSummaryRecord>(
                predicate: #Predicate<DailyHealthSummaryRecord> { $0.dayIdentifier == dayIdentifier }
            )
            currentDailySummary = (try? modelContext.fetch(summaryFetch))?.first

            let recentJournalStart = calendar.date(byAdding: .hour, value: -36, to: now) ?? now
            let journalFetch = FetchDescriptor<JournalEntryRecord>(
                predicate: #Predicate<JournalEntryRecord> { $0.createdAt >= recentJournalStart && $0.createdAt <= now },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            recentJournalEntries = (try? modelContext.fetch(journalFetch)) ?? []

            let recentStrengthStart = calendar.date(byAdding: .day, value: -28, to: now) ?? now
            let strengthFetch = FetchDescriptor<StrengthWorkoutRecord>(
                predicate: #Predicate<StrengthWorkoutRecord> { $0.startedAt >= recentStrengthStart && $0.startedAt <= now },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            recentStrengthWorkouts = (try? modelContext.fetch(strengthFetch)) ?? []

            let responseStart = calendar.date(byAdding: .day, value: -28, to: now) ?? now
            let responseFetch = FetchDescriptor<TrainingResponseRecord>(
                predicate: #Predicate<TrainingResponseRecord> { $0.date >= responseStart && $0.date <= now },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            recentTrainingResponses = (try? modelContext.fetch(responseFetch)) ?? []

            let foodRange = DateRangeQuery.today(containing: now, calendar: calendar)
            let foodStart = foodRange.start
            let foodEnd = foodRange.end
            let foodFetch = FetchDescriptor<FoodLogRecord>(
                predicate: #Predicate<FoodLogRecord> { $0.createdAt >= foodStart && $0.createdAt < foodEnd },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            todayFoodLogs = (try? modelContext.fetch(foodFetch)) ?? []

            // 联通专项批次 2：身体模型状态挂进 dashboard（主流程一句话洞察与
            // 证据页共用；BodyModelBuilder 是 O(n) 轻量计算，全量记录与长线报告
            // 已在上面取过同款数据，此处只补训练/响应/手记全量）。
            let allStrengthForModel = (try? modelContext.fetch(FetchDescriptor<StrengthWorkoutRecord>())) ?? []
            let allResponsesForModel = (try? modelContext.fetch(FetchDescriptor<TrainingResponseRecord>())) ?? []
            let allJournalsForModel = (try? modelContext.fetch(FetchDescriptor<JournalEntryRecord>())) ?? []
            let onboardingForModel = (try? modelContext.fetch(FetchDescriptor<OnboardingState>()))?.first
            trainingPreference = onboardingForModel?.trainingPreference
            // 身体模型组装同样移出主线程（审计 H2）：先转值类型证据（Sendable），
            // Task.detached 中计算，不与 Live Object 跨并发域。
            let bodyModelEvidence = BodyModelEvidence(
                onboardingSeed: onboardingForModel?.profileSeed,
                dailySummaries: allDailySummaryRecords.map(\.bodyModelEvidence),
                journalEntries: allJournalsForModel.map(\.dto),
                strengthWorkouts: allStrengthForModel.map(\.dto),
                trainingResponses: allResponsesForModel.map(\.dto),
                longTermBaselines: longTermReport,
                asOf: now,
                calendar: calendar
            )
            bodyModelState = await Task.detached {
                BodyModelBuilder().build(evidence: bodyModelEvidence)
            }.value
        }

        var dashboard = DashboardSummary(
            date: context.date,
            sleepSummary: resolvedSleepSummary,
            sleepScore: sleepScore,
            recovery: recovery,
            recoveryMetrics: context.recoveryMetrics,
            recoveryBaseline: context.recoveryBaseline,
            strain: strain,
            stress: stress,
            energy: energy,
            healthAge: healthAge,
            bodyMetrics: context.bodyMetrics,
            extendedMetrics: context.extendedMetrics,
            workouts: context.strainToday.workouts,
            dailyInsight: dailyInsight(recovery: recovery, sleepScore: sleepScore, strain: strain, source: .healthKit),
            source: .healthKit,
            longTermBaselines: longTermReport,
            bodyModelState: bodyModelState
        )
        let activeStatus = ActiveStatusSettings.resolveStatus(
            at: now,
            now: statusEvaluationNow,
            calendar: calendar
        )
        // 合并计划事件与近 48h 事件：hash 要覆盖计划完成事件，近期活动证据也要完整。
        var bodyStateEvents = planResolutionEvents
        let planEventIDs = Set(planResolutionEvents.map(\.id))
        for event in recentWorkoutEvents where !planEventIDs.contains(event.id) {
            bodyStateEvents.append(event)
        }
        let dayId = DailyHealthSummaryRecord.dayIdentifier(for: now, calendar: calendar)
        var persistedDecision: DailyTrainingDecision?
        var persistedBodyStateHash: String?
        var persistedTargetSessionTitle: String?
        var persistedOperatingPlanPayload: DailyOperatingPlanPayload?
        if let modelContext {
            let opPlanDescriptor = FetchDescriptor<DailyOperatingPlanRecord>(
                predicate: #Predicate<DailyOperatingPlanRecord> { $0.dayIdentifier == dayId }
            )
            if let existingPlan = (try? modelContext.fetch(opPlanDescriptor))?.first {
                persistedDecision = existingPlan.trainingDecision
                persistedBodyStateHash = existingPlan.bodyStateHash
                persistedOperatingPlanPayload = existingPlan.operatingPlanPayload
                persistedTargetSessionTitle = persistedOperatingPlanPayload?.targetSessionTitle
            }
        }
        let feedbackCalibration = modelContext.map {
            DailyDecisionFeedbackService().calculateFeedbackCalibration(modelContext: $0, now: now)
        }
        let intelligence = DailyIntelligenceAssemblyModule.assemble(
            DailyIntelligenceAssemblyInput(
                dashboard: dashboard,
                selectedDay: now,
                calendar: calendar,
                dailySummary: currentDailySummary?.dto,
                bodyStateWorkoutEvents: bodyStateEvents.map { $0.dto },
                decisionWorkoutEvents: planResolutionEvents.map { $0.dto },
                strengthWorkouts: recentStrengthWorkouts.map { $0.dto },
                trainingResponses: recentTrainingResponses.map { $0.dto },
                foodLogs: todayFoodLogs.map { $0.dto },
                journalEntries: recentJournalEntries.map { $0.dto },
                activePlan: activePlan?.dto,
                activeStatus: activeStatus,
                trendHistoryProvider: DailySummaryHealthTrendHistoryProvider(
                    snapshots: allDailySummarySnapshots,
                    longTermBaselines: longTermReport
                ),
                snapshots: snapshots180,
                feedbackCalibration: feedbackCalibration,
                trainingPreference: trainingPreference,
                persistedDecision: persistedDecision,
                persistedBodyStateHash: persistedBodyStateHash,
                persistedTargetSessionTitle: persistedTargetSessionTitle
            )
        )
        let bodyState = intelligence.bodyState
        let dailyTrainingDecision = intelligence.trainingDecision
        dashboard = intelligence.dashboard
        
        let persistedSnapshot = makeSnapshot(
            from: dashboard,
            context: context,
            date: now,
            rawBodyWeight: snapshot.bodyWeight
        )
        if let modelContext {
            let snapshotRepo = HealthSnapshotRepository(modelContext: modelContext, calendar: calendar)
            do {
                try snapshotRepo.saveDailySnapshot(
                    persistedSnapshot,
                    scoreEvidence: DailyScoreEvidenceEnvelope(
                        sleep: dashboard.sleepScore,
                        recovery: dashboard.recovery,
                        strain: dashboard.strain,
                        stress: dashboard.stress,
                        energy: dashboard.energy,
                        persistedAt: now
                    )
                )
                try WorkoutAggregationService.shared.aggregateDay(
                    date: now,
                    modelContext: modelContext,
                    calendar: calendar
                )
                try modelContext.save()
                
                // Reuse the canonical decision when hashes match, but still migrate a
                // legacy training-only payload to ADR-0007's bounded action sequence.
                if DailyOperatingPlanRefreshPolicy.shouldRegenerate(
                    usedPersistedDecision: intelligence.usedPersistedDecision,
                    persistedPayload: persistedOperatingPlanPayload
                ) {
                    try DailyOperatingPlanCoordinator.upsert(
                        bodyState: bodyState,
                        decision: dailyTrainingDecision,
                        brief: dashboard.personalHealthBrief,
                        modelContext: modelContext,
                        calendar: calendar
                    )
                }
            } catch {
                PipelineDiagnosticsLogger.log(
                    modelContext: modelContext,
                    stage: "DailySummaryUseCase.loadDashboard.saveDailySnapshot",
                    isSuccess: false,
                    summary: "Failed to save daily snapshot to repository.",
                    error: error
                )
            }
            await refreshPersonalBaselinesIfNeeded(modelContext: modelContext, longTerm: longTermReport)
            do {
                // 三年历史回填（HistoricalBackfillService）写入的长期记录同样保留：
                // 保留窗口从 90 天放宽到 3 年 + 余量，只清理更老的孤儿行。
                try snapshotRepo.pruneOldSnapshots(keepingDays: 1100)
            } catch {
                PipelineDiagnosticsLogger.log(
                    modelContext: modelContext,
                    stage: "DailySummaryUseCase.loadDashboard.pruneOldSnapshots",
                    isSuccess: false,
                    summary: "Failed to prune old snapshots.",
                    error: error
                )
            }
            await checkAndAlertAbnormalMetrics(snapshot: persistedSnapshot, modelContext: modelContext)
        }
        return dashboard
    }

    private func calculateMedian(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        if sorted.count % 2 == 1 {
            return sorted[sorted.count / 2]
        } else {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        }
    }

    private func refreshIntradayBuckets(
        in range: DateRangeQuery,
        modelContext: ModelContext
    ) async {
        let repository = HealthSnapshotRepository(
            modelContext: modelContext,
            calendar: calendar
        )
        for signal in [HealthSignal.workoutHR, .activeEnergy, .stepCount] {
            let points = (try? await queryService.intradaySamples(for: signal, in: range)) ?? []
            let unit = HealthSignalCatalog.unit(for: signal)?.symbol ?? "unit"
            let pointsBySource = Dictionary(grouping: points, by: \.sourceIdentifier)
            let buckets = pointsBySource.flatMap { sourceIdentifier, sourcePoints in
                IntradaySignalBucketizer.bucket(
                    points: sourcePoints,
                    signal: signal,
                    unit: unit,
                    sourceIdentifier: sourceIdentifier
                )
            }
            do {
                try repository.reconcileIntradayBuckets(
                    buckets,
                    signal: signal,
                    on: range.start
                )
            } catch {
                PipelineDiagnosticsLogger.log(
                    modelContext: modelContext,
                    stage: "DailySummaryUseCase.refreshIntradayBuckets",
                    isSuccess: false,
                    summary: "Failed to persist \(signal.rawValue) intraday buckets.",
                    error: error
                )
            }
        }
    }



    private func computeSleepTimingBaseline(modelContext: ModelContext, now: Date) async -> (bedtimeOffset: Double?, wakeOffset: Double?)? {
        let thirtyDays = DateRangeQuery.recentDays(30, endingAt: now, calendar: calendar)

        // Query raw sleep data for baseline timing
        guard let currentSleep = try? await queryService.sleepSummary(in: DateRangeQuery.recentDays(2, endingAt: now, calendar: calendar)),
              let todayBedtime = currentSleep.bedtime,
              let todayWaketime = currentSleep.wakeTime else { return nil }

        let episodes = (try? await queryService.sleepEpisodes(in: thirtyDays)) ?? []
        let pastEpisodes = episodes.filter { !calendar.isDate($0.date, inSameDayAs: now) }

        guard !pastEpisodes.isEmpty else { return nil }

        let bedtimes: [Date] = pastEpisodes.compactMap(\.bedtime)
        let bedtimeComponents = bedtimes.map { calendar.dateComponents([.hour, .minute], from: $0) }
        
        // Map bedtime seconds to be relative to 12:00 PM (noon). If bedtime is before 12:00 PM (e.g. 00:30), add 86400 to map it smoothly across midnight.
        let bedtimeSeconds = bedtimeComponents.map { comps -> Double in
            let secs = Double((comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60)
            return secs < 43200.0 ? secs + 86400.0 : secs
        }
        let avgBedtimeSeconds = bedtimeSeconds.isEmpty ? nil : bedtimeSeconds.reduce(0, +) / Double(bedtimeSeconds.count)

        let waketimes: [Date] = pastEpisodes.compactMap(\.wakeTime)
        let waketimeComponents = waketimes.map { calendar.dateComponents([.hour, .minute], from: $0) }
        let waketimeSeconds = waketimeComponents.map { Double(($0.hour ?? 0) * 3600 + ($0.minute ?? 0) * 60) }
        let avgWaketimeSeconds = waketimeSeconds.isEmpty ? nil : Double(waketimeSeconds.reduce(0, +)) / Double(waketimeSeconds.count)

        guard let avgBedtimeSeconds, let avgWaketimeSeconds else { return nil }

        let todayBedtimeComps = calendar.dateComponents([.hour, .minute], from: todayBedtime)
        var todayBedtimeSeconds = Double((todayBedtimeComps.hour ?? 0) * 3600 + (todayBedtimeComps.minute ?? 0) * 60)
        if todayBedtimeSeconds < 43200.0 {
            todayBedtimeSeconds += 86400.0
        }

        let todayWaketimeComps = calendar.dateComponents([.hour, .minute], from: todayWaketime)
        let todayWaketimeSeconds = Double((todayWaketimeComps.hour ?? 0) * 3600 + (todayWaketimeComps.minute ?? 0) * 60)

        let bedtimeOffset = (todayBedtimeSeconds - avgBedtimeSeconds) / 60.0
        let wakeOffset = (todayWaketimeSeconds - avgWaketimeSeconds) / 60.0

        return (bedtimeOffset, wakeOffset)
    }

    private func refreshPersonalBaselinesIfNeeded(
        modelContext: ModelContext,
        longTerm: LongTermBaselineReport? = nil
    ) async {
        let snapshotRepo = HealthSnapshotRepository(modelContext: modelContext, calendar: calendar)
        let snapshots = (try? snapshotRepo.fetchSnapshots(days: 30)) ?? []
        guard snapshots.count >= 7 else { return }

        let baselines = PersonalBaselineEngine.computeBaselines(from: snapshots)
        let hasPublishedBaseline = [
            baselines.hrvBaselineMean,
            baselines.rhrBaselineMean,
            baselines.sleepHoursBaseline,
            baselines.strainBaselineMean
        ].contains { $0 != nil }
        guard hasPublishedBaseline else { return }
        PersonalBaselineEngine.saveBaselinesToWiki(baselines, longTerm: longTerm)
        WikiSyncManager.sync(modelContext: modelContext)
    }

    private func checkAndAlertAbnormalMetrics(snapshot: DailyHealthSnapshot, modelContext: ModelContext) async {
        let snapshotRepo = HealthSnapshotRepository(modelContext: modelContext, calendar: calendar)
        let recentSnapshots = (try? snapshotRepo.fetchSnapshots(days: 28)) ?? []
        let baselines = recentSnapshots.count >= 7
            ? PersonalBaselineEngine.computeBaselines(from: recentSnapshots)
            : nil

        // Check yesterday's sleep score for consecutive low sleep detection
        let yesterday = calendar.date(byAdding: .day, value: -1, to: snapshot.date) ?? snapshot.date
        let yesterdaySnapshot = (try? snapshotRepo.fetchSnapshots(days: 7, endingAt: snapshot.date))
            .flatMap { $0.first(where: { calendar.isDate($0.date, inSameDayAs: yesterday) }) }

        let notificationService = NotificationService.shared

        // Handle consecutive low sleep check
        if notificationService.checkConsecutiveLowSleep(
            currentSleepScore: snapshot.sleepScore,
            yesterdaySleepScore: yesterdaySnapshot?.sleepScore
        ) {
            notificationService.sendNotification(
                title: "Sleep Alert",
                body: "Your sleep score has been below 50 for 2+ consecutive days. Consider prioritizing rest tonight.",
                category: .abnormalMetric
            )
        }

        notificationService.checkAndAlertAbnormalMetrics(snapshot: snapshot, baselines: baselines)
    }

    func makeSnapshot(
        from dashboard: DashboardSummary,
        context: DailyHealthContext,
        date: Date,
        rawBodyWeight: Double? = nil
    ) -> DailyHealthSnapshot {
        let sleepMetrics = dashboard.sleepScore.metrics
        let strainMetrics = dashboard.strain.metrics

        return DailyHealthSnapshot(
            date: date,
            sleepScore: dashboard.sleepScore.hasData ? dashboard.sleepScore.value : nil,
            recoveryScore: dashboard.recovery.hasData ? dashboard.recovery.value : nil,
            strainScore: dashboard.strain.hasData ? dashboard.strain.value : nil,
            stressIndex: dashboard.stress.hasData ? dashboard.stress.value : nil,
            morningEnergy: dashboard.energy.hasData ? dashboard.energy.morningEnergy : nil,
            currentEnergy: dashboard.energy.hasData ? dashboard.energy.value : nil,
            // F3 修复：与引擎 applying(to:) 一致（energyBank = energy.value），
            // 此前硬编码 nil 会抹掉引擎写入的「能量银行」字段。
            energyBank: dashboard.energy.hasData ? dashboard.energy.value : nil,
            healthAge: dashboard.healthAge.trendScore,
            hrvAverage: dashboard.recoveryMetrics.hrvMilliseconds,
            hrvRmssdMilliseconds: dashboard.recoveryMetrics.hrvRmssdMilliseconds,
            restingHeartRate: dashboard.recoveryMetrics.restingHeartRate,
            sleepHours: context.sleepSummary.map { Double($0.totalSleepMinutes) / 60.0 },
            deepSleepPercent: sleepMetrics["deep_pct"].map { HealthUnitNormalizer.normalizeSleepStagePercent($0 / 100.0) },
            remSleepPercent: sleepMetrics["rem_pct"].map { HealthUnitNormalizer.normalizeSleepStagePercent($0 / 100.0) },
            sleepEfficiency: sleepMetrics["sleep_efficiency"].map { HealthUnitNormalizer.normalizeSleepEfficiency($0 / 100.0) },
            steps: strainMetrics["steps_raw"],
            activeCalories: strainMetrics["active_energy_raw"],
            activeMinutes: strainMetrics["exercise_minutes_raw"],
            workoutCount: dashboard.workouts.isEmpty ? nil : dashboard.workouts.count,
            workoutTypes: dashboard.workouts.isEmpty ? nil : Set(dashboard.workouts.map(\.activityName)).sorted().joined(separator: ", "),
            workoutDuration: dashboard.workouts.isEmpty ? nil : dashboard.workouts.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60.0,
            // F8 修复：快照存原始 HealthKit 体重（rawBodyWeight），
            // 手动覆盖只在展示/上下文层生效——此前手填体重污染原始 HK 体重历史，
            // 清除手填值后历史日也回不去真实测量值。
            bodyWeight: rawBodyWeight ?? context.bodyMetrics.weightKilograms,
            bodyFatPercent: context.bodyMetrics.bodyFatPercentage.map { HealthUnitNormalizer.normalizeBodyFatPercentage($0) },
            bmi: context.extendedMetrics.bmi,
            oxygenSaturation: context.extendedMetrics.oxygenSaturation.map { HealthUnitNormalizer.normalizeOxygenSaturation($0) },
            respiratoryRate: dashboard.recoveryMetrics.respiratoryRate,
            wristTemperature: context.extendedMetrics.bodyTemperature,
            dailyLoad: strainMetrics["daily_load"],
            workoutLoad: strainMetrics["workout_load"],
            activityLoad: strainMetrics["activity_load"],
            trainingLoadRatio: strainMetrics["training_load_ratio"],
            atl: dashboard.energy.metrics["atl"],
            ctl: dashboard.energy.metrics["ctl"],
            tsb: dashboard.energy.metrics["tsb"],
            acwr: dashboard.energy.metrics["acwr"],
            awakeMinutes: context.sleepSummary?.stageMinutes[.awake].map { Double($0) },
            awakeEpisodeCount: context.sleepSummary?.segments.filter { $0.stage == .awake && $0.end.timeIntervalSince($0.start) >= 120 }.count,
            deepSleepMinutes: context.sleepSummary?.stageMinutes[.deep].map { Double($0) },
            remSleepMinutes: context.sleepSummary?.stageMinutes[.rem].map { Double($0) },
            workouts: context.strainToday.workouts
        )
    }

    private func dailyInsight(
        recovery: MetricResult,
        sleepScore: MetricResult,
        strain: MetricResult,
        source: DashboardSummary.DataSource
    ) -> String {
        if source == .healthKit {
            return L10n.t(
                "Updated from Apple Health. Recovery \(Int(recovery.score.rounded())), sleep \(Int(sleepScore.score.rounded())), strain \(Int(strain.score.rounded())).",
                "已读取 Apple 健康数据。恢复 \(Int(recovery.score.rounded()))，睡眠 \(Int(sleepScore.score.rounded()))，负荷 \(Int(strain.score.rounded()))。"
            )
        }
        return L10n.t(
            "Recovery is moderate. Keep training controlled and protect sleep timing tonight.",
            "恢复处于中等水平。今天训练保持可控，今晚优先保护睡眠时间。"
        )
    }

#if DEBUG
    private func seedMockDataIfNeeded(modelContext: ModelContext, now: Date) {
        let repo = SwiftDataDailyHealthSummaryRepository(modelContext: modelContext)
        
        // Check if there are already records in the last 30 days
        let range = DateRangeQuery.recentDays(30, endingAt: now, calendar: calendar)
        let existing = (try? repo.fetch(in: range)) ?? []
        
        // If there are already records, don't overwrite them
        guard existing.isEmpty else { return }
        
        // Seed 30 days of high-fidelity data
        for offset in 0..<30 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            
            // Generate realistic variations based on day offset
            let seed = Double(offset)
            let recoveryScore = 55 + sin(seed * 0.8) * 20 + Double((offset * 7) % 8)
            let sleepScore = 65 + cos(seed * 0.6) * 15 + Double((offset * 3) % 10)
            let strainScore = 8 + abs(sin(seed * 1.2)) * 10 + Double((offset * 2) % 4)
            let stressIndex = 25 + cos(seed * 0.9) * 12 + Double((offset * 5) % 15)
            let steps = 4000 + abs(sin(seed * 0.5)) * 8000 + Double((offset * 500) % 3000)
            let activeCalories = 150 + abs(sin(seed * 0.5)) * 400 + Double((offset * 50) % 200)
            let rhr = 58 + cos(seed * 0.7) * 6 + Double((offset * 2) % 4)
            let hrv = 45 + sin(seed * 0.7) * 15 + Double((offset * 3) % 8)
            
            let snapshot = DailyHealthSnapshot(
                date: day,
                sleepScore: sleepScore,
                recoveryScore: recoveryScore,
                strainScore: strainScore,
                stressIndex: stressIndex,
                morningEnergy: 50 + sin(seed * 0.5) * 20,
                currentEnergy: max(10, min(100, 50 + sin(seed * 0.5) * 20 - strainScore * 2)),
                energyBank: 40 + cos(seed * 0.4) * 25,
                healthAge: 26.5,
                hrvAverage: hrv,
                restingHeartRate: rhr,
                sleepHours: 6.5 + cos(seed * 0.6) * 1.5,
                deepSleepPercent: 0.18 + sin(seed * 0.3) * 0.05,
                remSleepPercent: 0.22 + cos(seed * 0.3) * 0.04,
                sleepEfficiency: 0.88 + sin(seed * 0.2) * 0.05,
                steps: steps,
                activeCalories: activeCalories,
                activeMinutes: 20 + abs(sin(seed * 0.5)) * 45,
                workoutCount: offset % 3 == 0 ? 1 : 0,
                workoutTypes: offset % 3 == 0 ? "跑步" : nil,
                workoutDuration: offset % 3 == 0 ? 35.0 : 0.0,
                bodyWeight: 72.0,
                bodyFatPercent: 17.5,
                bmi: 22.8,
                oxygenSaturation: 0.98,
                respiratoryRate: 14.5,
                wristTemperature: 36.6
            )
            
            let record = DailyHealthSummaryRecord(snapshot: snapshot, calendar: calendar)
            // Persist provenance so a later normal Debug launch never presents
            // simulator fixtures as an Apple Health snapshot.
            record.configVersion = Self.debugDemoConfigVersion
            modelContext.insert(record)
        }
        try? modelContext.save()
    }
#endif

    func loadCachedDashboard(
        for date: Date = Date(),
        modelContext: ModelContext
    ) async throws -> DashboardSummary? {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let records = try SwiftDataDailyHealthSummaryRepository(modelContext: modelContext)
            .fetch(in: DateRangeQuery(start: dayStart, end: dayEnd))
        guard let record = records.last else { return nil }
        let source = Self.cachedSource(configVersion: record.configVersion)
        var dashboard = makeDashboardFromRecord(record, source: source)
        // 缓存启动路径同样挂载三年长线基准：否则重启后长线修正/证据/身体模型
        // 会静默退化为空（直到一次完整刷新）。
        let allRecords = (try? modelContext.fetch(FetchDescriptor<DailyHealthSummaryRecord>())) ?? []
        dashboard.longTermBaselines = LongTermBaselineEngine.compute(
            points: allRecords.map(\.longTermBaselinePoint),
            today: date,
            calendar: calendar
        )
        // 缓存启动路径同样挂载身体模型：否则重启后的前 15 分钟 TTL 内，
        // 今日页/训练页的个人洞察会静默消失，与完整刷新口径不一致。
        let allStrength = (try? modelContext.fetch(FetchDescriptor<StrengthWorkoutRecord>())) ?? []
        let allResponses = (try? modelContext.fetch(FetchDescriptor<TrainingResponseRecord>())) ?? []
        let allJournals = (try? modelContext.fetch(FetchDescriptor<JournalEntryRecord>())) ?? []
        let onboarding = (try? modelContext.fetch(FetchDescriptor<OnboardingState>()))?.first
        // 缓存启动路径的长线基准与身体模型组装一并移出主线程（审计 H2）：
        // MainActor 上只做 fetch + 值类型转换，Task.detached 内纯计算。
        let onboardingSeed = onboarding?.profileSeed
        let dailyEvidences = allRecords.map(\.bodyModelEvidence)
        let journalDTOs = allJournals.map(\.dto)
        let strengthDTOs = allStrength.map(\.dto)
        let responseDTOs = allResponses.map(\.dto)
        let baselinePoints = allRecords.map(\.longTermBaselinePoint)
        let computationCalendar = calendar
        let (baselines, bodyModel) = await Task.detached {
            let report = LongTermBaselineEngine.compute(points: baselinePoints, today: date, calendar: computationCalendar)
            let model = BodyModelBuilder().build(evidence: BodyModelEvidence(
                onboardingSeed: onboardingSeed,
                dailySummaries: dailyEvidences,
                journalEntries: journalDTOs,
                strengthWorkouts: strengthDTOs,
                trainingResponses: responseDTOs,
                longTermBaselines: report,
                asOf: date,
                calendar: computationCalendar
            ))
            return (report, model)
        }.value
        dashboard.longTermBaselines = baselines
        dashboard.bodyModelState = bodyModel
        // The cache path has no HealthKit work to refresh, but it still needs
        // to publish the canonical Brief/AI projection with the same complete
        // three-year trend history as a live DailySummary load. Secondary
        // assembly preserves this projection when it only has its bounded
        // recent snapshot window.
        let trendProvider = DailySummaryHealthTrendHistoryProvider(
            snapshots: allRecords.map { $0.toSnapshot() },
            longTermBaselines: baselines
        )
        let trendAnalysis = HealthTrendEngine().analyze(
            dashboard: dashboard,
            historyProvider: trendProvider,
            selectedDay: date,
            calendar: calendar
        )
        dashboard.personalHealthBrief = trendAnalysis.brief
        dashboard.healthTrends = trendAnalysis.findings
        return dashboard
    }

    func makeDashboardFromRecord(
        _ record: DailyHealthSummaryRecord,
        source: DashboardSummary.DataSource = .cache
    ) -> DashboardSummary {
        let persistedEvidence = record.decodedScoreEvidence()
        let totalSleepMinutes = max(Int((record.sleepHours ?? 0) * 60), 0)
        let deepMinutes = Int(record.deepSleepMinutes ?? percentMinutes(record.deepSleepPercent, total: totalSleepMinutes))
        let remMinutes = Int(record.remSleepMinutes ?? percentMinutes(record.remSleepPercent, total: totalSleepMinutes))
        let awakeMinutes = Int(record.awakeMinutes ?? 0)
        let coreMinutes = max(totalSleepMinutes - deepMinutes - remMinutes, 0)
        let sleepSummary = SleepSummary(
            date: record.date,
            totalSleepMinutes: totalSleepMinutes,
            bedtime: record.bedtime,
            wakeTime: record.wakeTime,
            stageMinutes: compactStageMinutes([
                .deep: deepMinutes,
                .rem: remMinutes,
                .core: coreMinutes,
                .awake: awakeMinutes
            ]),
            segments: [],
            sleepScore: record.sleepScore
        )

        let sleep = persistedEvidence?.sleep ?? cachedMetric(
            name: "Sleep Score",
            value: record.sleepScore,
            components: compactComponents([
                "duration_minutes": Double(totalSleepMinutes),
                "sleep_efficiency": percentValue(record.sleepEfficiency),
                "deep_pct": percentValue(record.deepSleepPercent),
                "rem_pct": percentValue(record.remSleepPercent),
                "awake_minutes": record.awakeMinutes,
                "awake_episode_count": record.awakeEpisodeCount.map(Double.init)
            ]),
            updatedAt: record.updatedAt
        )
        let recovery = persistedEvidence?.recovery ?? cachedMetric(
            name: "Recovery Score",
            value: record.recoveryScore,
            components: compactComponents([
                "hrv_ms": record.hrvAverage,
                "rhr_bpm": record.restingHeartRate,
                "respiratory_rate": record.respiratoryRate,
                "spo2": percentValue(record.oxygenSaturation)
            ]),
            updatedAt: record.updatedAt
        )
        let targetRange = recommendedStrainRange(for: record.recoveryScore)
        let strain = persistedEvidence?.strain ?? cachedMetric(
            name: "Strain Score",
            value: record.strainScore,
            components: compactComponents([
                "daily_load": record.dailyLoad,
                "workout_load": record.workoutLoad,
                "activity_load": record.activityLoad,
                "training_load_ratio": record.trainingLoadRatio,
                "steps_raw": record.steps,
                "active_energy_raw": record.activeCalories,
                "exercise_minutes_raw": record.activeMinutes ?? record.workoutDuration,
                "recommended_lower": Double(targetRange.lowerBound),
                "recommended_upper": Double(targetRange.upperBound)
            ]),
            updatedAt: record.updatedAt
        )
        let stress = persistedEvidence?.stress ?? cachedMetric(
            name: "Physiological Stress Index",
            value: record.stressIndex,
            components: compactComponents(["stress_index": record.stressIndex]),
            updatedAt: record.updatedAt
        )
        let energy = persistedEvidence?.energy ?? cachedMetric(
            name: "Energy Bank",
            value: record.currentEnergy ?? record.energyBank,
            components: compactComponents([
                "morningEnergy": record.morningEnergy,
                "currentEnergy": record.currentEnergy ?? record.energyBank,
                "atl": record.atl,
                "ctl": record.ctl,
                "tsb": record.tsb,
                "acwr": record.acwr
            ]),
            updatedAt: record.updatedAt
        )
        let snapshot = record.toSnapshot()

        return DashboardSummary(
            date: record.date,
            sleepSummary: sleepSummary,
            sleepScore: sleep,
            recovery: recovery,
            recoveryMetrics: RecoveryMetricSummary(
                hrvMilliseconds: record.hrvAverage,
                hrvRmssdMilliseconds: record.hrvRmssdMilliseconds,
                restingHeartRate: record.restingHeartRate,
                sleepHeartRate: nil,
                respiratoryRate: record.respiratoryRate
            ),
            recoveryBaseline: RecoveryMetricSummary(),
            strain: strain,
            stress: stress,
            energy: energy,
            healthAge: cachedHealthAgeTrend(record.healthAge),
            bodyMetrics: BodyMetricsSummary(
                // VO2max 未持久化到记录，缓存态不携带（live 路径查询 HealthKit 提供）。
                vo2Max: nil,
                weightKilograms: UserProfileSettings.weightKilograms() ?? record.bodyWeight,
                bodyFatPercentage: record.bodyFatPercent,
                leanBodyMassKilograms: nil
            ),
            extendedMetrics: ExtendedHealthMetrics(
                age: UserProfileSettings.age(),
                biologicalSex: UserProfileSettings.biologicalSex(),
                heightCm: UserProfileSettings.heightCentimeters(),
                bmi: record.bmi,
                oxygenSaturation: record.oxygenSaturation,
                bodyTemperature: record.wristTemperature
            ),
            workouts: snapshot.workouts,
            dailyInsight: source == .preview
                ? L10n.t(
                    "Showing opt-in simulator demo data.",
                    "正在显示主动启用的模拟器演示数据。"
                )
                : L10n.t(
                    "Showing your latest saved Apple Health snapshot while Vela checks for updates.",
                    "正在显示最近一次 Apple 健康快照，Vela 会在后台检查更新。"
                ),
            source: source
        )
    }

    private func cachedMetric(
        name: String,
        value: Double?,
        components: [String: Double],
        updatedAt: Date
    ) -> MetricResult {
        var resolvedComponents = components
        if let value {
            resolvedComponents["cached_score"] = value
        }
        return MetricResult(
            name: name,
            value: value,
            band: value.map(ScoringMath.band(for:)) ?? .low,
            confidence: value == nil ? .low : .medium,
            components: resolvedComponents,
            componentWeights: [:],
            reasons: [L10n.t("Loaded from the latest saved Apple Health snapshot.", "已读取最近一次保存的 Apple 健康快照。")],
            missingInputs: value == nil ? ["cachedValue"] : [],
            dataWindow: DateInterval(start: calendar.startOfDay(for: updatedAt), end: updatedAt),
            source: .derived,
            algorithmVersion: VelaAppMetadata.configVersion,
            lastUpdated: updatedAt
        )
    }

    private func compactComponents(_ values: [String: Double?]) -> [String: Double] {
        values.reduce(into: [:]) { result, pair in
            if let value = pair.value {
                result[pair.key] = value
            }
        }
    }

    private func compactStageMinutes(_ values: [SleepStage: Int]) -> [SleepStage: Int] {
        values.filter { $0.value > 0 }
    }

    private func percentMinutes(_ value: Double?, total: Int) -> Double {
        guard let value else { return 0 }
        return (value <= 1 ? value : value / 100) * Double(total)
    }

    private func percentValue(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return value <= 1 ? value * 100 : value
    }

    private func recommendedStrainRange(for recoveryScore: Double?) -> ClosedRange<Int> {
        guard let recoveryScore else { return 40...70 }
        if recoveryScore < 40 { return 15...40 }
        if recoveryScore < 70 { return 35...65 }
        return 55...85
    }

    private func cachedHealthAgeTrend(_ score: Double?) -> HealthAgeTrendResult {
        guard let score else {
            return HealthAgeTrendEngine().calculate(from: HealthAgeTrendInput(factors: []))
        }
        let label: HealthAgeTrendLabel
        if score >= 0.35 {
            label = .improving
        } else if score <= -0.35 {
            label = .worsening
        } else {
            label = .stable
        }
        return HealthAgeTrendResult(
            trendScore: score,
            label: label,
            confidence: .medium,
            positiveFactors: [],
            negativeFactors: [],
            reasons: [L10n.t("Loaded from the latest saved trend snapshot.", "已读取最近一次保存的趋势快照。")],
            metrics: ["trend_score": score]
        )
    }

}

@MainActor
final class DailyPlanRefreshCoordinator {
    static let shared = DailyPlanRefreshCoordinator()

    private init() {}

    /// 最近一次被调度的计划刷新任务，供调用方 join，避免 fire-and-forget 任务越过调用帧存活。
    private(set) var latestTask: Task<Void, Never>?

    /// 调度计划刷新。刷新在 MainActor 上使用 `container.mainContext` 执行，
    /// 不持有调用方的 ModelContext——调用方 context 的生命周期与隔离域不影响刷新安全。
    @discardableResult
    func schedulePlanRefresh(for dates: [Date], container: ModelContainer) -> Task<Void, Never> {
        let task = Task { @MainActor in
            for date in dates {
                await refreshPlan(for: date, container: container)
            }
        }
        latestTask = task
        return task
    }

    func refreshPlan(for date: Date = Date(), container: ModelContainer) async {
        // 深度专项批次 5：计划刷新同样收口到统一调度层（不同步、只重算+落计划）。
        let context = container.mainContext
        _ = try? await VelaDailyOrchestrator.refresh(
            for: date,
            modelContext: context,
            syncDays: 0,
            shouldSyncHealthData: false
        )
        VelaAppState.shared.markLocalDataChanged()
    }
}

// MARK: - 深度专项批次 5：统一调度层

/// 所有「同步 → 评分 → 计划」触发源的唯一入口：
/// ① 共享 AppSyncCoordinator（同步去重 + 30s 节流）；
/// ② 同一天的同 key 并发触发共享同一次计算（回前台双链不再跑两遍全量管线）；
/// ③ 历史日由调用方传 shouldSyncHealthData=false（不再对历史日跑 HealthKit 同步）。
/// 幂等原语全部沿用既有机制：HealthCachePolicy TTL / 脏标记 / bodyStateHash。
@MainActor
enum VelaDailyOrchestrator {
    private static var inFlight: [String: Task<DashboardSummary, Error>] = [:]

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        DailyHealthSummaryRecord.dayIdentifier(for: date, calendar: calendar)
    }

    @discardableResult
    static func refresh(
        for date: Date,
        modelContext: ModelContext,
        queryService: any HealthQueryService = HealthKitQueryService(),
        syncDays: Int = 3,
        shouldSyncHealthData: Bool = true,
        calendar: Calendar = .current
    ) async throws -> DashboardSummary {
        let key = dayKey(for: date, calendar: calendar)
        if let running = inFlight[key] {
            // 同日并发触发（回前台 TodayView + 主动洞察、后台投递补跑等）共享同一结果。
            return try await running.value
        }
        let task = Task<DashboardSummary, Error> { @MainActor in
            try await DailySummaryUseCase(
                queryService: queryService,
                calendar: calendar,
                syncCoordinator: AppSyncCoordinator.shared
            ).loadDashboard(
                for: date,
                modelContext: modelContext,
                syncDays: syncDays,
                shouldSyncHealthData: shouldSyncHealthData
            )
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }
}
