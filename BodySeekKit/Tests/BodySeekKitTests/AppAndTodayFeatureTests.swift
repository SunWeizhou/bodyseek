import BodySeekCore
import BodySeekFeatures
import BodySeekHealth
import BodySeekStore
import ComposableArchitecture
import XCTest

@MainActor
final class AppAndTodayFeatureTests: XCTestCase {
    func testCachedWorkoutArrivalUpdatesRecoveryAndShowsStrengthReviewWithoutReopeningTab() async {
        let now = DayKey(year: 2026, month: 11, day: 20).startDate().addingTimeInterval(8 * 3600)
        let oldRecord = StoredWorkoutRecord(hkUUID: UUID().uuidString, type: "力量训练",
                                            start: now.addingTimeInterval(-86_400),
                                            end: now.addingTimeInterval(-82_800), energy: 140,
                                            reviewState: .annotated)
        let run = WorkoutSummary(activityName: "跑步", symbolName: "figure.run", startDate: now.addingTimeInterval(-7_200),
                                 durationMinutes: 40, activeEnergyKcal: 300)
        let strength = WorkoutSummary(activityName: "力量训练", symbolName: "dumbbell.fill",
                                      startDate: now.addingTimeInterval(-3_600), durationMinutes: 45, activeEnergyKcal: 200)
        func snapshot(workouts: [WorkoutSummary]) -> BodySeekDashboardSnapshot {
            BevelScoringEngine.computeWindow(
                rawDays: [DailyRawMetrics(date: now, workouts: workouts)], sleepGoalMinutes: 450,
                referenceDate: now, sourceLabel: "测试", isAuthorized: true
            )
        }

        var initial = AppFeature.State(snapshot: snapshot(workouts: []))
        initial.workout.storedWorkouts = [oldRecord]
        let store = TestStore(initialState: initial) { AppFeature() } withDependencies: {
            $0.date.now = now
        }
        store.exhaustivity = .off
        let incoming = CachedDashboardState(snapshot: snapshot(workouts: [strength, run]), chartCache: [:], contentDigest: "new-workouts")

        await store.send(.cachedDashboardLoaded(incoming))

        XCTAssertEqual(store.state.workout.unreviewedWorkouts.map(\.hkUUID), [strength.id.uuidString])
        XCTAssertTrue(store.state.workout.recoverySnapshot.estimate(for: .quadriceps).contributingEvents.contains { $0.workoutUUID == run.id.uuidString })
        XCTAssertEqual(store.state.workout.storedWorkouts.last, oldRecord)
    }

