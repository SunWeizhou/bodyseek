import Foundation

public protocol ScoreEngine {
    associatedtype Input
    associatedtype Output

    func calculate(from input: Input) -> Output
}

public enum MetricBand: String, Codable, Hashable, Sendable {
    case veryLow = "veryLow"
    case low = "low"
    case normal = "normal"
    case high = "high"
    case veryHigh = "veryHigh"
}

public enum MetricConfidence: String, Codable, Hashable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"
}

/// G1 状态着色:指标当前处于「好/注意/差」哪种状态。
/// 颜色只表达状态,不表达指标身份。
public enum MetricState: String, Codable, Hashable, Sendable {
    case good
    case moderate
    case poor
}

public enum MetricSource: String, Codable, Hashable, Sendable {
    case healthKit = "healthKit"
    case userInput = "userInput"
    case derived = "derived"
    case mixed = "mixed"
}

public enum ScoredHealthDomain: String, Codable, Hashable, CaseIterable, Sendable {
    case recovery
    case sleep
    case strain
    case physiologicalStress
    case energy

    fileprivate static func infer(from name: String) -> ScoredHealthDomain {
        let normalized = name.lowercased()
        if normalized.contains("sleep") { return .sleep }
        if normalized.contains("strain") { return .strain }
        if normalized.contains("stress") { return .physiologicalStress }
        if normalized.contains("energy") { return .energy }
        return .recovery
    }
}

public enum ScoreDirection: String, Codable, Hashable {
    case higherIsBetter
    case higherIsLoad
    case higherNeedsAttention
}

public enum ScoreDataCoverage: String, Codable, Hashable {
    case unavailable
    case partial
    case substantial
    case complete
}

enum ScoringAlgorithmVersions {
    static let sleep = "sleep.v2.2.0"
    static let recovery = "recovery.v2.0.0"
    static let strain = "strain.v2.1.0"
    static let physiologicalStress = "physiologicalStress.v2.0.0"
    static let energy = "energy.v2.1.0"
}

/// Availability of a daily training-load observation. This is an in-memory
/// evidence contract; it does not alter the SwiftData schema. In particular,
/// `missing` is never silently represented as a measured zero.
public enum TrainingLoadAvailability: String, Codable, Hashable, Sendable {
    case observed
    case knownZero
    case missing
    case excluded

    public var contributesToLoad: Bool {
        switch self {
        case .observed, .knownZero: return true
        case .missing, .excluded: return false
        }
    }
}

public struct DailyLoadObservation: Codable, Hashable, Sendable {
    public var date: Date
    public var value: Double?
    public var availability: TrainingLoadAvailability
    public var reason: String?
    public var observedWindow: DateInterval?

    public init(
        date: Date,
        value: Double?,
        availability: TrainingLoadAvailability,
        reason: String? = nil,
        observedWindow: DateInterval? = nil
    ) {
        self.date = date
        self.value = value
        self.availability = availability
        self.reason = reason
        self.observedWindow = observedWindow
    }

    public var isObservedValue: Bool {
        availability.contributesToLoad && value != nil
    }
}

public enum StrainTargetStatus: String, Codable, Hashable {
    case belowTarget = "Below target"
    case withinTarget = "Within target"
    case aboveTarget = "Above target"
}

public enum EnergyBankStatus: String, Codable, Hashable {
    case unknown = "Unknown"
    case depleted = "Depleted"
    case low = "Low"
    case stable = "Stable"
    case strong = "Strong"
}

public enum TrainingLoadStatus: String, Codable, Hashable {
    case unknown = "unknown"
    case wellBelow = "wellBelow"
    case below = "below"
    case optimal = "optimal"
    case elevated = "elevated"
    case highRisk = "highRisk"
}

