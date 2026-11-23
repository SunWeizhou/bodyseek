import BodySeekCore
import SwiftUI

/// 心率区间 Z1–Z5 比例条：单色负荷色阶（越高的区间越深），不再用彩虹色区分。
public struct ZoneBar: View {
    public let zones: WorkoutHeartRateZones
    public let showsTrimp: Bool

    private static let barHeight: CGFloat = BSSize.dot
    private static let minimumSegmentWidth: CGFloat = BSSpace.xxs

    public init(zones: WorkoutHeartRateZones, showsTrimp: Bool = false) {
        self.zones = zones
        self.showsTrimp = showsTrimp
    }

    private var minutes: [Int] {
        [zones.zone1Minutes, zones.zone2Minutes, zones.zone3Minutes, zones.zone4Minutes, zones.zone5Minutes]
    }

    /// 负荷色阶：Z1 最浅，Z5 最深。
    private static func shade(_ index: Int) -> Color {
        let steps = [BSOpacity.faint, BSOpacity.muted, BSOpacity.disabled, BSOpacity.scrim, 1.0]
        return BSColor.strain.opacity(steps[min(max(index, 0), steps.count - 1)])
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BSSpace.xs) {
            bar
            legend
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("心率区间分布")
        .accessibilityValue("Z2 \(zones.zone2Minutes)分钟，Z3 \(zones.zone3Minutes)分钟，Z4 \(zones.zone4Minutes)分钟，Z5 \(zones.zone5Minutes)分钟")
    }

    private var bar: some View {
        let total = max(1, Double(zones.totalZoneMinutes))
        return GeometryReader { geo in
            HStack(spacing: BSChartStroke.rule) {
                ForEach(Array(minutes.enumerated()), id: \.offset) { index, mins in
                    segment(mins, index: index, total: total, width: geo.size.width)
                }
            }
        }
        .frame(height: Self.barHeight)
    }

    @ViewBuilder
    private func segment(_ mins: Int, index: Int, total: Double, width: CGFloat) -> some View {
        if mins > 0 {
            RoundedRectangle(cornerRadius: BSRadius.s, style: .continuous)
                .fill(Self.shade(index))
                .frame(width: max(Self.minimumSegmentWidth, width * CGFloat(Double(mins) / total)))
        }
    }

    private var legend: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: BSSize.ringM), alignment: .leading)],
            alignment: .leading,
            spacing: BSSpace.xxs
        ) {
            ForEach(Array(minutes.enumerated()), id: \.offset) { index, mins in
                zoneTag("Z\(index + 1)", mins, index: index)
            }
            if showsTrimp {
                Text(String(format: "TRIMP %.0f", zones.trimpScore))
                    .bsText(.caption)
            }
        }
    }

    private func zoneTag(_ label: String, _ mins: Int, index: Int) -> some View {
        HStack(spacing: BSSpace.xxs) {
            Circle()
                .fill(Self.shade(index))
                .frame(width: BSSize.dot, height: BSSize.dot)
            Text("\(label) \(mins)分")
                .bsText(.caption)
                .lineLimit(1)
        }
    }
}
