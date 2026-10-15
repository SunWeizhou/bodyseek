import Foundation
import XCTest
@testable import Vela

/// Production stress scores pass through the app adapter into
/// `BodySeekDomain.StressIndexEngine`. These assertions stay on the app
/// type so the mapped `MetricResult` still matches the replay fixture.
final class StressReplaySensitivityTests: XCTestCase {
    private let asOf: Date = ISO8601DateFormatter().date(from: "2026-07-31T12:00:00Z")!

    func testBaselineReplayIdentityAndFingerprint() {
        let result = StressIndexEngine().calculate(from: baselineInput())
        XCTAssertEqual(result.value ?? -999, 56.2142645029, accuracy: 0.0000001)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.missingInputs, [])
        XCTAssertEqual(result.algorithmVersion, ScoringAlgorithmVersions.physiologicalStress)
        XCTAssertEqual(result.components["rhr_stress"] ?? -1, 74, accuracy: 0.0000001)
        XCTAssertEqual(result.components["hrv_stress"] ?? -1, 61.8530580115, accuracy: 0.0000001)
    }

    func testSensitivityCasesHaveStableOutputs() {
        let engine = StressIndexEngine()
        let cases: [(String, StressIndexInput, Double)] = [
            ("high-rhr-72", replacing(baselineInput(), quietHRToday: 72), 62.7142645029),
            ("low-hrv-28", replacing(baselineInput(), hrvToday: 28), 65.751),
            ("high-temp-1.1", replacing(baselineInput(), bodyTempDelta: 1.1), 62.2142645029)
        ]
        for (name, input, expected) in cases {
            let result = engine.calculate(from: input)
            XCTAssertEqual(result.value ?? -999, expected, accuracy: 0.0000001, name)
            XCTAssertEqual(result.confidence, .high, name)
            XCTAssertEqual(result.algorithmVersion, ScoringAlgorithmVersions.physiologicalStress, name)
        }
    }

    func testWorkoutWindowRemainsUnavailable() {
        var input = baselineInput()
        input.isWithinWorkoutWindow = true
        let result = StressIndexEngine().calculate(from: input)
        XCTAssertNil(result.value)
        XCTAssertEqual(result.dataCoverage, .unavailable)
        XCTAssertEqual(result.formattedScore, "--")
        XCTAssertEqual(result.missingInputs, ["quietWindow"])
    }

    private func baselineInput() -> StressIndexInput {
        StressIndexInput(
            asOf: asOf,
            mode: .rawVitals,
            quietHRToday: 62,
            quietHRBaseline: 58,
            quietHRSD: 3,
            hrvToday: 45,
            hrvBaseline: 50,
            hrvSD: 8,
            respRateToday: 15,
            respRateBaseline: 14,
            respRateSD: 0.8,
            bodyTempDelta: 0.2,
            sleepScoreLastNight: 77.43,
            strainScoreToday: 65.53,
            isWithinWorkoutWindow: false
        )
    }

    private func replacing(
        _ input: StressIndexInput,
        quietHRToday: Double? = nil,
        hrvToday: Double? = nil,
        bodyTempDelta: Double? = nil
    ) -> StressIndexInput {
        var copy = input
        if let quietHRToday { copy.quietHRToday = quietHRToday }
        if let hrvToday { copy.hrvToday = hrvToday }
        if let bodyTempDelta { copy.bodyTempDelta = bodyTempDelta }
        return copy
    }
}
