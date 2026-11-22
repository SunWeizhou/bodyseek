import BodySeekCore
import BodySeekDesign
import SwiftUI

public struct StressDetailView: View {
    public let day: DailyComputedDay
    public let activeChartSnapshot: ChartSeriesSnapshot
    public let onSelectDate: @MainActor (Date?) -> Void

    public init(
        day: DailyComputedDay,
        activeChartSnapshot: ChartSeriesSnapshot,
        onSelectDate: @escaping @MainActor (Date?) -> Void
    ) {
        self.day = day
        self.activeChartSnapshot = activeChartSnapshot
        self.onSelectDate = onSelectDate
    }

    public var body: some View {
        let excludedHours = workoutHoursSet()
        VStack(alignment: .leading, spacing: 16) {
            BevelCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("日内自主神经压力节律（估算至当前时刻）")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.stressColor)

                    IntradayBarChart(
                        bins: day.stressTimeline,
                        excludedHours: excludedHours,
                        height: 156,
                        interactive: true
                    )

                    Text("每个柱状块代表 2 小时窗口的模型估算（非逐分钟实时采样），不预测未来时段。")
                        .font(.caption2)
                        .foregroundStyle(BevelTheme.inkSecondary)

                    if !excludedHours.isEmpty {
                        Text("浅灰斜纹区块代表运动进行窗口，已从静息自主神经压力统计中排除。")
                            .font(.caption2)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                }
            }

            stressZoneBreakdownCard(excludedHours: excludedHours)

            BevelCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("压力趋势")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.stressColor)

                    TrendHorizonChart(
                        snapshot: activeChartSnapshot,
                        tint: BevelTheme.stressColor,
                        onSelectDate: onSelectDate,
                        onSelectBucket: { bucket in onSelectDate(bucket?.endDate) }
                    )
                }
            }
        }
    }

    private func stressZoneBreakdownCard(excludedHours: Set<Int>) -> some View {
        let validBins = day.stressTimeline.filter { !excludedHours.contains($0.hour) }
        let restHours = validBins.filter { $0.level == .rest }.count
        let lowHours = validBins.filter { $0.level == .low }.count
        let mediumHours = validBins.filter { $0.level == .medium }.count
        let elevatedHours = validBins.filter { $0.level == .elevated }.count

        return BevelCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("高压时段 vs 恢复时段")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BevelTheme.ink)

                if validBins.isEmpty {
                    Text("今日暂无可统计的静息压力小时窗口。")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], alignment: .leading, spacing: 8) {
                        bucketChip(title: "放松恢复", hours: restHours, color: BevelTheme.recoveryColor)
                        bucketChip(title: "轻度激活", hours: lowHours, color: BevelTheme.stressColor.opacity(0.65))
                        bucketChip(title: "中等压力", hours: mediumHours, color: BevelTheme.energyColor)
                        bucketChip(title: "高压警示", hours: elevatedHours, color: BevelTheme.stressColor)
                    }
                }
            }
        }
    }

    private func bucketChip(title: String, hours: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption)
                .foregroundStyle(BevelTheme.inkSecondary)
            Spacer(minLength: 4)
            Text("\(hours) 窗 · 约\(hours * 2)h")
                .font(.caption.weight(.bold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(BevelTheme.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func workoutHoursSet() -> Set<Int> {
        let cal = Calendar.current
        var hours = Set<Int>()
        for workout in day.raw.workouts {
            let startHour = cal.component(.hour, from: workout.startDate)
            let spanHours = max(1, (workout.durationMinutes + 59) / 60)
            for offset in 0..<spanHours {
                hours.insert((startHour + offset) % 24)
            }
        }
        return hours
    }
}
