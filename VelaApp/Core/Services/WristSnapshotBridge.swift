import Foundation
@preconcurrency import WatchConnectivity
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Versioned contract shared by the iPhone bridge and its persisted payloads.
///
/// The watch and the iPhone do not share a Swift module, so the corresponding
/// watch-side constants live in `VelaWatchApp.swift`. Keep the values and the
/// boundary algorithm in lockstep when this envelope evolves.
enum WristSnapshotContract {
    static let currentSchemaVersion = 2
    static let legacySchemaVersion = 1
    static let healthDayBoundaryMinutes = 4 * 60

    static func isSupported(schemaVersion: Int) -> Bool {
        schemaVersion == legacySchemaVersion || schemaVersion == currentSchemaVersion
    }

    static func healthDayIdentifier(
        for date: Date,
        calendar: Calendar = .current
    ) -> String {
        let midnight = calendar.startOfDay(for: date)
        let boundary = calendar.date(
            byAdding: .minute,
            value: healthDayBoundaryMinutes,
            to: midnight
        ) ?? midnight
        let labelDate: Date
        if date >= boundary {
            labelDate = midnight
        } else {
            labelDate = calendar.date(byAdding: .day, value: -1, to: midnight) ?? midnight
        }
        let components = calendar.dateComponents([.year, .month, .day], from: labelDate)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func isCurrentHealthDay(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        healthDayIdentifier(for: date, calendar: calendar)
            == healthDayIdentifier(for: now, calendar: calendar)
    }
}

// MARK: - WidgetKit Shared Snapshot & Data Provider (P3)

public struct VelaWidgetSnapshot: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var bodyStateTitle: String
    public var summary: String
    public var decision: String
    public var decisionConfidence: Double
    public var recoveryScore: Int?
    public var sleepScore: Int?
    public var strainScore: Int?
    public var stressScore: Int?
    public var energyScore: Int?
    public var hrvMilliseconds: Int?
    public var restingHeartRate: Int?
    public var primaryAction: String
    public var planTitle: String?
    public var sessionTitle: String?
    public var sessionDetail: String?
    public var planProgress: String?

    public var isStale: Bool {
        Date().timeIntervalSince(generatedAt) > 12 * 3600
            || !WristSnapshotContract.isCurrentHealthDay(generatedAt)
    }

    public init(
        generatedAt: Date = Date(),
        bodyStateTitle: String = "恢复状态",
        summary: String = "准备就绪",
        decision: String = "按计划训练",
        decisionConfidence: Double = 0.85,
        recoveryScore: Int? = 80,
        sleepScore: Int? = 78,
        strainScore: Int? = 30,
        stressScore: Int? = 25,
        energyScore: Int? = 75,
        hrvMilliseconds: Int? = 55,
        restingHeartRate: Int? = 54,
        primaryAction: String = "开始今日训练",
        planTitle: String? = nil,
        sessionTitle: String? = nil,
        sessionDetail: String? = nil,
        planProgress: String? = nil
    ) {
        self.generatedAt = generatedAt
        self.bodyStateTitle = bodyStateTitle
        self.summary = summary
        self.decision = decision
        self.decisionConfidence = decisionConfidence
        self.recoveryScore = recoveryScore
        self.sleepScore = sleepScore
        self.strainScore = strainScore
        self.stressScore = stressScore
        self.energyScore = energyScore
        self.hrvMilliseconds = hrvMilliseconds
        self.restingHeartRate = restingHeartRate
        self.primaryAction = primaryAction
        self.planTitle = planTitle
        self.sessionTitle = sessionTitle
        self.sessionDetail = sessionDetail
        self.planProgress = planProgress
    }

