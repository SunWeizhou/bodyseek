import BodySeekCore
import XCTest

final class BevelScoringEngineTests: XCTestCase {

    func testChartSnapshotBuildAllMatchesIndividualSnapshots() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let raw = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 200, calendar: calendar)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: raw,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Parity",
            isAuthorized: true,
            calendar: calendar
        )
        let all = BevelScoringEngine.buildAllChartSnapshots(
            days: snapshot.historyDays,
            referenceDate: now,
            calendar: calendar
        )
        for horizon in TrendHorizon.allCases {
            for kind in MetricKind.allCases {
                let single = BevelScoringEngine.buildChartSeriesSnapshot(
                    for: kind,
                    horizon: horizon,
                    days: snapshot.historyDays,
                    referenceDate: now,
                    calendar: calendar
                )
                XCTAssertEqual(all[horizon]?[kind], single, "parity mismatch \(kind)/\(horizon)")
            }
        }
    }


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
        let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        let now = calendar.date(bySettingHour: 22, minute: 30, second: 0, of: dayStart) ?? dayStart
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

    func testSevenDaysOnlyKeepsACWRInsufficientWithoutPriorBaseline() {
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        let now = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: dayStart) ?? dayStart
        let raw7 = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            return DailyRawMetrics(date: date, activeEnergyKcal: 437, hasAuthorizedHealthData: true)
        }
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: raw7,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "7d-only",
            isAuthorized: true,
            calendar: calendar
        )
        XCTAssertNil(snapshot.trainingLoad.acwrRatio)
        XCTAssertEqual(snapshot.trainingLoad.zone, .insufficientData)
        XCTAssertEqual(snapshot.trainingLoad.acuteCoveredDays, 7)
        XCTAssertEqual(snapshot.trainingLoad.priorBaselineDays, 0)
    }

    func testMorningIntradayTimelinesDoNotGenerateFutureHours() {
        let calendar = Calendar(identifier: .gregorian)
        let dayStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart)!
        let raw = PreviewSeedFactory.makeRawWindow(endingAt: morning, days: 14, calendar: calendar)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: raw,
            sleepGoalMinutes: 450,
            referenceDate: morning,
            sourceLabel: "09:00",
            isAuthorized: true,
            calendar: calendar
        )
        XCTAssertTrue(snapshot.today.energyCurve.allSatisfy { $0.hour <= 9 })
        XCTAssertTrue(snapshot.today.stressTimeline.allSatisfy { $0.hour <= 8 })
    }

    func testScoreV2VersionContributorsAndDeterministicReplay() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        let raw = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 45, calendar: calendar)

        let first = BevelScoringEngine.computeWindow(
            rawDays: raw,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Test",
            isAuthorized: true,
            calendar: calendar
        )
        let second = BevelScoringEngine.computeWindow(
            rawDays: raw,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Test",
            isAuthorized: true,
            calendar: calendar
        )

        XCTAssertEqual(first.scoreAlgorithmVersion, .scoreV2)
        XCTAssertEqual(first.today.algorithmVersion, .scoreV2)
        XCTAssertEqual(first.today.recovery.algorithmVersion, .scoreV2)
        XCTAssertEqual(first.today.sleep.algorithmVersion, .scoreV2)
        XCTAssertEqual(first.today.strain.algorithmVersion, .scoreV2)
        XCTAssertEqual(first.today.stress.algorithmVersion, .scoreV2)
        XCTAssertEqual(first.today.energy.algorithmVersion, .scoreV2)

        XCTAssertFalse(first.today.recovery.contributors.isEmpty)
        XCTAssertFalse(first.today.sleep.contributors.isEmpty)
        XCTAssertFalse(first.today.strain.contributors.isEmpty)
        XCTAssertFalse(first.today.stress.contributors.isEmpty)
        XCTAssertFalse(first.today.energy.contributors.isEmpty)

        XCTAssertEqual(first.historyDays, second.historyDays)
        XCTAssertEqual(first.trainingLoad, second.trainingLoad)
    }

    func testIncrementalRecomputeMatchesFullComputeAnd3YearCapsules() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_763_500_000))
        let baseRaw = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 180, calendar: calendar)

        let baselineSnap = BevelScoringEngine.computeWindow(
            rawDays: baseRaw,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Base",
            isAuthorized: true,
            calendar: calendar
        )

        // Mutate 2 days in the middle and mark only those 2 dayKeys dirty.
        var mutatedRaw = baseRaw
        let idx1 = 60
        let idx2 = 120
        mutatedRaw[idx1].hrvMs = 32
        mutatedRaw[idx1].sleepAsleepMinutes = 290
        mutatedRaw[idx2].hrvMs = 95
        mutatedRaw[idx2].restingHeartRateBpm = 48

        let dirtyKeys: Set<DayKey> = [
            try XCTUnwrap(mutatedRaw[idx1].dayKey),
            try XCTUnwrap(mutatedRaw[idx2].dayKey),
        ]
        let existingByKey = Dictionary(
            uniqueKeysWithValues: baselineSnap.historyDays.map { ($0.dayKey, $0) }
        )

        let incrementalSnap = BevelScoringEngine.recomputeIncremental(
            existingByDayKey: existingByKey,
            allRawDays: mutatedRaw,
            dirtyDayKeys: dirtyKeys,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Inc",
            isAuthorized: true,
            calendar: calendar
        )

        let fullSnap = BevelScoringEngine.computeWindow(
            rawDays: mutatedRaw,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Full",
            isAuthorized: true,
            calendar: calendar
        )

        XCTAssertEqual(incrementalSnap.historyDays, fullSnap.historyDays)
        XCTAssertEqual(incrementalSnap.trainingLoad, fullSnap.trainingLoad)

        // Pre-mutation days (< idx1) stay untouched vs baselineSnap (causal zero future leakage).
        XCTAssertEqual(incrementalSnap.historyDays[idx1 - 1], baselineSnap.historyDays[idx1 - 1])

        // 6m weekly capsules & 3y monthly capsules + TrendHorizon.threeYears == 1095
        XCTAssertEqual(TrendHorizon.threeYears.dayCount, 1095)
        let sixMonthChart = BevelScoringEngine.buildChartSeriesSnapshot(
            for: .recovery,
            horizon: .sixMonths,
            days: fullSnap.historyDays,
            referenceDate: now,
            calendar: calendar
        )
        XCTAssertFalse(sixMonthChart.capsules.isEmpty)
        XCTAssertEqual(sixMonthChart.totalDays, 180)

        // 7 天按日胶囊与 30 天按周胶囊（趋势页统一胶囊视觉）。
        let weekChart = BevelScoringEngine.buildChartSeriesSnapshot(
            for: .recovery,
            horizon: .week,
            days: fullSnap.historyDays,
            referenceDate: now,
            calendar: calendar
        )
        XCTAssertEqual(weekChart.totalDays, 7)
        XCTAssertEqual(weekChart.capsules.count, 7)
        XCTAssertTrue(weekChart.capsules.allSatisfy { $0.p25 == $0.p75 && $0.sampleCount == 1 })

        let monthChart = BevelScoringEngine.buildChartSeriesSnapshot(
            for: .recovery,
            horizon: .month,
            days: fullSnap.historyDays,
            referenceDate: now,
            calendar: calendar
        )
        XCTAssertEqual(monthChart.totalDays, 30)
        XCTAssertGreaterThanOrEqual(monthChart.capsules.count, 4)
        XCTAssertTrue(monthChart.capsules.allSatisfy { $0.totalDays >= 2 })

        let threeYearRaw = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 1095, calendar: calendar)
        let threeYearSnap = BevelScoringEngine.computeWindow(
            rawDays: threeYearRaw,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "3Y",
            isAuthorized: true,
            calendar: calendar
        )
        let threeYearChart = BevelScoringEngine.buildChartSeriesSnapshot(
            for: .recovery,
            horizon: .threeYears,
            days: threeYearSnap.historyDays,
            referenceDate: now,
            calendar: calendar
        )
        XCTAssertEqual(threeYearChart.totalDays, 1095)
        XCTAssertGreaterThanOrEqual(threeYearChart.capsules.count, 35)
    }
}
