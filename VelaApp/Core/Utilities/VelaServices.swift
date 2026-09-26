import Foundation
import HealthKit
import SwiftData

// MARK: - Explicit composition seams (ARCH-02 / PR2)

/// A clock is deliberately tiny and value-oriented so tests can replay a
/// selected health day without relying on wall-clock time. `Date()` remains
/// available to legacy paths; new stores should receive an `AppClock`.
protocol AppClock: Sendable {
    var now: Date { get }
}

struct SystemAppClock: AppClock, Sendable {
    init() {}

    var now: Date { Date() }
}

struct FixedAppClock: AppClock, Sendable {
    let now: Date

    init(now: Date) {
        self.now = now
    }
}

/// Health-day policy is kept in the host layer. The Domain package receives
/// explicit dates/calendars and never resolves `.current` itself.
@MainActor
struct RuntimeDependencies {
    let clock: any AppClock
    let calendar: Calendar
    let healthDayBoundary: HealthDayBoundary

    init(clock: any AppClock, calendar: Calendar) {
        self.clock = clock
        self.calendar = calendar
        self.healthDayBoundary = HealthDayBoundary(calendar: calendar)
    }
}

@MainActor
protocol HealthAuthorizationProviding: AnyObject {
    func shouldDeferBackgroundSync() async -> Bool
}

extension HealthAuthorizationService: HealthAuthorizationProviding {}

enum TodayRefreshPolicy: Equatable, Sendable {
    case cacheOnly
    case automatic
    case force
}

/// App-side value projection used by the pre-PR3 reader seam. PR3 will map
/// this projection into `TodayViewState`; it is intentionally not a SwiftData
/// model and does not expose `ModelContext` to callers.
struct TodayDashboardSnapshot: Hashable, Sendable {
    let dashboard: DashboardSummary
    /// Secondary Today values are captured once by the reader at the same
    /// boundary as the dashboard.  The root surface must consume these
    /// projections from `TodayViewState` instead of reading the shared
    /// DashboardViewModel or rebuilding command/experience models in getters.
    let bodyState: BodyState?
    let trainingDecision: DailyTrainingDecision?
    let command: TodayCommandState?
    let experience: TodayExperienceModel?
    let todayAIInsight: DailyAIInsight?
    let nutrition: TodayNutritionProjection?
    let livedState: TodayLivedStateProjection?
    let feedback: TodayFeedbackProjection?
    let coverage: DataCoverageSummaryModel?
    /// Active executable plan and pending user-review proposal are distinct
    /// value projections; neither exposes a SwiftData model.
    let activePlan: TodayPlanProjection?
    let pendingPlan: TodayPendingPlanProjection?
    let weather: TodayWeatherProjection?
    let operatingPlanPayload: DailyOperatingPlanPayload?
    let lastUpdated: Date?
    let vitalTrendSeries: [String: [Double]]
    let errorMessage: String?
    let secondaryDataErrorMessage: String?

    init(
        dashboard: DashboardSummary,
        bodyState: BodyState? = nil,
        trainingDecision: DailyTrainingDecision? = nil,
        command: TodayCommandState? = nil,
        experience: TodayExperienceModel? = nil,
        todayAIInsight: DailyAIInsight? = nil,
        nutrition: TodayNutritionProjection? = nil,
        livedState: TodayLivedStateProjection? = nil,
        feedback: TodayFeedbackProjection? = nil,
        coverage: DataCoverageSummaryModel? = nil,
        activePlan: TodayPlanProjection? = nil,
        pendingPlan: TodayPendingPlanProjection? = nil,
        weather: TodayWeatherProjection? = nil,
        operatingPlanPayload: DailyOperatingPlanPayload? = nil,
        lastUpdated: Date? = nil,
        vitalTrendSeries: [String: [Double]] = [:],
        errorMessage: String? = nil,
        secondaryDataErrorMessage: String? = nil
    ) {
        self.dashboard = dashboard
        self.bodyState = bodyState
        self.trainingDecision = trainingDecision
        self.command = command
        self.experience = experience
        self.todayAIInsight = todayAIInsight
        self.nutrition = nutrition
        self.livedState = livedState
        self.feedback = feedback
        self.coverage = coverage
        self.activePlan = activePlan
        self.pendingPlan = pendingPlan
        self.weather = weather
        self.operatingPlanPayload = operatingPlanPayload
        self.lastUpdated = lastUpdated
        self.vitalTrendSeries = vitalTrendSeries
        self.errorMessage = errorMessage
        self.secondaryDataErrorMessage = secondaryDataErrorMessage
    }

