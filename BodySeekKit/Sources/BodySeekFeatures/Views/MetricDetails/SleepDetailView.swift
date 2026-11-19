import BodySeekCore
import BodySeekDesign
import SwiftUI

public struct SleepDetailView: View {
    public let day: DailyComputedDay
    public let historyDays: [DailyComputedDay]
    public let activeChartSnapshot: ChartSeriesSnapshot
    public let sleepGoalMinutes: Int
    public let onSelectDate: @MainActor (Date?) -> Void

    public init(
        day: DailyComputedDay,
        historyDays: [DailyComputedDay],
        activeChartSnapshot: ChartSeriesSnapshot,
        sleepGoalMinutes: Int,
        onSelectDate: @escaping @MainActor (Date?) -> Void
    ) {
        self.day = day
        self.historyDays = historyDays
        self.activeChartSnapshot = activeChartSnapshot
        self.sleepGoalMinutes = sleepGoalMinutes
        self.onSelectDate = onSelectDate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BevelCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("昨夜睡眠分期阶梯", systemImage: MetricKind.sleep.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.sleepColor)
                        Spacer()
                        Text(day.sleep.subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    SleepStageChart(segments: day.raw.sleepSegments, height: 168, interactive: true)
                }
            }

            stageDistributionCard

            regularityAndDebtCard

            BevelCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(activeChartSnapshot.horizon.usesRangeCapsules ? "睡眠质量分布胶囊" : "睡眠趋势")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.sleepColor)

                    if activeChartSnapshot.horizon.usesRangeCapsules {
                        RangeCapsuleChart(snapshot: activeChartSnapshot, tint: BevelTheme.sleepColor) { bucket in
                            onSelectDate(bucket?.endDate)
                        }
                    } else {
                        TrendLineChart(snapshot: activeChartSnapshot, tint: BevelTheme.sleepColor, onSelectDate: onSelectDate)
                    }
                }
            }
        }
    }

    private var stageDistributionCard: some View {
        let deep = day.raw.deepMinutes ?? 0
        let core = day.raw.coreMinutes ?? 0
        let rem = day.raw.remMinutes ?? 0
        let awake = day.raw.awakeMinutes ?? 0
        let total = max(1, deep + core + rem + awake)
        let hasData = (deep + core + rem + awake) > 0

        return BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("阶段构成占比")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.ink)
                    Spacer()
                    if let asleep = day.raw.sleepAsleepMinutes, let inBed = day.raw.sleepInBedMinutes, inBed > 0 {
                        let eff = Int((Double(asleep) / Double(inBed) * 100).rounded())
                        Text("效率 \(eff)%")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .fontDesign(.rounded)
                            .foregroundStyle(BevelTheme.sleepColor)
                    }
                }

                if hasData {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            stageBar(minutes: deep, total: total, width: geo.size.width, color: BevelTheme.sleepStageColor(.deep))
                            stageBar(minutes: core, total: total, width: geo.size.width, color: BevelTheme.sleepStageColor(.core))
                            stageBar(minutes: rem, total: total, width: geo.size.width, color: BevelTheme.sleepStageColor(.rem))
                            stageBar(minutes: awake, total: total, width: geo.size.width, color: BevelTheme.sleepStageColor(.awake))
                        }
                    }
                    .frame(height: 10)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 6) {
                        stageRow(.deep, minutes: day.raw.deepMinutes, total: total)
                        stageRow(.core, minutes: day.raw.coreMinutes, total: total)
                        stageRow(.rem, minutes: day.raw.remMinutes, total: total)
                        stageRow(.awake, minutes: day.raw.awakeMinutes, total: total)
                    }
                } else {
                    Text("昨夜暂无睡眠分期时长明细。")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func stageBar(minutes: Int, total: Int, width: CGFloat, color: Color) -> some View {
        if minutes > 0 {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: max(4, width * CGFloat(Double(minutes) / Double(total))))
        }
    }

    private func stageRow(_ stage: SleepStage, minutes: Int?, total: Int) -> some View {
        let valText: String = if let minutes {
            "\(minutes)分 (\(Int((Double(minutes) / Double(total) * 100).rounded()))%)"
        } else {
            "--"
        }
        return HStack(spacing: 6) {
            Circle()
                .fill(BevelTheme.sleepStageColor(stage))
                .frame(width: 8, height: 8)
            Text(stage.title)
                .font(.caption)
                .foregroundStyle(BevelTheme.inkSecondary)
            Text(valText)
                .font(.caption.weight(.semibold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(BevelTheme.ink)
                .lineLimit(1)
        }
    }

    private var regularityAndDebtCard: some View {
        let cal = Calendar.current
        let recent14 = historyDays.suffix(14)
        let bedMinutes: [Int] = recent14.compactMap { item -> Int? in
            guard let start = item.raw.sleepStart else { return nil }
            let h = cal.component(.hour, from: start)
            let m = cal.component(.minute, from: start)
            // Shift post-midnight bedtimes across 24h boundary for clean spread comparison
            let totalM = (h < 12 ? h + 24 : h) * 60 + m
            return totalM
        }
        let spreadText: String = {
            guard let minB = bedMinutes.min(), let maxB = bedMinutes.max(), bedMinutes.count >= 3 else {
                return "--"
            }
            return "±\((maxB - minB) / 2) 分钟"
        }()

        let recent7 = historyDays.suffix(7).compactMap { $0.raw.sleepAsleepMinutes }
        let debtMinutes: Int? = recent7.isEmpty ? nil : recent7.reduce(0) { $0 + ($1 - sleepGoalMinutes) }
        let debtText: String = if let debtMinutes {
            if debtMinutes >= 0 {
                "盈余 \(debtMinutes) 分钟"
            } else {
                "缺口 \(abs(debtMinutes)) 分钟"
            }
        } else {
            "--"
        }

        return BevelCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("规律性与睡眠债（目标 \(String(format: "%.1f", Double(sleepGoalMinutes) / 60.0))h）")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BevelTheme.ink)

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("近 14 天入睡波动")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                        Text(spreadText)
                            .font(.headline.monospacedDigit())
                            .fontDesign(.rounded)
                            .foregroundStyle(spreadText == "--" ? BevelTheme.inkSecondary : BevelTheme.ink)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("近 \(recent7.count) 日睡眠盈亏")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                        Text(debtText)
                            .font(.headline.monospacedDigit())
                            .fontDesign(.rounded)
                            .foregroundStyle((debtMinutes ?? 0) < -90 ? BevelTheme.strainColor : BevelTheme.ink)
                    }
                }
            }
        }
    }
}
