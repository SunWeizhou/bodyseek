import BodySeekAgent
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

    func testCoachAgentUpdatesMemoriesAndEmitsProposal() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 14),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "示例数据",
            isAuthorized: true
        )
        let pendingMem = TieredMemoryRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000050")!,
            tier: .activeConstraint,
            content: "右膝微痛，减免大重量深蹲",
            scopeJSON: #"{"category":"injury"}"#,
            confidence: 0.95,
            expiresAt: now.addingTimeInterval(14 * 86_400),
            confirmedAt: now
        )
        let proposal = WorkoutProposal(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000051")!,
            template: ExerciseCatalog.defaultTemplates[0],
            rationale: "优先安排上肢推力训练"
        )
        let replyID = UUID(uuidString: "00000000-0000-0000-0000-000000000052")!
        let storeClient = BodySeekStoreClient.previewValue

        let store = TestStore(
            initialState: CoachFeature.State(snapshot: snapshot)
        ) {
            CoachFeature()
        } withDependencies: {
            $0.coachAIClient.reply = { _, context in
                await context.effects.recordMemoryProposal(pendingMem)
                await context.effects.recordProposal(proposal)
                return CoachMessage(
                    id: replyID,
                    role: .assistant,
                    text: "已整理右膝限制提案与上肢替代课表，请确认后写入。",
                    engineLabel: "Test AI",
                    timestamp: now,
                    evidenceMetric: .recovery,
                    workoutProposal: proposal,
                    memorySavedNote: "待你确认记忆",
                    memoryProposal: pendingMem,
                    toolsInvoked: ["get_today_context", "propose_memory", "propose_plan_change"]
                )
            }
            $0.fitnessStoreClient = .previewValue
            $0.bodySeekStoreClient = storeClient
            $0.uuid = .incrementing
            $0.date.now = now
        }
        store.exhaustivity = .off

        await store.send(.quickPromptTapped("记住右膝痛，帮我排上肢课表"))
        await store.receive(\.aiReplyReceived)

        // Confirm-to-write invariant: NOTHING is saved until user confirms the proposal card!
        XCTAssertTrue(store.state.memories.isEmpty)
        XCTAssertTrue(store.state.tieredMemories.isEmpty)
        let preAudit = try await storeClient.loadActionAuditEntries(10)
        XCTAssertTrue(preAudit.isEmpty)
        XCTAssertEqual(store.state.messages.last?.workoutProposal?.template.title, proposal.template.title)
        XCTAssertEqual(store.state.messages.last?.memoryProposal?.content, "右膝微痛，减免大重量深蹲")

        await store.send(.confirmMemoryProposalTapped(messageID: replyID, memory: pendingMem))
        await store.receive(\.memoryProposalCommitted)
        await store.receive(\.delegate.tieredMemoriesUpdated)
        await store.receive(\.delegate.memoriesUpdated)

        XCTAssertEqual(store.state.tieredMemories.count, 1)
        XCTAssertEqual(store.state.memories.first?.content, "右膝微痛，减免大重量深蹲")

        let persistedMemories = try await storeClient.loadTieredMemories(false)
        XCTAssertEqual(persistedMemories.count, 1)
        let postAudit = try await storeClient.loadActionAuditEntries(10)
        XCTAssertEqual(postAudit.count, 1)
        XCTAssertEqual(postAudit.first?.origin, .agent)
        XCTAssertEqual(postAudit.first?.decision, .applied)

        // Retiring the memory writes an audit entry and removes it from active list
        await store.send(.retireTieredMemoryTapped(pendingMem.id))
        let afterRetireActive = try await storeClient.loadTieredMemories(false)
        XCTAssertTrue(afterRetireActive.isEmpty)
        let auditCountAfterRetire = try await storeClient.loadActionAuditEntries(10).count
        XCTAssertEqual(auditCountAfterRetire, 2)
    }

    func testCoachAnnotationCandidateSelectionBindsOneWorkout() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 14),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "示例数据",
            isAuthorized: true
        )
        let start = now.addingTimeInterval(-12 * 3600)
        let parsed = ChineseWorkoutLexiconParser.parse("昨晚练腿，深蹲 5 组 RPE 8")
        let proposal = CoachWorkoutAnnotationProposal(
            workoutUUID: "W-COACH-1",
            workoutTitle: "传统力量训练",
            rawText: "昨晚练腿，深蹲 5 组 RPE 8",
            proposal: parsed,
            muscleLoads: [],
            recordState: WorkoutAnnotationRecordState(
                workoutUUID: "W-COACH-1",
                start: start,
                end: start.addingTimeInterval(3600),
                type: "传统力量训练",
                reviewState: .unreviewed
            )
        )
        let candidate = CoachWorkoutAnnotationCandidate(
            proposal: proposal,
            start: start,
            end: start.addingTimeInterval(3600),
            dayKey: "2026-10-13",
            source: "healthkit",
            reviewState: .unreviewed
        )
        let messageID = UUID(uuidString: "00000000-0000-4000-8000-000000000099")!
        var state = CoachFeature.State(snapshot: snapshot)
        state.messages = [
            CoachMessage(
                id: messageID,
                role: .assistant,
                text: "找到两条训练，请选择。",
                timestamp: now,
                workoutAnnotationCandidates: [candidate]
            ),
        ]

        let store = TestStore(initialState: state) {
            CoachFeature()
        } withDependencies: {
            $0.bodySeekStoreClient = .previewValue
            $0.fitnessStoreClient = .previewValue
            $0.date.now = now
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.selectAnnotationCandidate(messageID: messageID, candidate: candidate))
        XCTAssertEqual(store.state.annotationCandidateSelections[messageID]?.workoutUUID, "W-COACH-1")
        XCTAssertEqual(store.state.annotationCandidateSelections[messageID]?.recordState?.latestAnnotationID, nil)

        await store.send(.dismissAnnotationProposalTapped(messageID))
        XCTAssertNil(store.state.annotationCandidateSelections[messageID])
    }

    func testCoachCandidatePatternPromotionAndTodayProactiveInsights() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 21),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "示例数据",
            isAuthorized: true
        )
        let candidate = PatternFindingRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000888")!,
            statement: "23:30 前入睡与次日 HRV 较高相关",
            effect: 5.5,
            ciLow: 2.0,
            ciHigh: 9.0,
            sampleSize: 90,
            method: "FDR",
            modelVersion: "v1",
            status: .candidate
        )
        let storeClient = BodySeekStoreClient.previewValue
        try await storeClient.savePatternFinding(candidate)

        var initialCoachState = CoachFeature.State(snapshot: snapshot)
        initialCoachState.patternFindings = [candidate]

        let coachStore = TestStore(initialState: initialCoachState) {
            CoachFeature()
        } withDependencies: {
            $0.bodySeekStoreClient = storeClient
            $0.fitnessStoreClient = .previewValue
            $0.date.now = now
            $0.uuid = .incrementing
        }
        coachStore.exhaustivity = .off

        await coachStore.send(.confirmCandidatePatternTapped(candidate))
        await coachStore.receive(\.candidatePatternConfirmed)

        XCTAssertEqual(coachStore.state.patternFindings.first?.status, .confirmed)
        XCTAssertEqual(coachStore.state.tieredMemories.first?.tier, .verifiedPattern)
        let verifiedMems = try await storeClient.loadTieredMemories(false)
        XCTAssertEqual(verifiedMems.first?.tier, .verifiedPattern)

        // Proactive insight dismissal & toggle behavior on AppFeature
        let appStore = TestStore(
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
            $0.bodySeekStoreClient = .previewValue
            $0.coachAIClient = .previewValue
            $0.continuousClock = ImmediateClock()
            $0.date.now = now
        }
        appStore.exhaustivity = .off

        XCTAssertLessThanOrEqual(appStore.state.today.proactiveInsights.count, 2)
        if let firstInsight = appStore.state.today.proactiveInsights.first {
            let beforeCount = appStore.state.today.proactiveInsights.count
            await appStore.send(.today(.dismissProactiveInsightTapped(firstInsight.id)))
            XCTAssertEqual(appStore.state.today.proactiveInsights.count, beforeCount - 1)
        }
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
