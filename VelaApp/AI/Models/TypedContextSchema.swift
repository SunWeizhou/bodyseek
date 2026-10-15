import Foundation
import BodySeekDomain

// MARK: - Network outbound consent

/// Data categories that may appear in an AI request.  Keep this list aligned
/// with the user-facing Coach consent sheet; a missing category must be
/// treated as denied (never as an implicit "all" grant).
enum AgentOutboundDataCategory: String, CaseIterable, Codable, Sendable {
    case health
    case training
    case nutrition
    case journal
    case wiki
    case reports
    case conversationHistory
    case webSearch
    case files
}

/// A snapshot of the two independent gates required by automated agents:
/// the feature-level background consent and per-category outbound consent.
/// This type intentionally copies booleans instead of retaining
/// `CoachOutboundDataPolicy`, so background payload preparation remains a
/// value type that is safe to pass across task boundaries.
struct AgentOutboundConsentPolicy: Equatable, Sendable {
    var backgroundNetworkAIConsent: Bool
    var health: Bool
    var training: Bool
    var nutrition: Bool
    var journal: Bool
    var wiki: Bool
    var reports: Bool
    var conversationHistory: Bool
    var webSearch: Bool
    var files: Bool

    init(
        backgroundNetworkAIConsent: Bool,
        health: Bool,
        training: Bool,
        nutrition: Bool,
        journal: Bool,
        wiki: Bool,
        reports: Bool,
        conversationHistory: Bool,
        webSearch: Bool,
        files: Bool
    ) {
        self.backgroundNetworkAIConsent = backgroundNetworkAIConsent
        self.health = health
        self.training = training
        self.nutrition = nutrition
        self.journal = journal
        self.wiki = wiki
        self.reports = reports
        self.conversationHistory = conversationHistory
        self.webSearch = webSearch
        self.files = files
    }

    init(
        backgroundNetworkAIConsent: Bool,
        categoryPolicy: CoachOutboundDataPolicy
    ) {
        self.init(
            backgroundNetworkAIConsent: backgroundNetworkAIConsent,
            health: categoryPolicy.health,
            training: categoryPolicy.training,
            nutrition: categoryPolicy.nutrition,
            journal: categoryPolicy.journal,
            wiki: categoryPolicy.wiki,
            reports: categoryPolicy.reports,
            conversationHistory: categoryPolicy.conversationHistory,
            webSearch: categoryPolicy.webSearch,
            files: categoryPolicy.files
        )
    }

    /// Resolve the policy once at an outbound boundary.  All automated
    /// schedulers should capture this value before building their payload.
    static var current: AgentOutboundConsentPolicy {
        AgentOutboundConsentPolicy(
            backgroundNetworkAIConsent: AutoAgentConfig.shared.backgroundNetworkAIConsent,
            categoryPolicy: CoachOutboundDataPolicy.stored
        )
    }

    /// No network request is allowed when the feature gate or every category
    /// gate is closed.  This is deliberately stricter than
    /// `hasExplicitConsent`, which only records that the sheet was reviewed.
    var canSendNetworkAI: Bool {
        backgroundNetworkAIConsent && hasAnyCategoryConsent
    }

    var hasAnyCategoryConsent: Bool {
        health || training || nutrition || journal || wiki || reports
            || conversationHistory || webSearch || files
    }

    func allows(_ category: AgentOutboundDataCategory) -> Bool {
        switch category {
        case .health: health
        case .training: training
        case .nutrition: nutrition
        case .journal: journal
        case .wiki: wiki
        case .reports: reports
        case .conversationHistory: conversationHistory
        case .webSearch: webSearch
        case .files: files
        }
    }
}

extension CoachOutboundDataPolicy {
    /// A consent sheet can be confirmed with every toggle off.  Callers that
    /// are about to make an automated network request must require at least
    /// one explicit category in addition to the consent version.
    var hasAnyCategoryConsent: Bool {
        health || training || nutrition || journal || wiki || reports
            || conversationHistory || webSearch || files
    }
}

// MARK: - Typed Metric Value

public typealias DataFreshness = BodySeekDomain.DataFreshness

public enum DataConfidence: String, Codable, Hashable, CaseIterable, Sendable {
    case high
    case medium
    case low
    case unavailable
}

public enum HealthDataSource: String, Codable, Hashable, CaseIterable, Sendable {
    case healthKit
    case userProvided
    case aiEstimated
    case wikiProfile
    case biomarkerLab
    case computed
}

struct BaselineComparison: Codable, Hashable, Sendable {
    var baselineValue: Double?
    var delta: Double?
    var deltaPercent: Double?
    var zScore: Double?
    var windowDays: Int?
}

