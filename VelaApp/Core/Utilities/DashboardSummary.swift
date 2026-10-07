import Foundation
import SwiftData

struct DashboardSummary: Hashable, Sendable {
    var date: Date
    var sleepSummary: SleepSummary
    var sleepScore: MetricResult
    var recovery: MetricResult
    var recoveryMetrics: RecoveryMetricSummary
    var recoveryBaseline: RecoveryMetricSummary
    var strain: MetricResult
    var stress: MetricResult
    var energy: MetricResult
    var healthAge: HealthAgeTrendResult
    var bodyMetrics: BodyMetricsSummary
    var extendedMetrics: ExtendedHealthMetrics
    /// The exact profile inputs used for this dashboard computation. AI must
    /// consume this value instead of re-reading today's mutable preferences.
    var scoringContext: ScoringContext? = nil
    var workouts: [WorkoutSummary]
    var dailyInsight: String
    var source: DataSource
    /// 三年长线基准报告（回填后可用）；评分修正、长线证据与 wiki 同源。
    var longTermBaselines: LongTermBaselineReport? = nil
    /// 联通专项批次 2：身体模型状态（主流程一句话洞察/证据页共用；纯内存聚合体）。
    var bodyModelState: BodyModelState? = nil
    /// 规范产品层：统一身体简报与多尺度趋势发现
    var personalHealthBrief: PersonalHealthBrief? = nil
    var healthTrends: [HealthTrendFinding] = []
    
    private var _trainingDecision: TrainingDecision?
    var trainingDecision: TrainingDecision {
        get {
            guard let _trainingDecision else {
                return TrainingDecision.compatibilityView(
                    of: DailyTrainingDecision(
                        decision: .rest,
                        volumeMultiplier: 0.5,
                        intensityCap: 50,
                        reasons: ["等待综合身体状态分析"],
                        userFacingSummary: "等待数据同步完成后生成",
                        confidence: 0.0,
                        source: "DashboardSummary.fallback",
                        safetyNotice: "仅提供一般健康与训练建议，不构成医疗诊断。"
                    ),
                    bodyState: bodyState
                )
            }
            return _trainingDecision
        }
        set {
            _trainingDecision = newValue
        }
    }

    private var _bodyState: BodyState?
    var bodyState: BodyState {
        get {
            _bodyState ?? BodyState(
                date: date,
                readiness: .unknown,
                recovery: MetricResult(
                    name: "Recovery", value: nil, band: .low, confidence: .low,
                    components: [:], componentWeights: [:], reasons: ["No data"],
                    missingInputs: ["hrv", "rhr", "sleep"],
                    dataWindow: DateInterval(start: date, end: date),
                    source: .derived, algorithmVersion: "1.0", lastUpdated: date
                ),
                sleep: MetricResult(
                    name: "Sleep", value: nil, band: .low, confidence: .low,
                    components: [:], componentWeights: [:], reasons: ["No data"],
                    missingInputs: ["duration"],
                    dataWindow: DateInterval(start: date, end: date),
                    source: .derived, algorithmVersion: "1.0", lastUpdated: date
                ),
                strain: MetricResult(
                    name: "Strain", value: nil, band: .low, confidence: .low,
                    components: [:], componentWeights: [:], reasons: ["No data"],
                    missingInputs: ["daily_load"],
                    dataWindow: DateInterval(start: date, end: date),
                    source: .derived, algorithmVersion: "1.0", lastUpdated: date
                ),
                energy: MetricResult(
                    name: "Energy Bank", value: nil, band: .low, confidence: .low,
                    components: [:], componentWeights: [:], reasons: ["No data"],
                    missingInputs: ["recovery", "sleep"],
                    dataWindow: DateInterval(start: date, end: date),
                    source: .derived, algorithmVersion: "1.0", lastUpdated: date
                ),
                stress: MetricResult(
                    name: "Stress", value: nil, band: .low, confidence: .low,
                    components: [:], componentWeights: [:], reasons: ["No data"],
                    missingInputs: ["hrv", "rhr"],
                    dataWindow: DateInterval(start: date, end: date),
                    source: .derived, algorithmVersion: "1.0", lastUpdated: date
                ),
                localFatigue: [:],
                drivers: [],
                confidence: .unavailable,
                freshness: .stale,
                source: "DashboardSummary.fallback",
                activeStatus: "active",
                hash: ""
            )
        }
        set { _bodyState = newValue }
    }

