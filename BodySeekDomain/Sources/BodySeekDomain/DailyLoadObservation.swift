import Foundation

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

extension Array where Element == DailyLoadObservation {
    /// Observed and known-zero loads, in the existing order.
    /// Missing and excluded days are left out so an unworn day is not a rest day.
    public func loadValuesSkippingGaps() -> [Double] {
        compactMap { observation in
            guard observation.availability.contributesToLoad else { return nil }
            return observation.value
        }
    }
}