    init(from wristSnapshot: WristSnapshot) {
        self.generatedAt = wristSnapshot.generatedAt
        self.bodyStateTitle = wristSnapshot.bodyStateTitle
        self.summary = wristSnapshot.summary
        self.decision = wristSnapshot.decision
        self.decisionConfidence = wristSnapshot.decisionConfidence
        self.recoveryScore = wristSnapshot.recoveryScore
        self.sleepScore = wristSnapshot.sleepScore
        self.strainScore = wristSnapshot.strainScore
        self.stressScore = wristSnapshot.stressScore
        self.energyScore = wristSnapshot.energyScore
        self.hrvMilliseconds = wristSnapshot.hrvMilliseconds
        self.restingHeartRate = wristSnapshot.restingHeartRate
        self.primaryAction = wristSnapshot.primaryAction
        self.planTitle = wristSnapshot.planTitle
        self.sessionTitle = wristSnapshot.sessionTitle
        self.sessionDetail = wristSnapshot.sessionDetail
        self.planProgress = wristSnapshot.planProgress
    }
}

public final class VelaWidgetDataProvider: @unchecked Sendable {
    public static let shared = VelaWidgetDataProvider()
    public static let appGroupSuiteName = "group.com.sunweizhou.Vela"
    public static let widgetSnapshotKey = "vela.widget.latest-snapshot"

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public var userDefaults: UserDefaults {
        UserDefaults(suiteName: Self.appGroupSuiteName) ?? .standard
    }

