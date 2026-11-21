import BodySeekCore
import BodySeekDesign
import SwiftUI

public struct EnergyDetailView: View {
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
        let sorted = day.energyCurve.sorted { $0.hour < $1.hour }
        let peak = sorted.max { $0.value < $1.value }
        let latest = sorted.last

        VStack(alignment: .leading, spacing: 16) {
            BevelCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("昼夜电池充放电轨迹")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.energyColor)

                    EnergyAreaChart(curve: day.energyCurve, height: 156, interactive: true)
                }
            }

            BevelCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("今日主要回充与消耗事件")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.ink)

                    eventRow(
                        icon: "battery.100percent.bolt",
                        tint: BevelTheme.recoveryColor,
                        title: "晨起电量峰值（夜间恢复回充）",
                        value: peak.map { "\($0.value)%" } ?? "--"
                    )
                    Divider()
                    eventRow(
                        icon: "flame.fill",
                        tint: BevelTheme.strainColor,
                        title: "日间活动能量消耗",
                        value: day.raw.activeEnergyKcal.map { "-\(Int($0.rounded())) kcal" } ?? "--"
                    )
                    Divider()
                    eventRow(
                        icon: "figure.walk",
                        tint: BevelTheme.energyColor,
                        title: "当前剩余电池储备",
                        value: latest.map { "\($0.value)%" } ?? "--"
                    )
                }
            }

            BevelCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("能量储备趋势")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.energyColor)

                    TrendHorizonChart(
                        snapshot: activeChartSnapshot,
                        tint: BevelTheme.energyColor,
                        onSelectDate: onSelectDate,
                        onSelectBucket: { bucket in onSelectDate(bucket?.endDate) }
                    )
                }
            }
        }
    }

    private func eventRow(icon: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(BevelTheme.inkSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(value == "--" ? BevelTheme.inkSecondary : BevelTheme.ink)
        }
    }
}
