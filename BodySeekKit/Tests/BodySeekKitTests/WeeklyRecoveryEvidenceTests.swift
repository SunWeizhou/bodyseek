import BodySeekAgent
import BodySeekCore
import XCTest

final class WeeklyRecoveryEvidenceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    private func date(_ key: DayKey) -> Date {
        key.startDate(cutoverHour: 4, timeZone: calendar.timeZone)
    }

    private func day(
        _ key: DayKey,
        recovery: MetricScore? = nil,
        sleep: MetricScore? = nil,
        strain: MetricScore? = nil,
        stress: MetricScore? = nil,
        energy: MetricScore? = nil,
        hrv: Double? = 50,
        rhr: Double? = 60,
        asleep: Int? = 420,
        activeEnergy: Double? = 300,
        exerciseMinutes: Int? = 30
    ) -> DailyComputedDay {
        let raw = DailyRawMetrics(
            date: date(key),
            hrvMs: hrv,
            restingHeartRateBpm: rhr,
            sleepAsleepMinutes: asleep,
            sleepInBedMinutes: asleep.map { $0 + 20 },
            deepMinutes: asleep.map { Int(Double($0) * 0.2) },
            remMinutes: asleep.map { Int(Double($0) * 0.22) },
            coreMinutes: asleep.map { Int(Double($0) * 0.58) },
            awakeMinutes: 18,
            sleepStart: date(key).addingTimeInterval(-7 * 3600),
            sleepEnd: date(key).addingTimeInterval(-1 * 3600),
            activeEnergyKcal: activeEnergy,
            exerciseMinutes: exerciseMinutes,
            steps: 7000,
            workouts: [],
            daytimeMeanHeartRateBpm: 72,
            daytimeMaxHeartRateBpm: 120,
            hasAuthorizedHealthData: true,
            sourceNames: ["fixture"],
            dayKey: key
        )
        func score(_ kind: MetricKind, _ fallback: MetricScore?) -> MetricScore {
            fallback ?? MetricScore(kind: kind, value: 70, availability: .available, badge: "", subtitle: "")
        }
        return DailyComputedDay(
            date: date(key),
            dayKey: key,
            raw: raw,
            recovery: score(.recovery, recovery),
            sleep: score(.sleep, sleep),
            strain: score(.strain, strain),
            stress: score(.stress, stress),
            energy: score(.energy, energy),
            energyCurve: [],
            stressTimeline: [],
            factualSummary: "",
            evidenceSummary: ""
        )
    }

    private func score(_ kind: MetricKind, _ value: Int?, _ availability: MetricAvailability) -> MetricScore {
        MetricScore(kind: kind, value: value, availability: availability, badge: "", subtitle: "")
    }

    private func makeContext(
        endKey: DayKey,
        asOf: Date,
        history: [DailyComputedDay],
        storedWorkouts: [StoredWorkoutRecord] = [],
        checkIns: [DailyCheckIn] = [],
        nutritionLogs: [DailyNutritionLog] = []
    ) -> AgentExecutionContext {
        let today = history.first { $0.dayKey == endKey } ?? history.last!
        let snapshot = BodySeekDashboardSnapshot(
            referenceDate: asOf,
            today: today,
            historyDays: history,
            trainingLoad: TrainingLoadStatus(acute7dLoad: 300, chronic28dWeeklyAvg: 280, acwrRatio: 1.07, zone: .sweetSpot),
            sourceLabel: "fixture",
            lastUpdatedAt: asOf,
            isAuthorized: true
        )
        return AgentExecutionContext(
            snapshot: snapshot,
            storedWorkouts: storedWorkouts,
            todayNutritionLog: nutritionLogs.first,
            nutritionLogs: nutritionLogs,
            checkIns: checkIns,
            asOf: asOf
        )
    }

    func testCoverageAndSamplesSeparateMissingExcludedAndKnownZero() throws {
        let endKey = DayKey(year: 2026, month: 11, day: 20)
        let controlKeys = (0..<28).map { endKey.addingDays($0 - 34) }
        let targetKeys = (0..<7).map { endKey.addingDays($0 - 6) }
        let missing = Set(controlKeys.prefix(3))
        let excluded = Set(controlKeys.dropFirst(3).prefix(2))

        var history: [DailyComputedDay] = []
        for key in controlKeys {
            let recovery: MetricScore
            if missing.contains(key) {
                recovery = score(.recovery, nil, .missing(reason: "无样本"))
            } else if excluded.contains(key) {
                recovery = score(.recovery, nil, .excluded(reason: "运动伪影"))
            } else {
                recovery = score(.recovery, 70, .available)
            }
            history.append(day(key, recovery: recovery))
        }
        for key in targetKeys {
            history.append(day(key, recovery: score(.recovery, 60, .available)))
        }
        let asOf = date(endKey).addingTimeInterval(12 * 3600)
        let context = makeContext(endKey: endKey, asOf: asOf, history: history)

        let evidence = try WeeklyRecoveryEvidenceBuilder.build(
            endDayKey: endKey, asOf: asOf, context: context, calendar: calendar
        )
        let control = evidence.control.metricStats.first { $0.metric == "recovery" }!
        XCTAssertEqual(control.missingDays, 3)
        XCTAssertEqual(control.excludedDays, 2)
        XCTAssertEqual(control.availableDays, 23)
        XCTAssertEqual(control.sampleCount, 23)
        XCTAssertEqual(control.coverage, 23.0 / 28.0, accuracy: 0.0001)
        XCTAssertEqual(evidence.recovery.controlMedian, 70)
        XCTAssertEqual(evidence.recovery.targetMedian, 60)
        XCTAssertEqual(evidence.recovery.delta, -10)
        XCTAssertTrue(evidence.recovery.isDecline)
        XCTAssertTrue(evidence.recovery.evidenceSufficient)
    }

    func testKnownZeroCountsAsObservedAndKeepsSample() throws {
        let endKey = DayKey(year: 2026, month: 11, day: 20)
        let targetKeys = (0..<7).map { endKey.addingDays($0 - 6) }
        let asOf = date(endKey).addingTimeInterval(12 * 3600)
        var history = targetKeys.map { key in
            day(key, strain: score(.strain, nil, .knownZero(reason: "无训练")))
        }
        history.append(contentsOf: (0..<28).map { offset in
            let key = endKey.addingDays(offset - 34)
            return day(key, strain: score(.strain, nil, .knownZero(reason: "无训练")))
        })
        let context = makeContext(endKey: endKey, asOf: asOf, history: history)
        let evidence = try WeeklyRecoveryEvidenceBuilder.build(
            endDayKey: endKey, asOf: asOf, context: context, calendar: calendar
        )
        let strain = evidence.target.metricStats.first { $0.metric == "strain" }!
        XCTAssertEqual(strain.knownZeroDays, 7)
        XCTAssertEqual(strain.sampleCount, 7)
        XCTAssertEqual(strain.coverage, 1.0)
        XCTAssertEqual(strain.median, 0)
    }

    func testPhysiologicalCutoverAndFutureDay() throws {
        let asOf = Date(timeIntervalSince1970: 1_795_000_000) // 2026-11-18 11:46 +08
        let currentKey = asOf.physiologicalDayKey(cutoverHour: 4, timeZone: calendar.timeZone)
        let history = [day(currentKey)]
        let context = makeContext(endKey: currentKey, asOf: asOf, history: history)
        let evidence = try WeeklyRecoveryEvidenceBuilder.build(endDayKey: nil, asOf: asOf, context: context, calendar: calendar)
        XCTAssertEqual(evidence.target.endDayKey, currentKey.isoString)
        XCTAssertTrue(evidence.endDayIsPartial)

        XCTAssertThrowsError(try WeeklyRecoveryEvidenceBuilder.build(
            endDayKey: currentKey.addingDays(1), asOf: asOf, context: context, calendar: calendar
        )) { error in
            guard case WeeklyRecoveryEvidenceError.futureDayKey = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testTargetAndControlDoNotOverlap() throws {
        let endKey = DayKey(year: 2026, month: 11, day: 20)
        let asOf = date(endKey).addingTimeInterval(12 * 3600)
        let history = (0..<35).map { day(endKey.addingDays($0 - 34)) }
        let context = makeContext(endKey: endKey, asOf: asOf, history: history)
        let evidence = try WeeklyRecoveryEvidenceBuilder.build(endDayKey: endKey, asOf: asOf, context: context, calendar: calendar)
        XCTAssertEqual(evidence.target.startDayKey, endKey.addingDays(-6).isoString)
        XCTAssertEqual(evidence.target.endDayKey, endKey.isoString)
        XCTAssertEqual(evidence.control.startDayKey, endKey.addingDays(-34).isoString)
        XCTAssertEqual(evidence.control.endDayKey, endKey.addingDays(-7).isoString)
        XCTAssertEqual(evidence.daily.count, 7)
        XCTAssertFalse(evidence.control.metricStats.isEmpty)
    }

    func testSameDayWorkoutsAreEachCountedOnceAndDeletedExcluded() throws {
        let endKey = DayKey(year: 2026, month: 11, day: 20)
        let dayStart = date(endKey)
        let strength = StoredWorkoutRecord(
            hkUUID: "W-STRENGTH", type: "传统力量训练", start: dayStart.addingTimeInterval(9 * 3600),
            end: dayStart.addingTimeInterval(10 * 3600), energy: 300, reviewState: .annotated
        )
        let badminton = StoredWorkoutRecord(
            hkUUID: "W-BADMINTON", type: "羽毛球", start: dayStart.addingTimeInterval(20 * 3600),
            end: dayStart.addingTimeInterval(21 * 3600), energy: 460, reviewState: .unreviewed
        )
        let deleted = StoredWorkoutRecord(
            hkUUID: "W-DELETED", type: "力量训练", start: dayStart.addingTimeInterval(12 * 3600),
            end: dayStart.addingTimeInterval(13 * 3600), energy: 200
        )
        var history = [day(endKey)]
        history.append(contentsOf: (0..<6).map { day(endKey.addingDays($0 - 6)) })
        let asOf = dayStart.addingTimeInterval(22 * 3600)
        var context = makeContext(
            endKey: endKey, asOf: asOf, history: history,
            storedWorkouts: [strength, badminton, deleted]
        )
        context = AgentExecutionContext(
            snapshot: context.snapshot,
            storedWorkouts: [strength, badminton, deleted],
            deletedWorkoutUUIDs: ["w-deleted"],
            asOf: asOf
        )
        let evidence = try WeeklyRecoveryEvidenceBuilder.build(endDayKey: endKey, asOf: asOf, context: context, calendar: calendar)
        let workouts = evidence.daily.first { $0.dayKey == endKey.isoString }!.workouts
        XCTAssertEqual(workouts.map(\.uuid), ["W-STRENGTH", "W-BADMINTON"])
        XCTAssertEqual(Set(workouts.map(\.uuid)).count, 2)
    }

    func testMissingSleepAndUnknownCoffeeTime() throws {
        let endKey = DayKey(year: 2026, month: 11, day: 20)
        let asOf = date(endKey).addingTimeInterval(12 * 3600)
        let history = (0..<7).map { offset in
            let key = endKey.addingDays(offset - 6)
            return day(key, sleep: offset == 6 ? score(.sleep, nil, .missing(reason: "无样本")) : nil, asleep: offset == 6 ? nil : 420)
        }
        let entry = MealEntry(
            dayKey: endKey, mealType: .breakfast, foodName: "美式咖啡",
            portionAmount: 300, portionUnit: "ml", recordedAt: date(endKey).addingTimeInterval(8 * 3600)
        )
        let log = DailyNutritionLog(dayKey: endKey, entries: [entry], dietKcal: 15, dietProteinG: 0)
        let context = makeContext(endKey: endKey, asOf: asOf, history: history, nutritionLogs: [log])
        let evidence = try WeeklyRecoveryEvidenceBuilder.build(endDayKey: endKey, asOf: asOf, context: context, calendar: calendar)
        let finalDay = evidence.daily.last!
        XCTAssertEqual(finalDay.sleep?.state, "missing")
        XCTAssertEqual(finalDay.nutrition?.mealTimePrecision, "unknown")
        XCTAssertEqual(finalDay.nutrition?.recordedAtIsSaveTime, true)
        XCTAssertEqual(evidence.coffeeObservations.first?.timeKnown, false)
        XCTAssertEqual(evidence.coffeeObservations.first?.name, "美式咖啡")
    }

    func testToolEnvelopeCarriesEvidenceAndRejectsInvalidDate() async throws {
        let endKey = DayKey(year: 2026, month: 11, day: 20)
        let asOf = date(endKey).addingTimeInterval(12 * 3600)
        let history = (0..<35).map { day(endKey.addingDays($0 - 34)) }
        let context = makeContext(endKey: endKey, asOf: asOf, history: history)
        let json = await CoachToolRegistry.execute(
            name: "get_weekly_recovery_evidence",
            argumentsJSON: #"{"end_day_key":"2026-11-20"}"#,
            context: context
        )
        XCTAssertTrue(json.contains("\"evidence\""))
        XCTAssertTrue(json.contains("\"weekly.recovery.delta\""))

        let invalid = await CoachToolRegistry.execute(
            name: "get_weekly_recovery_evidence",
            argumentsJSON: #"{"end_day_key":"2026-13-40"}"#,
            context: context
        )
        XCTAssertTrue(invalid.contains("\"state\":\"excluded\""))
    }

    func testTypedProvenanceRejectsWrongDateMetricAndUnit() {
        let toolOutput = """
        {"tool":"get_weekly_recovery_evidence","evidence":[
          {"key":"day.2026-11-20.recovery","value":71,"unit":"score_0_100","metric":"recovery","scope":"day:2026-11-20","dayKey":"2026-11-20","state":"available","isEstimate":false,"source":"local"},
          {"key":"day.2026-11-20.hrv","value":54,"unit":"ms","metric":"hrv","scope":"day:2026-11-20","dayKey":"2026-11-20","state":"available","isEstimate":false,"source":"healthkit"}
        ]}
        """
        func unverified(_ text: String) -> [String] {
            NumericProvenanceVerifier.verify(responseText: text, toolOutputs: [toolOutput]).unverifiedTokens
        }
        XCTAssertTrue(unverified("11月19日恢复 71 分。").contains { $0.contains("71") })
        XCTAssertTrue(unverified("恢复 71 ms。").contains { $0.contains("71") })
        XCTAssertTrue(unverified("睡眠 71 分。").contains { $0.contains("71") })
        XCTAssertTrue(unverified("11月20日恢复 99 分。").contains { $0.contains("99") })
        XCTAssertTrue(unverified("11月20日恢复 71 分。").isEmpty)
        XCTAssertTrue(unverified("11月20日 HRV 54 ms。").isEmpty)

        // Mixed turn: a legacy tool result may still supply a number that is absent
        // from typed evidence; it must not be flagged merely because typed facts exist.
        let legacyOutput = #"{"tool":"get_today_context","data":{"hrvMs":46}}"#
        let mixed = NumericProvenanceVerifier.verify(
            responseText: "今天 HRV 46 ms。",
            toolOutputs: [toolOutput, legacyOutput]
        )
        XCTAssertTrue(mixed.unverifiedTokens.isEmpty)
    }
}