    /// Source-compatible convenience used by cache-only adapters that only
    /// have the primary dashboard projection available.
    init(dashboard: DashboardSummary) {
        self.init(dashboard: dashboard, bodyState: nil)
    }
}

@MainActor
protocol TodayReadingModule: AnyObject {
    func cached(for day: Date) async throws -> TodayDashboardSnapshot?
    func load(for day: Date, policy: TodayRefreshPolicy) async throws -> TodayDashboardSnapshot
}

/// A deterministic reader for previews and tests. It never constructs a
/// HealthKit store and always returns the supplied value projection.
@MainActor
final class StaticTodayReadingModule: TodayReadingModule {
    private let snapshot: TodayDashboardSnapshot?

    init(snapshot: TodayDashboardSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func cached(for day: Date) async throws -> TodayDashboardSnapshot? {
        snapshot
    }

    func load(for day: Date, policy: TodayRefreshPolicy) async throws -> TodayDashboardSnapshot {
        snapshot ?? TodayDashboardSnapshot(dashboard: DashboardSummary.empty(date: day))
    }
}

/// Existing DailySummary pipeline adapter. It is intentionally not wired into
/// `AppCoordinator` in PR2: the adapter is available for the later TodayStore
/// migration while legacy ViewModel/resolver construction remains compatible.
@MainActor
final class DailySummaryTodayReadingModule: TodayReadingModule {
    let useCase: DailySummaryUseCase
    private let modelContext: ModelContext?
    private let syncDays: Int

    init(
        useCase: DailySummaryUseCase,
        modelContext: ModelContext?,
        syncDays: Int = 3
    ) {
        self.useCase = useCase
        self.modelContext = modelContext
        self.syncDays = syncDays
    }

    func cached(for day: Date) async throws -> TodayDashboardSnapshot? {
        guard let modelContext else { return nil }
        return try await useCase
            .loadCachedDashboard(for: day, modelContext: modelContext)
            .map(TodayDashboardSnapshot.init(dashboard:))
    }

    func load(for day: Date, policy: TodayRefreshPolicy) async throws -> TodayDashboardSnapshot {
        // Preview/test readers have no ModelContext and must not fall through
        // to the HealthKit singleton. A missing context is therefore an
        // explicit empty projection until PR3 injects the real store.
        guard let modelContext else {
            return TodayDashboardSnapshot(dashboard: DashboardSummary.empty(date: day))
        }
        if policy == .cacheOnly, let cached = try await cached(for: day) {
            return cached
        }
        let dashboard = try await useCase.loadDashboard(
            for: day,
            modelContext: modelContext,
            syncDays: syncDays,
            shouldSyncHealthData: policy != .cacheOnly
        )
        return TodayDashboardSnapshot(dashboard: dashboard)
    }
}

@MainActor
struct HealthDependencies {
    let queryService: any HealthQueryService
    let authorization: any HealthAuthorizationProviding
    let syncCoordinator: AppSyncCoordinator
}

@MainActor
struct TodayDependencies {
    let reader: any TodayReadingModule
    /// Kept for the legacy bridge. New callers should use `reader` and let
    /// PR3 own state/action orchestration.
    let dailySummaryUseCase: DailySummaryUseCase
}

/// Minimal composition-root value for ARCH-02. It is constructable in live,
/// preview, and test modes without making `ModelContext` or `HKHealthStore`
/// cross an actor/domain boundary. The app still uses `VelaResolver` until a
/// later composition-root PR switches its construction site.
@MainActor
struct AppDependencies {
    let runtime: RuntimeDependencies
    let health: HealthDependencies
    let today: TodayDependencies

    static func live(
        modelContainer: ModelContainer,
        clock: any AppClock = SystemAppClock(),
        calendar: Calendar = .current
    ) -> AppDependencies {
        let queryService = HealthKitQueryService()
        let authorization = HealthAuthorizationService()
        let syncCoordinator = AppSyncCoordinator()
        let useCase = DailySummaryUseCase(
            queryService: queryService,
            authorizationService: authorization,
            calendar: calendar,
            syncCoordinator: syncCoordinator
        )
        return AppDependencies(
            runtime: RuntimeDependencies(clock: clock, calendar: calendar),
            health: HealthDependencies(
                queryService: queryService,
                authorization: authorization,
                syncCoordinator: syncCoordinator
            ),
            today: TodayDependencies(
                reader: DailySummaryTodayReadingModule(
                    useCase: useCase,
                    modelContext: modelContainer.mainContext
                ),
                dailySummaryUseCase: useCase
            )
        )
    }

