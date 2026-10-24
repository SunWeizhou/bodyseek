import SwiftUI
import Charts

enum DetailTimeRange: String, CaseIterable, Identifiable {
    case week, month, halfYear, threeYears
    
    var id: String { rawValue }
    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .halfYear: return 180
        case .threeYears: return 1095
        }
    }
    var title: String {
        switch self {
        case .week: return "7天"
        case .month: return "30天"
        case .halfYear: return "6个月"
        case .threeYears: return "3年"
        }
    }

    var trendHorizon: HealthTrendHorizon? {
        switch self {
        case .week: return .sevenDays
        case .month: return .thirtyDays
        case .halfYear: return .sixMonths
        case .threeYears: return .threeYears
        }
    }
}

struct ChartPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

private struct MetricChartSegment: Identifiable {
    let points: [ChartPoint]
    var id: Date { points[0].id }
}

enum VelaChartSegmentation {
    static func segments(points: [ChartPoint], maximumGap: TimeInterval) -> [[ChartPoint]] {
        let sorted = points.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [] }

        return sorted.dropFirst().reduce(into: [[sorted[0]]]) { segments, point in
            guard let last = segments.last?.last else { return }
            if point.date.timeIntervalSince(last.date) > maximumGap {
                segments.append([point])
            } else {
                segments[segments.count - 1].append(point)
            }
        }
    }
}