    public func saveSnapshot(_ snapshot: VelaWidgetSnapshot) {
        if let data = try? encoder.encode(snapshot) {
            userDefaults.set(data, forKey: Self.widgetSnapshotKey)
            if userDefaults != .standard {
                UserDefaults.standard.set(data, forKey: Self.widgetSnapshotKey)
            }
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }

    public func loadSnapshot() -> VelaWidgetSnapshot? {
        if let data = userDefaults.data(forKey: Self.widgetSnapshotKey),
           let snapshot = try? decoder.decode(VelaWidgetSnapshot.self, from: data) {
            return snapshot
        }
        if let data = UserDefaults.standard.data(forKey: Self.widgetSnapshotKey),
           let snapshot = try? decoder.decode(VelaWidgetSnapshot.self, from: data) {
            return snapshot
        }
        return nil
    }

    func updateSnapshot(from wristSnapshot: WristSnapshot) {
        let widgetSnapshot = VelaWidgetSnapshot(from: wristSnapshot)
        saveSnapshot(widgetSnapshot)
    }

    public func clearSnapshot() {
        userDefaults.removeObject(forKey: Self.widgetSnapshotKey)
        UserDefaults.standard.removeObject(forKey: Self.widgetSnapshotKey)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

struct WristSnapshot: Codable, Equatable, Sendable {
    var generatedAt: Date
    /// `1` is the pre-health-day/versioned envelope. Decoding it remains
    /// supported so a watch that has not yet been updated can still render the
    /// last snapshot; new payloads always publish the current version.
    var schemaVersion: Int = WristSnapshotContract.currentSchemaVersion
    /// Calendar-day label using the app's 04:00 health-day boundary. Optional
    /// for legacy payloads that only carried `generatedAt`.
    var healthDayIdentifier: String? = nil
    var bodyStateTitle: String
    var summary: String
    var decision: String
    var decisionConfidence: Double
    var recoveryScore: Int?
    var sleepScore: Int?
    var strainScore: Int?
    var stressScore: Int? = nil
    var energyScore: Int? = nil
    var hrvMilliseconds: Int?
    var restingHeartRate: Int?
    var primaryAction: String
    var planTitle: String?
    var sessionTitle: String?
    var sessionDetail: String?
    var planProgress: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case healthDayIdentifier
        case bodyStateTitle
        case summary
        case decision
        case decisionConfidence
        case recoveryScore
        case sleepScore
        case strainScore
        case stressScore
        case energyScore
        case hrvMilliseconds
        case restingHeartRate
        case primaryAction
        case planTitle
        case sessionTitle
        case sessionDetail
        case planProgress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? WristSnapshotContract.legacySchemaVersion
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        healthDayIdentifier = try container.decodeIfPresent(String.self, forKey: .healthDayIdentifier)
        bodyStateTitle = try container.decode(String.self, forKey: .bodyStateTitle)
        summary = try container.decode(String.self, forKey: .summary)
        decision = try container.decode(String.self, forKey: .decision)
        decisionConfidence = try container.decode(Double.self, forKey: .decisionConfidence)
        recoveryScore = try container.decodeIfPresent(Int.self, forKey: .recoveryScore)
        sleepScore = try container.decodeIfPresent(Int.self, forKey: .sleepScore)
        strainScore = try container.decodeIfPresent(Int.self, forKey: .strainScore)
        stressScore = try container.decodeIfPresent(Int.self, forKey: .stressScore)
        energyScore = try container.decodeIfPresent(Int.self, forKey: .energyScore)
        hrvMilliseconds = try container.decodeIfPresent(Int.self, forKey: .hrvMilliseconds)
        restingHeartRate = try container.decodeIfPresent(Int.self, forKey: .restingHeartRate)
        primaryAction = try container.decode(String.self, forKey: .primaryAction)
        planTitle = try container.decodeIfPresent(String.self, forKey: .planTitle)
        sessionTitle = try container.decodeIfPresent(String.self, forKey: .sessionTitle)
        sessionDetail = try container.decodeIfPresent(String.self, forKey: .sessionDetail)
        planProgress = try container.decodeIfPresent(String.self, forKey: .planProgress)
    }

    /// Explicit memberwise initializer retained because the compatibility
    /// decoder above suppresses Swift's synthesized memberwise initializer.
    /// Keep the original parameter order so existing callers remain source
    /// compatible; new contract fields are appended with defaults.
    init(
        generatedAt: Date,
        bodyStateTitle: String,
        summary: String,
        decision: String,
        decisionConfidence: Double,
        recoveryScore: Int?,
        sleepScore: Int?,
        strainScore: Int?,
        stressScore: Int? = nil,
        energyScore: Int? = nil,
        hrvMilliseconds: Int? = nil,
        restingHeartRate: Int? = nil,
        primaryAction: String = "打开 Vela",
        planTitle: String? = nil,
        sessionTitle: String? = nil,
        sessionDetail: String? = nil,
        planProgress: String? = nil,
        schemaVersion: Int = WristSnapshotContract.currentSchemaVersion,
        healthDayIdentifier: String? = nil
    ) {
        self.generatedAt = generatedAt
        self.schemaVersion = schemaVersion
        self.healthDayIdentifier = healthDayIdentifier
        self.bodyStateTitle = bodyStateTitle
        self.summary = summary
        self.decision = decision
        self.decisionConfidence = decisionConfidence
        self.recoveryScore = recoveryScore
        self.sleepScore = sleepScore
        self.strainScore = strainScore
        self.stressScore = stressScore
        self.energyScore = energyScore
        self.hrvMilliseconds = hrvMilliseconds
        self.restingHeartRate = restingHeartRate
        self.primaryAction = primaryAction
        self.planTitle = planTitle
        self.sessionTitle = sessionTitle
        self.sessionDetail = sessionDetail
        self.planProgress = planProgress
    }
}

/// Minimal, append-only payload emitted by an Apple Watch workout. It is
/// intentionally independent of `WristSnapshot`: a workout recorded entirely
/// on the watch must remain valid when the iPhone has no current dashboard
/// snapshot or is temporarily unreachable.
struct WristTrainingObservation: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    static func isSupported(schemaVersion: Int) -> Bool {
        schemaVersion == currentSchemaVersion
    }

    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var workoutKind: String
    var activeCalories: Double
    var averageHeartRate: Double?
    var completedSets: Int
    var healthDayIdentifier: String
    var schemaVersion: Int = Self.currentSchemaVersion
    var source: String = "appleWatch"

    private enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case endedAt
        case workoutKind
        case activeCalories
        case averageHeartRate
        case completedSets
        case healthDayIdentifier
        case schemaVersion
        case source
    }