public struct MetricResult: Codable, Hashable, Sendable {
    public var domain: ScoredHealthDomain
    public var name: String
    public var value: Double?              // 0–100; nil if not computable
    public var band: MetricBand            // veryLow / low / normal / high / veryHigh
    public var confidence: MetricConfidence // low / medium / high
    public var components: [String: Double]
    public var componentWeights: [String: Double]
    public var reasons: [String]
    public var missingInputs: [String]
    public var dataWindow: DateInterval
    public var source: MetricSource         // healthKit / userInput / derived / mixed
    public var algorithmVersion: String
    public var lastUpdated: Date
    public var observedWindow: DateInterval?
    public var observedAt: Date?
    public var computedAt: Date?

    public init(
        domain: ScoredHealthDomain? = nil,
        name: String,
        value: Double?,
        band: MetricBand,
        confidence: MetricConfidence,
        components: [String: Double],
        componentWeights: [String: Double],
        reasons: [String],
        missingInputs: [String],
        dataWindow: DateInterval,
        source: MetricSource,
        algorithmVersion: String,
        lastUpdated: Date,
        observedWindow: DateInterval? = nil,
        observedAt: Date? = nil,
        computedAt: Date? = nil
    ) {
        self.domain = domain ?? ScoredHealthDomain.infer(from: name)
        self.name = name
        self.value = value
        self.band = band
        self.confidence = confidence
        self.components = components
        self.componentWeights = componentWeights
        self.reasons = reasons
        self.missingInputs = missingInputs
        self.dataWindow = dataWindow
        self.source = source
        self.algorithmVersion = algorithmVersion
        self.lastUpdated = lastUpdated
        self.observedWindow = observedWindow
        self.observedAt = observedAt
        self.computedAt = computedAt ?? lastUpdated
    }

    // Backward compatibility for SwiftUI views
    public var score: Double { value ?? 0 }
    public var weights: [String: Double] { componentWeights }
    public var metrics: [String: Double] { components }
    public var configVersion: String { algorithmVersion }
    public var hasData: Bool { value != nil }
    public var formattedScore: String {
        guard hasData, let v = value else { return "--" }
        return "\(Int(v.rounded()))"
    }
    public var direction: ScoreDirection {
        switch domain {
        case .recovery, .sleep, .energy:
            return .higherIsBetter
        case .strain:
            return .higherIsLoad
        case .physiologicalStress:
            return .higherNeedsAttention
        }
    }

    /// G1 状态着色:颜色只表达「好不好」,由 direction + band 推导。
    /// higherIsBetter(恢复/睡眠/能量):越高越好;higherNeedsAttention(压力):越低越好;
    /// higherIsLoad(负荷):落在正常区间为最好。
    public var state: MetricState {
        switch direction {
        case .higherIsBetter:
            switch band {
            case .high, .veryHigh: return .good
            case .normal: return .moderate
            case .low, .veryLow: return .poor
            }
        case .higherNeedsAttention:
            switch band {
            case .low, .veryLow: return .good
            case .normal: return .moderate
            case .high, .veryHigh: return .poor
            }
        case .higherIsLoad:
            switch band {
            case .normal: return .good
            case .low, .high: return .moderate
            case .veryLow, .veryHigh: return .poor
            }
        }
    }
    public var dataCoverage: ScoreDataCoverage {
        guard hasData else { return .unavailable }
        guard !missingInputs.isEmpty else { return .complete }
        return confidence == .low ? .partial : .substantial
    }

    // For EnergyBankResult
    public var morningEnergy: Double { components["morningEnergy"] ?? (value ?? 0) }
    public var currentEnergy: Double { value ?? 0 }
    public var status: EnergyBankStatus {
        guard let value else { return .unknown }
        switch value {
        case ..<25: return .depleted
        case ..<50: return .low
        case ..<75: return .stable
        default: return .strong
        }
    }

    // For StrainScoreResult
    /// The personalized reference band only exists when the scoring engine
    /// actually published both bounds. UI must use this optional projection so
    /// the compatibility fallback below is never presented as personal data.
    public var explicitRecommendedRange: ClosedRange<Double>? {
        guard let lower = components["recommended_lower"],
              let upper = components["recommended_upper"],
              lower <= upper else {
            return nil
        }
        return lower...upper
    }

