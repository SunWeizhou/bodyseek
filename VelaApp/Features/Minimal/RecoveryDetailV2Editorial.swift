import Charts
import SwiftUI

// MARK: - BodySeek / Recovery editorial presentation
//
// Drop-in alternative to RecoveryDetailV2View.
// Reuses RecoveryDetailV2Model and DetailTimeRange from the existing app.
// No HealthKit reads, scoring formulas, synthetic baselines, or persistence writes.

struct RecoveryDetailV2EditorialView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var scoreFontSize: CGFloat = 68

    let model: RecoveryDetailV2Model
    @Binding var selectedRange: DetailTimeRange
    let onAskCoach: () -> Void

    @State private var selectedDate: Date?
    @State private var showsEvidence = false

    private let recovery = VelaTheme.recoveryColor
    private let ink = VelaTheme.rhythmInk
    private let secondary = VelaTheme.rhythmInkSecondary
    private let hairline = VelaTheme.rhythmMist

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if model.isSimulated { simulationNotice }
            overview
            history
            physiologicalSignals
            interpretation
            methodNote
        }
        .padding(.top, 12)
        .padding(.bottom, 28)
        .onChange(of: selectedRange) { _, _ in
            selectedDate = nil
            showsEvidence = false
        }
    }

    // MARK: 01 — State at a glance, without another oversized card

    private var overview: some View {
        VStack(alignment: .leading, spacing: 17) {
            eyebrow("BODYSEEK  /  RECOVERY")

            Text("你今天的恢复状态")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(ink)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 24) {
                    heroNumber
                    overviewFacts
                }
                VStack(alignment: .leading, spacing: 12) {
                    heroNumber
                    overviewFacts
                }
            }

            scoreTrack

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .foregroundStyle(recovery)
                    Text("数据覆盖：\(model.coverageText)")
                    Text("·")
                    Text("证据等级：\(model.confidenceText)")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label("数据覆盖：\(model.coverageText)", systemImage: "checkmark.shield")
                    Text("证据等级：\(model.confidenceText)")
                }
            }
            .font(.system(.caption, design: .default))
            .foregroundStyle(secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let missing = model.missingSummary {
                Text(missing)
                    .font(.footnote)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("metric-detail-hero")
    }

    private var heroNumber: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(model.scoreText)
                .font(.system(size: min(scoreFontSize, 94), weight: .medium, design: .rounded))
                .tracking(-3)
                .monospacedDigit()
                .foregroundStyle(ink)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if model.scoreValue != nil {
                Text("/ 100")
                    .font(.footnote)
                    .foregroundStyle(secondary)
            }
        }
        .accessibilityLabel("今日恢复分数 \(model.scoreText)")
    }

    private var overviewFacts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.bandText)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(recovery)
            if let median = model.baselineMedianText {
                Label("窗口中位数 \(median)", systemImage: "scope")
                    .font(.subheadline)
                    .foregroundStyle(secondary)
            } else {
                Text("个人基线建立中")
                    .font(.subheadline)
                    .foregroundStyle(secondary)
            }
            if let deviation = model.deviationText {
                Text(deviation)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scoreTrack: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(recovery.opacity(0.12))
                if let score = model.scoreValue, score.isFinite {
                    Capsule()
                        .fill(recovery)
                        .frame(width: geometry.size.width * CGFloat(min(max(score, 0), 100) / 100))
                }
                if let median = model.baselineMedianValue, (0...100).contains(median) {
                    Rectangle()
                        .fill(ink)
                        .frame(width: 2, height: 16)
                        .offset(x: max(0, geometry.size.width * CGFloat(median / 100) - 1))
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 7)
        }
        .frame(height: 16)
        .accessibilityLabel("恢复分与窗口中位数对照")
        .accessibilityValue(model.deviationText ?? "当前没有足够数据进行对照")
    }

    // MARK: 02 — One continuous narrative chart with an explicit baseline

    private var history: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeading(index: "01", title: "恢复轨迹", subtitle: "与自己的历史相比，而不是与别人比较")
            rangeSelector

            if let point = selectedPoint {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(point.date.formatted(.dateTime.month().day()))
                        .foregroundStyle(secondary)
                    Text(point.value.map { "恢复 \(Int($0.rounded()))" } ?? "暂无记录")
                        .fontWeight(.semibold)
                        .foregroundStyle(ink)
                }
                .font(.subheadline)
            } else {
                Text(model.trendSummary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.observedDayCount > 0 {
                recoveryChart
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 250 : 216)
                    .accessibilityIdentifier("recovery-detail-chart")
            } else {
                ContentUnavailableView(
                    "暂无趋势读数",
                    systemImage: "chart.xyaxis.line",
                    description: Text("该时间窗口还没有可用恢复分；缺失值不会补零。")
                )
                .accessibilityIdentifier("recovery-detail-chart")
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "circle.dotted")
                Text("\(model.sampleText) · 当前窗口可见读数 \(model.observedDayCount) 天、缺失 \(model.missingDayCount) 天")
            }
            .font(.caption)
            .foregroundStyle(secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 15) {
                legendLine(color: recovery, title: "每日评分", dashed: false)
                if model.showsBaselineLine {
                    legendLine(color: secondary, title: "窗口中位数", dashed: true)
                }
                if model.baselineBand != nil {
                    Text("浅绿色带：已有基线区间")
                        .font(.caption2)
                        .foregroundStyle(secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(hairline.opacity(0.70), lineWidth: 0.75)
        }
    }

    @ViewBuilder
    private var rangeSelector: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Menu {
                ForEach(DetailTimeRange.allCases) { range in
                    Button(range.title) { selectedRange = range }
                }
            } label: {
                Label(selectedRange.title, systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
        } else {
            HStack(spacing: 6) {
                ForEach(DetailTimeRange.allCases) { range in
                    Button {
                        selectedRange = range
                    } label: {
                        Text(range.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selectedRange == range ? ink : secondary)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background {
                                if selectedRange == range {
                                    Capsule().fill(VelaTheme.rhythmCanvas)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
                }
            }
            .padding(3)
            .background(hairline.opacity(0.45), in: Capsule())
        }
    }

    private var recoveryChart: some View {
        Chart {
            if let band = model.baselineBand,
               let first = model.points.first?.date,
               let last = model.points.last?.date {
                RectangleMark(
                    xStart: .value("开始", first, unit: .day),
                    xEnd: .value("结束", last, unit: .day),
                    yStart: .value("基线下界", band.lowerBound),
                    yEnd: .value("基线上界", band.upperBound)
                )
                .foregroundStyle(recovery.opacity(0.09))
            }
            if model.showsBaselineLine, let baseline = model.baselineMedianValue {
                RuleMark(y: .value("窗口中位数", baseline))
                    .foregroundStyle(secondary.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 5]))
            }
            ForEach(Array(model.chartSegments.enumerated()), id: \.offset) { index, segment in
                if segment.count == 1, let point = segment.first, let value = point.value {
                    PointMark(x: .value("日期", point.date, unit: .day), y: .value("恢复", value))
                        .foregroundStyle(recovery)
                        .symbolSize(34)
                } else {
                    ForEach(segment) { point in
                        if let value = point.value {
                            LineMark(
                                x: .value("日期", point.date, unit: .day),
                                y: .value("恢复", value),
                                series: .value("连续观测段", index)
                            )
                            .foregroundStyle(recovery)
                            .interpolationMethod(.linear)
                            .lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
            }
            if selectedRange == .week || selectedRange == .month {
                ForEach(model.points.filter { $0.value == nil }) { point in
                    RuleMark(x: .value("缺失日期", point.date, unit: .day))
                        .foregroundStyle(secondary.opacity(0.16))
                        .lineStyle(StrokeStyle(lineWidth: 0.7, dash: [2, 5]))
                }
            }
            if let point = selectedPoint {
                RuleMark(x: .value("选中", point.date, unit: .day))
                    .foregroundStyle(secondary.opacity(0.35))
                if let value = point.value {
                    PointMark(x: .value("选中日期", point.date, unit: .day), y: .value("恢复", value))
                        .foregroundStyle(recovery)
                        .symbolSize(82)
                }
            }
        }
        .chartXScale(domain: chartDomain)
        .chartYScale(domain: 0...100)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel().foregroundStyle(secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { _ in
                AxisGridLine().foregroundStyle(hairline.opacity(0.65))
                AxisValueLabel().foregroundStyle(secondary)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedRange)
        .accessibilityLabel("恢复分数历史趋势")
        .accessibilityValue("有效观测 \(model.observedDayCount) 天，缺失 \(model.missingDayCount) 天")
    }

    private var chartDomain: ClosedRange<Date> {
        let start = model.points.first?.date ?? Date()
        let end = model.points.last?.date ?? start
        return start...end
    }

    private var selectedPoint: RecoveryDetailV2Point? {
        guard let selectedDate else { return nil }
        return model.points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    // MARK: 03 — Observations, not a wall of generic cards

    private var physiologicalSignals: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeading(index: "02", title: "身体信号", subtitle: "构成解释依据的实际观测值")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 11)], spacing: 11) {
                ForEach(Array(model.observations.prefix(2))) { observation in
                    signalTile(observation)
                }
            }
            ForEach(Array(model.observations.dropFirst(2))) { observation in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(observation.title)
                        .foregroundStyle(secondary)
                    Spacer(minLength: 6)
                    Text(observation.valueText)
                        .fontWeight(.semibold)
                        .foregroundStyle(ink)
                        .monospacedDigit()
                }
                .font(.subheadline)
                .padding(.vertical, 6)
                if let baseline = observation.baselineText {
                    Text(baseline)
                        .font(.caption2)
                        .foregroundStyle(secondary)
                }
                Divider().overlay(hairline)
            }
            Text("身体信号基线与恢复分的窗口中位数是不同统计量。")
                .font(.caption)
                .foregroundStyle(secondary)
        }
        .accessibilityIdentifier("recovery-detail-observations")
    }

    private func signalTile(_ observation: RecoveryObservation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(observation.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(secondary)
            Text(observation.valueText)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(ink)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(observation.baselineText ?? "暂无可用的基线对照")
                .font(.caption2)
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 113, alignment: .topLeading)
        .padding(15)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: 04 — One insight, then supporting evidence

    private var interpretation: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading(index: "03", title: "分析发现", subtitle: "先读结论，再检查依据")
            VStack(alignment: .leading, spacing: 14) {
                Text("统计观察")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(recovery)
                Text(model.findingText)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let candidate = model.candidateExplanation {
                    Divider().overlay(hairline)
                    Text("可能的关联")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondary)
                    Text(candidate)
                        .font(.subheadline)
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("这是候选解释，不代表已经确认因果关系。")
                        .font(.caption2)
                        .foregroundStyle(secondary)
                }

                Button {
                    showsEvidence.toggle()
                } label: {
                    HStack {
                        Text(showsEvidence ? "收起统计证据" : "查看统计证据")
                        Spacer()
                        Image(systemName: showsEvidence ? "chevron.up" : "chevron.down")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("recovery-detail-evidence-toggle")

                if showsEvidence {
                    Divider().overlay(hairline)
                    ForEach(model.evidence) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .foregroundStyle(ink)
                                Text(item.kind.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(secondary)
                            }
                            Spacer(minLength: 8)
                            Text(item.valueText)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundStyle(ink)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(recovery.opacity(0.75))
                    .frame(width: 3)
                    .padding(.vertical, 14)
                .accessibilityHidden(true)
            }

            Button(action: onAskCoach) {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                    Text("让 Coach 解释这些变化")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityIdentifier("recovery-detail-finding")
    }

    private var methodNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("关于这些数字")
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondary)
            Text(model.baselineBand == nil
                 ? "虚线代表当前时间窗口的中位数；没有经过数据合同确认的区间时，不绘制基线带。"
                 : "浅色区域是数据合同提供的参考带，不代表临床正常范围。")
            Text("趋势为描述性统计，不代表显著性检验；缺失日不插值或补零。算法版本：\(model.algorithmVersion)")
        }
        .font(.caption2)
        .foregroundStyle(secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var simulationNotice: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("模拟数据 · 非真实 Apple Health 记录", systemImage: "testtube.2")
                .font(.caption.weight(.semibold))
            if let scenario = model.scenarioLabel {
                Text(scenario).font(.caption2)
            }
        }
        .foregroundStyle(ink)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmMist.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }

    private func eyebrow(_ title: String) -> some View {
        Text(title)
            .font(.system(.caption2, design: .monospaced, weight: .semibold))
            .tracking(1.5)
            .foregroundStyle(secondary)
    }

    private func sectionHeading(index: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(index)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(recovery)
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(ink)
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(secondary)
        }
    }

    private func legendLine(color: Color, title: String, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            if dashed {
                HStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        Capsule().fill(color).frame(width: 4, height: 1)
                    }
                }
            } else {
                Capsule().fill(color).frame(width: 16, height: 3)
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(secondary)
        }
    }
}

// MARK: - Visual regression only: source is labeled as simulated.
private struct RecoveryDetailV2EditorialPreviewHost: View {
    @State private var selectedRange: DetailTimeRange = .week

    private var visualModel: RecoveryDetailV2Model {
        var source = RecoveryDetailV2Fixtures.interactiveSource
        source.baselineBand = 68...80 // Simulated, explicitly labeled.
        return RecoveryDetailV2Builder.make(
            source: source,
            range: selectedRange,
            endingAt: RecoveryDetailV2Fixtures.endingAt
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                RecoveryDetailV2EditorialView(
                    model: visualModel,
                    selectedRange: $selectedRange,
                    onAskCoach: {}
                )
                .padding(.horizontal, VelaTheme.pagePadding)
            }
            .background(VelaTheme.rhythmCanvas)
            .navigationTitle("恢复")
        }
    }
}

#Preview("BodySeek Recovery · Editorial") {
    RecoveryDetailV2EditorialPreviewHost()
}
