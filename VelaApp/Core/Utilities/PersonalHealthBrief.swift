import Foundation

// MARK: - Health Trend Enums

public enum HealthTrendHorizon: String, Codable, Hashable, CaseIterable, Sendable, Identifiable {
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case sixMonths = "6m"
    case threeYears = "3y"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sevenDays: return "7天"
        case .thirtyDays: return "30天"
        case .sixMonths: return "6个月"
        case .threeYears: return "3年"
        }
    }

    public var detailedTitle: String {
        switch self {
        case .sevenDays: return "最近 7 天"
        case .thirtyDays: return "最近 30 天"
        case .sixMonths: return "最近 6 个月"
        case .threeYears: return "三年轨迹"
        }
    }

    public var requiredSampleCount: Int {
        switch self {
        case .sevenDays: return 4
        case .thirtyDays: return 14
        case .sixMonths: return 60
        case .threeYears: return 60
        }
    }

    public var windowDays: Int {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .sixMonths: return 180
        case .threeYears: return 1095
        }
    }
}

public enum HealthTrendDirection: String, Codable, Hashable, Sendable {
    case improving = "improving"
    case declining = "declining"
    case stable = "stable"
    case elevated = "elevated"
    case suppressed = "suppressed"
    case insufficientData = "insufficientData"

    public var icon: String {
        switch self {
        case .improving: return "arrow.up.forward"
        case .declining: return "arrow.down.forward"
        case .stable: return "minus"
        case .elevated: return "arrow.up"
        case .suppressed: return "arrow.down"
        case .insufficientData: return "ellipsis"
        }
    }

    public var label: String {
        switch self {
        case .improving: return "改善"
        case .declining: return "下降"
        case .stable: return "平稳"
        case .elevated: return "偏高"
        case .suppressed: return "偏低"
        case .insufficientData: return "数据积累中"
        }
    }
}

public enum MetricPolarity: String, Codable, Hashable, Sendable {
    case higherIsBetter = "higherIsBetter"
    case lowerIsBetter = "lowerIsBetter"
    case contextual = "contextual"
}

public enum CoreHealthMetric: String, Codable, Hashable, CaseIterable, Sendable, Identifiable {
    case hrv = "hrv"
    case restingHeartRate = "rhr"
    case sleepDuration = "sleep"
    case sleepScore = "sleepScore"
    case recovery = "recovery"
    case strain = "strain"
    case stress = "stress"
    case energy = "energy"
    case respiratoryRate = "resp"
    case oxygenSaturation = "spo2"
    case bodyWeight = "weight"
    case bodyFat = "bodyFat"
    case steps = "steps"
    case activeCalories = "activeCalories"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hrv: return "心率变异性"
        case .restingHeartRate: return "静息心率"
        case .sleepDuration: return "睡眠时长"
        case .sleepScore: return "睡眠得分"
        case .recovery: return "恢复得分"
        case .strain: return "耗力负荷"
        case .stress: return "压力指数"
        case .energy: return "能量储备"
        case .respiratoryRate: return "呼吸率"
        case .oxygenSaturation: return "血氧饱和度"
        case .bodyWeight: return "体重"
        case .bodyFat: return "体脂率"
        case .steps: return "步数"
        case .activeCalories: return "活动消耗"
        }
    }

    public var shortTitle: String {
        switch self {
        case .hrv: return "HRV"
        case .restingHeartRate: return "静息心率"
        case .sleepDuration: return "睡眠时长"
        case .sleepScore: return "睡眠"
        case .recovery: return "恢复"
        case .strain: return "耗力"
        case .stress: return "压力"
        case .energy: return "能量"
        case .respiratoryRate: return "呼吸率"
        case .oxygenSaturation: return "血氧"
        case .bodyWeight: return "体重"
        case .bodyFat: return "体脂"
        case .steps: return "步数"
        case .activeCalories: return "消耗"
        }
    }

    public var unit: String {
        switch self {
        case .hrv: return "ms"
        case .restingHeartRate: return "bpm"
        case .sleepDuration: return "h"
        case .sleepScore: return "分"
        case .recovery: return "%"
        case .strain: return ""
        case .stress: return ""
        case .energy: return "%"
        case .respiratoryRate: return "次/分"
        case .oxygenSaturation: return "%"
        case .bodyWeight: return "kg"
        case .bodyFat: return "%"
        case .steps: return "步"
        case .activeCalories: return "kcal"
        }
    }

    /// Today ring that this metric may emphasize. Sleep duration is not the
    /// sleep-score ring; a short night must not be read as a score deviation.
    public var todayScoreRingID: String? {
        switch self {
        case .recovery: return "recovery"
        case .sleepScore: return "sleep"
        case .strain: return "strain"
        case .stress: return "stress"
        case .energy: return "energy"
        default: return nil
        }
    }

    public var icon: String {
        switch self {
        case .hrv: return "waveform.path.ecg"
        case .restingHeartRate: return "heart.fill"
        case .sleepDuration, .sleepScore: return "moon.stars.fill"
        case .recovery: return "heart.circle.fill"
        case .strain: return "figure.run"
        case .stress: return "bolt.shield.fill"
        case .energy: return "bolt.fill"
        case .respiratoryRate: return "lungs.fill"
        case .oxygenSaturation: return "drop.fill"
        case .bodyWeight: return "scalemass.fill"
        case .bodyFat: return "figure.arms.open"
        case .steps: return "shoeprints.fill"
        case .activeCalories: return "flame.fill"
        }
    }

    public var polarity: MetricPolarity {
        switch self {
        case .hrv, .recovery, .sleepDuration, .sleepScore, .energy, .oxygenSaturation:
            return .higherIsBetter
        case .restingHeartRate, .stress:
            return .lowerIsBetter
        case .strain, .respiratoryRate, .bodyWeight, .bodyFat, .steps, .activeCalories:
            return .contextual
        }
    }
}