    public var recommendedRange: ClosedRange<Int> {
        let lower = components["recommended_lower"] ?? 40.0
        let upper = components["recommended_upper"] ?? 70.0
        return Int(lower)...Int(upper)
    }
    public var targetStatus: StrainTargetStatus {
        let v = value ?? 0
        let r = recommendedRange
        if v < Double(r.lowerBound) { return .belowTarget }
        if v > Double(r.upperBound) { return .aboveTarget }
        return .withinTarget
    }
    public var trainingLoadStatus: TrainingLoadStatus {
        guard let code = components["training_load_status_code"] else { return .unknown }
        switch Int(code) {
        case 0: return .wellBelow
        case 1: return .below
        case 2: return .optimal
        case 3: return .elevated
        case 4: return .highRisk
        default: return .unknown
        }
    }

    // For StressIndexResult
    public var stressIndex: Double { value ?? 0 }

    private enum CodingKeys: String, CodingKey {
        case domain
        case name
        case value
        case band
        case confidence
        case components
        case componentWeights
        case reasons
        case missingInputs
        case dataWindow
        case source
        case algorithmVersion
        case lastUpdated
        case observedWindow
        case observedAt
        case computedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        domain = try container.decodeIfPresent(ScoredHealthDomain.self, forKey: .domain)
            ?? ScoredHealthDomain.infer(from: name)
        value = try container.decodeIfPresent(Double.self, forKey: .value)
        band = try container.decode(MetricBand.self, forKey: .band)
        confidence = try container.decode(MetricConfidence.self, forKey: .confidence)
        components = try container.decode([String: Double].self, forKey: .components)
        componentWeights = try container.decode([String: Double].self, forKey: .componentWeights)
        reasons = try container.decode([String].self, forKey: .reasons)
        missingInputs = try container.decode([String].self, forKey: .missingInputs)
        dataWindow = try container.decode(DateInterval.self, forKey: .dataWindow)
        source = try container.decode(MetricSource.self, forKey: .source)
        algorithmVersion = try container.decode(String.self, forKey: .algorithmVersion)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        observedWindow = try container.decodeIfPresent(DateInterval.self, forKey: .observedWindow)
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
        computedAt = try container.decodeIfPresent(Date.self, forKey: .computedAt) ?? lastUpdated
    }
}

public enum ScoreBand: String, Codable, Hashable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
}

public enum ScoreConfidence: String, Codable, Hashable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

// Keep StandardScoreResult as a thin wrapper or backward compatibility struct if needed elsewhere,
// but all engines will be refactored to output MetricResult directly.
public struct StandardScoreResult: Codable, Hashable {
    public var score: Double
    public var band: ScoreBand
    public var confidence: ScoreConfidence
    public var components: [String: Double]
    public var weights: [String: Double]
    public var reasons: [String]
    public var metrics: [String: Double]
    public var configVersion: String = "v0.1"

    public var hasData: Bool { !components.isEmpty }

    public init(
        score: Double,
        band: ScoreBand,
        confidence: ScoreConfidence,
        components: [String: Double],
        weights: [String: Double],
        reasons: [String],
        metrics: [String: Double],
        configVersion: String = "v0.1"
    ) {
        self.score = score
        self.band = band
        self.confidence = confidence
        self.components = components
        self.weights = weights
        self.reasons = reasons
        self.metrics = metrics
        self.configVersion = configVersion
    }
}

public enum ScoringMath {
    public static func clamp(_ value: Double, min minimum: Double = 0, max maximum: Double = 100) -> Double {
        // NaN/+inf/−inf 无意义：NaN 此前经 Swift.max/min 语义静默变成 100。
        guard value.isFinite else { return minimum }
        return Swift.max(minimum, Swift.min(maximum, value))
    }

