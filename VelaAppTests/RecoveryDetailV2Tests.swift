import XCTest
@testable import Vela

final class RecoveryDetailV2Tests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private var endingAt: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 8))!
    }

    func testGridKeepsMissingDaysAndDoesNotTurnThemIntoZero() {
        let snapshots = [
            snapshot(offset: -6, score: 80),
            snapshot(offset: -3, score: 72),
            snapshot(offset: 0, score: 64)
        ]
        let model = makeModel(snapshots: snapshots, finding: availableFinding(sampleCount: 7))

        XCTAssertEqual(model.points.count, 7)
        XCTAssertEqual(model.missingDayCount, 4)
        XCTAssertEqual(model.observedDayCount, 3)
        XCTAssertFalse(model.points.contains { $0.value == 0 })
        XCTAssertEqual(model.points.map(\.value), [80, nil, nil, 72, nil, nil, 64])
        XCTAssertEqual(model.chartSegments.map { $0.compactMap(\.value) }, [[80], [72], [64]])
    }

    func testKnownZeroStaysZero() {
        let model = makeModel(
        recoveryValue: 0,
        snapshots: [snapshot(offset: 0, score: 0)],
        finding: availableFinding(sampleCount: 4, current: 0)
        )

        XCTAssertEqual(model.points.last?.value, 0)
        XCTAssertEqual(model.scoreText, "0")
        XCTAssertEqual(model.observedDayCount, 1)
    }

    func testNonFiniteAndNilScoresStayMissingAndLaterSnapshotWins() {
        let earlier = snapshot(offset: 0, score: 80, createdAtOffset: 0)
        var later = snapshot(offset: 0, score: nil, createdAtOffset: 60)
        later.recoveryScore = .nan
        let replaced = makeModel(
            snapshots: [earlier, later],
            finding: HealthTrendFinding.unavailable(metric: .recovery, horizon: .sevenDays, sampleCount: 1)
        )
        XCTAssertNil(replaced.points.last?.value)

        let missing = makeModel(
            snapshots: [
                snapshot(offset: -1, score: 70, createdAtOffset: 0),
                snapshot(offset: -1, score: nil, createdAtOffset: 30)
            ],
            finding: HealthTrendFinding.unavailable(metric: .recovery, horizon: .sevenDays, sampleCount: 0)
        )
        let yesterday = calendar.date(byAdding: .day, value: -1, to: endingAt)!
        XCTAssertNil(missing.points.first { calendar.isDate($0.date, inSameDayAs: yesterday) }?.value)
    }

    func testPointBaselineDrawsLineWithoutInventingBand() {
        let model = makeModel(
            snapshots: [snapshot(offset: 0, score: 82)],
            finding: availableFinding(sampleCount: 7, baseline: 74),
            baselineBand: nil
        )

        XCTAssertTrue(model.showsBaselineLine)
        XCTAssertEqual(model.baselineMedianValue, 74)
        XCTAssertNil(model.baselineBand)
        XCTAssertEqual(model.deviationText, "较基线偏高 10.8%")
    }

    func testContractBandIsForwardedUnchanged() {
        let model = makeModel(
            snapshots: [snapshot(offset: 0, score: 82)],
            finding: availableFinding(sampleCount: 7),
            baselineBand: 68...80
        )

        XCTAssertEqual(model.baselineBand, 68...80)
        XCTAssertTrue(model.showsBaselineLine)
    }

    func testUnavailableBaselineDoesNotDrawLineOrBand() {
        let model = makeModel(
            snapshots: [snapshot(offset: 0, score: 71)],
            finding: HealthTrendFinding.unavailable(metric: .recovery, horizon: .sevenDays, sampleCount: 2),
            baselineBand: nil
        )

        XCTAssertFalse(model.showsBaselineLine)
        XCTAssertNil(model.baselineMedianValue)
        XCTAssertNil(model.baselineBand)
        XCTAssertNil(model.deviationText)
        XCTAssertEqual(model.sampleText, "有效样本 2/4 天")
    }

    func testMissingScoreStaysDashAndSkipsDeviation() {
        let model = makeModel(
            recoveryValue: nil,
            snapshots: [snapshot(offset: -1, score: 74)],
            finding: availableFinding(sampleCount: 7, current: nil)
        )

        XCTAssertNil(model.scoreValue)
        XCTAssertEqual(model.scoreText, "--")
        XCTAssertNil(model.deviationText)
        XCTAssertNotEqual(model.points.last?.value, 0)
    }

    func testCandidateExplanationUsesExistingDriverOnlyWhenNotable() {
        let notable = availableFinding(sampleCount: 7, notable: true)
        let stable = availableFinding(sampleCount: 7, notable: false)
        let recoveryDriver = "观察到 HRV 偏低与静息心率升高在近期协同出现，提示生理恢复负荷有所累积"
        let sleepDriver = "近期睡眠得分偏离个人基线，可能与恢复感受变化相关"

        XCTAssertEqual(
            RecoveryDetailV2Builder.candidateExplanation(finding: notable, drivers: [sleepDriver, recoveryDriver]),
            sleepDriver
        )
        XCTAssertNil(RecoveryDetailV2Builder.candidateExplanation(finding: stable, drivers: [recoveryDriver]))
        XCTAssertNil(RecoveryDetailV2Builder.candidateExplanation(finding: notable, drivers: ["  "]))
    }

    func testDashboardAdapterReadsExistingResultsAndDoesNotInventBand() {
        let day = endingAt
        var dashboard = DashboardSummary.empty(date: day)
        dashboard.recovery = MetricResult(
            name: "Recovery Score",
            value: 80,
            band: .high,
            confidence: .high,
            components: [
                "hrv_z_score": -0.4,
                "rhr_z_score": 0.8,
                "prior_strain": 40
            ],
            componentWeights: ["hrv": 0.35],
            reasons: ["HRV 高于近期个人基线"],
            missingInputs: [],
            dataWindow: DateInterval(start: day, duration: 86_400),
            source: .healthKit,
            algorithmVersion: "recovery.v2.0.0",
            lastUpdated: day
        )
        dashboard.sleepScore = MetricResult(
            name: "Sleep Score",
            value: 81,
            band: .high,
            confidence: .high,
            components: [:],
            componentWeights: [:],
            reasons: [],
            missingInputs: [],
            dataWindow: DateInterval(start: day, duration: 86_400),
            source: .healthKit,
            algorithmVersion: "sleep.v2.2.0",
            lastUpdated: day
        )
        dashboard.recoveryMetrics = RecoveryMetricSummary(hrvMilliseconds: 42, restingHeartRate: 62, respiratoryRate: 14)
        dashboard.recoveryBaseline = RecoveryMetricSummary(hrvMilliseconds: 46, restingHeartRate: 60, respiratoryRate: nil)
        dashboard.personalHealthBrief = PersonalHealthBrief(
            date: day,
            headline: "测试",
            subheadline: "测试",
            possibleDrivers: ["观察到 HRV 偏低与静息心率升高在近期协同出现，提示生理恢复负荷有所累积"]
        )
        dashboard.healthTrends = [availableFinding(sampleCount: 7, notable: true, current: 80)]

        let model = RecoveryDetailV2Builder.make(
            dashboard: dashboard,
            snapshots: [snapshot(offset: 0, score: 80)],
            range: .week,
            endingAt: day,
            calendar: calendar,
            baselineBand: nil
        )

        XCTAssertEqual(model.scoreText, "80")
        XCTAssertNil(model.baselineBand)
        XCTAssertTrue(model.showsBaselineLine)
        XCTAssertEqual(model.observations.first { $0.id == "hrv" }?.valueText, "42 ms")
        XCTAssertEqual(model.observations.first { $0.id == "hrv" }?.baselineText, "信号基线 · 中位数 46 ms")
        XCTAssertEqual(model.observations.first { $0.id == "rhr" }?.baselineText, "信号基线 · 近端均值 60 bpm")
        XCTAssertEqual(model.observations.first { $0.id == "respiratory" }?.baselineText, "信号基线 · 近端均值建立中")
        XCTAssertEqual(model.evidence.first { $0.id == "sleep-input" }?.valueText, "81")
        XCTAssertEqual(model.evidence.first { $0.id == "strain-input" }?.valueText, "40")
        XCTAssertEqual(model.candidateExplanation?.contains("HRV"), true)
        XCTAssertEqual(model.algorithmVersion, "recovery.v2.0.0")
        XCTAssertFalse(model.isSimulated)
    }

    private func makeModel(
        recoveryValue: Double? = 82,
        snapshots: [DailyHealthSnapshot],
        finding: HealthTrendFinding,
        baselineBand: ClosedRange<Double>? = nil
    ) -> RecoveryDetailV2Model {
        RecoveryDetailV2Builder.make(
            source: RecoveryDetailV2Source(
                recoveryValue: recoveryValue,
                bandText: recoveryValue == nil ? "暂无恢复分" : "高恢复",
                coverageText: recoveryValue == nil ? "暂无数据" : "完整",
                confidenceText: recoveryValue == nil ? "不可用" : "高",
                algorithmVersion: "recovery.test",
                findings: [finding],
                snapshots: snapshots,
                baselineBand: baselineBand
            ),
            range: .week,
            endingAt: endingAt,
            calendar: calendar
        )
    }

    private func availableFinding(
        sampleCount: Int,
        baseline: Double = 74,
        notable: Bool = false,
        current: Double? = 82
    ) -> HealthTrendFinding {
        HealthTrendFinding(
            metric: .recovery,
            horizon: .sevenDays,
            direction: .improving,
            valueDirection: .rising,
            assessment: .neutral,
            currentValue: current,
            currentValueFormatted: current.map { "\(Int($0))" } ?? "--",
            baselineValue: baseline,
            baselineValueFormatted: "\(Int(baseline))",
            currentDeviationPercent: current == nil ? nil : 10.8,
            temporalTrendDeltaPercent: 4.2,
            sampleCount: sampleCount,
            requiredSampleCount: 4,
            isAvailable: true,
            confidence: .high,
            deviationSummary: current == nil ? "今日没有可比较的恢复分" : "较基线偏高 10.8%",
            temporalTrendSummary: "最近 7 天中位数上升 +4.2%",
            summary: "较基线偏高 10.8%，最近 7 天中位数上升 +4.2%",
            isNotable: notable
        )
    }

    private func snapshot(offset: Int, score: Double?, createdAtOffset: TimeInterval = 0) -> DailyHealthSnapshot {
        let day = calendar.date(byAdding: .day, value: offset, to: endingAt)!
        var snapshot = DailyHealthSnapshot(date: day, createdAt: day.addingTimeInterval(createdAtOffset))
        snapshot.recoveryScore = score
        return snapshot
    }
}
