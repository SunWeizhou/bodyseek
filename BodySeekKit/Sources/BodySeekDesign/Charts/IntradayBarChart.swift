import BodySeekCore
import Charts
import SwiftUI

/// 24-hour autonomic stress bar chart with workout-excluded visual marking.
public struct IntradayBarChart: View {
    public let bins: [StressTimelineBin]
    public let excludedHours: Set<Int>
    public let height: CGFloat
    public let interactive: Bool

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
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(BevelTheme.scoreTrack)
                    .frame(height: height)
            }
        } else {
            VStack(alignment: .leading, spacing: interactive ? 10 : 0) {
                if interactive {
                    ChartLockedReadoutHeader(
                        primaryText: headerPrimary(sorted: sorted),
                        secondaryText: headerSecondary(sorted: sorted),
                        tint: selectedBin.map(color(for:)) ?? BevelTheme.stressColor,
                        isLocked: selectedBin != nil,
                        onClear: selectedBin == nil ? nil : { selectedBin = nil }
                    )
                }

                Chart {
                    ForEach(sorted) { bin in
                        let isExcluded = excludedHours.contains(bin.hour)
                        let isSelected = selectedBin?.hour == bin.hour

                        BarMark(
                            x: .value("小时", bin.hour),
                            y: .value("压力", isExcluded ? 0 : max(4, bin.value)),
                            width: .ratio(interactive ? 0.68 : 0.72)
                        )
                        .cornerRadius(interactive ? 3 : 2)
                        .foregroundStyle(
                            isExcluded
                                ? BevelTheme.inkSecondary.opacity(0.22)
                                : color(for: bin).opacity(selectedBin == nil || isSelected ? 0.92 : 0.4)
                        )

                        if isExcluded {
                            RectangleMark(
                                xStart: .value("起", Double(bin.hour) - 0.42),
                                xEnd: .value("止", Double(bin.hour) + 0.42),
                                yStart: .value("下", 0),
                                yEnd: .value("上", 100)
                            )
                            .foregroundStyle(BevelTheme.inkSecondary.opacity(0.14))
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXScale(domain: -0.5...23.5)
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
                        AxisMarks(values: [0, 6, 12, 18]) { value in
                            AxisValueLabel {
                                if let h = value.as(Int.self) {
                                    Text(String(format: "%02d:00", h))
                                        .font(.caption2.monospacedDigit())
                                        .fontDesign(.rounded)
                                        .foregroundStyle(BevelTheme.inkSecondary)
                                }
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    if interactive {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 8)
                                        .onChanged { value in
                                            selectHour(at: value.location, sorted: sorted, proxy: proxy, geometry: geometry)
                                        }
                                )
                                .simultaneousGesture(
                                    SpatialTapGesture()
                                        .onEnded { value in
                                            selectHour(at: value.location, sorted: sorted, proxy: proxy, geometry: geometry)
                                        }
                                )
                        }
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

    private func selectHour(
        at location: CGPoint,
        sorted: [StressTimelineBin],
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let x = location.x - frame.origin.x
        guard x >= 0, x <= frame.size.width else { return }
        guard let hourValue: Double = proxy.value(atX: x) else { return }
        let nearest = sorted.min(by: { abs(Double($0.hour) - hourValue) < abs(Double($1.hour) - hourValue) })
        if selectedBin?.hour != nearest?.hour {
            selectedBin = nearest
            BodySeekSignposts.shared.emitEvent(.chartScrub, detail: "intraday-stress")
        }
    }

    private func color(for bin: StressTimelineBin) -> Color {
        switch bin.level {
        case .rest: BevelTheme.recoveryColor.opacity(0.65)
        case .low: BevelTheme.stressColor.opacity(0.55)
        case .medium: BevelTheme.energyColor
        case .elevated: BevelTheme.stressColor
        }
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
            return String(format: "%02d:00–%02d:59", selected.hour, selected.hour)
        }
        if excludedHours.isEmpty {
            return "\(sorted.count) 小时窗口"
        }
        return "\(sorted.count) 小时 · 已排除 \(excludedHours.count)h 运动窗"
    }
}