    public static func band(for score: Double) -> MetricBand {
        switch score {
        case ..<25:
            return .veryLow
        case ..<45:
            return .low
        case ..<75:
            return .normal
        case ..<90:
            return .high
        default:
            return .veryHigh
        }
    }

    public static func confidence(available: Int, expected: Int) -> MetricConfidence {
        guard expected > 0 else { return .low }
        if available == expected { return .high }
        if available >= max(1, expected - 1) { return .medium }
        return .low
    }
}

// MARK: - Circadian Alignment Kernel

public struct CircadianInput: Sendable {
    public var sleepStartHour: Double     // e.g. 23.5 for 23:30
    public var sleepEndHour: Double       // e.g. 7.5 for 07:30
    public var targetBedtimeHour: Double  // e.g. 23.0 for 23:00
    public var hrvLowestPointHour: Double?// e.g. 3.5 for 03:30

    public init(
        sleepStartHour: Double = 23.5,
        sleepEndHour: Double = 7.5,
        targetBedtimeHour: Double = 23.0,
        hrvLowestPointHour: Double? = nil
    ) {
        self.sleepStartHour = sleepStartHour
        self.sleepEndHour = sleepEndHour
        self.targetBedtimeHour = targetBedtimeHour
        self.hrvLowestPointHour = hrvLowestPointHour
    }
}

public struct CircadianResult: Sendable, Equatable {
    public var alignmentScore: Double     // 0..100
    public var phaseOffsetMinutes: Int   // difference from target bedtime
    public var estimatedCortisolPeak: String // e.g. "07:45"
    public var caffeineCutoffTime: String    // e.g. "14:00"
    public var recommendations: [String]

    public init(
        alignmentScore: Double,
        phaseOffsetMinutes: Int,
        estimatedCortisolPeak: String,
        caffeineCutoffTime: String,
        recommendations: [String]
    ) {
        self.alignmentScore = alignmentScore
        self.phaseOffsetMinutes = phaseOffsetMinutes
        self.estimatedCortisolPeak = estimatedCortisolPeak
        self.caffeineCutoffTime = caffeineCutoffTime
        self.recommendations = recommendations
    }
}

public struct CircadianAlignmentKernel: Sendable {
    public init() {}

    public func evaluate(input: CircadianInput) -> CircadianResult {
        let diffHours = abs(input.sleepStartHour - input.targetBedtimeHour)
        let phaseOffsetMinutes = Int(diffHours * 60)

        let score = max(0.0, 100.0 - Double(phaseOffsetMinutes) * 0.5)

        let wakeHour = input.sleepEndHour
        let cortisolHour = wakeHour + 0.5
        let cortisolInt = Int(cortisolHour)
        let cortisolMin = Int((cortisolHour - Double(cortisolInt)) * 60)
        let estimatedCortisolPeak = String(format: "%02d:%02d", cortisolInt, cortisolMin)

        let cutoffHour = max(0, input.targetBedtimeHour - 9.5)
        let cutoffInt = Int(cutoffHour)
        let cutoffMin = Int((cutoffHour - Double(cutoffInt)) * 60)
        let caffeineCutoffTime = String(format: "%02d:%02d", cutoffInt, cutoffMin)

        var recs: [String] = []
        if phaseOffsetMinutes > 45 {
            recs.append("入睡时间偏离理想节律窗口超过 45 分钟，建议今晚提前 15 分钟准备躺下。")
        } else {
            recs.append("昼夜节律调和状态良好，继续维持稳定的入睡时间窗。")
        }

        if let hrvLow = input.hrvLowestPointHour, hrvLow > (wakeHour - 2.0) {
            recs.append("夜间 HRV 最低点出现偏晚，可能与晚间进食或剧烈运动相关。")
        }

        return CircadianResult(
            alignmentScore: score,
            phaseOffsetMinutes: phaseOffsetMinutes,
            estimatedCortisolPeak: estimatedCortisolPeak,
            caffeineCutoffTime: caffeineCutoffTime,
            recommendations: recs
        )
    }
}
