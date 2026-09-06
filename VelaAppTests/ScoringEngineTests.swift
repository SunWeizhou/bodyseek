import XCTest
import SwiftData
@testable import Vela

final class ScoringEngineTests: XCTestCase {
    func testMissingDailyDecisionUsesConservativeExecutableFallback() {
        let fallback = TrainingDecisionFallback.conservative(targetSessionTitle: "上肢力量")

        XCTAssertEqual(fallback.decision, .reduce)
        XCTAssertEqual(fallback.targetSessionTitle, "上肢力量")
        XCTAssertEqual(fallback.volumeMultiplier, 0.60)
        XCTAssertEqual(fallback.intensityCap, 7)
        XCTAssertLessThan(fallback.confidence, 0.5)
        XCTAssertEqual(fallback.source, "TrainingDecisionFallback")
    }
    func testRescheduleAdaptationUsesNextRecoveryDayAfterCurrentSession() {
        let strengthDay = TrainingDay(
            weekNumber: 2, dayNumber: 1, title: "Strength", description: "", focus: "strength", durationMinutes: 60, intensity: "high"
        )
        let nextTrainingDay = TrainingDay(
            weekNumber: 2, dayNumber: 2, title: "Cardio", description: "", focus: "cardio", durationMinutes: 30, intensity: "moderate"
        )
        let recoveryDay = TrainingDay(
            weekNumber: 2, dayNumber: 3, title: "Rest", description: "", focus: "rest", durationMinutes: 0, intensity: "low"
        )
        let plan = TrainingPlanRecord(title: "Test", goalDescription: "", days: [strengthDay, nextTrainingDay, recoveryDay])
        let adaptation = TrainingPlanAdaptationRecord(
            planId: plan.id,
            dayId: strengthDay.id,
            adjustment: .reschedule,
            reason: "test"
        )

        XCTAssertTrue(AdaptiveTrainingManager().applyAdaptation(adaptation, to: plan))
        XCTAssertEqual(plan.days[0].focus, "rest")
        XCTAssertEqual(plan.days[2].focus, "strength")
        XCTAssertEqual(plan.days[2].dayNumber, recoveryDay.dayNumber)
    }

    func testRescheduleAdaptationDoesNotApplyWithoutFutureRecoveryDay() {
        let strengthDay = TrainingDay(
            weekNumber: 1, dayNumber: 1, title: "Strength", description: "", focus: "strength", durationMinutes: 60, intensity: "high"
        )
        let plan = TrainingPlanRecord(title: "Test", goalDescription: "", days: [strengthDay])
        let adaptation = TrainingPlanAdaptationRecord(
            planId: plan.id,
            dayId: strengthDay.id,
            adjustment: .reschedule,
            reason: "test"
        )

        XCTAssertFalse(AdaptiveTrainingManager().applyAdaptation(adaptation, to: plan))
        XCTAssertEqual(plan.days, [strengthDay])
    }

    func testHealthProfileMigrationResetsLegacyHydratedValuesOnce() {
        let suiteName = "UserProfileSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 旧版本会把 Apple 健康值 hydrate 进 UserDefaults；新解析语义下手填值优先，
        // 这些残留值会冻结陈旧健康数据，迁移应一次性清除。
        defaults.set(29, forKey: UserProfileSettings.ageKey)
        defaults.set(71.4, forKey: UserProfileSettings.weightKey)
        defaults.set(178, forKey: UserProfileSettings.heightKey)
        defaults.set("male", forKey: UserProfileSettings.biologicalSexKey)

        UserProfileSettings.migrateLegacyHydratedValuesIfNeeded(defaults: defaults)
        XCTAssertNil(UserProfileSettings.age(defaults: defaults))
        XCTAssertNil(UserProfileSettings.weightKilograms(defaults: defaults))
        XCTAssertNil(UserProfileSettings.heightCentimeters(defaults: defaults))
        XCTAssertNil(UserProfileSettings.biologicalSex(defaults: defaults))

        // 迁移后用户再次手动填写，重复迁移不得再清除。
        defaults.set(35, forKey: UserProfileSettings.ageKey)
        defaults.set(80.0, forKey: UserProfileSettings.weightKey)
        UserProfileSettings.migrateLegacyHydratedValuesIfNeeded(defaults: defaults)
        XCTAssertEqual(UserProfileSettings.age(defaults: defaults), 35)
        XCTAssertEqual(UserProfileSettings.weightKilograms(defaults: defaults), 80.0)
    }

    func testPersonalBaselineRequiresSevenValidSamplesPerMetric() {
        let date = Date()
        let sixSnapshots = (0..<6).map { offset -> DailyHealthSnapshot in
            var snapshot = DailyHealthSnapshot(date: date.addingTimeInterval(Double(-offset) * 86_400))
            snapshot.hrvAverage = 50
            snapshot.restingHeartRate = 60
            return snapshot
        }
        let sevenSnapshots = (0..<7).map { offset -> DailyHealthSnapshot in
            var snapshot = DailyHealthSnapshot(date: date.addingTimeInterval(Double(-offset) * 86_400))
            snapshot.hrvAverage = 50
            snapshot.restingHeartRate = 60
            return snapshot
        }

        let insufficient = PersonalBaselineEngine.computeBaselines(from: sixSnapshots)
        XCTAssertNil(insufficient.hrvBaselineMean)
        XCTAssertNil(insufficient.rhrBaselineMean)

        let ready = PersonalBaselineEngine.computeBaselines(from: sevenSnapshots)
        XCTAssertEqual(ready.hrvBaselineMean, 50)
        XCTAssertEqual(ready.rhrBaselineMean, 60)
    }

    func testPersonalBaselineFormationCountsDistinctEvidenceDaysAndRequiresSeven() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let selectedDate = Date(timeIntervalSince1970: 1_780_000_000)

        let sixEvidenceDays = (1...6).map { offset -> DailyHealthSnapshot in
            var snapshot = DailyHealthSnapshot(
                date: calendar.date(byAdding: .day, value: -offset, to: selectedDate)!
            )
            snapshot.hrvAverage = 50 + Double(offset)
            return snapshot
        }
        var duplicateDay = DailyHealthSnapshot(date: sixEvidenceDays[0].date.addingTimeInterval(3_600))
        duplicateDay.restingHeartRate = 60
        var futureDay = DailyHealthSnapshot(
            date: calendar.date(byAdding: .day, value: 1, to: selectedDate)!
        )
        futureDay.sleepHours = 8
        let emptyPastDay = DailyHealthSnapshot(
            date: calendar.date(byAdding: .day, value: -10, to: selectedDate)!
        )

        let learning = PersonalBaselineEngine.formationProgress(
            from: sixEvidenceDays + [duplicateDay, futureDay, emptyPastDay],
            selectedDate: selectedDate,
            calendar: calendar
        )

        XCTAssertEqual(learning.phase, .learning)
        XCTAssertEqual(learning.observedDays, 6)
        XCTAssertEqual(learning.progress, 6.0 / 7.0, accuracy: 0.001)

        var seventhDay = DailyHealthSnapshot(date: selectedDate)
        seventhDay.sleepHours = 7.5
        let ready = PersonalBaselineEngine.formationProgress(
            from: sixEvidenceDays + [seventhDay],
            selectedDate: selectedDate,
            calendar: calendar
        )

