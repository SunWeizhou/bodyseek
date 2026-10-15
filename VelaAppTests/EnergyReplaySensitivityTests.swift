import Foundation
import XCTest
@testable import Vela

/// Production energy scores pass through the app adapter into
/// `BodySeekDomain.EnergyBankEngine`. These assertions stay on the app
/// type so the mapped `MetricResult` still matches the replay fixture.
final class EnergyReplaySensitivityTests: XCTestCase {
    private let asOf: Date = ISO8601DateFormatter().date(from: "2026-07-31T12:00:00Z")!

    func testBaselineReplayIdentity() {
        let result = EnergyBankEngine().calculate(from: baselineInput())
        XCTAssertEqual(result.value ?? -999, 53.2, accuracy: 0.0000001)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.missingInputs, [])
        XCTAssertEqual(result.algorithmVersion, ScoringAlgorithmVersions.energy)
        XCTAssertEqual(result.components["atl"] ?? -1, 58.75, accuracy: 0.0000001)
        XCTAssertEqual(result.components["acwr"] ?? -1, 0.9848265896, accuracy: 0.0000001)
    }

    func testMissingRecoveryAndSleepRemainsUnavailable() {
        let result = EnergyBankEngine().calculate(from: EnergyBankInput(
            asOf: asOf,
            recoveryScore: nil,
            sleepScore: nil,
            strainScore: nil,
            stressIndex: nil
        ))
        XCTAssertNil(result.value)
        XCTAssertEqual(result.formattedScore, "--")
        XCTAssertEqual(result.dataCoverage, .unavailable)
    }

    private func baselineInput() -> EnergyBankInput {
        EnergyBankInput(
            asOf: asOf,
            recoveryScore: 70,
            sleepScore: 80,
            strainScore: 40,
            stressIndex: 30,
            hrvToday: 50,
            hrvBaseline: 50,
            rhrToday: 58,
            rhrBaseline: 60,
            sleepHours: 7.5,
            strainHistory: Array(repeating: 60, count: 14),
            todayLoad: 55,
            bodyTempDelta: 0.2,
            hoursSinceWake: 8,
            respiratoryRateZ: 0.2,
            SpO2: 98,
            recoveryConfidence: .high,
            sleepConfidence: .high
        )
    }
}
