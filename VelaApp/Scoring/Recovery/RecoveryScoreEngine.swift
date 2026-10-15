import Foundation
import BodySeekDomain

/// App-facing recovery types stay stable while the formula lives in
/// `BodySeekDomain`. Callers still construct `RecoveryScoreInput` and read an
/// app `MetricResult`; this file only maps that result back across the seam.
public typealias RecoveryLongTermContext = BodySeekDomain.RecoveryLongTermContext
public typealias RecoveryScoreInput = BodySeekDomain.RecoveryScoreInput

public struct RecoveryScoreEngine: ScoreEngine {
    public typealias Input = RecoveryScoreInput
    public typealias Output = MetricResult

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func calculate(from input: RecoveryScoreInput) -> MetricResult {
        let result = BodySeekDomain.RecoveryScoreEngine(calendar: calendar).calculate(from: input)
        return DomainMetricAdapter.metric(result)
    }
}
