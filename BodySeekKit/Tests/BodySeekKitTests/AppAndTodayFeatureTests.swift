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
}
