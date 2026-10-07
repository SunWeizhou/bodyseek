import Foundation
import XCTest
@testable import BodySeekDomain

final class GoldenReplayTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testSleepGoldenFixtureMatchesVelaOracle() {
        // This is a complete mirror of the PR0 Vela golden fixture, including
        // its 14 historical snapshots. The package currently consumes only
        // the sleep fields; retaining every field here prevents a partial
        // fixture from being mistaken for a complete parity replay.
        let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31))!
        let asOf = day.addingTimeInterval(12 * 3_600)
        let history = (1...14).map { offset -> DailyHealthSnapshot in
            var item = DailyHealthSnapshot(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", offset))!,
                date: calendar.date(byAdding: .day, value: -offset, to: day)!
            )
            item.hrvAverage = 48 + Double(offset % 5)
            item.restingHeartRate = 58 + Double(offset % 3)
            item.respiratoryRate = 14 + Double(offset % 2) * 0.2
            item.sleepHours = 7.2 + Double(offset % 4) * 0.1
            item.wristTemperature = 36.35 + Double(offset % 3) * 0.02
            item.dailyLoad = 44 + Double(offset % 6) * 3
            item.strainScore = 52 + Double(offset % 5)
            return item
        }
        var snapshot = DailyHealthSnapshot(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            date: day
        )
        snapshot.hrvAverage = 54
        snapshot.restingHeartRate = 57
        snapshot.respiratoryRate = 14.1
        snapshot.sleepHours = 7.75
        snapshot.bedtime = day.addingTimeInterval(-45 * 60)
        snapshot.wakeTime = day.addingTimeInterval(7 * 3_600)
        snapshot.awakeMinutes = 24
        snapshot.awakeEpisodeCount = 2
        snapshot.deepSleepMinutes = 92
        snapshot.remSleepMinutes = 108
        snapshot.wristTemperature = 36.4
        snapshot.oxygenSaturation = 98 // Normalized snapshot percentage, matching the production oracle.
        snapshot.steps = 8_400
        snapshot.activeCalories = 460
        snapshot.activeMinutes = 42
        snapshot.workouts = [
            WorkoutSummary(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000016")!,
                start: day.addingTimeInterval(9 * 3_600),
                end: day.addingTimeInterval(9.75 * 3_600),
                activityName: "Strength Training",
                averageHeartRate: 132,
                source: "fixture",
                rpe: 7
            )
        ]
        let profile = DailyHealthComputationProfile(
            sleepTargetMinutes: 450,
            maxHeartRate: 190,
            biologicalSex: "other"
        )
        let result = DailyHealthComputation(calendar: calendar, now: asOf, profile: profile)
            .compute(for: snapshot, history: history)

        XCTAssertEqual(result.sleep.value ?? -1, 77.43, accuracy: 0.01)
        XCTAssertEqual(result.sleep.algorithmVersion, ScoringAlgorithmVersions.sleep)
        XCTAssertEqual(result.sleep.components["duration"] ?? -1, 50, accuracy: 0.0001)
        XCTAssertEqual(result.sleep.components["interruption"] ?? -1, 4.2, accuracy: 0.0001)
        XCTAssertEqual(result.sleep.confidence, MetricConfidence.low)
        XCTAssertTrue(result.recovery.value == nil)
        XCTAssertTrue(result.strain.value == nil)
        XCTAssertTrue(result.physiologicalStress.value == nil)
        XCTAssertTrue(result.energy.value == nil)
        XCTAssertFalse(result.allMetrics.contains { $0.value != nil && $0.domain != ScoredHealthDomain.sleep })
        XCTAssertEqual(result.recovery.algorithmVersion, ScoringAlgorithmVersions.recovery)
        XCTAssertEqual(result.strain.algorithmVersion, ScoringAlgorithmVersions.strain)
        XCTAssertEqual(result.physiologicalStress.algorithmVersion, ScoringAlgorithmVersions.physiologicalStress)
        XCTAssertEqual(result.energy.algorithmVersion, ScoringAlgorithmVersions.energy)
    }

    func testEmptySnapshotPreservesUnavailableSemantics() {
        let snapshot = DailyHealthSnapshot(date: date("2026-07-31T00:00:00Z"))
        let result = DailyHealthComputation(
            calendar: calendar,
            now: date("2026-07-31T12:00:00Z"),
            profile: DailyHealthComputationProfile(sleepTargetMinutes: 450)
        ).compute(for: snapshot, history: [])

        for metric in result.allMetrics {
            XCTAssertNil(metric.value, metric.domain.rawValue)
            XCTAssertNil(metric.score, metric.domain.rawValue)
            XCTAssertNil(metric.morningEnergy, metric.domain.rawValue)
            XCTAssertNil(metric.currentEnergy, metric.domain.rawValue)
            XCTAssertNil(metric.stressIndex, metric.domain.rawValue)
            XCTAssertNil(metric.state, metric.domain.rawValue)
            XCTAssertNil(metric.status, metric.domain.rawValue)
            XCTAssertNil(metric.recommendedRange, metric.domain.rawValue)
            XCTAssertNil(metric.targetStatus, metric.domain.rawValue)
            XCTAssertFalse(metric.hasData)
            XCTAssertEqual(metric.formattedScore, "--")
            XCTAssertEqual(metric.dataCoverage, .unavailable)
        }
    }

    func testMetricResultCodableRoundTripKeepsMissingValue() throws {
        let input = MetricResult(
            domain: .sleep,
            name: "Sleep Score",
            value: nil,
            band: .low,
            confidence: .low,
            reasons: ["missing"],
            missingInputs: ["totalSleepMinutes"],
            dataWindow: DateInterval(start: date("2026-07-31T00:00:00Z"), end: date("2026-07-31T12:00:00Z")),
            source: .healthKit,
            algorithmVersion: ScoringAlgorithmVersions.sleep,
            lastUpdated: date("2026-07-31T12:00:00Z")
        )
        let data = try JSONEncoder().encode(input)
        let output = try JSONDecoder().decode(MetricResult.self, from: data)
        XCTAssertNil(output.value)
        XCTAssertEqual(output, input)
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: value)!
    }
}
