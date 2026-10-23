import Foundation
import XCTest
@testable import BodySeekDomain

/// Package replay for Recovery after the engine moved out of the app target.
/// The numeric oracle is `docs/baselines/recovery-replay-fixtures.json`.
final class RecoveryReplaySensitivityTests: XCTestCase {
    private let asOf: Date = ISO8601DateFormatter().date(from: "2026-07-31T12:00:00Z")!

    func testBaselineReplayIdentityAndFingerprint() {
        let input = baselineInput()
        let result = RecoveryScoreEngine().calculate(from: input)

        XCTAssertEqual(result.value ?? -999, 68.8497077483, accuracy: 0.0000001)
        XCTAssertEqual(result.algorithmVersion, ScoringAlgorithmVersions.recovery)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.missingInputs, [])
        XCTAssertEqual(fingerprint(input), "recovery-v2|2026-07-31T12:00:00Z|hrv=54.00|hrvBaseline=50.00|hrvHistory=14|rhr=57.00|rhrBaseline=60.00|rhrHistory=14|sleep=77.43|strain=52.00|resp=14.10|respBaseline=14.00|respHistory=14|temp=0.00|spo2=98.00")
    }

    func testMissingCardiovascularInputRemainsUnavailable() {
        var input = baselineInput()
        input.hrvToday = nil
        input.restingHeartRateToday = nil
        let result = RecoveryScoreEngine().calculate(from: input)

        XCTAssertNil(result.value)
        XCTAssertEqual(result.dataCoverage, .unavailable)
        XCTAssertEqual(result.formattedScore, "--")
        XCTAssertTrue(result.missingInputs.contains("hrvToday"))
        XCTAssertTrue(result.missingInputs.contains("restingHeartRateToday"))
    }

    func testSensitivityCasesHaveStableOutputs() {
        let engine = RecoveryScoreEngine()
        let cases: [(String, RecoveryScoreInput, Double)] = [
            ("baseline", baselineInput(), 68.8497077483),
            ("short-sleep-360", replacing(baselineInput(), sleepScoreLastNight: 53.62), 62.8972077483),
            ("high-strain-90", replacing(baselineInput(), strainScoreYesterday: 90), 59.6418762029),
            ("high-temperature", replacing(baselineInput(), bodyTempDelta: 1.0), 60.8497077483),
            ("low-spo2", replacing(baselineInput(), SpO2: 93), 60.8497077483)
        ]

        for (name, input, expected) in cases {
            let result = engine.calculate(from: input)
            XCTAssertEqual(result.value ?? -999, expected, accuracy: 0.0000001, name)
            XCTAssertEqual(result.algorithmVersion, ScoringAlgorithmVersions.recovery, name)
            XCTAssertEqual(result.confidence, .high, name)
            XCTAssertNotNil(result.value, name)
        }
    }

    private func baselineInput() -> RecoveryScoreInput {
        RecoveryScoreInput(
            asOf: asOf,
            hrvToday: 54,
            hrvBaseline: 50,
            hrvHistory: (1...14).map { 48 + Double($0 % 5) },
            restingHeartRateToday: 57,
            restingHeartRateBaseline: 60,
            rhrHistory: (1...14).map { 58 + Double($0 % 3) },
            sleepScoreLastNight: 77.43,
            strainScoreYesterday: 52,
            respiratoryRateToday: 14.1,
            respiratoryRateBaseline: 14,
            respiratoryRateHistory: (1...14).map { 14 + Double($0 % 2) * 0.2 },
            bodyTempDelta: 0,
            SpO2: 98
        )
    }

    private func replacing(
        _ input: RecoveryScoreInput,
        sleepScoreLastNight: Double? = nil,
        strainScoreYesterday: Double? = nil,
        bodyTempDelta: Double? = nil,
        SpO2: Double? = nil
    ) -> RecoveryScoreInput {
        var copy = input
        if let sleepScoreLastNight { copy.sleepScoreLastNight = sleepScoreLastNight }
        if let strainScoreYesterday { copy.strainScoreYesterday = strainScoreYesterday }
        if let bodyTempDelta { copy.bodyTempDelta = bodyTempDelta }
        if let SpO2 { copy.SpO2 = SpO2 }
        return copy
    }

    private func fingerprint(_ input: RecoveryScoreInput) -> String {
        let number: (Double?) -> String = { value in value.map { String(format: "%.2f", $0) } ?? "nil" }
        return "recovery-v2|\(iso8601(input.asOf))|hrv=\(number(input.hrvToday))|hrvBaseline=\(number(input.hrvBaseline))|hrvHistory=\(input.hrvHistory.count)|rhr=\(number(input.restingHeartRateToday))|rhrBaseline=\(number(input.restingHeartRateBaseline))|rhrHistory=\(input.rhrHistory.count)|sleep=\(number(input.sleepScoreLastNight))|strain=\(number(input.strainScoreYesterday))|resp=\(number(input.respiratoryRateToday))|respBaseline=\(number(input.respiratoryRateBaseline))|respHistory=\(input.respiratoryRateHistory.count)|temp=\(number(input.bodyTempDelta))|spo2=\(number(input.SpO2))"
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
