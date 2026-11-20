import BodySeekCore
import BodySeekFeatures
import BodySeekHealth
import ComposableArchitecture
import XCTest

@MainActor
final class WorkoutAndCoachReducerTests: XCTestCase {
    private struct StubSaveError: LocalizedError {
        var errorDescription: String? { "SwiftData write failed" }
    }

    func testMuscleSelectionAndTemplateLogging() async {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 21),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "示例数据",
            isAuthorized: true
        )
        let fixedUUID = UUID(uuidString: "12345678-1234-1234-1234-1234567890ab")!

        let store = TestStore(
            initialState: WorkoutFeature.State(
                snapshot: snapshot,
                templates: ExerciseCatalog.defaultTemplates,
                sessions: []
            )
        ) {
            WorkoutFeature()
        } withDependencies: {
            $0.fitnessStoreClient = .previewValue
            $0.healthKitClient = .previewValue
            $0.restTimerClient = .previewValue
            $0.continuousClock = TestClock()
            $0.uuid = .constant(fixedUUID)
            $0.date.now = now
        }
        store.exhaustivity = .off

        await store.send(.muscleSelected(.chest))
        XCTAssertEqual(store.state.selectedMuscle, .chest)
        XCTAssertTrue(store.state.filteredExercises.allSatisfy {
            $0.primaryMuscles.contains(.chest) || $0.secondaryMuscles.contains(.chest)
        })

        // Toggle same muscle clears filter
        await store.send(.muscleSelected(.chest))
        XCTAssertNil(store.state.selectedMuscle)

        let template = ExerciseCatalog.defaultTemplates.first!
        await store.send(.startTemplateTapped(template))
        XCTAssertNotNil(store.state.activeWorkout)
        XCTAssertEqual(store.state.activeWorkout?.title, template.title)

        await store.send(.activeWorkoutToggleSetCompleted(exerciseIndex: 0, setIndex: 0))
        XCTAssertEqual(store.state.activeWorkout?.completedSetCount, 1)
        XCTAssertNotNil(store.state.activeWorkout?.restSecondsRemaining)

        await store.send(.skipRestTimerTapped)
        XCTAssertNil(store.state.activeWorkout?.restSecondsRemaining)

        await store.send(.completeActiveWorkoutTapped)
        await store.receive(\.workoutPersisted)
        XCTAssertNil(store.state.activeWorkout)
        XCTAssertEqual(store.state.sessions.count, 1)
    }

    func testWorkoutPersistFailureIsSurfacedNotSwallowed() async {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 10),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "示例数据",
            isAuthorized: true
        )

        let store = TestStore(
            initialState: WorkoutFeature.State(snapshot: snapshot, templates: ExerciseCatalog.defaultTemplates, sessions: [])
        ) {
            WorkoutFeature()
        } withDependencies: {
            $0.fitnessStoreClient.saveSession = { _ in throw StubSaveError() }
            $0.healthKitClient = .previewValue
            $0.restTimerClient = .previewValue
            $0.uuid = .incrementing
            $0.date.now = now
        }
        store.exhaustivity = .off

        await store.send(.startQuickEmptyTapped)
        await store.send(.completeActiveWorkoutTapped)
        await store.receive(\.workoutPersistFailed)

        XCTAssertEqual(store.state.lastError, "保存训练失败：SwiftData write failed")
        XCTAssertNotNil(store.state.activeWorkout)
    }

    func testCoachAgentUpdatesMemoriesAndEmitsProposal() async {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 14),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "示例数据",
            isAuthorized: true
        )
        let newMemory = AthleteMemoryItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000050")!,
            category: .injury,
            content: "右膝微痛，减免大重量深蹲",
            updatedAt: now
        )
        let proposal = WorkoutProposal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000051")!,
            template: ExerciseCatalog.defaultTemplates[0],
            rationale: "优先安排上肢推力训练"
        )

        let store = TestStore(
            initialState: CoachFeature.State(snapshot: snapshot)
        ) {
            CoachFeature()
        } withDependencies: {
            $0.coachAIClient.reply = { _, context in
                await context.effects.recordMemory(newMemory)
                await context.effects.recordProposal(proposal)
                return CoachMessage(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000052")!,
                    role: .assistant,
                    text: "已记住右膝状态并生成上肢替代课表。",
                    engineLabel: "Test AI",
                    timestamp: now,
                    evidenceMetric: .recovery,
                    workoutProposal: proposal,
                    memorySavedNote: "已记录伤病"
                )
            }
            $0.fitnessStoreClient = .previewValue
            $0.uuid = .incrementing
            $0.date.now = now
        }
        store.exhaustivity = .off

        await store.send(.quickPromptTapped("记住右膝痛，帮我排上肢课表"))
        await store.receive(\.aiReplyReceived)
        await store.receive(\.delegate.memoriesUpdated)

        XCTAssertEqual(store.state.memories.count, 1)
        XCTAssertEqual(store.state.memories.first?.content, "右膝微痛，减免大重量深蹲")
        XCTAssertEqual(store.state.messages.last?.workoutProposal?.template.title, proposal.template.title)
    }

    func testWatchFirstReviewInboxParsesCommits14DayMemoryAndUpdatesMuscleRecovery() async {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 21),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "示例数据",
            isAuthorized: true
        )

        let storeClient = BodySeekStoreClient.previewValue
        let store = TestStore(
            initialState: WorkoutFeature.State(
                snapshot: snapshot,
                templates: ExerciseCatalog.defaultTemplates,
                sessions: []
            )
        ) {
            WorkoutFeature()
        } withDependencies: {
            $0.bodySeekStoreClient = storeClient
            $0.workoutReviewParserClient = .testValue
            $0.fitnessStoreClient = .previewValue
            $0.healthKitClient = .previewValue
            $0.restTimerClient = .previewValue
            $0.date.now = now
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.watchWorkoutsLoaded)

        // Running & Badminton must auto-attribute while Strength stays in unreviewed Inbox
        XCTAssertFalse(store.state.unreviewedWorkouts.isEmpty)
        guard let targetWorkout = store.state.unreviewedWorkouts.first else {
            XCTFail("Expected an unreviewed Watch strength workout in Inbox")
            return
        }

        let runWorkout = store.state.archiveWorkouts.first { $0.type.contains("跑步") }
        XCTAssertEqual(runWorkout?.reviewState, .autoAttributed)
        let badmintonWorkout = store.state.archiveWorkouts.first { $0.type.contains("羽毛球") }
        XCTAssertEqual(badmintonWorkout?.reviewState, .autoAttributed)

        await store.send(.openReviewTapped(targetWorkout))
        XCTAssertNotNil(store.state.reviewDraft)

        await store.send(.reviewTextChanged("今天练胸，平板卧推 5 组，RPE 9，右肩前束略紧"))
        await store.send(.parseReviewTapped)
        await store.receive(\.reviewParsed)

        XCTAssertEqual(store.state.reviewDraft?.rpe, 9)
        XCTAssertTrue(store.state.reviewDraft?.primaryMuscles.contains(.chest) ?? false)
        XCTAssertEqual(store.state.reviewDraft?.bodySignals.count, 1)

        await store.send(.addMuscleToDraft(.deltoids, asPrimary: true))
        XCTAssertTrue(store.state.reviewDraft?.primaryMuscles.contains(.deltoids) ?? false)

        await store.send(.confirmReviewTapped)
        await store.receive(\.reviewPersisted)
        await store.receive(\.delegate.memoryCommitted)

        XCTAssertNil(store.state.reviewDraft)
        XCTAssertFalse(store.state.unreviewedWorkouts.contains(where: { $0.hkUUID == targetWorkout.hkUUID }))
        let chestEstimate = store.state.recoverySnapshot.estimate(for: .chest)
        XCTAssertLessThan(chestEstimate.recoveryRatio, 0.85)
        XCTAssertGreaterThan(chestEstimate.hoursUntilReady, 0.0)
        XCTAssertTrue(chestEstimate.disclaimer.contains("启发式估计"))

        do {
            let savedAnns = try await storeClient.loadWorkoutAnnotations(targetWorkout.hkUUID)
            XCTAssertEqual(savedAnns.count, 1)
            XCTAssertTrue(savedAnns[0].rawText.contains("右肩前束略紧"))
        } catch {
            XCTFail("Expected persisted annotation, got error: \(error)")
        }
    }
}
