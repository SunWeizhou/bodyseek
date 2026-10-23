import SwiftUI
import Charts

/// Full-width overview with a shared 0–100 scale. Canvas keeps five charts
/// lightweight while scrolling; dates and values remain in their original slots.
struct TrendsOverviewChart: View {
    let series: TrendsMetricSeries
    var tint: Color = VelaTheme.rhythmInk
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var timeDomain: ClosedRange<Date> {
        let start = series.points.first?.date ?? series.selectedDay
        let end = series.points.last?.date ?? series.selectedDay
        return start...max(end, start.addingTimeInterval(1))
    }

    private var axisDates: [Date] {
        let start = timeDomain.lowerBound
        let end = timeDomain.upperBound
        return [start, start.addingTimeInterval(end.timeIntervalSince(start) / 2), end]
    }

    var body: some View {
        let observed = series.points.filter { $0.value != nil }
        let segments = series.nonMissingSegments
        let domain = timeDomain
        let plotHeight: CGFloat = dynamicTypeSize.isAccessibilitySize ? 88 : 58

        Grid(horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Canvas { context, size in
                    let inset: CGFloat = 4
                    let plotWidth = max(0, size.width - inset * 2)
                    let plotHeight = max(0, size.height - inset * 2)
                    let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
                    func position(date: Date, value: Double) -> CGPoint {
                        CGPoint(
                            x: inset + CGFloat(date.timeIntervalSince(domain.lowerBound) / span) * plotWidth,
                            y: inset + CGFloat(1 - value / 100) * plotHeight
                        )
                    }

                    if let band = series.baselineBand {
                        let top = position(date: domain.lowerBound, value: min(100, band.upperBound)).y
                        let bottom = position(date: domain.upperBound, value: max(0, band.lowerBound)).y
                        context.fill(
                            Path(CGRect(x: inset, y: top, width: plotWidth, height: max(0, bottom - top))),
                            with: .color(VelaTheme.rangeBand.opacity(0.65))
                        )
                    }
                    for value in [0.0, 50, 100] {
                        let y = position(date: domain.lowerBound, value: value).y
                        var gridline = Path()
                        gridline.move(to: CGPoint(x: 0, y: y))
                        gridline.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(gridline, with: .color(VelaTheme.rhythmInkSecondary.opacity(0.18)),
                                       style: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                    }
                    for segment in segments {
                        var line = Path()
                        for (index, point) in segment.enumerated() {
                            guard let value = point.value else { continue }
                            let position = position(date: point.date, value: value)
                            if index == 0 { line.move(to: position) }
                            else { line.addLine(to: position) }
                        }
                        context.stroke(line, with: .color(tint),
                                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        for point in segment {
                            guard let value = point.value else { continue }
                            let isLatest = point.date == observed.last?.date
                            guard observed.count <= 14 || segment.count == 1 || isLatest else { continue }
                            let center = position(date: point.date, value: value)
                            let radius: CGFloat = isLatest ? 3 : 2
                            let dot = CGRect(x: center.x - radius, y: center.y - radius,
                                             width: radius * 2, height: radius * 2)
                            context.fill(Path(ellipseIn: dot), with: .color(tint))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: plotHeight)
                .overlay {
                    if observed.isEmpty {
                        Text("暂无评分记录")
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(VelaTheme.rhythmCanvasRaised, in: Capsule())
                    }
                }

                VStack(spacing: 0) {
                    Text("100")
                    Spacer(minLength: 0)
                    Text("50")
                    Spacer(minLength: 0)
                    Text("0")
                }
                .font(VelaTheme.caption2())
                .monospacedDigit()
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .frame(height: plotHeight)
                .fixedSize(horizontal: true, vertical: false)
            }
            GridRow {
                HStack(spacing: 0) {
                    ForEach(axisDates, id: \.self) { date in
                        if date != axisDates.first { Spacer(minLength: 0) }
                        Text(date, format: series.horizon == .threeYears
                             ? .dateTime.year().month(.twoDigits)
                             : .dateTime.month(.twoDigits).day(.twoDigits))
                    }
                }
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .lineLimit(1)
                Color.clear.frame(width: 0, height: 0)
            }
        }
        // The card has a full-size spoken summary; keep visual axis labels
        // legible without letting three ticks overlap at accessibility sizes.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // The enclosing card exposes the value, coverage and detail action.
        .accessibilityHidden(true)
    }
}

/// Small Swift Charts renderer for the Store-owned value series.  It renders
/// only contiguous non-missing runs, a supplied personal baseline band, and a
/// selected point for provenance drill-down.  It does not fetch SwiftData or
/// infer values.
struct TrendsOneMetricChart: View {
    let series: TrendsMetricSeries
    @Binding var selectedDate: Date?
    var tint: Color = VelaTheme.rhythmDeep

    var body: some View {
        Chart {
            if let baselineBand = series.baselineBand,
               let firstDate = series.points.first?.date,
               let lastDate = series.points.last?.date {
                RectangleMark(
                    xStart: .value("Baseline start", firstDate, unit: .day),
                    xEnd: .value("Baseline end", lastDate, unit: .day),
                    yStart: .value("Baseline lower", baselineBand.lowerBound),
                    yEnd: .value("Baseline upper", baselineBand.upperBound)
                )
                .foregroundStyle(tint.opacity(0.10))

                RuleMark(y: .value("Baseline lower", baselineBand.lowerBound))
                    .foregroundStyle(tint.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
                RuleMark(y: .value("Baseline upper", baselineBand.upperBound))
                    .foregroundStyle(tint.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 4]))
            }

            ForEach(Array(series.nonMissingSegments.enumerated()), id: \.offset) { index, segment in
                ForEach(segment) { point in
                    if let value = point.value {
                        LineMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Value", value),
                            series: .value("Segment", index)
                        )
                        .foregroundStyle(tint)
                        .interpolationMethod(.linear)
                    }
                }
            }

            ForEach(missingPoints, id: \.date) { point in
                RuleMark(x: .value("Missing date", point.date, unit: .day))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.22))
                    .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [2, 4]))
            }

            if let selected = selectedPoint {
                RuleMark(x: .value("Selected date", selected.date, unit: .day))
                    .foregroundStyle(tint.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if let value = selected.value {
                    PointMark(
                        x: .value("Selected point date", selected.date, unit: .day),
                        y: .value("Selected point value", value)
                    )
                    .foregroundStyle(tint)
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartPlotStyle { plotArea in
            plotArea
                .background(VelaTheme.rhythmCanvasRaised.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(height: 198)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        )
        .accessibilityLabel("\(series.metric.title)趋势图")
        .accessibilityValue(accessibilityValue)
    }

    private var selectedPoint: TrendsChartPoint? {
        guard let selectedDate else { return nil }
        return series.points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var missingPoints: [TrendsChartPoint] {
        series.points.filter { $0.value == nil }.prefix(60).map { $0 }
    }

    private var accessibilityValue: String {
        let observedCount = series.points.compactMap(\.value).count
        let missingCount = series.points.count - observedCount
        var parts = ["真实读数 \(observedCount) 个"]
        if missingCount > 0 { parts.append("\(missingCount) 个日期缺失") }
        if let baselineBand = series.baselineBand {
            parts.append("个人基线 \(Int(baselineBand.lowerBound.rounded())) 到 \(Int(baselineBand.upperBound.rounded()))")
        }
        if let selectedPoint {
            parts.append(selectedPoint.value.map { "选中 \(Int($0.rounded()))" } ?? "选中日期暂无数据")
        }
        return parts.joined(separator: "，")
    }
}
