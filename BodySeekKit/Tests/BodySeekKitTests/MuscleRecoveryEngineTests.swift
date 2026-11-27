import BodySeekCore
import BodySeekStore
import Foundation
import XCTest

final class MuscleRecoveryEngineTests: XCTestCase {
    func testLinkedManualWorkoutFillsMissingMusclesWithoutDoubleCountingExistingLoads() {
        let now = Date(timeIntervalSince1970: 1_760_500_000)
        let start = now.addingTimeInterval(-3600)
        let end = now.addingTimeInterval(-600)
        let workout = StoredWorkoutRecord(hkUUID: "watch-1", type: "力量训练", start: start, end: end,
                                           energy: 180, reviewState: .annotated)
        let exercise = LoggedExerciseRecord(exerciseID: "barbell-bench-press", sets: [
            .init(setIndex: 0, weightKg: 60, reps: 8, isCompleted: true),
        ])
        let session = LoggedWorkoutSession(title: "卧推", startedAt: start, completedAt: end,
                                           exercises: [exercise], rpe: 7, estimatedCalories: 180,
                                           syncedHealthKitUUID: "WATCH-1")
        let existing = WorkoutMuscleLoadRecord(workoutUUID: workout.hkUUID, muscle: .triceps,
                                               role: .secondary, load: 0.3)
        let result = MuscleRecoveryEngine.compute(asOf: now, storedWorkouts: [workout],
                                                  muscleLoads: [existing], manualSessions: [session])
        XCTAssertLessThan(result.estimate(for: .chest).recoveryRatio, 1)
        let importedOnly = MuscleRecoveryEngine.compute(asOf: now, storedWorkouts: [workout], muscleLoads: [existing])
        XCTAssertEqual(result.estimate(for: .triceps).recoveryRatio, importedOnly.estimate(for: .triceps).recoveryRatio)
    }

    func testExponentialRecoveryRemainsStrictlyPositiveUnderHeavyStackedLoads() {
        let asOf = Date(timeIntervalSince1970: 1_760_500_000)
        let w1 = StoredWorkoutRecord(
            hkUUID: "W-HEAVY-1",
            type: "传统力量训练",
            start: asOf.addingTimeInterval(-3 * 3600),
            end: asOf.addingTimeInterval(-2 * 3600),
            energy: 360
        )
        let w2 = StoredWorkoutRecord(
            hkUUID: "W-HEAVY-2",
            type: "传统力量训练",
            start: asOf.addingTimeInterval(-1.5 * 3600),
            end: asOf.addingTimeInterval(-0.5 * 3600),
            energy: 420
        )
        let loads = [
            WorkoutMuscleLoadRecord(workoutUUID: "W-HEAVY-1", muscle: .quadriceps, role: .primary, load: 1.4),
            WorkoutMuscleLoadRecord(workoutUUID: "W-HEAVY-2", muscle: .quadriceps, role: .primary, load: 1.4),
        ]

        let snapshot = MuscleRecoveryEngine.compute(
            asOf: asOf,
            storedWorkouts: [w1, w2],
            muscleLoads: loads
        )
        let quad = snapshot.estimate(for: .quadriceps)
        XCTAssertGreaterThan(quad.fatigue, 2.0)
        XCTAssertGreaterThan(quad.recoveryRatio, 0.0, "exp(-F_m) must never turn negative")
        XCTAssertLessThanOrEqual(quad.recoveryRatio, 1.0)
        XCTAssertGreaterThan(quad.hoursUntilReady, 0.0)
        XCTAssertEqual(quad.algorithmVersion, .recoveryHeuristicV1)
        XCTAssertTrue(quad.disclaimer.contains("启发式估计"))
    }

