import Foundation
import XCTest
@testable import BodySeekDomain

/// Package replay for physiological stress after the engine moved out of the app.
/// The numeric oracle is `docs/baselines/stress-replay-fixtures.json`.
final class StressReplaySensitivityTests: XCTestCase {
    private let asOf: Date = ISO8601DateFormatter().date(from: "2026-07-31T12:00:00Z")!

    func testBaselineReplayIdentityAndFingerprint() {
        let input = baselineInput()
        let result = StressIndexEngine().calculate(from: input)

        XCTAssertEqual(result.value ?? -999, 56.2142645029, accuracy: 0.0000001)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.missingInputs, [])
        XCTAssertEqual(result.algorithmVersion, ScoringAlgorithmVersions.physiologicalStress)
        XCTAssertEqual(result.components["rhr_stress"] ?? -1, 74, accuracy: 0.0000001)
        XCTAssertEqual(result.components["hrv_stress"] ?? -1, 61.8530580115, accuracy: 0.0000001)
        XCTAssertEqual(fingerprint(input), "stress-v2|2026-07-31T12:00:00Z|mode=rawVitals|rhr=62.00|rhrBase=58.00|rhrSD=3.00|hrv=45.00|hrvBase=50.00|hrvSD=8.00|resp=15.00|respBase=14.00|respSD=0.80|temp=0.20|sleep=77.43|strain=65.53|window=false|longRHR=nil")
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

    func testLongTermQuietHeartRateGateNeutralizesShortTermElevation() {
        var input = baselineInput()
        input.quietHRToday = 70
        input.quietHRBaseline = 60
        input.quietHRSD = 5
        input.longTermQuietHRMedian = 72
        let result = StressIndexEngine().calculate(from: input)
        XCTAssertEqual(result.components["rhr_stress"] ?? -1, 50, accuracy: 0.0000001)
        XCTAssertTrue(result.reasons.contains { $0.contains("中和") })
    }

    func testWorkoutWindowRemainsUnavailable() {
        var input = baselineInput()
        input.isWithinWorkoutWindow = true
        let result = StressIndexEngine().calculate(from: input)
        XCTAssertNil(result.value)
        XCTAssertEqual(result.dataCoverage, .unavailable)
        XCTAssertEqual(result.confidence, .low)
        XCTAssertEqual(result.formattedScore, "--")
        XCTAssertEqual(result.missingInputs, ["quietWindow"])
        XCTAssertEqual(result.algorithmVersion, ScoringAlgorithmVersions.physiologicalStress)
    }

    func testEmptyInputRemainsUnavailable() {
        let result = StressIndexEngine().calculate(from: StressIndexInput(asOf: asOf))
        XCTAssertNil(result.value)
        XCTAssertEqual(result.dataCoverage, .unavailable)
        XCTAssertEqual(result.confidence, .low)
        XCTAssertEqual(result.formattedScore, "--")
        XCTAssertTrue(result.missingInputs.contains("bodyTempDelta"))
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

    private func fingerprint(_ input: StressIndexInput) -> String {
        let number: (Double?) -> String = { value in value.map { String(format: "%.2f", $0) } ?? "nil" }
        let mode = input.mode == .rawVitals ? "rawVitals" : "legacyComponentScores"
        return "stress-v2|\(iso8601(input.asOf))|mode=\(mode)|rhr=\(number(input.quietHRToday))|rhrBase=\(number(input.quietHRBaseline))|rhrSD=\(number(input.quietHRSD))|hrv=\(number(input.hrvToday))|hrvBase=\(number(input.hrvBaseline))|hrvSD=\(number(input.hrvSD))|resp=\(number(input.respRateToday))|respBase=\(number(input.respRateBaseline))|respSD=\(number(input.respRateSD))|temp=\(number(input.bodyTempDelta))|sleep=\(number(input.sleepScoreLastNight))|strain=\(number(input.strainScoreToday))|window=\(input.isWithinWorkoutWindow)|longRHR=\(number(input.longTermQuietHRMedian))"
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
