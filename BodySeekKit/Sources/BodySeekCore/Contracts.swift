import Foundation

/// Physiological calendar day identity anchored by a configurable cutover hour (default 04:00 local time).
public struct DayKey: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, cutoverHour: Int = 4, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let shifted = calendar.date(byAdding: .hour, value: -cutoverHour, to: date) ?? date
        let comps = calendar.dateComponents([.year, .month, .day], from: shifted)
        self.year = comps.year ?? 1970
        self.month = comps.month ?? 1
        self.day = comps.day ?? 1
    }

    public init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2]),
              (1...12).contains(m),
              (1...31).contains(d)
        else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let comps = DateComponents(year: y, month: m, day: d)
        guard let validated = calendar.date(from: comps) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: validated)
        guard roundTrip.year == y, roundTrip.month == m, roundTrip.day == d else {
            return nil
        }
        self.year = y
        self.month = m
        self.day = d
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String {
        isoString
    }

    public func startDate(cutoverHour: Int = 4, timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let comps = DateComponents(year: year, month: month, day: day, hour: cutoverHour, minute: 0, second: 0)
        return calendar.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

public extension Date {
    func physiologicalDayKey(cutoverHour: Int = 4, timeZone: TimeZone = .current) -> DayKey {
        DayKey(date: self, cutoverHour: cutoverHour, timeZone: timeZone)
    }
}

public enum MissingReason: Hashable, Codable, Sendable {
    case unauthorized
    case noSamples
    case insufficientBaseline
    case sensorUnavailable
    case notRecorded
    case other(String)

    public var displayText: String {
        switch self {
        case .unauthorized: "未授权读取 Apple 健康数据"
        case .noSamples: "当前时间窗口无采样"
        case .insufficientBaseline: "历史基线样本不足"
        case .sensorUnavailable: "传感器未佩戴或不可用"
        case .notRecorded: "尚未记录"
        case let .other(message): message
        }
    }
}

public enum ExclusionReason: Hashable, Codable, Sendable {
    case postWorkoutWindow
    case motionArtifact
    case sourceConflict
    case outOfPhysiologicalRange
    case userExcluded
    case other(String)

    public var displayText: String {
        switch self {
        case .postWorkoutWindow: "运动后恢复排除窗口"
        case .motionArtifact: "高活动/伪影窗口已排除"
        case .sourceConflict: "多源冲突已按策略排除"
        case .outOfPhysiologicalRange: "超出正常生理阈值已排除"
        case .userExcluded: "用户已手动排除"
        case let .other(message): message
        }
    }
}

public struct SourceRef: Hashable, Codable, Sendable {
    public let bundleIdentifier: String?
    public let name: String
    public let deviceModel: String?
    public let priority: Int

    public init(
        bundleIdentifier: String? = nil,
        name: String,
        deviceModel: String? = nil,
        priority: Int = 0
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.deviceModel = deviceModel
        self.priority = priority
    }
}

public struct Provenance: Hashable, Codable, Sendable {
    public let sources: [SourceRef]
    public let window: DateInterval
    public let coverage: Double
    public let ingestedAt: Date
    public let timeZoneIdentifier: String

    public init(
        sources: [SourceRef],
        window: DateInterval,
        coverage: Double,
        ingestedAt: Date = Date(),
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.sources = sources
        self.window = window
        self.coverage = min(1.0, max(0.0, coverage))
        self.ingestedAt = ingestedAt
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

/// Four-state truth representation flowing across HealthKit -> Store -> Core -> Chart -> Agent -> ML mask.
/// Named `HealthObservation` rather than `Observation` so it never shadows Apple's system `Observation` module.
public enum HealthObservation<Value: Sendable & Codable & Hashable>: Hashable, Codable, Sendable {
    case available(Value, Provenance)
    case knownZero(reason: String, Provenance)
    case missing(reason: MissingReason)
    case excluded(reason: ExclusionReason, Provenance)

    public var value: Value? {
        switch self {
        case let .available(val, _): val
        case .knownZero, .missing, .excluded: nil
        }
    }

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var provenance: Provenance? {
        switch self {
        case let .available(_, prov), let .knownZero(_, prov), let .excluded(_, prov):
            prov
        case .missing:
            nil
        }
    }
}

public struct AlgorithmVersion: Hashable, Codable, Sendable, CustomStringConvertible {
    public let id: String
    public let semver: String

    public init(id: String, semver: String) {
        self.id = id
        self.semver = semver
    }

    public var description: String {
        "\(id)@\(semver)"
    }

    public static let scoreV2 = AlgorithmVersion(id: "score-v2", semver: "2.0.0")
    public static let recoveryHeuristicV1 = AlgorithmVersion(id: "recovery-heuristic-v1", semver: "1.0.0")
    public static let sleepMergeV1 = AlgorithmVersion(id: "sleep-merge-v1", semver: "1.0.0")
    public static let workoutParserV1 = AlgorithmVersion(id: "workout-parser-v1", semver: "1.0.0")
}

public struct EvidenceRef: Hashable, Codable, Sendable {
    public let kind: String
    public let identifier: String
    public let summary: String

    public init(kind: String, identifier: String, summary: String) {
        self.kind = kind
        self.identifier = identifier
        self.summary = summary
    }
}

public struct ActionProposal: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case annotateWorkout
        case commitMemory
        case retireMemory
        case adjustPlan
        case recordCheckIn
    }

    public enum Origin: String, Codable, Sendable, Hashable {
        case user
        case agent
        case system
    }

    public let id: UUID
    public let kind: Kind
    public let origin: Origin
    public let payload: Data
    public let rationale: String?
    public let evidenceRefs: [EvidenceRef]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: Kind,
        origin: Origin,
        payload: Data,
        rationale: String? = nil,
        evidenceRefs: [EvidenceRef] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.origin = origin
        self.payload = payload
        self.rationale = rationale
        self.evidenceRefs = evidenceRefs
        self.createdAt = createdAt
    }

    public init<P: Encodable>(
        id: UUID = UUID(),
        kind: Kind,
        origin: Origin,
        encodablePayload: P,
        rationale: String? = nil,
        evidenceRefs: [EvidenceRef] = [],
        createdAt: Date = Date(),
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        let data = try encoder.encode(encodablePayload)
        self.init(
            id: id,
            kind: kind,
            origin: origin,
            payload: data,
            rationale: rationale,
            evidenceRefs: evidenceRefs,
            createdAt: createdAt
        )
    }

    public func decodePayload<P: Decodable>(
        _ type: P.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> P {
        try decoder.decode(type, from: payload)
    }
}

public struct MetricContributor: Hashable, Codable, Sendable, Identifiable {
    public enum Impact: String, Hashable, Codable, Sendable {
        case positive
        case neutral
        case negative
        case missing
    }

    public let id: String
    public let label: String
    public let valueText: String
    public let baselineDeltaText: String?
    public let weight: Double?
    public let impact: Impact

    public init(
        id: String,
        label: String,
        valueText: String,
        baselineDeltaText: String? = nil,
        weight: Double? = nil,
        impact: Impact = .neutral
    ) {
        self.id = id
        self.label = label
        self.valueText = valueText
        self.baselineDeltaText = baselineDeltaText
        self.weight = weight
        self.impact = impact
    }
}