    static func preview(
        now: Date,
        calendar: Calendar
    ) -> AppDependencies {
        let queryService = PreviewHealthQueryService()
        let authorization = PreviewHealthAuthorization()
        let syncCoordinator = AppSyncCoordinator(minimumInterval: 0)
        let useCase = DailySummaryUseCase(
            queryService: queryService,
            authorizationService: authorization,
            calendar: calendar,
            syncCoordinator: syncCoordinator
        )
        let snapshot = TodayDashboardSnapshot(dashboard: DashboardSummary.preview(date: now))
        return AppDependencies(
            runtime: RuntimeDependencies(clock: FixedAppClock(now: now), calendar: calendar),
            health: HealthDependencies(
                queryService: queryService,
                authorization: authorization,
                syncCoordinator: syncCoordinator
            ),
            today: TodayDependencies(
                reader: StaticTodayReadingModule(snapshot: snapshot),
                dailySummaryUseCase: useCase
            )
        )
    }

    static func test(
        now: Date,
        calendar: Calendar,
        queryService: any HealthQueryService = PreviewHealthQueryService(),
        snapshot: TodayDashboardSnapshot? = nil,
        authorizationService: (any HealthAuthorizationProviding)? = nil
    ) -> AppDependencies {
        let authorization = authorizationService ?? PreviewHealthAuthorization()
        let syncCoordinator = AppSyncCoordinator(minimumInterval: 0)
        let useCase = DailySummaryUseCase(
            queryService: queryService,
            authorizationService: authorization,
            calendar: calendar,
            syncCoordinator: syncCoordinator
        )
        return AppDependencies(
            runtime: RuntimeDependencies(clock: FixedAppClock(now: now), calendar: calendar),
            health: HealthDependencies(
                queryService: queryService,
                authorization: authorization,
                syncCoordinator: syncCoordinator
            ),
            today: TodayDependencies(
                reader: StaticTodayReadingModule(snapshot: snapshot),
                dailySummaryUseCase: useCase
            )
        )
    }
}

/// No-op HealthKit-free implementations used only by preview/test factories.
@MainActor
private final class PreviewHealthAuthorization: HealthAuthorizationProviding {
    func shouldDeferBackgroundSync() async -> Bool { true }
}

@MainActor
private final class PreviewHealthQueryService: HealthQueryService {
    func sleepSummary(in range: DateRangeQuery) async throws -> SleepSummary? { nil }
    func sleepEpisodes(in range: DateRangeQuery) async throws -> [SleepSummary] { [] }
    func recoveryMetrics(in range: DateRangeQuery) async throws -> RecoveryMetricSummary { RecoveryMetricSummary() }
    func strainSummary(in range: DateRangeQuery) async throws -> StrainActivitySummary {
        StrainActivitySummary(workouts: [])
    }
    func bodyMetrics(in range: DateRangeQuery) async throws -> BodyMetricsSummary { BodyMetricsSummary() }
    func recentWorkouts(limit: Int) async throws -> [WorkoutSummary] { [] }
    func heartRateSamples(start: Date, end: Date) async throws -> [HeartRateSample] { [] }
    func workoutRoute(workoutId: UUID) async throws -> [RouteCoordinate] { [] }
}

@MainActor
final class AppSyncCoordinator: ObservableObject {
    /// 算法打通（深度专项批次 1）：全 App 共享一个去重/节流实例——
    /// 此前前台刷新、主动洞察、后台任务各自构造实例，inFlight/30s 节流失效，
    /// 回前台一次会并发拉起多条全量同步+评分管线。
    static let shared = AppSyncCoordinator()

    enum Source: Hashable {
        case healthKit
        case xunji
    }

    struct SourceStatus: Equatable {
        var lastAttemptAt: Date?
        var lastSuccessAt: Date?
        var lastFailureAt: Date?
        var lastErrorDescription: String?
        var consecutiveFailures = 0

        var isHealthy: Bool {
            lastFailureAt == nil || (lastSuccessAt ?? .distantPast) > (lastFailureAt ?? .distantPast)
        }
    }

    @Published private(set) var activeSources: Set<Source> = []
    @Published private(set) var sourceStatuses: [Source: SourceStatus] = [:]

