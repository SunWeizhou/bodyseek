import XCTest
@testable import Vela

final class HealthTrendAndBriefTests: XCTestCase {

    func testHealthTrendEngineWithEmptyDashboardReturnsEmptyBrief() {
        let date = Date()
        let emptyDashboard = DashboardSummary.empty(date: date)
        let engine = HealthTrendEngine()
        let result = engine.analyze(
            dashboard: emptyDashboard,
            snapshots: [],
            longTermBaselines: nil,
            today: date
        )

        XCTAssertEqual(result.brief.overallState, .insufficientData)
        XCTAssertEqual(result.brief.headline, "正在建立个人健康基线")
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertTrue(result.brief.notableChanges.isEmpty)
    }

    func testHealthTrendEngineSynthesizesNotableChangesAndBrief() {
        let calendar = Calendar.current
        let today = Date()

        var snapshots: [DailyHealthSnapshot] = []
        for i in (0..<30).reversed() {
            let d = calendar.date(byAdding: .day, value: -i, to: today)!
            var s = DailyHealthSnapshot(date: d)
            s.hrvAverage = i < 7 ? 40.0 : 65.0 // HRV dropped in the last 7 days
            s.restingHeartRate = i < 7 ? 62.0 : 54.0 // RHR elevated
            s.sleepHours = 7.5
            s.recoveryScore = i < 7 ? 35.0 : 75.0
            s.strainScore = 45.0
            s.stressIndex = 45.0
            snapshots.append(s)
        }

        var dashboard = DashboardSummary.empty(date: today)
        dashboard.recovery = MetricResult(
            domain: .recovery, name: "Recovery", value: 35.0, band: .low, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )
        dashboard.recoveryMetrics = RecoveryMetricSummary(
            hrvMilliseconds: 40.0,
            restingHeartRate: 62.0,
            sleepHeartRate: nil,
            respiratoryRate: 14.5
        )
        dashboard.sleepScore = MetricResult(
            domain: .sleep, name: "Sleep", value: 75.0, band: .normal, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )

        let engine = HealthTrendEngine()
        let result = engine.analyze(
            dashboard: dashboard,
            snapshots: snapshots,
            longTermBaselines: nil,
            today: today,
            calendar: calendar
        )

        XCTAssertFalse(result.findings.isEmpty)
        XCTAssertNotEqual(result.brief.overallState, .insufficientData)
        XCTAssertFalse(result.brief.subheadline.isEmpty)

        // Verify notable findings exist for HRV, RHR or Recovery
        let notableMetrics = Set(result.brief.notableChanges.map(\.metric))
        XCTAssertTrue(notableMetrics.contains(.hrv) || notableMetrics.contains(.restingHeartRate) || notableMetrics.contains(.recovery))
        XCTAssertEqual(
            result.brief.notableChanges.map(\.metric).count,
            notableMetrics.count,
            "Personal Health Brief must expose at most one notable finding per metric"
        )
    }

    func testSixMonthTrendCalculationAndNoSilentHorizonFallback() {
        let calendar = Calendar.current
        let today = Date()

        // 1. Only 30 snapshots available: 30d should be available, but 6m (< 60 samples) must be unavailable
        var snapshots30: [DailyHealthSnapshot] = []
        for i in (0..<30).reversed() {
            let d = calendar.date(byAdding: .day, value: -i, to: today)!
            var s = DailyHealthSnapshot(date: d)
            s.hrvAverage = 60.0
            s.restingHeartRate = 55.0
            s.sleepHours = 7.5
            s.recoveryScore = 70.0
            snapshots30.append(s)
        }

        var dashboard = DashboardSummary.empty(date: today)
        dashboard.recovery = MetricResult(
            domain: .recovery, name: "Recovery", value: 70.0, band: .normal, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )
        dashboard.recoveryMetrics = RecoveryMetricSummary(
            hrvMilliseconds: 60.0,
            restingHeartRate: 55.0,
            sleepHeartRate: nil,
            respiratoryRate: 14.0
        )

        let engine = HealthTrendEngine()
        let result30 = engine.analyze(
            dashboard: dashboard,
            snapshots: snapshots30,
            longTermBaselines: nil,
            today: today,
            calendar: calendar
        )

        let finding30d = result30.findings.first { $0.metric == .hrv && $0.horizon == .thirtyDays }
        let finding6m = result30.findings.first { $0.metric == .hrv && $0.horizon == .sixMonths }

        XCTAssertNotNil(finding30d)
        XCTAssertTrue(finding30d?.isAvailable == true)

        // 6-month finding must NOT be silently substituted by 30-day data; it must be marked unavailable
        XCTAssertNotNil(finding6m)
        XCTAssertFalse(finding6m?.isAvailable == true)
        XCTAssertEqual(finding6m?.direction, .insufficientData)
        XCTAssertEqual(finding6m?.currentValueFormatted, "--")

        // 2. Now provide 180 snapshots: 6m should become available and calculate true trend
        var snapshots180: [DailyHealthSnapshot] = []
        for i in (0..<180).reversed() {
            let d = calendar.date(byAdding: .day, value: -i, to: today)!
            var s = DailyHealthSnapshot(date: d)
            s.hrvAverage = i < 60 ? 70.0 : 55.0 // Gradual multi-month improvement
            s.restingHeartRate = 54.0
            s.sleepHours = 7.5
            s.recoveryScore = 75.0
            snapshots180.append(s)
        }

        let result180 = engine.analyze(
            dashboard: dashboard,
            snapshots: snapshots180,
            longTermBaselines: nil,
            today: today,
            calendar: calendar
        )

        let finding6mActive = result180.findings.first { $0.metric == .hrv && $0.horizon == .sixMonths }
        XCTAssertNotNil(finding6mActive)
        XCTAssertTrue(finding6mActive?.isAvailable == true)
        XCTAssertEqual(finding6mActive?.direction, .improving)
    }

