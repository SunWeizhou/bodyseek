import BodySeekCore
import Charts
import SwiftUI

/// Circadian body-battery recharge/discharge curve rendered via native Swift Charts.
public struct EnergyAreaChart: View {
    public let curve: [EnergyCurvePoint]
    public let height: CGFloat
    public let interactive: Bool

    @State private var rawSelectedDate: Date?
    @State private var selectedPoint: EnergyCurvePoint?

    public init(curve: [EnergyCurvePoint], height: CGFloat = 38, interactive: Bool = false) {
        self.curve = curve
        self.height = height
        self.interactive = interactive
    }

    public var body: some View {
        let sorted = curve.sorted { $0.hour < $1.hour }
        if sorted.count < 2 {
            if interactive {
                ChartEmptyPlaceholder(
                    title: "暂无昼夜能量充放电曲线",
                    systemImage: "bolt.fill",
                    height: max(120, height)
                )
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(BevelTheme.scoreTrack)
                    .frame(height: height)
            }
        } else {
            let tickDates = ChartAxisSupport.explicitTickDates(from: sorted.map(\.date), maxTicks: 4)
            let peakPoint = sorted.max(by: { $0.value < $1.value })

            VStack(alignment: .leading, spacing: interactive ? 10 : 0) {
                if interactive {
                    ChartLockedReadoutHeader(
                        primaryText: selectedPoint.map { "\($0.value)%" } ?? (sorted.last.map { "\($0.value)% 当前" } ?? "--"),
                        secondaryText: selectedPoint.map {
                            "\(ChartAxisSupport.formatHour($0.date)) · 选定"
                        } ?? (peakPoint.map { "峰值 \($0.value)% (\(ChartAxisSupport.formatHour($0.date)))" } ?? ""),
                        tint: BevelTheme.energyColor,
                        isLocked: selectedPoint != nil,
                        onClear: selectedPoint == nil ? nil : {
                            rawSelectedDate = nil
                            selectedPoint = nil
                        }
                    )
                }

                let chart = Chart {
                    if interactive {
                        RuleMark(y: .value("平衡线", 50))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(BevelTheme.inkSecondary.opacity(0.35))
                    }

                    ForEach(sorted) { pt in
                        AreaMark(
                            x: .value("时刻", pt.date),
                            y: .value("能量", pt.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [BevelTheme.energyColor.opacity(0.28), BevelTheme.energyColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("时刻", pt.date),
                            y: .value("能量", pt.value)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.1, lineCap: .round))
                        .foregroundStyle(BevelTheme.energyColor)
                    }

                    if interactive, let selectedPoint {
                        RuleMark(x: .value("选中时刻", selectedPoint.date))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(BevelTheme.energyColor.opacity(0.75))
                            .annotation(
                                position: .top,
                                spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                ChartSelectionCallout(
                                    valueText: "\(selectedPoint.value)%",
                                    subtitleText: ChartAxisSupport.formatHour(selectedPoint.date),
                                    tint: BevelTheme.energyColor
                                )
                            }
                    }

                    if let active = selectedPoint ?? (interactive ? sorted.last : nil) {
                        PointMark(
                            x: .value("时刻", active.date),
                            y: .value("能量", active.value)
                        )
                        .symbol {
                            Circle()
                                .fill(BevelTheme.energyColor)
                                .overlay(Circle().strokeBorder(BevelTheme.card, lineWidth: 1.8))
                                .frame(width: selectedPoint != nil ? 10 : 8, height: selectedPoint != nil ? 10 : 8)
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis(interactive ? .automatic : .hidden)
                .chartYAxis {
                    if interactive {
                        AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(BevelTheme.hairline.opacity(0.7))
                            AxisValueLabel {
                                if let v = value.as(Int.self) {
                                    Text("\(v)")
                                        .font(.caption2.monospacedDigit())
                                        .fontDesign(.rounded)
                                        .foregroundStyle(BevelTheme.inkSecondary)
                                }
                            }
                        }
                    }
                }
                .chartXAxis(interactive ? .automatic : .hidden)
                .chartXAxis {
                    if interactive {
                        AxisMarks(values: tickDates) { value in
                            AxisValueLabel(centered: true) {
                                if let d = value.as(Date.self) {
                                    Text(ChartAxisSupport.formatHour(d))
                                        .font(.caption2.monospacedDigit())
                                        .fontDesign(.rounded)
                                        .foregroundStyle(BevelTheme.inkSecondary)
                                }
                            }
                        }
                    }
                }

                Group {
                    if interactive {
                        chart
                            .chartXSelection(value: $rawSelectedDate)
                            .onChange(of: rawSelectedDate) { _, newValue in
                                handleSelectionChange(newValue, sorted: sorted)
                            }
                    } else {
                        chart
                    }
                }
                .frame(height: height)
                .bodyseekSelectionHaptic(trigger: selectedPoint?.id)
                .accessibilityChartDescriptor(
                    NumericSeriesAXDescriptor(
                        title: "昼夜能量充放电曲线",
                        summary: peakPoint.map { "峰值 \($0.value)%" } ?? "能量分布",
                        points: sorted.map { (ChartAxisSupport.formatHour($0.date), Double($0.value)) },
                        yAxisTitle: "能量%",
                        yRange: 0...100
                    )
                )
            }
        }
    }

    private func handleSelectionChange(_ date: Date?, sorted: [EnergyCurvePoint]) {
        guard let date else {
            selectedPoint = nil
            return
        }
        let nearest = sorted.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
        if selectedPoint?.id != nearest?.id {
            selectedPoint = nearest
            BodySeekSignposts.shared.emitEvent(.chartScrub, detail: "energy-curve")
        }
    }
}