    private let minimumInterval: TimeInterval
    private var inFlight: [Source: Task<Void, Never>] = [:]
    private var lastCompletedAt: [Source: Date] = [:]

    init(minimumInterval: TimeInterval = 30) {
        self.minimumInterval = minimumInterval
    }

    func run(
        source: Source,
        force: Bool = false,
        operation: @escaping @MainActor () async -> Void
    ) async {
        if let running = inFlight[source] {
            await running.value
            return
        }
        if !force,
           let lastCompletedAt = lastCompletedAt[source],
           Date().timeIntervalSince(lastCompletedAt) < minimumInterval {
            return
        }

        activeSources.insert(source)
        let task = Task { @MainActor in
            await operation()
        }
        inFlight[source] = task
        await task.value
        inFlight[source] = nil
        lastCompletedAt[source] = Date()
        activeSources.remove(source)
    }

    /// Runs a sync operation that can fail and only applies throttling after a
    /// successful completion. Callers can surface the latest failure without
    /// allowing a failed attempt to suppress the next retry.
    @discardableResult
    func runReporting(
        source: Source,
        force: Bool = false,
        operation: @escaping @MainActor () async throws -> Void
    ) async -> Bool {
        if let running = inFlight[source] {
            await running.value
            return sourceStatuses[source]?.isHealthy ?? true
        }
        if !force,
           let lastCompletedAt = lastCompletedAt[source],
           Date().timeIntervalSince(lastCompletedAt) < minimumInterval {
            return true
        }

        activeSources.insert(source)
        var succeeded = false
        let task = Task { @MainActor in
            var status = sourceStatuses[source] ?? SourceStatus()
            status.lastAttemptAt = Date()
            do {
                try await operation()
                succeeded = true
                status.lastSuccessAt = Date()
                status.lastErrorDescription = nil
                status.consecutiveFailures = 0
            } catch {
                status.lastFailureAt = Date()
                status.lastErrorDescription = error.localizedDescription
                status.consecutiveFailures += 1
            }
            sourceStatuses[source] = status
        }
        inFlight[source] = task
        await task.value
        inFlight[source] = nil
        if succeeded {
            lastCompletedAt[source] = Date()
        }
        activeSources.remove(source)
        return succeeded
    }
}

@MainActor
final class VelaServices: ObservableObject {
    private let injectedDependencies: AppDependencies?

    var queryService: any HealthQueryService {
        injectedDependencies?.health.queryService
            ?? VelaResolver.shared.resolve(HealthQueryService.self)
    }
    var contextBuilder: AIContextBuilder {
        VelaResolver.shared.resolve(AIContextBuilder.self)
    }
    var dailySummaryUseCase: DailySummaryUseCase {
        injectedDependencies?.today.dailySummaryUseCase
            ?? VelaResolver.shared.resolve(DailySummaryUseCase.self)
    }
    var syncCoordinator: AppSyncCoordinator {
        injectedDependencies?.health.syncCoordinator
            ?? VelaResolver.shared.resolve(AppSyncCoordinator.self)
    }
    var coachChat: CoachChatVM {
        VelaResolver.shared.resolve(CoachChatVM.self)
    }
    var proactiveOrchestrator: ProactiveIntelligenceOrchestrator {
        VelaResolver.shared.resolve(ProactiveIntelligenceOrchestrator.self)
    }
    var workoutAdaptationService: WorkoutAdaptationService {
        VelaResolver.shared.resolve(WorkoutAdaptationService.self)
    }

    /// WebSearchService uses a private singleton — expose via computed property.
    /// D10：WebSearchService 为死代码（线上路径是 WebSearchHelper），已移除暴露。

    /// WikiFileService is a stateless enum namespace — reference directly or via this alias.
    typealias Wiki = WikiFileService

    private var providerCache: [String: DeepSeekProvider] = [:]

    init(dependencies: AppDependencies? = nil) {
        self.injectedDependencies = dependencies
    }

    func deepSeekProvider(apiKey: String, model: String? = nil) -> DeepSeekProvider {
        let model = model ?? DeepSeekTextModel.stored.apiIdentifier
        let cacheKey = "\(apiKey)|\(model)"
        if let cached = providerCache[cacheKey] {
            return cached
        }
        let provider = DeepSeekProvider(apiKey: apiKey, model: model)
        providerCache[cacheKey] = provider
        return provider
    }
}

@MainActor
final class VelaResolver {
    static let shared = VelaResolver()
    