    func testMissingRecoveryDataDoesNotEvaluateToZeroOrRecovering() {
        let today = Date()
        var dashboard = DashboardSummary.empty(date: today)
        // Recovery is nil/missing
        dashboard.recovery.value = nil
        dashboard.recovery.confidence = .low
        // Sleep is healthy (8.0 hours / score 85)
        dashboard.sleepScore = MetricResult(
            domain: .sleep, name: "Sleep", value: 85.0, band: .high, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )
        dashboard.sleepSummary = SleepSummary(
            date: today,
            totalSleepMinutes: 480,
            bedtime: today.addingTimeInterval(-28800),
            wakeTime: today,
            stageMinutes: [.deep: 90, .rem: 100, .awake: 30],
            segments: [],
            sleepScore: 85.0
        )

        let engine = HealthTrendEngine()
        let result = engine.analyze(
            dashboard: dashboard,
            snapshots: [],
            longTermBaselines: nil,
            today: today
        )

        // Must NOT assume recovery = 0 and jump to .recovering!
        XCTAssertNotEqual(result.brief.overallState, .recovering, "Missing recovery must not be coerced to 0 score")
    }

    func testStrainScaleAndThresholdIsCalibratedTo0To100() {
        let today = Date()
        var dashboard = DashboardSummary.empty(date: today)
        dashboard.recovery = MetricResult(
            domain: .recovery, name: "Recovery", value: 75.0, band: .high, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )
        // Strain of 45.0 in a 0-100 scale is a normal moderate workout day
        dashboard.strain = MetricResult(
            domain: .strain, name: "Strain", value: 45.0, band: .normal, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )

        let engine = HealthTrendEngine()
        let result = engine.analyze(
            dashboard: dashboard,
            snapshots: [],
            longTermBaselines: nil,
            today: today
        )

        // Must NOT be strained simply because 45.0 >= 14!
        XCTAssertNotEqual(result.brief.overallState, .strained, "Strain of 45/100 is normal moderate load, not strained")
    }

    func testHighStrainIsNotHiddenByOptimalRecovery() {
        let today = Date()
        var dashboard = DashboardSummary.empty(date: today)
        dashboard.recovery = MetricResult(
            domain: .recovery, name: "Recovery", value: 80.0, band: .high, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )
        dashboard.strain = MetricResult(
            domain: .strain, name: "Strain", value: 85.0, band: .high, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )

        let result = HealthTrendEngine().analyze(
            dashboard: dashboard,
            snapshots: [],
            longTermBaselines: nil,
            today: today
        )

        XCTAssertEqual(result.brief.overallState, .strained)
    }

    func testThreeYearFindingPublishesValueDirectionAndAssessment() {
        let today = Date()
        var dashboard = DashboardSummary.empty(date: today)
        dashboard.recovery = MetricResult(
            domain: .recovery, name: "Recovery", value: 70.0, band: .normal, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )
        dashboard.recoveryMetrics.hrvMilliseconds = 40.0

        let hrvBaseline = LongTermMetricBaseline(
            metric: .hrv,
            sampleCount: 90,
            threeYearMedian: 60.0,
            percentile10: 45.0,
            percentile25: 52.0,
            percentile75: 68.0,
            percentile90: 75.0,
            recent30DayMean: 40.0,
            longTermDeviationPercent: -33.3,
            yearOverYearDelta: nil,
            trendLabel: "worsening"
        )
        let report = LongTermBaselineReport(
            calculatedAt: today,
            daysOfData: 90,
            earliestDate: today.addingTimeInterval(-90 * 86400),
            latestDate: today,
            baselines: [.hrv: hrvBaseline]
        )

        let result = HealthTrendEngine().analyze(
            dashboard: dashboard,
            snapshots: [],
            longTermBaselines: report,
            today: today
        )
        let finding = result.findings.first { $0.metric == .hrv && $0.horizon == .threeYears }

        XCTAssertEqual(finding?.direction, .declining)
        XCTAssertEqual(finding?.valueDirection, .falling)
        XCTAssertEqual(finding?.assessment, .unfavorable)
    }

