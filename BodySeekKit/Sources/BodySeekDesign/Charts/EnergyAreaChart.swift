import BodySeekCore
import Charts
import SwiftUI

/// Circadian body-battery recharge/discharge curve rendered via native Swift Charts.
public struct EnergyAreaChart: View {
    public let curve: [EnergyCurvePoint]
    public let height: CGFloat
    public let interactive: Bool

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
                            "\(ChartAxisSupport.formatHour($0.date)) · 已锁读数"
                        } ?? (peakPoint.map { "峰值 \($0.value)% (\(ChartAxisSupport.formatHour($0.date)))" } ?? ""),
                        tint: BevelTheme.energyColor,
                        isLocked: selectedPoint != nil,
                        onClear: selectedPoint == nil ? nil : { selectedPoint = nil }
                    )
                }

                Chart {
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

                    if let active = selectedPoint ?? (interactive ? sorted.last : nil) {
                        PointMark(
                            x: .value("时刻", active.date),
                            y: .value("能量", active.value)
                        )
                        .symbolSize(selectedPoint != nil ? 64 : 36)
                        .foregroundStyle(BevelTheme.energyColor)
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
                .chartOverlay { proxy in
                    if interactive {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 8)
                                        .onChanged { value in
                                            selectNearest(at: value.location, sorted: sorted, proxy: proxy, geometry: geometry)
                                        }
                                )
                                .simultaneousGesture(
                                    SpatialTapGesture()
                                        .onEnded { value in
                                            selectNearest(at: value.location, sorted: sorted, proxy: proxy, geometry: geometry)
                                        }
                                )
                        }
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

    private func selectNearest(
        at location: CGPoint,
        sorted: [EnergyCurvePoint],
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let x = location.x - frame.origin.x
        guard x >= 0, x <= frame.size.width else { return }
        guard let target: Date = proxy.value(atX: x) else { return }
        let nearest = sorted.min(by: { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) })
        if selectedPoint?.id != nearest?.id {
            selectedPoint = nearest
            BodySeekSignposts.shared.emitEvent(.chartScrub, detail: "energy-curve")
        }
    }
}
