import Foundation
import BodySeekDomain

public typealias StressIndexInputMode = BodySeekDomain.StressIndexInputMode
public typealias StressIndexInput = BodySeekDomain.StressIndexInput

/// App-facing stress types stay stable while the formula lives in
/// `BodySeekDomain`. Callers still construct `StressIndexInput` and read an
/// app `MetricResult`.
public struct StressIndexEngine: ScoreEngine {
    public typealias Input = StressIndexInput
    public typealias Output = MetricResult

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func calculate(from input: StressIndexInput) -> MetricResult {
        let result = BodySeekDomain.StressIndexEngine(calendar: calendar).calculate(from: input)
        return DomainMetricAdapter.metric(result)
    }
}
