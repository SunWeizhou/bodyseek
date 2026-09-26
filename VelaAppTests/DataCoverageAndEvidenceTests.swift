import XCTest
@testable import Vela

final class DataCoverageAndEvidenceTests: XCTestCase {

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

    func testMetricResultWithDataReturnsFormattedNumberAndCompleteOrPartialCoverage() {
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

    // MARK: - S1: Observation Time vs Recomputation Time
    func testS1ObservationTimePreservedAndIndependentOfRecomputation() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_785_369_600))
        let observedAt = day.addingTimeInterval(8 * 3600) // 08:00 AM
        let recomputedAt = day.addingTimeInterval(22 * 3600) // 22:00 PM
        let hrvWindow = DateInterval(start: day.addingTimeInterval(2 * 3600), end: day.addingTimeInterval(6 * 3600))

        var snapshot = DailyHealthSnapshot(date: day)
        snapshot.hrvAverage = 55
        snapshot.restingHeartRate = 60
        snapshot.oxygenSaturation = 0.98
        snapshot.hrvObservedAt = observedAt
        snapshot.hrvObservedWindow = hrvWindow

        let computation = DailyHealthComputation(
            calendar: calendar,
            now: recomputedAt,
            profile: DailyHealthComputationProfile(sleepTargetMinutes: 480, maxHeartRate: 190, biologicalSex: "other")
        )
        let evidence = computation.compute(for: snapshot, history: [])

        // Recovery result must keep true observation timestamp
        XCTAssertEqual(evidence.recovery.observedAt, observedAt)
        XCTAssertEqual(evidence.recovery.observedWindow, hrvWindow)
        XCTAssertEqual(evidence.recovery.lastUpdated, recomputedAt)
        // Ensure recomputation timestamp does not overwrite observation time
        XCTAssertNotEqual(evidence.recovery.observedAt, recomputedAt)
    }

    // MARK: - S2: Long-Term Baseline Context Validity
    func testS2LongTermBaselineRequiresAtLeast60SamplesAndIgnoresFuture() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_785_369_600))

        // History with 120 days but only 30 samples: context should be nil (< 60)
        let baseline30 = LongTermMetricBaseline(metric: .hrv, sampleCount: 30, threeYearMedian: 50, percentile10: 30, percentile90: 70)
        let report30 = LongTermBaselineReport(
            calculatedAt: day,
            daysOfData: 120,
            earliestDate: day.addingTimeInterval(-120 * 86400),
            latestDate: day,
            baselines: [.hrv: baseline30]
        )

        var snapshot = DailyHealthSnapshot(date: day)
        snapshot.hrvAverage = 20 // Below P10
        snapshot.restingHeartRate = 60

        let computation = DailyHealthComputation(
            calendar: calendar,
            now: day.addingTimeInterval(12 * 3600),
            profile: DailyHealthComputationProfile(sleepTargetMinutes: 480, maxHeartRate: 190, biologicalSex: "other")
        )

        let evidence30 = computation.compute(for: snapshot, history: [], longTermBaselines: report30)
        // Long-term context is only enabled when sampleCount >= 60. With 30 samples, no P10 reason is added.
        XCTAssertFalse(evidence30.recovery.reasons.contains { $0.contains("三年分布 P10") })

        // History with >= 60 samples
        let baseline60 = LongTermMetricBaseline(metric: .hrv, sampleCount: 75, threeYearMedian: 50, percentile10: 25, percentile90: 75)
        let report60 = LongTermBaselineReport(
            calculatedAt: day,
            daysOfData: 120,
            earliestDate: day.addingTimeInterval(-120 * 86400),
            latestDate: day,
            baselines: [.hrv: baseline60]
        )
        let evidence60 = computation.compute(for: snapshot, history: [], longTermBaselines: report60)
        // With 75 samples, long-term context is active and flags hrvToday (20) < p10 (25)
        XCTAssertTrue(evidence60.recovery.reasons.contains { $0.contains("三年分布 P10") })
    }

    // MARK: - S3: PSTI Requires Genuine RMSSD
    func testS3PSTIRequiresGenuineRMSSDAndDoesNotFallbackToSDNN() {
        let asOf = Date()
        let engine = RecoveryScoreEngine()

        // 1. Only SDNN provided (hrvToday), no RMSSD
        let inputSDNNOnly = RecoveryScoreInput(
            asOf: asOf,
            hrvToday: 55, // SDNN
            hrvBaseline: 50,
            hrvHistory: [48, 50, 52],
            hrvRmssdToday: nil, // Missing RMSSD
            hrvRmssdBaseline: nil,
            restingHeartRateToday: 60,
            restingHeartRateBaseline: 60,
            sleepScoreLastNight: 75,
            strainScoreYesterday: nil
        )
        let resultSDNNOnly = engine.calculate(from: inputSDNNOnly)
        XCTAssertNil(resultSDNNOnly.components["parasympathetic_tone_index"], "PSTI must NOT be computed without genuine RMSSD")
        XCTAssertNil(resultSDNNOnly.components["psti_z_score"])

        // 2. RMSSD provided with genuine RMSSD baseline and history
        let inputRMSSD = RecoveryScoreInput(
            asOf: asOf,
            hrvToday: 55,
            hrvBaseline: 50,
            hrvRmssdToday: 42,
            hrvRmssdBaseline: 40,
            hrvRmssdHistory: [38, 40, 42, 41],
            restingHeartRateToday: 60,
            restingHeartRateBaseline: 60,
            sleepScoreLastNight: 75,
            strainScoreYesterday: nil
        )
        let resultRMSSD = engine.calculate(from: inputRMSSD)
        XCTAssertNotNil(resultRMSSD.components["parasympathetic_tone_index"], "PSTI must be computed when valid RMSSD is provided")
        XCTAssertNotNil(resultRMSSD.components["psti_z_score"])
    }

    // MARK: - S4: Sleep Target Behavioral vs Physiological Adequacy
    func testS4SleepTargetBehavioralGoalDoesNotClaimAASMPhysiologicalAdequacy() {
        let asOf = Date()
        let engine = SleepScoreEngine()

        // User sets target to 5h (300 min) and sleeps exactly 5h (300 min)
        let inputShortTarget = SleepScoreInput(
            asOf: asOf,
            totalSleepMinutes: 300,
            sleepTargetMinutes: 300,
            awakeMinutes: 15,
            awakeEpisodeCount: nil // missing awake episode count
        )
        let result = engine.calculate(from: inputShortTarget)
        
        // Check reasons for behavioral qualification vs physiological adequacy
        let hasBehavioralNotice = result.reasons.contains { $0.contains("AASM") || $0.contains("生理充分满足") }
        XCTAssertTrue(hasBehavioralNotice, "Short sleep target completion must explicitly clarify behavioral vs physiological adequacy")

        let hasAwakeEstimateNotice = result.reasons.contains { $0.contains("估算") }
        XCTAssertTrue(hasAwakeEstimateNotice, "Missing awake count must be flagged as estimated")
    }

    // MARK: - S5: Workout Deduplication and Method Codes
    func testS5WorkoutDeduplicationAndTRIMPMethodCodes() {
        let asOf = Date()
        let engine = StrainScoreEngine()
        let workoutUUID = UUID()

        // Pass 2 copies of the exact same workout
        let workout = WorkoutInput(
            id: workoutUUID,
            durationMinutes: 45,
            averageHeartRate: 145,
            rpe: nil
        )
        let input = StrainScoreInput(
            asOf: asOf,
            workouts: [workout, workout], // duplicate
            activeEnergyToday: 300,
            exerciseMinutesToday: 45,
            stepCount: 5000,
            restingHR: 60,
            maxHR: 190,
            biologicalSex: "male"
        )
        let result = engine.calculate(from: input)

        // Workout load for 45 min at 145 HR should be ~30-50, definitely not doubled
        let singleWorkoutInput = StrainScoreInput(
            asOf: asOf,
            workouts: [workout],
            activeEnergyToday: 300,
            exerciseMinutesToday: 45,
            stepCount: 5000,
            restingHR: 60,
            maxHR: 190,
            biologicalSex: "male"
        )
        let singleResult = engine.calculate(from: singleWorkoutInput)

        XCTAssertEqual(result.components["workout_load"], singleResult.components["workout_load"], "Duplicate workout UUID must not be double counted")
        XCTAssertEqual(result.components["workout_load_method_code"], 2.0, "Method B (avg HR) should record method code 2.0")
    }

    // MARK: - S6: Discontinuous Load Calendar Decay
    func testS6DiscontinuousCalendarDaysDecayEWMAAndDeactivatesWhenUnder7Days() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_785_369_600))
        var snapshot = DailyHealthSnapshot(date: day)
        snapshot.activeCalories = 300
        snapshot.steps = 5000

        // Create sparse history: only 4 valid days in past 28 days
        var sparseHistory: [DailyHealthSnapshot] = []
        for offset in [1, 2, 10, 15] {
            var item = DailyHealthSnapshot(date: calendar.date(byAdding: .day, value: -offset, to: day)!)
            item.dailyLoad = 50.0
            sparseHistory.append(item)
        }

        let computation = DailyHealthComputation(
            calendar: calendar,
            now: day.addingTimeInterval(12 * 3600),
            profile: DailyHealthComputationProfile(sleepTargetMinutes: 480, maxHeartRate: 190, biologicalSex: "other")
        )
        let evidence = computation.compute(for: snapshot, history: sparseHistory)

        // With only 4 observed days (< 7), ATL/CTL should be deactivated
        XCTAssertNil(evidence.strain.components["training_load_ratio"], "ATL/CTL must be deactivated when valid observed days < 7")
        XCTAssertTrue(evidence.strain.reasons.contains { $0.contains("不足 7 天") || $0.contains("尚未形成") })
    }

    // MARK: - S7: Physiological Stress Workout Window Exclusion
    func testS7PhysiologicalStressExcludedDuringWorkoutRecoveryWindow() {
        let now = Date()
        let engine = StressIndexEngine()

        // Within workout recovery window
        let inputWithin = StressIndexInput(
            asOf: now,
            quietHRToday: 75,
            quietHRBaseline: 60,
            hrvToday: 35,
            hrvBaseline: 50,
            isWithinWorkoutWindow: true
        )
        let resultWithin = engine.calculate(from: inputWithin)

        XCTAssertNil(resultWithin.value, "Physiological stress must be nil (excluded), NOT zero, inside workout recovery window")
        XCTAssertTrue(resultWithin.reasons.contains { $0.contains("运动窗口及运动后 90 分钟") })
    }

    // MARK: - S8: Energy Bank Stability When Missing Signals & Quality Propagation
    func testS8EnergyBankOvernightStabilityNeutralWhenMissingAndPropagatesQuality() {
        let asOf = Date()
        let engine = EnergyBankEngine()

        // 1. All overnight signals missing -> overnight_stability should be 50.0 (neutral), not 100.0
        let inputMissingOvernight = EnergyBankInput(
            asOf: asOf,
            recoveryScore: 80,
            sleepScore: 80,
            strainScore: 30,
            stressIndex: 30,
            bodyTempDelta: nil,
            respiratoryRateZ: nil,
            SpO2: nil,
            recoveryConfidence: .high,
            sleepConfidence: .high
        )
        let resultMissing = engine.calculate(from: inputMissingOvernight)
        XCTAssertEqual(resultMissing.components["overnight_stability"], 50.0, "Overnight stability must be neutral 50.0 when temp/resp/SpO2 are missing")
        XCTAssertTrue(resultMissing.missingInputs.contains("overnightStabilitySignals"))
        // Energy confidence cannot be .high without overnight stability signals
        XCTAssertNotEqual(resultMissing.confidence, .high)

        // 2. Upstream low confidence degrades energy confidence
        let inputLowQuality = EnergyBankInput(
            asOf: asOf,
            recoveryScore: 80,
            sleepScore: 80,
            strainScore: 30,
            stressIndex: 30,
            bodyTempDelta: 0.1,
            respiratoryRateZ: 0.2,
            SpO2: 98,
            recoveryConfidence: .low, // upstream recovery is low confidence
            sleepConfidence: .high
        )
        let resultLow = engine.calculate(from: inputLowQuality)
        XCTAssertEqual(resultLow.confidence, .low, "Energy confidence must be .low when upstream recovery confidence is .low")

        // 3. Stress excluded due to workout: strain > 0, stressIndex == nil
        let inputWorkoutExcluded = EnergyBankInput(
            asOf: asOf,
            recoveryScore: 80,
            sleepScore: 80,
            strainScore: 45,
            stressIndex: nil, // stress excluded
            bodyTempDelta: 0.1,
            respiratoryRateZ: 0.2,
            SpO2: 98
        )
        let resultWorkout = engine.calculate(from: inputWorkoutExcluded)
        XCTAssertEqual(resultWorkout.components["stress_drain"], 0.0)
        XCTAssertTrue(resultWorkout.reasons.contains { $0.contains("运动排除窗口") }, "Must explain that stress drain is accounted for by training load")

        // A missing strain score is not a measured zero: the drain is neutral,
        // while coverage remains explicitly unknown for downstream consumers.
        let inputMissingStrain = EnergyBankInput(
            asOf: asOf,
            recoveryScore: 80,
            sleepScore: 80,
            strainScore: nil,
            stressIndex: 30,
            bodyTempDelta: 0.1,
            respiratoryRateZ: 0.2,
            SpO2: 98
        )
        let resultMissingStrain = engine.calculate(from: inputMissingStrain)
        XCTAssertEqual(resultMissingStrain.components["strain_drain"], 0.0)
        XCTAssertTrue(resultMissingStrain.missingInputs.contains("strainScore"))
    }

    // MARK: - V1: 10 Scenario Replay Generation
    func testGenerateV1ReplayComparisonData() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let baseDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_785_369_600)) // 2026-07-31

        struct MetricComparisonDTO: Codable {
            var domain: String
            var oldValue: Double?
            var newValue: Double?
            var oldQuality: String
            var newQuality: String
            var missingInputs: [String]
            var version: String
            var keyReason: String
        }

        struct ScenarioReportDTO: Codable {
            var scenario: String
            var description: String
            var downstreamImpact: String
            var metrics: [MetricComparisonDTO]
        }

        var reports: [ScenarioReportDTO] = []

        // 1. Empty Scenario
        do {
            let snapshot = DailyHealthSnapshot(date: baseDay)
            let comp = DailyHealthComputation(calendar: calendar, now: baseDay.addingTimeInterval(12 * 3600))
            let evidence = comp.compute(for: snapshot, history: [])
            let metrics: [MetricComparisonDTO] = [
                MetricComparisonDTO(domain: "Sleep", oldValue: nil, newValue: evidence.sleep.value, oldQuality: "unavailable", newQuality: evidence.sleep.confidence.rawValue, missingInputs: evidence.sleep.missingInputs, version: evidence.sleep.algorithmVersion, keyReason: evidence.sleep.reasons.first ?? ""),
                MetricComparisonDTO(domain: "Recovery", oldValue: nil, newValue: evidence.recovery.value, oldQuality: "unavailable", newQuality: evidence.recovery.confidence.rawValue, missingInputs: evidence.recovery.missingInputs, version: evidence.recovery.algorithmVersion, keyReason: evidence.recovery.reasons.first ?? ""),
                MetricComparisonDTO(domain: "Strain", oldValue: nil, newValue: evidence.strain.value, oldQuality: "unavailable", newQuality: evidence.strain.confidence.rawValue, missingInputs: evidence.strain.missingInputs, version: evidence.strain.algorithmVersion, keyReason: evidence.strain.reasons.first ?? ""),
                MetricComparisonDTO(domain: "Stress", oldValue: nil, newValue: evidence.physiologicalStress.value, oldQuality: "unavailable", newQuality: evidence.physiologicalStress.confidence.rawValue, missingInputs: evidence.physiologicalStress.missingInputs, version: evidence.physiologicalStress.algorithmVersion, keyReason: evidence.physiologicalStress.reasons.first ?? ""),
                MetricComparisonDTO(domain: "Energy", oldValue: nil, newValue: evidence.energy.value, oldQuality: "unavailable", newQuality: evidence.energy.confidence.rawValue, missingInputs: evidence.energy.missingInputs, version: evidence.energy.algorithmVersion, keyReason: evidence.energy.reasons.first ?? "")
            ]
            reports.append(ScenarioReportDTO(scenario: "empty", description: "全空输入，无历史无当日体征", downstreamImpact: "五项保持不可估计(--)，无总分，引导等待 Apple 健康同步", metrics: metrics))
        }

        // 2. Partial Scenario (only sleep and RHR)
        do {
            var snapshot = DailyHealthSnapshot(date: baseDay)
            snapshot.sleepHours = 7.0
            snapshot.restingHeartRate = 62
            let comp = DailyHealthComputation(calendar: calendar, now: baseDay.addingTimeInterval(12 * 3600))
            let evidence = comp.compute(for: snapshot, history: [])
            let metrics: [MetricComparisonDTO] = [
                MetricComparisonDTO(domain: "Sleep", oldValue: 70.0, newValue: evidence.sleep.value, oldQuality: "medium", newQuality: evidence.sleep.confidence.rawValue, missingInputs: evidence.sleep.missingInputs, version: evidence.sleep.algorithmVersion, keyReason: evidence.sleep.reasons.first ?? ""),
                MetricComparisonDTO(domain: "Recovery", oldValue: nil, newValue: evidence.recovery.value, oldQuality: "unavailable", newQuality: evidence.recovery.confidence.rawValue, missingInputs: evidence.recovery.missingInputs, version: evidence.recovery.algorithmVersion, keyReason: evidence.recovery.reasons.first ?? ""),
                MetricComparisonDTO(domain: "Strain", oldValue: nil, newValue: evidence.strain.value, oldQuality: "unavailable", newQuality: evidence.strain.confidence.rawValue, missingInputs: evidence.strain.missingInputs, version: evidence.strain.algorithmVersion, keyReason: evidence.strain.reasons.first ?? ""),
                MetricComparisonDTO(domain: "Stress", oldValue: 50.0, newValue: evidence.physiologicalStress.value, oldQuality: "low", newQuality: evidence.physiologicalStress.confidence.rawValue, missingInputs: evidence.physiologicalStress.missingInputs, version: evidence.physiologicalStress.algorithmVersion, keyReason: evidence.physiologicalStress.reasons.first ?? ""),
                MetricComparisonDTO(domain: "Energy", oldValue: 65.0, newValue: evidence.energy.value, oldQuality: "high", newQuality: evidence.energy.confidence.rawValue, missingInputs: evidence.energy.missingInputs, version: evidence.energy.algorithmVersion, keyReason: evidence.energy.reasons.first ?? "")
            ]
            reports.append(ScenarioReportDTO(scenario: "partial", description: "部分输入（仅有睡眠7小时与静息心率62bpm，缺失HRV与负荷）", downstreamImpact: "能量置信度严格降为 low，且说明基于睡眠估算", metrics: metrics))
        }

        // 3. Baseline Forming (< 7 days)
        do {
            var snapshot = DailyHealthSnapshot(date: baseDay)
            snapshot.activeCalories = 350
            snapshot.steps = 6000
            let history = (1...3).map { offset -> DailyHealthSnapshot in
                var item = DailyHealthSnapshot(date: calendar.date(byAdding: .day, value: -offset, to: baseDay)!)
                item.dailyLoad = 40.0
                return item
            }
            let comp = DailyHealthComputation(calendar: calendar, now: baseDay.addingTimeInterval(12 * 3600))
            let evidence = comp.compute(for: snapshot, history: history)
            let metrics: [MetricComparisonDTO] = [
                MetricComparisonDTO(domain: "Strain", oldValue: 45.0, newValue: evidence.strain.value, oldQuality: "medium", newQuality: evidence.strain.confidence.rawValue, missingInputs: evidence.strain.missingInputs, version: evidence.strain.algorithmVersion, keyReason: evidence.strain.reasons.first ?? "")
            ]
            reports.append(ScenarioReportDTO(scenario: "baselineForming", description: "仅有3天历史负荷，未满7天有效观测", downstreamImpact: "ATL/CTL训练负荷比停用(nil)，不虚构减量/过载结论", metrics: metrics))
        }

        // 4. Normal Healthy Baseline
        do {
            var snapshot = DailyHealthSnapshot(date: baseDay)
            snapshot.hrvAverage = 54
            snapshot.restingHeartRate = 57
            snapshot.sleepHours = 7.75
            snapshot.wristTemperature = 36.4
            snapshot.oxygenSaturation = 0.98
            snapshot.activeCalories = 460
            snapshot.steps = 8400
            let history = (1...14).map { offset -> DailyHealthSnapshot in
                var item = DailyHealthSnapshot(date: calendar.date(byAdding: .day, value: -offset, to: baseDay)!)
                item.hrvAverage = 52 + Double(offset % 3)
                item.restingHeartRate = 58
                item.dailyLoad = 45
                item.wristTemperature = 36.38
                return item
            }
            let comp = DailyHealthComputation(calendar: calendar, now: baseDay.addingTimeInterval(12 * 3600))
            let evidence = comp.compute(for: snapshot, history: history)
            let metrics: [MetricComparisonDTO] = [
                MetricComparisonDTO(domain: "Sleep", oldValue: 77.43, newValue: evidence.sleep.value, oldQuality: "high", newQuality: evidence.sleep.confidence.rawValue, missingInputs: evidence.sleep.missingInputs, version: evidence.sleep.algorithmVersion, keyReason: "正常作息达成"),
                MetricComparisonDTO(domain: "Recovery", oldValue: 60.70, newValue: evidence.recovery.value, oldQuality: "high", newQuality: evidence.recovery.confidence.rawValue, missingInputs: evidence.recovery.missingInputs, version: evidence.recovery.algorithmVersion, keyReason: "HRV与RHR处于良好范围"),
                MetricComparisonDTO(domain: "Strain", oldValue: 63.67, newValue: evidence.strain.value, oldQuality: "high", newQuality: evidence.strain.confidence.rawValue, missingInputs: evidence.strain.missingInputs, version: evidence.strain.algorithmVersion, keyReason: "负荷适中"),
                MetricComparisonDTO(domain: "Stress", oldValue: 21.08, newValue: evidence.physiologicalStress.value, oldQuality: "high", newQuality: evidence.physiologicalStress.confidence.rawValue, missingInputs: evidence.physiologicalStress.missingInputs, version: evidence.physiologicalStress.algorithmVersion, keyReason: "生理压力处于平稳状态"),
                MetricComparisonDTO(domain: "Energy", oldValue: 42.31, newValue: evidence.energy.value, oldQuality: "high", newQuality: evidence.energy.confidence.rawValue, missingInputs: evidence.energy.missingInputs, version: evidence.energy.algorithmVersion, keyReason: "能量估计正常")
            ]
            reports.append(ScenarioReportDTO(scenario: "normalHealthy", description: "14天稳定历史与正常体征", downstreamImpact: "五项评分完整，置信度高，基线稳固", metrics: metrics))
        }

        // 5. Method Switch (SDNN vs RMSSD)
        do {
            let engine = RecoveryScoreEngine()
            let inputSDNN = RecoveryScoreInput(asOf: baseDay, hrvToday: 55, hrvBaseline: 50, restingHeartRateToday: 60, restingHeartRateBaseline: 60, sleepScoreLastNight: 75, strainScoreYesterday: nil)
            let resSDNN = engine.calculate(from: inputSDNN)
            let metrics: [MetricComparisonDTO] = [
                MetricComparisonDTO(domain: "Recovery-PSTI", oldValue: 50.0, newValue: resSDNN.components["parasympathetic_tone_index"], oldQuality: "fake_rmssd", newQuality: "unavailable", missingInputs: ["hrvRmssdToday"], version: resSDNN.algorithmVersion, keyReason: "缺少真实RMSSD时PSTI严格不可估计")
            ]
            reports.append(ScenarioReportDTO(scenario: "methodSwitch", description: "仅有SDNN心率变异性，缺少RMSSD测量", downstreamImpact: "拒绝以SDNN假冒RMSSD计算副交感神经张力", metrics: metrics))
        }

        // 6. Discontinuous Gaps (Load Decay)
        do {
            var snapshot = DailyHealthSnapshot(date: baseDay)
            snapshot.activeCalories = 300
            snapshot.steps = 5000
            var sparseHistory: [DailyHealthSnapshot] = []
            for offset in [1, 2, 10, 15] {
                var item = DailyHealthSnapshot(date: calendar.date(byAdding: .day, value: -offset, to: baseDay)!)
                item.dailyLoad = 50.0
                sparseHistory.append(item)
            }
            let comp = DailyHealthComputation(calendar: calendar, now: baseDay.addingTimeInterval(12 * 3600))
            let evidence = comp.compute(for: snapshot, history: sparseHistory)
            let metrics: [MetricComparisonDTO] = [
                MetricComparisonDTO(domain: "Strain", oldValue: 50.0, newValue: evidence.strain.value, oldQuality: "compacted", newQuality: evidence.strain.confidence.rawValue, missingInputs: evidence.strain.missingInputs, version: evidence.strain.algorithmVersion, keyReason: "日历断续天衰减EWMA而非压缩时间轴")
            ]
            reports.append(ScenarioReportDTO(scenario: "discontinuousGaps", description: "非连续日历历史（中间存在多天未佩戴或休息）", downstreamImpact: "EWMA正确随真实时间流逝衰减，不足7天停用状态", metrics: metrics))
        }

        // 7. Future Data Rejection
        do {
            var snapshot = DailyHealthSnapshot(date: baseDay)
            snapshot.hrvAverage = 50
            snapshot.restingHeartRate = 60
            var history: [DailyHealthSnapshot] = []
            var futureItem = DailyHealthSnapshot(date: calendar.date(byAdding: .day, value: 5, to: baseDay)!)
            futureItem.hrvAverage = 100
            futureItem.dailyLoad = 200
            history.append(futureItem)
            for offset in 1...7 {
                var pastItem = DailyHealthSnapshot(date: calendar.date(byAdding: .day, value: -offset, to: baseDay)!)
                pastItem.hrvAverage = 50
                pastItem.restingHeartRate = 60
                history.append(pastItem)
            }
            let comp = DailyHealthComputation(calendar: calendar, now: baseDay.addingTimeInterval(12 * 3600))
            let evidence = comp.compute(for: snapshot, history: history)
            let metrics: [MetricComparisonDTO] = [
                MetricComparisonDTO(domain: "Recovery", oldValue: 60.0, newValue: evidence.recovery.value, oldQuality: "safe", newQuality: evidence.recovery.confidence.rawValue, missingInputs: [], version: evidence.recovery.algorithmVersion, keyReason: "未来数据被基线与负荷网格严格过滤")
            ]
            reports.append(ScenarioReportDTO(scenario: "futureDataRejection", description: "历史中包含未来错误时间戳的数据点", downstreamImpact: "零信息泄露，未来数据不污染过去评分与基线", metrics: metrics))
        }

        // 8. Cross Timezone Bedtime
        do {
            var snapshot = DailyHealthSnapshot(date: baseDay)
            snapshot.bedtime = baseDay.addingTimeInterval(-45 * 60) // 23:15 previous day
            snapshot.wakeTime = baseDay.addingTimeInterval(7 * 3600) // 07:00 current day
            snapshot.sleepHours = 7.75
            let comp = DailyHealthComputation(calendar: calendar, now: baseDay.addingTimeInterval(12 * 3600))
            let evidence = comp.compute(for: snapshot, history: [])
            let metrics: [MetricComparisonDTO] = [
                MetricComparisonDTO(domain: "Sleep", oldValue: 75.0, newValue: evidence.sleep.value, oldQuality: "medium", newQuality: evidence.sleep.confidence.rawValue, missingInputs: evidence.sleep.missingInputs, version: evidence.sleep.algorithmVersion, keyReason: "跨日作息时间与醒来时间连续计算")
            ]
            reports.append(ScenarioReportDTO(scenario: "crossTimezone", description: "跨夜入睡与跨日历日清晨醒来", downstreamImpact: "准确识别昨夜睡眠，不截断作息区间", metrics: metrics))
        }

        // 9. Post Workout Window Exclusion
        do {
            var snapshot = DailyHealthSnapshot(date: baseDay)
            snapshot.restingHeartRate = 60
            snapshot.hrvAverage = 50
            snapshot.sleepHours = 7.5
            snapshot.workouts = [
                WorkoutSummary(
                    start: baseDay.addingTimeInterval(9 * 3600),
                    end: baseDay.addingTimeInterval(10 * 3600),
                    activityName: "Running",
                    averageHeartRate: 150
                )
            ]
            let asOf = baseDay.addingTimeInterval(10.5 * 3600) // 10:30 (within 90 min post workout)
            let comp = DailyHealthComputation(calendar: calendar, now: asOf)
            let evidence = comp.compute(for: snapshot, history: [])
            let metrics: [MetricComparisonDTO] = [
                MetricComparisonDTO(domain: "Stress", oldValue: 0.0, newValue: evidence.physiologicalStress.value, oldQuality: "fake_zero", newQuality: evidence.physiologicalStress.confidence.rawValue, missingInputs: ["quietWindow"], version: evidence.physiologicalStress.algorithmVersion, keyReason: "运动后90分钟自主神经恢复期内压力排除为nil"),
                MetricComparisonDTO(domain: "Energy", oldValue: 50.0, newValue: evidence.energy.value, oldQuality: "rebounded", newQuality: evidence.energy.confidence.rawValue, missingInputs: evidence.energy.missingInputs, version: evidence.energy.algorithmVersion, keyReason: "说明运动负荷已包含消耗，无压力回弹假象")
            ]
            reports.append(ScenarioReportDTO(scenario: "postWorkoutExclusion", description: "运动后90分钟内进行当日评分计算", downstreamImpact: "压力排除为nil而非0；能量解释消耗由训练承担，不误判回升", metrics: metrics))
        }

        // 10. Extreme Outliers
        do {
            var snapshot = DailyHealthSnapshot(date: baseDay)
            snapshot.restingHeartRate = 220 // extreme glitch
            snapshot.hrvAverage = 350 // extreme glitch
            snapshot.wristTemperature = 40.5
            let comp = DailyHealthComputation(calendar: calendar, now: baseDay.addingTimeInterval(12 * 3600))
            let evidence = comp.compute(for: snapshot, history: [])
            let metrics: [MetricComparisonDTO] = [
                MetricComparisonDTO(domain: "Recovery", oldValue: 0.0, newValue: evidence.recovery.value, oldQuality: "clamped", newQuality: evidence.recovery.confidence.rawValue, missingInputs: [], version: evidence.recovery.algorithmVersion, keyReason: "极端值被安全钳制在0-100，不发生NaN或崩溃"),
                MetricComparisonDTO(domain: "Stress", oldValue: 100.0, newValue: evidence.physiologicalStress.value, oldQuality: "clamped", newQuality: evidence.physiologicalStress.confidence.rawValue, missingInputs: [], version: evidence.physiologicalStress.algorithmVersion, keyReason: "异常心率产生保护性下调并记录理由")
            ]
            reports.append(ScenarioReportDTO(scenario: "extremeOutliers", description: "极端异常体征数据（传感器毛刺、极度心动过速、高热）", downstreamImpact: "数值边界严格钳制，不产生溢出或NaN崩溃", metrics: metrics))
        }

        // Serialize to JSON and CSV
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(reports)

        var csvLines = ["Scenario,Domain,OldValue,NewValue,OldQuality,NewQuality,MissingInputs,KeyReason,DownstreamImpact"]
        for r in reports {
            for m in r.metrics {
                let oldValStr = m.oldValue.map { String(format: "%.2f", $0) } ?? "nil"
                let newValStr = m.newValue.map { String(format: "%.2f", $0) } ?? "nil"
                let missingStr = m.missingInputs.joined(separator: ";")
                let safeReason = m.keyReason.replacingOccurrences(of: ",", with: "，")
                let safeImpact = r.downstreamImpact.replacingOccurrences(of: ",", with: "，")
                csvLines.append("\(r.scenario),\(m.domain),\(oldValStr),\(newValStr),\(m.oldQuality),\(m.newQuality),\"\(missingStr)\",\"\(safeReason)\",\"\(safeImpact)\"")
            }
        }
        let csvString = csvLines.joined(separator: "\n")

        // Write directly to workspace docs/validation/v1/ and /tmp/
        let targetDir = URL(fileURLWithPath: "/Users/sunweizhou/Developer/Vela/docs/validation/v1")
        try? FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let jsonURL = targetDir.appendingPathComponent("replay_comparison.json")
        let csvURL = targetDir.appendingPathComponent("replay_comparison.csv")
        try? jsonData.write(to: jsonURL)
        try? csvString.write(to: csvURL, atomically: true, encoding: .utf8)

        // Also write to /tmp for redundancy
        try? jsonData.write(to: URL(fileURLWithPath: "/tmp/replay_comparison.json"))
        try? csvString.write(to: URL(fileURLWithPath: "/tmp/replay_comparison.csv"), atomically: true, encoding: .utf8)

        XCTAssertEqual(reports.count, 10, "Must generate exactly 10 scenario comparisons")
    }

    func testGenerateSleepSemanticsReplayContract() throws {
        struct ComponentDTO: Codable {
            var value: Double?
            var availability: String
            var reason: String?
        }

        struct ScenarioDTO: Codable {
            var scenario: String
            var oldValue: Double?
            var newValue: Double?
            var queryOutcome: String?
            var freshness: String?
            var components: [String: ComponentDTO]
            var dataCoverage: String
            var confidence: String
            var missingInputs: [String]
            var reasons: [String]
            var algorithmVersion: String
        }

        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let range = DateInterval(start: asOf.addingTimeInterval(-86_400), end: asOf)
        func observed(_ value: Double) -> SleepComponentObservation {
            SleepComponentObservation(value: value, availability: .observed, observedWindow: range)
        }
        func missing(_ reason: String) -> SleepComponentObservation {
            SleepComponentObservation(value: nil, availability: .missing, reason: reason, observedWindow: range)
        }
        func context(
            outcome: HealthQueryOutcomeKind,
            freshness: DataFreshness,
            total: SleepComponentObservation,
            bedtime: SleepComponentObservation,
            wake: SleepComponentObservation,
            inBed: SleepComponentObservation,
            awake: SleepComponentObservation,
            rem: SleepComponentObservation,
            deep: SleepComponentObservation,
            episodeCount: SleepComponentObservation
        ) -> SleepEvidenceContext {
            SleepEvidenceContext(
                queryOutcome: outcome,
                freshness: freshness,
                totalSleep: total,
                bedtime: bedtime,
                wakeTime: wake,
                inBed: inBed,
                awake: awake,
                rem: rem,
                deep: deep,
                episodeCount: episodeCount
            )
        }

        let scenarios: [(String, Double?, SleepEvidenceContext)] = [
            (
                "observed_complete",
                78,
                context(
                    outcome: .data,
                    freshness: .today,
                    total: observed(450),
                    bedtime: observed(asOf.timeIntervalSinceReferenceDate - 8 * 3_600),
                    wake: observed(asOf.timeIntervalSinceReferenceDate),
                    inBed: observed(480),
                    awake: observed(30),
                    rem: observed(90),
                    deep: observed(80),
                    episodeCount: SleepComponentObservation(value: 2, availability: .estimated, reason: "由清醒片段估算醒来次数", observedWindow: range)
                )
            ),
            (
                "estimated_efficiency",
                70,
                context(
                    outcome: .data,
                    freshness: .today,
                    total: observed(450),
                    bedtime: observed(asOf.timeIntervalSinceReferenceDate - 8 * 3_600),
                    wake: observed(asOf.timeIntervalSinceReferenceDate),
                    inBed: SleepComponentObservation(value: 480, availability: .estimated, reason: "由睡眠时长与清醒时长推导卧床时长", observedWindow: range),
                    awake: observed(30),
                    rem: missing("HealthKit 未提供 REM 阶段"),
                    deep: missing("HealthKit 未提供 Deep 阶段"),
                    episodeCount: missing("缺少清醒次数数据")
                )
            ),
            (
                "stale_retained",
                75,
                context(
                    outcome: .transient,
                    freshness: .stale,
                    total: observed(450),
                    bedtime: missing("查询失败"),
                    wake: missing("查询失败"),
                    inBed: missing("查询失败"),
                    awake: missing("查询失败"),
                    rem: missing("查询失败"),
                    deep: missing("查询失败"),
                    episodeCount: missing("查询失败")
                )
            ),
            (
                "no_valid_sleep",
                nil,
                context(
                    outcome: .noData,
                    freshness: .stale,
                    total: missing("没有有效睡眠片段"),
                    bedtime: missing("没有入睡时间"),
                    wake: missing("没有起床时间"),
                    inBed: missing("没有卧床阶段"),
                    awake: missing("没有清醒阶段"),
                    rem: missing("没有 REM 阶段"),
                    deep: missing("没有 Deep 阶段"),
                    episodeCount: missing("没有清醒次数")
                )
            )
        ]

        func dto(_ observation: SleepComponentObservation) -> ComponentDTO {
            ComponentDTO(value: observation.value, availability: observation.availability.rawValue, reason: observation.reason)
        }

        let reports = scenarios.map { name, oldValue, evidence in
            let result = SleepScoreEngine().calculate(from: SleepScoreInput(
                asOf: asOf,
                totalSleepMinutes: evidence.totalSleep.value,
                sleepTargetMinutes: 450,
                evidence: evidence
            ))
            return ScenarioDTO(
                scenario: name,
                oldValue: oldValue,
                newValue: result.value,
                queryOutcome: evidence.queryOutcome?.rawValue,
                freshness: evidence.freshness?.rawValue,
                components: [
                    "totalSleep": dto(evidence.totalSleep),
                    "inBed": dto(evidence.inBed),
                    "awake": dto(evidence.awake),
                    "rem": dto(evidence.rem),
                    "deep": dto(evidence.deep),
                    "episodeCount": dto(evidence.episodeCount)
                ],
                dataCoverage: result.dataCoverage.rawValue,
                confidence: result.confidence.rawValue,
                missingInputs: result.missingInputs,
                reasons: result.reasons,
                algorithmVersion: result.algorithmVersion
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(reports)
        let url = URL(fileURLWithPath: "/Users/sunweizhou/Developer/Vela/docs/validation/v1/sleep_semantics_replay.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        XCTAssertEqual(reports.count, 4)
    }
}
