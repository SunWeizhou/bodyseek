import Charts
import SwiftUI

// MARK: - Presentation

/// Recovery Detail V2 只投影已经算好的结果。
/// 基线带必须由调用方从数据合同传入；本类型不会用标准差或分位数临时生成区间。
enum RecoveryDetailKind: String, Equatable, Sendable {
    case currentValue = "当前数值"
    case statisticalDescription = "统计描述"
    case candidateExplanation = "候选解释"
    case scoreInput = "评分输入"
}

struct RecoveryDetailV2Point: Identifiable, Equatable, Sendable {
    var date: Date
    /// `nil` 表示这一天没有恢复分。不得写成 0。
    var value: Double?
    var id: Date { date }
}

struct RecoveryObservation: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var valueText: String
    var baselineText: String?
    var kind: RecoveryDetailKind
}

struct RecoveryEvidenceLine: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var valueText: String
    var kind: RecoveryDetailKind
}

struct RecoveryDetailV2Model: Equatable, Sendable {
    var isSimulated: Bool
    var scenarioLabel: String?
    var scoreText: String
    var scoreValue: Double?
    var bandText: String
    var coverageText: String
    var confidenceText: String
    var missingSummary: String?
    var baselineWindowTitle: String
    var baselineMedianText: String?
    var baselineMedianValue: Double?
    var deviationText: String?
    var sampleText: String
    var showsBaselineLine: Bool
    /// 只有数据合同给出上下界时才非 nil。
    var baselineBand: ClosedRange<Double>?
    var trendSummary: String
    var points: [RecoveryDetailV2Point]
    var range: DetailTimeRange
    var observations: [RecoveryObservation]
    var findingText: String
    var candidateExplanation: String?
    var evidence: [RecoveryEvidenceLine]
    var algorithmVersion: String

    var observedDayCount: Int { points.compactMap(\.value).count }
    var missingDayCount: Int { points.count - observedDayCount }

    var chartSegments: [[RecoveryDetailV2Point]] {
        RecoveryDetailV2Series.segments(points)
    }
}

enum RecoveryDetailV2Series {
    static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    /// 窗口内每个日历日都保留一个点。没有快照、分数缺失或非有限值都保持 `nil`。
    static func grid(
        snapshots: [DailyHealthSnapshot],
        range: DetailTimeRange,
        endingAt: Date,
        calendar: Calendar
    ) -> [RecoveryDetailV2Point] {
        let end = calendar.startOfDay(for: endingAt)
        let start = calendar.date(byAdding: .day, value: -(range.days - 1), to: end) ?? end
        let sorted = snapshots.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.createdAt < rhs.createdAt
        }
        var byDay: [Date: Double?] = [:]
        for snapshot in sorted {
            let day = calendar.startOfDay(for: snapshot.date)
            guard day >= start, day <= end else { continue }
            byDay[day] = finite(snapshot.recoveryScore)
        }

        var points: [RecoveryDetailV2Point] = []
        var day = start
        while day <= end {
            points.append(RecoveryDetailV2Point(date: day, value: storedValue(byDay[day])))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }

    private static func storedValue(_ stored: (Double?)?) -> Double? {
        stored ?? nil
    }

