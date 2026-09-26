import Foundation
import XCTest
@testable import BodySeekDomain

/// ARCH-08 release evidence for the sleep-only replay slice.
///
/// These cases intentionally exercise the v2.1.0 evidence contract without
/// changing it. The canonical input text is also the replay fingerprint
/// recorded in `docs/baselines/sleep-replay-fixtures.json`.
final class SleepReplaySensitivityTests: XCTestCase {
    private lazy var asOf = date("2026-07-31T12:00:00Z")
    private lazy var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testBaselineReplayIdentityAndFingerprint() throws {
        let input = baselineInput()
        let result = SleepScoreEngine(calendar: calendar).calculate(from: input)

        XCTAssertEqual(result.value ?? -1, 77.43, accuracy: 0.01)
        XCTAssertEqual(result.algorithmVersion, ScoringAlgorithmVersions.sleep)
        XCTAssertEqual(result.confidence, .low)
        XCTAssertEqual(result.missingInputs, ["remMinutes", "deepMinutes", "todayBedtime", "recentBedtimesHistory"])
        XCTAssertEqual(result.components["duration"] ?? -1, 50, accuracy: 0.0001)
        XCTAssertEqual(result.components["interruption"] ?? -1, 4.2, accuracy: 0.0001)
        XCTAssertEqual(replayFingerprint(input), "sleep-v2|2026-07-31T12:00:00Z|465.0|450.0|awake=24.0|episodes=2|bedtime=nil|history=0")
    }

    func testMissingSleepInputRemainsUnavailableWithExplicitReason() {
        var input = baselineInput()
        input.totalSleepMinutes = nil
        let result = SleepScoreEngine(calendar: calendar).calculate(from: input)

        XCTAssertNil(result.value)
        XCTAssertEqual(result.dataCoverage, .unavailable)
        XCTAssertEqual(result.confidence, .low)
        XCTAssertEqual(result.missingInputs, ["totalSleepMinutes"])
        XCTAssertEqual(result.formattedScore, "--")
    }

    func testSensitivityCasesHaveExactOutputs() {
        let engine = SleepScoreEngine(calendar: calendar)
        let cases: [(String, SleepScoreInput, Double?, MetricConfidence, [String])] = [
            ("baseline", baselineInput(), 77.43, .low, ["remMinutes", "deepMinutes", "todayBedtime", "recentBedtimesHistory"]),
            ("short-sleep-360", replacing(baselineInput(), totalSleepMinutes: 360), 53.62, .low, ["remMinutes", "deepMinutes", "todayBedtime", "recentBedtimesHistory"]),
            ("no-awake-time", replacing(baselineInput(), awakeMinutes: 0, awakeEpisodeCount: 0), 79.0, .low, ["remMinutes", "deepMinutes", "todayBedtime", "recentBedtimesHistory"]),
            ("missing-awake-time", missingAwakeInput(), 79.0, .low, ["inBedMinutes", "remMinutes", "deepMinutes", "awakeEpisodeCount", "todayBedtime", "recentBedtimesHistory", "awakeMinutes"]),
            ("five-bedtime-history", replacing(baselineInput(), todayBedtime: date("2026-07-30T23:15:00Z"), recentBedtimes: bedtimeHistory()), 84.2, .medium, ["remMinutes", "deepMinutes"])
        ]

        for (name, input, expected, confidence, missing) in cases {
            let result = engine.calculate(from: input)
            if let expected {
                XCTAssertEqual(result.value ?? -1, expected, accuracy: 0.01, name)
            } else {
                XCTAssertNil(result.value, name)
            }
            XCTAssertEqual(result.confidence, confidence, name)
            XCTAssertEqual(result.missingInputs, missing, name)
        }
    }

