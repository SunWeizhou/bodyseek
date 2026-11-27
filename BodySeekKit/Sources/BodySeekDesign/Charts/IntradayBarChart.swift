import BodySeekCore
import Charts
import SwiftUI

/// 24-hour autonomic stress bar chart with workout-excluded visual marking and native `.chartXSelection`.
public struct IntradayBarChart: View {
    public let bins: [StressTimelineBin]
    public let excludedHours: Set<Int>
    public let height: CGFloat
    public let interactive: Bool

    @State private var rawSelectedHour: Double?
    @State private var selectedBin: StressTimelineBin?

    public init(
        bins: [StressTimelineBin],
        excludedHours: Set<Int> = [],
        height: CGFloat = 38,
        interactive: Bool = false
    ) {
        self.bins = bins
        self.excludedHours = excludedHours
        self.height = height
        self.interactive = interactive
    }

    public var body: some View {
        let sorted = bins.sorted { $0.hour < $1.hour }
        if sorted.isEmpty {
            if interactive {
                ChartEmptyPlaceholder(
                    title: "暂无日内压力分时采样",
                    systemImage: "waveform.path.ecg",
                    height: max(120, height)
                )
            } else {
                RoundedRectangle(cornerRadius: BSRadius.s, style: .continuous)
                    .fill(BevelTheme.scoreTrack)
                    .frame(height: height)
            }
        } else {
            let activeColor = selectedBin.map { color(for: $0) } ?? BevelTheme.stressColor
            let barWidth: CGFloat = interactive ? 8.0 : 4.2

            VStack(alignment: .leading, spacing: interactive ? 10 : 0) {
                if interactive {
                    ChartLockedReadoutHeader(
                        primaryText: headerPrimary(sorted: sorted),
                        secondaryText: headerSecondary(sorted: sorted),
                        tint: activeColor,
                        isLocked: selectedBin != nil,
                        onClear: selectedBin == nil ? nil : {
                            rawSelectedHour = nil
                            selectedBin = nil
                        }
                    )
                }

                let chart = Chart {
                    ForEach(sorted) { bin in
                        let hourVal = Double(bin.hour)
                        let isExcluded = excludedHours.contains(bin.hour)
                        let isSelected = selectedBin?.hour == bin.hour

                        if isExcluded {
                            RectangleMark(
                                xStart: .value("起", hourVal - 0.38),
                                xEnd: .value("止", hourVal + 0.38),
                                yStart: .value("底", 0),
                                yEnd: .value("顶", 100)
                            )
                            .foregroundStyle(Color.secondary.opacity(BSOpacity.faint))
                        } else {
                            BarMark(
                                x: .value("小时", hourVal),
                                yStart: .value("底", 0),
                                yEnd: .value("顶", max(5, bin.value)),
                                width: .fixed(barWidth)
                            )
                            .cornerRadius(barWidth / 2)
                            .foregroundStyle(selectedBin == nil || isSelected ? color(for: bin) : BSColor.dimmed)
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXScale(domain: -0.6...23.6)
                .chartYAxis(interactive ? .automatic : .hidden)
                .chartYAxis {
                    if interactive {
                        AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: BSChartStroke.grid))
                                .foregroundStyle(BSColor.separator)
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
                        AxisMarks(values: [0.0, 6.0, 12.0, 18.0]) { value in
                            AxisValueLabel(centered: true) {
                                if let h = value.as(Double.self) {
                                    Text(String(format: "%02d:00", Int(h.rounded())))
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
                            .chartXSelection(value: $rawSelectedHour)
                            .onChange(of: rawSelectedHour) { _, newValue in
                                handleSelectionChange(newValue, sorted: sorted)
                            }
                    } else {
                        chart
                    }
                }
                .frame(height: height)
                .bodyseekSelectionHaptic(trigger: selectedBin?.hour)
                .accessibilityChartDescriptor(
                    NumericSeriesAXDescriptor(
                        title: "24 小时压力节律",
                        summary: excludedHours.isEmpty ? "全天分时自主神经负荷" : "含运动排除区间",
                        points: sorted.map { (String(format: "%02d:00", $0.hour), Double($0.value)) },
                        yAxisTitle: "压力",
                        yRange: 0...100
                    )
                )
            }
        }
    }

    private func handleSelectionChange(_ hourValue: Double?, sorted: [StressTimelineBin]) {
        guard let hourValue else { return }
        let nearest = sorted.min(by: { abs(Double($0.hour) - hourValue) < abs(Double($1.hour) - hourValue) })
        if selectedBin?.hour != nearest?.hour {
            selectedBin = nearest
            BodySeekSignposts.shared.emitEvent(.chartScrub, detail: "intraday-stress")
        }
    }

    /// 单色柱：高度表示强度，不再按档位换色。
    private func color(for bin: StressTimelineBin) -> Color {
        BSColor.stress
    }

    private func levelLabel(_ level: StressLevel) -> String {
        switch level {
        case .rest: "放松"
        case .low: "轻度"
        case .medium: "适中"
        case .elevated: "偏高"
        }
    }

    private func headerPrimary(sorted: [StressTimelineBin]) -> String {
        if let selected = selectedBin {
            if excludedHours.contains(selected.hour) {
                return String(format: "%02d:00 · 运动排除", selected.hour)
            }
            return "\(selected.value) · \(levelLabel(selected.level))"
        }
        let nonExcluded = sorted.filter { !excludedHours.contains($0.hour) }
        guard !nonExcluded.isEmpty else { return "--" }
        let avg = nonExcluded.reduce(0) { $0 + $1.value } / nonExcluded.count
        return "日均 \(avg)"
    }

    private func headerSecondary(sorted: [StressTimelineBin]) -> String {
        if let selected = selectedBin {
            let endHour = min(24, selected.hour + max(1, selected.spanHours))
            return String(format: "%02d:00–%02d:00（%@）", selected.hour, endHour, selected.isEstimated ? "估算窗口" : "实测")
        }
        let unitLabel = sorted.first?.spanHours == 1 ? "每窗 1h" : "每窗 \(sorted.first?.spanHours ?? 2)h 估算"
        if excludedHours.isEmpty {
            return "\(sorted.count) 个时段窗（\(unitLabel)）"
        }
        return "\(sorted.count) 个时段窗 · 已排除 \(excludedHours.count)h 运动窗"
    }
}