        XCTAssertEqual(ready.phase, .ready)
        XCTAssertEqual(ready.observedDays, 7)
        XCTAssertEqual(ready.progress, 1)
        XCTAssertEqual(
            PersonalBaselineEngine.formationProgress(
                from: [emptyPastDay],
                selectedDate: selectedDate,
                calendar: calendar
            ).phase,
            .waitingForEvidence
        )
        XCTAssertEqual(
            PersonalBaselineFormation.visualRegressionValue(
                fallback: .ready,
                arguments: ["Vela", "-velaBaselineObservedDays", "4"]
            ),
            PersonalBaselineFormation(phase: .learning, observedDays: 4)
        )
    }

    func testPersonalBaselineUsesInjectedCalculationTime() {
        let calculatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshots = (0..<7).map { offset -> DailyHealthSnapshot in
            var snapshot = DailyHealthSnapshot(
                date: calculatedAt.addingTimeInterval(Double(-offset) * 86_400)
            )
            snapshot.hrvAverage = 50
            return snapshot
        }

        let baseline = PersonalBaselineEngine.computeBaselines(
            from: snapshots,
            calculatedAt: calculatedAt
        )

        XCTAssertEqual(baseline.calculatedAt, calculatedAt)
    }

    func testMetricResultDecodesLegacyCacheWithoutTypedDomain() throws {
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let original = MetricResult(
            domain: .physiologicalStress,
            name: "Physiological Stress Index",
            value: 42,
            band: .low,
            confidence: .medium,
            components: ["stress": 42],
            componentWeights: [:],
            reasons: [],
            missingInputs: [],
            dataWindow: DateInterval(start: asOf.addingTimeInterval(-3600), end: asOf),
            source: .derived,
            algorithmVersion: "1.0.0",
            lastUpdated: asOf
        )
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "domain")

        let decoded = try JSONDecoder().decode(
            MetricResult.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.domain, .physiologicalStress)
        XCTAssertEqual(decoded.direction, .higherNeedsAttention)
    }

    func testSleepScoreEngineProducesValidRange() {
        let engine = SleepScoreEngine()
        let input = SleepScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            totalSleepMinutes: 420,
            sleepTargetMinutes: 480,
            awakeMinutes: 15,
            awakeEpisodeCount: 2,
            remMinutes: 90,
            deepMinutes: 90
        )
        let result = engine.calculate(from: input)
        XCTAssertGreaterThanOrEqual(result.value ?? 0, 0)
        XCTAssertLessThanOrEqual(result.value ?? 0, 100)
    }

    func testSleepScoreEngineAwakeCountDistinguishesMeasuredFactFromEstimate() {
        let engine = SleepScoreEngine()

        // 1. Measured awakeEpisodeCount should report as detected fact (no "估算")
        let measuredInput = SleepScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            totalSleepMinutes: 420,
            sleepTargetMinutes: 480,
            awakeMinutes: 20,
            awakeEpisodeCount: 3
        )
        let measuredResult = engine.calculate(from: measuredInput)
        let measuredInterruptionReason = measuredResult.reasons.first { $0.contains("睡眠中断") } ?? ""
        XCTAssertTrue(measuredInterruptionReason.contains("醒来频率 3次"))
        XCTAssertFalse(measuredInterruptionReason.contains("估算"))

        // 2. Missing awakeEpisodeCount with awakeMinutes > 0 must explicitly declare "估算"
        let estimatedInput = SleepScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            totalSleepMinutes: 420,
            sleepTargetMinutes: 480,
            awakeMinutes: 24,
            awakeEpisodeCount: nil
        )
        let estimatedResult = engine.calculate(from: estimatedInput)
        let estimatedInterruptionReason = estimatedResult.reasons.first { $0.contains("睡眠中断") } ?? ""
        XCTAssertTrue(estimatedInterruptionReason.contains("醒来频率约 3次 · 估算"))
    }

    func testSleepTargetCompletionReasonUsesExactObservedMinutes() {
        let engine = SleepScoreEngine()
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)

        func durationReason(sleepMinutes: Double?, targetMinutes: Double = 360) -> String {
            let result = engine.calculate(from: SleepScoreInput(
                asOf: asOf,
                totalSleepMinutes: sleepMinutes,
                sleepTargetMinutes: targetMinutes,
                awakeMinutes: 0
            ))
            return result.reasons.first { $0.hasPrefix("睡眠时长") } ?? ""
        }

        let adequacyNote = "；注：依据 AASM 成人共识，成人健康睡眠建议为 7–9 小时，达成个人作息目标不代表生理充分满足"
        XCTAssertEqual(durationReason(sleepMinutes: 240), "睡眠时长 4小时0分钟（未达成个人作息目标 6小时\(adequacyNote)）")
        XCTAssertEqual(durationReason(sleepMinutes: 360), "睡眠时长 6小时0分钟（已达成个人作息目标 6小时\(adequacyNote)）")
        XCTAssertEqual(durationReason(sleepMinutes: 390), "睡眠时长 6小时30分钟（已达成个人作息目标 6小时；超过目标30分钟\(adequacyNote)）")
        XCTAssertEqual(durationReason(sleepMinutes: 359), "睡眠时长 5小时59分钟（未达成个人作息目标 6小时\(adequacyNote)）")
        XCTAssertEqual(durationReason(sleepMinutes: 390, targetMinutes: 390), "睡眠时长 6小时30分钟（已达成个人作息目标 6小时30分钟\(adequacyNote)）")
        XCTAssertEqual(durationReason(sleepMinutes: nil), "")
    }

    func testDailySnapshotObservationTimesSurviveEvidencePersistenceAndDoNotChangeScores() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let hrvWindow = DateInterval(start: day.addingTimeInterval(7 * 3600 + 55 * 60), end: day.addingTimeInterval(8 * 3600))
        var snapshot = DailyHealthSnapshot(date: day, hrvAverage: 42, restingHeartRate: 58, sleepHours: 7, oxygenSaturation: 98)
        snapshot.hrvObservedAt = hrvWindow.end
        snapshot.rhrObservedAt = day.addingTimeInterval(9 * 3600 + 50 * 60)
        snapshot.spo2ObservedAt = day.addingTimeInterval(9 * 3600 + 30 * 60)
        snapshot.hrvObservedWindow = hrvWindow

        let profile = DailyHealthComputationProfile(sleepTargetMinutes: 450, maxHeartRate: 190, biologicalSex: "other")
        let before = DailyHealthComputation(calendar: calendar, now: day.addingTimeInterval(22 * 3600), profile: profile).compute(for: snapshot, history: [])
        let envelope = DailyScoreEvidenceEnvelope(evidence: before, persistedAt: day.addingTimeInterval(22 * 3600 + 60))
        let record = DailyHealthSummaryRecord(snapshot: snapshot, calendar: calendar)
        try record.apply(scoreEvidence: nil, observations: snapshot)
        let rawReloaded = record.toSnapshot()
        XCTAssertEqual(rawReloaded.hrvObservedAt, snapshot.hrvObservedAt)
        XCTAssertEqual(rawReloaded.rhrObservedAt, snapshot.rhrObservedAt)
        XCTAssertEqual(rawReloaded.spo2ObservedAt, snapshot.spo2ObservedAt)
        try record.apply(scoreEvidence: envelope, observations: snapshot)
        let reloaded = record.toSnapshot()
        XCTAssertEqual(reloaded.hrvObservedAt, snapshot.hrvObservedAt)
        XCTAssertEqual(reloaded.rhrObservedAt, snapshot.rhrObservedAt)
        XCTAssertEqual(reloaded.spo2ObservedAt, snapshot.spo2ObservedAt)
        XCTAssertEqual(reloaded.hrvObservedWindow, snapshot.hrvObservedWindow)

        let after = DailyHealthComputation(calendar: calendar, now: day.addingTimeInterval(22 * 3600), profile: profile).compute(for: reloaded, history: [])
        XCTAssertEqual(after.sleep.value, before.sleep.value)
        XCTAssertEqual(after.recovery.value, before.recovery.value)
        XCTAssertEqual(after.strain.value, before.strain.value)
        XCTAssertEqual(after.physiologicalStress.value, before.physiologicalStress.value)
        XCTAssertEqual(after.energy.value, before.energy.value)
    }

    func testTodayVitalCardModelAndAssessmentFourStates() {
        // Test favorable
        let favCard = TodayVitalCardModel(
            kind: .hrv, label: "HRV", value: "65", unit: "ms",
            status: "正常", assessment: .favorable, trend: [60, 65]
        )
        XCTAssertTrue(favCard.isGood)
        XCTAssertEqual(favCard.assessment, .favorable)

        // Test neutral
        let neutralCard = TodayVitalCardModel(
            kind: .rhr, label: "RHR", value: "60", unit: "bpm",
            status: "基线附近", assessment: .neutral, trend: [60, 60]
        )
        XCTAssertFalse(neutralCard.isGood)
        XCTAssertEqual(neutralCard.assessment, .neutral)

        // Test unfavorable
        let unfavCard = TodayVitalCardModel(
            kind: .spo2, label: "SpO2", value: "93", unit: "%",
            status: "偏低", assessment: .unfavorable, trend: [95, 93]
        )
        XCTAssertFalse(unfavCard.isGood)
        XCTAssertEqual(unfavCard.assessment, .unfavorable)

        // Test unknown
        let unknownCard = TodayVitalCardModel(
            kind: .sleep, label: "Sleep", value: "--", unit: "时",
            status: "待同步", assessment: .unknown, trend: []
        )
        XCTAssertFalse(unknownCard.isGood)
        XCTAssertEqual(unknownCard.assessment, .unknown)
    }

    func testRecoveryScoreEngineHandlesEmptyHistory() {
        let engine = RecoveryScoreEngine()
        let input = RecoveryScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            hrvToday: 45,
            hrvBaseline: 50,
            hrvHistory: [],
            restingHeartRateToday: 58,
            restingHeartRateBaseline: 55,
            rhrHistory: [],
            sleepScoreLastNight: 75,
            strainScoreYesterday: 50
        )
        let result = engine.calculate(from: input)
        XCTAssertNotNil(result)
    }

    func testRecoveryScoreDoesNotPublishFromPriorStrainAlone() {
        let result = RecoveryScoreEngine().calculate(from: RecoveryScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            hrvToday: nil,
            hrvBaseline: nil,
            hrvHistory: [],
            restingHeartRateToday: nil,
            restingHeartRateBaseline: nil,
            rhrHistory: [],
            sleepScoreLastNight: nil,
            strainScoreYesterday: 0
        ))

        XCTAssertNil(result.value)
        XCTAssertFalse(result.hasData)
        XCTAssertTrue(result.reasons.contains { $0.contains("才会给出恢复评分") })
    }

    func testRecoveryScoreEngineCalculatesParasympatheticToneIndexFromRMSSD() {
        let engine = RecoveryScoreEngine()
        let input = RecoveryScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            hrvToday: 50,
            hrvBaseline: 50,
            hrvHistory: [48, 50, 52, 49, 51, 50, 48],
            hrvRmssdToday: 55,
            hrvRmssdBaseline: 50,
            hrvRmssdHistory: [48, 50, 52, 49, 51, 50, 48],
            restingHeartRateToday: 58,
            restingHeartRateBaseline: 58,
            rhrHistory: [58, 59, 57, 58, 58, 59, 58],
            sleepScoreLastNight: 80,
            strainScoreYesterday: 40
        )
        let result = engine.calculate(from: input)
        XCTAssertNotNil(result.components["parasympathetic_tone_index"])
        XCTAssertNotNil(result.components["psti_z_score"])
        let psti = result.components["parasympathetic_tone_index"]!
        XCTAssertGreaterThanOrEqual(psti, 0.0)
        XCTAssertLessThanOrEqual(psti, 100.0)
    }

    func testHealthSignalCatalogTreatsRMSSDAsDerivedFromSDNN() {
        XCTAssertEqual(HealthSignal.heartRateVariabilityRMSSD.rawValue, "hrv_rmssd")
        XCTAssertEqual(
            HealthSignalCatalog.objectType(for: .heartRateVariabilityRMSSD)?.identifier,
            HealthSignal.hrvSDNN.objectType?.identifier
        )
        XCTAssertFalse(HealthSignalCatalog.coreSignals.contains(.heartRateVariabilityRMSSD))
        XCTAssertEqual(HealthSignalCatalog.unit(for: .heartRateVariabilityRMSSD)?.symbol, "ms")
    }

    func testWristTemperatureAbovePersonalBaselineReducesRecoveryScore() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let history = (1...7).compactMap { offset -> DailyHealthSnapshot? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            var snapshot = DailyHealthSnapshot(date: date)
            snapshot.hrvAverage = 50
            snapshot.restingHeartRate = 60
            snapshot.sleepHours = 7.5
            snapshot.wristTemperature = 36.2
            return snapshot
        }

        var neutral = DailyHealthSnapshot(date: today)
        neutral.hrvAverage = 50
        neutral.restingHeartRate = 60
        neutral.sleepHours = 7.5
        neutral.wristTemperature = 36.2

        var elevated = neutral
        // +1.4°C — a genuinely elevated temp. Normal circadian/day-to-day body-temp
        // variation spans ~±0.5–0.6°C and must NOT trigger the recovery penalty;
        // only a clear fever-range departure (≥1.0°C) should.
        elevated.wristTemperature = 37.6

        let computation = DailyHealthComputation(
            calendar: calendar,
            now: today,
            profile: DailyHealthComputationProfile(
                sleepTargetMinutes: 450,
                maxHeartRate: 190,
                biologicalSex: "other"
            )
        )
        let neutralRecovery = computation.compute(for: neutral, history: history).recovery
        let elevatedRecovery = computation.compute(for: elevated, history: history).recovery

        XCTAssertNotNil(neutralRecovery.value)
        XCTAssertNotNil(elevatedRecovery.value)
        XCTAssertEqual(elevatedRecovery.components["body_temp_delta"] ?? 0, 1.4, accuracy: 0.01)
        XCTAssertLessThanOrEqual(elevatedRecovery.value ?? .infinity, (neutralRecovery.value ?? 0) - 7.9)
    }

    /// Regression guard: a NORMAL wrist-temp day-to-day drift (~0.5°C above the
    /// personal baseline) must NOT trigger the recovery penalty. Previously the
    /// threshold was 0.5°C, which fired on healthy users' normal variation every
    /// day and dragged Recovery, Energy and Stress scores low with normal raw
    /// signals (the reported "所有算法分都低但没做活动").
    func testNormalBodyTempVariationDoesNotReduceRecoveryScore() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let history = (1...7).compactMap { offset -> DailyHealthSnapshot? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            var snapshot = DailyHealthSnapshot(date: date)
            snapshot.hrvAverage = 50
            snapshot.restingHeartRate = 60
            snapshot.sleepHours = 7.5
            snapshot.wristTemperature = 36.2
            return snapshot
        }

        var neutral = DailyHealthSnapshot(date: today)
        neutral.hrvAverage = 50
        neutral.restingHeartRate = 60
        neutral.sleepHours = 7.5
        neutral.wristTemperature = 36.2

        // +0.6°C — within normal circadian/day-to-day variation.
        var drift = neutral
        drift.wristTemperature = 36.8

        let computation = DailyHealthComputation(
            calendar: calendar,
            now: today,
            profile: DailyHealthComputationProfile(
                sleepTargetMinutes: 450,
                maxHeartRate: 190,
                biologicalSex: "other"
            )
        )
        let neutralRecovery = computation.compute(for: neutral, history: history).recovery
        let driftedRecovery = computation.compute(for: drift, history: history).recovery

        XCTAssertNotNil(neutralRecovery.value)
        XCTAssertNotNil(driftedRecovery.value)
        XCTAssertEqual(driftedRecovery.components["body_temp_delta"] ?? 0, 0.6, accuracy: 0.01)
        // Normal drift must not drop recovery by the old 8-point penalty.
        XCTAssertGreaterThan(driftedRecovery.value ?? 0, (neutralRecovery.value ?? 100) - 2.0)
    }

    func testDailyHealthComputationDoesNotInventBedtimeOrWakeTime() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let dayStart = calendar.startOfDay(for: asOf)
        let history = (1...7).map { offset -> DailyHealthSnapshot in
            let date = calendar.date(byAdding: .day, value: -offset, to: dayStart)!
            var snapshot = DailyHealthSnapshot(date: date)
            snapshot.bedtime = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: date)
            snapshot.hrvAverage = 50
            snapshot.restingHeartRate = 60
            snapshot.sleepHours = 7.5
            return snapshot
        }
        var snapshot = DailyHealthSnapshot(date: dayStart)
        snapshot.hrvAverage = 50
        snapshot.restingHeartRate = 60
        snapshot.sleepHours = 7.5

        let evidence = DailyHealthComputation(
            calendar: calendar,
            now: asOf,
            profile: DailyHealthComputationProfile(
                sleepTargetMinutes: 450,
                maxHeartRate: 190,
                biologicalSex: "other"
            )
        ).compute(for: snapshot, history: history)

        XCTAssertNil(evidence.sleep.components["consistency"])
        XCTAssertTrue(evidence.sleep.missingInputs.contains("todayBedtime"))
        XCTAssertEqual(evidence.energy.components["time_drain"], 0)
        XCTAssertTrue(evidence.energy.missingInputs.contains("wakeTime"))
    }

    func testDailyHealthComputationExcludesStressInsideWorkoutRecoveryWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        var snapshot = DailyHealthSnapshot(date: calendar.startOfDay(for: asOf))
        snapshot.hrvAverage = 50
        snapshot.restingHeartRate = 60
        snapshot.sleepHours = 7.5
        snapshot.workouts = [
            WorkoutSummary(
                start: asOf.addingTimeInterval(-3_600),
                end: asOf.addingTimeInterval(-900),
                activityName: "Strength Training",
                energyKilocalories: 220,
                averageHeartRate: 135,
                source: "test",
                rpe: 7
            )
        ]

        let evidence = DailyHealthComputation(
            calendar: calendar,
            now: asOf,
            profile: DailyHealthComputationProfile(
                sleepTargetMinutes: 450,
                maxHeartRate: 190,
                biologicalSex: "other"
            )
        ).compute(for: snapshot, history: [])

        XCTAssertNil(evidence.physiologicalStress.value)
        XCTAssertTrue(evidence.physiologicalStress.missingInputs.contains("quietWindow"))
    }

    func testDailyHealthComputationGoldenFixtureAndVersionConsistency() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 31
        ))!
        let now = day.addingTimeInterval(12 * 3_600)
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
        snapshot.oxygenSaturation = 0.98
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

        let evidence = DailyHealthComputation(
            calendar: calendar,
            now: now,
            profile: DailyHealthComputationProfile(
                sleepTargetMinutes: 450,
                maxHeartRate: 190,
                biologicalSex: "other"
            )
        ).compute(for: snapshot, history: history)

        XCTAssertEqual(evidence.sleep.value ?? -1, 77.43, accuracy: 0.01)
        XCTAssertEqual(evidence.recovery.value ?? -1, 60.70, accuracy: 0.01)
        XCTAssertEqual(evidence.strain.value ?? -1, 63.67, accuracy: 0.01)
        // 2026-08-13 有意重定标：HRV 因子单位修复（log 域 SD）使生理压力正确反映
        // HRV 高于基线的低压力（见 testStressEngineHRVFactorRespondsToRealisticHRVDecline）
        XCTAssertEqual(evidence.physiologicalStress.value ?? -1, 21.08, accuracy: 0.01)
        // 2026-08-13 有意重定标：ATL/CTL/TSB 改用 TRIMP 域 todayLoad
        // （见 testEnergyBankTrainingLoadUsesTRIMPScaleTodayLoad）
        XCTAssertEqual(evidence.energy.value ?? -1, 42.31, accuracy: 0.01)
        XCTAssertEqual(evidence.sleep.algorithmVersion, ScoringAlgorithmVersions.sleep)
        XCTAssertEqual(evidence.recovery.algorithmVersion, ScoringAlgorithmVersions.recovery)
        XCTAssertEqual(evidence.strain.algorithmVersion, ScoringAlgorithmVersions.strain)
        XCTAssertEqual(
            evidence.physiologicalStress.algorithmVersion,
            ScoringAlgorithmVersions.physiologicalStress
        )
        XCTAssertEqual(evidence.energy.algorithmVersion, ScoringAlgorithmVersions.energy)
    }

    func testDailyHealthComputationIgnoresFutureHistory() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_785_369_600))
        var target = DailyHealthSnapshot(date: day)
        target.hrvAverage = 50
        target.restingHeartRate = 60
        target.sleepHours = 7.5
        let past = (1...7).map { offset -> DailyHealthSnapshot in
            var item = DailyHealthSnapshot(
                date: calendar.date(byAdding: .day, value: -offset, to: day)!
            )
            item.hrvAverage = 50
            item.restingHeartRate = 60
            item.sleepHours = 7.5
            return item
        }
        var future = DailyHealthSnapshot(
            date: calendar.date(byAdding: .day, value: 1, to: day)!
        )
        future.hrvAverage = 2
        future.restingHeartRate = 180
        future.sleepHours = 1
        let computation = DailyHealthComputation(calendar: calendar, now: day)

        XCTAssertEqual(
            computation.compute(for: target, history: past),
            computation.compute(for: target, history: past + [future])
        )
    }

    func testBodyInterpreterUsesConservativeDataCoverageLimiterWhenSignalsAreMissing() {
        let interpretation = BodyInterpreterEngine().interpret(
            dashboard: .empty(date: Date()),
            wiki: [:],
            activePlan: nil
        )

        XCTAssertEqual(interpretation.primaryLimiter.metricName, "Data Coverage")
        XCTAssertTrue(interpretation.trainingWindow.isOpen)
        XCTAssertEqual(interpretation.trainingWindow.recommendedIntensity, "low")
        XCTAssertEqual(interpretation.trainingWindow.maxDurationMinutes, 30)
        XCTAssertFalse(interpretation.recommendedAction.evidenceChain.contains { $0.metricName == "Sleep Score" })
    }

    func testBodyInterpreterSingleMildStressSignalDoesNotProduceSevereFatigue() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var dashboard = DashboardSummary.empty(date: date)

        func healthyMetric(_ name: String, domain: ScoredHealthDomain, value: Double) -> MetricResult {
            MetricResult(
                domain: domain,
                name: name,
                value: value,
                band: .high,
                confidence: .high,
                components: [:],
                componentWeights: [:],
                reasons: [],
                missingInputs: [],
                dataWindow: DateInterval(start: date, duration: 86400),
                source: .healthKit,
                algorithmVersion: "1.0.0",
                lastUpdated: date
            )
        }

        // 唯一疲劳信号：stress = 55（轻度心理压力）；其余指标全部健康
        dashboard.sleepScore = healthyMetric("Sleep Score", domain: .sleep, value: 90)
        dashboard.recovery = healthyMetric("Recovery Score", domain: .recovery, value: 85)
        dashboard.strain = healthyMetric("Strain Score", domain: .strain, value: 40)
        dashboard.stress = healthyMetric("Stress Index", domain: .physiologicalStress, value: 55)

        let interpretation = BodyInterpreterEngine().interpret(
            dashboard: dashboard,
            wiki: [:],
            activePlan: nil
        )

        // 单个轻度信号应判 .mild，不得因归一化失真升级为 .severe
        XCTAssertEqual(interpretation.fatigueLevel, .mild)
    }

    func testRecoveryReasonsDescribeMeasuredSignalsWithoutPhysiologicalClaims() {
        let result = RecoveryScoreEngine().calculate(from: RecoveryScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            hrvToday: 50,
            hrvBaseline: 50,
            hrvHistory: [50, 50, 50, 50, 50],
            restingHeartRateToday: 62,
            restingHeartRateBaseline: 55,
            rhrHistory: [55, 55, 55, 55, 55],
            sleepScoreLastNight: 85,
            strainScoreYesterday: 80
        ))
        let reasons = result.reasons.joined(separator: " ")

        XCTAssertTrue(reasons.contains("静息心率高于近期个人基线"))
        XCTAssertTrue(reasons.contains("昨晚睡眠评分较高"))
        XCTAssertTrue(reasons.contains("昨日训练负荷评分偏高"))
        XCTAssertFalse(reasons.contains("异常"))
        XCTAssertFalse(reasons.contains("系统性修复"))
        XCTAssertFalse(reasons.contains("恢复代偿"))
    }

    func testStressReasonsDoNotInferUnmeasuredHormonesOrAutonomicState() {
        let result = StressIndexEngine().calculate(from: StressIndexInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            sleepScoreLastNight: 45,
            strainScoreToday: 70
        ))
        let reasons = result.reasons.joined(separator: " ")

        XCTAssertTrue(reasons.contains("睡眠评分偏低"))
        XCTAssertFalse(reasons.contains("皮质醇"))
        XCTAssertFalse(reasons.contains("自主神经平衡"))
    }

    func testEnergyBankTrainingLoadUsesTRIMPScaleTodayLoad() {
        // 今日真实训练负荷 120 TRIMP，strain 评分 85（0-100 域）。
        // ATL/CTL/TSB 必须使用 TRIMP 域的 todayLoad 参与 EWMA；
        // 旧实现把 0-100 评分当 TRIMP 加入，ATL 被系统性拉低，深度负 TSB 被掩盖。
        let input = EnergyBankInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            recoveryScore: 75,
            sleepScore: 75,
            strainScore: 85,
            stressIndex: 50,
            strainHistory: [100, 95, 90, 85, 80, 75, 70], // newest-first TRIMP
            todayLoad: 120
        )
        let result = EnergyBankEngine().calculate(from: input)
        let tsb = result.components["tsb"] ?? 0
        let atl = result.components["atl"] ?? 0
        let ctl = result.components["ctl"] ?? 0
        // 暖启动（初期均值种子）后阈值按新语义校准：仍是深度负 TSB、急性高于慢性。
        XCTAssertLessThan(tsb, -5, "今日高负荷（120 TRIMP）应产生负 TSB，实际 \(tsb)")
        XCTAssertGreaterThan(atl, ctl, "急性负荷应高于慢性负荷：atl=\(atl) ctl=\(ctl)")
        XCTAssertGreaterThan(atl, 90, "120 TRIMP 应显著抬升 ATL，实际 \(atl)")
    }

    /// 暖启动回归：EWMA 不再被最旧的离群值锚定（旧实现以首值为种子）。
    func testEnergyBankEWMAWarmStartNotAnchoredByOldestOutlier() {
        let input = EnergyBankInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            recoveryScore: 75,
            sleepScore: 75,
            strainScore: 60,
            stressIndex: 50,
            strainHistory: [70, 70, 70, 70, 70, 70, 300], // newest-first，最旧=300 离群
            todayLoad: 70
        )
        let result = EnergyBankEngine().calculate(from: input)
        let ctl = result.components["ctl"] ?? 0
        XCTAssertLessThan(ctl, 120, "CTL 不应被最旧离群值 300 锚定，实际 \(ctl)")
        XCTAssertGreaterThan(ctl, 60, "CTL 应接近近期负荷 70，实际 \(ctl)")
    }

    func testStressEngineHRVFactorRespondsToRealisticHRVDecline() {
        // HRV 从基线 40ms 暴跌至 20ms（-50%），raw SD 10ms。
        // hrvSD 语义为原始 ms 域标准差；hrvZ 在 log 域计算，引擎须换算单位，
        // 否则 Z ≈ -0.07，HRV 压力因子被 25% 权重完全稀释。
        let result = StressIndexEngine().calculate(from: StressIndexInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            hrvToday: 20,
            hrvBaseline: 40,
            hrvSD: 10
        ))
        let hrvStress = result.components["hrv_stress"] ?? 0
        XCTAssertGreaterThan(hrvStress, 60, "HRV -50% 暴跌应产生显著压力信号，实际 \(hrvStress)")
    }

    func testBodyLimiterFramesLowHRVAsSignalNotPhysiologicalDiagnosis() {
        let previousLanguage = AppLanguage.stored
        defer { AppLanguage.stored = previousLanguage }
        AppLanguage.stored = .simplifiedChinese

        var dashboard = DashboardSummary.preview(date: Date())
        var recovery = dashboard.recovery
        recovery.components["hrv_z_score"] = -1.8
        dashboard.recovery = recovery

        let interpretation = BodyInterpreterEngine().interpret(
            dashboard: dashboard,
            wiki: [:],
            activePlan: nil
        )
        let copy = interpretation.primaryLimiter.interpretation

        XCTAssertTrue(copy.contains("HRV 低于个人基线"))
        XCTAssertFalse(copy.contains("副交感"))
        XCTAssertFalse(copy.contains("神经系统处于疲劳"))
    }

    func testProactiveTrainingInsightDoesNotPrescribeHighIntensity() {
        let previousLanguage = AppLanguage.stored
        defer { AppLanguage.stored = previousLanguage }
        AppLanguage.stored = .simplifiedChinese

        var dashboard = DashboardSummary.preview(date: Date())
        var recovery = dashboard.recovery
        recovery.components["hrv_z_score"] = 0.8
        recovery.components["rhr_z_score"] = -0.7
        dashboard.recovery = recovery
        var sleep = dashboard.sleepScore
        sleep.value = 86
        dashboard.sleepScore = sleep

        let insight = ProactiveInsightService.evaluate(dashboard: dashboard)
            .first { $0.focus == .training }

        XCTAssertNotNil(insight)
        XCTAssertTrue(insight?.title.contains("按计划训练") == true)
        XCTAssertFalse(insight?.coachPresetQuestion.contains("挑战性") == true)
        XCTAssertFalse(insight?.suggestedAction?.contains("渐进超负荷") == true)
    }

    func testLowHRVInsightFramesSignalWithoutPhysiologicalDiagnosis() {
        let previousLanguage = AppLanguage.stored
        defer { AppLanguage.stored = previousLanguage }
        AppLanguage.stored = .simplifiedChinese

        var dashboard = DashboardSummary.preview(date: Date())
        var recovery = dashboard.recovery
        recovery.components["hrv_z_score"] = -1.8
        dashboard.recovery = recovery

        let insight = ProactiveInsightService.evaluate(dashboard: dashboard)
            .first { $0.focus == .recovery }

        XCTAssertNotNil(insight)
        XCTAssertTrue(insight?.body.contains("恢复信号") == true)
        XCTAssertFalse(insight?.body.contains("高压力输出") == true)
        XCTAssertFalse(insight?.body.contains("收益会比风险低") == true)
        XCTAssertTrue(insight?.suggestedAction?.contains("若有不适") == true)
    }

    func testStrainScoreEngineProducesValidRange() {
        let engine = StrainScoreEngine()
        let input = StrainScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            workouts: [WorkoutInput(durationMinutes: 45, averageHeartRate: 140, rpe: 6)],
            activeEnergyToday: 500,
            exerciseMinutesToday: 45,
            restingHR: 60,
            maxHR: 180,
            last28DaysDailyLoads: []
        )
        let result = engine.calculate(from: input)
        XCTAssertGreaterThanOrEqual(result.value ?? 0, 0)
        XCTAssertLessThanOrEqual(result.value ?? 0, 100)
    }

    func testStrainScoreDoesNotInventHeartRateReserveWithoutProfile() {
        let result = StrainScoreEngine().calculate(from: StrainScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            workouts: [WorkoutInput(durationMinutes: 40, averageHeartRate: 145)],
            activeEnergyToday: 320,
            exerciseMinutesToday: 40,
            restingHR: 0,
            maxHR: 0,
            last28DaysDailyLoads: []
        ))

        XCTAssertTrue(result.reasons.contains { $0.contains("心率数据未用于个体化负荷计算") })
        XCTAssertTrue(result.reasons.contains { $0.contains("尚未形成个人历史负荷基线") })
    }

    func testStrainScoreDoesNotPublishWithoutActivityEvidence() {
        let result = StrainScoreEngine().calculate(from: StrainScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            restingHR: 60,
            maxHR: 190,
            last28DaysDailyLoads: [55, 60, 65]
        ))

        XCTAssertNil(result.value)
        XCTAssertFalse(result.hasData)
        XCTAssertEqual(result.confidence, .low)
        XCTAssertTrue(result.missingInputs.contains("workouts"))
    }

    func testEnergyBankDoesNotPublishWithoutRecoveryOrSleepEvidence() {
        let result = EnergyBankEngine().calculate(from: EnergyBankInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            recoveryScore: nil,
            sleepScore: nil,
            strainScore: 30,
            stressIndex: 20,
            hoursSinceWake: 4
        ))

        XCTAssertNil(result.value)
        XCTAssertFalse(result.hasData)
        XCTAssertEqual(result.confidence, .low)
        XCTAssertTrue(result.missingInputs.contains("recoveryScore"))
        XCTAssertTrue(result.missingInputs.contains("sleepScore"))
    }

    func testBodyStateKernelProvidesFallbackWithoutHealthKit() {
        let now = Date()
        let bodyState = BodyStateKernel().build(input: BodyStateInput(
            dashboard: .empty(date: now),
            activeStatus: "active",
            generatedAt: now
        ))

        XCTAssertEqual(bodyState.readiness, .unknown)
        XCTAssertEqual(bodyState.confidence, .low)
        XCTAssertEqual(bodyState.freshness, .missing)
        XCTAssertFalse(bodyState.drivers.isEmpty)
        XCTAssertFalse(bodyState.hash.isEmpty)
    }

    func testBodyStateKernelIncludesLocalFatigueAndTrainingResponseDrivers() {
        let now = Date()
        let workout = StrengthWorkoutRecord(
            title: "Leg Day",
            startedAt: now.addingTimeInterval(-6 * 3600),
            durationMinutes: 60,
            exercises: [
                StrengthExerciseLog(
                    name: "Squat",
                    equipment: "barbell",
                    primaryMuscleGroup: "legs",
                    sets: (0..<14).map { _ in
                        StrengthSetLog(repetitions: 8, weightKilograms: 100, rpe: 8, isCompleted: true)
                    }
                )
            ]
        )
        let response = TrainingResponseRecord(
            workoutId: UUID(),
            date: now.addingTimeInterval(-2 * 86_400),
            nextDayDate: now.addingTimeInterval(-86_400),
            primaryMuscleGroups: ["legs"],
            totalEffectiveSets: 12,
            totalVolumeKg: 9_600,
            nextDayRecoveryDelta: -10
        )

        let bodyState = BodyStateKernel().build(input: BodyStateInput(
            dashboard: .preview(date: now),
            strengthWorkouts: [workout.dto],
            trainingResponses: [response.dto],
            activeStatus: "active",
            generatedAt: now
        ))

        XCTAssertEqual(bodyState.localFatigue["legs"]?.fatigueLevel, "high")
        XCTAssertTrue(bodyState.drivers.contains { $0.kind == .localFatigue })
        XCTAssertTrue(bodyState.drivers.contains { $0.kind == .trainingResponse })
    }

    func testBodyStateAndTrainingDecisionUseChineseUserFacingCopy() {
        let previousLanguage = AppLanguage.stored
        AppLanguage.stored = .simplifiedChinese
        defer { AppLanguage.stored = previousLanguage }

        // 隔离阈值类静态污染：前置测试可能写 baselines.md / strategies.md 后未恢复。
        let baselineURL = WikiFileService.localURL(for: "baselines.md")
        let strategiesURL = WikiFileService.localURL(for: "strategies.md")
        let baselineOriginal = try? Data(contentsOf: baselineURL)
        let strategiesOriginal = try? Data(contentsOf: strategiesURL)
        func restoreWikiFile(_ data: Data?, to url: URL) {
            if let data {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? data.write(to: url)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
        defer {
            restoreWikiFile(baselineOriginal, to: baselineURL)
            restoreWikiFile(strategiesOriginal, to: strategiesURL)
            WikiFileService.invalidateDictionaryCache()
        }
        try? FileManager.default.removeItem(at: baselineURL)
        try? FileManager.default.removeItem(at: strategiesURL)
        WikiFileService.invalidateDictionaryCache()

        let now = Date()
        let response = TrainingResponseRecord(
            workoutId: UUID(),
            date: now.addingTimeInterval(-2 * 86_400),
            nextDayDate: now.addingTimeInterval(-86_400),
            primaryMuscleGroups: ["legs"],
            totalEffectiveSets: 12,
            totalVolumeKg: 9_600,
            nextDayRecoveryDelta: -10,
            nextDayHRVDelta: -12,
            nextDayRHRDelta: 6
        )

        let bodyState = BodyStateKernel().build(input: BodyStateInput(
            dashboard: .preview(date: now),
            trainingResponses: [response.dto],
            activeStatus: "active",
            generatedAt: now
        ))
        let decision = TrainingDecisionKernel().decide(input: TrainingDecisionInput(bodyState: bodyState))
        let model = TodayExperienceModel.build(
            dashboard: .preview(date: now),
            bodyState: bodyState,
            trainingDecision: decision,
            generatedAt: now
        )
        let userFacingText = (
            [decision.userFacingSummary, decision.safetyNotice]
            + decision.reasons
            + bodyState.drivers.flatMap { [$0.title, $0.detail] }
            + model.evidenceChips
            + [model.hero.summary, model.coachPreview]
        ).joined(separator: " ")

        XCTAssertFalse(userFacingText.contains("Recent training response"))
        XCTAssertFalse(userFacingText.contains("A legs session"))
        XCTAssertFalse(userFacingText.contains("Reduce planned volume"))
        XCTAssertFalse(userFacingText.contains("not a medical diagnosis"))
        XCTAssertTrue(userFacingText.contains("训练响应"))
        XCTAssertTrue(
            userFacingText.contains("减量") ||
            userFacingText.contains("替换") ||
            userFacingText.contains("调整")
        )
    }

    func testTodayExperienceDoesNotExposeLegacyEnglishDecisionCopy() {
        let previousLanguage = AppLanguage.stored
        AppLanguage.stored = .english
        defer { AppLanguage.stored = previousLanguage }

        let now = Date()
        let dashboard = DashboardSummary.preview(date: now)
        let bodyState = BodyStateKernel().build(input: BodyStateInput(
            dashboard: dashboard,
            activeStatus: "active",
            generatedAt: now
        ))
        let legacyDecision = DailyTrainingDecision(
            decision: .swap,
            targetSessionTitle: nil,
            volumeMultiplier: 0.65,
            intensityCap: 7,
            reasons: [
                "back local fatigue: 14 effective sets in 48h and 20 in 7d.",
                "Recent training response: back local fatigue."
            ],
            userFacingSummary: "Swap away from back and keep the session controlled.",
            confidence: 0.75,
            source: "legacy",
            safetyNotice: "General guidance only."
        )

        let model = TodayExperienceModel.build(
            dashboard: dashboard,
            bodyState: bodyState,
            trainingDecision: legacyDecision,
            generatedAt: now
        )
        let rendered = ([model.hero.summary, model.coachPreview] + model.evidenceChips)
            .joined(separator: " ")

        XCTAssertTrue(rendered.contains("替换"))
        XCTAssertFalse(rendered.contains("Swap away"))
        XCTAssertFalse(rendered.contains("back local fatigue"))
    }

    func testTrainingDecisionKernelRestsForSickStatus() {
        let now = Date()
        let bodyState = BodyStateKernel().build(input: BodyStateInput(
            dashboard: .preview(date: now),
            activeStatus: "sick",
            generatedAt: now
        ))

        let decision = TrainingDecisionKernel().decide(input: TrainingDecisionInput(bodyState: bodyState))

        XCTAssertEqual(decision.decision, .rest)
        XCTAssertEqual(decision.volumeMultiplier, 0)
        XCTAssertLessThanOrEqual(decision.intensityCap, 2)
        XCTAssertTrue(decision.safetyNotice.contains("不构成医疗诊断"))
    }

    func testLegacyTrainingDecisionIsACompatibilityViewOfCanonicalDecision() {
        let bodyState = BodyStateKernel().build(input: BodyStateInput(
            dashboard: .preview(),
            activeStatus: "active"
        ))
        let canonical = DailyTrainingDecision(
            decision: .reduce,
            targetSessionTitle: "Upper Strength",
            volumeMultiplier: 0.72,
            intensityCap: 7,
            reasons: ["Sleep: below baseline"],
            userFacingSummary: "建议减量训练。",
            confidence: 0.75,
            source: "BodyStateKernel + TrainingDecisionKernel",
            safetyNotice: "一般健康与训练建议，不构成医疗诊断。"
        )

        let compatibility = TrainingDecision.compatibilityView(
            of: canonical,
            bodyState: bodyState
        )

        XCTAssertEqual(compatibility.kind, .maintain)
        XCTAssertEqual(compatibility.volumeMultiplier, canonical.volumeMultiplier)
        XCTAssertEqual(compatibility.maxIntensity, "RPE 7")
        XCTAssertEqual(compatibility.whyThis, canonical.reasons.joined(separator: " "))
        XCTAssertEqual(compatibility.body, canonical.userFacingSummary)
    }

    func testTodayExperienceModelTurnsHealthyDashboardIntoActionableCommandCenter() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        var dashboard = DashboardSummary.preview(date: now)
        dashboard.recovery.value = 82
        dashboard.sleepScore.value = 86
        dashboard.strain.value = 44
        dashboard.stress.value = 32
        dashboard.energy.value = 76
        let bodyState = BodyStateKernel().build(input: BodyStateInput(
            dashboard: dashboard,
            activeStatus: "active",
            generatedAt: now
        ))
        let decision = TrainingDecisionKernel().decide(input: TrainingDecisionInput(bodyState: bodyState))

        let model = TodayExperienceModel.build(
            dashboard: dashboard,
            bodyState: bodyState,
            trainingDecision: decision,
            generatedAt: now,
            nutrition: .init(calories: 1_420, calorieTarget: 2_100, protein: 118, carbs: 168, fat: 42)
        )

        XCTAssertEqual(model.hero.scoreTitle, "恢复 82")
        XCTAssertEqual(model.hero.decisionTitle, "按计划训练")
        XCTAssertEqual(model.hero.primaryActionTitle, "查看今日训练建议")
        XCTAssertEqual(model.signalCards.map(\.id), ["recovery", "sleep", "strain", "stress", "energy"])
        XCTAssertEqual(
            model.signalCards.map(\.directionLabel),
            ["越高越好", "越高越好", "越高负荷越大", "越高越需关注", "越高越好"]
        )
        XCTAssertTrue(model.signalCards.allSatisfy { $0.coverageLabel != "暂无覆盖" })
        XCTAssertEqual(model.signalCards.first?.subtitle, "较好，支持计划训练")
        XCTAssertTrue(model.signalCards.allSatisfy { $0.trend.count == 1 })
        XCTAssertEqual(model.actions.count, 3)
        XCTAssertTrue(model.actions[0].title.contains("训练"))
        XCTAssertTrue(model.actions[0].evidence?.contains("恢复 82") == true)
        XCTAssertTrue(model.actions[0].evidence?.contains("睡眠 86") == true)
        XCTAssertTrue(model.coachPreview.contains("判断依据"))
        XCTAssertEqual(model.nutrition.calorieProgress, 0.676, accuracy: 0.001)
    }

    func testTodayExperienceModelIncludesSevenDaySignalTrends() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        var dashboard = DashboardSummary.preview(date: now)
        dashboard.recovery.value = 82
        dashboard.sleepScore.value = 86
        dashboard.strain.value = 44
        dashboard.stress.value = 32
        dashboard.energy.value = 76
        let bodyState = BodyStateKernel().build(input: BodyStateInput(
            dashboard: dashboard,
            activeStatus: "active",
            generatedAt: now
        ))
        let decision = TrainingDecisionKernel().decide(input: TrainingDecisionInput(bodyState: bodyState))
        let history = (1...8).map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            return DailyHealthSummaryDTO(
                dayIdentifier: "trend-\(offset)",
                date: date,
                updatedAt: date,
                recoveryScore: Double(60 + offset),
                sleepScore: Double(70 + offset),
                strainScore: Double(30 + offset),
                stressIndex: Double(40 + offset),
                currentEnergy: Double(50 + offset),
                morningEnergy: nil,
                energyBank: nil
            )
        }

        let model = TodayExperienceModel.build(
            dashboard: dashboard,
            bodyState: bodyState,
            trainingDecision: decision,
            generatedAt: now,
            history: history
        )

        XCTAssertEqual(model.signalCards.first(where: { $0.id == "recovery" })?.trend.count, 7)
        XCTAssertEqual(model.signalCards.first(where: { $0.id == "recovery" })?.trend.last, 82)
        XCTAssertEqual(model.signalCards.first(where: { $0.id == "sleep" })?.trend.last, 86)
        XCTAssertEqual(model.signalCards.first(where: { $0.id == "strain" })?.trend.last, 44)
        XCTAssertEqual(model.signalCards.first(where: { $0.id == "stress" })?.trend.last, 32)
        XCTAssertEqual(model.signalCards.first(where: { $0.id == "energy" })?.trend.last, 76)
    }

    func testTodayExperienceModelIsConservativeWhenHealthDataIsMissing() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let dashboard = DashboardSummary.empty(date: now)
        let bodyState = BodyStateKernel().build(input: BodyStateInput(
            dashboard: dashboard,
            activeStatus: "active",
            generatedAt: now
        ))
        let decision = TrainingDecisionKernel().decide(input: TrainingDecisionInput(bodyState: bodyState))

        let model = TodayExperienceModel.build(
            dashboard: dashboard,
            bodyState: bodyState,
            trainingDecision: decision,
            generatedAt: now,
            nutrition: .empty
        )

        XCTAssertEqual(model.hero.scoreTitle, "恢复 --")
        XCTAssertEqual(model.hero.decisionTitle, "正在同步身体数据")
        XCTAssertEqual(model.hero.confidenceLabel, "数据不足")
        XCTAssertEqual(model.hero.primaryActionTitle, "检查数据连接")
        XCTAssertTrue(model.evidenceChips.contains("等待 HealthKit"))
        XCTAssertEqual(model.actions.first?.title, "同步健康数据")
        XCTAssertEqual(model.signalCards.filter { $0.value == "--" }.count, 5)
        XCTAssertTrue(model.signalCards.allSatisfy { $0.coverageLabel == "暂无覆盖" })
        XCTAssertTrue(model.signalCards.allSatisfy { $0.trend.isEmpty })
    }

    func testMetricRecommendationPolicyUsesScoreDirectionAndThresholds() {
        var dashboard = DashboardSummary.preview(date: Date(timeIntervalSince1970: 1_780_000_000))
        dashboard.recovery.value = 32
        dashboard.stress.value = 78
        dashboard.strain.value = Double(dashboard.strain.recommendedRange.upperBound + 12)

        let recovery = MetricRecommendationPolicy.make(
            metric: .recovery,
            dashboard: dashboard,
            valueText: "32/100",
            hasData: true
        )
        let stress = MetricRecommendationPolicy.make(
            metric: .stress,
            dashboard: dashboard,
            valueText: "78/100",
            hasData: true
        )
        let strain = MetricRecommendationPolicy.make(
            metric: .strain,
            dashboard: dashboard,
            valueText: "82/100",
            hasData: true
        )

        XCTAssertTrue(recovery.title.contains("恢复优先"))
        XCTAssertTrue(stress.title.contains("低刺激恢复"))
        XCTAssertTrue(strain.title.contains("停止继续加量"))
    }

    func testMetricRecommendationPolicyDoesNotInventMissingReading() {
        let recommendation = MetricRecommendationPolicy.make(
            metric: .sleep,
            dashboard: .empty(date: Date(timeIntervalSince1970: 1_780_000_000)),
            valueText: "--",
            hasData: false
        )

        XCTAssertTrue(recommendation.title.contains("补齐数据"))
        XCTAssertTrue(recommendation.evidence.contains("不使用估算值"))
    }

    func testTodayExperienceNutritionClampsProgressAndExplainsUnsetTarget() {
        let overTarget = TodayExperienceNutrition(
            calories: 2_600,
            calorieTarget: 2_100,
            protein: 140,
            carbs: 260,
            fat: 74
        )
        let unsetTarget = TodayExperienceNutrition(
            calories: 840,
            calorieTarget: 0,
            protein: 42,
            carbs: 92,
            fat: 28
        )

        XCTAssertEqual(overTarget.calorieProgress, 1.0)
        XCTAssertEqual(unsetTarget.calorieProgress, 0.0)
        XCTAssertEqual(unsetTarget.calorieText, "840 kcal · 目标未设置")

        let noLogYet = TodayExperienceNutrition(
            calories: 0,
            calorieTarget: 2_000,
            protein: 0,
            carbs: 0,
            fat: 0
        )
        XCTAssertEqual(noLogYet.calorieText, "今日未记录")
        XCTAssertEqual(noLogYet.macroText, "今日营养尚未记录")
    }

    func testTodayExperienceActionPlanMapsEveryTrainingDecision() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        var dashboard = DashboardSummary.preview(date: now)
        dashboard.recovery.value = 82
        dashboard.sleepScore.value = 86
        dashboard.strain.value = 44
        dashboard.stress.value = 32
        dashboard.energy.value = 76
        let bodyState = BodyStateKernel().build(input: BodyStateInput(
            dashboard: dashboard,
            activeStatus: "active",
            generatedAt: now
        ))

        let expectations: [(DailyTrainingDecisionType, String, String, String)] = [
            (.keep, "查看训练边界", "review_training", "training"),
            (.reduce, "训练时控制容量", "reduce_training", "training"),
            (.swap, "替换训练内容", "swap_session", "training"),
            (.rest, "执行恢复日", "recovery_day", "recovery")
        ]

        for (type, title, actionID, destination) in expectations {
            let decision = DailyTrainingDecision(
                decision: type,
                targetSessionTitle: nil,
                volumeMultiplier: type == .keep ? 1.0 : 0.65,
                intensityCap: type == .rest ? 2 : 7,
                reasons: ["Test evidence"],
                userFacingSummary: "Test summary",
                confidence: 0.75,
                source: "test",
                safetyNotice: "test"
            )
            let model = TodayExperienceModel.build(
                dashboard: dashboard,
                bodyState: bodyState,
                trainingDecision: decision,
                generatedAt: now
            )
            let primary = try XCTUnwrap(model.actions.first(where: \.isPrimary))

            XCTAssertEqual(primary.title, title)
            XCTAssertEqual(primary.id, actionID)
            XCTAssertEqual(primary.destination, destination)
        }
    }

    func testActionPlanFollowsKernelConclusionForElevatedStress() {
        // 压力 85：算法打通批次 A 后 Kernel 有压力分支（rest），
        // TodayCommandBuilder 投影为 recover——标题与行动与 Kernel 同源，不再同屏矛盾。
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        var dashboard = DashboardSummary.preview(date: now)
        dashboard.recovery.value = 72
        dashboard.sleepScore.value = 80
        dashboard.strain.value = 44
        dashboard.stress.value = 85
        dashboard.energy.value = 70
        let bodyState = BodyStateKernel().build(input: BodyStateInput(
            dashboard: dashboard,
            activeStatus: "active",
            generatedAt: now
        ))
        let kernelDecision = TrainingDecisionKernel().decide(input: TrainingDecisionInput(
            bodyState: bodyState
        ))
        let commandState = TodayCommandBuilder.build(
            from: dashboard,

            coachArtifact: nil,
            trainingDecision: kernelDecision
        )
        let readiness = commandState.readinessDecision.decision

        let model = TodayExperienceModel.build(
            dashboard: dashboard,
            bodyState: bodyState,
            trainingDecision: kernelDecision,
            readiness: readiness
        )

        XCTAssertEqual(kernelDecision.decision, .rest, "Kernel 应识别压力偏高并建议恢复")
        XCTAssertEqual(readiness, .recover)
        XCTAssertEqual(model.hero.decisionTitle, "恢复优先")
        let primary = model.actions.first(where: \.isPrimary)
        XCTAssertEqual(primary?.id, "recovery_day")
    }

    func testTrainingSurfaceSummaryPrefersOperatingPlanPayload() {
        let dashboard = DashboardSummary.preview()
        let bodyState = BodyStateKernel().build(input: BodyStateInput(dashboard: dashboard))
        let decision = TrainingDecisionKernel().decide(input: TrainingDecisionInput(bodyState: bodyState))
        let today = TodayExperienceModel.build(
            dashboard: dashboard,
            bodyState: bodyState,
            trainingDecision: decision
        )
        let payload = DailyOperatingPlanPayload(
            decision: .reduce,
            volumeMultiplier: 0.75,
            intensityCap: 7,
            summary: "Reduce today by 25% and keep RPE under 7.",
            targetSessionTitle: "Upper strength"
        )

        let model = TrainingSurfaceSummaryModel.build(
            dashboard: dashboard,
            todayExperience: today,
            trainingDecision: decision,
            operatingPlan: payload
        )

        XCTAssertEqual(model.decision, .reduce)
        XCTAssertEqual(model.sessionTitle, "Upper strength")
        XCTAssertTrue(model.guidance.contains("25%"))
        XCTAssertEqual(model.intensityCapText, "RPE <= 7")
    }

    func testDailyOperatingPlanBuildsBoundedCrossDomainActionSequence() throws {
        let now = Date(timeIntervalSince1970: 1_781_654_400)
        var dashboard = DashboardSummary.preview(date: now)
        dashboard.recovery.value = 48
        dashboard.sleepScore.value = 52
        dashboard.stress.value = 86
        dashboard.energy.value = 42
        let bodyState = BodyStateKernel().build(input: BodyStateInput(
            dashboard: dashboard,
            activeStatus: "active",
            generatedAt: now
        ))
        let decision = TrainingDecisionKernel().decide(input: TrainingDecisionInput(
            bodyState: bodyState
        ))

        let payload = DailyOperatingPlanBuilder.build(
            bodyState: bodyState,
            decision: decision,
            brief: dashboard.personalHealthBrief,
            language: .simplifiedChinese
        )

        let primary = try XCTUnwrap(payload.primaryAction)
        XCTAssertEqual(payload.schemaVersion, DailyOperatingPlanPayload.currentSchemaVersion)
        XCTAssertTrue(payload.hasCanonicalActionSequence)
        XCTAssertLessThanOrEqual(payload.supportingActions.count, 2)
        XCTAssertFalse(payload.supportingActions.contains { $0.domain == primary.domain })
        XCTAssertEqual(Set(payload.supportingActions.map(\.domain)).count, payload.supportingActions.count)
        XCTAssertTrue(payload.supportingActions.contains { $0.domain == .sleep })

        let experience = TodayExperienceModel.build(
            dashboard: dashboard,
            bodyState: bodyState,
            trainingDecision: decision,
            operatingPlan: payload
        )
        XCTAssertEqual(experience.actions.first?.id, primary.id)
        XCTAssertEqual(experience.actions.first?.isPrimary, true)
        XCTAssertEqual(experience.actions.dropFirst().map(\.id), payload.supportingActions.map(\.id))
    }

    func testDailyOperatingPlanLegacyPayloadDecodesAndAwaitsMigration() throws {
        let legacyJSON = #"{"decision":"reduce","volumeMultiplier":0.75,"intensityCap":7,"summary":"Reduce safely","targetSessionTitle":null}"#
        let payload = try JSONDecoder().decode(
            DailyOperatingPlanPayload.self,
            from: try XCTUnwrap(legacyJSON.data(using: .utf8))
        )

        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertEqual(payload.decision, .reduce)
        XCTAssertNil(payload.primaryAction)
        XCTAssertTrue(payload.supportingActions.isEmpty)
        XCTAssertFalse(payload.hasCanonicalActionSequence)
    }

    func testDailyOperatingPlanDropsDuplicateAndOverflowSupportingDomains() {
        let primary = DailyOperatingPlanAction(
            id: "primary",
            domain: .training,
            title: "Train",
            detail: "Primary",
            destination: "training",
            evidence: nil
        )
        let actions = [
            DailyOperatingPlanAction(id: "same", domain: .training, title: "Duplicate", detail: "", destination: "training", evidence: nil),
            DailyOperatingPlanAction(id: "sleep-1", domain: .sleep, title: "Sleep", detail: "", destination: "evidence", evidence: nil),
            DailyOperatingPlanAction(id: "sleep-2", domain: .sleep, title: "Sleep again", detail: "", destination: "evidence", evidence: nil),
            DailyOperatingPlanAction(id: "move", domain: .movement, title: "Move", detail: "", destination: "recovery", evidence: nil),
            DailyOperatingPlanAction(id: "eat", domain: .eatingRhythm, title: "Eat", detail: "", destination: "evidence", evidence: nil)
        ]

        let payload = DailyOperatingPlanPayload(
            decision: .keep,
            volumeMultiplier: 1,
            intensityCap: 8,
            summary: "Keep",
            targetSessionTitle: nil,
            primaryAction: primary,
            supportingActions: actions
        )

        XCTAssertEqual(payload.supportingActions.map(\.id), ["sleep-1", "move"])
        XCTAssertTrue(payload.hasCanonicalActionSequence)
    }

    func testTrainingSurfaceSummaryStaysConservativeWithoutHealthData() {
        let dashboard = DashboardSummary.empty(date: Date(timeIntervalSince1970: 1_781_654_400))
        let bodyState = BodyStateKernel().build(input: BodyStateInput(dashboard: dashboard))
        let decision = TrainingDecisionKernel().decide(input: TrainingDecisionInput(bodyState: bodyState))
        let today = TodayExperienceModel.build(
            dashboard: dashboard,
            bodyState: bodyState,
            trainingDecision: decision
        )

        let model = TrainingSurfaceSummaryModel.build(
            dashboard: dashboard,
            todayExperience: today,
            trainingDecision: decision,
            operatingPlan: nil
        )

        XCTAssertEqual(model.confidenceLabel, "数据不足")
        XCTAssertTrue(model.guidance.contains("保守"))
        XCTAssertEqual(model.recoveryValue, "--")
        XCTAssertEqual(model.sleepValue, "--")
    }

    func testDailyOperatingPlanDisplayModelLocalizesChineseTrainingFallbacks() {
        let payload = DailyOperatingPlanPayload(
            decision: .reduce,
            volumeMultiplier: 0.75,
            intensityCap: 7,
            summary: "建议减量训练，动作质量下降时停止加量。",
            targetSessionTitle: nil
        )

        let model = DailyOperatingPlanDisplayModel.build(
            payload: payload,
            primaryActionType: "reduce",
            source: "BodyStateKernel + TrainingDecisionKernel",
            safetyNotice: "一般健康与训练建议，不构成医疗诊断。",
            confidence: 0.5,
            isChinese: true
        )

        XCTAssertEqual(model.actionLabel, "减量")
        XCTAssertEqual(model.statusTitle, "建议训练 · RPE 7")
        XCTAssertTrue(model.summary.contains("75%"))
        XCTAssertTrue(model.summary.contains("动作质量下降"))
        XCTAssertFalse(model.summary.contains("Reduce"))
        XCTAssertFalse(model.evidenceLine.contains("BodyStateKernel"))
        XCTAssertFalse(model.evidenceLine.contains("medical diagnosis"))
        XCTAssertTrue(model.evidenceLine.contains("本地身体状态"))
        XCTAssertEqual(model.confidenceLabel, "判断依据有限")
    }

    func testPersonalBaselineThresholdResolutionAndFallback() {
        let baselineURL = WikiFileService.localURL(for: "baselines.md")
        
        // Save existing file content if any
        let originalContent = try? String(contentsOf: baselineURL, encoding: .utf8)
        defer {
            // Restore original content or clean up
            if let originalContent = originalContent {
                try? originalContent.write(to: baselineURL, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: baselineURL)
            }
        }
        
        // Case 1: No baseline file / insufficient days of data (< 7)
        try? FileManager.default.removeItem(at: baselineURL)
        let fallbackThresholds = PersonalBaselineEngine.resolveThresholds()
        XCTAssertEqual(fallbackThresholds.source, "using default conservative threshold")
        XCTAssertEqual(fallbackThresholds.recoveryRest, 40)
        XCTAssertEqual(fallbackThresholds.recoveryCaution, 62)
        XCTAssertEqual(fallbackThresholds.recoveryHigh, 70)
        XCTAssertEqual(fallbackThresholds.sleepCaution, 68)
        XCTAssertEqual(fallbackThresholds.sleepRest, 55)
        
        // Case 2: Valid baseline file with >= 7 days of data
        let baselines = PersonalBaselines(
            hrvBaselineMean: 50.0,
            hrvBaselineSD: 5.0,
            rhrBaselineMean: 60.0,
            rhrBaselineSD: 4.0,
            sleepHoursBaseline: 8.0,
            sleepEfficiencyBaseline: 0.90,
            deepSleepPercentBaseline: 0.20,
            remSleepPercentBaseline: 0.20,
            strainBaselineMean: 10.0,
            stepsBaseline: 10000,
            activeCaloriesBaseline: 400.0,
            calculatedAt: Date(),
            daysOfData: 10,
            recoveryBaselineMean: 65.0,
            recoveryBaselineSD: 8.0,
            sleepScoreBaselineMean: 70.0,
            sleepScoreBaselineSD: 6.0
        )
        
        PersonalBaselineEngine.saveBaselinesToWiki(baselines)
        
        let resolved = PersonalBaselineEngine.resolveThresholds()
        XCTAssertEqual(resolved.source, "using personal baseline")
        XCTAssertEqual(resolved.recoveryRest, 50.0)
        XCTAssertEqual(resolved.recoveryCaution, 58.6)
        XCTAssertEqual(resolved.recoveryHigh, 65.0)
        XCTAssertEqual(resolved.sleepCaution, 65.2)
        XCTAssertEqual(resolved.sleepRest, 60.0)
        
        // Let's test that BodyStateKernel uses the resolved thresholds.
        var dashboard = DashboardSummary.preview()
        dashboard.recovery.value = 45.0
        dashboard.sleepScore.value = 80.0
        
        let bodyState = BodyStateKernel().build(input: BodyStateInput(dashboard: dashboard))
        XCTAssertEqual(bodyState.readiness, .recovering)
        
        // Under default thresholds:
        try? FileManager.default.removeItem(at: baselineURL)
        let bodyStateFallback = BodyStateKernel().build(input: BodyStateInput(dashboard: dashboard))
        XCTAssertEqual(bodyStateFallback.readiness, .caution)
    }

    func testMetricResultMissingDataReturnsFormattedDashAndUnavailableCoverage() {
        let date = Date()
        let missingMetric = MetricResult(
            domain: .recovery,
            name: "Recovery Score",
            value: nil,
            band: .low,
            confidence: .low,
            components: [:],
            componentWeights: [:],
            reasons: ["No HealthKit signals available"],
            missingInputs: ["hrv", "rhr", "sleep"],
            dataWindow: DateInterval(start: date, duration: 86400),
            source: .derived,
            algorithmVersion: "1.0.0",
            lastUpdated: date
        )

        XCTAssertFalse(missingMetric.hasData)
        XCTAssertEqual(missingMetric.formattedScore, "--")
        XCTAssertEqual(missingMetric.dataCoverage, .unavailable)
        XCTAssertEqual(missingMetric.domain, .recovery)
        XCTAssertEqual(missingMetric.direction, .higherIsBetter)
        XCTAssertEqual(missingMetric.missingInputs, ["hrv", "rhr", "sleep"])
    }

    func testMetricResultWithDataReturnsFormattedNumberAndCompleteCoverage() {
        let date = Date()
        let completeMetric = MetricResult(
            domain: .recovery,
            name: "Recovery Score",
            value: 82.4,
            band: .high,
            confidence: .high,
            components: ["hrv": 65.0, "rhr": 55.0],
            componentWeights: ["hrv": 0.6, "rhr": 0.4],
            reasons: ["Good HRV trend"],
            missingInputs: [],
            dataWindow: DateInterval(start: date, duration: 86400),
            source: .healthKit,
            algorithmVersion: "1.0.0",
            lastUpdated: date
        )

        XCTAssertTrue(completeMetric.hasData)
        XCTAssertEqual(completeMetric.formattedScore, "82")
        XCTAssertEqual(completeMetric.dataCoverage, .complete)
        XCTAssertEqual(completeMetric.score, 82.4)
    }

    func testEmptyDashboardProducesUnavailableSignalsAndNoAggregateReadinessScore() {
        let date = Date()
        let emptyDashboard = DashboardSummary.empty(date: date)

        // Verify 5 independent scored health evidence metrics exist and are all unpopulated
        XCTAssertFalse(emptyDashboard.recovery.hasData)
        XCTAssertFalse(emptyDashboard.sleepScore.hasData)
        XCTAssertFalse(emptyDashboard.strain.hasData)
        XCTAssertFalse(emptyDashboard.stress.hasData)
        XCTAssertFalse(emptyDashboard.energy.hasData)

        XCTAssertEqual(emptyDashboard.recovery.formattedScore, "--")
        XCTAssertEqual(emptyDashboard.sleepScore.formattedScore, "--")
        XCTAssertEqual(emptyDashboard.strain.formattedScore, "--")

        // Verify ADR 0003 compliance: domains are distinct and independent
        XCTAssertEqual(emptyDashboard.recovery.domain, .recovery)
        XCTAssertEqual(emptyDashboard.sleepScore.domain, .sleep)
        XCTAssertEqual(emptyDashboard.strain.domain, .strain)
        XCTAssertEqual(emptyDashboard.stress.domain, .physiologicalStress)
        XCTAssertEqual(emptyDashboard.energy.domain, .energy)
    }

    func testTodayExperienceModelBuildsCleanSignalsFromEmptyDashboard() {
        let date = Date()
        let emptyDashboard = DashboardSummary.empty(date: date)
        let bodyState = emptyDashboard.bodyState
        let decision = DailyTrainingDecision(
            decision: .rest,
            volumeMultiplier: 0.5,
            intensityCap: 50,
            reasons: ["Data missing"],
            userFacingSummary: "Waiting for health data",
            confidence: 0.0,
            source: "test",
            safetyNotice: "Notice"
        )

        let experience = TodayExperienceModel.build(
            dashboard: emptyDashboard,
            bodyState: bodyState,
            trainingDecision: decision,
            generatedAt: date
        )

        XCTAssertEqual(experience.signalCards.count, 5)
        for card in experience.signalCards {
            XCTAssertEqual(card.value, "--", "Signal \(card.id) should be formatted as -- when missing data")
            XCTAssertEqual(card.coverageLabel, "暂无覆盖")
        }
    }

    @MainActor
    func testWorkoutSaveCoordinatorCreatesTrainingResponseRecordAndArtifact() async throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let modelContext = container.mainContext

        let exercise = StrengthExerciseLog(
            name: "杠铃卧推",
            equipment: "杠铃",
            primaryMuscleGroup: "chest",
            sets: [
                StrengthSetLog(repetitions: 10, weightKilograms: 80.0, isWarmup: false, rpe: 8.0, isCompleted: true),
                StrengthSetLog(repetitions: 8, weightKilograms: 85.0, isWarmup: false, rpe: 9.0, isCompleted: true)
            ]
        )
        let workout = StrengthWorkoutRecord(
            title: "胸肌力量训练",
            startedAt: Date(),
            durationMinutes: 45,
            notes: "感觉状态很好",
            exercises: [exercise]
        )
        workout.sessionRPE = 8.5

        let artifact = CoachArtifactRecord(artifact: CoachArtifact(
            type: .askCoachAnswer,
            title: "训练总结",
            summary: "完成了胸部力量训练",
            confidence: 1,
            reasons: [
                CoachArtifactReason(
                    signal: "卧推",
                    value: "80kg",
                    explanation: "完成计划训练组"
                )
            ],
            actions: [
                CoachArtifactAction(
                    type: "recovery",
                    label: "安排充分蛋白质补充"
                )
            ],
            sourceContextHash: "hash123"
        ))

        let coordinator = WorkoutSaveCoordinator()
        let result = try coordinator.commitNewWorkout(
            workout: workout,
            artifact: artifact,
            sessionRPE: 8.5,
            modelContext: modelContext
        )

        XCTAssertEqual(result.workout.id, workout.id)
        XCTAssertEqual(result.event.linkedStrengthWorkoutId, workout.id)
        XCTAssertEqual(result.event.rpe, 8.5)

        // Verify TrainingResponseRecord was automatically generated and linked
        let workoutID = workout.id
        let responseDescriptor = FetchDescriptor<TrainingResponseRecord>(
            predicate: #Predicate<TrainingResponseRecord> { $0.workoutId == workoutID }
        )
        let responses = try modelContext.fetch(responseDescriptor)
        XCTAssertEqual(responses.count, 1)

        let response = responses[0]
        XCTAssertEqual(response.primaryMuscleGroups, ["chest"])
        XCTAssertEqual(response.totalEffectiveSets, 2)
        XCTAssertEqual(response.totalVolumeKg, (10 * 80.0) + (8 * 85.0))
        XCTAssertEqual(response.sessionRPE, 8.5)

        // Verify deletion cleans up all linked records
        try WorkoutAggregationService.shared.deleteStrengthWorkout(workout, modelContext: modelContext)
        let remainingResponses = try modelContext.fetch(responseDescriptor)
        XCTAssertEqual(remainingResponses.count, 0)

        // join 保存与删除调度的计划刷新任务，避免 fire-and-forget 任务越过测试存活
        await DailyPlanRefreshCoordinator.shared.latestTask?.value
    }

    @MainActor
    func testCommitNewWorkoutExposesAwaitablePlanRefreshIndependentOfCallerContext() async throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let revisionBefore = VelaAppState.shared.localDataRevision

        let workout = StrengthWorkoutRecord(
            title: "计划刷新测试",
            startedAt: Date(),
            durationMinutes: 45,
            notes: "",
            exercises: []
        )
        workout.sessionRPE = 8.0
        let artifact = CoachArtifactRecord(artifact: CoachArtifact(
            type: .askCoachAnswer,
            title: "训练总结",
            summary: "刷新测试",
            confidence: 1,
            reasons: [],
            actions: [],
            sourceContextHash: "refresh-hash"
        ))

        let coordinator = WorkoutSaveCoordinator()
        var capturedContext: ModelContext? = container.mainContext
        _ = try coordinator.commitNewWorkout(
            workout: workout,
            artifact: artifact,
            sessionRPE: 8.0,
            modelContext: capturedContext!
        )
        // 调用方不再持有 context：刷新任务必须自持 container 完成，不得依赖调用方 context
        capturedContext = nil

        await DailyPlanRefreshCoordinator.shared.latestTask?.value

        XCTAssertGreaterThan(VelaAppState.shared.localDataRevision, revisionBefore)
    }

    @MainActor
    func testDictationControllerStopWithoutInstalledTapDoesNotCrash() {
        // 从未安装 tap 时调用 stop()（或连续两次 stop()）不得触发
        // AVAudioNode.removeTap(onBus:) 的无 tap ObjC 异常（Swift 不可捕获 → 直接崩溃）。
        let controller = CoachDictationController()
        controller.stop()
        controller.stop()
        XCTAssertFalse(controller.isRecording)
    }

    @MainActor
    func testRecoveryImpactDataHonorsMissingRPEInsteadOfAssumingMedium() {
        // 用户跳过训练后自评：workout/event 均无 RPE。
        // 展示层不得把缺失解释为中等强度（旧实现 rpe ?? 6），应显示无法估算。
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = StrengthWorkoutRecord(
            title: "无自评训练",
            startedAt: start,
            durationMinutes: 45,
            notes: "",
            exercises: []
        )
        let event = WorkoutEventRecord(
            source: "strengthLog",
            startedAt: start,
            endedAt: start.addingTimeInterval(2700),
            activityType: "无自评训练",
            energyKilocalories: 300,
            rpe: nil,
            linkedStrengthWorkoutId: workout.id,
            calendar: .current
        )
        let impact = PostWorkoutImpact(
            workout: workout,
            event: event,
            response: nil,
            todaySummary: nil,
            nextDaySummary: nil,
            postWorkoutStart: start,
            postWorkoutHeartRates: []
        )
        XCTAssertNil(impact.strainCost)
        XCTAssertTrue(impact.strainSourceText.contains("未填写"))
    }

    func testOutboundRevokeClosesBackgroundNetworkAIChannel() {
        // 「撤销全部联网数据授权」必须同时关闭后台自动化的独立 consent 体系，
        // 否则晚间 Wiki 同步/晨间简报仍会向网络 AI 发送完整健康事实集。
        let previousConsent = AutoAgentConfig.shared.backgroundNetworkAIConsent
        let previousPolicy = CoachOutboundDataPolicy.stored
        let hadExplicitConsent = CoachOutboundDataPolicy.hasExplicitConsent
        defer {
            AutoAgentConfig.shared.backgroundNetworkAIConsent = previousConsent
            if hadExplicitConsent {
                previousPolicy.saveExplicitConsent()
            } else {
                CoachOutboundDataPolicy.revoke()
            }
        }

        AutoAgentConfig.shared.backgroundNetworkAIConsent = true
        CoachOutboundDataPolicy.revoke()

        XCTAssertFalse(AutoAgentConfig.shared.backgroundNetworkAIConsent)
        XCTAssertFalse(AutoAgentConfig.shared.canSendHealthContextToNetworkAI)
    }

    @MainActor
    func testCoachRetryTargetsTheFailedQuestionNotTheLastMessage() {
        // Q1 失败（重试气泡）→ Q2 成功。点 Q1 的重试必须重发 Q1，
        // 旧实现取「最后一条用户消息」会重复回答 Q2。
        let q1 = CoachChatVM.ChatMsg(role: .user, content: "Q1 我的恢复怎么样？")
        let q1Error = CoachChatVM.ChatMsg(
            role: .assistant,
            content: "AI 服务暂时不可用",
            recoveryAction: LLMErrorRecoveryAction(title: "重试", systemImage: "arrow.clockwise", destination: .retry)
        )
        let q2 = CoachChatVM.ChatMsg(role: .user, content: "Q2 今晚睡眠建议？")
        let a2 = CoachChatVM.ChatMsg(role: .assistant, content: "A2")

        let target = CoachChatVM.userMessageForRetry(in: [q1, q1Error, q2, a2])

        XCTAssertEqual(target?.text, "Q1 我的恢复怎么样？")
        XCTAssertEqual(target?.retryBubbleId, q1Error.id)
    }

    @MainActor
    func testTodayHealthToolSerializesReasonsWithoutCrash() async throws {
        // 真实设备场景：dashboard 带 reasons 时，prefix(3) 产生 ArraySlice（Swift 结构体），
        // JSONSerialization 会抛不可捕获的 NSException「Invalid type in JSON write (__SwiftValue)」。
        let container = try VelaModelContainer.make(inMemory: true)
        var dashboard = DashboardSummary.preview()
        dashboard.recovery.reasons = ["HRV 低于基线", "睡眠不足", "负荷偏高", "第四条"]
        dashboard.sleepScore.reasons = ["睡眠时长不足", "深睡偏少"]
        let context = ToolExecutionContext(modelContext: container.mainContext, dashboard: dashboard)
        let tool = TodayHealthTool(executionContext: context)

        let result = try await tool.execute(arguments: #"{"sections": ["autonomic", "sleep"]}"#)

        let obj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any],
            "工具返回必须是合法 JSON"
        )
        XCTAssertNotNil(obj["autonomic"])
        XCTAssertNotNil(obj["sleep"])
    }

    // MARK: - MetricResult.state (G1 状态着色)

    private func makeMetric(domain: ScoredHealthDomain, band: MetricBand) -> MetricResult {
        MetricResult(
            domain: domain,
            name: domain.rawValue,
            value: 50,
            band: band,
            confidence: .high,
            components: [:],
            componentWeights: [:],
            reasons: [],
            missingInputs: [],
            dataWindow: DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86400),
            source: .healthKit,
            algorithmVersion: "test",
            lastUpdated: Date(timeIntervalSince1970: 0)
        )
    }

    func testExplicitStrainReferenceRangeNeverUsesCompatibilityFallback() {
        var metric = makeMetric(domain: .strain, band: .normal)
        XCTAssertNil(metric.explicitRecommendedRange)

        metric.components["recommended_lower"] = 35
        metric.components["recommended_upper"] = 65
        XCTAssertEqual(metric.explicitRecommendedRange, 35...65)

        metric.components["recommended_lower"] = 80
        XCTAssertNil(metric.explicitRecommendedRange)
    }

    func testMetricStateHigherIsBetter() {
        XCTAssertEqual(makeMetric(domain: .recovery, band: .high).state, .good)
        XCTAssertEqual(makeMetric(domain: .sleep, band: .veryHigh).state, .good)
        XCTAssertEqual(makeMetric(domain: .energy, band: .normal).state, .moderate)
        XCTAssertEqual(makeMetric(domain: .recovery, band: .low).state, .poor)
        XCTAssertEqual(makeMetric(domain: .sleep, band: .veryLow).state, .poor)
    }

    func testMetricStateHigherNeedsAttention() {
        XCTAssertEqual(makeMetric(domain: .physiologicalStress, band: .low).state, .good)
        XCTAssertEqual(makeMetric(domain: .physiologicalStress, band: .veryLow).state, .good)
        XCTAssertEqual(makeMetric(domain: .physiologicalStress, band: .normal).state, .moderate)
        XCTAssertEqual(makeMetric(domain: .physiologicalStress, band: .high).state, .poor)
        XCTAssertEqual(makeMetric(domain: .physiologicalStress, band: .veryHigh).state, .poor)
    }

    func testMetricStateHigherIsLoad() {
        XCTAssertEqual(makeMetric(domain: .strain, band: .normal).state, .good)
        XCTAssertEqual(makeMetric(domain: .strain, band: .low).state, .moderate)
        XCTAssertEqual(makeMetric(domain: .strain, band: .high).state, .moderate)
        XCTAssertEqual(makeMetric(domain: .strain, band: .veryLow).state, .poor)
        XCTAssertEqual(makeMetric(domain: .strain, band: .veryHigh).state, .poor)
    }

    // MARK: - 数值审计修复回归（V1/V4/V5/V7）

    /// V1：睡眠效率 105%（inBed 短于总睡眠）应钳制 1.0，而非除以 100 得 0.0105。
    func testSleepEfficiencyFractionOverOneClampsToOne() {
        XCTAssertEqual(HealthUnitNormalizer.normalizeSleepEfficiency(1.05), 1.0, accuracy: 0.0001)
        XCTAssertEqual(HealthUnitNormalizer.normalizeSleepEfficiency(0.85), 0.85, accuracy: 0.0001)
        XCTAssertEqual(HealthUnitNormalizer.normalizeSleepEfficiency(85.0), 0.85, accuracy: 0.0001)
        XCTAssertEqual(HealthUnitNormalizer.normalizeSleepEfficiency(0.0), 0.0, accuracy: 0.0001)
    }

    /// V4：睡眠数据缺失 + 恢复正常时不应误判「减量」。
    func testMissingSleepDataDoesNotForceReduceDecision() {
        var dashboard = DashboardSummary.empty(date: Date())
        dashboard.recovery = MetricResult(
            name: "Recovery", value: 80, band: .normal, confidence: .high,
            components: [:], componentWeights: [:], reasons: ["HRV 正常"],
            missingInputs: [], dataWindow: DateInterval(start: Date(), duration: 86400),
            source: .derived, algorithmVersion: "audit", lastUpdated: Date()
        )
        dashboard.sleepScore = MetricResult(
            name: "Sleep", value: nil, band: .low, confidence: .low,
            components: [:], componentWeights: [:], reasons: [],
            missingInputs: ["sleep"], dataWindow: DateInterval(start: Date(), duration: 86400),
            source: .derived, algorithmVersion: "audit", lastUpdated: Date()
        )
        let result = TodayCommandBuilder.readinessDecision(from: dashboard, signals: [], recentStrengthSummary: nil)
        // 睡眠/压力缺失时保守降级为 reduce，且理由必须诚实说明是数据缺失
        //（不得是「不够低到休息、不够强到满量」这类误导性文案）。
        XCTAssertEqual(result.decision, .reduce, "睡眠数据缺失应保守降级，实际 \(result.decision)")
        XCTAssertFalse(result.reasons.contains { $0.contains("not strong enough") },
            "理由不得误导为「数据不达标」：\(result.reasons)")
    }

    /// V7：Stress 引擎 SD=0 应回退基线 SD，而非除零静默满分。
    func testStressEngineZeroSDFallsBackInsteadOfFullScore() {
        let input = StressIndexInput(
            asOf: Date(), mode: .rawVitals,
            quietHRToday: 60, quietHRBaseline: 55, quietHRSD: 0.0,
            isWithinWorkoutWindow: false
        )
        let result = StressIndexEngine().calculate(from: input)
        XCTAssertNotNil(result.value, "SD=0 时不应因除零而丢失输出")
        if let value = result.value {
            XCTAssertLessThan(value, 100.0, "SD=0 不应产出满分，实际 \(value)")
        }
    }

    /// V5：todayLoad 缺失时 ACWR 不得随 0-100 评分域 strainScore 漂移。
    func testEnergyBankAcwrIgnoresScoreWhenTodayLoadMissing() {
        func acwr(strainScore: Double) -> Double? {
            let input = EnergyBankInput(
                asOf: Date(),
                recoveryScore: 70, sleepScore: 70, strainScore: strainScore, stressIndex: 30,
                hrvToday: 50, hrvBaseline: 50, rhrToday: 55, rhrBaseline: 55, sleepHours: 7.5,
                strainHistory: Array(repeating: 30.0, count: 42),
                todayLoad: nil
            )
            return EnergyBankEngine().calculate(from: input).components["acwr"]
        }
        let a = acwr(strainScore: 100)
        let b = acwr(strainScore: 50)
        XCTAssertEqual(a, b, "todayLoad 缺失时 acwr 不应随评分域 strainScore 变化：100→\(String(describing: a)) vs 50→\(String(describing: b))")
    }

    // MARK: - 批次二修复回归

    /// 回归：多个失败气泡时，重试锚定在点击的气泡对应的用户问题上。
    @MainActor
    func testCoachRetryAnchorTargetsTheTappedBubble() {
        let q1 = CoachChatVM.ChatMsg(role: .user, content: "Q1")
        let f1 = CoachChatVM.ChatMsg(
            role: .assistant, content: "服务不可用",
            recoveryAction: LLMErrorRecoveryAction(title: "重试", systemImage: "arrow.clockwise", destination: .retry)
        )
        let q2 = CoachChatVM.ChatMsg(role: .user, content: "Q2")
        let f2 = CoachChatVM.ChatMsg(
            role: .assistant, content: "服务不可用",
            recoveryAction: LLMErrorRecoveryAction(title: "重试", systemImage: "arrow.clockwise", destination: .retry)
        )
        let messages = [q1, f1, q2, f2]

        let target1 = CoachChatVM.userMessageForRetry(in: messages, retryBubbleId: f1.id)
        let target2 = CoachChatVM.userMessageForRetry(in: messages, retryBubbleId: f2.id)

        XCTAssertEqual(target1?.text, "Q1", "点 Q1 的气泡必须重发 Q1")
        XCTAssertEqual(target2?.text, "Q2", "点 Q2 的气泡必须重发 Q2")
    }

    /// 回归：ReportGenerator 的上下文裁剪必须产出合法 JSON，而非字符截断残片。
    func testReportContextTrimmingProducesValidJSONWithinBudget() throws {
        var dict: [String: Any] = ["small": 1]
        for i in 0..<200 {
            dict["key_\(i)"] = String(repeating: "x", count: 200)
        }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        let full = String(data: data, encoding: .utf8)!

        let trimmed = ReportGenerator.trimmedContextJSON(from: full, maxChars: 3000)

        XCTAssertLessThanOrEqual(trimmed.utf8.count, 3000, "裁剪结果必须在预算内")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any]
        )
        XCTAssertLessThan(object.count, 200, "应丢弃部分键")
        XCTAssertNotNil(object["small"], "小键应保留")
    }

    // MARK: - 决策反馈回灌（C1）

    func testDecisionFeedbackCalibrationAdjustsConfidenceByAccuracy() {
        let base = 0.76
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func record(_ rating: String?, offset: Double = 0) -> DailyDecisionFeedbackRecord {
            DailyDecisionFeedbackRecord(
                dayIdentifier: "fb-\(UUID().uuidString)",
                bodyStateHash: "h",
                decisionType: "keep",
                decisionTitle: "按计划训练",
                accuracyRating: rating,
                createdAt: now.addingTimeInterval(-offset)
            )
        }

        // 样本不足：不校准
        let few = [record("accurate"), record("inaccurate")]
        XCTAssertEqual(
            DecisionFeedbackCalibrator.calibratedConfidence(base: base, decision: .keep, records: few, now: now),
            base,
            accuracy: 0.0001,
            "样本 < 3 不应校准"
        )

        // 4/5 准确 → 乘数 0.6 + 0.4*0.8 = 0.92
        let mixed = [
            record("accurate"), record("accurate"), record("accurate"),
            record("accurate"), record("inaccurate")
        ]
        XCTAssertEqual(
            DecisionFeedbackCalibrator.calibratedConfidence(base: base, decision: .keep, records: mixed, now: now),
            0.76 * 0.92,
            accuracy: 0.0001,
            "4/5 准确应把置信度乘 0.92"
        )

        // 全准确 → 乘数 1.0，置信度不变
        let perfect = [record("accurate"), record("accurate"), record("accurate")]
        XCTAssertEqual(
            DecisionFeedbackCalibrator.calibratedConfidence(base: base, decision: .keep, records: perfect, now: now),
            base,
            accuracy: 0.0001
        )

        // 过期反馈不计入
        let stale = [record("inaccurate", offset: 40 * 86_400), record("accurate"), record("accurate")]
        XCTAssertEqual(
            DecisionFeedbackCalibrator.calibratedConfidence(base: base, decision: .keep, records: stale, now: now),
            base,
            accuracy: 0.0001,
            "超过 28 天的反馈不应计入"
        )
    }

    func testDecisionFeedbackCalibrationNormalizesRestToRecover() {
        // PR1 回归：写入路径存 DailyTrainingDecisionType（"rest"），
        // 校准器按 ReadinessDecisionKind（"recover"）匹配——必须归一化，恢复日反馈不得丢弃。
        let base = 0.72
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let restRecords = (0..<3).map { i in
            DailyDecisionFeedbackRecord(
                dayIdentifier: "rest-\(i)",
                bodyStateHash: "h",
                decisionType: "rest",
                decisionTitle: "休息",
                accuracyRating: i < 2 ? "accurate" : "inaccurate",
                createdAt: now
            )
        }
        // 2/3 准确 → 乘数 0.6 + 0.4 * (2/3)
        XCTAssertEqual(
            DecisionFeedbackCalibrator.calibratedConfidence(base: base, decision: .recover, records: restRecords, now: now),
            base * (0.6 + 0.4 * (2.0 / 3.0)),
            accuracy: 0.0001,
            "rest 记录的反馈必须计入 recover 决策的校准"
        )
    }

    func testDecisionFeedbackCalibrationCountsPartlyAsHalfCredit() {
        // PR9 回归：「部分准确」按 0.5 计分，不再误判为不准确。
        let base = 0.8
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let records = (0..<3).map { i in
            DailyDecisionFeedbackRecord(
                dayIdentifier: "p-\(i)",
                bodyStateHash: "h",
                decisionType: "keep",
                decisionTitle: "t",
                accuracyRating: i == 2 ? "partly" : "accurate",
                createdAt: now
            )
        }
        // (1 + 1 + 0.5)/3 = 5/6 → 乘数 0.6 + 0.4 * (5/6)
        XCTAssertEqual(
            DecisionFeedbackCalibrator.calibratedConfidence(base: base, decision: .keep, records: records, now: now),
            base * (0.6 + 0.4 * (5.0 / 6.0)),
            accuracy: 0.0001
        )
    }

    func testComputationProfileUsesFallbacksWhenManualAndWikiEmpty() {
        // F1/M1 机制回归：手动与 wiki 均无值时，HealthKit 兜底必须生效。
        let defaults = UserDefaults.standard
        let keys = [UserProfileSettings.ageKey, UserProfileSettings.biologicalSexKey]
        let originals = keys.map { defaults.object(forKey: $0) }
        let wikiURL = WikiFileService.localURL(for: "profile.md")
        let wikiOriginal = try? Data(contentsOf: wikiURL)
        defer {
            for (key, value) in zip(keys, originals) {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            if let wikiOriginal {
                try? FileManager.default.createDirectory(at: wikiURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? wikiOriginal.write(to: wikiURL)
            } else {
                try? FileManager.default.removeItem(at: wikiURL)
            }
        }
        defaults.removeObject(forKey: UserProfileSettings.ageKey)
        defaults.removeObject(forKey: UserProfileSettings.biologicalSexKey)
        try? FileManager.default.removeItem(at: wikiURL)

        let profile = DailyHealthComputationProfile.current(
            ageFallback: 29,
            biologicalSexFallback: "female"
        )
        XCTAssertEqual(profile.maxHeartRate, UserProfileSettings.inferredMaxHeartRate(age: 29))
        XCTAssertEqual(profile.biologicalSex, "female")
    }

    // MARK: - 时间衰减基线（B1）

    func testRecencyWeightedMeanEmphasizesRecentSamples() {
        // 30 个样本：前 23 个 = 10，近 7 个 = 20。
        let values = Array(repeating: 10.0, count: 23) + Array(repeating: 20.0, count: 7)
        let weighted = PersonalBaselineEngine.recencyWeightedMean(values)
        // 期望 = (10*23 + 20*7*2) / (23 + 14) = 510/37 ≈ 13.78
        XCTAssertEqual(weighted ?? 0, 510.0 / 37.0, accuracy: 0.0001)
        XCTAssertGreaterThan(weighted ?? 0, 12.33, "加权后必须更靠近近期水平")
        let short = PersonalBaselineEngine.recencyWeightedMean([1, 2, 3])
        XCTAssertEqual(short ?? 0, 2.0, accuracy: 0.0001)
    }

    // MARK: - 训练响应校准（C3）

    func testTrainingResponseCalibratorAdjustsVolumeByMeanRecoveryDelta() {
        let base = 1.0
        // 样本不足：不校准
        XCTAssertEqual(
            TrainingResponseCalibrator.calibratedVolumeMultiplier(base: base, recoveryDeltas: [-5, 3, 2]),
            base,
            accuracy: 0.0001
        )
        // 平均恢复变化 +5 → ×1.05
        let positive = [5.0, 6.0, 4.0, 5.0, 6.0, 4.0]
        XCTAssertEqual(
            TrainingResponseCalibrator.calibratedVolumeMultiplier(base: base, recoveryDeltas: positive),
            1.05,
            accuracy: 0.0001
        )
        // 平均恢复变化 -20 → 0.8（低于下限 0.85 → 钳 0.85）
        let crash = [-20.0, -20.0, -20.0, -20.0, -20.0, -20.0]
        XCTAssertEqual(
            TrainingResponseCalibrator.calibratedVolumeMultiplier(base: base, recoveryDeltas: crash),
            0.85,
            accuracy: 0.0001
        )
    }

    // MARK: - token 预算（B3）

    func testTokenEstimationWeightsChineseHeavierThanASCII() {
        let ascii = String(repeating: "a", count: 4000)
        let chinese = String(repeating: "汉", count: 2000)
        XCTAssertEqual(ContextBudget.estimatedTokenCount(ascii), 1000, "4000 ASCII ≈ 1000 token")
        XCTAssertEqual(ContextBudget.estimatedTokenCount(chinese), 3000, "2000 汉字 ≈ 3000 token")
        XCTAssertGreaterThan(
            ContextBudget.estimatedTokenCount(chinese),
            ContextBudget.estimatedTokenCount(ascii)
        )
    }

    // MARK: - 计划日解析与训练页同源

    func testTrainingDecisionKernelSkipsPlanDayCompletedThroughWorkoutEvent() {
        let calendar = Calendar.current
        let now = Date()
        let todayNumber = calendar.component(.weekday, from: now) == 1
            ? 7
            : calendar.component(.weekday, from: now) - 1
        let tomorrowNumber = todayNumber == 7 ? 1 : todayNumber + 1

        let todayDay = TrainingDay(
            id: UUID(),
            weekNumber: 1,
            dayNumber: todayNumber,
            title: "今天已完成",
            description: "",
            focus: "strength",
            durationMinutes: 45,
            intensity: "moderate",
            isCompleted: false
        )
        let tomorrowDay = TrainingDay(
            id: UUID(),
            weekNumber: tomorrowNumber == 1 ? 2 : 1,
            dayNumber: tomorrowNumber,
            title: "明天待执行",
            description: "",
            focus: "strength",
            durationMinutes: 45,
            intensity: "moderate",
            isCompleted: false
        )
        let plan = TrainingPlanRecord(
            title: "Schedule Test",
            goalDescription: "",
            startDate: now,
            isActive: true,
            days: [todayDay, tomorrowDay]
        )
        let completedEvent = WorkoutEventRecord(
            source: "manual",
            startedAt: now.addingTimeInterval(-3600),
            endedAt: now,
            activityType: "Strength",
            linkedTrainingPlanDayId: todayDay.id
        )

        var dashboard = DashboardSummary.preview(date: now)
        dashboard.recovery.value = 85
        dashboard.sleepScore.value = 85
        dashboard.strain.value = 40
        dashboard.stress.value = 30
        dashboard.energy.value = 80
        let bodyState = BodyStateKernel().build(input: BodyStateInput(
            dashboard: dashboard,
            activeStatus: "active",
            generatedAt: now
        ))

        let decision = TrainingDecisionKernel().decide(input: TrainingDecisionInput(
            bodyState: bodyState,
            activePlan: plan.dto,
            workoutEvents: [completedEvent.dto]
        ))

        XCTAssertEqual(decision.targetSessionTitle, "明天待执行")
        XCTAssertNotEqual(decision.targetSessionTitle, "今天已完成")
    }
}

    /// 契约测试（P0-A）：未同步/空数据时，canonical TrainingDecision 必须落在
    /// 保守窗口（reduce/0.60/RPE≤7），不得出现 keep@100%——文案与命令行
    /// 「保守健康窗口」承诺的是同一个边界。
    func testUnsyncedDataProducesConservativeBoundariesInsteadOfKeep100() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let bodyState = BodyStateKernel().build(input: BodyStateInput(
            dashboard: .empty(date: now),
            trainingResponses: [],
            activeStatus: "active",
            generatedAt: now
        ))
        let decision = TrainingDecisionKernel().decide(
            input: TrainingDecisionInput(bodyState: bodyState)
        )

        XCTAssertEqual(decision.decision, .reduce, "未同步数据不得给出 keep@100%")
        XCTAssertLessThanOrEqual(decision.volumeMultiplier, 0.7)
        XCTAssertLessThanOrEqual(decision.intensityCap, 7)
        XCTAssertEqual(decision.confidence, 0.0, "数据不可用时不得给出伪置信度")
        XCTAssertFalse(
            decision.userFacingSummary.contains("等待数据同步"),
            "摘要应如实表达保守窗口"
        )
        // 与既有 fallback、今日命令状态（readinessDecision → .reduce）同一边界语义
        let fallback = TrainingDecisionFallback.conservative(targetSessionTitle: decision.targetSessionTitle)
        XCTAssertEqual(decision.volumeMultiplier, fallback.volumeMultiplier)
        XCTAssertEqual(decision.intensityCap, fallback.intensityCap)
    }

    /// 回归测试（XII）：训练记录完成计数必须同时统计 workout_completed 与
    /// workout_log —— 否则「产品质量诊断」长期少计训练打卡。
    @MainActor
    func testQualitySnapshotCountsBothWorkoutCompletionEventTypes() throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        context.insert(VelaEventRecord(
            eventType: VelaProductEventType.workoutCompleted,
            timestamp: now.addingTimeInterval(-3600),
            title: "打卡"
        ))
        context.insert(VelaEventRecord(
            eventType: "workout_log",
            timestamp: now.addingTimeInterval(-7200),
            title: "日志"
        ))
        context.insert(VelaEventRecord(
            eventType: VelaProductEventType.healthSyncSucceeded,
            timestamp: now.addingTimeInterval(-3600),
            title: "同步"
        ))
        try context.save()

        let snapshot = DailyDecisionFeedbackService().qualitySnapshot(
            modelContext: context,
            periodDays: 28,
            now: now
        )

        XCTAssertEqual(snapshot.workoutLogs, 2, "workout_completed 与 workout_log 都应计入")
    }