    /// 只连接网格里相邻、且都有读数的日期。缺失日断开，不插值。
    /// `grid` 已补齐每个日历日，所以相邻下标就是相邻日期。
    static func segments(_ points: [RecoveryDetailV2Point]) -> [[RecoveryDetailV2Point]] {
        var segments: [[RecoveryDetailV2Point]] = []
        var current: [RecoveryDetailV2Point] = []
        for point in points {
            guard point.value != nil else {
                if !current.isEmpty {
                    segments.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }
            current.append(point)
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }
}

struct RecoveryDetailV2Source: Equatable, Sendable {
    var recoveryValue: Double?
    var bandText: String
    var coverageText: String
    var confidenceText: String
    var missingSummary: String?
    var algorithmVersion: String
    var observations: [RecoveryObservation]
    var findings: [HealthTrendFinding]
    var candidateDrivers: [String]
    var snapshots: [DailyHealthSnapshot]
    var baselineBand: ClosedRange<Double>?
    var hrvZ: Double?
    var rhrZ: Double?
    var respiratoryZ: Double?
    var sleepScoreText: String
    var priorStrainText: String
    var isSimulated: Bool
    var scenarioLabel: String?

    init(
        recoveryValue: Double?,
        bandText: String,
        coverageText: String,
        confidenceText: String,
        missingSummary: String? = nil,
        algorithmVersion: String,
        observations: [RecoveryObservation] = [],
        findings: [HealthTrendFinding] = [],
        candidateDrivers: [String] = [],
        snapshots: [DailyHealthSnapshot] = [],
        baselineBand: ClosedRange<Double>? = nil,
        hrvZ: Double? = nil,
        rhrZ: Double? = nil,
        respiratoryZ: Double? = nil,
        sleepScoreText: String = "--",
        priorStrainText: String = "--",
        isSimulated: Bool = false,
        scenarioLabel: String? = nil
    ) {
        self.recoveryValue = RecoveryDetailV2Series.finite(recoveryValue)
        self.bandText = bandText
        self.coverageText = coverageText
        self.confidenceText = confidenceText
        self.missingSummary = missingSummary
        self.algorithmVersion = algorithmVersion
        self.observations = observations
        self.findings = findings
        self.candidateDrivers = candidateDrivers
        self.snapshots = snapshots
        self.baselineBand = baselineBand
        self.hrvZ = hrvZ
        self.rhrZ = rhrZ
        self.respiratoryZ = respiratoryZ
        self.sleepScoreText = sleepScoreText
        self.priorStrainText = priorStrainText
        self.isSimulated = isSimulated
        self.scenarioLabel = scenarioLabel
    }
}

enum RecoveryDetailV2Builder {
    static func make(
        dashboard: DashboardSummary,
        snapshots: [DailyHealthSnapshot],
        range: DetailTimeRange,
        endingAt: Date,
        calendar: Calendar = .current,
        baselineBand: ClosedRange<Double>? = nil,
        isSimulated: Bool = false,
        scenarioLabel: String? = nil
    ) -> RecoveryDetailV2Model {
        let recovery = dashboard.recovery
        return make(
            source: RecoveryDetailV2Source(
                recoveryValue: recovery.value,
                bandText: recovery.value == nil ? "暂无恢复分" : "\(bandLabel(recovery.band))恢复",
                coverageText: coverageLabel(recovery),
                confidenceText: recovery.value == nil ? "不可用" : confidenceLabel(recovery.confidence),
                missingSummary: missingSummary(recovery),
                algorithmVersion: recovery.algorithmVersion,
                observations: observations(from: dashboard),
                findings: dashboard.healthTrends,
                candidateDrivers: dashboard.personalHealthBrief?.possibleDrivers ?? [],
                snapshots: snapshots,
                baselineBand: baselineBand,
                hrvZ: recovery.components["hrv_z_score"],
                rhrZ: recovery.components["rhr_z_score"],
                respiratoryZ: recovery.components["respiratory_rate_z"],
                sleepScoreText: scoreText(dashboard.sleepScore.value),
                priorStrainText: scoreText(recovery.components["prior_strain"]),
                isSimulated: isSimulated,
                scenarioLabel: scenarioLabel
            ),
            range: range,
            endingAt: endingAt,
            calendar: calendar
        )
    }

    static func make(
        source: RecoveryDetailV2Source,
        range: DetailTimeRange,
        endingAt: Date,
        calendar: Calendar = .current
    ) -> RecoveryDetailV2Model {
        let horizon = range.trendHorizon ?? .sevenDays
        let finding = source.findings.first { $0.metric == .recovery && $0.horizon == horizon }
            ?? HealthTrendFinding.unavailable(metric: .recovery, horizon: horizon)
        let points = RecoveryDetailV2Series.grid(
            snapshots: source.snapshots,
            range: range,
            endingAt: endingAt,
            calendar: calendar
        )
        let hasMedian = finding.isAvailable && finding.baselineValue != nil
        let deviationText: String? = source.recoveryValue == nil || !finding.isAvailable
            ? nil
            : finding.deviationSummary
        let candidate = candidateExplanation(finding: finding, drivers: source.candidateDrivers)

        return RecoveryDetailV2Model(
            isSimulated: source.isSimulated,
            scenarioLabel: source.scenarioLabel,
            scoreText: scoreText(source.recoveryValue),
            scoreValue: source.recoveryValue,
            bandText: source.bandText,
            coverageText: source.coverageText,
            confidenceText: source.confidenceText,
            missingSummary: source.missingSummary,
            baselineWindowTitle: horizon.detailedTitle,
            baselineMedianText: hasMedian ? scoreText(finding.baselineValue) : nil,
            baselineMedianValue: hasMedian ? finding.baselineValue : nil,
            deviationText: deviationText,
            sampleText: "有效样本 \(finding.sampleCount)/\(finding.requiredSampleCount) 天",
            showsBaselineLine: hasMedian,
            baselineBand: source.baselineBand,
            trendSummary: finding.isAvailable ? finding.temporalTrendSummary : finding.summary,
            points: points,
            range: range,
            observations: source.observations,
            findingText: finding.summary,
            candidateExplanation: candidate,
            evidence: evidenceLines(finding: finding, source: source, hasMedian: hasMedian),
            algorithmVersion: source.algorithmVersion
        )
    }

    static func scoreText(_ value: Double?) -> String {
        guard let value = RecoveryDetailV2Series.finite(value) else { return "--" }
        return "\(Int(value.rounded()))"
    }

    /// 只有恢复趋势被标成值得留意时，才引用简报里已有的第一句候选解释。
    /// 不改写原文，也不把它说成因果关系。
    static func candidateExplanation(
        finding: HealthTrendFinding,
        drivers: [String]
    ) -> String? {
        guard finding.isAvailable, finding.isNotable else { return nil }
        return drivers.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func evidenceLines(
        finding: HealthTrendFinding,
        source: RecoveryDetailV2Source,
        hasMedian: Bool
    ) -> [RecoveryEvidenceLine] {
        var lines: [RecoveryEvidenceLine] = [
            .init(id: "sample", title: "有效样本", valueText: "\(finding.sampleCount)/\(finding.requiredSampleCount) 天", kind: .statisticalDescription),
            .init(id: "median", title: "窗口中位数", valueText: hasMedian ? scoreText(finding.baselineValue) : "--", kind: .statisticalDescription),
            .init(
                id: "trend",
                title: "前后半窗中位数变化",
                valueText: finding.isAvailable ? percentText(finding.temporalTrendDeltaPercent) : "--",
                kind: .statisticalDescription
            ),
            .init(id: "sleep-input", title: "昨夜睡眠分", valueText: source.sleepScoreText, kind: .scoreInput),
            .init(id: "strain-input", title: "昨日负荷成分", valueText: source.priorStrainText, kind: .scoreInput),
            .init(id: "hrv-z", title: "HRV 稳健 Z", valueText: signedText(source.hrvZ, suffix: " z"), kind: .statisticalDescription),
            .init(id: "rhr-z", title: "静息心率稳健 Z", valueText: signedText(source.rhrZ, suffix: " z"), kind: .statisticalDescription)
        ]
        if source.respiratoryZ != nil {
            lines.append(.init(id: "resp-z", title: "呼吸率 Z", valueText: signedText(source.respiratoryZ, suffix: " z"), kind: .statisticalDescription))
        }
        return lines
    }

    private static func observations(from dashboard: DashboardSummary) -> [RecoveryObservation] {
        let metrics = dashboard.recoveryMetrics
        let baseline = dashboard.recoveryBaseline
        var rows: [RecoveryObservation] = [
            observation("hrv", "HRV", metrics.hrvMilliseconds, " ms", baseline.hrvMilliseconds, "信号基线 · 中位数"),
            observation("rhr", "静息心率", metrics.restingHeartRate, " bpm", baseline.restingHeartRate, "信号基线 · 近端均值"),
            observation("respiratory", "呼吸率", metrics.respiratoryRate, " 次/分", baseline.respiratoryRate, "信号基线 · 近端均值")
        ]
        if let spo2 = dashboard.recovery.components["spo2"] ?? dashboard.extendedMetrics.oxygenSaturation {
            rows.append(observation("spo2", "血氧", spo2, "%", nil, nil))
        } else {
            rows.append(observation("spo2", "血氧", nil, "%", nil, nil))
        }
        let sleepMinutes = dashboard.sleepSummary.totalSleepMinutes
        rows.append(
            RecoveryObservation(
                id: "sleep-duration",
                title: "昨夜睡眠时长",
                valueText: sleepMinutes > 0 ? VelaMinimalFormatting.duration(minutes: sleepMinutes) : "--",
                baselineText: nil,
                kind: .currentValue
            )
        )
        return rows
    }

    private static func observation(
        _ id: String,
        _ title: String,
        _ value: Double?,
        _ unit: String,
        _ baseline: Double?,
        _ baselineCaption: String?
    ) -> RecoveryObservation {
        let baselineText: String?
        if let baselineCaption {
            if let baseline = RecoveryDetailV2Series.finite(baseline) {
                baselineText = "\(baselineCaption) \(scoreText(baseline))\(unit)"
            } else {
                baselineText = "\(baselineCaption)建立中"
            }
        } else {
            baselineText = nil
        }
        return RecoveryObservation(
            id: id,
            title: title,
            valueText: measurementText(value, unit: unit),
            baselineText: baselineText,
            kind: .currentValue
        )
    }

    private static func measurementText(_ value: Double?, unit: String) -> String {
        guard let value = RecoveryDetailV2Series.finite(value) else { return "--" }
        return "\(Int(value.rounded()))\(unit)"
    }

    private static func percentText(_ value: Double?) -> String {
        guard let value = RecoveryDetailV2Series.finite(value) else { return "--" }
        return String(format: "%+.1f%%", value)
    }

    private static func signedText(_ value: Double?, suffix: String) -> String {
        guard let value = RecoveryDetailV2Series.finite(value) else { return "--" }
        return String(format: "%+.1f%@", value, suffix)
    }

    private static func bandLabel(_ band: MetricBand) -> String {
        switch band {
        case .veryLow: "很低"
        case .low: "低"
        case .normal: "正常"
        case .high: "高"
        case .veryHigh: "很高"
        }
    }

    private static func confidenceLabel(_ confidence: MetricConfidence) -> String {
        switch confidence {
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }

    private static func coverageLabel(_ result: MetricResult) -> String {
        guard result.value != nil else { return "暂无数据" }
        switch result.dataCoverage {
        case .unavailable: return "不可用"
        case .partial: return "部分"
        case .substantial: return "主要数据"
        case .complete: return "完整"
        }
    }

    private static func missingSummary(_ result: MetricResult) -> String? {
        guard result.value != nil, !result.missingInputs.isEmpty else {
            if result.value == nil {
                return "缺少可用读数；不会用 0 代替。"
            }
            return nil
        }
        let labels = result.missingInputs.prefix(3).map(missingLabel)
        return "仍缺少：\(labels.joined(separator: "、"))。"
    }

    private static func missingLabel(_ input: String) -> String {
        let normalized = input.lowercased()
        if normalized.contains("hrv") { return "HRV" }
        if normalized.contains("rhr") || normalized.contains("resting") { return "静息心率" }
        if normalized.contains("sleep") { return "睡眠分" }
        if normalized.contains("strain") { return "昨日负荷" }
        return "部分输入"
    }
}

// MARK: - View

struct RecoveryDetailV2View: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: RecoveryDetailV2Model
    @Binding var selectedRange: DetailTimeRange
    let onAskCoach: () -> Void

    @State private var scrubbedDate: Date?
    @State private var showsEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.isSimulated {
                simulatedBanner
            }
            scoreSection
            baselineSection
            trendSection
            observationSection
            findingSection
        }
        .padding(.top, 8)
        .onChange(of: selectedRange) { _, _ in
            scrubbedDate = nil
            showsEvidence = false
        }
    }

    private var simulatedBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("模拟数据，不是 Apple 健康记录")
                .font(VelaTheme.caption1().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
            if let scenarioLabel = model.scenarioLabel {
                Text(scenarioLabel)
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmWarm.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("recovery-detail-simulated")
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            kindLabel(.currentValue)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    scoreRing
                    scoreFacts
                }
                VStack(alignment: .leading, spacing: 12) {
                    scoreRing
                    scoreFacts
                }
            }
        }
        .padding(16)
        .modifier(RecoveryDetailCard())
        .accessibilityIdentifier("metric-detail-hero")
    }

    private var scoreRing: some View {
        ZStack {
            Circle()
                .stroke(VelaTheme.recoveryColor.opacity(0.14), lineWidth: 9)
            if model.scoreValue != nil {
                Circle()
                    .trim(from: 0, to: min(1, max(0, (model.scoreValue ?? 0) / 100)))
                    .stroke(VelaTheme.recoveryColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(VelaTheme.dataAnimation(reduceMotion: reduceMotion), value: model.scoreValue)
            } else {
                Circle()
                    .stroke(VelaTheme.rhythmInkSecondary.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [3, 5]))
            }
            if let median = model.baselineMedianValue, (0...100).contains(median) {
                Circle()
                    .fill(VelaTheme.rhythmInkSecondary)
                    .frame(width: 7, height: 7)
                    .offset(y: -54)
                    .rotationEffect(.degrees(-90 + median / 100 * 360))
                    .accessibilityHidden(true)
            }
            Text(model.scoreText)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(VelaTheme.rhythmInk)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(width: 116, height: 116)
        .accessibilityHidden(true)
    }

    private var scoreFacts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日恢复")
                .font(VelaTheme.caption1().weight(.semibold))
                .foregroundStyle(VelaTheme.recoveryColor)
                .accessibilityIdentifier("metric-detail-hero")
            Text(model.bandText)
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.rhythmInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("覆盖度 \(model.coverageText) · 置信度 \(model.confidenceText)")
                .font(VelaTheme.caption1())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let missingSummary = model.missingSummary {
                Text(missingSummary)
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var baselineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            kindLabel(.statisticalDescription)
            Text("个人基线对照")
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.rhythmInk)
            Text(model.baselineWindowTitle)
                .font(VelaTheme.caption1().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            if let median = model.baselineMedianText {
                labeledValue("窗口中位数", median)
                if let deviationText = model.deviationText {
                    Text(deviationText)
                        .font(VelaTheme.body())
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .fixedSize(horizontal: false, vertical: true)
                } else if model.scoreValue == nil {
                    Text("今日没有恢复分，不能计算偏离。")
                        .font(VelaTheme.body())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("这个窗口的恢复分中位数还在建立。")
                    .font(VelaTheme.body())
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(model.sampleText)
                .font(VelaTheme.caption1())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            Text(baselineContractCaption)
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .modifier(RecoveryDetailCard())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recovery-detail-baseline")
    }

    private var baselineContractCaption: String {
        if let band = model.baselineBand {
            return "基线带 \(Int(band.lowerBound.rounded()))–\(Int(band.upperBound.rounded())) 来自数据合同，不是由中位数推算的区间。"
        }
        if model.showsBaselineLine {
            return "目前只有窗口中位数，没有基线区间。"
        }
        return "样本不足时不绘制基线，也不补一个区间。"
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    kindLabel(.statisticalDescription)
                    Text("恢复趋势")
                        .font(VelaTheme.headline())
                        .foregroundStyle(VelaTheme.rhythmInk)
                }
                Spacer(minLength: 8)
            }
            rangePicker
            Text(model.trendSummary)
                .font(VelaTheme.body())
                .foregroundStyle(VelaTheme.rhythmInk)
                .fixedSize(horizontal: false, vertical: true)
            if let scrubbedPoint {
                Text(scrubCaption(scrubbedPoint))
                    .font(VelaTheme.caption1().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            trendChart
            Text("有效 \(model.observedDayCount) 天 · 缺失 \(model.missingDayCount) 天。缺失日保留空档，不插值，也不记为 0。")
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            chartLegend
        }
        .padding(16)
        .modifier(RecoveryDetailCard())
        .accessibilityIdentifier("recovery-detail-chart")
    }

    @ViewBuilder
    private var trendChart: some View {
        if model.observedDayCount == 0 {
            VelaStateCard(
                state: .calibrating,
                message: "这个窗口还没有恢复分。缺失日不会被画成 0。"
            )
        } else {
            Chart {
                if let band = model.baselineBand,
                   let first = model.points.first?.date,
                   let last = model.points.last?.date {
                    RectangleMark(
                        xStart: .value("开始", first, unit: .day),
                        xEnd: .value("结束", last, unit: .day),
                        yStart: .value("下界", band.lowerBound),
                        yEnd: .value("上界", band.upperBound)
                    )
                    .foregroundStyle(VelaTheme.recoveryColor.opacity(0.12))
                }
                if model.showsBaselineLine, let median = model.baselineMedianValue {
                    RuleMark(y: .value("窗口中位数", median))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                ForEach(Array(model.chartSegments.enumerated()), id: \.offset) { index, segment in
                    if segment.count == 1, let point = segment.first, let value = point.value {
                        PointMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value("恢复分", value)
                        )
                        .foregroundStyle(VelaTheme.recoveryColor)
                        .symbolSize(36)
                    } else {
                        ForEach(segment) { point in
                            if let value = point.value {
                                LineMark(
                                    x: .value("日期", point.date, unit: .day),
                                    y: .value("恢复分", value),
                                    series: .value("分段", index)
                                )
                                .foregroundStyle(VelaTheme.recoveryColor)
                                .interpolationMethod(.linear)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            }
                        }
                    }
                }
                if selectedRange == .week || selectedRange == .month {
                    ForEach(model.points.filter { $0.value == nil }) { point in
                        RuleMark(x: .value("缺失", point.date, unit: .day))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.18))
                            .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [2, 4]))
                    }
                }
                if let scrubbedPoint {
                    RuleMark(x: .value("选中", scrubbedPoint.date, unit: .day))
                        .foregroundStyle(VelaTheme.rhythmInk.opacity(0.35))
                    if let value = scrubbedPoint.value {
                        PointMark(
                            x: .value("选中日期", scrubbedPoint.date, unit: .day),
                            y: .value("选中分数", value)
                        )
                        .foregroundStyle(VelaTheme.recoveryColor)
                        .symbolSize(70)
                    }
                }
            }
            .chartXScale(domain: xDomain)
            .chartXSelection(value: $scrubbedDate)
            .chartXAxis {
                if selectedRange == .halfYear || selectedRange == .threeYears {
                    AxisMarks(values: .stride(by: .month, count: selectedRange == .threeYears ? 6 : 1)) { _ in
                        AxisGridLine().foregroundStyle(VelaTheme.rhythmMist.opacity(0.7))
                        AxisValueLabel()
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                } else {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine().foregroundStyle(VelaTheme.rhythmMist.opacity(0.7))
                        AxisValueLabel()
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(VelaTheme.rhythmMist.opacity(0.7))
                    AxisValueLabel()
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 220 : 180)
            .accessibilityLabel("恢复趋势")
            .accessibilityValue("有效 \(model.observedDayCount) 天，缺失 \(model.missingDayCount) 天")
        }
    }

    private var xDomain: ClosedRange<Date> {
        let start = model.points.first?.date ?? Date()
        let end = model.points.last?.date ?? start
        return start...end
    }

    private var chartLegend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("折线只连接相邻的真实读数。")
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            if model.showsBaselineLine {
                Text("虚线是窗口中位数。")
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            if model.baselineBand != nil {
                Text("浅色带是数据合同里的上下界。")
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
        }
    }

    private var observationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            kindLabel(.currentValue)
            Text("观测依据")
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.rhythmInk)
            Text("信号基线和上方的恢复分窗口中位数不是同一个数。")
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(model.observations) { observation in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(observation.title)
                            .font(VelaTheme.body())
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Spacer(minLength: 8)
                        Text(observation.valueText)
                            .font(VelaTheme.body().weight(.semibold).monospacedDigit())
                            .foregroundStyle(VelaTheme.rhythmInk)
                    }
                    if let baselineText = observation.baselineText {
                        Text(baselineText)
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .modifier(RecoveryDetailCard())
        .accessibilityIdentifier("recovery-detail-observations")
    }

    private var findingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("主要发现")
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.rhythmInk)
            kindLabel(.statisticalDescription)
            Text(model.findingText)
                .font(VelaTheme.body())
                .foregroundStyle(VelaTheme.rhythmInk)
                .fixedSize(horizontal: false, vertical: true)
            if let candidate = model.candidateExplanation {
                kindLabel(.candidateExplanation)
                Text(candidate)
                    .font(VelaTheme.body())
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text("这是已有简报中的候选解释，不是已验证的因果关系。")
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                showsEvidence.toggle()
            } label: {
                HStack {
                    Text(showsEvidence ? "收起证据" : "查看证据")
                        .font(VelaTheme.body().weight(.semibold))
                    Spacer()
                    Image(systemName: showsEvidence ? "chevron.up" : "chevron.down")
                        .font(VelaTheme.caption1().weight(.semibold))
                }
                .foregroundStyle(VelaTheme.rhythmDeep)
                .frame(minHeight: VelaTheme.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("recovery-detail-evidence-toggle")
            if showsEvidence {
                ForEach(model.evidence) { line in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.kind.rawValue)
                                .font(VelaTheme.caption2())
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            Text(line.title)
                                .font(VelaTheme.caption1())
                                .foregroundStyle(VelaTheme.rhythmInk)
                        }
                        Spacer(minLength: 8)
                        Text(line.valueText)
                            .font(VelaTheme.caption1().weight(.semibold).monospacedDigit())
                            .foregroundStyle(VelaTheme.rhythmInk)
                    }
                }
                Text("变化是前后半窗中位数的描述，不是统计显著性。算法 \(model.algorithmVersion)。")
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onAskCoach) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("向 Coach 追问")
                        .font(VelaTheme.body().weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(VelaTheme.caption2().weight(.bold))
                }
                .foregroundStyle(VelaTheme.rhythmInk)
                .frame(minHeight: VelaTheme.minimumHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开 Coach，沿用当前恢复详情的上下文")
        }
        .padding(16)
        .modifier(RecoveryDetailCard())
        .accessibilityIdentifier("recovery-detail-finding")
    }

    private func kindLabel(_ kind: RecoveryDetailKind) -> some View {
        Text(kind.rawValue)
            .font(VelaTheme.caption2().weight(.semibold))
            .foregroundStyle(VelaTheme.rhythmInkSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(VelaTheme.rhythmMist.opacity(colorSchemeContrast == .increased ? 0.9 : 0.45), in: Capsule())
    }

    private func labeledValue(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(VelaTheme.body())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(VelaTheme.rhythmInk)
        }
    }

    private func scrubCaption(_ point: RecoveryDetailV2Point) -> String {
        let day = point.date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
        if let value = point.value {
            return "\(day) 的恢复分 \(RecoveryDetailV2Builder.scoreText(value))"
        }
        return "\(day) 没有恢复分"
    }

    private var scrubbedPoint: RecoveryDetailV2Point? {
        guard let scrubbedDate else { return nil }
        return model.points.min {
            abs($0.date.timeIntervalSince(scrubbedDate)) < abs($1.date.timeIntervalSince(scrubbedDate))
        }
    }

    @ViewBuilder
    private var rangePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Menu {
                ForEach(DetailTimeRange.allCases) { range in
                    Button(range.title) { select(range) }
                }
            } label: {
                Label(selectedRange.title, systemImage: "calendar")
                    .font(VelaTheme.body().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
            }
            .accessibilityLabel("趋势时间范围")
            .accessibilityValue(selectedRange.title)
        } else {
            HStack(spacing: 4) {
                ForEach(DetailTimeRange.allCases) { range in
                    Button(range.title) { select(range) }
                        .font(VelaTheme.caption1().weight(.semibold))
                        .foregroundStyle(selectedRange == range ? VelaTheme.rhythmInk : VelaTheme.rhythmInkSecondary)
                        .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget)
                        .background(
                            Capsule().fill(selectedRange == range ? VelaTheme.rhythmCanvas : Color.clear)
                        )
                        .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
                }
            }
            .padding(3)
            .background(VelaTheme.rhythmMist.opacity(0.45), in: Capsule())
            .accessibilityLabel("时间区间")
        }
    }

    private func select(_ range: DetailTimeRange) {
        guard selectedRange != range else { return }
        selectedRange = range
    }
}

