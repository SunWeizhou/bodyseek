import BodySeekCore
import XCTest

final class BevelScoringEngineTests: XCTestCase {
    func testEmptyWindowMarksAllMetricsMissingNeverZero() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeEmptyRawWindow(endingAt: now),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "未授权",
            isAuthorized: false
        )

        XCTAssertNil(snapshot.today.recovery.value)
        XCTAssertNil(snapshot.today.sleep.value)
        XCTAssertNil(snapshot.today.strain.value)
        XCTAssertNil(snapshot.today.stress.value)
        XCTAssertNil(snapshot.today.energy.value)
        XCTAssertFalse(snapshot.today.recovery.availability.isAvailable)
        XCTAssertEqual(snapshot.today.recovery.formattedScore, "--")
    }

    func testAuthorizedRestDayProducesKnownZeroStrain() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let restDay = DailyRawMetrics(
            date: now,
            hrvMs: 62,
            restingHeartRateBpm: 56,
            activeEnergyKcal: 0,
            exerciseMinutes: 0,
            steps: 20,
            workouts: [],
            hasAuthorizedHealthData: true
        )
        let computed = BevelScoringEngine.scoreDay(restDay, priorDays: [], sleepGoalMinutes: 450)
        XCTAssertEqual(computed.strain.value, 0)
        if case .knownZero = computed.strain.availability {
            // Expected
        } else {
            XCTFail("Expected knownZero strain when authorized with zero activity")
        }
    }

    func testRollingBaselineDoesNotLeakFutureDays() {
        let calendar = Calendar(identifier: .gregorian)
        let baseDate = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))

        var windowA: [DailyRawMetrics] = []
        var windowB: [DailyRawMetrics] = []

        for offset in 0..<20 {
            let day = calendar.date(byAdding: .day, value: offset, to: baseDate)!
            let hrvA = 55.0 + Double(offset % 3) * 2.0
            let hrvB = offset >= 15 ? 120.0 : hrvA
            windowA.append(DailyRawMetrics(date: day, hrvMs: hrvA, restingHeartRateBpm: 58, sleepAsleepMinutes: 440))
            windowB.append(DailyRawMetrics(date: day, hrvMs: hrvB, restingHeartRateBpm: 58, sleepAsleepMinutes: 440))
        }

        let snapA = BevelScoringEngine.computeWindow(
            rawDays: windowA,
            sleepGoalMinutes: 450,
            referenceDate: calendar.date(byAdding: .day, value: 19, to: baseDate)!,
            sourceLabel: "Test",
            isAuthorized: true,
            calendar: calendar
        )
        let snapB = BevelScoringEngine.computeWindow(
            rawDays: windowB,
            sleepGoalMinutes: 450,
            referenceDate: calendar.date(byAdding: .day, value: 19, to: baseDate)!,
            sourceLabel: "Test",
            isAuthorized: true,
            calendar: calendar
        )

        // Day 10 must remain bit-for-bit identical regardless of future day 15-19 changes.
        XCTAssertEqual(snapA.historyDays[10].recovery, snapB.historyDays[10].recovery)
        XCTAssertNotEqual(snapA.historyDays[16].recovery, snapB.historyDays[16].recovery)
    }

    func testPreviewSeedFactoryAndTrendCoverageWithGaps() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        let raw = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 45, calendar: calendar)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: raw,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "示例数据",
            isAuthorized: true,
            calendar: calendar
        )

        XCTAssertNotNil(snapshot.today.recovery.value)
        XCTAssertNotNil(snapshot.today.sleep.value)
        XCTAssertNotNil(snapshot.today.strain.value)
        XCTAssertNotNil(snapshot.today.stress.value)
        XCTAssertNotNil(snapshot.today.energy.value)
        XCTAssertNil(snapshot.today.raw.oxygenSaturationPct)

        let series = BevelScoringEngine.trendSeries(
            for: .recovery,
            horizon: .month,
            days: snapshot.historyDays,
            referenceDate: now,
            calendar: calendar
        )
        XCTAssertEqual(series.totalDays, 30)
        // Preview seed omits offsets -12 and -13 intentionally
        XCTAssertEqual(series.coveredDays, 28)
        XCTAssertNotNil(series.baselineRange)

        XCTAssertNotNil(snapshot.trainingLoad.acwrRatio)
        XCTAssertEqual(snapshot.today.energyCurve.count, 11)
        XCTAssertEqual(snapshot.today.stressTimeline.count, 12)
    }

    func testInsufficientHistoryKeepsACWRInInsufficientZone() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 4),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Test",
            isAuthorized: true
        )
        XCTAssertNil(snapshot.trainingLoad.acwrRatio)
        XCTAssertEqual(snapshot.trainingLoad.zone, .insufficientData)
    }
}
