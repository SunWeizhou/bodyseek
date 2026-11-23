import BodySeekCore
import Charts
import SwiftUI

/// Native Swift Charts Split-Conformal forecast fan chart showing trailing 14-day observations + tomorrow's point & 80%/90% calibrated intervals.
/// Expects `historyPoints` in the target's native unit (`ms`, `bpm`, or `0...1` ratio for `sleep_efficiency`).
public struct ForecastFanChart: View {
    public let target: PersonalForecastTargetResult
    public let historyPoints: [(date: Date, value: Double)]
    public let targetDate: Date
    public let tint: Color
    public let height: CGFloat

    @State private var rawSelectedDate: Date?
    @State private var selectedItem: SelectablePoint?

    private struct PlotPoint: Identifiable {
        let id: String
        let date: Date
        let value: Double
    }

    private struct SelectablePoint: Equatable {
        let id: String
        let date: Date
        let valueText: String
        let subtitleText: String
    }

    public init(
        target: PersonalForecastTargetResult,
        historyPoints: [(date: Date, value: Double)],
        targetDate: Date,
        tint: Color,
        height: CGFloat = 196
    ) {
        self.target = target
        self.historyPoints = historyPoints
        self.targetDate = targetDate
        self.tint = tint
        self.height = height
    }

    private var isPercent: Bool {
        target.name == "sleep_efficiency"
    }

    private var unitLabel: String {
        isPercent ? "%" : target.unit
    }

    private func displayScale(_ value: Double) -> Double {
        isPercent ? value * 100.0 : value
    }

    private func formatValue(_ scaledValue: Double) -> String {
        if isPercent {
            return String(format: "%.1f%%", scaledValue)
        }
        return String(format: "%.1f %@", scaledValue, target.unit)
    }

