import BodySeekCore
import Charts
import SwiftUI

/// Visual ACWR & 14-day training load dashboard card powered by Apple Swift Charts.
public struct TrainingLoadDashboardCard: View {
    public let load: TrainingLoadStatus
    public let recentDays: [DailyComputedDay]
    public let coachMicroInsight: String
    public let onOpenTrends: () -> Void
    public let onAskCoach: () -> Void

    @State private var rawSelectedDate: Date?
    @State private var selectedPoint: LoadBarPoint?

    private struct LoadBarPoint: Identifiable, Equatable {
        let id: String
        let date: Date
        let load: Double
        let strainScore: Int?
        let trimpScore: Double
    }

    public init(
        load: TrainingLoadStatus,
        recentDays: [DailyComputedDay],
        coachMicroInsight: String,
        onOpenTrends: @escaping () -> Void,
        onAskCoach: @escaping () -> Void
    ) {
        self.load = load
        self.recentDays = recentDays
        self.coachMicroInsight = coachMicroInsight
        self.onOpenTrends = onOpenTrends
        self.onAskCoach = onAskCoach
    }

    public var body: some View {
        let zoneTint = tint(for: load.zone)
        let points = buildBarPoints()
        let dailyBaseline = load.chronic28dWeeklyAvg > 0 ? load.chronic28dWeeklyAvg / 7.0 : nil

        BevelCard {
            VStack(alignment: .leading, spacing: 14) {
                headerRow(zoneTint: zoneTint)

                gaugeSection(zoneTint: zoneTint)

                acuteChronicTiles

                dailyLoadChartSection(points: points, dailyBaseline: dailyBaseline)

                coachInsightStrip
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-training-load-card")
    }

    private func headerRow(zoneTint: Color) -> some View {
        HStack(spacing: 8) {
            Label("训练负荷", systemImage: "flame.fill")
                .font(.headline)
                .foregroundStyle(BevelTheme.ink)

            Text(load.zone.title)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(zoneTint.opacity(0.15), in: Capsule())
                .foregroundStyle(zoneTint)

            Spacer()

            Button("查看趋势", action: onOpenTrends)
                .font(.subheadline)
                .buttonStyle(.borderless)
        }
    }

    private func gaugeSection(zoneTint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(load.acwrRatio.map { String(format: "%.2f", $0) } ?? "—")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(BevelTheme.ink)

                Text("ACWR 负荷比（7日 / 28日）")
                    .font(.caption)
                    .foregroundStyle(BevelTheme.inkSecondary)

                Spacer()
            }

            acwrSegmentedGauge(ratio: load.acwrRatio, zoneTint: zoneTint)

            Text(load.zone.note)
                .font(.caption)
                .foregroundStyle(BevelTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if load.acuteCoveredDays > 0 || load.chronicCoveredDays > 0 {
                Text("覆盖：近 7 天 \(load.acuteCoveredDays)/7 天 · 近 28 天 \(load.chronicCoveredDays)/28 天")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(BevelTheme.inkSecondary)
            }
        }
    }

    private func acwrSegmentedGauge(ratio: Double?, zoneTint: Color) -> some View {
        let minScale = 0.4
        let maxScale = 1.8
        let span = maxScale - minScale
        let sweetStartFrac = (0.8 - minScale) / span
        let sweetEndFrac = (1.32 - minScale) / span

        return VStack(spacing: 4) {
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let wLow = width * sweetStartFrac
                let wSweet = width * (sweetEndFrac - sweetStartFrac)
                let wHigh = max(0, width - wLow - wSweet)

                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(BevelTheme.energyColor.opacity(0.28))
                            .frame(width: max(4, wLow - 1), height: 8)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(BevelTheme.recoveryColor.opacity(0.36))
                            .frame(width: max(4, wSweet - 2), height: 8)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(BevelTheme.dangerColor.opacity(0.28))
                            .frame(width: max(4, wHigh - 1), height: 8)
                    }

                    if let ratio {
                        let clamped = min(maxScale, max(minScale, ratio))
                        let frac = (clamped - minScale) / span
                        let centerX = min(max(7, width * frac), max(7, width - 7))
                        Circle()
                            .fill(zoneTint)
                            .overlay(Circle().strokeBorder(BevelTheme.card, lineWidth: 2))
                            .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                            .frame(width: 14, height: 14)
                            .offset(x: centerX - 7)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 16)

            HStack {
                Text("偏低 <0.8")
                Spacer()
                Text("甜蜜推进 0.8–1.3")
                    .foregroundStyle(BevelTheme.recoveryColor)
                Spacer()
                Text("预警 >1.3")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(BevelTheme.inkSecondary)
        }
    }

    private var acuteChronicTiles: some View {
        let deltaPercent: Int? = {
            guard load.chronic28dWeeklyAvg > 1 else { return nil }
            return Int((((load.acute7dLoad - load.chronic28dWeeklyAvg) / load.chronic28dWeeklyAvg) * 100).rounded())
        }()

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("近 7 天急性负荷")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(BevelTheme.inkSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(load.acute7dLoad.rounded()))")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .fontDesign(.rounded)
                        .foregroundStyle(BevelTheme.ink)
                    if let deltaPercent {
                        let sign = deltaPercent > 0 ? "+" : ""
                        let tint: Color = deltaPercent > 32
                            ? BevelTheme.dangerColor
                            : (deltaPercent < -20 ? BevelTheme.energyColor : BevelTheme.recoveryColor)
                        Text("\(sign)\(deltaPercent)%")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tint.opacity(0.14), in: Capsule())
                            .foregroundStyle(tint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("28 天周均基线")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(BevelTheme.inkSecondary)
                Text(load.chronic28dWeeklyAvg > 0 ? "\(Int(load.chronic28dWeeklyAvg.rounded()))" : "—")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .fontDesign(.rounded)
                    .foregroundStyle(BevelTheme.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private func dailyLoadChartSection(points: [LoadBarPoint], dailyBaseline: Double?) -> some View {
        let nonZeroCount = points.filter { $0.load > 0 }.count
        if points.count < 2 || nonZeroCount == 0 {
            Text("积累更多训练负荷日后，这里会展示近 14 天每日负荷柱状走势。")
                .font(.caption)
                .foregroundStyle(BevelTheme.inkSecondary)
                .padding(.vertical, 4)
        } else {
            let maxVal = max(points.map(\.load).max() ?? 100, (dailyBaseline ?? 0) * 1.15)
            let topBound = max(60.0, ceil(maxVal * 1.16 / 10.0) * 10.0)
            let yDomain: ClosedRange<Double> = 0...topBound
            let yTicks = ChartAxisSupport.yAxisTicks(for: yDomain, count: 3)
            let tickDates = ChartAxisSupport.explicitTickDates(from: points.map(\.date), maxTicks: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("近 14 天每日负荷分布")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.inkSecondary)
                    Spacer()
                    if let dailyBaseline {
                        Text("基线虚线 \(Int(dailyBaseline.rounded()))/日")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                }

                Chart {
                    if let dailyBaseline, dailyBaseline > 0 {
                        RuleMark(y: .value("日均基线", dailyBaseline))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(BevelTheme.inkSecondary.opacity(0.5))
                    }

                    ForEach(points) { pt in
                        let isSelected = selectedPoint?.id == pt.id
                        let aboveBaseline = dailyBaseline.map { pt.load >= $0 } ?? (pt.load > 0)
                        BarMark(
                            x: .value("日期", pt.date),
                            y: .value("负荷", pt.load),
                            width: .fixed(10)
                        )
                        .cornerRadius(4)
                        .foregroundStyle(
                            BevelTheme.strainColor.opacity(
                                selectedPoint != nil
                                    ? (isSelected ? 0.95 : 0.25)
                                    : (aboveBaseline ? 0.86 : 0.40)
                            )
                        )
                    }

                    if let selectedPoint {
                        let dateStr = ChartAxisSupport.formatAxisDate(selectedPoint.date, horizon: .month)
                        let sub = selectedPoint.trimpScore > 0
                            ? "\(dateStr) · TRIMP \(Int(selectedPoint.trimpScore.rounded()))"
                            : dateStr
                        RuleMark(x: .value("选中日", selectedPoint.date))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(BevelTheme.strainColor.opacity(0.75))
                            .annotation(
                                position: .top,
                                spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                ChartSelectionCallout(
                                    valueText: "负荷 \(Int(selectedPoint.load.rounded()))",
                                    subtitleText: sub,
                                    tint: BevelTheme.strainColor
                                )
                            }
                    }
                }
                .chartYScale(domain: yDomain)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: yTicks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(BevelTheme.hairline.opacity(0.7))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(ChartAxisSupport.formatYAxisTick(v))
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
                                Text(ChartAxisSupport.formatAxisDate(d, horizon: .month))
                                    .font(.caption2.monospacedDigit())
                                    .fontDesign(.rounded)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                        }
                    }
                }
                .chartXSelection(value: $rawSelectedDate)
                .onChange(of: rawSelectedDate) { _, newValue in
                    handleSelectionChange(newValue, points: points)
                }
                .frame(height: 118)
                .bodyseekSelectionHaptic(trigger: selectedPoint?.id)
            }
        }
    }