struct MetricValue<T: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    var value: T?
    var unit: String?
    var source: HealthDataSource
    var measuredAt: Date?
    var freshness: DataFreshness
    var confidence: DataConfidence
    var baseline: BaselineComparison?
    var note: String?

    static func missing(unit: String? = nil, note: String? = nil) -> MetricValue<T> {
        MetricValue(value: nil, unit: unit, source: .healthKit, freshness: .missing, confidence: .unavailable, note: note)
    }

    static func live(
        _ value: T,
        unit: String? = nil,
        source: HealthDataSource = .healthKit,
        measuredAt: Date? = nil,
        freshness: DataFreshness = .live,
        confidence: DataConfidence = .high,
        baseline: BaselineComparison? = nil
    ) -> MetricValue<T> {
        MetricValue(
            value: value,
            unit: unit,
            source: source,
            measuredAt: measuredAt,
            freshness: freshness,
            confidence: confidence,
            baseline: baseline
        )
    }
}

// MARK: - Typed Domain Contexts

struct RecoveryContext: Codable, Hashable, Sendable {
    var score: MetricValue<Double>
    var band: String
    var hrv: MetricValue<Double>
    /// A2：RMSSD 派生指标（缺失时引擎回退 SDNN，但此处如实标注 missing）。
    var hrvRmssd: MetricValue<Double>?
    var restingHeartRate: MetricValue<Double>
    var respiratoryRate: MetricValue<Double>
    var topReason: String?
    /// 联通专项批次 3：v2 上下文补齐 z-score（此前 v1 有、v2 反而丢）。
    var hrvZScore: MetricValue<Double>
    var rhrZScore: MetricValue<Double>
}

struct SleepContext: Codable, Hashable, Sendable {
    var score: MetricValue<Double>
    var band: String
    var totalMinutes: MetricValue<Int>
    var efficiency: MetricValue<Double>
    var remPercent: MetricValue<Double>
    var deepPercent: MetricValue<Double>
    var coreMinutes: MetricValue<Int>
    var remMinutes: MetricValue<Int>
    var deepMinutes: MetricValue<Int>
    var awakeMinutes: MetricValue<Int>
    var bedtime: Date?
    var wakeTime: Date?
    var topReason: String?
}

struct StrainContext: Codable, Hashable, Sendable {
    var score: MetricValue<Double>
    var band: String
    var targetStatus: String
    var recommendedRangeLower: Int
    var recommendedRangeUpper: Int
    var steps: MetricValue<Int>
    var activeEnergyKcal: MetricValue<Int>
    var exerciseMinutes: MetricValue<Int>
}

struct StressContext: Codable, Hashable, Sendable {
    var stressIndex: MetricValue<Double>
    var band: String
    var confidence: DataConfidence
    var proxyNote: String
    /// 联通专项批次 3：压力六因子（此前 v2 只有聚合值，agent 无法解释压力来源）。
    var rhrStress: MetricValue<Double>
    var hrvStress: MetricValue<Double>
    var respStress: MetricValue<Double>
    var tempStress: MetricValue<Double>
    var sleepDebtStress: MetricValue<Double>
    var loadStress: MetricValue<Double>
}

struct EnergyBankContext: Codable, Hashable, Sendable {
    var morningEnergy: MetricValue<Double>
    var currentEnergy: MetricValue<Double>
    var status: String
    var chargeEfficiency: MetricValue<Double>
    var atl7Day: MetricValue<Double>
    var ctl42Day: MetricValue<Double>
    var tsbFreshness: MetricValue<Double>
    /// 联通专项批次 3：v2 补齐 ACWR（此前 v1 有、v2 丢）。
    var acwrRatio: MetricValue<Double>
}

struct TrainingContext: Codable, Hashable, Sendable {
    var activePlan: ActivePlanSummary?
    var workoutCount: Int
    var workoutTypes: [String]
    var totalEnergyKcal: Double
    var totalDurationMin: Int
    var workoutListJSON: String
}

struct ActivePlanSummary: Codable, Hashable, Sendable {
    var title: String
    var goalDescription: String
    var weeksCount: Int
    var completedDays: Int
    var totalDays: Int
}

struct NutritionContext: Codable, Hashable, Sendable {
    var recentEntries: [String]
    var recentCount: Int
    var totalCalories: Int
    var totalProtein: Int
    var totalCarbs: Int
    var totalFat: Int
    var totalFiber: Int
}

struct ExtendedMetricsContext: Codable, Hashable, Sendable {
    var age: Int?
    var biologicalSex: String?
    var heightCm: MetricValue<Double>
    var weightKg: MetricValue<Double>
    var bmi: MetricValue<Double>
    var bodyFatPct: MetricValue<Double>
    var vo2Max: MetricValue<Double>
    var walkingSpeed: MetricValue<Double>
    var walkingAsymmetry: MetricValue<Double>
    var doubleSupportPct: MetricValue<Double>
    var spo2: MetricValue<Double>
    var bloodPressureSystolic: MetricValue<Int>?
    var bloodPressureDiastolic: MetricValue<Int>?
    var bloodGlucose: MetricValue<Double>?
    var waterMl: MetricValue<Int>?
    var caffeineMg: MetricValue<Int>?
    var envNoiseDb: MetricValue<Double>?
    var daylightMinutes: MetricValue<Int>?
    var wristTempC: MetricValue<Double>?
}