    func testInjectedCalendarKeepsLocalBedtimeConsistentAcrossDaylightSaving() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let history = (28...31).map { date("2026-10-\($0)T06:30:00Z") }
            + [date("2026-11-01T06:30:00Z")]
        let input = SleepScoreInput(
            asOf: date("2026-11-02T20:00:00Z"),
            totalSleepMinutes: 450,
            todayBedtime: date("2026-11-02T07:30:00Z"),
            recentBedtimes: history,
            awakeMinutes: 0,
            awakeEpisodeCount: 0
        )
        let result = SleepScoreEngine(calendar: losAngeles).calculate(from: input)
        XCTAssertEqual(result.components["consistency"], 30, "All six bedtimes are 23:30 in the supplied calendar")
        XCTAssertEqual(result.value ?? -1, 100, accuracy: 0.000_001)
        XCTAssertEqual(result.dataWindow.duration, 313 * 3_600, accuracy: 0.000_001, "Thirteen local calendar days span the fall clock change")
    }

    func testInjectedUTCCalendarKeepsBedtimesNearMidnightAdjacent() {
        let input = SleepScoreInput(
            asOf: asOf,
            totalSleepMinutes: 450,
            todayBedtime: date("2026-07-31T00:30:00Z"),
            recentBedtimes: (25...29).map { date("2026-07-\($0)T23:30:00Z") },
            awakeMinutes: 0,
            awakeEpisodeCount: 0
        )
        let result = SleepScoreEngine(calendar: calendar).calculate(from: input)
        XCTAssertEqual(result.components["consistency"], 24, "Across midnight, 23:30 to 00:30 is a one-hour shift")
        XCTAssertEqual(result.value ?? -1, 94, accuracy: 0.000_001)
    }

    func testFacadeExcludesBedtimesOutsideThirteenCalendarDays() {
        let day = date("2026-09-22T00:00:00Z")
        let bedtime = day.addingTimeInterval(-3_600)
        let history = [14, 21, 28, 35, 42].map { offset -> DailyHealthSnapshot in
            var snapshot = DailyHealthSnapshot(date: calendar.date(byAdding: .day, value: -offset, to: day)!)
            snapshot.bedtime = calendar.date(byAdding: .day, value: -offset, to: bedtime)!
            return snapshot
        }
        var today = DailyHealthSnapshot(date: day)
        today.sleepHours = 7.5
        today.bedtime = bedtime
        today.awakeMinutes = 0
        today.awakeEpisodeCount = 0
        let sleep = DailyHealthComputation(
            calendar: calendar,
            now: day.addingTimeInterval(12 * 3_600),
            profile: DailyHealthComputationProfile(sleepTargetMinutes: 450)
        ).compute(for: today, history: history).sleep
        XCTAssertNil(sleep.components["consistency"])
        XCTAssertEqual(sleep.value ?? -1, 79, accuracy: 0.000_001)
    }

    private func baselineInput() -> SleepScoreInput {
        SleepScoreInput(
            asOf: asOf,
            totalSleepMinutes: 465,
            sleepTargetMinutes: 450,
            awakeMinutes: 24,
            awakeEpisodeCount: 2
        )
    }

    private func replacing(
        _ input: SleepScoreInput,
        totalSleepMinutes: Double? = nil,
        awakeMinutes: Double? = nil,
        awakeEpisodeCount: Int? = nil,
        todayBedtime: Date? = nil,
        recentBedtimes: [Date]? = nil
    ) -> SleepScoreInput {
        var copy = input
        if let totalSleepMinutes { copy.totalSleepMinutes = totalSleepMinutes }
        if let awakeMinutes { copy.awakeMinutes = awakeMinutes }
        if let awakeEpisodeCount { copy.awakeEpisodeCount = awakeEpisodeCount }
        if let todayBedtime { copy.todayBedtime = todayBedtime }
        if let recentBedtimes { copy.recentBedtimes = recentBedtimes }
        return copy
    }

    private func bedtimeHistory() -> [Date] {
        (1...5).map { date("2026-07-30T23:15:00Z").addingTimeInterval(Double(-$0 + 1) * 86_400) }
    }

    private func missingAwakeInput() -> SleepScoreInput {
        var input = baselineInput()
        input.awakeMinutes = nil
        input.awakeEpisodeCount = nil
        return input
    }

    private func replayFingerprint(_ input: SleepScoreInput) -> String {
        let bedtime = input.todayBedtime.map(iso8601) ?? "nil"
        let total = input.totalSleepMinutes.map { String($0) } ?? "nil"
        let awake = input.awakeMinutes.map { String($0) } ?? "nil"
        let episodes = input.awakeEpisodeCount.map { String($0) } ?? "nil"
        return "sleep-v2|\(iso8601(input.asOf))|\(total)|\(input.sleepTargetMinutes)|awake=\(awake)|episodes=\(episodes)|bedtime=\(bedtime)|history=\(input.recentBedtimes.count)"
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