    private var coachInsightStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BevelTheme.brand)
                    .padding(.top, 2)
                Text(coachMicroInsight)
                    .font(.caption)
                    .foregroundStyle(BevelTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onAskCoach) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    Text("问 Coach 今日训练强度")
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(BevelTheme.brandSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(BevelTheme.brand)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workout-load-ask-coach")
        }
        .padding(10)
        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func handleSelectionChange(_ date: Date?, points: [LoadBarPoint]) {
        guard let date else {
            selectedPoint = nil
            return
        }
        let nearest = points.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
        if selectedPoint?.id != nearest?.id {
            selectedPoint = nearest
            BodySeekSignposts.shared.emitEvent(.chartScrub, detail: "training-load-14d")
        }
    }

    private func buildBarPoints() -> [LoadBarPoint] {
        recentDays
            .sorted { $0.date < $1.date }
            .suffix(14)
            .map { day in
                let trimp = day.raw.workouts.compactMap { $0.heartRateZones?.trimpScore }.reduce(0, +)
                let strain = Double(day.strain.value ?? 0)
                let loadVal = trimp > 0 ? trimp : strain
                return LoadBarPoint(
                    id: day.dayKey.isoString,
                    date: day.date,
                    load: loadVal,
                    strainScore: day.strain.value,
                    trimpScore: trimp
                )
            }
    }

    private func tint(for zone: ACWRZone) -> Color {
        switch zone {
        case .sweetSpot: BevelTheme.recoveryColor
        case .highRisk: BevelTheme.dangerColor
        case .undertraining: BevelTheme.energyColor
        case .insufficientData: BevelTheme.inkSecondary
        }
    }
}