    func testReviewOfTrainingCompletedAfterSnapshotRefreshesRecoveryAndClearsMorningAdvice() async {
        let day = DayKey(year: 2026, month: 11, day: 20)
        let morning = day.startDate().addingTimeInterval(4 * 3600)
        let evening = morning.addingTimeInterval(10 * 3600)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: [], sleepGoalMinutes: 450, referenceDate: morning,
            sourceLabel: "测试", isAuthorized: true
        )
        var initialState = AppFeature.State(snapshot: snapshot)
        initialState.today.briefingStatus = .generated(text: "今天可以安排强度训练", engineName: "测试")
        let chest = StoredWorkoutRecord(
            hkUUID: UUID().uuidString, type: "力量训练",
            start: evening.addingTimeInterval(-3600), end: evening.addingTimeInterval(-120),
            energy: 200, reviewState: .annotated
        )
        let legs = StoredWorkoutRecord(
            hkUUID: UUID().uuidString, type: "力量训练",
            start: chest.start.addingTimeInterval(-86_400), end: chest.end.addingTimeInterval(-86_400),
            energy: 240, reviewState: .annotated
        )
        let loads = [
            WorkoutMuscleLoadRecord(workoutUUID: chest.hkUUID, muscle: .chest, role: .primary, load: 0.6,
                                    algorithmVersion: .recoveryHeuristicV1),
            WorkoutMuscleLoadRecord(workoutUUID: legs.hkUUID, muscle: .quadriceps, role: .primary, load: 0.6,
                                    algorithmVersion: .recoveryHeuristicV1),
        ]
        let store = TestStore(initialState: initialState) { AppFeature() } withDependencies: {
            $0.date.now = evening
        }
        store.exhaustivity = .off
        await store.send(.workout(.reviewPersisted(workouts: [chest, legs], annotations: [], loads: loads, committedMemories: [])))
        XCTAssertLessThan(store.state.workout.recoverySnapshot.estimate(for: .chest).recoveryRatio, 0.8)
        XCTAssertTrue(store.state.today.postWorkoutAdvice?.contains("胸部") == true)
        XCTAssertFalse(store.state.today.postWorkoutAdvice?.contains(BodyRegionMuscle.quadriceps.title) == true)
        await store.send(.briefingGenerated(.generated(text: "过时的晨间建议", engineName: "测试")))
        if case .generated = store.state.today.briefingStatus {
            XCTFail("A briefing from before today's completed workout is still visible")
        }
    }

    func testDashboardReferenceKeepsLocalTimeForPhysiologicalDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let day = DayKey(year: 2026, month: 11, day: 20)
        let cutoff = day.startDate(timeZone: calendar.timeZone)
        for (instant, expected) in [(cutoff.addingTimeInterval(-1), day.addingDays(-1)), (cutoff, day)] {
            let snapshot = BevelScoringEngine.computeWindow(
                rawDays: [], sleepGoalMinutes: 450, referenceDate: instant,
                sourceLabel: "测试", isAuthorized: false, calendar: calendar
            )
            XCTAssertEqual(snapshot.referenceDate, instant)
            XCTAssertEqual(snapshot.referenceDate.physiologicalDayKey(timeZone: calendar.timeZone), expected)
        }
    }

    func testAppFeatureOpensMetricDetailAndRoutesQuestionToCoach() async {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 30),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "示例数据",
            isAuthorized: true
        )

        let store = TestStore(
            initialState: AppFeature.State(
                hasCompletedOnboarding: true,
                snapshot: snapshot,
                preferences: AppPreferencesState(),
                arguments: ["-velaPreviewDashboard"]
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.healthKitClient = .previewValue
            $0.preferencesClient = .previewValue
            $0.fitnessStoreClient = .previewValue
            $0.coachAIClient = .previewValue
            $0.restTimerClient = .previewValue
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
            $0.date.now = now
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.snapshotLoaded)

        await store.send(.today(.metricTapped(.recovery)))
        await store.receive(\.today.delegate.openMetric)
        XCTAssertEqual(store.state.todayPath.count, 1)
        XCTAssertEqual(store.state.todayPath.first?.kind, .recovery)

        if let firstID = store.state.todayPath.ids.first {
            await store.send(.todayPath(.element(id: firstID, action: .askCoachTapped)))
            await store.receive(\.todayPath)
            await store.receive(\.coach.externalPromptSubmitted)
            await store.receive(\.coach.aiReplyReceived)
            await store.receive(\.clearMetricDetailPaths)
            XCTAssertEqual(store.state.selectedTab, .coach)
            XCTAssertTrue(store.state.todayPath.isEmpty)
        }
    }

    func testCoachWorkoutProposalAppliesDirectlyToWorkoutTab() async {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 20),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "示例数据",
            isAuthorized: true
        )

        let proposalTemplate = WorkoutTemplate(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            title: "AI 减量上肢训练",
            subtitle: "Tool-calling 生成",
            focusTag: "AI 处方",
            estimatedMinutes: 30,
            exercises: [
                PlannedExerciseItem(exerciseID: "barbell-bench-press", targetSets: 3, targetReps: 8, targetWeightKg: 50, restSeconds: 90),
            ],
            isAIGenerated: true
        )
        let proposal = WorkoutProposal(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            template: proposalTemplate,
            rationale: "今日 HRV 略低，减容保持张力"
        )

        let store = TestStore(
            initialState: AppFeature.State(
                hasCompletedOnboarding: true,
                snapshot: snapshot,
                arguments: ["-velaPreviewDashboard"]
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.healthKitClient = .previewValue
            $0.preferencesClient = .previewValue
            $0.fitnessStoreClient = .previewValue
            $0.coachAIClient = .previewValue
            $0.restTimerClient = .previewValue
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
            $0.date.now = now
        }
        store.exhaustivity = .off

        let msgID = UUID()
        await store.send(.coach(.applyProposalTapped(messageID: msgID, proposal: proposal, startImmediately: false)))
        await store.receive(\.coach.delegate.applyWorkoutProposal)
        await store.receive(\.workout.acceptProposalTapped)

        XCTAssertEqual(store.state.selectedTab, .workout)
        XCTAssertEqual(store.state.workout.templates.first?.title, "AI 减量上肢训练")
        XCTAssertEqual(store.state.workout.pendingProposal?.template.title, "AI 减量上肢训练")
    }

    func testDailyCheckInFlowAndPersistenceFailurePropagation() async {
        struct WriteDeniedError: LocalizedError {
            var errorDescription: String? { "disk full" }
        }

        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 14),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Test",
            isAuthorized: true
        )

        let prefsBox = LockedPrefsRecorder(AppPreferencesState())
        let savedStore = TestStore(
            initialState: AppFeature.State(
                hasCompletedOnboarding: true,
                snapshot: snapshot,
                preferences: prefsBox.value
            )
        ) {
            AppFeature()
        } withDependencies: {
            var client = PreferencesClient.previewValue
            client.save = { updated in prefsBox.set(updated) }
            $0.preferencesClient = client
            $0.healthKitClient = .previewValue
            $0.fitnessStoreClient = .previewValue
            $0.coachAIClient = .previewValue
            $0.continuousClock = ImmediateClock()
            $0.date.now = now
        }
        savedStore.exhaustivity = .off

        await savedStore.send(.today(.openCheckInTapped))
        await savedStore.receive(\.today.delegate.openCheckIn)
        XCTAssertTrue(savedStore.state.isCheckInPresented)

        let entry = DailyCheckIn(
            dayKey: snapshot.referenceDate.physiologicalDayKey(),
            recordedAt: now,
            energy: 5,
            mood: 4,
            stress: 2,
            soreness: [.upperBack: 2],
            note: "背训练后感觉饱满"
        )
        await savedStore.send(.checkInSaved(entry))
        XCTAssertFalse(savedStore.state.isCheckInPresented)
        XCTAssertEqual(savedStore.state.today.todayCheckIn, entry)
        XCTAssertEqual(savedStore.state.coach.checkIns.first, entry)
        XCTAssertEqual(savedStore.state.preferences.checkInsByDay[entry.dayKey.isoString], entry)
        XCTAssertEqual(prefsBox.value.checkInsByDay[entry.dayKey.isoString], entry)

        var updatedEntry = entry
        updatedEntry.energy = 2
        updatedEntry.note = "下午有点累"
        await savedStore.send(.checkInSaved(updatedEntry))
        XCTAssertEqual(savedStore.state.coach.checkIns.count, 1)
        XCTAssertEqual(savedStore.state.coach.checkIns.first?.energy, 2)

        var failingClient = PreferencesClient.previewValue
        failingClient.save = { _ in throw WriteDeniedError() }
        let failingStore = TestStore(
            initialState: AppFeature.State(hasCompletedOnboarding: true, snapshot: snapshot)
        ) {
            AppFeature()
        } withDependencies: {
            $0.preferencesClient = failingClient
            $0.date.now = now
        }
        failingStore.exhaustivity = .off

        await failingStore.send(.checkInSaved(entry))
        XCTAssertTrue(failingStore.state.today.lastError?.contains("保存每日体感打卡失败") == true)
    }

    func testSettingsResetRequiresConfirmationAndCancelPreservesData() async {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 7),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Test",
            isAuthorized: true
        )
        let tracker = LockedResetTracker()
        var prefs = PreferencesClient.previewValue
        prefs.reset = { tracker.markPrefsReset() }
        var fitness = FitnessStoreClient.previewValue
        fitness.resetAll = { tracker.markFitnessReset() }

        let store = TestStore(
            initialState: SettingsFeature.State(
                snapshot: snapshot,
                preferences: AppPreferencesState(sleepGoalMinutes: 480),
                memories: [AthleteMemoryItem(category: .goal, content: "备赛半马", updatedAt: now)],
                tieredMemories: [TieredMemoryRecord(tier: .profile, content: "晨跑前不吃过饱", confidence: 1.0)]
            )
        ) {
            SettingsFeature()
        } withDependencies: {
            $0.preferencesClient = prefs
            $0.fitnessStoreClient = fitness
            $0.coachAIClient = .previewValue
        }
        store.exhaustivity = .off

        await store.send(.resetConfirmationPresented(true))
        XCTAssertTrue(store.state.showResetConfirmation)

        // Cancelling confirmation leaves all data & stores untouched
        await store.send(.resetConfirmationPresented(false))
        XCTAssertFalse(store.state.showResetConfirmation)
        XCTAssertFalse(tracker.didResetAny)
        XCTAssertEqual(store.state.memories.count, 1)
        XCTAssertEqual(store.state.tieredMemories.count, 1)

        // Confirming executes reset and clears state
        await store.send(.resetConfirmationPresented(true))
        await store.send(.resetAllDataTapped)
        await store.receive(\.resetFinished)
        XCTAssertFalse(store.state.showResetConfirmation)
        XCTAssertTrue(tracker.didResetBoth)
        XCTAssertTrue(store.state.memories.isEmpty)
        XCTAssertTrue(store.state.tieredMemories.isEmpty)
    }

    func testFreshNonPreviewInstallDoesNotSeedDemoPatterns() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: [],
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "未授权",
            isAuthorized: false
        )
        let isolatedStoreClient = BodySeekStoreClient.testValue
        let store = TestStore(
            initialState: AppFeature.State(
                hasCompletedOnboarding: true,
                snapshot: snapshot,
                arguments: []
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.healthKitClient = .previewValue
            $0.preferencesClient = .previewValue
            $0.fitnessStoreClient = .previewValue
            $0.bodySeekStoreClient = isolatedStoreClient
            $0.coachAIClient = .previewValue
            $0.restTimerClient = .previewValue
            $0.continuousClock = ImmediateClock()
            $0.date.now = now
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.supplementalContextLoaded)
        XCTAssertTrue(store.state.trends.patternFindings.isEmpty)
        let storedPatterns = try await isolatedStoreClient.loadPatternFindings(nil)
        XCTAssertTrue(storedPatterns.isEmpty)
    }
}

private final class LockedResetTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var prefs = false
    private var fitness = false
    func markPrefsReset() { lock.withLock { prefs = true } }
    func markFitnessReset() { lock.withLock { fitness = true } }
    var didResetAny: Bool { lock.withLock { prefs || fitness } }
    var didResetBoth: Bool { lock.withLock { prefs && fitness } }
}

private final class LockedPrefsRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: AppPreferencesState

    init(_ initial: AppPreferencesState) {
        storage = initial
    }

    var value: AppPreferencesState {
        lock.withLock { storage }
    }

    func set(_ newValue: AppPreferencesState) {
        lock.withLock { storage = newValue }
    }
}
