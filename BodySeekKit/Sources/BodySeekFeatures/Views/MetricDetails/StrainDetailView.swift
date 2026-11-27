import BodySeekCore
import BodySeekDesign
import SwiftUI

public struct StrainDetailView: View {
    public let day: DailyComputedDay
    public let trainingLoad: TrainingLoadStatus
    public let activeChartSnapshot: ChartSeriesSnapshot
    public let onSelectDate: @MainActor (Date?) -> Void

    public init(
        day: DailyComputedDay,
        trainingLoad: TrainingLoadStatus,
        activeChartSnapshot: ChartSeriesSnapshot,
        onSelectDate: @escaping @MainActor (Date?) -> Void
    ) {
        self.day = day
        self.trainingLoad = trainingLoad
        self.activeChartSnapshot = activeChartSnapshot
        self.onSelectDate = onSelectDate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BSSpace.m) {
            acwrGaugeCard

            workoutsBreakdownCard

            BSCard {
                VStack(alignment: .leading, spacing: BSSpace.s) {
                    Text("训练负荷趋势")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.strainColor)

                    TrendHorizonChart(
                        snapshot: activeChartSnapshot,
                        tint: BevelTheme.strainColor,
                        onSelectDate: onSelectDate,
                        onSelectBucket: { bucket in onSelectDate(bucket?.endDate) }
                    )

                    Text(activeChartSnapshot.statusSummary)
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }
            }
        }
    }

    private var acwrGaugeCard: some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                HStack {
                    Text("急慢性负荷比 (ACWR)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.ink)
                    Spacer()
                    Text(trainingLoad.zone.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, BSSpace.xs)
                        .padding(.vertical, BSSpace.xxs)
                        .background(zoneColor(trainingLoad.zone).opacity(BSOpacity.faint), in: Capsule())
                        .foregroundStyle(zoneColor(trainingLoad.zone))
                }

                HStack(spacing: BSSpace.m) {
                    metricCell(title: "ACWR", value: trainingLoad.acwrRatio.map { String(format: "%.2f", $0) } ?? "--")
                    metricCell(title: "7 天急性", value: String(format: "%.0f", trainingLoad.acute7dLoad))
                    metricCell(title: "28 天周均", value: String(format: "%.0f", trainingLoad.chronic28dWeeklyAvg))
                }

                GeometryReader { geo in
                    let maxScale: Double = 1.8
                    let sweetStart = CGFloat(0.8 / maxScale) * geo.size.width
                    let sweetEnd = CGFloat(1.32 / maxScale) * geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(BevelTheme.scoreTrack)
                            .frame(height: BSSize.dot)
                        RoundedRectangle(cornerRadius: BSRadius.s, style: .continuous)
                            .fill(BevelTheme.recoveryColor.opacity(BSOpacity.muted))
                            .frame(width: sweetEnd - sweetStart, height: BSSize.dot)
                            .offset(x: sweetStart)
                        if let ratio = trainingLoad.acwrRatio {
                            let clamped = min(maxScale, max(0, ratio))
                            let x = CGFloat(clamped / maxScale) * max(1, geo.size.width - 10)
                            Circle()
                                .fill(zoneColor(trainingLoad.zone))
                                .frame(width: BSSize.dot, height: BSSize.dot)
                                .offset(x: x)
                        }
                    }
                }
                .frame(height: BSSize.dot)

                Text("安全适配甜区：0.80–1.32 · TRIMP 按 Watch 心率区间计算，不与系统估算重复叠加")
                    .font(.caption2)
                    .foregroundStyle(BevelTheme.inkSecondary)
            }
        }
    }

    private func metricCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: BSSpace.xxs) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(BevelTheme.inkSecondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(value == "--" ? BevelTheme.inkSecondary : BevelTheme.ink)
        }
    }

    private var workoutsBreakdownCard: some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                Text("当日 Apple Watch 训练与心率区间")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BevelTheme.ink)

                if day.raw.workouts.isEmpty {
                    Text("今日暂无训练记录。")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                } else {
                    ForEach(day.raw.workouts) { workout in
                        VStack(alignment: .leading, spacing: BSSpace.xs) {
                            HStack {
                                Label(workout.activityName, systemImage: workout.symbolName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                Spacer()
                                Text("\(workout.durationMinutes) 分钟 · \(Int(workout.activeEnergyKcal.rounded())) kcal")
                                    .font(.caption.monospacedDigit())
                                    .fontDesign(.rounded)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }

                            HStack(spacing: BSSpace.s) {
                                if let avgHR = workout.averageHeartRate {
                                    tagPill("均心率 \(Int(avgHR.rounded())) bpm", tint: BevelTheme.heartRateAverage)
                                }
                                if let userEffort = workout.effortScore {
                                    tagPill(String(format: "主观用力 %.1f", userEffort), tint: BevelTheme.strainColor)
                                } else {
                                    tagPill("主观用力 --", tint: BevelTheme.inkSecondary)
                                }
                                if let estEffort = workout.estimatedEffortScore {
                                    tagPill(String(format: "系统估算 %.1f", estEffort), tint: BevelTheme.infoBlue)
                                }
                            }

                            if let zones = workout.heartRateZones, zones.totalZoneMinutes > 0 {
                                ZoneBar(zones: zones, showsTrimp: true)
                            }
                        }
                        .padding(BSSpace.s)
                        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: BSRadius.m, style: .continuous))
                    }
                }
            }
        }
    }

    private func tagPill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium).monospacedDigit())
            .fontDesign(.rounded)
            .padding(.horizontal, BSSpace.xs)
            .padding(.vertical, BSSpace.xxs)
            .background(tint.opacity(BSOpacity.faint), in: Capsule())
            .foregroundStyle(tint)
    }

    private func zoneColor(_ zone: ACWRZone) -> Color {
        switch zone {
        case .sweetSpot: BevelTheme.recoveryColor
        case .highRisk: BevelTheme.dangerColor
        case .undertraining: BevelTheme.energyColor
        case .insufficientData: BevelTheme.inkSecondary
        }
    }
}