public enum TrendValueDirection: String, Codable, Hashable, Sendable {
    case rising = "rising"
    case falling = "falling"
    case stable = "stable"
    case unknown = "unknown"

    public var icon: String {
        switch self {
        case .rising: return "arrow.up.right"
        case .falling: return "arrow.down.right"
        case .stable: return "arrow.right"
        case .unknown: return "minus"
        }
    }

    public var label: String {
        switch self {
        case .rising: return "上升"
        case .falling: return "下降"
        case .stable: return "持平"
        case .unknown: return "积累中"
        }
    }
}

public enum TrendAssessment: String, Codable, Hashable, Sendable {
    case favorable = "favorable"
    case unfavorable = "unfavorable"
    case neutral = "neutral"
    case insufficientData = "insufficientData"

    public var label: String {
        switch self {
        case .favorable: return "改善"
        case .unfavorable: return "偏弱"
        case .neutral: return "平稳"
        case .insufficientData: return "数据积累中"
        }
    }
}

// MARK: - Health Trend Finding

public struct HealthTrendFinding: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(metric.rawValue)_\(horizon.rawValue)" }
    public var metric: CoreHealthMetric
    public var horizon: HealthTrendHorizon
    public var direction: HealthTrendDirection
    public var valueDirection: TrendValueDirection
    public var assessment: TrendAssessment
    public var currentValue: Double?
    public var currentValueFormatted: String
    public var baselineValue: Double?
    public var baselineValueFormatted: String?
    public var currentDeviationValue: Double?
    public var currentDeviationPercent: Double?
    public var temporalTrendDelta: Double?
    public var temporalTrendDeltaPercent: Double?
    public var historicalPercentile: Double?
    public var sampleCount: Int
    public var requiredSampleCount: Int
    public var isAvailable: Bool
    public var confidence: DataConfidence
    public var deviationSummary: String
    public var temporalTrendSummary: String
    public var summary: String
    public var isNotable: Bool

    public init(
        metric: CoreHealthMetric,
        horizon: HealthTrendHorizon,
        direction: HealthTrendDirection,
        valueDirection: TrendValueDirection = .stable,
        assessment: TrendAssessment = .neutral,
        currentValue: Double?,
        currentValueFormatted: String,
        baselineValue: Double? = nil,
        baselineValueFormatted: String? = nil,
        currentDeviationValue: Double? = nil,
        currentDeviationPercent: Double? = nil,
        temporalTrendDelta: Double? = nil,
        temporalTrendDeltaPercent: Double? = nil,
        historicalPercentile: Double? = nil,
        sampleCount: Int = 0,
        requiredSampleCount: Int = 0,
        isAvailable: Bool = true,
        confidence: DataConfidence = .high,
        deviationSummary: String = "",
        temporalTrendSummary: String = "",
        summary: String,
        isNotable: Bool = false
    ) {
        self.metric = metric
        self.horizon = horizon
        self.direction = direction
        self.valueDirection = valueDirection
        self.assessment = assessment
        self.currentValue = currentValue
        self.currentValueFormatted = currentValueFormatted
        self.baselineValue = baselineValue
        self.baselineValueFormatted = baselineValueFormatted
        self.currentDeviationValue = currentDeviationValue
        self.currentDeviationPercent = currentDeviationPercent
        self.temporalTrendDelta = temporalTrendDelta
        self.temporalTrendDeltaPercent = temporalTrendDeltaPercent
        self.historicalPercentile = historicalPercentile
        self.sampleCount = sampleCount
        self.requiredSampleCount = requiredSampleCount
        self.isAvailable = isAvailable
        self.confidence = confidence
        self.deviationSummary = deviationSummary
        self.temporalTrendSummary = temporalTrendSummary
        self.summary = summary
        self.isNotable = isNotable
    }

    public static func unavailable(
        metric: CoreHealthMetric,
        horizon: HealthTrendHorizon,
        sampleCount: Int = 0
    ) -> HealthTrendFinding {
        HealthTrendFinding(
            metric: metric,
            horizon: horizon,
            direction: .insufficientData,
            valueDirection: .unknown,
            assessment: .insufficientData,
            currentValue: nil,
            currentValueFormatted: "--",
            baselineValue: nil,
            baselineValueFormatted: nil,
            sampleCount: sampleCount,
            requiredSampleCount: horizon.requiredSampleCount,
            isAvailable: false,
            confidence: .unavailable,
            deviationSummary: "数据积累中",
            temporalTrendSummary: "样本不足（需至少 \(horizon.requiredSampleCount) 天）",
            summary: "数据积累中（需至少 \(horizon.requiredSampleCount) 天）",
            isNotable: false
        )
    }
}