    /// The first observation envelope shipped without an explicit schema field.
    /// Decode that payload as v1 so a queued workout survives an app/watch
    /// upgrade instead of being dropped by synthesized Codable decoding.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        workoutKind = try container.decode(String.self, forKey: .workoutKind)
        activeCalories = try container.decodeIfPresent(Double.self, forKey: .activeCalories) ?? 0
        averageHeartRate = try container.decodeIfPresent(Double.self, forKey: .averageHeartRate)
        completedSets = try container.decodeIfPresent(Int.self, forKey: .completedSets) ?? 0
        healthDayIdentifier = try container.decodeIfPresent(String.self, forKey: .healthDayIdentifier)
            ?? WristSnapshotContract.healthDayIdentifier(for: startedAt)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "appleWatch"
    }

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        workoutKind: String,
        activeCalories: Double = 0,
        averageHeartRate: Double? = nil,
        completedSets: Int = 0,
        healthDayIdentifier: String,
        schemaVersion: Int = Self.currentSchemaVersion,
        source: String = "appleWatch"
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.workoutKind = workoutKind
        self.activeCalories = max(0, activeCalories)
        self.averageHeartRate = averageHeartRate
        self.completedSets = max(0, completedSets)
        self.healthDayIdentifier = healthDayIdentifier
        self.schemaVersion = schemaVersion
        self.source = source
    }
}

/// The persistence-neutral shape produced by the Watch observation adapter.
/// `recordID` is deliberately the Watch observation UUID: it is the stable
/// idempotency key used by the eventual SwiftData repository to upsert the
/// StrengthWorkout/TrainingResponse pair.
struct WristTrainingObservationDraft: Equatable, Sendable {
    let recordID: UUID
    let idempotencyKey: String
    let title: String
    let startedAt: Date
    let endedAt: Date
    let durationMinutes: Int
    let activeCalories: Double
    let averageHeartRate: Double?
    let completedSets: Int
    let healthDayIdentifier: String
    let source: String
    let notes: String
}

struct WristTrainingObservationAudit: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case mapped
        case duplicate
        case rejected
    }

    let observationID: UUID
    let idempotencyKey: String
    let outcome: Outcome
    let reason: String
    let recordedAt: Date

    static func mapped(_ observation: WristTrainingObservation, at date: Date = Date()) -> Self {
        Self(
            observationID: observation.id,
            idempotencyKey: observation.idempotencyKey,
            outcome: .mapped,
            reason: "readyForPersistence",
            recordedAt: date
        )
    }

    static func duplicate(_ observation: WristTrainingObservation, at date: Date = Date()) -> Self {
        Self(
            observationID: observation.id,
            idempotencyKey: observation.idempotencyKey,
            outcome: .duplicate,
            reason: "existingRecordReused",
            recordedAt: date
        )
    }

    static func rejected(
        _ observation: WristTrainingObservation,
        reason: String,
        at date: Date = Date()
    ) -> Self {
        Self(
            observationID: observation.id,
            idempotencyKey: observation.idempotencyKey,
            outcome: .rejected,
            reason: reason,
            recordedAt: date
        )
    }
}

enum WristTrainingObservationMapping: Equatable, Sendable {
    case ready(WristTrainingObservationDraft)
    case rejected(WristTrainingObservationAudit)
}

/// Pure, replayable Watch observation adapter. It intentionally has no
/// HealthKit, SwiftData, or UserDefaults dependency; an iPhone repository can
/// persist the resulting draft and acknowledge its UUID atomically.
enum WristTrainingObservationAdapter {
    static let maxDuration: TimeInterval = 24 * 60 * 60
    static let maxCompletedSets = 500

