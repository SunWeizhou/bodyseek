import BodySeekCore
import BodySeekFeatures
import BodySeekHealth
import ComposableArchitecture
import XCTest

@MainActor
final class AppAndTodayFeatureTests: XCTestCase {
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
        await store.receive(\.briefingGenerated)

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
        XCTAssertEqual(savedStore.state.preferences.checkInsByDay[entry.dayKey.isoString], entry)
        XCTAssertEqual(prefsBox.value.checkInsByDay[entry.dayKey.isoString], entry)

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