struct AgentBodyStateContext: Codable, Hashable, Sendable {
    var readiness: BodyReadiness
    var confidence: DataConfidence
    var freshness: DataFreshness
    var source: String
    var activeStatus: String
    var contextHash: String
    var drivers: [BodyStateDriver]
}

struct AgentTrainingDecisionContext: Codable, Hashable, Sendable {
    var readinessLevel: String
    var readinessGuidance: String
    var volumeMultiplier: Double
    var maxIntensity: String
    var recommendedTrainingType: String
    var reasons: String
    var confidence: DataConfidence
}

struct AgentDataCoverageContext: Codable, Hashable, Sendable {
    var availableSections: Int
    var totalSections: Int
    var missingSections: [String]
    var confidence: DataConfidence
}

// MARK: - Canonical Agent Fact Snapshot (v2)

struct AgentFactSnapshot: Codable, Hashable, Sendable {
    var schemaVersion: String
    var contextHash: String
    var generatedAt: Date
    var contextWindow: String

    var bodyState: AgentBodyStateContext
    var trainingDecision: AgentTrainingDecisionContext
    var dataCoverage: AgentDataCoverageContext

    var recovery: RecoveryContext
    var sleep: SleepContext
    var strain: StrainContext
    var stress: StressContext
    var energyBank: EnergyBankContext
    var training: TrainingContext
    var nutrition: NutritionContext
    var extendedMetrics: ExtendedMetricsContext
    var strengthTraining: StrengthTrainingContext?

    var recentTrends: [String: String]
    var weeklyTrends: [String: String]
    var journalEntries: [String]
    var historicalReports: [String]
    var userWiki: [String: String]
    /// A1：完整 Daily Operating Plan（主行动/支持行动/理由/置信度）。
    /// 此前 LLM 只拿到 trainingDecision 切片，无法讨论跨域计划的完整内容。
    var dailyOperatingPlan: [String: String]?
    /// 规范产品层：统一身体简报与多尺度趋势发现，让 Agent 解释 UI 当前显示的同一份事实
    var personalHealthBrief: PersonalHealthBrief?
    var healthTrends: [HealthTrendFinding]?
}

extension AgentFactSnapshot {
    /// Returns a copy safe to place in a network request.  Builders may still
    /// assemble a complete local snapshot for deterministic calculations, but
    /// this final boundary guarantees that a future caller cannot accidentally
    /// re-introduce a denied category by forgetting one input-side guard.
    func redacted(for policy: AgentOutboundConsentPolicy) -> AgentFactSnapshot {
        var redacted = self
        if !policy.health {
            redacted.redactHealth()
        }
        if !policy.training {
            redacted.training = TrainingContext(
                activePlan: nil,
                workoutCount: 0,
                workoutTypes: [],
                totalEnergyKcal: 0,
                totalDurationMin: 0,
                workoutListJSON: "[]"
            )
            redacted.strengthTraining = nil
        }
        if !policy.health || !policy.training {
            // Readiness, volume and intensity are derived from health signals
            // as well as training history.  Keep them out unless both source
            // categories are explicitly allowed.
            redacted.trainingDecision = AgentTrainingDecisionContext(
                readinessLevel: "unavailable",
                readinessGuidance: "Health and training data are not both shared.",
                volumeMultiplier: 0,
                maxIntensity: "unavailable",
                recommendedTrainingType: "unavailable",
                reasons: "",
                confidence: .unavailable
            )
        }
        if !policy.nutrition {
            redacted.nutrition = NutritionContext(
                recentEntries: [],
                recentCount: 0,
                totalCalories: 0,
                totalProtein: 0,
                totalCarbs: 0,
                totalFat: 0,
                totalFiber: 0
            )
        }
        if !policy.journal {
            redacted.journalEntries = []
        }
        if !policy.wiki {
            redacted.userWiki = [:]
        }
        if !policy.reports {
            redacted.historicalReports = []
        }
        if !policy.health || !policy.training {
            // The daily operating plan is a health-derived training action;
            // do not preserve it when either source category is denied.
            redacted.dailyOperatingPlan = nil
        }

        // Body-state drivers are a compact aggregate but retain their source
        // category in the typed model.  Filter those source-specific details
        // even when the aggregate health category itself remains allowed.
        redacted.bodyState.drivers = redacted.bodyState.drivers.filter { driver in
            switch driver.kind {
            case .localFatigue, .trainingResponse, .activePlan, .recentActivity:
                return policy.training
            case .nutrition:
                return policy.nutrition
            case .journal:
                return policy.journal
            default:
                return true
            }
        }

        redacted.contextHash = Self.redactedContentHash(redacted)
        return redacted
    }

