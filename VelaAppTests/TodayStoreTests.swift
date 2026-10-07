import XCTest
@testable import Vela

/// ARCH-00/PR0's deterministic fixture, kept in one Today-focused helper so
/// the Store projection is checked against the same five values as the
/// scoring gate (rather than a synthetic all-equal dashboard).
private enum TodayPR0GoldenFixture {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 31))!
    }

    static var now: Date { day.addingTimeInterval(12 * 3_600) }

    static func evidence() -> ScoredHealthEvidence {
        let history = (1...14).map { offset -> DailyHealthSnapshot in
            var item = DailyHealthSnapshot(
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
        var snapshot = DailyHealthSnapshot(date: day)
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
        snapshot.oxygenSaturation = 98
        snapshot.steps = 8_400
        snapshot.activeCalories = 460
        snapshot.activeMinutes = 42
        snapshot.workouts = [
            WorkoutSummary(
                start: day.addingTimeInterval(9 * 3_600),
                end: day.addingTimeInterval(9.75 * 3_600),
                activityName: "Strength Training",
                averageHeartRate: 132,
                source: "fixture",
                rpe: 7
            )
        ]

        return DailyHealthComputation(
            calendar: calendar,
            now: now,
            profile: DailyHealthComputationProfile(
                sleepTargetMinutes: 450,
                maxHeartRate: 190,
                biologicalSex: "other"
            )
        ).compute(for: snapshot, history: history)
    }

    static func dashboard() -> DashboardSummary {
        let scores = evidence()
        var dashboard = DashboardSummary.empty(date: day)
        dashboard.source = .healthKit
        dashboard.sleepScore = scores.sleep
        dashboard.recovery = scores.recovery
        dashboard.strain = scores.strain
        dashboard.stress = scores.physiologicalStress
        dashboard.energy = scores.energy
        return dashboard
    }
}

final class TodayStoreTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date { Date(timeIntervalSince1970: 1_780_000_000) }

    @MainActor
    private final class RecordingReader: TodayReadingModule {
        var cachedSnapshot: TodayDashboardSnapshot?
        var loadSnapshot: TodayDashboardSnapshot?
        var cachedCalls = 0
        var loadCalls = 0
        var policies: [TodayRefreshPolicy] = []
        var loadDelayNanoseconds: UInt64 = 0
        var loadError: Error?

        func cached(for day: Date) async throws -> TodayDashboardSnapshot? {
            cachedCalls += 1
            return cachedSnapshot
        }

        func load(for day: Date, policy: TodayRefreshPolicy) async throws -> TodayDashboardSnapshot {
            loadCalls += 1
            policies.append(policy)
            if loadDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: loadDelayNanoseconds)
            }
            if let loadError { throw loadError }
            return loadSnapshot ?? TodayDashboardSnapshot(dashboard: .empty(date: day))
        }
    }

    /// A reader whose shared request can be released by the test.  The gate
    /// makes the distinction between cancelling one waiter and cancelling the
    /// underlying coalesced load observable without touching implementation
    /// details inside TodayStore.
    @MainActor
    private final class GatedReader: TodayReadingModule {
        let cancellationBox = CancellationBox()
        var loadCalls = 0
        var loadContinuation: CheckedContinuation<TodayDashboardSnapshot, Error>?
        var startedContinuation: CheckedContinuation<Void, Never>?

        func cached(for day: Date) async throws -> TodayDashboardSnapshot? { nil }

        func load(for day: Date, policy: TodayRefreshPolicy) async throws -> TodayDashboardSnapshot {
            loadCalls += 1
            startedContinuation?.resume()
            startedContinuation = nil
            return try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    loadContinuation = continuation
                }
            }, onCancel: {
                cancellationBox.markCancelled()
                Task { @MainActor in
                    loadContinuation?.resume(throwing: CancellationError())
                    loadContinuation = nil
                }
            })
        }

        func waitUntilStarted() async {
            guard loadCalls == 0 else { return }
            await withCheckedContinuation { continuation in
                startedContinuation = continuation
            }
        }

        func resume(with snapshot: TodayDashboardSnapshot) {
            loadContinuation?.resume(returning: snapshot)
            loadContinuation = nil
        }
    }

    private final class CancellationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        func markCancelled() {
            lock.lock()
            value = true
            lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    @MainActor
    private final class CompletionFlag {
        private(set) var value = false

        func markCompleted() {
            value = true
        }
    }

    @MainActor
    private final class RecordingEffects: TodayEffectRouter {
        var openedMetrics: [TodayMetricID] = []
        var openedEvidence = 0
        var openedCalendar = 0
        var openedPlan = 0
        var openedSettings = 0
        var coachQuestions: [String] = []
        var startedTraining = 0
        var openedTrends = 0
        var openedQuickCoach = 0
        var requestedWeather = 0
        var refreshedWeather = 0
        var requestedCoverage = 0
        var viewedHashes: [String] = []
        var actionEvents: [(String, String)] = []
        var alignments: [LivedStateAlignment] = []
        var checkIns: [LivedStateCheckIn] = []
        var feedbackCount = 0

        func openCalendar() async { openedCalendar += 1 }
        func openMetric(_ metric: TodayMetricID) async { openedMetrics.append(metric) }
        func openEvidence() async { openedEvidence += 1 }
        func openPlan() async { openedPlan += 1 }
        func openSettings() async { openedSettings += 1 }
        func askCoach(_ question: String) async { coachQuestions.append(question) }
        func startTraining() async { startedTraining += 1 }
        func openTrends() async { openedTrends += 1 }
        func openQuickCoach() async { openedQuickCoach += 1 }
        func requestWeather() async -> TodayWeatherProjection? {
            requestedWeather += 1
            return nil
        }
        func refreshWeatherFromKnownLocation() async -> TodayWeatherProjection? {
            refreshedWeather += 1
            return nil
        }
        func requestCoverage() async -> DataCoverageSummaryModel? {
            requestedCoverage += 1
            return nil
        }
        func trackDailyDecisionViewed(bodyStateHash: String) async {
            viewedHashes.append(bodyStateHash)
        }
        func trackDailyDecisionAction(bodyStateHash: String, destination: String) async {
            actionEvents.append((bodyStateHash, destination))
        }
        func saveLivedStateAlignment(_ alignment: LivedStateAlignment) async { alignments.append(alignment) }
        func saveLivedState(_ checkIn: LivedStateCheckIn) async { checkIns.append(checkIn) }
        func submitFeedback(_ values: DailyDecisionFeedbackValues) async { feedbackCount += 1 }
    }

    private func snapshot(
        day: Date,
        source: DashboardSummary.DataSource = .healthKit,
        score: Double? = 77.43,
        updatedAt: Date? = nil
    ) -> TodayDashboardSnapshot {
        var dashboard = DashboardSummary.empty(date: day)
        dashboard.source = source
        for keyPath in [
            \DashboardSummary.recovery,
            \DashboardSummary.sleepScore,
            \DashboardSummary.strain,
            \DashboardSummary.stress,
            \DashboardSummary.energy
        ] {
            var metric = dashboard[keyPath: keyPath]
            metric.value = score
            metric.lastUpdated = updatedAt ?? day
            dashboard[keyPath: keyPath] = metric
        }
        return TodayDashboardSnapshot(dashboard: dashboard)
    }

    @MainActor
    func testAppearUsesCacheThenLiveAndPreservesFiveScoreSemantics() async {
        let reader = RecordingReader()
        let day = calendar.startOfDay(for: now)
        reader.cachedSnapshot = snapshot(day: day, source: .cache, score: nil)
        reader.loadSnapshot = snapshot(day: day, score: 77.43, updatedAt: now)
        let store = TodayStore(
            reader: reader,
            clock: FixedAppClock(now: now),
            calendar: calendar
        )

        await store.send(.appear)

        XCTAssertEqual(reader.cachedCalls, 1)
        XCTAssertEqual(reader.loadCalls, 1)
        XCTAssertEqual(store.state.phase, .ready)
        XCTAssertEqual(store.state.scores.ordered.count, 5)
        XCTAssertEqual(store.state.scores.sleep.value, 77.43)
        XCTAssertEqual(store.state.scores.recovery.algorithmVersion, "1.0.0")
        XCTAssertNil(store.state.command, "Store must not rebuild command state in a getter")
    }

    @MainActor
    func testConcurrentSameDayLoadsCoalesce() async {
        let reader = RecordingReader()
        reader.loadSnapshot = snapshot(day: calendar.startOfDay(for: now), score: 81, updatedAt: now)
        reader.loadDelayNanoseconds = 50_000_000
        let store = TodayStore(reader: reader, clock: FixedAppClock(now: now), calendar: calendar)

        async let first: Void = store.send(.refresh(force: false))
        async let second: Void = store.send(.refresh(force: true))
        _ = await (first, second)

        XCTAssertEqual(reader.loadCalls, 1)
        XCTAssertEqual(store.state.scores.recovery.value, 81)
    }

    @MainActor
    func testCancellingOneCoalescedWaiterDoesNotCancelSharedLoad() async throws {
        let reader = GatedReader()
        let day = calendar.startOfDay(for: now)
        let expected = snapshot(day: day, score: 83, updatedAt: now)
        let store = TodayStore(reader: reader, clock: FixedAppClock(now: now), calendar: calendar)

        let first = Task { @MainActor in
            await store.send(.refresh(force: false))
        }
        await reader.waitUntilStarted()

        let secondStarted = CompletionFlag()
        let second = Task { @MainActor in
            secondStarted.markCompleted()
            await store.send(.refresh(force: true))
        }
        // Let the second MainActor task cross the store's waiter registration
        // point before cancelling the first.  The bounded yield loop avoids a
        // scheduler-dependent race while keeping the test independent of
        // TodayStore internals.
        for _ in 0..<100 where !secondStarted.value {
            await Task.yield()
        }
        XCTAssertTrue(secondStarted.value)
        for _ in 0..<100 {
            await Task.yield()
        }

        let firstCompletion = CompletionFlag()
        let firstObserver = Task { @MainActor in
            await first.value
            firstCompletion.markCompleted()
        }
        first.cancel()
        for _ in 0..<50 where !firstCompletion.value {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertTrue(firstCompletion.value, "a cancelled waiter must stop waiting promptly")
        XCTAssertFalse(reader.cancellationBox.isCancelled, "one waiter cancellation must not cancel the shared reader task")
        XCTAssertEqual(reader.loadCalls, 1, "same-day waiters must continue to coalesce")

        reader.resume(with: expected)
        await second.value
        await firstObserver.value

        XCTAssertEqual(store.state.phase, .ready)
        XCTAssertEqual(store.state.scores.recovery.value, 83)
    }

    @MainActor
    func testRefreshForwardsAutomaticAndForcePolicies() async {
        let reader = RecordingReader()
        let store = TodayStore(reader: reader, clock: FixedAppClock(now: now), calendar: calendar)

        await store.send(.refresh(force: false))
        await store.send(.refresh(force: true))

        XCTAssertEqual(reader.policies, [.automatic, .force])
    }

    @MainActor
    func testOldDateResultCannotOverwriteNewSelectedDay() async throws {
        let reader = RecordingReader()
        let oldDay = calendar.startOfDay(for: now)
        let newDay = calendar.date(byAdding: .day, value: -1, to: oldDay)!
        reader.loadSnapshot = snapshot(day: oldDay, score: 11, updatedAt: oldDay)
        reader.loadDelayNanoseconds = 100_000_000
        let store = TodayStore(reader: reader, clock: FixedAppClock(now: now), calendar: calendar)

        let oldRequest = Task { @MainActor in
            await store.send(.refresh(force: false))
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        reader.loadSnapshot = snapshot(day: newDay, score: 22, updatedAt: newDay)
        await store.send(.selectDay(newDay))
        await oldRequest.value

        XCTAssertEqual(store.state.selectedDay, newDay)
        XCTAssertEqual(store.state.scores.recovery.value, 22)
        XCTAssertFalse(store.state.scores.recovery.value == 11)
    }

    @MainActor
    func testEmptyAndReaderFailureAreDistinct() async {
        let reader = RecordingReader()
        let store = TodayStore(reader: reader, clock: FixedAppClock(now: now), calendar: calendar)
        await store.send(.refresh(force: false))
        XCTAssertEqual(store.state.phase, .empty)
        XCTAssertNil(store.state.scores.recovery.value)

        reader.loadError = NSError(domain: "TodayStoreTests", code: 1)
        await store.send(.refresh(force: true))
        guard case let .failed(failure) = store.state.phase,
              case .reader = failure else {
            return XCTFail("reader errors must be represented as failed, not empty")
        }
        XCTAssertNil(store.state.scores.energy.value)
    }

    @MainActor
    func testCancellationDoesNotLeaveStoreStuckLoading() async throws {
        let reader = RecordingReader()
        reader.loadDelayNanoseconds = 500_000_000
        let store = TodayStore(reader: reader, clock: FixedAppClock(now: now), calendar: calendar)

        let request = Task { @MainActor in
            await store.send(.refresh(force: false))
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        request.cancel()
        await request.value

        if case .loading = store.state.phase {
            XCTFail("cancellation must settle the loading phase")
        }
    }

    @MainActor
    func testFutureSelectionIsRejected() async {
        let reader = RecordingReader()
        let store = TodayStore(reader: reader, clock: FixedAppClock(now: now), calendar: calendar)
        let future = calendar.date(byAdding: .day, value: 1, to: now)!

        await store.send(.selectDay(future))

        XCTAssertEqual(store.state.selectedDay, calendar.startOfDay(for: now))
        XCTAssertEqual(store.state.phase, .failed(.invalidDay))
        XCTAssertEqual(reader.cachedCalls, 0)
    }

    @MainActor
    func testIntentActionsRouteToEffectsAndUpdateLocalProjections() async {
        let reader = RecordingReader()
        let effects = RecordingEffects()
        let store = TodayStore(
            reader: reader,
            clock: FixedAppClock(now: now),
            calendar: calendar,
            effects: effects
        )
        let checkIn = LivedStateCheckIn(stress: 2, energy: 1, soreness: 0, motivation: 1)

        await store.send(.openEvidence)
        await store.send(.openMetric(.sleep))
        await store.send(.askCoach("为什么今天要恢复？"))
        await store.send(.startTraining)
        await store.send(.openTrends)
        await store.send(.openQuickCoach)
        await store.send(.requestWeather)
        await store.send(.setLivedStateAlignment(.worse))
        await store.send(.saveLivedState(checkIn))

        XCTAssertEqual(effects.openedEvidence, 1)
        XCTAssertEqual(effects.openedMetrics, [.sleep])
        XCTAssertEqual(effects.coachQuestions, ["为什么今天要恢复？"])
        XCTAssertEqual(effects.startedTraining, 1)
        XCTAssertEqual(effects.openedTrends, 1)
        XCTAssertEqual(effects.openedQuickCoach, 1)
        XCTAssertEqual(effects.requestedWeather, 1)
        XCTAssertEqual(effects.alignments, [.worse])
        XCTAssertEqual(effects.checkIns, [checkIn])
        XCTAssertEqual(store.state.livedState.alignment, .worse)
        XCTAssertEqual(store.state.livedState.checkIn, checkIn)
    }

    @MainActor
    func testLocationDeliveryDoesNotRequestPermissionOrRestartLocationAcquisition() async {
        let reader = RecordingReader()
        let effects = RecordingEffects()
        let store = TodayStore(reader: reader, clock: FixedAppClock(now: now), calendar: calendar, effects: effects)

        await store.send(.appear)
        XCTAssertEqual(effects.requestedWeather, 0)
        await store.send(.weatherLocationChanged)
        XCTAssertEqual(effects.refreshedWeather, 1)
        XCTAssertEqual(effects.requestedWeather, 0)
        await store.send(.requestWeather)
        XCTAssertEqual(effects.requestedWeather, 1)
    }

    @MainActor
    func testWeatherCoverageAndAnalyticsRemainStoreOwnedEffects() async {
        let reader = RecordingReader()
        let effects = RecordingEffects()
        let store = TodayStore(
            reader: reader,
            clock: FixedAppClock(now: now),
            calendar: calendar,
            effects: effects
        )

        await store.send(.requestWeather)
        await store.send(.refreshCoverage)
        await store.send(.trackDailyDecisionViewed(bodyStateHash: "body-hash"))
        await store.send(.trackDailyDecisionViewed(bodyStateHash: "body-hash"))
        await store.send(.trackDailyDecisionAction(bodyStateHash: "body-hash", destination: "training"))

        XCTAssertEqual(store.state.weather, .unavailable)
        XCTAssertEqual(store.state.coverage.status, .unknown)
        XCTAssertEqual(effects.requestedWeather, 1)
        XCTAssertEqual(effects.requestedCoverage, 1)
        XCTAssertEqual(effects.viewedHashes, ["body-hash", "body-hash"])
        XCTAssertEqual(effects.actionEvents.map(\.1), ["training"])
    }
}

final class TodayViewStateTests: XCTestCase {
    @MainActor
    func testPR0GoldenProjectsExactFiveScoresVersionsSourceAndCompleteness() {
        let day = TodayPR0GoldenFixture.day
        let state = TodayViewState.projection(
            snapshot: TodayDashboardSnapshot(dashboard: TodayPR0GoldenFixture.dashboard()),
            selectedDay: day,
            now: TodayPR0GoldenFixture.now,
            calendar: TodayPR0GoldenFixture.calendar
        )

        let expected: [(TodayMetricID, Double, String, MetricSource, [String])] = [
            (.recovery, 68.70, ScoringAlgorithmVersions.recovery, .healthKit, []),
            // The fixture intentionally has no historical bedtime values;
            // preserve the engine's explicit consistency-data gap.
            (.sleep, 77.43, ScoringAlgorithmVersions.sleep, .healthKit, ["recentBedtimesHistory"]),
            (.strain, 63.67, ScoringAlgorithmVersions.strain, .healthKit, []),
            (.stress, 21.08, ScoringAlgorithmVersions.physiologicalStress, .derived, []),
            (.energy, 47.91, ScoringAlgorithmVersions.energy, .derived, [])
        ]
        XCTAssertEqual(state.phase, .ready)
        XCTAssertEqual(state.source, .healthKit)
        XCTAssertEqual(state.freshness, .live)
        XCTAssertEqual(state.scores.ordered.map(\.id), expected.map(\.0))
        for (id, score, version, source, missingInputs) in expected {
            let metric = state.scores.metric(for: id)
            XCTAssertEqual(metric.value ?? -1, score, accuracy: 0.01, "PR0 score changed for \(id.rawValue)")
            XCTAssertEqual(metric.algorithmVersion, version, "algorithm version changed for \(id.rawValue)")
            XCTAssertEqual(metric.source, source, "score source changed for \(id.rawValue)")
            XCTAssertEqual(metric.missingInputs, missingInputs, "PR0 missing inputs for \(id.rawValue)")
        }
    }

    @MainActor
    func testMissingProjectionKeepsAllScoresUnavailableAndNoAggregate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 1_780_000_000)
        let snapshot = TodayDashboardSnapshot(dashboard: .empty(date: day))
        let state = TodayViewState.projection(
            snapshot: snapshot,
            selectedDay: day,
            now: day,
            calendar: calendar
        )

        XCTAssertEqual(state.phase, .empty)
        XCTAssertEqual(state.freshness, .missing)
        XCTAssertEqual(state.scores.ordered.count, 5)
        XCTAssertTrue(state.scores.ordered.allSatisfy { $0.metric.value == nil })
        XCTAssertTrue(state.scores.ordered.allSatisfy { $0.metric.formattedScore == "--" })
        XCTAssertEqual(state.coverage.status, .unknown)
        XCTAssertEqual(state.coverage.title, "Checking data coverage")
        XCTAssertNil(state.command)
        XCTAssertNil(state.experience)
        XCTAssertEqual(state.livedState, .empty)
        XCTAssertEqual(state.feedback, .empty)
        XCTAssertNil(state.plan)
        XCTAssertNil(state.activePlan)
        XCTAssertNil(state.pendingPlan)
        XCTAssertNil(state.nutrition)
        XCTAssertEqual(state.weather, .unavailable)
        XCTAssertNil(state.weather.temperature)
    }

    @MainActor
    func testSecondaryReaderValuesSurviveCanonicalStateProjection() {
        let day = TodayPR0GoldenFixture.day
        let nutrition = TodayNutritionProjection(
            calories: 1_420,
            calorieTarget: 2_000,
            protein: 118,
            carbs: 164,
            fat: 52
        )
        let livedState = TodayLivedStateProjection(
            alignment: .worse,
            checkIn: LivedStateCheckIn(stress: 2, energy: 0, soreness: 1, motivation: 1)
        )
        let feedback = TodayFeedbackProjection(
            isSubmitted: true,
            summary: "按计划完成",
            adoptionStatus: "followed",
            accuracyRating: "accurate",
            actualAction: "as_planned",
            energyRating: 2,
            fatigueRating: 1,
            painRating: 0,
            satisfactionRating: 2,
            note: "状态不错"
        )
        let payload = DailyOperatingPlanPayload(
            decision: .reduce,
            volumeMultiplier: 0.6,
            intensityCap: 7,
            summary: "今天降低训练容量",
            targetSessionTitle: "轻量下肢"
        )
        let coverage = DataCoverageSummaryModel(
            scorePercent: 82,
            status: .high,
            title: "数据覆盖",
            subtitle: "关键健康信号可用",
            actionTitle: "查看数据",
            actionSystemImage: "checkmark",
            domainSummaries: [
                DataCoverageDomainSummary(
                    id: "sleep",
                    title: "睡眠",
                    icon: "bed.double",
                    scorePercent: 82,
                    usableCount: 9,
                    totalCount: 11
                )
            ],
            topBlockers: [],
            coachContextLine: "数据覆盖 82%"
        )
        let activePlan = TodayPlanProjection(payload: payload)
        let pendingPlan = TodayPendingPlanProjection(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            adjustment: "reduce",
            reason: "恢复信号偏低",
            suggestedAlternative: "轻量下肢",
            originalDayTitle: "下肢力量",
            createdAt: day,
            status: "proposed"
        )
        let weather = TodayWeatherProjection(
            status: .available,
            temperature: 21.5,
            apparentTemperature: 20.0,
            humidity: 0.62,
            windSpeed: 3.2,
            conditionCode: 2,
            isDay: true,
            locationName: "上海",
            capturedAt: day
        )
        let snapshot = TodayDashboardSnapshot(
            dashboard: TodayPR0GoldenFixture.dashboard(),
            nutrition: nutrition,
            livedState: livedState,
            feedback: feedback,
            coverage: coverage,
            activePlan: activePlan,
            pendingPlan: pendingPlan,
            weather: weather,
            operatingPlanPayload: payload
        )

        let state = TodayViewState.projection(
            snapshot: snapshot,
            selectedDay: day,
            now: TodayPR0GoldenFixture.now,
            calendar: TodayPR0GoldenFixture.calendar
        )

        XCTAssertEqual(state.nutrition, nutrition)
        XCTAssertEqual(state.livedState, livedState)
        XCTAssertEqual(state.feedback, feedback)
        XCTAssertEqual(state.coverage, coverage)
        XCTAssertEqual(state.plan, TodayPlanProjection(payload: payload))
        XCTAssertEqual(state.activePlan, activePlan)
        XCTAssertEqual(state.pendingPlan, pendingPlan)
        XCTAssertEqual(state.weather, weather)
        XCTAssertEqual(state.operatingPlanPayload, payload)
    }

    @MainActor
    func testFreshnessUsesInjectedClockAndMetricTimestamp() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 1_780_000_000)
        var dashboard = DashboardSummary.empty(date: day)
        dashboard.recovery.value = 60
        dashboard.recovery.lastUpdated = day.addingTimeInterval(-4 * 3_600)
        let state = TodayViewState.projection(
            snapshot: TodayDashboardSnapshot(dashboard: dashboard),
            selectedDay: day,
            now: day,
            calendar: calendar
        )
        XCTAssertEqual(state.freshness, .today)
    }
}