private struct RecoveryDetailCard: ViewModifier {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        colorSchemeContrast == .increased ? VelaTheme.rhythmInk : VelaTheme.rhythmMist,
                        lineWidth: colorSchemeContrast == .increased ? 1 : 0.75
                    )
            }
    }
}

// MARK: - Simulated preview scenarios

enum RecoveryDetailV2Fixtures {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static let endingAt = date(2026, 10, 8)

    static var pointBaseline: RecoveryDetailV2Model {
        make(
            label: "模拟数据 · 仅有基线点估计，画中位数线",
            value: 82,
            band: "高恢复",
            finding: availableFinding(baseline: 74, deviationPercent: 10.8, trendPercent: 4.2, notable: false),
            snapshots: series([70, 72, nil, 74, 76, 78, 82]),
            bandRange: nil
        )
    }

    static var contractBand: RecoveryDetailV2Model {
        make(
            label: "模拟数据 · 合同提供了基线上下界，才画基线带",
            value: 82,
            band: "高恢复",
            finding: availableFinding(baseline: 74, deviationPercent: 10.8, trendPercent: 4.2, notable: true),
            snapshots: series([70, 72, 74, 76, 78, 80, 82]),
            bandRange: 68...80,
            drivers: ["观察到 HRV 偏低与静息心率升高在近期协同出现，提示生理恢复负荷有所累积"]
        )
    }