    func testSleepScoreTrendIsIndependentFromSleepDuration() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        var snapshots: [DailyHealthSnapshot] = []

        for day in 0..<30 {
            let date = calendar.date(byAdding: .day, value: day - 29, to: today)!
            var snapshot = DailyHealthSnapshot(date: date)
            snapshot.sleepHours = 8
            snapshot.sleepScore = day < 15 ? 86 : 62
            snapshot.recoveryScore = 70
            snapshots.append(snapshot)
        }

        var dashboard = DashboardSummary.empty(date: today)
        dashboard.recovery = MetricResult(
            domain: .recovery, name: "Recovery", value: 70, band: .normal, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86_400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )
        dashboard.sleepScore = MetricResult(
            domain: .sleep, name: "Sleep", value: 62, band: .low, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86_400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )
        dashboard.sleepSummary.totalSleepMinutes = 480

        let result = HealthTrendEngine().analyze(
            dashboard: dashboard,
            snapshots: snapshots,
            longTermBaselines: nil,
            today: today,
            calendar: calendar
        )
        let findings = result.findings

        let score = findings.first { $0.metric == .sleepScore && $0.horizon == .thirtyDays }
        let duration = findings.first { $0.metric == .sleepDuration && $0.horizon == .thirtyDays }
        XCTAssertEqual(score?.currentValue, 62)
        XCTAssertEqual(score?.valueDirection, .falling)
        XCTAssertEqual(score?.assessment, .unfavorable)
        XCTAssertEqual(duration?.valueDirection, .stable)

