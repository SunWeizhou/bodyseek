import BodySeekCore
import SwiftUI

/// Color-coded stacked bar for Apple Watch Workout Heart Rate Zones 1–5 with AX5-safe wrapping legend.
public struct ZoneBar: View {
    public let zones: WorkoutHeartRateZones
    public let showsTrimp: Bool

    public init(zones: WorkoutHeartRateZones, showsTrimp: Bool = false) {
        self.zones = zones
        self.showsTrimp = showsTrimp
    }

    public var body: some View {
        let total = max(1, Double(zones.totalZoneMinutes))
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    segment(zones.zone1Minutes, total: total, width: geo.size.width, color: BevelTheme.inkSecondary.opacity(0.45))
                    segment(zones.zone2Minutes, total: total, width: geo.size.width, color: BevelTheme.infoBlue)
                    segment(zones.zone3Minutes, total: total, width: geo.size.width, color: BevelTheme.recoveryColor)
                    segment(zones.zone4Minutes, total: total, width: geo.size.width, color: BevelTheme.energyColor)
                    segment(zones.zone5Minutes, total: total, width: geo.size.width, color: BevelTheme.stressColor)
                }
            }
            .frame(height: 8)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 68), alignment: .leading)],
                alignment: .leading,
                spacing: 4
            ) {
                zoneTag("Z1", zones.zone1Minutes, color: BevelTheme.inkSecondary.opacity(0.55))
                zoneTag("Z2", zones.zone2Minutes, color: BevelTheme.infoBlue)
                zoneTag("Z3", zones.zone3Minutes, color: BevelTheme.recoveryColor)
                zoneTag("Z4", zones.zone4Minutes, color: BevelTheme.energyColor)
                zoneTag("Z5", zones.zone5Minutes, color: BevelTheme.stressColor)
                if showsTrimp {
                    Text(String(format: "TRIMP %.0f", zones.trimpScore))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .fontDesign(.rounded)
                        .foregroundStyle(BevelTheme.strainColor)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("心率区间分布")
        .accessibilityValue("Z2 \(zones.zone2Minutes)分钟，Z3 \(zones.zone3Minutes)分钟，Z4 \(zones.zone4Minutes)分钟，Z5 \(zones.zone5Minutes)分钟")
    }

    @ViewBuilder
    private func segment(_ mins: Int, total: Double, width: CGFloat, color: Color) -> some View {
        if mins > 0 {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: max(4, width * CGFloat(Double(mins) / total)))
        }
    }

    private func zoneTag(_ label: String, _ mins: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label) \(mins)分")
                .font(.caption2.monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(BevelTheme.inkSecondary)
                .lineLimit(1)
        }
    }
}
