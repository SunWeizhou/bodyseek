import BodySeekCore
import BodySeekHealth
import BodySeekStore
import Foundation
import XCTest

final class SyncEngineTests: XCTestCase {
    func testAnchoredWorkoutDeletionInvalidatesDayAndPreventsStaleSnapshotReimport() async throws {
        let database = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: database)
        let time = Date(timeIntervalSince1970: 1_790_000_000)
        let removed = StoredWorkoutRecord(hkUUID: UUID().uuidString, type: "跑步", start: time, end: time, energy: 100)
        let kept = StoredWorkoutRecord(hkUUID: UUID().uuidString, type: "手动", start: time, end: time, energy: 50)
        try await repo.upsertWorkouts([removed, kept])
        let batch = SyncBatch(deletedWorkoutUUIDs: [removed.hkUUID], nextAnchorData: Data([1]))
        let engine = SyncEngine(repository: repo, source: MockHealthKitSyncSource(recentBatch: batch))
        let first = try await engine.syncRecentWindow(referenceDate: time)
        let retry = try await engine.syncRecentWindow(referenceDate: time)
        try await repo.upsertWorkouts([removed])
        let records = try await repo.loadWorkouts()
        XCTAssertEqual(first.syncedDayKeys, [time.physiologicalDayKey()])
        XCTAssertEqual(retry.syncedDayKeys, first.syncedDayKeys)
        XCTAssertEqual(records.map(\.hkUUID), [kept.hkUUID])
    }

    func testRecentSyncPersistsAnchorMergesSleepAndSeparatesWorkoutEffort() async throws {
        let db = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: db)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))

        let dayKey = DayKey(year: 2026, month: 11, day: 19)
        let morningWake = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 7, minute: 0)))
        let nightStart = morningWake.addingTimeInterval(-8 * 3600)

        let watchSource = SourceRef(bundleIdentifier: "com.apple.health", name: "Apple Watch", deviceModel: "Watch7,1", priority: 100)
        let autoSleepSource = SourceRef(bundleIdentifier: "com.tantsissa.AutoSleep", name: "AutoSleep", deviceModel: "iPhone17,1", priority: 60)
        let workoutUUID = UUID().uuidString

        let batch = SyncBatch(
            dayMetrics: [
                DayMetricRecord(dayKey: dayKey, metric: DayMetricField.hrvMs.rawValue, value: 66.0, state: .available, sources: [watchSource]),
                DayMetricRecord(dayKey: dayKey, metric: DayMetricField.restingHeartRateBpm.rawValue, value: 54.0, state: .available, sources: [watchSource]),
                DayMetricRecord(dayKey: dayKey, metric: DayMetricField.activeEnergyKcal.rawValue, value: 490.0, state: .available, sources: [watchSource]),
                DayMetricRecord(dayKey: dayKey, metric: DayMetricField.exerciseMinutes.rawValue, value: 45.0, state: .available, sources: [watchSource]),
                DayMetricRecord(dayKey: dayKey, metric: DayMetricField.steps.rawValue, value: 8400.0, state: .available, sources: [watchSource]),
            ],
            hourlyMetrics: [
                HourlyMetricRecord(hourStart: morningWake.addingTimeInterval(3 * 3600), metric: "hr_bpm", value: 78.0),
            ],
            rawSleepSamples: [
                RawSleepSample(startDate: nightStart, endDate: morningWake, stage: .asleepUnspecified, source: autoSleepSource),
                RawSleepSample(startDate: nightStart, endDate: nightStart.addingTimeInterval(2 * 3600), stage: .deep, source: watchSource),
                RawSleepSample(startDate: nightStart.addingTimeInterval(2 * 3600), endDate: nightStart.addingTimeInterval(6 * 3600), stage: .core, source: watchSource),
                RawSleepSample(startDate: nightStart.addingTimeInterval(6 * 3600), endDate: morningWake, stage: .rem, source: watchSource),
            ],
            workouts: [
                StoredWorkoutRecord(
                    hkUUID: workoutUUID,
                    type: "羽毛球",
                    start: morningWake.addingTimeInterval(11 * 3600),
                    end: morningWake.addingTimeInterval(12 * 3600),
                    energy: 420,
                    avgHR: 147,
                    effortUser: 8.5,
                    effortEstimated: 7.1,
                    reviewState: .unreviewed
                ),
            ],
            workoutSymbols: [workoutUUID: "figure.badminton"],
            affectedDayKeys: [dayKey],
            nextAnchorData: Data("anchor-token-v1".utf8)
        )

        let mockSource = MockHealthKitSyncSource(recentBatch: batch)
        let engine = SyncEngine(
            repository: repo,
            source: mockSource,
            conditions: MutableConditionProvider(),
            debounceDuration: .milliseconds(10),
            sleepGoalMinutes: 450,
            calendar: cal
        )

        let summary = try await engine.syncRecentWindow(days: 30, referenceDate: morningWake)
        XCTAssertEqual(summary.syncedDayKeys, [dayKey])
        XCTAssertEqual(summary.sleepEpisodesSaved, 1)
        XCTAssertEqual(summary.workoutsSaved, 1)
        XCTAssertEqual(summary.scoresComputed, 1)

        let savedAnchor = try await repo.loadSyncAnchor(type: SyncEngine.recentAnchorType)
        XCTAssertEqual(savedAnchor?.anchorData, Data("anchor-token-v1".utf8))

        let rawDays = try await repo.loadRawDays(from: dayKey, to: dayKey, calendar: cal)
        let raw = try XCTUnwrap(rawDays.first)
        XCTAssertEqual(raw.sleepAsleepMinutes, 480)
        XCTAssertEqual(raw.deepMinutes, 120)
        XCTAssertEqual(raw.coreMinutes, 240)
        XCTAssertEqual(raw.remMinutes, 120)
        XCTAssertEqual(raw.workouts.first?.effortScore, 8.5)
        XCTAssertEqual(raw.workouts.first?.estimatedEffortScore, 7.1)
    }

    func testResumableBackfillPausesOnLowPowerAndThermalThenCompletes() async throws {
        let db = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: db)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))

        let refDate = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12)))
        let mockSource = MockHealthKitSyncSource()
        let conditionProvider = MutableConditionProvider()

        let engine = SyncEngine(
            repository: repo,
            source: mockSource,
            conditions: conditionProvider,
            calendar: cal
        )

        let tz = cal.timeZone

        // Pause after 2 monthly chunks due to Low Power Mode
        await mockSource.setOnMonthlyBackfill { callIndex, monthStart, _ in
            if callIndex == 2 {
                await conditionProvider.set(SystemConditions(isLowPowerModeEnabled: true, isThermallyThrottled: false))
            }
            let key = monthStart.physiologicalDayKey(cutoverHour: 4, timeZone: tz)
            return SyncBatch(
                dayMetrics: [
                    DayMetricRecord(dayKey: key, metric: DayMetricField.hrvMs.rawValue, value: 60.0, state: .available),
                ],
                affectedDayKeys: [key]
            )
        }

        let firstRun = try await engine.runResumableBackfill(totalMonths: 4, referenceDate: refDate)
        XCTAssertEqual(firstRun.monthsCompleted, 2)
        XCTAssertEqual(firstRun.pausedReason, .lowPowerMode)
        XCTAssertFalse(firstRun.completedAll)
        let cursorAfterFirst = try XCTUnwrap(firstRun.lastCursor)

        // Switch to thermal throttle -> immediately pauses with 0 additional months and keeps cursor intact
        await conditionProvider.set(SystemConditions(isLowPowerModeEnabled: false, isThermallyThrottled: true))
        let secondRun = try await engine.runResumableBackfill(totalMonths: 4, referenceDate: refDate)
        XCTAssertEqual(secondRun.monthsCompleted, 0)
        XCTAssertEqual(secondRun.pausedReason, .thermalThrottle)
        XCTAssertEqual(secondRun.lastCursor, cursorAfterFirst)

        // Clear throttle and remove hook -> finishes remaining 2 months and marks completedAll = true
        await conditionProvider.set(SystemConditions(isLowPowerModeEnabled: false, isThermallyThrottled: false))
        await mockSource.setOnMonthlyBackfill(nil)
        let finalRun = try await engine.runResumableBackfill(totalMonths: 4, referenceDate: refDate)
        XCTAssertEqual(finalRun.monthsCompleted, 2)
        XCTAssertNil(finalRun.pausedReason)
        XCTAssertTrue(finalRun.completedAll)

        let totalBackfillCalls = await mockSource.monthlyCallCount
        XCTAssertEqual(totalBackfillCalls, 4)
    }

    func testThreeSecondDebounceCoalescesRapidObserverSignalsAndPropagatesErrors() async throws {
        let db = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: db)
        let dayKey = DayKey(year: 2026, month: 11, day: 19)
        let batch = SyncBatch(
            dayMetrics: [
                DayMetricRecord(dayKey: dayKey, metric: DayMetricField.hrvMs.rawValue, value: 58.0, state: .available),
            ],
            affectedDayKeys: [dayKey],
            nextAnchorData: Data("debounced-anchor".utf8)
        )
        let mockSource = MockHealthKitSyncSource(recentBatch: batch)
        let engine = SyncEngine(
            repository: repo,
            source: mockSource,
            debounceDuration: .milliseconds(40)
        )

        let expectation = expectation(description: "Coalesced debounced sync completes once")
        for idx in 0..<5 {
            await engine.scheduleDebouncedSync { duration in
                try await Task.sleep(for: duration)
            } onCompleted: { result in
                if idx == 4 {
                    if case .success = result {
                        expectation.fulfill()
                    }
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        let recentCalls = await mockSource.recentCallCount
        XCTAssertEqual(recentCalls, 1)

        // Verify source failure propagates without overwriting anchor
        struct SimulatedHKError: Error {}
        await mockSource.setForcedError(SimulatedHKError())
        do {
            _ = try await engine.syncRecentWindow(days: 30)
            XCTFail("Expected syncRecentWindow to throw SimulatedHKError")
        } catch is SimulatedHKError {
            // Expected
        }
        let preservedAnchor = try await repo.loadSyncAnchor(type: SyncEngine.recentAnchorType)
        XCTAssertEqual(preservedAnchor?.anchorData, Data("debounced-anchor".utf8))
    }
}

private actor MutableConditionProvider: SystemConditionProvider {
    private var current = SystemConditions()

    func set(_ newValue: SystemConditions) {
        current = newValue
    }

    func currentConditions() async -> SystemConditions {
        current
    }
}

private actor MockHealthKitSyncSource: HealthKitSyncSource {
    var recentBatch: SyncBatch
    var recentCallCount = 0
    var monthlyCallCount = 0
    var forcedError: Error?
    var onMonthlyBackfill: (@Sendable (Int, Date, Date) async throws -> SyncBatch)?

    init(recentBatch: SyncBatch = SyncBatch()) {
        self.recentBatch = recentBatch
    }

    func setForcedError(_ error: Error?) {
        forcedError = error
    }

    func setOnMonthlyBackfill(_ handler: (@Sendable (Int, Date, Date) async throws -> SyncBatch)?) {
        onMonthlyBackfill = handler
    }

    func fetchAnchoredRecent(
        anchorData: Data?,
        lookbackDays: Int,
        referenceDate: Date
    ) async throws -> SyncBatch {
        if let forcedError { throw forcedError }
        recentCallCount += 1
        return recentBatch
    }

    func fetchMonthlyBackfill(
        monthStart: Date,
        monthEnd: Date
    ) async throws -> SyncBatch {
        if let forcedError { throw forcedError }
        monthlyCallCount += 1
        if let onMonthlyBackfill {
            return try await onMonthlyBackfill(monthlyCallCount, monthStart, monthEnd)
        }
        return SyncBatch()
    }
}