    static var missingDays: RecoveryDetailV2Model {
        make(
            label: "模拟数据 · 序列含缺失日，空档保持为空",
            value: 64,
            band: "正常恢复",
            finding: availableFinding(baseline: 70, deviationPercent: -8.6, trendPercent: -6.0, notable: false),
            snapshots: series([80, nil, nil, 72, 68, nil, 64]),
            bandRange: nil
        )
    }

    static var baselineUnavailable: RecoveryDetailV2Model {
        make(
            label: "模拟数据 · 基线样本不足，不画线和区间",
            value: 71,
            band: "高恢复",
            finding: HealthTrendFinding.unavailable(metric: .recovery, horizon: .thirtyDays, sampleCount: 6),
            snapshots: series([71, nil, 70]),
            bandRange: nil,
            range: .month
        )
    }

    static var missingScore: RecoveryDetailV2Model {
        make(
            label: "模拟数据 · 今日没有恢复分",
            value: nil,
            band: "暂无恢复分",
            coverage: "暂无数据",
            confidence: "不可用",
            missing: "缺少可用读数；不会用 0 代替。",
            finding: availableFinding(baseline: 74, deviationPercent: nil, trendPercent: 1.0, notable: false, current: nil),
            snapshots: series([74, 75, 73, nil, 76, 74, nil]),
            bandRange: nil,
            observations: [
                RecoveryObservation(id: "hrv", title: "HRV", valueText: "--", baselineText: "信号基线 · 中位数建立中", kind: .currentValue),
                RecoveryObservation(id: "rhr", title: "静息心率", valueText: "--", baselineText: "信号基线 · 近端均值建立中", kind: .currentValue)
            ]
        )
    }

