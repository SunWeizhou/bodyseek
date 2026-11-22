import BodySeekCore
import BodySeekStore
import Foundation
import XCTest

final class BodySeekStoreTests: XCTestCase {
    func testCoachAnnotationDecisionSurvivesReloadAndOldActionCannotOverwriteCorrection() async throws {
        let database = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: database)
        let executor = ActionExecutor(database: database)
        let now = Date()
        let workout = StoredWorkoutRecord(hkUUID: UUID().uuidString, type: "力量", start: now, end: now, energy: 200)
        try await repo.upsertWorkouts([workout])
        let parsed = WorkoutAnnotationProposal(rawText: "练胸", primaryMuscles: [.chest])
        let draft = CoachWorkoutAnnotationProposal(workoutUUID: workout.hkUUID, workoutTitle: workout.type,
                                                   rawText: parsed.rawText, proposal: parsed, muscleLoads: [])
        let message = CoachMessage(role: .assistant, text: "复盘提议", workoutAnnotationProposal: draft)
        try await repo.appendMessage(message)
        let first = try ActionProposal(id: message.id, kind: .annotateWorkout, origin: .agent,
                                      encodablePayload: AnnotateWorkoutPayload(workoutUUID: workout.hkUUID, rawText: "练胸",
                                                                               coachAnnotationDecision: .applied))
        let audit = try await executor.execute(first)
        let correction = try ActionProposal(kind: .annotateWorkout, origin: .user,
                                            encodablePayload: AnnotateWorkoutPayload(workoutUUID: workout.hkUUID, rawText: "练腿"))
        _ = try await executor.execute(correction)
        let retry = try await executor.execute(first)
        let messages = try await repo.loadMessages()
        let annotations = try await repo.loadWorkoutAnnotations(workoutUUID: workout.hkUUID)
        XCTAssertEqual(retry.id, audit.id)
        XCTAssertEqual(messages.first?.annotationDecision, .applied)
        XCTAssertEqual(annotations.count, 2)
    }

    func testComputedDaysRoundTripAndIncrementalReuse() async throws {
        let db = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: db)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        let dayKey = date.physiologicalDayKey(cutoverHour: 4, timeZone: calendar.timeZone)
        let raw = DailyRawMetrics(
            date: date,
            hrvMs: 52,
            restingHeartRateBpm: 58,
            sleepAsleepMinutes: 430,
            sleepInBedMinutes: 470,
            deepMinutes: 70,
            remMinutes: 95,
            coreMinutes: 265,
            awakeMinutes: 25,
            activeEnergyKcal: 420,
            exerciseMinutes: 35,
            steps: 7200,
            daytimeMeanHeartRateBpm: 71,
            daytimeMaxHeartRateBpm: 132,
            hasAuthorizedHealthData: true,
            sourceNames: ["Fixture"],
            dayKey: dayKey
        )
        try await repo.saveDailyRawMetrics([raw], calendar: calendar)
        let computed = BevelScoringEngine.scoreDay(
            raw,
            priorDays: [],
            sleepGoalMinutes: 450,
            calendar: calendar,
            referenceDate: date
        )
        try await repo.saveComputedDays([computed])

        let loaded = try await repo.loadComputedDays(calendar: calendar)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.dayKey, dayKey)
        XCTAssertEqual(loaded.first?.recovery, computed.recovery)
        XCTAssertEqual(loaded.first?.sleep, computed.sleep)
        XCTAssertEqual(loaded.first?.energyCurve, computed.energyCurve)
        XCTAssertEqual(loaded.first?.raw.hrvMs, 52)

        let snapshot = BevelScoringEngine.recomputeIncremental(
            existingByDayKey: [dayKey: loaded[0]],
            allRawDays: [raw],
            dirtyDayKeys: [],
            sleepGoalMinutes: 450,
            referenceDate: date,
            sourceLabel: "cache-test",
            isAuthorized: true,
            calendar: calendar
        )
        XCTAssertEqual(snapshot.historyDays.count, 1)
        XCTAssertEqual(snapshot.historyDays[0].recovery, computed.recovery)
        XCTAssertEqual(snapshot.historyDays[0].energyCurve, computed.energyCurve)
        XCTAssertEqual(snapshot.historyDays[0].sleepGoalMinutes, 450)

        let changedGoal = BevelScoringEngine.recomputeIncremental(
            existingByDayKey: [dayKey: loaded[0]],
            allRawDays: [raw],
            dirtyDayKeys: [],
            sleepGoalMinutes: 500,
            referenceDate: date,
            sourceLabel: "cache-test",
            isAuthorized: true,
            calendar: calendar
        )
        XCTAssertEqual(changedGoal.historyDays[0].sleepGoalMinutes, 500)
    }

    func testMigrationIdentifiersAreStable() {
        XCTAssertEqual(
            BodySeekDatabase.migrator.migrations,
            ["v1_initial_schema", "v2_nutrition_schema", "v3_allow_unknown_meal_portions", "v4_healthkit_workout_deletions", "v5_action_audit_undo_snapshots", "v6_sleep_goal_cache_key"]
        )
    }

    func testAuditQueryHonorsDatabaseLimit() async throws {
        let db = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: db)
        let payload = try ActionProposal(
            kind: .annotateWorkout,
            origin: .user,
            encodablePayload: AnnotateWorkoutPayload(workoutUUID: "W-1", rawText: "练腿")
        )
        let json = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        try await db.writer.write { db in
            for (offset, id) in ["00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-000000000002"].enumerated() {
                try db.execute(
                    sql: """
                    INSERT INTO action_audit (id, proposal_json, origin, decision, decided_at, affected_ids_json)
                    VALUES (?, ?, 'user', 'applied', ?, '[]')
                    """,
                    arguments: [id, json, 1_000.0 + Double(offset)]
                )
            }
        }
        let limited = try await repo.loadAuditEntries(limit: 1)
        XCTAssertEqual(limited.count, 1)
        XCTAssertEqual(limited.first?.id.uuidString.lowercased(), "00000000-0000-4000-8000-000000000002")
        let all = try await repo.loadAuditEntries()
        XCTAssertEqual(all.count, 2)
    }

    func testSchemaV1CreatesAllFifteenV5TablesAndFTSTriggers() async throws {
        let db = try BodySeekDatabase.inMemory()
        // Re-running migrator on an already-migrated DB must be idempotent.
        try await db.writer.write { rawDB in
            let tables = try String.fetchAll(rawDB, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
            XCTAssertFalse(tables.isEmpty)
        }
        try BodySeekDatabase.migrator.migrate(db.writer)

        let repo = BodySeekRepository(database: db)
        let tableNames = try await repo.existingTableNames()

        let requiredTables: [String] = [
            "sync_anchor",
            "day_metric",
            "hourly_metric",
            "sleep_episode",
            "workout",
            "workout_annotation",
            "workout_muscle_load",
            "score_snapshot",
            "day_computed_artifact",
            "muscle_recovery",
            "check_in",
            "plan_item",
            "memory",
            "action_audit",
            "coach_message",
            "pattern_finding",
            "workout_template",
            "logged_workout_session",
            "memory_fts",
            "workout_annotation_fts",
            "nutrition_profile",
            "nutrition_target_plan",
            "food_library_item",
            "food_library_fts",
            "daily_nutrition_log",
            "meal_entry",
        ]

        for name in requiredTables {
            XCTAssertTrue(tableNames.contains(name), "Missing required GRDB table: \(name)")
        }
    }

    func testRawMetricsWorkoutsCheckInAndPatternRoundTrip() async throws {
        let db = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: db)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))

        let dayKey = DayKey(year: 2026, month: 11, day: 18)
        let dayStart = dayKey.startDate(cutoverHour: 4, timeZone: cal.timeZone)
        let workoutUUID = UUID()
        let sleepStart = dayStart.addingTimeInterval(-5 * 3600)
        let sleepEnd = dayStart.addingTimeInterval(2 * 3600)

        let raw = DailyRawMetrics(
            date: dayStart,
            hrvMs: 64.5,
            restingHeartRateBpm: 53.0,
            respiratoryRateBrpm: 14.3,
            wristTempDeltaC: 0.12,
            oxygenSaturationPct: 98.2,
            sleepAsleepMinutes: 400,
            sleepInBedMinutes: 420,
            deepMinutes: 90,
            remMinutes: 100,
            coreMinutes: 210,
            awakeMinutes: 20,
            sleepStart: sleepStart,
            sleepEnd: sleepEnd,
            sleepSegments: [
                SleepStageSegment(stage: .deep, startDate: sleepStart, endDate: sleepStart.addingTimeInterval(90 * 60)),
                SleepStageSegment(stage: .core, startDate: sleepStart.addingTimeInterval(90 * 60), endDate: sleepEnd),
            ],
            activeEnergyKcal: 520,
            exerciseMinutes: 48,
            steps: 9320,
            workouts: [
                WorkoutSummary(
                    id: workoutUUID,
                    activityName: "羽毛球",
                    symbolName: "figure.badminton",
                    startDate: dayStart.addingTimeInterval(15 * 3600),
                    durationMinutes: 60,
                    activeEnergyKcal: 430,
                    averageHeartRate: 149,
                    effortScore: 8.0,
                    estimatedEffortScore: 7.2,
                    healthKitUUID: workoutUUID
                ),
            ],
            daytimeMeanHeartRateBpm: 76,
            daytimeMaxHeartRateBpm: 171,
            hasAuthorizedHealthData: true,
            sourceNames: ["Apple Watch"],
            dayKey: dayKey,
            walkingHeartRateAvgBpm: 94,
            vo2MaxMlKgMin: 46.8,
            heartRateRecovery1MinBpm: 28,
            bodyMassKg: 71.4,
            physicalEffortKcalPerKgHr: 6.2
        )

        try await repo.saveDailyRawMetrics([raw], calendar: cal)

        let loaded = try await repo.loadRawDays(from: dayKey, to: dayKey, calendar: cal)
        XCTAssertEqual(loaded.count, 1)
        let item = try XCTUnwrap(loaded.first)
        XCTAssertEqual(item.dayKey, dayKey)
        XCTAssertEqual(item.hrvMs, 64.5)
        XCTAssertEqual(item.walkingHeartRateAvgBpm, 94)
        XCTAssertEqual(item.vo2MaxMlKgMin, 46.8)
        XCTAssertEqual(item.heartRateRecovery1MinBpm, 28)
        XCTAssertEqual(item.bodyMassKg, 71.4)
        XCTAssertEqual(item.physicalEffortKcalPerKgHr, 6.2)
        XCTAssertEqual(item.sleepSegments.count, 2)
        XCTAssertEqual(item.workouts.first?.effortScore, 8.0)
        XCTAssertEqual(item.workouts.first?.estimatedEffortScore, 7.2)

        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: loaded,
            sleepGoalMinutes: 450,
            referenceDate: dayStart,
            sourceLabel: "GRDB",
            isAuthorized: true,
            calendar: cal
        )
        try await repo.saveComputedDays(snapshot.historyDays)

        let checkIn = DailyCheckIn(
            dayKey: dayKey,
            recordedAt: dayStart.addingTimeInterval(3600),
            energy: 4,
            mood: 5,
            stress: 2,
            soreness: [.deltoids: 2, .forearm: 1],
            note: "羽毛球后右肩轻微发紧"
        )
        try await repo.saveCheckIn(checkIn)
        let loadedCheckIns = try await repo.loadCheckIns()
        XCTAssertEqual(loadedCheckIns, [checkIn])

        let finding = PatternFindingRecord(
            statement: "睡前 2 小时高强度运动后深睡占比下降 11%",
            effect: -11.0,
            ciLow: -17.5,
            ciHigh: -4.2,
            sampleSize: 42,
            method: "distributed_lag_bootstrap",
            modelVersion: "m4a-v1",
            status: .confirmed
        )
        try await repo.savePatternFinding(finding)
        let findings = try await repo.loadPatternFindings(status: .confirmed)
        XCTAssertEqual(findings, [finding])
    }

    func testActionExecutorAtomicityFTS5AndForeignKeyRollback() async throws {
        let db = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: db)
        let executor = ActionExecutor(database: db)
        let workoutUUID = UUID().uuidString

        // 1. Attempting to annotate a non-existent workout must fail and write ZERO audit/muscle rows.
        let badPayload = AnnotateWorkoutPayload(
            workoutUUID: workoutUUID,
            rawText: "练胸 50 分钟",
            muscleLoads: [
                WorkoutMuscleLoadRecord(workoutUUID: workoutUUID, muscle: .chest, role: .primary, load: 0.7),
            ]
        )
        let badProposal = try ActionProposal(kind: .annotateWorkout, origin: .user, encodablePayload: badPayload)

        do {
            _ = try await executor.execute(badProposal)
            XCTFail("Expected foreign key failure for missing workout row")
        } catch {
            // Expected propagation
        }

        let auditsAfterFailure = try await repo.loadAuditEntries()
        XCTAssertTrue(auditsAfterFailure.isEmpty)
        let loadsAfterFailure = try await repo.loadMuscleLoads(workoutUUID: workoutUUID)
        XCTAssertTrue(loadsAfterFailure.isEmpty)

        // 2. Insert workout then annotate -> annotation + muscle loads + workout state + audit + FTS5 all succeed atomically.
        let now = Date(timeIntervalSince1970: 1_763_500_000)
        try await repo.upsertWorkouts([
            StoredWorkoutRecord(
                hkUUID: workoutUUID,
                type: "传统力量训练",
                start: now.addingTimeInterval(-3600),
                end: now,
                energy: 280,
                avgHR: 132,
                effortUser: 7.5
            ),
        ])

        let goodPayload = AnnotateWorkoutPayload(
            workoutUUID: workoutUUID,
            rawText: "上肢推拉超级组，平板卧推后左肩略酸",
            muscleLoads: [
                WorkoutMuscleLoadRecord(workoutUUID: workoutUUID, muscle: .chest, role: .primary, load: 0.8),
                WorkoutMuscleLoadRecord(workoutUUID: workoutUUID, muscle: .deltoids, role: .secondary, load: 0.35),
            ]
        )
        let goodProposal = try ActionProposal(kind: .annotateWorkout, origin: .user, encodablePayload: goodPayload)
        let audit = try await executor.execute(goodProposal, now: now)
        XCTAssertEqual(audit.decision, .applied)

        let workouts = try await repo.loadWorkouts()
        XCTAssertEqual(workouts.first?.reviewState, .annotated)
        let loadedMuscles = try await repo.loadMuscleLoads(workoutUUID: workoutUUID)
        XCTAssertEqual(loadedMuscles.count, 2)

        let annotationHits = try await repo.searchWorkoutAnnotationsFTS(query: "卧推")
        XCTAssertEqual(annotationHits.count, 1)
        XCTAssertEqual(annotationHits.first?.workoutUUID, workoutUUID)
        let trigramAnnotationHits = try await repo.searchWorkoutAnnotationsFTS(query: "平板卧推")
        XCTAssertEqual(trigramAnnotationHits.map(\.workoutUUID), [workoutUUID])

        // 3. Memory commit -> FTS5 search -> retire removes from active FTS5 search.
        let memory = TieredMemoryRecord(
            tier: .activeConstraint,
            content: "右膝深蹲超过 90 度有弹响",
            expiresAt: now.addingTimeInterval(14 * 86_400),
            confirmedAt: now
        )
        let commitMem = try ActionProposal(
            kind: .commitMemory,
            origin: .agent,
            encodablePayload: CommitMemoryPayload(memory: memory)
        )
        _ = try await executor.execute(commitMem, now: now)
        let ftsHits = try await repo.searchMemoriesFTS(query: "右膝")
        XCTAssertEqual(ftsHits.map(\.id), [memory.id])
        let trigramMemoryHits = try await repo.searchMemoriesFTS(query: "右膝深蹲")
        XCTAssertEqual(trigramMemoryHits.map(\.id), [memory.id])

        let retireMem = try ActionProposal(
            kind: .retireMemory,
            origin: .user,
            encodablePayload: RetireMemoryPayload(memoryID: memory.id, retiredAt: now.addingTimeInterval(60))
        )
        _ = try await executor.execute(retireMem, now: now.addingTimeInterval(60))
        let ftsAfterRetire = try await repo.searchMemoriesFTS(query: "右膝")
        XCTAssertTrue(ftsAfterRetire.isEmpty)
        let trigramAfterRetire = try await repo.searchMemoriesFTS(query: "右膝深蹲")
        XCTAssertTrue(trigramAfterRetire.isEmpty)

        // 4. Plan adjust + check-in proposals + rejection audit.
        let planItem = PlanItemRecord(
            dayKey: DayKey(year: 2026, month: 11, day: 19),
            kind: .recoveryAction,
            payloadJSON: "{\"title\":\"23:00 前关灯入睡\"}",
            state: .adopted,
            origin: .agent
        )
        _ = try await executor.execute(
            ActionProposal(kind: .adjustPlan, origin: .agent, encodablePayload: AdjustPlanPayload(item: planItem)),
            now: now
        )
        let plans = try await repo.loadPlanItems(dayKey: DayKey(year: 2026, month: 11, day: 19))
        XCTAssertEqual(plans, [planItem])

        let checkIn = DailyCheckIn(dayKey: DayKey(year: 2026, month: 11, day: 19), recordedAt: now, energy: 5, mood: 5, stress: 1)
        _ = try await executor.execute(
            ActionProposal(kind: .recordCheckIn, origin: .user, encodablePayload: RecordCheckInPayload(checkIn: checkIn)),
            now: now
        )
        let checkIns = try await repo.loadCheckIns()
        XCTAssertEqual(checkIns, [checkIn])

        let rejectProposal = try ActionProposal(kind: .adjustPlan, origin: .agent, encodablePayload: AdjustPlanPayload(item: planItem))
        let rejectedAudit = try await executor.reject(rejectProposal, now: now)
        XCTAssertEqual(rejectedAudit.decision, .rejected)
    }

    func testLegacyDataImporterIsIdempotent() async throws {
        let db = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: db)
        let now = Date(timeIntervalSince1970: 1_763_500_000)

        let payload = LegacyImportPayload(
            templates: Array(ExerciseCatalog.defaultTemplates.prefix(1)),
            sessions: PreviewSeedFactory.makeSampleLoggedWorkouts(referenceDate: now),
            memories: [AthleteMemoryItem(category: .injury, content: "左肩盂唇敏感", updatedAt: now)],
            messages: [CoachMessage(role: .user, text: "昨晚睡得一般", timestamp: now)],
            checkIns: [DailyCheckIn(dayKey: DayKey(year: 2026, month: 11, day: 18), recordedAt: now, energy: 3, mood: 4, stress: 2)]
        )

        let first = try await LegacyDataImporter.importIfNeeded(into: repo, now: now) { payload }
        XCTAssertFalse(first.alreadyImported)
        XCTAssertEqual(first.templatesImported, 1)
        XCTAssertEqual(first.sessionsImported, payload.sessions.count)
        XCTAssertEqual(first.memoriesImported, 1)
        XCTAssertEqual(first.messagesImported, 1)
        XCTAssertEqual(first.checkInsImported, 1)

        let second = try await LegacyDataImporter.importIfNeeded(into: repo, now: now) {
            XCTFail("Provider should not be called after initial legacy import")
            return payload
        }
        XCTAssertTrue(second.alreadyImported)
        XCTAssertEqual(second.totalImported, 0)

        let messages = try await repo.loadMessages()
        XCTAssertEqual(messages.count, 1)
    }

    func testSleepMergePolicyPrioritizesWatchOverAutoSleepAndIPhoneSeparatingNaps() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))

        func date(_ day: Int, _ hour: Int, _ min: Int) throws -> Date {
            try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: min)))
        }

        let watchSource = SourceRef(
            bundleIdentifier: "com.apple.health.watch",
            name: "Joe’s Apple Watch",
            deviceModel: "Watch7,1",
            priority: 100
        )
        let autoSleepSource = SourceRef(
            bundleIdentifier: "com.tantsissa.AutoSleep",
            name: "AutoSleep",
            deviceModel: "iPhone17,1",
            priority: 60
        )
        let iPhoneSource = SourceRef(
            bundleIdentifier: "com.apple.health",
            name: "iPhone",
            deviceModel: "iPhone17,1",
            priority: 10
        )

        let samples: [RawSleepSample] = [
            // Coarse iPhone InBed spanning entire night 23:00 -> 07:00
            RawSleepSample(
                startDate: try date(18, 23, 0),
                endDate: try date(19, 7, 0),
                stage: .inBed,
                source: iPhoneSource
            ),
            // Overlapping AutoSleep unspecified 23:00 -> 07:00
            RawSleepSample(
                startDate: try date(18, 23, 0),
                endDate: try date(19, 7, 0),
                stage: .asleepUnspecified,
                source: autoSleepSource
            ),
            // Apple Watch detailed stages covering 23:00 -> 05:30 (leaving 05:30..07:00 to AutoSleep fallback)
            RawSleepSample(
                startDate: try date(18, 23, 0),
                endDate: try date(19, 0, 30),
                stage: .deep,
                source: watchSource
            ),
            RawSleepSample(
                startDate: try date(19, 0, 30),
                endDate: try date(19, 3, 30),
                stage: .core,
                source: watchSource
            ),
            RawSleepSample(
                startDate: try date(19, 3, 30),
                endDate: try date(19, 5, 30),
                stage: .rem,
                source: watchSource
            ),
            // Separate daytime nap 13:30 -> 14:15 (> 90m gap after 07:00)
            RawSleepSample(
                startDate: try date(19, 13, 30),
                endDate: try date(19, 14, 15),
                stage: .asleepUnspecified,
                source: autoSleepSource
            ),
        ]

        let merged = SleepMergePolicy.merge(samples: samples, cutoverHour: 4, timeZone: cal.timeZone)
        let nov19Key = DayKey(year: 2026, month: 11, day: 19)
        let result = try XCTUnwrap(merged[nov19Key])

        XCTAssertEqual(result.mergePolicyVersion, .sleepMergeV1)
        XCTAssertEqual(result.episodes.count, 2)
        XCTAssertEqual(result.naps.count, 1)

        let primary = try XCTUnwrap(result.primaryEpisode)
        XCTAssertTrue(primary.isPrimarySleep)
        XCTAssertEqual(primary.primarySource, watchSource)
        // Exact non-overlapping total = 8 hours = 480 min (zero double counting across 3 sources!)
        XCTAssertEqual(primary.asleepMinutes, 480)
        XCTAssertEqual(primary.deepMinutes, 90)
        XCTAssertEqual(primary.coreMinutes, 180)
        XCTAssertEqual(primary.remMinutes, 120)

        // Verify adjacent segments do not overlap
        for idx in 1..<primary.segments.count {
            XCTAssertLessThanOrEqual(primary.segments[idx - 1].endDate, primary.segments[idx].startDate)
        }

        // Total across overnight + 45m nap = 525 min
        XCTAssertEqual(result.totalAsleepMinutes, 525)
        XCTAssertEqual(result.naps.first?.asleepMinutes, 45)
    }

    func testReadModelFallsBackWhenCachedArtifactIsCorrupt() async throws {
        let db = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: db)
        let readModel = BodySeekReadModel(database: db)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
        let dayKey = date.physiologicalDayKey(cutoverHour: 4, timeZone: calendar.timeZone)
        let raw = DailyRawMetrics(
            date: date,
            hrvMs: 50,
            restingHeartRateBpm: 60,
            sleepAsleepMinutes: 420,
            activeEnergyKcal: 380,
            hasAuthorizedHealthData: true,
            sourceNames: ["Fixture"],
            dayKey: dayKey
        )
        try await repo.saveDailyRawMetrics([raw], calendar: calendar)
        let computed = BevelScoringEngine.scoreDay(raw, priorDays: [], sleepGoalMinutes: 450, calendar: calendar)
        try await repo.saveComputedDays([computed])
        try await db.writer.write { db in
            try db.execute(
                sql: "UPDATE day_computed_artifact SET energy_curve_json = 'not-json' WHERE day_key = ?",
                arguments: [dayKey.isoString]
            )
        }

        let cached = try await readModel.loadCachedDashboard(
            sleepGoalMinutes: 450,
            referenceDate: date,
            sourceLabel: "Fixture",
            isAuthorized: true,
            calendar: calendar
        )
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.snapshot.historyDays.count, 1)
        XCTAssertEqual(cached?.snapshot.historyDays.first?.recovery.value, computed.recovery.value)
    }

    func testReadModelPrecomputesChartCacheAndDeduplicatesIdenticalContentDigest() async throws {
        let db = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: db)
        let readModel = BodySeekReadModel(database: db)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))

        let refDate = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12)))
        let rawDays = PreviewSeedFactory.makeRawWindow(endingAt: refDate, days: 45, calendar: cal)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: rawDays,
            sleepGoalMinutes: 450,
            referenceDate: refDate,
            sourceLabel: "Apple 健康",
            isAuthorized: true,
            calendar: cal
        )

        try await repo.saveDailyRawMetrics(rawDays, calendar: cal)
        try await repo.saveComputedDays(snapshot.historyDays)

        let cachedOptional = try await readModel.loadCachedDashboard(
            sleepGoalMinutes: 450,
            referenceDate: refDate,
            sourceLabel: "Apple 健康",
            isAuthorized: true,
            calendar: cal
        )
        let cached = try XCTUnwrap(cachedOptional)
        XCTAssertEqual(cached.snapshot.historyDays.count, rawDays.count)
        XCTAssertEqual(cached.chartCache[.threeYears]?[.recovery]?.totalDays, 1095)
        XCTAssertEqual(cached.chartCache[.month]?[.recovery]?.coveredDays, cached.chartCache[.month]?[.recovery]?.dailyPoints.filter { $0.value != nil }.count)

        let firstExp = expectation(description: "Initial ReadModel emission")
        let changeExp = expectation(description: "Second emission after real metric change")
        actor EmissionCounter {
            var states: [CachedDashboardState] = []
            func append(_ s: CachedDashboardState) -> Int {
                states.append(s)
                return states.count
            }
            func count() -> Int { states.count }
            func all() -> [CachedDashboardState] { states }
        }
        let counter = EmissionCounter()
        let tz = cal.timeZone

        let stream = readModel.observeDashboard(
            sleepGoalMinutes: 450,
            referenceDateProvider: { refDate },
            sourceLabel: "Apple 健康",
            isAuthorized: true,
            calendar: cal
        )

        let task = Task {
            for try await state in stream {
                let c = await counter.append(state)
                if c == 1 {
                    firstExp.fulfill()
                } else if c == 2 {
                    changeExp.fulfill()
                }
            }
        }
        defer { task.cancel() }

        await fulfillment(of: [firstExp], timeout: 2.0)

        // Re-write identical raw data + new computedAt timestamp -> SHA256 contentDigest unchanged -> 0 new emissions.
        try await repo.saveDailyRawMetrics(rawDays, calendar: cal)
        try await repo.saveComputedDays(snapshot.historyDays, computedAt: refDate.addingTimeInterval(300))
        try await Task.sleep(for: .milliseconds(150))
        let countAfterIdenticalRewrite = await counter.count()
        XCTAssertEqual(countAfterIdenticalRewrite, 1)

        // Mutate a real HRV metric -> triggers real digest change -> 2nd emission delivered.
        var mutatedRaw = rawDays
        var calCopy = Calendar(identifier: .gregorian)
        calCopy.timeZone = tz
        mutatedRaw[mutatedRaw.count - 1].hrvMs = (mutatedRaw[mutatedRaw.count - 1].hrvMs ?? 55) + 22
        let updatedSnapshot = BevelScoringEngine.computeWindow(
            rawDays: mutatedRaw,
            sleepGoalMinutes: 450,
            referenceDate: refDate,
            sourceLabel: "Apple 健康",
            isAuthorized: true,
            calendar: calCopy
        )
        try await repo.saveDailyRawMetrics([mutatedRaw[mutatedRaw.count - 1]], calendar: calCopy)
        try await repo.saveComputedDays([updatedSnapshot.historyDays[updatedSnapshot.historyDays.count - 1]], computedAt: refDate.addingTimeInterval(600))

        await fulfillment(of: [changeExp], timeout: 2.0)
        let states = await counter.all()
        XCTAssertEqual(states.count, 2)
        XCTAssertNotEqual(states[0].contentDigest, states[1].contentDigest)
    }
}
