import BodySeekCore
import SwiftUI

/// 今日四项指标格（UI v4 §2.3）：领域图标块 + 名称 + 箭头；大数字 + "分"；一行灰色说明；
/// 一张专属迷你图（由调用方传入）；底部起止刻度。整格可点，进入指标详情。
public struct BSDomainTile<Chart: View>: View {
    private let kind: MetricKind
    private let value: Int?
    private let availability: MetricAvailability
    private let caption: String
    private let startLabel: String
    private let endLabel: String
    private let identifier: String?
    private let zoom: BSZoomSource?
    private let action: () -> Void
    private let chart: Chart

    /// 创建指标格。
    /// - Parameters:
    ///   - kind: 指标种类（决定图标、名称与领域色）。
    ///   - value: 0–100 的分数；缺失为 `nil`。
    ///   - availability: 四态可用性。
    ///   - caption: 一行灰色说明。
    ///   - startLabel: 迷你图起点刻度。
    ///   - endLabel: 迷你图终点刻度。
    ///   - identifier: 无障碍标识。
    ///   - zoom: zoom 转场来源。
    ///   - action: 点击进入详情。
    ///   - chart: 专属迷你图。
    public init(
        kind: MetricKind,
        value: Int?,
        availability: MetricAvailability = .available,
        caption: String,
        startLabel: String,
        endLabel: String,
        identifier: String? = nil,
        zoom: BSZoomSource? = nil,
        action: @escaping () -> Void,
        @ViewBuilder chart: () -> Chart
    ) {
        self.kind = kind
        self.value = value
        self.availability = availability
        self.caption = caption
        self.startLabel = startLabel
        self.endLabel = endLabel
        self.identifier = identifier
        self.zoom = zoom
        self.action = action
        self.chart = chart()
    }

    public var body: some View {
        Button(action: action) {
            BSCard {
                VStack(alignment: .leading, spacing: BSSpace.xs) {
                    header
                    numberRow
                    Text(availability.reasonText ?? caption)
                        .bsText(.caption)
                        .lineLimit(1)
                    chart
                        .frame(height: BSSize.chartMicro)
                    footer
                }
            }
        }
        .buttonStyle(.bsPressable)
        .accessibilityElement(children: .combine)
        .modifier(BSZoomIdentifier(identifier: identifier, zoom: zoom, zoomKey: kind.rawValue))
    }

    private var header: some View {
        HStack(spacing: BSSpace.xs) {
            BSIconBlock(kind: kind)
            Text(kind.title)
                .bsText(.label)
            Spacer(minLength: BSSpace.xxs)
            Image(systemName: "chevron.right")
                .bsText(.caption)
        }
    }

    private var numberRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: BSSpace.xxs) {
            Text(valueText)
                .bsText(.number)
            Text("分")
                .bsText(.label)
        }
    }

    private var footer: some View {
        HStack {
            Text(startLabel)
            Spacer(minLength: BSSpace.xxs)
            Text(endLabel)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var valueText: String {
        switch availability {
        case .available: value.map(String.init) ?? "--"
        case .knownZero: "0"
        case .missing, .excluded: "--"
        }
    }
}

/// 关键体征列表的一行：领域图标块 + 名称 + 迷你线 + 右侧数值与一行灰色比较。
public struct BSVitalRow: View {
    private let title: String
    private let systemImage: String
    private let tint: Color
    private let value: String?
    private let unit: String
    private let comparison: String
    private let trend: [Double]

    /// 创建体征行。缺测时 `value` 传 `nil`，`comparison` 写原因。
    public init(
        title: String,
        systemImage: String,
        tint: Color,
        value: String?,
        unit: String,
        comparison: String,
        trend: [Double] = []
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.value = value
        self.unit = unit
        self.comparison = comparison
        self.trend = trend
    }

    public var body: some View {
        HStack(spacing: BSSpace.s) {
            BSIconBlock(systemImage: systemImage, tint: tint)
            Text(title)
                .bsText(.cardTitle)
            Spacer(minLength: BSSpace.xs)
            if trend.count >= 2 {
                BSMiniLine(points: trend, color: tint, endDotColor: tint)
                    .frame(width: BSSize.ringM, height: BSSize.glyph)
            }
            VStack(alignment: .trailing, spacing: BSSpace.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: BSSpace.xxs) {
                    Text(value ?? "--")
                        .bsText(.number)
                    Text(unit)
                        .bsText(.label)
                }
                Text(comparison)
                    .bsText(.caption)
            }
        }
        .frame(minHeight: BSSize.hitTarget)
        .accessibilityElement(children: .combine)
    }

    /// 与近期均值的比较文字：差异在均值 3% 以内写"接近平时"，否则写"较均值 +5 ms"。
    public static func comparison(value: Double?, average: Double?, unit: String, digits: Int) -> String {
        guard let value else { return "暂无数据" }
        guard let average else { return "积累中" }
        let delta = value - average
        if abs(delta) <= abs(average) * 0.03 { return "接近平时" }
        let sign = delta > 0 ? "+" : "−"
        let magnitude = abs(delta).formatted(.number.precision(.fractionLength(digits)))
        return "较均值 \(sign)\(magnitude) \(unit)"
    }
}