    static var partialObservations: RecoveryDetailV2Model {
        make(
            label: "模拟数据 · HRV 缺失，静息心率仍是真实读数",
            value: 58,
            band: "正常恢复",
            coverage: "部分",
            confidence: "中",
            missing: "仍缺少：HRV。",
            finding: availableFinding(baseline: 73, deviationPercent: -20.5, trendPercent: -11.0, notable: true),
            snapshots: series([78, 76, 74, 70, 66, 62, 58]),
            bandRange: nil,
            drivers: ["近期睡眠得分偏离个人基线，可能与恢复感受变化相关"],
            observations: [
                RecoveryObservation(id: "hrv", title: "HRV", valueText: "--", baselineText: "信号基线 · 中位数 46 ms", kind: .currentValue),
                RecoveryObservation(id: "rhr", title: "静息心率", valueText: "67 bpm", baselineText: "信号基线 · 近端均值 60 bpm", kind: .currentValue),
                RecoveryObservation(id: "respiratory", title: "呼吸率", valueText: "15 次/分", baselineText: "信号基线 · 近端均值建立中", kind: .currentValue),
                RecoveryObservation(id: "spo2", title: "血氧", valueText: "--", baselineText: nil, kind: .currentValue),
                RecoveryObservation(id: "sleep-duration", title: "昨夜睡眠时长", valueText: "6小时10分钟", baselineText: nil, kind: .currentValue)
            ]
        )
    }