    private var factories: [String: () -> Any] = [:]
    private var cache: [String: Any] = [:]
    
    private init() {
        // Register default implementations
        register(HealthQueryService.self) { HealthKitQueryService() }
        register(AIContextBuilder.self) { AIContextBuilder() }
        register(AppSyncCoordinator.self) { AppSyncCoordinator.shared }
        register(DailySummaryUseCase.self) {
            DailySummaryUseCase(
                queryService: self.resolve(HealthQueryService.self),
                syncCoordinator: self.resolve(AppSyncCoordinator.self)
            )
        }
        register(CoachChatVM.self) { CoachChatVM() }
        register(VelaEventService.self) { VelaEventService.shared }
        register(ProactiveIntelligenceOrchestrator.self) { ProactiveIntelligenceOrchestrator() }
        register(WorkoutAdaptationService.self) { WorkoutAdaptationService() }
    }
    
    func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        let key = String(describing: type)
        factories[key] = factory
        cache.removeValue(forKey: key)
    }
    
    func resolve<T>(_ type: T.Type) -> T {
        let key = String(describing: type)
        if let cached = cache[key] as? T {
            return cached
        }
        guard let factory = factories[key] else {
            fatalError("No registered factory for \(key)")
        }
        let resolved = factory() as! T
        cache[key] = resolved
        return resolved
    }
    
    func reset() {
        cache.removeAll()
    }
}

@MainActor
final class VelaEventService {
    static let shared = VelaEventService()
    
    private init() {}
    
    func log(
        modelContext: ModelContext,
        type: String,
        title: String,
        detail: String = "",
        metadata: [String: Any] = [:]
    ) {
        let metadataJSON: String
        if let data = try? JSONSerialization.data(withJSONObject: metadata, options: []),
           let json = String(data: data, encoding: .utf8) {
            metadataJSON = json
        } else {
            metadataJSON = "{}"
        }
        
        let record = VelaEventRecord(
            eventType: type,
            timestamp: Date(),
            title: title,
            detail: detail,
            metadataJSON: metadataJSON
        )
        
        modelContext.insert(record)
        try? modelContext.save()
        
        // Notify local app state that data changed
        VelaAppState.shared.markLocalDataChanged()
    }
    