struct MetricChartSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let metric: VelaMetricDetailView.MetricType
    let isSleep: Bool
    let points: [ChartPoint]
    let isBarChart: Bool
    let metricColor: Color
    @Binding var selectedRange: DetailTimeRange
    @Binding var rawSelectedDate: Date?
    let displayDateText: String
    let dynamicValueText: String
    let metricSubtitle: String
    var baselineValue: Double? = nil
    var targetRange: ClosedRange<Double>? = nil
    var isSimulated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Top Bar: Range Picker & Active Date
            HStack(spacing: 8) {
                rangePicker
                Spacer()

                if rawSelectedDate != nil {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(metricColor)
                            .frame(width: 6, height: 6)
                        Text(displayDateText)
                            .font(.system(.caption, design: .default, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(metricColor.opacity(0.12)))
                }

                if isSimulated {
                    Text("模拟数据")
                        .font(VelaTheme.caption2().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmWarm)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(VelaTheme.rhythmWarm.opacity(0.12), in: Capsule())
                        .accessibilityLabel("模拟数据，不是 Apple 健康记录")
                }
            }
            .padding(.horizontal, 14)
            
            // Value and Status Row
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(dynamicValueText)
                        .font(.system(.largeTitle, design: .default, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(VelaTheme.rhythmInk)

                    if rawSelectedDate == nil {
                        Text(metricSubtitle)
                            .font(.system(.footnote, design: .default, weight: .semibold))
                            .foregroundStyle(metricColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(metricColor.opacity(0.12))
                            )
                    } else {
                        Text("按住滑动查看历史")
                            .font(.system(.caption2, design: .default, weight: .medium))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            
            // The Swift Chart!
            if points.isEmpty {
                VelaStateCard(
                    state: .calibrating,
                    message: "这个时间范围内还没有真实读数。"
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            } else {
                Chart {
                    let unit: Calendar.Component = selectedRange == .threeYears ? .month : .day

                    if points.count >= 3,
                       let targetRange,
                       let firstDate = points.first?.date,
                       let lastDate = points.last?.date {
                        RectangleMark(
                            xStart: .value("Target start", firstDate, unit: unit),
                            xEnd: .value("Target end", lastDate, unit: unit),
                            yStart: .value("Target lower", targetRange.lowerBound),
                            yEnd: .value("Target upper", targetRange.upperBound)
                        )
                        .foregroundStyle(metricColor.opacity(0.08))
                    }

                    if let effectiveBaseline {
                        RuleMark(y: .value("Personal baseline", effectiveBaseline))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .trailing, alignment: .trailing) {
                                Text("基线")
                                    .font(VelaTheme.caption2().weight(.semibold))
                                    .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.8))
                                    .padding(.trailing, 2)
                            }
                    }

                    ForEach(chartSegments) { segment in
                        if segment.points.count == 1, let pt = segment.points.first {
                            PointMark(
                                x: .value("Date", pt.date, unit: unit),
                                y: .value("Value", pt.value)
                            )
                            .foregroundStyle(metricColor)
                            .symbolSize(42)
                        } else {
                            ForEach(segment.points) { pt in
                                if isBarChart {
                                    BarMark(
                                        x: .value("Date", pt.date, unit: unit),
                                        y: .value("Value", pt.value)
                                    )
                                    .foregroundStyle(metricColor.gradient)
                                    .cornerRadius(4)
                                } else {
                                    LineMark(
                                        x: .value("Date", pt.date, unit: unit),
                                        y: .value("Value", pt.value),
                                        series: .value("Segment", segment.id)
                                    )
                                    .foregroundStyle(metricColor)
                                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                    .interpolationMethod(.linear)

                                    AreaMark(
                                        x: .value("Date", pt.date, unit: unit),
                                        y: .value("Value", pt.value),
                                        series: .value("Area segment", segment.id)
                                    )
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [metricColor.opacity(0.24), metricColor.opacity(0.01)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .interpolationMethod(.linear)
                                }
                            }
                        }
                    }
                    
                    // Scrub vertical line and dot overlay
                    if let selectedPoint = points.min(by: {
                        guard let rawSelectedDate else { return false }
                        return abs($0.date.timeIntervalSince(rawSelectedDate)) < abs($1.date.timeIntervalSince(rawSelectedDate))
                    }), rawSelectedDate != nil {
                        RuleMark(
                            x: .value("SelectedDate", selectedPoint.date, unit: unit)
                        )
                        .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        
                        PointMark(
                            x: .value("SelectedDatePoint", selectedPoint.date, unit: unit),
                            y: .value("SelectedValuePoint", selectedPoint.value)
                        )
                        .foregroundStyle(metricColor)
                        .symbolSize(88)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(VelaTheme.rhythmMist.opacity(0.6))
                        AxisValueLabel()
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(VelaTheme.rhythmMist.opacity(0.6))
                        AxisValueLabel()
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
                .chartXSelection(value: $rawSelectedDate)
                .frame(height: 175)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .accessibilityLabel("\(metricSubtitle)趋势图，共\(points.count)个真实读数")
                .accessibilityValue(dynamicValueText)
                .onChange(of: rawSelectedDate) { oldValue, newValue in
                    if newValue != nil && oldValue == nil {
                        VelaHaptic.selection()
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        )
    }

    @ViewBuilder
    private var rangePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Menu {
                ForEach(DetailTimeRange.allCases) { range in
                    Button {
                        select(range)
                    } label: {
                        Label(range.title, systemImage: selectedRange == range ? "checkmark" : "")
                    }
                }
            } label: {
                Label(selectedRange.title, systemImage: "calendar")
                    .font(VelaTheme.subheadline().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .padding(.horizontal, 12)
                    .frame(minHeight: VelaTheme.minimumHitTarget)
                    .background(VelaTheme.rhythmMist.opacity(0.42), in: Capsule(style: .continuous))
            }
            .accessibilityLabel("趋势时间范围")
            .accessibilityValue(selectedRange.title)
        } else {
            HStack(spacing: 3) {
                ForEach(DetailTimeRange.allCases) { range in
                    Button {
                        select(range)
                    } label: {
                        Text(range.title)
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundStyle(selectedRange == range ? VelaTheme.rhythmInk : VelaTheme.rhythmInkSecondary)
                            .padding(.horizontal, 9)
                            .frame(minHeight: VelaTheme.minimumHitTarget)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedRange == range ? VelaTheme.rhythmCanvasRaised : Color.clear)
                            )
                    }
                    .buttonStyle(.cardPress)
                    .accessibilityAddTraits(selectedRange == range ? .isSelected : [])
                }
            }
            .padding(3)
            .background(VelaTheme.rhythmMist.opacity(0.4), in: Capsule(style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("时间区间")
        }
    }

    private func select(_ range: DetailTimeRange) {
        guard selectedRange != range else { return }
        selectedRange = range
        rawSelectedDate = nil
        VelaHaptic.selection()
    }

    private var effectiveBaseline: Double? {
        guard points.count >= 3 else { return nil }
        return baselineValue
    }

    private var chartSegments: [MetricChartSegment] {
        let maximumGap: TimeInterval = selectedRange == .threeYears
            ? 46 * 24 * 60 * 60
            : 36 * 60 * 60
        return VelaChartSegmentation.segments(points: points, maximumGap: maximumGap)
            .filter { !$0.isEmpty }
            .map(MetricChartSegment.init(points:))
    }
}