    static func map(
        _ observation: WristTrainingObservation,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> WristTrainingObservationMapping {
        guard WristTrainingObservation.isSupported(schemaVersion: observation.schemaVersion) else {
            return .rejected(.rejected(observation, reason: "unsupportedSchemaVersion", at: now))
        }
        guard !observation.workoutKind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .rejected(.rejected(observation, reason: "emptyWorkoutKind", at: now))
        }
        guard observation.endedAt > observation.startedAt,
              observation.endedAt.timeIntervalSince(observation.startedAt) <= maxDuration else {
            return .rejected(.rejected(observation, reason: "invalidWorkoutInterval", at: now))
        }
        guard observation.activeCalories.isFinite, observation.activeCalories >= 0 else {
            return .rejected(.rejected(observation, reason: "invalidActiveCalories", at: now))
        }
        if let heartRate = observation.averageHeartRate,
           (!heartRate.isFinite || heartRate < 0 || heartRate > 300) {
            return .rejected(.rejected(observation, reason: "invalidAverageHeartRate", at: now))
        }
        guard (0...maxCompletedSets).contains(observation.completedSets) else {
            return .rejected(.rejected(observation, reason: "invalidCompletedSets", at: now))
        }
        guard !observation.healthDayIdentifier.isEmpty else {
            return .rejected(.rejected(observation, reason: "emptyHealthDayIdentifier", at: now))
        }

        // StrengthWorkoutRecord is the current response-bearing local model.
        // Non-strength Watch activities remain in the queue with an explicit
        // audit result until a future WorkoutEvent adapter owns that model.
        guard isStrengthKind(observation.workoutKind) else {
            return .rejected(.rejected(observation, reason: "unsupportedWorkoutKind", at: now))
        }

        let durationMinutes = max(
            1,
            Int((observation.endedAt.timeIntervalSince(observation.startedAt) / 60).rounded())
        )
        let title = "Apple Watch · \(observation.workoutKind.trimmingCharacters(in: .whitespacesAndNewlines))"
        let idempotencyKey = observation.idempotencyKey
        let healthDay = observation.healthDayIdentifier.isEmpty
            ? WristSnapshotContract.healthDayIdentifier(for: observation.startedAt, calendar: calendar)
            : observation.healthDayIdentifier
        let notes = "Apple Watch observation \(idempotencyKey) · schema v\(observation.schemaVersion) · health day \(healthDay)"
        return .ready(WristTrainingObservationDraft(
            recordID: observation.id,
            idempotencyKey: idempotencyKey,
            title: title,
            startedAt: observation.startedAt,
            endedAt: observation.endedAt,
            durationMinutes: durationMinutes,
            activeCalories: observation.activeCalories,
            averageHeartRate: observation.averageHeartRate,
            completedSets: observation.completedSets,
            healthDayIdentifier: healthDay,
            source: observation.source.isEmpty ? "appleWatch" : observation.source,
            notes: notes
        ))
    }

    private static func isStrengthKind(_ rawValue: String) -> Bool {
        let normalized = rawValue.lowercased()
        return normalized.contains("strength") || rawValue.contains("力量")
    }
}

private extension WristTrainingObservation {
    var idempotencyKey: String {
        "watch-training-\(id.uuidString.lowercased())"
    }
}

struct WristStrengthSet: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var repetitions: Int
    var weightKilograms: Double
    var isCompleted: Bool
}

struct WristStrengthExercise: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var sets: [WristStrengthSet]
}

struct WristActiveWorkout: Codable, Equatable, Sendable {
    var draftID: UUID
    var title: String
    var startedAt: Date
    var updatedAt: Date
    var exercises: [WristStrengthExercise]
}

struct WristStrengthSetEdit: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var draftID: UUID
    var exerciseID: UUID
    var setID: UUID
    var repetitions: Int
    var weightKilograms: Double
    var isCompleted: Bool
}

extension Notification.Name {
    static let wristStrengthSetEditQueued = Notification.Name("vela.wrist.strength-set-edit-queued")
}

