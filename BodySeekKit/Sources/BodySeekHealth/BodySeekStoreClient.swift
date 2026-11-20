import BodySeekCore
import BodySeekStore
import Dependencies
import DependenciesMacros
import Foundation
import os
#if os(iOS)
import HealthKit
#endif

/// Process-wide GRDB runtime coordinator shared by `BodySeekStoreClient` and `FitnessStoreClient`.
public actor BodySeekSharedStore {
    public static let shared = BodySeekSharedStore()
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "BodySeekSharedStore")

    private var cachedDB: BodySeekDatabase?
    private var cachedRepo: BodySeekRepository?
    private var cachedExecutor: ActionExecutor?
    private var cachedReadModel: BodySeekReadModel?
    private var hasCheckedLegacyImport = false
    private var lastBackfillRunAt: Date?

    private init() {}

    public func database() throws -> BodySeekDatabase {
        if let cachedDB { return cachedDB }
        let db = try BodySeekDatabase.openOnDisk()
        cachedDB = db
        return db
    }

    public func repository() throws -> BodySeekRepository {
        if let cachedRepo { return cachedRepo }
        let repo = BodySeekRepository(database: try database())
        cachedRepo = repo
        return repo
    }

    public func executor() throws -> ActionExecutor {
        if let cachedExecutor { return cachedExecutor }
        let exec = ActionExecutor(database: try database())
        cachedExecutor = exec
        return exec
    }

    public func readModel() throws -> BodySeekReadModel {
        if let cachedReadModel { return cachedReadModel }
        let rm = BodySeekReadModel(database: try database())
        cachedReadModel = rm
        return rm
    }

    @discardableResult
    public func ensureLegacyMigratedIfNeeded() async throws -> LegacyImportReport {
        let repo = try repository()
        if hasCheckedLegacyImport {
            if let anchor = try await repo.loadSyncAnchor(type: LegacyDataImporter.anchorKey) {
                return LegacyImportReport(
                    alreadyImported: true,
                    templatesImported: 0,
                    sessionsImported: 0,
                    memoriesImported: 0,
                    messagesImported: 0,
                    checkInsImported: 0,
                    completedAt: anchor.updatedAt
                )
            }
        }

        let report = try await LegacyDataImporter.importIfNeeded(into: repo) {
            let swiftDataPayload = try BodySeekSwiftDataBackend.shared.exportLegacyPayloadIfStoreExists()
            let prefs = try PreferencesClient.liveValue.load()
            let legacyCheckIns = Array(prefs.checkInsByDay.values)
            if swiftDataPayload == nil && legacyCheckIns.isEmpty {
                return nil
            }
            return LegacyImportPayload(
                templates: swiftDataPayload?.templates ?? [],
                sessions: swiftDataPayload?.sessions ?? [],
                memories: swiftDataPayload?.memories ?? [],
                messages: swiftDataPayload?.messages ?? [],
                checkIns: legacyCheckIns
            )
        }
        hasCheckedLegacyImport = true
        return report
    }

    public func runSyncRecentIfAvailable(
        sleepGoalMinutes: Int,
        referenceDate: Date
    ) async throws -> SyncRunSummary? {
        #if os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let repo = try repository()
        let engine = SyncEngine(
            repository: repo,
            source: LiveHealthKitSyncSource(),
            sleepGoalMinutes: sleepGoalMinutes
        )
        return try await engine.syncRecentWindow(days: 30, referenceDate: referenceDate)
        #else
        return nil
        #endif
    }

    public func runBackfillIfAvailable(
        sleepGoalMinutes: Int,
        referenceDate: Date
    ) async throws -> BackfillRunSummary? {
        #if os(iOS)
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        if let lastBackfillRunAt, referenceDate.timeIntervalSince(lastBackfillRunAt) < 120 {
            return nil
        }
        lastBackfillRunAt = referenceDate
        let repo = try repository()
        let engine = SyncEngine(
            repository: repo,
            source: LiveHealthKitSyncSource(),
            sleepGoalMinutes: sleepGoalMinutes
        )
        return try await engine.runResumableBackfill(totalMonths: 36, referenceDate: referenceDate)
        #else
        return nil
        #endif
    }

    public func resetAll() async throws {
        let repo = try repository()
        try await repo.resetAll()
        hasCheckedLegacyImport = true
    }
}

