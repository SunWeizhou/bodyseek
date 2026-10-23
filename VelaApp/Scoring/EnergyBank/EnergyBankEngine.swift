import Foundation
import BodySeekDomain

public typealias MetricConfidence = BodySeekDomain.MetricConfidence
public typealias TrainingLoadStatus = BodySeekDomain.TrainingLoadStatus
public typealias EnergyBankInput = BodySeekDomain.EnergyBankInput

/// App-facing energy types stay stable while the formula lives in
/// `BodySeekDomain`. Callers still construct `EnergyBankInput` and read an
/// app `MetricResult`.
public struct EnergyBankEngine: ScoreEngine {
    public typealias Input = EnergyBankInput
    public typealias Output = MetricResult

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func calculate(from input: EnergyBankInput) -> MetricResult {
        let result = BodySeekDomain.EnergyBankEngine(calendar: calendar).calculate(from: input)
        return DomainMetricAdapter.metric(result)
    }
}
