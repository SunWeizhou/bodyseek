import BodySeekCore
import SwiftUI

/// 指标格：名称、数值 + 单位、`BSDeltaBadge`、可选迷你折线。放在 `BSMetricGrid` 里。
///
/// 四态：有数据显示数值；已知为零显示 `0` 加原因；缺失和排除显示 `--` 加原因。
public struct BSMetricTile: View {
    private let title: String
    private let value: String?
    private let unit: String
    private let availability: MetricAvailability
    private let delta: Double?
    private let comparison: String
    private let trend: [Double]
    private let tint: Color
    private let isLoading: Bool
    private let action: (() -> Void)?

    /// 创建指标格。
    /// - Parameters:
    ///   - title: 指标名，例如"夜间 HRV"。
    ///   - value: 已格式化的数值；`nil` 显示 `--`。
    ///   - unit: 单位，例如 `ms`；也用于变化量。
    ///   - availability: 四态可用性。
    ///   - delta: 与基线的差值；`nil` 时不显示变化标记。
    ///   - comparison: 比较对象说明。
    ///   - trend: 迷你折线的数据点；少于 2 个点时不画。
    ///   - tint: 折线末端点的颜色，通常取领域色。
    ///   - isLoading: 为 `true` 时显示骨架。
    ///   - action: 点击动作（进入详情）。
    public init(
        title: String,
        value: String?,
        unit: String = "",
        availability: MetricAvailability = .available,
        delta: Double? = nil,
        comparison: String = "vs 28 天",
        trend: [Double] = [],
        tint: Color = BSColor.tint,
        isLoading: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.availability = availability
        self.delta = delta
        self.comparison = comparison
        self.trend = trend
        self.tint = tint
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.xs) {
                Text(title)
                    .bsText(.label)
                HStack(alignment: .firstTextBaseline, spacing: BSSpace.xxs) {
                    Text(valueText)
                        .bsText(.number)
                    if !unit.isEmpty {
                        Text(unit)
                            .bsText(.label)
                    }
                }
                footer
                if trend.count >= 2 {
                    BSMiniLine(points: trend, color: BSColor.dimmed, endDotColor: tint)
                        .frame(height: BSSize.chartMicro)
                }
            }
            .redacted(reason: isLoading ? .placeholder : [])
        }
        .bsTappable(action)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var footer: some View {
        if let reason = availability.reasonText {
            Text(reason)
                .bsText(.caption)
        } else if delta != nil {
            BSDeltaBadge(delta: delta, unit: unit, comparison: comparison)
        }
    }

    private var valueText: String {
        switch availability {
        case .available: value ?? "--"
        case .knownZero: "0"
        case .missing, .excluded: "--"
        }
    }
}

/// 指标格的 2 列网格；在无障碍最大字号下自动变成 1 列。
public struct BSMetricGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let content: Content

    private static var regularColumnCount: Int { 2 }

    /// 创建指标格网格。
    /// - Parameter content: 若干 `BSMetricTile`。
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        LazyVGrid(columns: columns, spacing: BSSpace.s) {
            content
        }
    }

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : Self.regularColumnCount
        return Array(repeating: GridItem(.flexible(), spacing: BSSpace.s), count: count)
    }
}
