import BodySeekCore
import Charts
import SwiftUI

/// Horizontal zero-centered diverging bar chart showing exact linear factor contributions to tomorrow's forecast.
public struct FeatureAttributionChart: View {
    public let drivers: [PersonalForecastDriver]
    public let targetName: String
    public let height: CGFloat

    public init(
        drivers: [PersonalForecastDriver],
        targetName: String,
        height: CGFloat = 148
    ) {
        self.drivers = drivers
        self.targetName = targetName
        self.height = height
    }

    private var isPercent: Bool {
        targetName == "sleep_efficiency"
    }

    public var body: some View {
        let nonZero = drivers.filter { $0.contribution.isFinite && abs($0.contribution) > 1e-6 }
        if nonZero.isEmpty {
            Text("当前特征接近个人基线中位，暂无明显偏离驱动项。")
                .font(.caption)
                .foregroundStyle(BevelTheme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        } else {
            let scaled = nonZero.map { item -> (driver: PersonalForecastDriver, value: Double) in
                let v = isPercent ? item.contribution * 100.0 : item.contribution
                return (item, v)
            }
            let maxAbs = scaled.map { abs($0.value) }.max() ?? 1.0
            let bound = max(maxAbs * 1.48, isPercent ? 1.5 : 0.8)

            Chart {
                RuleMark(x: .value("基线", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(BevelTheme.inkSecondary.opacity(0.45))

                ForEach(scaled, id: \.driver.id) { entry in
                    let favorable = isFavorable(contribution: entry.driver.contribution)
                    let tint = favorable ? BevelTheme.recoveryColor : BevelTheme.energyColor

                    BarMark(
                        xStart: .value("基线", 0),
                        xEnd: .value("贡献", entry.value),
                        y: .value("因素", entry.driver.label)
                    )
                    .cornerRadius(4)
                    .foregroundStyle(tint.opacity(0.84))
                    .annotation(
                        position: entry.value >= 0 ? .trailing : .leading,
                        spacing: 5
                    ) {
                        Text(formatSigned(entry.value, unit: entry.driver.unit))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .fontDesign(.rounded)
                            .foregroundStyle(tint)
                    }
                }
            }
            .chartXScale(domain: (-bound)...bound)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(BevelTheme.ink)
                        }
                    }
                }
            }
            .frame(height: max(88, min(height, CGFloat(scaled.count) * 34 + 14)))
        }
    }

    private func isFavorable(contribution: Double) -> Bool {
        if targetName == "resting_hr_bpm" {
            return contribution <= 0
        }
        return contribution >= 0
    }

    private func formatSigned(_ scaledVal: Double, unit: String) -> String {
        let sign = scaledVal >= 0 ? "+" : ""
        if isPercent {
            return String(format: "%@%.1f pp", sign, scaledVal)
        }
        return String(format: "%@%.2f %@", sign, scaledVal, unit)
    }
}