    func testSystemicAlphaDependsOnlyOnPriorSleepHRVRHRWithoutCircularStrainDependency() {
        let cal = Calendar(identifier: .gregorian)
        let asOf = Date(timeIntervalSince1970: 1_760_500_000)

        var rawDays = PreviewSeedFactory.makeRawWindow(endingAt: asOf, days: 30, calendar: cal)
        let lastIdx = rawDays.count - 1
        // Set very short sleep and depressed HRV on today to slow systemic recovery
        rawDays[lastIdx].sleepAsleepMinutes = 310
        rawDays[lastIdx].hrvMs = 30
        rawDays[lastIdx].restingHeartRateBpm = 68

        let computed = BevelScoringEngine.computeWindow(
            rawDays: rawDays,
            sleepGoalMinutes: 450,
            referenceDate: asOf,
            sourceLabel: "测试",
            isAuthorized: true
        )
        let alphaLowSleep = MuscleRecoveryEngine.computeSystemicFactor(
            historyDays: computed.historyDays,
            referenceDate: asOf,
            sleepGoalMinutes: 450
        ).alpha

        // Corrupt today's activeEnergy / exerciseMinutes / workouts (Strain inputs): alpha MUST stay identical!
        var alteredRawDays = rawDays
        alteredRawDays[lastIdx].activeEnergyKcal = 2200
        alteredRawDays[lastIdx].exerciseMinutes = 140
        alteredRawDays[lastIdx].workouts = [
            WorkoutSummary(
                activityName: "马拉松",
                symbolName: "figure.run",
                startDate: asOf.addingTimeInterval(-3600),
                durationMinutes: 140,
                activeEnergyKcal: 1800
            ),
        ]
        let alteredComputed = BevelScoringEngine.computeWindow(
            rawDays: alteredRawDays,
            sleepGoalMinutes: 450,
            referenceDate: asOf,
            sourceLabel: "测试",
            isAuthorized: true
        )
        let alphaAfterHeavyStrain = MuscleRecoveryEngine.computeSystemicFactor(
            historyDays: alteredComputed.historyDays,
            referenceDate: asOf,
            sleepGoalMinutes: 450
        ).alpha

        XCTAssertGreaterThan(alphaLowSleep, 1.05)
        XCTAssertEqual(alphaLowSleep, alphaAfterHeavyStrain, accuracy: 1e-9)
    }

    func testAutoAttributionSeparatesCardioBadmintonDominantHandFromStrengthInbox() {
        let now = Date(timeIntervalSince1970: 1_760_500_000)

        let strength = StoredWorkoutRecord(
            hkUUID: "STR-1",
            type: "传统力量训练 · Apple Watch",
            start: now.addingTimeInterval(-3600),
            end: now,
            energy: 280
        )
        XCTAssertTrue(WorkoutAutoAttributor.isStrengthWorkout(type: strength.type))
        XCTAssertNil(WorkoutAutoAttributor.autoAttribute(workout: strength, dominantHand: .right))

        let run = StoredWorkoutRecord(
            hkUUID: "RUN-1",
            type: "户外跑步 · Apple Watch",
            start: now.addingTimeInterval(-2400),
            end: now,
            energy: 360,
            zones: WorkoutHeartRateZones(zone1Minutes: 4, zone2Minutes: 14, zone3Minutes: 15, zone4Minutes: 7, zone5Minutes: 0)
        )
        let runAttr = WorkoutAutoAttributor.autoAttribute(workout: run, dominantHand: .right)
        XCTAssertNotNil(runAttr)
        XCTAssertTrue(runAttr?.loads.contains(where: { $0.muscle == .quadriceps && $0.role == .primary }) ?? false)
        XCTAssertTrue(runAttr?.loads.contains(where: { $0.muscle == .calves && $0.role == .primary }) ?? false)

        let badminton = StoredWorkoutRecord(
            hkUUID: "BAD-1",
            type: "羽毛球 · Apple Watch",
            start: now.addingTimeInterval(-3600),
            end: now,
            energy: 420,
            avgHR: 146
        )
        let rightAttr = WorkoutAutoAttributor.autoAttribute(workout: badminton, dominantHand: .right)
        let leftAttr = WorkoutAutoAttributor.autoAttribute(workout: badminton, dominantHand: .left)
        XCTAssertTrue(rightAttr?.note.contains("持拍右手") ?? false)
        XCTAssertTrue(leftAttr?.note.contains("持拍左手") ?? false)
        XCTAssertTrue(rightAttr?.loads.contains(where: { $0.muscle == .deltoids && $0.role == .primary }) ?? false)
        XCTAssertTrue(rightAttr?.loads.contains(where: { $0.muscle == .forearm && $0.role == .primary }) ?? false)
    }

