import BodySeekCore
import BodySeekDesign
import SwiftUI

public struct RecoveryDetailView: View {
    public let day: DailyComputedDay
    public let historyDays: [DailyComputedDay]
    public let activeChartSnapshot: ChartSeriesSnapshot
    public let score: MetricScore
    public let onSelectDate: @MainActor (Date?) -> Void

    public init(
        day: DailyComputedDay,
        historyDays: [DailyComputedDay],
        activeChartSnapshot: ChartSeriesSnapshot,
        score: MetricScore,
        onSelectDate: @escaping @MainActor (Date?) -> Void
    ) {
        self.day = day
        self.historyDays = historyDays
        self.activeChartSnapshot = activeChartSnapshot
        self.score = score
        self.onSelectDate = onSelectDate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BSSpace.m) {
            BSCard {
                VStack(alignment: .leading, spacing: BSSpace.s) {
                    Text("恢复储备趋势")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.recoveryColor)

                    TrendHorizonChart(
                        snapshot: activeChartSnapshot,
                        tint: BevelTheme.recoveryColor,
                        onSelectDate: onSelectDate,
                        onSelectBucket: { bucket in onSelectDate(bucket?.endDate) }
                    )

                    Text(activeChartSnapshot.statusSummary)
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }
            }

            vitalsDeviationCard

            contributorsCard
        }
    }

    private var vitalsDeviationCard: some View {
        let prior28 = historyDays.filter { $0.dayKey < day.dayKey }.suffix(28)
        let tempBase = median(prior28.compactMap { $0.raw.wristTempDeltaC })
        let respBase = median(prior28.compactMap { $0.raw.respiratoryRateBrpm })
        let spo2Base = median(prior28.compactMap { $0.raw.oxygenSaturationPct })
        let walkHRBase = median(prior28.compactMap { $0.raw.walkingHeartRateAvgBpm })

        return BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                Text("生理体征偏离 · 对照个人 28 天基线")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BevelTheme.ink)

                deviationRow(
                    title: "手腕温度偏离",
                    valueText: day.raw.wristTempDeltaC.map { String(format: "%+.2f ℃", $0) } ?? "--",
                    baselineText: tempBase.map { String(format: "基线 %+.2f ℃", $0) },
                    delta: day.raw.wristTempDeltaC.flatMap { cur in tempBase.map { cur - $0 } },
                    scale: 0.6
                )
                Divider()
                deviationRow(
                    title: "睡眠呼吸率",
                    valueText: day.raw.respiratoryRateBrpm.map { String(format: "%.1f 次/分", $0) } ?? "--",
                    baselineText: respBase.map { String(format: "基线 %.1f", $0) },
                    delta: day.raw.respiratoryRateBrpm.flatMap { cur in respBase.map { cur - $0 } },
                    scale: 2.0
                )
                Divider()
                deviationRow(
                    title: "血氧饱和度",
                    valueText: day.raw.oxygenSaturationPct.map { String(format: "%.0f%%", $0) } ?? "--",
                    baselineText: spo2Base.map { String(format: "基线 %.0f%%", $0) },
                    delta: day.raw.oxygenSaturationPct.flatMap { cur in spo2Base.map { cur - $0 } },
                    scale: 3.0
                )
                Divider()
                deviationRow(
                    title: "步行平均心率",
                    valueText: day.raw.walkingHeartRateAvgBpm.map { "\(Int($0.rounded())) bpm" } ?? "--",
                    baselineText: walkHRBase.map { "基线 \(Int($0.rounded())) bpm" },
                    delta: day.raw.walkingHeartRateAvgBpm.flatMap { cur in walkHRBase.map { cur - $0 } },
                    scale: 10.0
                )
            }
        }
    }

    private func deviationRow(
        title: String,
        valueText: String,
        baselineText: String?,
        delta: Double?,
        scale: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: BSSpace.xs) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(BevelTheme.ink)
                Spacer()
                Text(valueText)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .fontDesign(.rounded)
                    .foregroundStyle(valueText == "--" ? BevelTheme.inkSecondary : BevelTheme.ink)
            }

            GeometryReader { geo in
                let mid = geo.size.width / 2
                let clamped = delta.map { max(-1.0, min(1.0, $0 / max(0.01, scale))) } ?? 0
                let offsetWidth = abs(CGFloat(clamped)) * (mid - 4)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(BevelTheme.scoreTrack)
                        .frame(height: BSSize.dot)
                    Rectangle()
                        .fill(BevelTheme.inkSecondary.opacity(BSOpacity.disabled))
                        .frame(width: BSSize.dot, height: BSSize.dot)
                        .offset(x: mid - 0.75)
                    if delta != nil {
                        Capsule()
                            .fill(abs(clamped) > 0.65 ? BevelTheme.strainColor : BevelTheme.recoveryColor)
                            .frame(width: max(4, offsetWidth), height: BSSize.dot)
                            .offset(x: clamped >= 0 ? mid : (mid - max(4, offsetWidth)))
                    }
                }
            }
            .frame(height: BSSize.dot)

            Text(baselineText ?? "基线样本积累中")
                .font(.caption2)
                .foregroundStyle(BevelTheme.inkSecondary)
        }
    }

    private var contributorsCard: some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                Text("评分贡献因子（\(score.algorithmVersion.description)）")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BevelTheme.ink)

                if score.contributors.isEmpty {
                    Text("当前样本尚未生成详细贡献拆解。")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                } else {
                    ForEach(score.contributors) { item in
                        HStack(alignment: .top, spacing: BSSpace.s) {
                            Circle()
                                .fill(impactColor(item.impact))
                                .frame(width: BSSize.dot, height: BSSize.dot)
                                .padding(.top, BSSpace.xxs)

                            VStack(alignment: .leading, spacing: BSSpace.xxs) {
                                HStack {
                                    Text(item.label)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(BevelTheme.ink)
                                    if let weight = item.weight {
                                        Text("\(Int((weight * 100).rounded()))%")
                                            .font(.caption2.monospacedDigit())
                                            .fontDesign(.rounded)
                                            .foregroundStyle(BevelTheme.inkSecondary)
                                    }
                                    Spacer()
                                    Text(item.valueText)
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                        .fontDesign(.rounded)
                                        .foregroundStyle(item.impact == .missing ? BevelTheme.inkSecondary : BevelTheme.ink)
                                }
                                if let baseline = item.baselineDeltaText {
                                    Text(baseline)
                                        .font(.caption)
                                        .foregroundStyle(BevelTheme.deviationInk)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func impactColor(_ impact: MetricContributor.Impact) -> Color {
        switch impact {
        case .positive: BevelTheme.recoveryColor
        case .neutral: BevelTheme.brand
        case .negative: BevelTheme.strainColor
        case .missing: BevelTheme.inkSecondary
        }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2.0
        }
        return sorted[mid]
    }
}