    static var interactiveSource: RecoveryDetailV2Source {
        RecoveryDetailV2Source(
            recoveryValue: 82,
            bandText: "高恢复",
            coverageText: "完整",
            confidenceText: "高",
            algorithmVersion: "recovery.preview",
            observations: pointBaseline.observations,
            findings: HealthTrendHorizon.allCases.map { horizon in
                availableFinding(
                    baseline: 74,
                    deviationPercent: 10.8,
                    trendPercent: horizon == .sevenDays ? 4.2 : 1.5,
                    notable: horizon == .sevenDays,
                    horizon: horizon,
                    sampleCount: horizon.requiredSampleCount + 3
                )
            },
            candidateDrivers: ["观察到 HRV 偏低与静息心率升高在近期协同出现，提示生理恢复负荷有所累积"],
            snapshots: series(Array(repeating: 76.0, count: 40).enumerated().map { index, value in
                index.isMultiple(of: 9) ? nil : value + Double(index % 5)
            }),
            isSimulated: true,
            scenarioLabel: "模拟数据 · 切换窗口会改用对应的已有趋势结果"
        )
    }

    private static func make(
        label: String,
        value: Double?,
        band: String,
        coverage: String = "完整",
        confidence: String = "高",
        missing: String? = nil,
        finding: HealthTrendFinding,
        snapshots: [DailyHealthSnapshot],
        bandRange: ClosedRange<Double>?,
        range: DetailTimeRange = .week,
        drivers: [String] = [],
        observations: [RecoveryObservation]? = nil
    ) -> RecoveryDetailV2Model {
        RecoveryDetailV2Builder.make(
            source: RecoveryDetailV2Source(
                recoveryValue: value,
                bandText: band,
                coverageText: coverage,
                confidenceText: confidence,
                missingSummary: missing,
                algorithmVersion: "recovery.preview",
                observations: observations ?? defaultObservations,
                findings: [finding],
                candidateDrivers: drivers,
                snapshots: snapshots,
                baselineBand: bandRange,
                hrvZ: value == nil ? nil : -0.4,
                rhrZ: value == nil ? nil : 0.6,
                sleepScoreText: value == nil ? "--" : "81",
                priorStrainText: value == nil ? "--" : "42",
                isSimulated: true,
                scenarioLabel: label
            ),
            range: range,
            endingAt: endingAt,
            calendar: calendar
        )
    }