    init(
        date: Date,
        sleepSummary: SleepSummary,
        sleepScore: MetricResult,
        recovery: MetricResult,
        recoveryMetrics: RecoveryMetricSummary,
        recoveryBaseline: RecoveryMetricSummary,
        strain: MetricResult,
        stress: MetricResult,
        energy: MetricResult,
        healthAge: HealthAgeTrendResult,
        bodyMetrics: BodyMetricsSummary,
        extendedMetrics: ExtendedHealthMetrics,
        workouts: [WorkoutSummary],
        dailyInsight: String,
        source: DataSource,
        longTermBaselines: LongTermBaselineReport? = nil,
        bodyModelState: BodyModelState? = nil,
        scoringContext: ScoringContext? = nil
    ) {
        self.date = date
        self.sleepSummary = sleepSummary
        self.sleepScore = sleepScore
        self.recovery = recovery
        self.recoveryMetrics = recoveryMetrics
        self.recoveryBaseline = recoveryBaseline
        self.strain = strain
        self.stress = stress
        self.energy = energy
        self.healthAge = healthAge
        self.bodyMetrics = bodyMetrics
        self.extendedMetrics = extendedMetrics
        self.scoringContext = scoringContext
        self.workouts = workouts
        self.dailyInsight = dailyInsight
        self.source = source
        self.longTermBaselines = longTermBaselines
        self.bodyModelState = bodyModelState
        self._trainingDecision = nil
        self._bodyState = nil
    }

    enum DataSource: String, Hashable {
        case healthKit = "HealthKit"
        case cache = "Cached HealthKit"
        case empty = "Empty"
        case preview = "Preview"
    }

    #if DEBUG
    static func preview(date: Date = Date()) -> DashboardSummary {
        PreviewDataFactory.makeDashboard(date: date)
    }
    #else
    static func preview(date: Date = Date()) -> DashboardSummary {
        empty(date: date)
    }
    #endif

    static func empty(date: Date = Date()) -> DashboardSummary {
        func emptyMetric(name: String, reason: String) -> MetricResult {
            MetricResult(
                name: name,
                value: nil,
                band: .low,
                confidence: .low,
                components: [:],
                componentWeights: [:],
                reasons: [reason],
                missingInputs: ["healthData"],
                dataWindow: DateInterval(start: date, duration: 86400),
                source: .derived,
                algorithmVersion: "1.0.0",
                lastUpdated: date
            )
        }

        return DashboardSummary(
            date: date,
            sleepSummary: SleepSummary(
                date: date,
                totalSleepMinutes: 0,
                bedtime: nil,
                wakeTime: nil,
                stageMinutes: [:],
                segments: [],
                sleepScore: nil
            ),
            sleepScore: MetricResult(
                name: "Sleep Score",
                value: nil,
                band: .low,
                confidence: .low,
                components: [:],
                componentWeights: [:],
                reasons: ["Sleep data unavailable."],
                missingInputs: ["sleepSummary"],
                dataWindow: DateInterval(start: date, duration: 86400),
                source: .derived,
                algorithmVersion: "1.0.0",
                lastUpdated: date
            ),
            recovery: MetricResult(
                name: "Recovery Score",
                value: nil,
                band: .low,
                confidence: .low,
                components: [:],
                componentWeights: [:],
                reasons: ["Recovery data unavailable."],
                missingInputs: ["recoveryMetrics"],
                dataWindow: DateInterval(start: date, duration: 86400),
                source: .derived,
                algorithmVersion: "1.0.0",
                lastUpdated: date
            ),
            recoveryMetrics: RecoveryMetricSummary(
                hrvMilliseconds: nil,
                restingHeartRate: nil,
                sleepHeartRate: nil,
                respiratoryRate: nil
            ),
            recoveryBaseline: RecoveryMetricSummary(
                hrvMilliseconds: nil,
                restingHeartRate: nil,
                sleepHeartRate: nil,
                respiratoryRate: nil
            ),
            strain: emptyMetric(name: "Strain Score", reason: "Strain data unavailable."),
            stress: emptyMetric(name: "Physiological Stress Index", reason: "Stress data unavailable."),
            energy: emptyMetric(name: "Energy Bank", reason: "Energy data unavailable."),
            healthAge: HealthAgeTrendEngine().calculate(from: HealthAgeTrendInput(factors: [])),
            bodyMetrics: BodyMetricsSummary(
                vo2Max: nil,
                weightKilograms: nil,
                bodyFatPercentage: nil,
                leanBodyMassKilograms: nil
            ),
            extendedMetrics: ExtendedHealthMetrics.empty,
            workouts: [],
            dailyInsight: "",
            source: .empty
        )
    }
}

private extension ExtendedHealthMetrics {
    static let empty = ExtendedHealthMetrics(
        age: nil, biologicalSex: nil, heightCm: nil, bmi: nil,
        walkingHeartRateAvg: nil, oxygenSaturation: nil,
        bloodPressureSystolic: nil, bloodPressureDiastolic: nil,
        bloodGlucose: nil,
        walkingSpeed: nil, walkingStepLength: nil, walkingAsymmetry: nil,
        walkingDoubleSupport: nil, walkingSteadiness: nil,
        stairAscentSpeed: nil, stairDescentSpeed: nil, sixMinuteWalkDistance: nil,
        exerciseMinutes: nil, standMinutes: nil, flightsClimbed: nil,
        distanceKm: nil, cyclingDistanceKm: nil,
        environmentalNoisedB: nil, headphoneNoisedB: nil, timeInDaylight: nil,
        bodyTemperature: nil,
        waterMl: nil, caffeineMg: nil, dietaryEnergyKcal: nil,
        dietaryProteinG: nil, dietaryCarbsG: nil, dietaryFatG: nil,
        mindfulMinutes: nil, sleepBreathingDisturbances: nil
    )
}
