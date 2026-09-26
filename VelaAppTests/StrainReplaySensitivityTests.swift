import Foundation
import XCTest
@testable import Vela

/// ARCH-08 evidence for Strain while its engine remains app-target only.
///
/// These tests deliberately call the existing Vela oracle directly. They are
/// replay evidence, not a portable BodySeekDomain implementation, and must
/// not change the Strain formula.
final class StrainReplaySensitivityTests: XCTestCase {
    private let asOf: Date = ISO8601DateFormatter().date(from: "2026-07-31T12:00:00Z")!

    func testBaselineReplayIdentityAndFingerprint() {
        let input = baselineInput()
        let result = StrainScoreEngine().calculate(from: input)
        XCTAssertEqual(result.value ?? -999, 65.5297799653, accuracy: 0.0000001)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.dataCoverage, .complete)
        XCTAssertEqual(result.missingInputs, [])
        XCTAssertEqual(result.algorithmVersion, ScoringAlgorithmVersions.strain)
        XCTAssertEqual(fingerprint(input), "strain-v2|2026-07-31T12:00:00Z|workouts=1|duration=45.00|avgHR=145.00|samples=|rpe=6.00|energy=500.00|exercise=45.00|steps=8000.00|rhr=60.00|maxHR=190.00|sex=male|history=28")
        XCTAssertEqual(result.components["workout_load"] ?? -1, 66.0807056951, accuracy: 0.0000001)
        XCTAssertEqual(result.components["activity_load"] ?? -1, 15.575, accuracy: 0.0000001)
        XCTAssertEqual(result.components["daily_load"] ?? -1, 81.6557056951, accuracy: 0.0000001)
    }

    func testSensitivityCasesHaveStableOutputs() {
        let engine = StrainScoreEngine()
        let cases: [(String, StrainScoreInput, Double)] = [
            ("short-workout-20", replacing(baselineInput(), workoutDurationMinutes: 20), 44.3578249751),
            ("high-energy-900", replacing(baselineInput(), activeEnergyToday: 900), 66.7659808416),
            ("high-rpe-9", replacing(baselineInput(), rpe: 9), 83.2694664989)
        ]
        for (name, input, expected) in cases {
            let result = engine.calculate(from: input)
            XCTAssertEqual(result.value ?? -999, expected, accuracy: 0.0000001, name)
            XCTAssertEqual(result.confidence, .high, name)
            XCTAssertEqual(result.missingInputs, [], name)
            XCTAssertEqual(result.algorithmVersion, ScoringAlgorithmVersions.strain, name)
        }
    }

    func testMissingActivityRemainsUnavailable() {
        let result = StrainScoreEngine().calculate(from: missingActivityInput())
        XCTAssertNil(result.value)
        XCTAssertEqual(result.dataCoverage, .unavailable)
        XCTAssertEqual(result.confidence, .low)
        XCTAssertEqual(result.formattedScore, "--")
        XCTAssertEqual(result.missingInputs, ["workouts", "activeEnergyToday", "exerciseMinutesToday", "stepCount"])
        XCTAssertEqual(result.algorithmVersion, ScoringAlgorithmVersions.strain)
    }

    func testMissingActivityDoesNotPublishLoadOrTrainingStatusWithHistory() {
        var input = missingActivityInput()
        input.last28DaysDailyLoads = Array(repeating: 60, count: 28)
        let result = StrainScoreEngine().calculate(from: input)
        XCTAssertNil(result.value)
        XCTAssertNil(result.components["daily_load"])
        XCTAssertNil(result.components["training_load_ratio"])
        XCTAssertEqual(result.trainingLoadStatus, .unknown)
    }

    private func baselineInput() -> StrainScoreInput {
        StrainScoreInput(
            asOf: asOf,
            workouts: [WorkoutInput(durationMinutes: 45, averageHeartRate: 145, rpe: 6)],
            activeEnergyToday: 500,
            exerciseMinutesToday: 45,
            stepCount: 8_000,
            restingHR: 60,
            maxHR: 190,
            biologicalSex: "male",
            last28DaysDailyLoads: (1...28).map { 55 + Double($0 % 6) },
            recoveryScore: 72
        )
    }

    private func replacing(
        _ input: StrainScoreInput,
        workoutDurationMinutes: Double? = nil,
        activeEnergyToday: Double? = nil,
        rpe: Double? = nil
    ) -> StrainScoreInput {
        var copy = input
        if let workoutDurationMinutes { copy.workouts[0].durationMinutes = workoutDurationMinutes }
        if let activeEnergyToday { copy.activeEnergyToday = activeEnergyToday }
        if let rpe { copy.workouts[0].averageHeartRate = nil; copy.workouts[0].rpe = rpe }
        return copy
    }

    private func missingActivityInput() -> StrainScoreInput {
        StrainScoreInput(asOf: asOf, restingHR: 60, maxHR: 190, biologicalSex: "male")
    }

    private func fingerprint(_ input: StrainScoreInput) -> String {
        let number: (Double?) -> String = { value in value.map { String(format: "%.2f", $0) } ?? "nil" }
        let workout = input.workouts.first
        let samples = workout?.heartRateSamples.map { String(format: "%.1f", $0) }.joined(separator: ",") ?? ""
        return "strain-v2|\(iso8601(input.asOf))|workouts=\(input.workouts.count)|duration=\(number(workout?.durationMinutes))|avgHR=\(number(workout?.averageHeartRate))|samples=\(samples)|rpe=\(number(workout?.rpe))|energy=\(number(input.activeEnergyToday))|exercise=\(number(input.exerciseMinutesToday))|steps=\(number(input.stepCount))|rhr=\(number(input.restingHR))|maxHR=\(number(input.maxHR))|sex=\(input.biologicalSex ?? "nil")|history=\(input.last28DaysDailyLoads.count)"
    }

    private func formatted(_ value: Double?) -> String {
        value.map { String(format: "%.10f", $0) } ?? "nil"
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