private actor PreviewGRDBContainer {
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "PreviewGRDBContainer")
    private var db: BodySeekDatabase?

    func resolve() throws -> (BodySeekDatabase, BodySeekRepository, ActionExecutor, BodySeekReadModel) {
        if let db {
            return (db, BodySeekRepository(database: db), ActionExecutor(database: db), BodySeekReadModel(database: db))
        }
        let created = try BodySeekDatabase.inMemory()
        db = created
        return (created, BodySeekRepository(database: created), ActionExecutor(database: created), BodySeekReadModel(database: created))
    }
}

@DependencyClient
public struct BodySeekStoreClient: Sendable {
    public var loadCachedDashboard: @Sendable (_ sleepGoalMinutes: Int, _ referenceDate: Date) async throws -> CachedDashboardState?
    public var observeDashboard: @Sendable (_ sleepGoalMinutes: Int) async -> AsyncThrowingStream<CachedDashboardState, Error> = { _ in
        AsyncThrowingStream { $0.finish() }
    }
    public var persistDashboardSnapshot: @Sendable (_ snapshot: BodySeekDashboardSnapshot) async throws -> Void
    public var syncRecentWindow: @Sendable (_ sleepGoalMinutes: Int, _ referenceDate: Date) async throws -> SyncRunSummary?
    public var runBackgroundBackfill: @Sendable (_ sleepGoalMinutes: Int, _ referenceDate: Date) async throws -> BackfillRunSummary?
    public var executeProposal: @Sendable (_ proposal: ActionProposal) async throws -> ActionAuditEntry
    public var loadCheckIns: @Sendable () async throws -> [DailyCheckIn] = { [] }
    public var loadPlanItems: @Sendable (_ dayKey: DayKey) async throws -> [PlanItemRecord] = { _ in [] }
    public var loadExperimentPlanItems: @Sendable () async throws -> [PlanItemRecord] = { [] }
    public var loadPatternFindings: @Sendable (_ status: PatternFindingStatus?) async throws -> [PatternFindingRecord] = { _ in [] }
    public var loadNutritionProfile: @Sendable () async throws -> NutritionProfile?
    public var loadNutritionTargetPlan: @Sendable () async throws -> NutritionTargetPlan?
    public var loadNutritionLogs: @Sendable (_ from: DayKey?, _ to: DayKey?) async throws -> [DailyNutritionLog] = { _, _ in [] }
    public var searchFoodLibrary: @Sendable (_ query: String) async throws -> [FoodLibraryItem] = { _ in [] }
    public var seedStarterFoodLibraryIfNeeded: @Sendable () async throws -> Void
    public var saveFoodLibraryItem: @Sendable (_ item: FoodLibraryItem) async throws -> Void
    public var loadStoredWorkouts: @Sendable (_ limit: Int?) async throws -> [StoredWorkoutRecord] = { _ in [] }
    public var upsertStoredWorkouts: @Sendable (_ workouts: [StoredWorkoutRecord], _ symbolByUUID: [String: String]) async throws -> Void
    public var loadWorkoutAnnotations: @Sendable (_ workoutUUID: String?) async throws -> [WorkoutAnnotationRecord] = { _ in [] }
    public var loadAllMuscleLoads: @Sendable (_ since: Date?) async throws -> [WorkoutMuscleLoadRecord] = { _ in [] }
    public var applyAutoWorkoutAttribution: @Sendable (_ workoutUUID: String, _ loads: [WorkoutMuscleLoadRecord]) async throws -> Bool = { _, _ in false }
    public var loadTieredMemories: @Sendable (_ includeRetired: Bool) async throws -> [TieredMemoryRecord] = { _ in [] }
    public var loadActionAuditEntries: @Sendable (_ limit: Int) async throws -> [ActionAuditEntry] = { _ in [] }
    public var savePatternFinding: @Sendable (_ finding: PatternFindingRecord) async throws -> Void
}