final class WristSnapshotBridge: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WristSnapshotBridge()

    private let cacheKey = "vela.wrist.latest-snapshot"
    private let activeWorkoutCacheKey = "vela.wrist.active-workout"
    private let pendingEditCacheKey = "vela.wrist.pending-strength-edits"
    private let pendingTrainingObservationCacheKey = "vela.wrist.pending-training-observations"
    private let trainingObservationAuditCacheKey = "vela.wrist.training-observation-audit"
    private let encoder = JSONEncoder()
    private let lock = NSLock()
    private var latestPayload: Data?
    private var latestActiveWorkoutPayload: Data?
    private var pendingContextUpdate = false

    /// 会话激活后补发未送达的上下文更新。
    func retryPendingContextUpdateIfNeeded() {
        lock.lock()
        let pending = pendingContextUpdate
        lock.unlock()
        guard pending else { return }
        lock.lock()
        pendingContextUpdate = false
        lock.unlock()
        updateCombinedApplicationContext()
    }

    override private init() {
        super.init()
        latestPayload = UserDefaults.standard.data(forKey: cacheKey)
        latestActiveWorkoutPayload = UserDefaults.standard.data(forKey: activeWorkoutCacheKey)
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        if WCSession.default.activationState != .activated {
            WCSession.default.activate()
        }
    }

    func publish(
        dashboard: DashboardSummary,
        command: TodayCommandState,
        plan: TrainingPlanRecord?,
        scheduledDay: TrainingDay?
    ) {
        let completed = plan?.days.filter(\.isCompleted).count ?? 0
        let total = plan?.days.count ?? 0
        let generatedAt = Date()
        let snapshot = WristSnapshot(
            generatedAt: generatedAt,
            bodyStateTitle: command.bodyStateTitle,
            summary: command.summary,
            decision: command.readinessDecision.displayTitle,
            decisionConfidence: command.readinessDecision.confidence,
            recoveryScore: dashboard.recovery.roundedScore,
            sleepScore: dashboard.sleepScore.roundedScore,
            strainScore: dashboard.strain.roundedScore,
            stressScore: dashboard.stress.roundedScore,
            energyScore: dashboard.energy.roundedScore,
            hrvMilliseconds: dashboard.recoveryMetrics.hrvMilliseconds.map { Int($0.rounded()) },
            restingHeartRate: dashboard.recoveryMetrics.restingHeartRate.map { Int($0.rounded()) },
            primaryAction: command.actions.first(where: \.isPrimary)?.title ?? "打开 iPhone 查看今日建议",
            planTitle: plan?.title,
            sessionTitle: scheduledDay?.title,
            sessionDetail: scheduledDay.map { "\($0.durationMinutes) 分钟 · \(Self.intensityLabel($0.intensity))" },
            planProgress: total > 0 ? "\(completed)/\(total) 已完成" : nil,
            healthDayIdentifier: WristSnapshotContract.healthDayIdentifier(for: generatedAt)
        )
        guard let data = try? encoder.encode(snapshot) else { return }

        lock.lock()
        latestPayload = data
        lock.unlock()
        UserDefaults.standard.set(data, forKey: cacheKey)

        // Automatically sync iOS widgets with ground truth data
        VelaWidgetDataProvider.shared.updateSnapshot(from: snapshot)

        updateCombinedApplicationContext()
    }

    func publishActiveWorkout(_ draft: ActiveWorkoutDraftRecord) {
        let payload = WristActiveWorkout(
            draftID: draft.id,
            title: draft.title,
            startedAt: draft.startedAt,
            updatedAt: draft.lastUpdated,
            exercises: draft.exercises.map { exercise in
                WristStrengthExercise(
                    id: exercise.id,
                    name: exercise.name,
                    sets: exercise.sets.map {
                        WristStrengthSet(
                            id: $0.id,
                            repetitions: $0.repetitions,
                            weightKilograms: $0.weightKilograms,
                            isCompleted: $0.isCompleted == true
                        )
                    }
                )
            }
        )
        guard let data = try? encoder.encode(payload) else { return }
        lock.lock()
        latestActiveWorkoutPayload = data
        lock.unlock()
        UserDefaults.standard.set(data, forKey: activeWorkoutCacheKey)
        updateCombinedApplicationContext()
    }

    func clearActiveWorkout() {
        lock.lock()
        latestActiveWorkoutPayload = nil
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: activeWorkoutCacheKey)
        updateCombinedApplicationContext()
    }

    func drainPendingStrengthSetEdits() -> [WristStrengthSetEdit] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = UserDefaults.standard.data(forKey: pendingEditCacheKey),
              let edits = try? JSONDecoder().decode([WristStrengthSetEdit].self, from: data) else {
            return []
        }
        UserDefaults.standard.removeObject(forKey: pendingEditCacheKey)
        return edits
    }

    /// Drains watch-only training observations for the next local training
    /// response adapter. The queue lives in UserDefaults rather than SwiftData
    /// so receiving a workout never depends on the iPhone dashboard or schema.
    func drainPendingTrainingObservations() -> [WristTrainingObservation] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = UserDefaults.standard.data(forKey: pendingTrainingObservationCacheKey),
              let observations = try? JSONDecoder().decode([WristTrainingObservation].self, from: data) else {
            return []
        }
        return observations
    }

    /// Acknowledges only observations that the receiving adapter completed (or
    /// recognized as an existing idempotent record). Rejected/deferred payloads
    /// remain queued for a later retry while their audit outcome stays visible.
    func acknowledgePendingTrainingObservations(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let data = UserDefaults.standard.data(forKey: pendingTrainingObservationCacheKey),
              let observations = try? JSONDecoder().decode([WristTrainingObservation].self, from: data) else {
            return
        }
        let remaining = observations.filter { !ids.contains($0.id) }
        if remaining.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingTrainingObservationCacheKey)
        } else if let encoded = try? encoder.encode(remaining) {
            UserDefaults.standard.set(encoded, forKey: pendingTrainingObservationCacheKey)
        }
    }

    func trainingObservationAudit() -> [WristTrainingObservationAudit] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = UserDefaults.standard.data(forKey: trainingObservationAuditCacheKey) else {
            return []
        }
        return (try? JSONDecoder().decode([WristTrainingObservationAudit].self, from: data)) ?? []
    }

    /// Persists an adapter outcome outside SwiftData. This keeps rejected
    /// payloads inspectable without making the observation envelope part of the
    /// app's migration graph.
    func recordTrainingObservationAudit(_ audit: WristTrainingObservationAudit) {
        lock.lock()
        defer { lock.unlock() }
        var audits: [WristTrainingObservationAudit] = []
        if let data = UserDefaults.standard.data(forKey: trainingObservationAuditCacheKey) {
            audits = (try? JSONDecoder().decode([WristTrainingObservationAudit].self, from: data)) ?? []
        }
        audits.append(audit)
        if let data = try? encoder.encode(Array(audits.suffix(200))) {
            UserDefaults.standard.set(data, forKey: trainingObservationAuditCacheKey)
        }
    }

    /// Test/bridge seam for queueing a typed observation without requiring a
    /// live WCSession. Production Watch messages still use the delegate paths.
    func enqueueTrainingObservation(_ observation: WristTrainingObservation) {
        enqueue(observation)
    }

    func clearCachedSnapshot() {
        lock.lock()
        latestPayload = nil
        latestActiveWorkoutPayload = nil
        lock.unlock()
        // 「清除全部本地数据」必须连同 watch 缓存与 widget 缓存一起清。
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: activeWorkoutCacheKey)
        UserDefaults.standard.removeObject(forKey: pendingEditCacheKey)
        UserDefaults.standard.removeObject(forKey: pendingTrainingObservationCacheKey)
        UserDefaults.standard.removeObject(forKey: trainingObservationAuditCacheKey)
        VelaWidgetDataProvider.shared.clearSnapshot()
        updateCombinedApplicationContext()
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // 激活前 publish 的上下文会被静默丢弃；激活成功后补发一次。
        if activationState == .activated {
            DispatchQueue.main.async {
                WristSnapshotBridge.shared.retryPendingContextUpdateIfNeeded()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if let data = message["strengthSetEdit"] as? Data,
           let edit = try? JSONDecoder().decode(WristStrengthSetEdit.self, from: data) {
            enqueue(edit)
            replyHandler(["status": "queued", "mutationID": edit.id.uuidString])
            return
        }
        if let data = message["trainingObservation"] as? Data,
           let observation = try? JSONDecoder().decode(WristTrainingObservation.self, from: data) {
            enqueue(observation)
            replyHandler(["status": "queued", "observationID": observation.id.uuidString])
            return
        }
        guard message["command"] as? String == "latestSnapshot" else {
            replyHandler(["status": "unsupported"])
            return
        }
        lock.lock()
        let payload = latestPayload
        let activeWorkoutPayload = latestActiveWorkoutPayload
        lock.unlock()
        if payload != nil || activeWorkoutPayload != nil {
            var response: [String: Any] = [:]
            if let payload { response["snapshot"] = payload }
            if let activeWorkoutPayload { response["activeWorkout"] = activeWorkoutPayload }
            replyHandler(response)
        } else {
            replyHandler(["status": "pending"])
        }
    }

    /// watch 端以 replyHandler=nil 发送消息时走此变体（此前未实现导致
    /// strengthSetEdit 在手机可达时被静默丢弃）。
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        if let data = message["strengthSetEdit"] as? Data,
           let edit = try? JSONDecoder().decode(WristStrengthSetEdit.self, from: data) {
            enqueue(edit)
            return
        }
        if let data = message["trainingObservation"] as? Data,
           let observation = try? JSONDecoder().decode(WristTrainingObservation.self, from: data) {
            enqueue(observation)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo["strengthSetEdit"] as? Data,
           let edit = try? JSONDecoder().decode(WristStrengthSetEdit.self, from: data) {
            enqueue(edit)
        }
        if let data = userInfo["trainingObservation"] as? Data,
           let observation = try? JSONDecoder().decode(WristTrainingObservation.self, from: data) {
            enqueue(observation)
        }
    }

    private func enqueue(_ edit: WristStrengthSetEdit) {
        lock.lock()
        var edits: [WristStrengthSetEdit] = []
        if let data = UserDefaults.standard.data(forKey: pendingEditCacheKey) {
            edits = (try? JSONDecoder().decode([WristStrengthSetEdit].self, from: data)) ?? []
        }
        if !edits.contains(where: { $0.id == edit.id }) {
            edits.append(edit)
            if let data = try? encoder.encode(Array(edits.suffix(100))) {
                UserDefaults.standard.set(data, forKey: pendingEditCacheKey)
            }
        }
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .wristStrengthSetEditQueued, object: nil)
        }
    }

    private func enqueue(_ observation: WristTrainingObservation) {
        lock.lock()
        var observations: [WristTrainingObservation] = []
        if let data = UserDefaults.standard.data(forKey: pendingTrainingObservationCacheKey) {
            observations = (try? JSONDecoder().decode([WristTrainingObservation].self, from: data)) ?? []
        }
        if !observations.contains(where: { $0.id == observation.id }),
           let data = try? encoder.encode(Array((observations + [observation]).suffix(100))) {
            UserDefaults.standard.set(data, forKey: pendingTrainingObservationCacheKey)
        }
        lock.unlock()
    }

    private func updateCombinedApplicationContext() {
        guard WCSession.isSupported() else { return }
        guard WCSession.default.activationState == .activated else {
            pendingContextUpdate = true
            return
        }
        lock.lock()
        let snapshot = latestPayload
        let activeWorkout = latestActiveWorkoutPayload
        lock.unlock()
        var context: [String: Any] = [:]
        if let snapshot { context["snapshot"] = snapshot } else { context["clearSnapshot"] = true }
        if let activeWorkout { context["activeWorkout"] = activeWorkout } else { context["clearActiveWorkout"] = true }
        try? WCSession.default.updateApplicationContext(context)
        pendingContextUpdate = false
    }

    private static func intensityLabel(_ intensity: String) -> String {
        switch intensity.lowercased() {
        case "low": return "低强度"
        case "high": return "高强度"
        default: return "中强度"
        }
    }
}