    func testDatabaseReviewWorkflowPersistsAnnotationLoadsMemory14dAndAuditTrail() async throws {
        let db = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: db)
        let executor = ActionExecutor(database: db)
        let now = Date(timeIntervalSince1970: 1_760_500_000)

        let workout = StoredWorkoutRecord(
            hkUUID: "HK-STR-M2",
            type: "传统力量训练 · Apple Watch",
            start: now.addingTimeInterval(-3000),
            end: now,
            energy: 310,
            avgHR: 132,
            effortUser: 8.0,
            effortEstimated: 7.0,
            reviewState: .unreviewed
        )
        try await repo.upsertWorkouts([workout], symbolByUUID: ["HK-STR-M2": "dumbbell.fill"])

        // Attempt auto-attribution on strength workout must not happen
        XCTAssertNil(WorkoutAutoAttributor.autoAttribute(workout: workout, dominantHand: .right))

        let proposalParsed = ChineseWorkoutLexiconParser.parse("今天推日，杠铃卧推和哑铃推举 RPE 8，右肩前束略紧")
        let loads = WorkoutLoadBuilder.buildMuscleLoads(
            workoutUUID: workout.hkUUID,
            durationMinutes: 50,
            primaryMuscles: proposalParsed.primaryMuscles,
            secondaryMuscles: proposalParsed.secondaryMuscles,
            rpe: proposalParsed.rpe ?? 8
        )
        XCTAssertFalse(loads.isEmpty)

        let annotateProposal = try ActionProposal(
            kind: .annotateWorkout,
            origin: .user,
            encodablePayload: AnnotateWorkoutPayload(
                workoutUUID: workout.hkUUID,
                rawText: proposalParsed.rawText,
                parserVersion: .workoutParserV1,
                muscleLoads: loads,
                reviewState: .annotated
            ),
            rationale: "用户确认 Watch 力量训练复盘"
        )
        _ = try await executor.execute(annotateProposal, now: now)

        if let signal = proposalParsed.bodySignals.first {
            let mem = TieredMemoryRecord(
                tier: .activeConstraint,
                content: signal.suggestedConstraint,
                scopeJSON: #"{"muscle":"deltoids","source":"workout_review"}"#,
                confidence: 0.9,
                expiresAt: now.addingTimeInterval(Double(signal.defaultExpiryDays) * 86_400),
                confirmedAt: now
            )
            let memProposal = try ActionProposal(
                kind: .commitMemory,
                origin: .user,
                encodablePayload: CommitMemoryPayload(memory: mem),
                rationale: "练后身体信号转为 14 天 Active Constraint"
            )
            _ = try await executor.execute(memProposal, now: now)
        }

        let loadedWorkouts = try await repo.loadWorkouts(limit: nil)
        XCTAssertEqual(loadedWorkouts.first?.reviewState, .annotated)
        XCTAssertEqual(loadedWorkouts.first?.effortUser, 8.0)
        XCTAssertEqual(loadedWorkouts.first?.effortEstimated, 7.0)

        let loadedAnnotations = try await repo.loadWorkoutAnnotations(workoutUUID: workout.hkUUID)
        XCTAssertEqual(loadedAnnotations.count, 1)
        XCTAssertTrue(loadedAnnotations[0].rawText.contains("右肩前束略紧"))

        let loadedLoads = try await repo.loadAllMuscleLoads()
        XCTAssertTrue(loadedLoads.contains(where: { $0.muscle == .chest && $0.role == .primary }))

        let allMemories = try await repo.loadTieredMemories(includeRetired: false)
        let memories = allMemories.filter { $0.tier == .activeConstraint && $0.isActive(at: now) }
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.first?.expiresAt?.timeIntervalSince(now) ?? 0, 14 * 86_400, accuracy: 1.0)

        // Running recovery snapshot picks up DB loads cleanly
        let recSnap = MuscleRecoveryEngine.compute(
            asOf: now.addingTimeInterval(3600),
            storedWorkouts: loadedWorkouts,
            muscleLoads: loadedLoads
        )
        XCTAssertLessThan(recSnap.estimate(for: .chest).recoveryRatio, 0.80)
    }
}