    public var body: some View {
        let history: [PlotPoint] = historyPoints
            .filter { $0.value.isFinite }
            .sorted { $0.date < $1.date }
            .suffix(14)
            .enumerated()
            .map { idx, item in
                PlotPoint(id: "hist-\(idx)", date: item.date, value: displayScale(item.value))
            }

        let predPoint = displayScale(target.point)
        let low80 = displayScale(target.interval80Low)
        let high80 = displayScale(target.interval80High)
        let low90 = displayScale(target.interval90Low)
        let high90 = displayScale(target.interval90High)

        let allY = history.map(\.value) + [predPoint, low90, high90]
        let yDomain = ChartAxisSupport.smartYDomain(
            values: allY,
            clampRange: isPercent ? 40...100 : 0...250,
            minSpan: isPercent ? 8 : 8
        )
        let yTicks = ChartAxisSupport.yAxisTicks(for: yDomain, count: 3)

        let firstX = (history.first?.date ?? targetDate.addingTimeInterval(-7 * 86_400)).addingTimeInterval(-12 * 3600)
        let lastX = targetDate.addingTimeInterval(20 * 3600)
        let xDomain = firstX...max(lastX, firstX.addingTimeInterval(86_400))
        let tickDates = ChartAxisSupport.explicitTickDates(from: history.map(\.date) + [targetDate], maxTicks: 4)
        let selectable = buildSelectables(history: history, predPoint: predPoint, low80: low80, high80: high80)
        let defaultSecondary: String = isPercent
            ? String(format: "80%%区间 %.1f–%.1f%%", low80, high80)
            : String(format: "80%%区间 %.1f–%.1f %@", low80, high80, unitLabel)

        VStack(alignment: .leading, spacing: BSSpace.xs) {
            ChartLockedReadoutHeader(
                primaryText: selectedItem?.valueText ?? "明日预测 \(formatValue(predPoint))",
                secondaryText: selectedItem?.subtitleText ?? defaultSecondary,
                tint: tint,
                isLocked: selectedItem != nil,
                onClear: selectedItem == nil ? nil : {
                    rawSelectedDate = nil
                    selectedItem = nil
                }
            )

            Chart {
                ForEach(history) { pt in
                    LineMark(
                        x: .value("日期", pt.date),
                        y: .value("实测", pt.value),
                        series: .value("系列", "history")
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: BSChartStroke.data, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(tint)
                }

                if let lastHist = history.last {
                    ForEach([
                        PlotPoint(id: "conn-start", date: lastHist.date, value: lastHist.value),
                        PlotPoint(id: "conn-end", date: targetDate, value: predPoint),
                    ]) { pt in
                        LineMark(
                            x: .value("日期", pt.date),
                            y: .value("预测连线", pt.value),
                            series: .value("系列", "forecast")
                        )
                        .lineStyle(StrokeStyle(lineWidth: BSChartStroke.data, dash: BSChartStroke.estimateDash))
                        .foregroundStyle(tint)
                    }
                }

                BarMark(
                    x: .value("日期", targetDate),
                    yStart: .value("80%下界", low80),
                    yEnd: .value("80%上界", high80),
                    width: .fixed(12)
                )
                .cornerRadius(4)
                .foregroundStyle(tint.opacity(BSOpacity.disabled))

                PointMark(
                    x: .value("日期", targetDate),
                    y: .value("明日预测", predPoint)
                )
                .symbol {
                    Circle()
                        .fill(tint)
                        .overlay(Circle().strokeBorder(BSColor.surface, lineWidth: BSChartStroke.data))
                        .frame(width: BSSize.dot, height: BSSize.dot)
                }

                if let selectedItem {
                    RuleMark(x: .value("选中日", selectedItem.date))
                        .lineStyle(StrokeStyle(lineWidth: BSChartStroke.rule))
                        .foregroundStyle(BSColor.separator)
                }
            }
            .chartYScale(domain: yDomain)
            .chartXScale(domain: xDomain)
            .chartYAxis {
                AxisMarks(position: .trailing, values: yTicks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: BSChartStroke.grid))
                        .foregroundStyle(BSColor.separator)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(isPercent ? "\(Int(v.rounded()))%" : ChartAxisSupport.formatYAxisTick(v))
                                .font(.caption2.monospacedDigit())
                                .fontDesign(.rounded)
                                .foregroundStyle(BevelTheme.inkSecondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: tickDates) { value in
                    AxisValueLabel(centered: true) {
                        if let d = value.as(Date.self) {
                            let isForecastDay = Calendar.current.isDate(d, inSameDayAs: targetDate)
                            Text(isForecastDay ? "明日" : ChartAxisSupport.formatAxisDate(d, horizon: .month))
                                .font(.caption2.monospacedDigit())
                                .fontDesign(.rounded)
                                .foregroundStyle(isForecastDay ? tint : BevelTheme.inkSecondary)
                        }
                    }
                }
            }
            .chartXSelection(value: $rawSelectedDate)
            .onChange(of: rawSelectedDate) { _, newValue in
                guard let newValue else { return }
                let nearest = selectable.min {
                    abs($0.date.timeIntervalSince(newValue)) < abs($1.date.timeIntervalSince(newValue))
                }
                if selectedItem?.id != nearest?.id {
                    selectedItem = nearest
                    BodySeekSignposts.shared.emitEvent(.chartScrub, detail: "forecast-fan")
                }
            }
            .onChange(of: target.name) { _, _ in
                rawSelectedDate = nil
                selectedItem = nil
            }
            .frame(height: height)
            .bodyseekSelectionHaptic(trigger: selectedItem?.id)

            HStack(spacing: BSSpace.s) {
                HStack(spacing: BSSpace.xxs) {
                    Capsule().fill(tint).frame(width: BSSize.dot, height: BSSize.dot)
                    Text("近 14 日实测")
                }
                HStack(spacing: BSSpace.xxs) {
                    RoundedRectangle(cornerRadius: BSRadius.s, style: .continuous)
                        .fill(tint.opacity(BSOpacity.disabled))
                        .frame(width: BSSize.dot, height: BSSize.dot)
                    Text("80% 共形区间")
                }
                Spacer()
                Text("预测 \(formatValue(predPoint))")
                    .fontWeight(.semibold)
                    .foregroundStyle(tint)
            }
            .font(.caption2)
            .foregroundStyle(BevelTheme.inkSecondary)
        }
    }

    private func buildSelectables(
        history: [PlotPoint],
        predPoint: Double,
        low80: Double,
        high80: Double
    ) -> [SelectablePoint] {
        var items = history.map { pt in
            SelectablePoint(
                id: pt.id,
                date: pt.date,
                valueText: formatValue(pt.value),
                subtitleText: ChartAxisSupport.formatReadoutDate(pt.date, horizon: .month)
            )
        }
        let intervalSub = isPercent
            ? String(format: "明日预测 · 80%% %.1f–%.1f%%", low80, high80)
            : String(format: "明日预测 · 80%% %.1f–%.1f %@", low80, high80, unitLabel)
        items.append(
            SelectablePoint(
                id: "forecast-target",
                date: targetDate,
                valueText: formatValue(predPoint),
                subtitleText: intervalSub
            )
        )
        return items
    }
}
