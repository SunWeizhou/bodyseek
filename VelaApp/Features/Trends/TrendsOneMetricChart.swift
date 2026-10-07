import SwiftUI
import Charts

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