        XCTAssertEqual(CoreHealthMetric.sleepScore.todayScoreRingID, "sleep")
        XCTAssertNil(CoreHealthMetric.sleepDuration.todayScoreRingID)
        XCTAssertEqual(CoreHealthMetric.sleepDuration.shortTitle, "睡眠时长")
        XCTAssertEqual(CoreHealthMetric.sleepScore.shortTitle, "睡眠")
        XCTAssertEqual(score?.currentValueFormatted, "62")
        XCTAssertFalse(result.brief.subheadline.contains("%"))
        XCTAssertFalse(result.brief.subheadline.contains("各项核心体征处于基线良好"))
        XCTAssertTrue(result.brief.subheadline.contains("恢复 70"))
        XCTAssertTrue(result.brief.subheadline.contains("睡眠得分"))
        XCTAssertFalse(result.brief.subheadline.contains("睡眠时长"))
    }

    func testHighRecoveryGuidanceDoesNotDeclareEverySignalGood() {
        let today = Date()
        var dashboard = DashboardSummary.empty(date: today)
        dashboard.recovery = MetricResult(
            domain: .recovery, name: "Recovery", value: 82, band: .high, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86_400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )

        let brief = HealthTrendEngine().analyze(
            dashboard: dashboard,
            snapshots: [],
            longTermBaselines: nil,
            today: today
        ).brief

        XCTAssertEqual(brief.subheadline, "恢复 82。")
    }

    func testThreeYearDerivedScoreUsesPersistedDailySeries() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        var snapshots: [DailyHealthSnapshot] = []

        for day in 0..<400 {
            let date = calendar.date(byAdding: .day, value: day - 399, to: today)!
            var snapshot = DailyHealthSnapshot(date: date)
            snapshot.recoveryScore = day < 200 ? 82 : 61
            snapshots.append(snapshot)
        }

        var dashboard = DashboardSummary.empty(date: today)
        dashboard.recovery = MetricResult(
            domain: .recovery, name: "Recovery", value: 61, band: .normal, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86_400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )

        let finding = HealthTrendEngine().analyze(
            dashboard: dashboard,
            snapshots: snapshots,
            longTermBaselines: nil,
            today: today,
            calendar: calendar
        ).findings.first { $0.metric == .recovery && $0.horizon == .threeYears }

        XCTAssertTrue(finding?.isAvailable == true)
        XCTAssertEqual(finding?.valueDirection, .falling)
        XCTAssertEqual(finding?.assessment, .unfavorable)
        XCTAssertEqual(finding?.sampleCount, 400)
    }

    func testHistoryProviderInputPublishesThreeYearSeriesWithoutPersistenceCoupling() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        var snapshots: [DailyHealthSnapshot] = []

        // A provider can supply a full long window even when the daily brief
        // adapter normally keeps a shorter recent window in memory.
        for day in 0..<400 {
            let date = calendar.date(byAdding: .day, value: day - 399, to: today)!
            var snapshot = DailyHealthSnapshot(date: date)
            snapshot.recoveryScore = day < 200 ? 82 : 61
            snapshots.append(snapshot)
        }

        let dashboard = recoveryDashboard(value: 61, date: today)
        let input = HealthTrendInput(snapshots: snapshots)
        let provider = StaticHealthTrendHistoryProvider(input: input)
        let engine = HealthTrendEngine()

        let fromProvider = engine.analyze(
            dashboard: dashboard,
            historyProvider: provider,
            selectedDay: today,
            calendar: calendar
        )
        let direct = engine.analyze(
            dashboard: dashboard,
            input: input,
            selectedDay: today,
            calendar: calendar
        )

        let providerFinding = fromProvider.findings.first {
            $0.metric == .recovery && $0.horizon == .threeYears
        }
        XCTAssertTrue(providerFinding?.isAvailable == true)
        XCTAssertEqual(providerFinding?.sampleCount, 400)
        XCTAssertEqual(providerFinding?.valueDirection, .falling)
        XCTAssertEqual(fromProvider.findings, direct.findings)
        XCTAssertEqual(fromProvider.brief, direct.brief)
    }

    func testDailySummaryTrendProviderBoundsHistoryAndPreservesMissingValues() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let selectedDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

        var old = DailyHealthSnapshot(
            date: calendar.date(byAdding: .day, value: -HealthTrendHorizon.threeYears.windowDays - 1, to: selectedDay)!
        )
        old.recoveryScore = 99
        var edge = DailyHealthSnapshot(
            date: calendar.date(byAdding: .day, value: -HealthTrendHorizon.threeYears.windowDays, to: selectedDay)!
        )
        edge.recoveryScore = nil
        var current = DailyHealthSnapshot(date: selectedDay)
        current.recoveryScore = 60
        var future = DailyHealthSnapshot(
            date: calendar.date(byAdding: .day, value: 1, to: selectedDay)!
        )
        future.recoveryScore = 1

        let provider = DailySummaryHealthTrendHistoryProvider(
            snapshots: [old, edge, current, future],
            longTermBaselines: nil
        )
        let input = provider.history(endingAt: selectedDay, calendar: calendar)

        XCTAssertEqual(input.snapshots.map(\.date), [edge.date, current.date])
        XCTAssertNil(input.snapshots.first?.recoveryScore)
        XCTAssertNil(input.longTermBaselines)
    }

    func testDailyIntelligenceUsesThreeYearProviderWithoutWideningRecentEvidence() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let selectedDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        var longHistory: [DailyHealthSnapshot] = []
        for index in 0..<400 {
            let date = calendar.date(byAdding: .day, value: index - 399, to: selectedDay)!
            var snapshot = DailyHealthSnapshot(date: date)
            snapshot.recoveryScore = index < 200 ? 82 : 61
            longHistory.append(snapshot)
        }

        let dashboard = recoveryDashboard(value: 61, date: selectedDay)
        let assembly = DailyIntelligenceAssemblyModule.assemble(
            DailyIntelligenceAssemblyInput(
                dashboard: dashboard,
                selectedDay: selectedDay,
                calendar: calendar,
                trendHistoryProvider: DailySummaryHealthTrendHistoryProvider(snapshots: longHistory),
                // The recent scoring evidence is intentionally narrow. The
                // 3y provider above is the only source for trend findings.
                snapshots: [longHistory.last!]
            )
        )

        let recoveryFinding = assembly.dashboard.healthTrends.first {
            $0.metric == .recovery && $0.horizon == .threeYears
        }
        XCTAssertEqual(recoveryFinding?.sampleCount, 400)
        XCTAssertTrue(recoveryFinding?.isAvailable == true)
    }

    func testSecondaryAssemblyPreservesUpstreamThreeYearBrief() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let selectedDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        var longHistory: [DailyHealthSnapshot] = []
        for index in 0..<400 {
            let date = calendar.date(byAdding: .day, value: index - 399, to: selectedDay)!
            var snapshot = DailyHealthSnapshot(date: date)
            snapshot.recoveryScore = index < 200 ? 82 : 61
            longHistory.append(snapshot)
        }

        let source = DailyIntelligenceAssemblyModule.assemble(
            DailyIntelligenceAssemblyInput(
                dashboard: recoveryDashboard(value: 61, date: selectedDay),
                selectedDay: selectedDay,
                calendar: calendar,
                trendHistoryProvider: DailySummaryHealthTrendHistoryProvider(snapshots: longHistory),
                snapshots: [longHistory.last!]
            )
        )
        let preserved = DailyIntelligenceAssemblyModule.assemble(
            DailyIntelligenceAssemblyInput(
                dashboard: source.dashboard,
                selectedDay: selectedDay,
                calendar: calendar,
                // Simulate the secondary path, which only has a short recent
                // window and no persistence-backed trend provider.
                snapshots: [longHistory.last!]
            )
        )

        XCTAssertEqual(preserved.dashboard.personalHealthBrief, source.dashboard.personalHealthBrief)
        XCTAssertEqual(preserved.dashboard.healthTrends, source.dashboard.healthTrends)
    }

    func testThreeYearWindowExcludesOutOfWindowAndMissingSamples() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        var completeSnapshots: [DailyHealthSnapshot] = []

        // Exactly 60 valid samples spanning more than one year.
        for index in 0..<60 {
            let date = calendar.date(byAdding: .day, value: -600 + index * 10, to: today)!
            var snapshot = DailyHealthSnapshot(date: date)
            snapshot.recoveryScore = 70
            completeSnapshots.append(snapshot)
        }

        var old = DailyHealthSnapshot(date: calendar.date(byAdding: .day, value: -1_100, to: today)!)
        old.recoveryScore = 90
        var future = DailyHealthSnapshot(date: calendar.date(byAdding: .day, value: 1, to: today)!)
        future.recoveryScore = 90
        completeSnapshots += [old, future]

        let dashboard = recoveryDashboard(value: 70, date: today)
        let complete = HealthTrendEngine().analyze(
            dashboard: dashboard,
            input: HealthTrendInput(snapshots: completeSnapshots),
            selectedDay: today,
            calendar: calendar
        )
        let completeFinding = complete.findings.first {
            $0.metric == .recovery && $0.horizon == .threeYears
        }
        XCTAssertTrue(completeFinding?.isAvailable == true)
        XCTAssertEqual(completeFinding?.sampleCount, 60)

        // A missing value is not a zero: it reduces evidence and keeps the
        // three-year horizon explicitly unavailable below its sample gate.
        var missingSnapshots = completeSnapshots
        missingSnapshots[10].recoveryScore = nil
        let missing = HealthTrendEngine().analyze(
            dashboard: dashboard,
            input: HealthTrendInput(snapshots: missingSnapshots),
            selectedDay: today,
            calendar: calendar
        )
        let missingFinding = missing.findings.first {
            $0.metric == .recovery && $0.horizon == .threeYears
        }
        XCTAssertFalse(missingFinding?.isAvailable == true)
        XCTAssertEqual(missingFinding?.sampleCount, 59)
        XCTAssertEqual(missingFinding?.direction, .insufficientData)
    }

    func testHistoryInputResultsAreDeterministicAcrossFetchOrder() {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        var snapshots: [DailyHealthSnapshot] = []

        for day in 0..<30 {
            let date = calendar.date(byAdding: .day, value: day - 29, to: today)!
            var snapshot = DailyHealthSnapshot(date: date)
            snapshot.recoveryScore = day < 15 ? 80 : 50
            snapshots.append(snapshot)
        }

        let dashboard = recoveryDashboard(value: 50, date: today)
        let engine = HealthTrendEngine()
        let forward = engine.analyze(
            dashboard: dashboard,
            input: HealthTrendInput(snapshots: snapshots),
            selectedDay: today,
            calendar: calendar
        )
        let reversed = engine.analyze(
            dashboard: dashboard,
            input: HealthTrendInput(snapshots: Array(snapshots.reversed())),
            selectedDay: today,
            calendar: calendar
        )

        XCTAssertEqual(forward.findings, reversed.findings)
        XCTAssertEqual(forward.brief, reversed.brief)
    }

    func testMetricPolaritiesAreCorrectlyDefined() {
        XCTAssertEqual(CoreHealthMetric.bodyWeight.polarity, .contextual)
        XCTAssertEqual(CoreHealthMetric.bodyFat.polarity, .contextual)
        XCTAssertEqual(CoreHealthMetric.strain.polarity, .contextual)
        XCTAssertEqual(CoreHealthMetric.steps.polarity, .contextual)
        XCTAssertEqual(CoreHealthMetric.activeCalories.polarity, .contextual)
        XCTAssertEqual(CoreHealthMetric.respiratoryRate.polarity, .contextual)
        XCTAssertEqual(CoreHealthMetric.hrv.polarity, .higherIsBetter)
        XCTAssertEqual(CoreHealthMetric.recovery.polarity, .higherIsBetter)
        XCTAssertEqual(CoreHealthMetric.sleepDuration.polarity, .higherIsBetter)
        XCTAssertEqual(CoreHealthMetric.sleepScore.polarity, .higherIsBetter)
        XCTAssertEqual(CoreHealthMetric.restingHeartRate.polarity, .lowerIsBetter)
        XCTAssertEqual(CoreHealthMetric.stress.polarity, .lowerIsBetter)
    }

    func testStepsAndActiveCaloriesExtractionFromMetrics() {
        let today = Date()
        var dashboard = DashboardSummary.empty(date: today)
        dashboard.strain = MetricResult(
            domain: .strain, name: "Strain", value: 30.0, band: .normal, confidence: .high,
            components: ["steps_raw": 10450.0, "active_energy_raw": 580.0],
            componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )
        dashboard.recovery = MetricResult(
            domain: .recovery, name: "Recovery", value: 75.0, band: .normal, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )

        var snapshots: [DailyHealthSnapshot] = []
        for i in 0..<14 {
            var s = DailyHealthSnapshot(date: Calendar.current.date(byAdding: .day, value: -i, to: today)!)
            s.steps = 9500
            s.activeCalories = 520.0
            snapshots.append(s)
        }

        let engine = HealthTrendEngine()
        let result = engine.analyze(
            dashboard: dashboard,
            snapshots: snapshots,
            longTermBaselines: nil,
            today: today
        )

        let stepFinding = result.findings.first { $0.metric == .steps && $0.horizon == .sevenDays }
        XCTAssertNotNil(stepFinding)
        XCTAssertTrue(stepFinding?.isAvailable == true)
        XCTAssertEqual(stepFinding?.currentValue, 10450)

        let calorieFinding = result.findings.first { $0.metric == .activeCalories && $0.horizon == .sevenDays }
        XCTAssertNotNil(calorieFinding, "activeCalories finding must exist")
        XCTAssertTrue(calorieFinding?.isAvailable == true, "activeCalories finding must be available")
        XCTAssertEqual(calorieFinding?.currentValue, 580.0, "activeCalories should be 580.0 from active_energy_raw")
    }

    func testDecoupledValueDirectionAndAssessmentForRestingHeartRate() {
        let calendar = Calendar.current
        let today = Date()

        var snapshots: [DailyHealthSnapshot] = []
        for i in (0..<30).reversed() {
            let d = calendar.date(byAdding: .day, value: -i, to: today)!
            var s = DailyHealthSnapshot(date: d)
            // First half: 55 bpm, second half: 65 bpm (RHR value rises)
            s.restingHeartRate = (i > 15) ? 55.0 : 65.0
            snapshots.append(s)
        }

        var dashboard = DashboardSummary.empty(date: today)
        dashboard.recoveryMetrics.restingHeartRate = 65.0
        dashboard.recovery = MetricResult(
            domain: .recovery, name: "Recovery", value: 50.0, band: .normal, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )

        let engine = HealthTrendEngine()
        let result = engine.analyze(
            dashboard: dashboard,
            snapshots: snapshots,
            longTermBaselines: nil,
            today: today
        )

        let rhr30d = result.findings.first { $0.metric == .restingHeartRate && $0.horizon == .thirtyDays }
        XCTAssertNotNil(rhr30d)
        XCTAssertTrue(rhr30d?.isAvailable == true)
        // Numerical value went UP
        XCTAssertEqual(rhr30d?.valueDirection, .rising, "RHR value went up, so valueDirection must be rising")
        // Health assessment is unfavorable because lower is better for RHR
        XCTAssertEqual(rhr30d?.assessment, .unfavorable, "RHR rising is unfavorable for health")
    }

    func testSixMonthTrendRejectsClusteredSamplesWithInsufficientTimeSpan() {
        let calendar = Calendar.current
        let today = Date()

        var snapshots: [DailyHealthSnapshot] = []
        // 60 samples but all within the last 30 days (e.g. 2 samples per day or tight span)
        for i in 0..<60 {
            let d = calendar.date(byAdding: .day, value: -(i % 30), to: today)!
            var s = DailyHealthSnapshot(date: d)
            s.hrvAverage = 65.0
            snapshots.append(s)
        }

        var dashboard = DashboardSummary.empty(date: today)
        dashboard.recoveryMetrics.hrvMilliseconds = 65.0
        dashboard.recovery = MetricResult(
            domain: .recovery, name: "Recovery", value: 70.0, band: .normal, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )
        let engine = HealthTrendEngine()
        let result = engine.analyze(
            dashboard: dashboard,
            snapshots: snapshots,
            longTermBaselines: nil,
            today: today
        )

        let hrv6m = result.findings.first { $0.metric == .hrv && $0.horizon == .sixMonths }
        XCTAssertNotNil(hrv6m)
        XCTAssertFalse(hrv6m?.isAvailable == true, "6-month trend must reject samples with less than 90 days span")
    }

    func testEmptyDashboardProducesSafePendingDecisionInKernel() {
        let today = Date()
        let dashboard = DashboardSummary.empty(date: today)
        let bodyState = BodyStateKernel().build(input: BodyStateInput(dashboard: dashboard))

        let decision = TrainingDecisionKernel().decide(input: TrainingDecisionInput(
            bodyState: bodyState,
            personalHealthBrief: dashboard.personalHealthBrief
        ))

        // 契约（P0-A）：空数据必须落在保守窗口，而不是 keep@100% 或"等待同步"的含糊措辞。
        XCTAssertEqual(decision.decision, .reduce)
        XCTAssertEqual(decision.volumeMultiplier, 0.60)
        XCTAssertEqual(decision.intensityCap, 7)
        XCTAssertEqual(decision.confidence, 0.0)
        XCTAssertTrue(decision.userFacingSummary.contains("60%"), decision.userFacingSummary)
    }

    func testRobustHalfWindowMedianRejectsSingleDaySpike() {
        let calendar = Calendar.current
        let today = Date()

        var snapshots: [DailyHealthSnapshot] = []
        for i in (0..<30).reversed() {
            let d = calendar.date(byAdding: .day, value: -i, to: today)!
            var s = DailyHealthSnapshot(date: d)
            // 29 days of stable HRV 60ms, with 1 single anomalous spike to 140ms on day 20
            s.hrvAverage = (i == 10) ? 140.0 : 60.0
            snapshots.append(s)
        }

        var dashboard = DashboardSummary.empty(date: today)
        dashboard.recoveryMetrics.hrvMilliseconds = 60.0
        dashboard.recovery = MetricResult(
            domain: .recovery, name: "Recovery", value: 75.0, band: .normal, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: today, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: today
        )

        let engine = HealthTrendEngine()
        let result = engine.analyze(
            dashboard: dashboard,
            snapshots: snapshots,
            longTermBaselines: nil,
            today: today
        )

        let hrv30d = result.findings.first { $0.metric == .hrv && $0.horizon == .thirtyDays }
        XCTAssertNotNil(hrv30d)
        XCTAssertTrue(hrv30d?.isAvailable == true)
        // The median of both halves is 60.0, so the single day spike does NOT cause a false "improving" or "declining" trend!
        XCTAssertEqual(hrv30d?.direction, .stable, "Robust median trend must reject single-day spike")
    }

    func testTodayExperienceModelBuildsFromPersonalHealthBrief() {
        let date = Date()
        var dashboard = DashboardSummary.empty(date: date)
        dashboard.recovery = MetricResult(
            domain: .recovery, name: "Recovery", value: 80.0, band: .high, confidence: .high,
            components: [:], componentWeights: [:], reasons: [], missingInputs: [],
            dataWindow: DateInterval(start: date, duration: 86400), source: .healthKit,
            algorithmVersion: "1.0", lastUpdated: date
        )
        dashboard.recoveryMetrics = RecoveryMetricSummary(
            hrvMilliseconds: 70.0,
            restingHeartRate: 52.0,
            sleepHeartRate: nil,
            respiratoryRate: 13.5
        )

        let brief = PersonalHealthBrief(
            date: date,
            overallState: .optimal,
            headline: "身体机能处于良好水平",
            subheadline: "恢复 80。",
            notableChanges: [],
            stableSignals: [],
            confidence: .high,
            confidenceLabel: "数据充足",
            needsAction: false,
            suggestedActionCategory: .training,
            actionHeadline: "机能充沛",
            actionDetail: "体征处于基线良好区间，可按个人节奏正常开展日常工作与训练活动。",
            lifestyleSuggestions: []
        )
        dashboard.personalHealthBrief = brief

        let bodyState = BodyStateKernel().build(input: BodyStateInput(dashboard: dashboard))
        let decision = TrainingDecisionKernel().decide(input: TrainingDecisionInput(bodyState: bodyState))

        let experience = TodayExperienceModel.build(
            dashboard: dashboard,
            bodyState: bodyState,
            trainingDecision: decision
        )

        XCTAssertEqual(experience.hero.decisionTitle, "身体机能处于良好水平")
        XCTAssertEqual(experience.hero.summary, "恢复 80。")
    }

    // MARK: - WidgetKit Snapshot & Provider Tests (P3)

    func testVelaWidgetSnapshotCodableAndStaleness() throws {
        let now = Date()
        let snapshot = VelaWidgetSnapshot(
            generatedAt: now,
            bodyStateTitle: "身体处于充沛状态",
            summary: "恢复评分 88%，心率平稳",
            decision: "建议适度冲刺",
            decisionConfidence: 0.92,
            recoveryScore: 88,
            sleepScore: 84,
            strainScore: 42,
            stressScore: 18,
            energyScore: 90,
            hrvMilliseconds: 68,
            restingHeartRate: 54,
            primaryAction: "按原定计划进行专项训练",
            planTitle: "力量训练 A",
            sessionTitle: "深蹲与卧推",
            sessionDetail: "4组 8-10次",
            planProgress: "第 2/4 阶段"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(VelaWidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.recoveryScore, 88)
        XCTAssertEqual(decoded.decision, "建议适度冲刺")
        XCTAssertEqual(decoded.hrvMilliseconds, 68)
        XCTAssertFalse(decoded.isStale)

        let staleSnapshot = VelaWidgetSnapshot(
            generatedAt: Date().addingTimeInterval(-24 * 3600),
            bodyStateTitle: "旧体征",
            summary: "昨日的数据",
            decision: "注意休整",
            decisionConfidence: 0.8,
            recoveryScore: 45,
            primaryAction: "休息"
        )
        XCTAssertTrue(staleSnapshot.isStale)
    }

    func testVelaWidgetDataProviderSaveLoadClear() {
        let provider = VelaWidgetDataProvider.shared
        let snapshot = VelaWidgetSnapshot(
            generatedAt: Date(),
            bodyStateTitle: "状态良好",
            summary: "体征平稳",
            decision: "正常训练",
            decisionConfidence: 0.85,
            recoveryScore: 78,
            sleepScore: 80,
            strainScore: 35,
            stressScore: 22,
            energyScore: 82,
            hrvMilliseconds: 60,
            restingHeartRate: 56,
            primaryAction: "完成今日力量训练"
        )

        provider.saveSnapshot(snapshot)
        let loaded = provider.loadSnapshot()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.recoveryScore, 78)
        XCTAssertEqual(loaded?.decision, "正常训练")

        provider.clearSnapshot()
        let cleared = provider.loadSnapshot()
        XCTAssertNil(cleared)
    }

    func testWristSnapshotToWidgetSnapshotBridge() {
        let wrist = WristSnapshot(
            generatedAt: Date(),
            bodyStateTitle: "充沛",
            summary: "恢复评分 85%",
            decision: "执行计划",
            decisionConfidence: 0.9,
            recoveryScore: 85,
            sleepScore: 82,
            strainScore: 40,
            stressScore: 20,
            energyScore: 88,
            hrvMilliseconds: 65,
            restingHeartRate: 55,
            primaryAction: "力量训练",
            planTitle: "推拉腿计划",
            sessionTitle: "上半身推",
            sessionDetail: "卧推与肩推",
            planProgress: "第 1 周"
        )

        let widgetSnapshot = VelaWidgetSnapshot(from: wrist)
        XCTAssertEqual(widgetSnapshot.recoveryScore, 85)
        XCTAssertEqual(widgetSnapshot.planTitle, "推拉腿计划")
        XCTAssertEqual(widgetSnapshot.sessionTitle, "上半身推")

        // Test Provider update from wrist snapshot
        VelaWidgetDataProvider.shared.updateSnapshot(from: wrist)

        let activeSnapshot = VelaWidgetDataProvider.shared.loadSnapshot()
        XCTAssertNotNil(activeSnapshot)
        XCTAssertEqual(activeSnapshot?.recoveryScore, 85)
        XCTAssertEqual(activeSnapshot?.planTitle, "推拉腿计划")
        XCTAssertEqual(activeSnapshot?.sessionTitle, "上半身推")
    }

    private func recoveryDashboard(value: Double, date: Date) -> DashboardSummary {
        var dashboard = DashboardSummary.empty(date: date)
        dashboard.recovery = MetricResult(
            domain: .recovery,
            name: "Recovery",
            value: value,
            band: .normal,
            confidence: .high,
            components: [:],
            componentWeights: [:],
            reasons: [],
            missingInputs: [],
            dataWindow: DateInterval(start: date, duration: 86_400),
            source: .healthKit,
            algorithmVersion: "1.0",
            lastUpdated: date
        )
        return dashboard
    }
}