    private static var defaultObservations: [RecoveryObservation] {
        [
            RecoveryObservation(id: "hrv", title: "HRV", valueText: "42 ms", baselineText: "信号基线 · 中位数 46 ms", kind: .currentValue),
            RecoveryObservation(id: "rhr", title: "静息心率", valueText: "62 bpm", baselineText: "信号基线 · 近端均值 60 bpm", kind: .currentValue),
            RecoveryObservation(id: "respiratory", title: "呼吸率", valueText: "14 次/分", baselineText: "信号基线 · 近端均值 14 次/分", kind: .currentValue),
            RecoveryObservation(id: "spo2", title: "血氧", valueText: "97%", baselineText: nil, kind: .currentValue),
            RecoveryObservation(id: "sleep-duration", title: "昨夜睡眠时长", valueText: "7小时20分钟", baselineText: nil, kind: .currentValue)
        ]
    }

    private static func series(_ values: [Double?]) -> [DailyHealthSnapshot] {
        values.enumerated().compactMap { offset, value in
            let day = calendar.date(byAdding: .day, value: -(values.count - 1 - offset), to: endingAt) ?? endingAt
            guard value != nil else { return nil }
            var snapshot = DailyHealthSnapshot(date: day, createdAt: day)
            snapshot.recoveryScore = value
            return snapshot
        }
    }