extension BodySeekStoreClient: DependencyKey {
    public static let liveValue: BodySeekStoreClient = {
        let preview = PreviewGRDBContainer()
        let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "BodySeekStoreClient")

        return BodySeekStoreClient(
            loadCachedDashboard: { goalMinutes, refDate in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                    || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
                {
                    return nil
                }
                _ = try await BodySeekSharedStore.shared.ensureLegacyMigratedIfNeeded()
                let readModel = try await BodySeekSharedStore.shared.readModel()
                return try await readModel.loadCachedDashboard(
                    sleepGoalMinutes: goalMinutes,
                    referenceDate: refDate,
                    sourceLabel: "Apple 健康 · 离线缓存",
                    isAuthorized: true
                )
            },
            observeDashboard: { goalMinutes in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                    || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
                {
                    return AsyncThrowingStream { $0.finish() }
                }
                do {
                    let readModel = try await BodySeekSharedStore.shared.readModel()
                    return readModel.observeDashboard(
                        sleepGoalMinutes: goalMinutes,
                        sourceLabel: "Apple 健康"
                    )
                } catch {
                    logger.error("Failed starting observeDashboard: \(error.localizedDescription, privacy: .public)")
                    return AsyncThrowingStream { $0.finish(throwing: error) }
                }
            },
            persistDashboardSnapshot: { snapshot in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                    || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
                {
                    return
                }
                guard snapshot.isAuthorized else { return }
                let repo = try await BodySeekSharedStore.shared.repository()
                let rawDays = snapshot.historyDays.map(\.raw)
                try await repo.saveDailyRawMetrics(rawDays)
                try await repo.saveComputedDays(snapshot.historyDays)
            },
            syncRecentWindow: { goalMinutes, refDate in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                    || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
                {
                    return nil
                }
                return try await BodySeekSharedStore.shared.runSyncRecentIfAvailable(
                    sleepGoalMinutes: goalMinutes,
                    referenceDate: refDate
                )
            },
            runBackgroundBackfill: { goalMinutes, refDate in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                    || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
                {
                    return nil
                }
                return try await BodySeekSharedStore.shared.runBackfillIfAvailable(
                    sleepGoalMinutes: goalMinutes,
                    referenceDate: refDate
                )
            },
            executeProposal: { proposal in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                    || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
                {
                    let (_, _, exec, _) = try await preview.resolve()
                    return try await exec.execute(proposal)
                }
                let exec = try await BodySeekSharedStore.shared.executor()
                return try await exec.execute(proposal)
            },
            loadCheckIns: {
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                    || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
                {
                    let (_, repo, _, _) = try await preview.resolve()
                    return try await repo.loadCheckIns()
                }
                _ = try await BodySeekSharedStore.shared.ensureLegacyMigratedIfNeeded()
                let repo = try await BodySeekSharedStore.shared.repository()
                return try await repo.loadCheckIns()
            },
            loadPlanItems: { dayKey in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                    || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
                {
                    let (_, repo, _, _) = try await preview.resolve()
                    return try await repo.loadPlanItems(dayKey: dayKey)
                }
                let repo = try await BodySeekSharedStore.shared.repository()
                return try await repo.loadPlanItems(dayKey: dayKey)
            },
            loadExperimentPlanItems: {
                let repo = try await liveOrPreviewRepo(preview: preview)
                return try await repo.loadExperimentPlanItems()
            },
            loadPatternFindings: { status in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                    || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
                {
                    let (_, repo, _, _) = try await preview.resolve()
                    return try await repo.loadPatternFindings(status: status)
                }
                let repo = try await BodySeekSharedStore.shared.repository()
                return try await repo.loadPatternFindings(status: status)
            },
            loadNutritionProfile: {
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                    || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
                {
                    let (_, repo, _, _) = try await preview.resolve()
                    return try await repo.loadNutritionProfile()
                }
                let repo = try await BodySeekSharedStore.shared.repository()
                return try await repo.loadNutritionProfile()
            },
            loadNutritionTargetPlan: {
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                    || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
                {
                    let (_, repo, _, _) = try await preview.resolve()
                    return try await repo.loadNutritionTargetPlan()
                }
                let repo = try await BodySeekSharedStore.shared.repository()
                return try await repo.loadNutritionTargetPlan()
            },
            loadNutritionLogs: { fromKey, toKey in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                    || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
                {
                    let (_, repo, _, _) = try await preview.resolve()
                    return try await repo.loadNutritionLogs(from: fromKey, to: toKey)
                }
                let repo = try await BodySeekSharedStore.shared.repository()
                return try await repo.loadNutritionLogs(from: fromKey, to: toKey)
            },
            searchFoodLibrary: { query in
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                    || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
                {
                    let (_, repo, _, _) = try await preview.resolve()
                    return try await repo.searchFoodLibrary(query: query)
                }
                let repo = try await BodySeekSharedStore.shared.repository()
                return try await repo.searchFoodLibrary(query: query)
            },
            seedStarterFoodLibraryIfNeeded: {
                if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
                    || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
                {
                    let (_, repo, _, _) = try await preview.resolve()
                    try await repo.seedStarterFoodLibraryIfNeeded()
                    return
                }
                let repo = try await BodySeekSharedStore.shared.repository()
                try await repo.seedStarterFoodLibraryIfNeeded()
            },
            saveFoodLibraryItem: { item in
                let repo = try await liveOrPreviewRepo(preview: preview)
                try await repo.saveFoodLibraryItem(item)
            },
            loadStoredWorkouts: { limit in
                let repo = try await liveOrPreviewRepo(preview: preview)
                return try await repo.loadWorkouts(limit: limit)
            },
            upsertStoredWorkouts: { workouts, symbolByUUID in
                let repo = try await liveOrPreviewRepo(preview: preview)
                try await repo.upsertWorkouts(workouts, symbolByUUID: symbolByUUID)
            },
            loadWorkoutAnnotations: { workoutUUID in
                let repo = try await liveOrPreviewRepo(preview: preview)
                return try await repo.loadWorkoutAnnotations(workoutUUID: workoutUUID)
            },
            loadAllMuscleLoads: { since in
                let repo = try await liveOrPreviewRepo(preview: preview)
                return try await repo.loadAllMuscleLoads(since: since)
            },
            applyAutoWorkoutAttribution: { workoutUUID, loads in
                let repo = try await liveOrPreviewRepo(preview: preview)
                return try await repo.applyAutoWorkoutAttribution(workoutUUID: workoutUUID, loads: loads)
            },
            loadTieredMemories: { includeRetired in
                let repo = try await liveOrPreviewRepo(preview: preview)
                return try await repo.loadTieredMemories(includeRetired: includeRetired)
            },
            loadActionAuditEntries: { limit in
                let repo = try await liveOrPreviewRepo(preview: preview)
                return Array(try await repo.loadAuditEntries().prefix(max(1, limit)))
            },
            savePatternFinding: { finding in
                let repo = try await liveOrPreviewRepo(preview: preview)
                try await repo.savePatternFinding(finding)
            }
        )
    }()

    private static func liveOrPreviewRepo(preview: PreviewGRDBContainer) async throws -> BodySeekRepository {
        if ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
            || ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
        {
            let (_, repo, _, _) = try await preview.resolve()
            return repo
        }
        return try await BodySeekSharedStore.shared.repository()
    }

    public static let previewValue: BodySeekStoreClient = makeInMemoryClient()

    public static var testValue: BodySeekStoreClient {
        makeInMemoryClient()
    }

    private static func makeInMemoryClient() -> BodySeekStoreClient {
        let preview = PreviewGRDBContainer()
        return BodySeekStoreClient(
            loadCachedDashboard: { _, _ in nil },
            observeDashboard: { _ in AsyncThrowingStream { $0.finish() } },
            persistDashboardSnapshot: { snapshot in
                let (_, repo, _, _) = try await preview.resolve()
                try await repo.saveDailyRawMetrics(snapshot.historyDays.map(\.raw))
                try await repo.saveComputedDays(snapshot.historyDays)
            },
            syncRecentWindow: { _, _ in nil },
            runBackgroundBackfill: { _, _ in nil },
            executeProposal: { proposal in
                let (_, _, exec, _) = try await preview.resolve()
                return try await exec.execute(proposal)
            },
            loadCheckIns: {
                let (_, repo, _, _) = try await preview.resolve()
                return try await repo.loadCheckIns()
            },
            loadPlanItems: { dayKey in
                let (_, repo, _, _) = try await preview.resolve()
                return try await repo.loadPlanItems(dayKey: dayKey)
            },
            loadExperimentPlanItems: {
                let (_, repo, _, _) = try await preview.resolve()
                return try await repo.loadExperimentPlanItems()
            },
            loadPatternFindings: { status in
                let (_, repo, _, _) = try await preview.resolve()
                return try await repo.loadPatternFindings(status: status)
            },
            loadNutritionProfile: {
                let (_, repo, _, _) = try await preview.resolve()
                return try await repo.loadNutritionProfile()
            },
            loadNutritionTargetPlan: {
                let (_, repo, _, _) = try await preview.resolve()
                return try await repo.loadNutritionTargetPlan()
            },
            loadNutritionLogs: { fromKey, toKey in
                let (_, repo, _, _) = try await preview.resolve()
                return try await repo.loadNutritionLogs(from: fromKey, to: toKey)
            },
            searchFoodLibrary: { query in
                let (_, repo, _, _) = try await preview.resolve()
                return try await repo.searchFoodLibrary(query: query)
            },
            seedStarterFoodLibraryIfNeeded: {
                let (_, repo, _, _) = try await preview.resolve()
                try await repo.seedStarterFoodLibraryIfNeeded()
            },
            saveFoodLibraryItem: { item in
                let (_, repo, _, _) = try await preview.resolve()
                try await repo.saveFoodLibraryItem(item)
            },
            loadStoredWorkouts: { limit in
                let (_, repo, _, _) = try await preview.resolve()
                return try await repo.loadWorkouts(limit: limit)
            },
            upsertStoredWorkouts: { workouts, symbolByUUID in
                let (_, repo, _, _) = try await preview.resolve()
                try await repo.upsertWorkouts(workouts, symbolByUUID: symbolByUUID)
            },
            loadWorkoutAnnotations: { workoutUUID in
                let (_, repo, _, _) = try await preview.resolve()
                return try await repo.loadWorkoutAnnotations(workoutUUID: workoutUUID)
            },
            loadAllMuscleLoads: { since in
                let (_, repo, _, _) = try await preview.resolve()
                return try await repo.loadAllMuscleLoads(since: since)
            },
            applyAutoWorkoutAttribution: { workoutUUID, loads in
                let (_, repo, _, _) = try await preview.resolve()
                return try await repo.applyAutoWorkoutAttribution(workoutUUID: workoutUUID, loads: loads)
            },
            loadTieredMemories: { includeRetired in
                let (_, repo, _, _) = try await preview.resolve()
                return try await repo.loadTieredMemories(includeRetired: includeRetired)
            },
            loadActionAuditEntries: { limit in
                let (_, repo, _, _) = try await preview.resolve()
                return Array(try await repo.loadAuditEntries().prefix(max(1, limit)))
            },
            savePatternFinding: { finding in
                let (_, repo, _, _) = try await preview.resolve()
                try await repo.savePatternFinding(finding)
            }
        )
    }
}

public extension DependencyValues {
    var bodySeekStoreClient: BodySeekStoreClient {
        get { self[BodySeekStoreClient.self] }
        set { self[BodySeekStoreClient.self] = newValue }
    }
}