    func fetchEvents(
        modelContext: ModelContext,
        start: Date,
        end: Date
    ) -> [VelaEventRecord] {
        let descriptor = FetchDescriptor<VelaEventRecord>(
            predicate: #Predicate<VelaEventRecord> { $0.timestamp >= start && $0.timestamp <= end },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

enum VelaProductEventType {
    static let dailyDecisionViewed = "daily_decision_viewed"
    static let dailyDecisionActionStarted = "daily_decision_action_started"
    static let dailyDecisionFeedbackSaved = "daily_decision_feedback_saved"
    static let healthSyncSucceeded = "health_sync_succeeded"
    static let healthSyncFailed = "health_sync_failed"
    static let proactiveInsightGenerated = "proactive_insight_generated"
    static let trainingPlanAdapted = "training_plan_adapted"
    static let workoutCompleted = "workout_completed"
}

struct ProductQualitySnapshot: Equatable {
    var periodDays: Int
    var generatedPlans: Int
    var viewedDecisions: Int
    var startedActions: Int
    var completedFeedback: Int
    var adoptedDecisions: Int
    var accurateDecisions: Int
    var workoutLogs: Int
    var syncSuccesses: Int
    var syncFailures: Int

    var viewRate: Double { ratio(viewedDecisions, generatedPlans) }
    var actionRate: Double { ratio(startedActions, viewedDecisions) }
    var feedbackRate: Double { ratio(completedFeedback, startedActions) }
    var adoptionRate: Double { ratio(adoptedDecisions, completedFeedback) }
    var accuracyRate: Double { ratio(accurateDecisions, completedFeedback) }
    var syncSuccessRate: Double { ratio(syncSuccesses, syncSuccesses + syncFailures) }

    private func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }
}

@MainActor
struct DailyDecisionFeedbackService {
    @discardableResult
    func recordViewed(
        modelContext: ModelContext,
        dayIdentifier: String,
        plan: DailyOperatingPlanRecord?,
        bodyStateHash: String,
        decisionType: String,
        decisionTitle: String,
        now: Date = Date()
    ) throws -> DailyDecisionFeedbackRecord {
        let record = try upsert(
            modelContext: modelContext,
            dayIdentifier: dayIdentifier,
            plan: plan,
            bodyStateHash: bodyStateHash,
            decisionType: decisionType,
            decisionTitle: decisionTitle,
            now: now
        )
        guard record.viewedAt == nil else { return record }
        record.viewedAt = now
        record.updatedAt = now
        VelaEventService.shared.log(
            modelContext: modelContext,
            type: VelaProductEventType.dailyDecisionViewed,
            title: "Viewed daily decision",
            metadata: ["day": dayIdentifier, "decision_type": decisionType]
        )
        return record
    }

    @discardableResult
    func recordActionStarted(
        modelContext: ModelContext,
        dayIdentifier: String,
        plan: DailyOperatingPlanRecord?,
        bodyStateHash: String,
        decisionType: String,
        decisionTitle: String,
        destination: String,
        now: Date = Date()
    ) throws -> DailyDecisionFeedbackRecord {
        let record = try recordViewed(
            modelContext: modelContext,
            dayIdentifier: dayIdentifier,
            plan: plan,
            bodyStateHash: bodyStateHash,
            decisionType: decisionType,
            decisionTitle: decisionTitle,
            now: now
        )
        guard record.actionStartedAt == nil else { return record }
        record.actionStartedAt = now
        record.actionDestination = destination
        record.updatedAt = now
        VelaEventService.shared.log(
            modelContext: modelContext,
            type: VelaProductEventType.dailyDecisionActionStarted,
            title: "Started daily action",
            metadata: ["day": dayIdentifier, "destination": destination]
        )
        return record
    }

    func saveFeedback(
        modelContext: ModelContext,
        record: DailyDecisionFeedbackRecord,
        adoptionStatus: String,
        accuracyRating: String,
        actualAction: String,
        energyRating: Int?,
        fatigueRating: Int?,
        painRating: Int?,
        satisfactionRating: Int?,
        note: String,
        now: Date = Date()
    ) throws {
        record.adoptionStatus = adoptionStatus
        record.accuracyRating = accuracyRating
        record.actualAction = actualAction
        record.energyRating = energyRating
        record.fatigueRating = fatigueRating
        record.painRating = painRating
        record.satisfactionRating = satisfactionRating
        record.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        record.updatedAt = now
        VelaEventService.shared.log(
            modelContext: modelContext,
            type: VelaProductEventType.dailyDecisionFeedbackSaved,
            title: "Saved daily decision feedback",
            metadata: [
                "day": record.dayIdentifier,
                "adoption": adoptionStatus,
                "accuracy": accuracyRating,
                "actual_action": actualAction
            ]
        )
    }

    func qualitySnapshot(
        modelContext: ModelContext,
        periodDays: Int = 28,
        now: Date = Date()
    ) -> ProductQualitySnapshot {
        let cutoff = now.addingTimeInterval(-Double(periodDays) * 86_400)
        let plans = (try? modelContext.fetch(FetchDescriptor<DailyOperatingPlanRecord>(
            predicate: #Predicate { $0.generatedAt >= cutoff }
        ))) ?? []
        let feedback = (try? modelContext.fetch(FetchDescriptor<DailyDecisionFeedbackRecord>(
            predicate: #Predicate { $0.updatedAt >= cutoff }
        ))) ?? []
        let events = VelaEventService.shared.fetchEvents(modelContext: modelContext, start: cutoff, end: now)
        let completed = feedback.filter(\.isCompleted)
        return ProductQualitySnapshot(
            periodDays: periodDays,
            generatedPlans: plans.count,
            viewedDecisions: feedback.filter { $0.viewedAt != nil }.count,
            startedActions: feedback.filter { $0.actionStartedAt != nil }.count,
            completedFeedback: completed.count,
            adoptedDecisions: completed.filter { $0.adoptionStatus == "followed" || $0.adoptionStatus == "modified" }.count,
            accurateDecisions: completed.filter { $0.accuracyRating == "accurate" || $0.accuracyRating == "partly" }.count,
            // 训练完成打卡路径记录 workout_completed；历史/其他路径可能记录
            // workout_log（XII）：两者都算训练记录完成，否则诊断页长期少计。
            workoutLogs: events.filter {
                $0.eventType == "workout_log" || $0.eventType == VelaProductEventType.workoutCompleted
            }.count,
            syncSuccesses: events.filter { $0.eventType == VelaProductEventType.healthSyncSucceeded }.count,
            syncFailures: events.filter { $0.eventType == VelaProductEventType.healthSyncFailed }.count
        )
    }

    func calculateFeedbackCalibration(
        modelContext: ModelContext,
        periodDays: Int = 14,
        now: Date = Date()
    ) -> DecisionFeedbackCalibration {
        let cutoff = now.addingTimeInterval(-Double(periodDays) * 86_400)
        let feedback = (try? modelContext.fetch(FetchDescriptor<DailyDecisionFeedbackRecord>(
            predicate: #Predicate {
                $0.updatedAt >= cutoff && $0.updatedAt <= now && $0.createdAt <= now
            }
        ))) ?? []
        let completed = feedback.filter(\.isCompleted)
        guard completed.count >= 3 else {
            return DecisionFeedbackCalibration(completedFeedbackCount: completed.count, volumeAdjustmentMultiplier: 0.0)
        }

        var conservativeOverdrive = 0
        var fatigueOverdrive = 0

        for item in completed {
            let energy = item.energyRating ?? 3
            let fatigue = item.fatigueRating ?? 3
            let satisfaction = item.satisfactionRating ?? 3

            if (item.adoptionStatus == "modified" || item.adoptionStatus == "ignored") && energy >= 4 && fatigue <= 2 {
                conservativeOverdrive += 1
            } else if item.accuracyRating == "inaccurate" && energy >= 4 {
                conservativeOverdrive += 1
            }

            if fatigue >= 4 || (satisfaction <= 2 && fatigue >= 3) {
                fatigueOverdrive += 1
            }
        }

        let count = completed.count
        if Double(conservativeOverdrive) / Double(count) >= 0.50 {
            return DecisionFeedbackCalibration(
                completedFeedbackCount: count,
                volumeAdjustmentMultiplier: 0.05,
                note: "近期反馈显示精力充沛且多次主动加量，容量微调 +5%"
            )
        } else if Double(fatigueOverdrive) / Double(count) >= 0.50 {
            return DecisionFeedbackCalibration(
                completedFeedbackCount: count,
                volumeAdjustmentMultiplier: -0.05,
                note: "近期反馈疲劳感偏高，容量微调 -5%"
            )
        }

        return DecisionFeedbackCalibration(
            completedFeedbackCount: count,
            volumeAdjustmentMultiplier: 0.0
        )
    }

    private func upsert(
        modelContext: ModelContext,
        dayIdentifier: String,
        plan: DailyOperatingPlanRecord?,
        bodyStateHash: String,
        decisionType: String,
        decisionTitle: String,
        now: Date
    ) throws -> DailyDecisionFeedbackRecord {
        let descriptor = FetchDescriptor<DailyDecisionFeedbackRecord>(
            predicate: #Predicate { $0.dayIdentifier == dayIdentifier }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.planGeneratedAt = plan?.generatedAt
            existing.bodyStateHash = bodyStateHash
            existing.decisionType = decisionType
            existing.decisionTitle = decisionTitle
            existing.updatedAt = now
            return existing
        }
        let record = DailyDecisionFeedbackRecord(
            dayIdentifier: dayIdentifier,
            planGeneratedAt: plan?.generatedAt,
            bodyStateHash: bodyStateHash,
            decisionType: decisionType,
            decisionTitle: decisionTitle,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(record)
        return record
    }
}

struct PersonalExperimentTemplate: Identifiable, Hashable {
    var id: String
    var title: String
    var hypothesis: String
    var protocolText: String
    var targetBehaviorTag: String
    var durationDays: Int
}

struct PersonalExperimentOutcome: Equatable {
    var baselineAverage: Double?
    var experimentAverage: Double?
    var baselineSampleCount: Int
    var experimentSampleCount: Int
    var adherenceRate: Double

    var delta: Double? {
        guard let baselineAverage, let experimentAverage else { return nil }
        return experimentAverage - baselineAverage
    }

    var hasEnoughEvidence: Bool {
        baselineSampleCount >= 3 && experimentSampleCount >= 5
    }
}

@MainActor
struct PersonalExperimentService {
    static let templates: [PersonalExperimentTemplate] = [
        PersonalExperimentTemplate(
            id: "caffeine_cutoff",
            title: "下午 2 点后不喝咖啡因",
            hypothesis: "减少晚间咖啡因暴露，可能改善入睡与睡眠评分。",
            protocolText: "连续 14 天，14:00 后不摄入咖啡、茶、能量饮料或含咖啡因补剂。",
            targetBehaviorTag: "caffeine_cutoff",
            durationDays: 14
        ),
        PersonalExperimentTemplate(
            id: "consistent_bedtime",
            title: "固定睡眠窗口",
            hypothesis: "更稳定的上床时间，可能改善睡眠连续性与次日恢复。",
            protocolText: "连续 14 天，在设置的目标上床时间前后 30 分钟内上床。",
            targetBehaviorTag: "consistent_bedtime",
            durationDays: 14
        ),
        PersonalExperimentTemplate(
            id: "alcohol_free",
            title: "无酒精睡眠实验",
            hypothesis: "避免酒精，可能改善 HRV、静息心率和睡眠结构。",
            protocolText: "连续 14 天不饮酒；如未做到，请如实记录，不需要中断实验。",
            targetBehaviorTag: "alcohol_free",
            durationDays: 14
        ),
        PersonalExperimentTemplate(
            id: "early_dinner",
            title: "睡前 3 小时结束晚餐",
            hypothesis: "减少临睡前进食，可能改善夜间恢复与睡眠质量。",
            protocolText: "连续 14 天，在计划上床前至少 3 小时结束正餐与高热量加餐。",
            targetBehaviorTag: "early_dinner",
            durationDays: 14
        )
    ]

    func start(
        template: PersonalExperimentTemplate,
        modelContext: ModelContext,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> PersonalExperimentRecord {
        let active = try modelContext.fetch(FetchDescriptor<PersonalExperimentRecord>(
            predicate: #Predicate { $0.status == "active" }
        ))
        active.forEach { existing in
            existing.status = "cancelled"
            existing.updatedAt = now
        }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: template.durationDays, to: start) ?? now
        let record = PersonalExperimentRecord(
            templateID: template.id,
            title: template.title,
            hypothesis: template.hypothesis,
            protocolText: template.protocolText,
            targetBehaviorTag: template.targetBehaviorTag,
            startDate: start,
            endDate: end,
            createdAt: now,
            updatedAt: now
        )
        modelContext.insert(record)
        try modelContext.save()
        VelaAppState.shared.markLocalDataChanged()
        return record
    }

    func checkIn(
        experiment: PersonalExperimentRecord,
        followed: Bool,
        note: String = "",
        modelContext: ModelContext,
        date: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        let day = calendar.startOfDay(for: date)
        let dayID = DailyHealthSummaryRecord.dayIdentifier(for: day, calendar: calendar)
        let recordID = "\(experiment.id.uuidString):\(dayID)"
        let descriptor = FetchDescriptor<ExperimentCheckInRecord>(
            predicate: #Predicate { $0.id == recordID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.followedProtocol = followed
            existing.note = note
            existing.updatedAt = date
        } else {
            modelContext.insert(ExperimentCheckInRecord(
                experimentID: experiment.id,
                dayIdentifier: dayID,
                date: day,
                followedProtocol: followed,
                note: note,
                createdAt: date,
                updatedAt: date
            ))
        }
        if day >= experiment.endDate {
            experiment.status = "completed"
            experiment.updatedAt = date
        }
        try modelContext.save()
        VelaAppState.shared.markLocalDataChanged()
    }

    func outcome(
        experiment: PersonalExperimentRecord,
        summaries: [DailyHealthSummaryRecord],
        checkIns: [ExperimentCheckInRecord],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PersonalExperimentOutcome {
        let baselineStart = calendar.date(byAdding: .day, value: -experiment.baselineDays, to: experiment.startDate) ?? experiment.startDate
        let observationEnd = min(now, experiment.endDate)
        let baseline = summaries.filter { $0.date >= baselineStart && $0.date < experiment.startDate }.compactMap(\.sleepScore)
        let experimentValues = summaries.filter { $0.date >= experiment.startDate && $0.date <= observationEnd }.compactMap(\.sleepScore)
        let relevantCheckIns = checkIns.filter { $0.experimentID == experiment.id }
        let adherence = relevantCheckIns.isEmpty
            ? 0
            : Double(relevantCheckIns.filter(\.followedProtocol).count) / Double(relevantCheckIns.count)
        return PersonalExperimentOutcome(
            baselineAverage: average(baseline),
            experimentAverage: average(experimentValues),
            baselineSampleCount: baseline.count,
            experimentSampleCount: experimentValues.count,
            adherenceRate: adherence
        )
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