// MARK: - Body General State

public enum BodyGeneralState: String, Codable, Hashable, Sendable {
    case optimal = "optimal"
    case stable = "stable"
    case strained = "strained"
    case recovering = "recovering"
    case insufficientData = "insufficientData"

    public var title: String {
        switch self {
        case .optimal: return "身体状态良好"
        case .stable: return "身体状态总体稳定"
        case .strained: return "处于负荷累积状态"
        case .recovering: return "处于恢复调节状态"
        case .insufficientData: return "正在建立身体基线"
        }
    }

    public var icon: String {
        switch self {
        case .optimal: return "sparkles"
        case .stable: return "checkmark.circle.fill"
        case .strained: return "exclamationmark.triangle.fill"
        case .recovering: return "bed.double.fill"
        case .insufficientData: return "chart.line.uptrend.xyaxis"
        }
    }
}

public enum HealthActionCategory: String, Codable, Hashable, Sendable {
    case training = "training"
    case sleep = "sleep"
    case recovery = "recovery"
    case lifestyle = "lifestyle"
    case none = "none"

    public var title: String {
        switch self {
        case .training: return "日常活动与训练"
        case .sleep: return "睡眠关注"
        case .recovery: return "主动恢复"
        case .lifestyle: return "生活节奏"
        case .none: return "保持日常节奏"
        }
    }
}

// MARK: - Personal Health Brief (Canonical Product Object)

public struct PersonalHealthBrief: Codable, Hashable, Sendable {
    public var date: Date
    public var overallState: BodyGeneralState
    public var headline: String
    public var subheadline: String
    public var notableChanges: [HealthTrendFinding]
    public var stableSignals: [HealthTrendFinding]
    public var multiscaleTrends: [HealthTrendFinding]
    public var possibleDrivers: [String]
    public var confidence: DataConfidence
    public var confidenceLabel: String
    public var needsAction: Bool
    public var suggestedActionCategory: HealthActionCategory
    public var actionHeadline: String?
    public var actionDetail: String?
    public var lifestyleSuggestions: [String]
    public var generatedAt: Date

    public init(
        date: Date = Date(),
        overallState: BodyGeneralState = .stable,
        headline: String,
        subheadline: String,
        notableChanges: [HealthTrendFinding] = [],
        stableSignals: [HealthTrendFinding] = [],
        multiscaleTrends: [HealthTrendFinding] = [],
        possibleDrivers: [String] = [],
        confidence: DataConfidence = .high,
        confidenceLabel: String = "数据充足",
        needsAction: Bool = false,
        suggestedActionCategory: HealthActionCategory = .none,
        actionHeadline: String? = nil,
        actionDetail: String? = nil,
        lifestyleSuggestions: [String] = [],
        generatedAt: Date = Date()
    ) {
        self.date = date
        self.overallState = overallState
        self.headline = headline
        self.subheadline = subheadline
        self.notableChanges = notableChanges
        self.stableSignals = stableSignals
        self.multiscaleTrends = multiscaleTrends
        self.possibleDrivers = possibleDrivers
        self.confidence = confidence
        self.confidenceLabel = confidenceLabel
        self.needsAction = needsAction
        self.suggestedActionCategory = suggestedActionCategory
        self.actionHeadline = actionHeadline
        self.actionDetail = actionDetail
        self.lifestyleSuggestions = lifestyleSuggestions
        self.generatedAt = generatedAt
    }

    public static func empty(date: Date = Date()) -> PersonalHealthBrief {
        PersonalHealthBrief(
            date: date,
            overallState: .insufficientData,
            headline: "正在建立个人健康基线",
            subheadline: "同步 Apple 健康数据后，Vela 将自动识别你的生理基准与长期趋势。",
            confidence: .unavailable,
            confidenceLabel: "数据不足",
            needsAction: false,
            suggestedActionCategory: .none,
            generatedAt: date
        )
    }
}