    private mutating func redactHealth() {
        func redact<T: Codable & Hashable & Sendable>(_ metric: inout MetricValue<T>) {
            metric = .missing(unit: metric.unit, note: "Omitted by outbound consent.")
        }

        redact(&recovery.score)
        redact(&recovery.hrv)
        if var rmssd = recovery.hrvRmssd { redact(&rmssd); recovery.hrvRmssd = rmssd }
        redact(&recovery.restingHeartRate)
        redact(&recovery.respiratoryRate)
        redact(&recovery.hrvZScore)
        redact(&recovery.rhrZScore)
        recovery.band = "unavailable"
        recovery.topReason = nil

        redact(&sleep.score)
        redact(&sleep.totalMinutes)
        redact(&sleep.efficiency)
        redact(&sleep.remPercent)
        redact(&sleep.deepPercent)
        redact(&sleep.coreMinutes)
        redact(&sleep.remMinutes)
        redact(&sleep.deepMinutes)
        redact(&sleep.awakeMinutes)
        sleep.bedtime = nil
        sleep.wakeTime = nil
        sleep.band = "unavailable"
        sleep.topReason = nil

        redact(&strain.score)
        redact(&strain.steps)
        redact(&strain.activeEnergyKcal)
        redact(&strain.exerciseMinutes)
        strain.band = "unavailable"
        strain.targetStatus = "unavailable"
        strain.recommendedRangeLower = 0
        strain.recommendedRangeUpper = 0

        redact(&stress.stressIndex)
        redact(&stress.rhrStress)
        redact(&stress.hrvStress)
        redact(&stress.respStress)
        redact(&stress.tempStress)
        redact(&stress.sleepDebtStress)
        redact(&stress.loadStress)
        stress.band = "unavailable"
        stress.confidence = .unavailable

        redact(&energyBank.morningEnergy)
        redact(&energyBank.currentEnergy)
        redact(&energyBank.chargeEfficiency)
        redact(&energyBank.atl7Day)
        redact(&energyBank.ctl42Day)
        redact(&energyBank.tsbFreshness)
        redact(&energyBank.acwrRatio)
        energyBank.status = "unavailable"

        redact(&extendedMetrics.heightCm)
        redact(&extendedMetrics.weightKg)
        redact(&extendedMetrics.bmi)
        redact(&extendedMetrics.bodyFatPct)
        redact(&extendedMetrics.vo2Max)
        redact(&extendedMetrics.walkingSpeed)
        redact(&extendedMetrics.walkingAsymmetry)
        redact(&extendedMetrics.doubleSupportPct)
        redact(&extendedMetrics.spo2)
        if var value = extendedMetrics.bloodPressureSystolic { redact(&value); extendedMetrics.bloodPressureSystolic = value }
        if var value = extendedMetrics.bloodPressureDiastolic { redact(&value); extendedMetrics.bloodPressureDiastolic = value }
        if var value = extendedMetrics.bloodGlucose { redact(&value); extendedMetrics.bloodGlucose = value }
        if var value = extendedMetrics.waterMl { redact(&value); extendedMetrics.waterMl = value }
        if var value = extendedMetrics.caffeineMg { redact(&value); extendedMetrics.caffeineMg = value }
        if var value = extendedMetrics.envNoiseDb { redact(&value); extendedMetrics.envNoiseDb = value }
        if var value = extendedMetrics.daylightMinutes { redact(&value); extendedMetrics.daylightMinutes = value }
        if var value = extendedMetrics.wristTempC { redact(&value); extendedMetrics.wristTempC = value }
        extendedMetrics.age = nil
        extendedMetrics.biologicalSex = nil

        bodyState = AgentBodyStateContext(
            readiness: .unknown,
            confidence: .unavailable,
            freshness: .missing,
            source: "redacted",
            activeStatus: "unknown",
            contextHash: "",
            drivers: []
        )
        dataCoverage = AgentDataCoverageContext(
            availableSections: 0,
            totalSections: 0,
            missingSections: ["health"],
            confidence: .unavailable
        )
        recentTrends = [:]
        weeklyTrends = [:]
        personalHealthBrief = nil
        healthTrends = nil
    }

    private static func redactedContentHash(_ snapshot: AgentFactSnapshot) -> String {
        var semantic = snapshot
        semantic.contextHash = ""
        semantic.generatedAt = Date(timeIntervalSince1970: 0)
        semantic.bodyState.contextHash = ""
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(semantic)) ?? Data("{}".utf8)
        return ContentHash.hash(String(data: data, encoding: .utf8) ?? "{}")
    }
}
