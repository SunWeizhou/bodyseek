import BodySeekCore
import Charts
import SwiftUI

/// Dual-series combo chart comparing daily Strain bars against Recovery line with honest gaps.
public struct LoadRecoveryComboChart: View {
    public let days: [DailyComputedDay]
    public let height: CGFloat
    public let onSelectDate: (@MainActor (Date?) -> Void)?

    @State private var selectedDay: DailyComputedDay?

    private struct RecoverySegmentPoint: Identifiable {
        let id: String
        let segmentID: Int
        let date: Date
        let value: Int
    }

    public init(
        days: [DailyComputedDay],
        height: CGFloat = 204,
        onSelectDate: (@MainActor (Date?) -> Void)? = nil
    ) {
        self.days = days
        self.height = height
        self.onSelectDate = onSelectDate
    }

    public var body: some View {
        let ordered = days.sorted { $0.date < $1.date }
        let strainDays = ordered.filter { $0.strain.value != nil }
        let recoverySegments = buildRecoverySegments(from: ordered)

        if strainDays.count < 2 && recoverySegments.count < 2 {
            ChartEmptyPlaceholder(
                title: "暂无负荷与恢复对照数据",
                systemImage: "chart.bar.xaxis",
                height: height
            )
        } else {
            let tickDates = ChartAxisSupport.explicitTickDates(from: ordered.map(\.date), maxTicks: 4)
            let horizon: TrendHorizon = ordered.count <= 10 ? .week : (ordered.count <= 45 ? .month : .sixMonths)
            let header = headerStrings(ordered: ordered)

            VStack(alignment: .leading, spacing: 10) {
                ChartLockedReadoutHeader(
                    primaryText: header.primary,
                    secondaryText: header.secondary,
                    tint: BevelTheme.recoveryColor,
                    isLocked: selectedDay != nil,
                    onClear: selectedDay == nil ? nil : {
                        selectedDay = nil
                        onSelectDate?(nil)
                    }
                )

                HStack(spacing: 14) {
                    legendItem(color: BevelTheme.recoveryColor, label: "恢复曲线", isBar: false)
                    legendItem(color: BevelTheme.strainColor.opacity(0.65), label: "每日负荷", isBar: true)
                    Spacer()
                }

                Chart {
                    let comboBarWidth = max(2.0, min(7.0, 190.0 / CGFloat(max(1, ordered.count))))
                    ForEach(ordered) { day in
                        if let strainVal = day.strain.value {
                            let isSelected = selectedDay?.dayKey == day.dayKey
                            BarMark(
                                x: .value("日期", day.date),
                                yStart: .value("底", 0),
                                yEnd: .value("负荷", strainVal),
                                width: .fixed(comboBarWidth)
                            )
                            .cornerRadius(comboBarWidth / 2)
                            .foregroundStyle(BevelTheme.strainColor.opacity(selectedDay == nil || isSelected ? 0.34 : 0.14))
                        }
                    }

                    ForEach(recoverySegments) { pt in
                        LineMark(
                            x: .value("日期", pt.date),
                            y: .value("恢复", pt.value),
                            series: .value("段", pt.segmentID)
                        )
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.3, lineCap: .round))
                        .foregroundStyle(BevelTheme.recoveryColor)
                    }

                    if let selectedDay {
                        RuleMark(x: .value("选中日", selectedDay.date))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(BevelTheme.inkSecondary.opacity(0.65))
                        if let rec = selectedDay.recovery.value {
                            PointMark(x: .value("选中日", selectedDay.date), y: .value("恢复", rec))
                                .symbolSize(58)
                                .foregroundStyle(BevelTheme.recoveryColor)
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
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
                .chartXAxis {
                    AxisMarks(values: tickDates) { value in
                        AxisValueLabel(centered: true) {
                            if let d = value.as(Date.self) {
                                Text(ChartAxisSupport.formatAxisDate(d, horizon: horizon))
                                    .font(.caption2.monospacedDigit())
                                    .fontDesign(.rounded)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 8)
                                    .onChanged { value in
                                        selectNearest(at: value.location, ordered: ordered, proxy: proxy, geometry: geometry)
                                    }
                            )
                            .simultaneousGesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        selectNearest(at: value.location, ordered: ordered, proxy: proxy, geometry: geometry)
                                    }
                            )
                    }
                }
                .frame(height: height)
                .bodyseekSelectionHaptic(trigger: selectedDay?.dayKey)
            }
        }
    }

    private func buildRecoverySegments(from ordered: [DailyComputedDay]) -> [RecoverySegmentPoint] {
        var result: [RecoverySegmentPoint] = []
        var segmentID = 0
        var active = false
        for day in ordered {
            if let v = day.recovery.value {
                if !active {
                    segmentID += 1
                    active = true
                }
                result.append(RecoverySegmentPoint(
                    id: "\(segmentID)-\(day.dayKey.isoString)",
                    segmentID: segmentID,
                    date: day.date,
                    value: v
                ))
            } else {
                active = false
            }
        }
        return result
    }

    private func selectNearest(
        at location: CGPoint,
        ordered: [DailyComputedDay],
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let x = location.x - frame.origin.x
        guard x >= 0, x <= frame.size.width else { return }
        guard let date: Date = proxy.value(atX: x) else { return }
        let nearest = ordered.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
        if selectedDay?.dayKey != nearest?.dayKey {
            selectedDay = nearest
            BodySeekSignposts.shared.emitEvent(.chartScrub, detail: "load-recovery-combo")
            onSelectDate?(nearest?.date)
        }
    }

    private func headerStrings(ordered: [DailyComputedDay]) -> (primary: String, secondary: String) {
        if let day = selectedDay {
            let rText = day.recovery.value.map { "\($0)" } ?? "--"
            let sText = day.strain.value.map { "\($0)" } ?? "--"
            return (
                "恢复 \(rText) · 负荷 \(sText)",
                ChartAxisSupport.formatReadoutDate(day.date, horizon: .month)
            )
        }
        let recLast = ordered.last(where: { $0.recovery.value != nil })?.recovery.value.map { "\($0)" } ?? "--"
        let strLast = ordered.last(where: { $0.strain.value != nil })?.strain.value.map { "\($0)" } ?? "--"
        return ("恢复 \(recLast) · 负荷 \(strLast)", "共 \(ordered.count) 日对照")
    }

    private func legendItem(color: Color, label: String, isBar: Bool) -> some View {
        HStack(spacing: 5) {
            if isBar {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 10, height: 8)
            } else {
                Capsule()
                    .fill(color)
                    .frame(width: 14, height: 3)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(BevelTheme.inkSecondary)
        }
    }
}