    private static func availableFinding(
        baseline: Double,
        deviationPercent: Double?,
        trendPercent: Double,
        notable: Bool,
        current: Double? = 82,
        horizon: HealthTrendHorizon = .sevenDays,
        sampleCount: Int = 7
    ) -> HealthTrendFinding {
        let deviation = deviationPercent.map { baseline * $0 / 100 }
        return HealthTrendFinding(
            metric: .recovery,
            horizon: horizon,
            direction: trendPercent >= 3.5 ? .improving : (trendPercent <= -3.5 ? .declining : .stable),
            valueDirection: trendPercent >= 3.5 ? .rising : (trendPercent <= -3.5 ? .falling : .stable),
            assessment: .neutral,
            currentValue: current,
            currentValueFormatted: current.map { "\(Int($0))" } ?? "--",
            baselineValue: baseline,
            baselineValueFormatted: "\(Int(baseline))",
            currentDeviationValue: current.flatMap { value in deviation.map { value - baseline + $0 } },
            currentDeviationPercent: deviationPercent,
            temporalTrendDelta: baseline * trendPercent / 100,
            temporalTrendDeltaPercent: trendPercent,
            historicalPercentile: nil,
            sampleCount: sampleCount,
            requiredSampleCount: horizon.requiredSampleCount,
            isAvailable: true,
            confidence: .high,
            deviationSummary: deviationSummary(deviationPercent),
            temporalTrendSummary: trendSummary(trendPercent, horizon: horizon),
            summary: summary(deviationPercent: deviationPercent, trendPercent: trendPercent, horizon: horizon),
            isNotable: notable
        )
    }

    private static func deviationSummary(_ percent: Double?) -> String {
        guard let percent else { return "今日没有可比较的恢复分" }
        if abs(percent) < 3.5 { return "较基线基本持平" }
        if percent > 0 { return String(format: "较基线偏高 %.1f%%", percent) }
        return String(format: "较基线偏低 %.1f%%", abs(percent))
    }

    private static func trendSummary(_ percent: Double, horizon: HealthTrendHorizon) -> String {
        if abs(percent) < 3.5 { return "\(horizon.detailedTitle)整体平稳" }
        if percent > 0 { return String(format: "\(horizon.detailedTitle)中位数上升 +%.1f%%", percent) }
        return String(format: "\(horizon.detailedTitle)中位数下降 -%.1f%%", abs(percent))
    }

    private static func summary(deviationPercent: Double?, trendPercent: Double, horizon: HealthTrendHorizon) -> String {
        let trend = trendSummary(trendPercent, horizon: horizon)
        guard let deviationPercent, abs(deviationPercent) >= 5 else { return trend }
        return "\(deviationSummary(deviationPercent))，\(trend)"
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }
}

private struct RecoveryDetailV2PreviewHost: View {
    let model: RecoveryDetailV2Model
    @State private var range: DetailTimeRange

    init(model: RecoveryDetailV2Model) {
        self.model = model
        _range = State(initialValue: model.range)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                RecoveryDetailV2View(model: model, selectedRange: $range, onAskCoach: {})
                    .padding(.horizontal, VelaTheme.pagePadding)
                    .padding(.bottom, 24)
            }
            .background(VelaTheme.rhythmCanvas)
            .navigationTitle("恢复")
        }
    }
}

private struct RecoveryDetailV2InteractivePreview: View {
    @State private var range: DetailTimeRange = .week

    var body: some View {
        let model = RecoveryDetailV2Builder.make(
            source: RecoveryDetailV2Fixtures.interactiveSource,
            range: range,
            endingAt: RecoveryDetailV2Fixtures.endingAt,
            calendar: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                return calendar
            }()
        )
        NavigationStack {
            ScrollView {
                RecoveryDetailV2View(model: model, selectedRange: $range, onAskCoach: {})
                    .padding(.horizontal, VelaTheme.pagePadding)
                    .padding(.bottom, 24)
            }
            .background(VelaTheme.rhythmCanvas)
            .navigationTitle("恢复")
        }
    }
}

#Preview("模拟 · 点估计基线") {
    RecoveryDetailV2PreviewHost(model: RecoveryDetailV2Fixtures.pointBaseline)
}

#Preview("模拟 · 合同基线带") {
    RecoveryDetailV2PreviewHost(model: RecoveryDetailV2Fixtures.contractBand)
}

#Preview("模拟 · 缺失日") {
    RecoveryDetailV2PreviewHost(model: RecoveryDetailV2Fixtures.missingDays)
}

#Preview("模拟 · 基线不足") {
    RecoveryDetailV2PreviewHost(model: RecoveryDetailV2Fixtures.baselineUnavailable)
}

#Preview("模拟 · 今日无分数") {
    RecoveryDetailV2PreviewHost(model: RecoveryDetailV2Fixtures.missingScore)
}

#Preview("模拟 · 部分观测缺失") {
    RecoveryDetailV2PreviewHost(model: RecoveryDetailV2Fixtures.partialObservations)
}

#Preview("模拟 · 深色") {
    RecoveryDetailV2PreviewHost(model: RecoveryDetailV2Fixtures.contractBand)
        .preferredColorScheme(.dark)
}

#Preview("模拟 · 大字号") {
    RecoveryDetailV2PreviewHost(model: RecoveryDetailV2Fixtures.pointBaseline)
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("模拟 · 切换窗口") {
    RecoveryDetailV2InteractivePreview()
}
