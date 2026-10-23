import Foundation
import XCTest
@testable import BodySeekDomain

/// Package replay for Energy after the engine moved out of the app.
/// The numeric oracle is `docs/baselines/energy-replay-fixtures.json`.
final class EnergyReplaySensitivityTests: XCTestCase {
    private let asOf: Date = ISO8601DateFormatter().date(from: "2026-07-31T12:00:00Z")!

    func testBaselineReplayIdentityAndFingerprint() {
        let result = EnergyBankEngine().calculate(from: baselineInput())
        XCTAssertEqual(result.value ?? -999, 53.2, accuracy: 0.0000001)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.missingInputs, [])
        XCTAssertEqual(result.algorithmVersion, ScoringAlgorithmVersions.energy)
        XCTAssertEqual(result.components["morningEnergy"] ?? -1, 80.7, accuracy: 0.0000001)
        XCTAssertEqual(result.components["atl"] ?? -1, 58.75, accuracy: 0.0000001)
        XCTAssertEqual(result.components["ctl"] ?? -1, 59.7674418605, accuracy: 0.0000001)
        XCTAssertEqual(result.components["tsb"] ?? -1, 1.0174418605, accuracy: 0.0000001)
        XCTAssertEqual(result.components["acwr"] ?? -1, 0.9848265896, accuracy: 0.0000001)
        XCTAssertEqual(fingerprint(baselineInput()), "energy-v2|2026-07-31T12:00:00Z|recovery=70.00|sleep=80.00|strain=40.00|stress=30.00|hrv=50.00/50.00|rhr=58.00/60.00|history=14|today=55.00|temp=0.20|hours=8.00|rrz=0.20|spo2=98.00|load=nil")
    }

    func testSensitivityCasesHaveStableOutputs() {
        let engine = EnergyBankEngine()
        let cases: [(String, EnergyBankInput, Double)] = [
            ("high-strain-80", replacing(baselineInput(), strainScore: 80), 39.2),
            ("elevated-load", replacing(baselineInput(), trainingLoadStatus: .elevated), 48.2)
        ]
        for (name, input, expected) in cases {
            let result = engine.calculate(from: input)
            XCTAssertEqual(result.value ?? -999, expected, accuracy: 0.0000001, name)
            XCTAssertEqual(result.algorithmVersion, ScoringAlgorithmVersions.energy, name)
        }
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
        XCTAssertEqual(result.dataCoverage, .unavailable)
        XCTAssertEqual(result.confidence, .low)
        XCTAssertEqual(result.formattedScore, "--")
        XCTAssertTrue(result.missingInputs.contains("recoveryScore"))
        XCTAssertTrue(result.missingInputs.contains("sleepScore"))
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

    private func replacing(
        _ input: EnergyBankInput,
        strainScore: Double? = nil,
        trainingLoadStatus: TrainingLoadStatus? = nil
    ) -> EnergyBankInput {
        var copy = input
        if let strainScore { copy.strainScore = strainScore }
        if let trainingLoadStatus { copy.trainingLoadStatus = trainingLoadStatus }
        return copy
    }

    private func fingerprint(_ input: EnergyBankInput) -> String {
        let number: (Double?) -> String = { value in value.map { String(format: "%.2f", $0) } ?? "nil" }
        let status = input.trainingLoadStatus?.rawValue ?? "nil"
        return "energy-v2|\(iso8601(input.asOf))|recovery=\(number(input.recoveryScore))|sleep=\(number(input.sleepScore))|strain=\(number(input.strainScore))|stress=\(number(input.stressIndex))|hrv=\(number(input.hrvToday))/\(number(input.hrvBaseline))|rhr=\(number(input.rhrToday))/\(number(input.rhrBaseline))|history=\(input.strainHistory?.count ?? 0)|today=\(number(input.todayLoad))|temp=\(number(input.bodyTempDelta))|hours=\(number(input.hoursSinceWake))|rrz=\(number(input.respiratoryRateZ))|spo2=\(number(input.SpO2))|load=\(status)"
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
