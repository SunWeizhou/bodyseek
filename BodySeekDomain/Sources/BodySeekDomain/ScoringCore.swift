import Foundation

public protocol ScoreEngine {
    associatedtype Input
    associatedtype Output

    func calculate(from input: Input) -> Output
}

public enum MetricBand: String, Codable, Hashable, Sendable {
    case veryLow
    case low
    case normal
    case high
    case veryHigh
}

public enum MetricConfidence: String, Codable, Hashable, Sendable {
    case low
    case medium
    case high
}

public enum MetricState: String, Codable, Hashable, Sendable {
    case good
    case moderate
    case poor
}

public enum MetricSource: String, Codable, Hashable, Sendable {
    case healthKit
    case userInput
    case derived
    case mixed
}

/// Platform-neutral outcome of a health data read.  This deliberately lives
/// in the calculation package so adapters can preserve permission, no-data,
/// and transient failures without importing HealthKit.
public enum HealthQueryOutcomeKind: String, Codable, Hashable, Sendable {
    case data
    case noData
    case denied
    case unavailable
    case transient
    case failed

    public var isFailure: Bool {
        switch self {
        case .denied, .unavailable, .transient, .failed: true
        case .data, .noData: false
        }
    }
}

/// Freshness is intentionally broader than Sleep's current scoring policy;
/// adapters may preserve live/recent values while the engine only needs to
/// distinguish current, stale, and missing evidence.
public enum DataFreshness: String, Codable, Hashable, CaseIterable, Sendable {
    case live
    case today
    case recent
    case stale
    case missing
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

public enum ScoreDirection: String, Codable, Hashable, Sendable {
    case higherIsBetter
    case higherIsLoad
    case higherNeedsAttention
}

public enum ScoreDataCoverage: String, Codable, Hashable, Sendable {
    case unavailable
    case partial
    case substantial
    case complete
}

/// Version identifiers are part of the replay contract, not UI metadata.
public enum ScoringAlgorithmVersions {
    public static let sleep = "sleep.v2.2.0"
    public static let recovery = "recovery.v2.0.0"
    public static let strain = "strain.v2.1.0"
    public static let physiologicalStress = "physiologicalStress.v2.0.0"
    public static let energy = "energy.v2.0.0"
}

public enum StrainTargetStatus: String, Codable, Hashable, Sendable {
    case belowTarget = "Below target"
    case withinTarget = "Within target"
    case aboveTarget = "Above target"
}

public enum EnergyBankStatus: String, Codable, Hashable, Sendable {
    case depleted = "Depleted"
    case low = "Low"
    case stable = "Stable"
    case strong = "Strong"
}

public enum TrainingLoadStatus: String, Codable, Hashable, Sendable {
    case unknown
    case wellBelow
    case below
    case optimal
    case elevated
    case highRisk
}

public struct MetricResult: Codable, Hashable, Sendable {
    public var domain: ScoredHealthDomain
    public var name: String
    public var value: Double?
    public var band: MetricBand
    public var confidence: MetricConfidence
    public var components: [String: Double]
    public var componentWeights: [String: Double]
    public var reasons: [String]
    public var missingInputs: [String]
    public var dataWindow: DateInterval
    public var source: MetricSource
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
        components: [String: Double] = [:],
        componentWeights: [String: Double] = [:],
        reasons: [String] = [],
        missingInputs: [String] = [],
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

    /// Optional compatibility projection. `nil` stays `nil`; callers must not
    /// treat unavailable evidence as a numeric zero.
    public var score: Double? { value }
    public var weights: [String: Double] { componentWeights }
    public var metrics: [String: Double] { components }
    public var configVersion: String { algorithmVersion }
    public var hasData: Bool { value != nil }
    public var formattedScore: String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))"
    }
    public var direction: ScoreDirection {
        switch domain {
        case .recovery, .sleep, .energy: .higherIsBetter
        case .strain: .higherIsLoad
        case .physiologicalStress: .higherNeedsAttention
        }
    }
    public var state: MetricState? {
        guard value != nil else { return nil }
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
        guard missingInputs.isEmpty == false else { return .complete }
        return confidence == .low ? .partial : .substantial
    }
    public var morningEnergy: Double? { components["morningEnergy"] ?? value }
    public var currentEnergy: Double? { value }
    public var stressIndex: Double? { value }
    public var status: EnergyBankStatus? {
        guard let value else { return nil }
        switch value {
        case ..<25: return .depleted
        case ..<50: return .low
        case ..<75: return .stable
        default: return .strong
        }
    }
    public var explicitRecommendedRange: ClosedRange<Double>? {
        guard let lower = components["recommended_lower"],
              let upper = components["recommended_upper"],
              lower <= upper else { return nil }
        return lower...upper
    }
    public var recommendedRange: ClosedRange<Double>? {
        explicitRecommendedRange
    }
    public var targetStatus: StrainTargetStatus? {
        guard let value, let range = recommendedRange else { return nil }
        if value < range.lowerBound { return .belowTarget }
        if value > range.upperBound { return .aboveTarget }
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
}

/// Compatibility result retained for adapters that have not yet switched to
/// `MetricResult`. It is pure value data and has no UI or persistence behavior.
public enum ScoreBand: String, Codable, Hashable, Sendable {
    case low = "Low"
    case moderate = "Moderate"
    case high = "High"
}

public enum ScoreConfidence: String, Codable, Hashable, Sendable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

public struct StandardScoreResult: Codable, Hashable, Sendable {
    public var score: Double
    public var band: ScoreBand
    public var confidence: ScoreConfidence
    public var components: [String: Double]
    public var weights: [String: Double]
    public var reasons: [String]
    public var metrics: [String: Double]
    public var configVersion: String

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
    public static func clamp(
        _ value: Double,
        min minimum: Double = 0,
        max maximum: Double = 100
    ) -> Double {
        guard value.isFinite else { return minimum }
        return Swift.max(minimum, Swift.min(maximum, value))
    }

    public static func band(for score: Double) -> MetricBand {
        switch score {
        case ..<25: .veryLow
        case ..<45: .low
        case ..<75: .normal
        case ..<90: .high
        default: .veryHigh
        }
    }

    public static func confidence(available: Int, expected: Int) -> MetricConfidence {
        guard expected > 0 else { return .low }
        if available == expected { return .high }
        if available >= max(1, expected - 1) { return .medium }
        return .low
    }

    /// Median used by the existing scoring engines. Sorting is deterministic;
    /// an empty collection remains unavailable (`nil`).
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    /// Sample standard deviation (Bessel correction), matching the Vela
    /// PersonalBaselineEngine implementation.
    public static func sampleStandardDeviation(_ values: [Double]) -> Double? {
        guard values.count > 1 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDifference = values.reduce(0.0) { $0 + pow($1 - mean, 2) }
        let value = sqrt(squaredDifference / Double(values.count - 1))
        return value > 0 ? value : nil
    }

    /// Median absolute deviation scaled to a normal-distribution estimate,
    /// matching the Vela PersonalBaselineEngine implementation.
    public static func robustStandardDeviation(
        _ values: [Double],
        around median: Double
    ) -> Double? {
        guard let mad = self.median(values.map { abs($0 - median) }) else { return nil }
        let value = 1.4826 * mad
        return value > 0 ? value : nil
    }
}
