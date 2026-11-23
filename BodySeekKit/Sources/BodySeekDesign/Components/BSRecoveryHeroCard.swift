import BodySeekCore
import SwiftUI

/// 今日恢复主卡（UI v4 §2.1，不用环）：左侧大数字 + 状态标签 + 说明 + 详情入口，右侧 7 天恢复折线。
///
/// 四态：有数据显示数字；缺失和排除显示 `--` 加原因。左侧整块可点，进入恢复详情。
public struct BSRecoveryHeroCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let value: Int?
    private let availability: MetricAvailability
    private let statusText: String?
    private let caption: String
    private let weekValues: [Double?]
    private let startLabel: String
    private let endLabel: String
    private let identifier: String?
    private let zoom: BSZoomSource?
    private let action: () -> Void

    /// 创建恢复主卡。
    /// - Parameters:
    ///   - value: 0–100 的恢复分；缺失时为 `nil`。
    ///   - availability: 四态可用性。
    ///   - statusText: 状态标签，例如"平时范围内"。
    ///   - caption: 一行灰色说明。
    ///   - weekValues: 近 7 天恢复分，最后一项是今天；缺失为 `nil`。
    ///   - startLabel: 折线起点日期刻度。
    ///   - endLabel: 折线终点日期刻度。
    ///   - identifier: 左侧按钮的无障碍标识。
    ///   - zoom: zoom 转场来源。
    ///   - action: 点击进入恢复详情。
    public init(
        value: Int?,
        availability: MetricAvailability = .available,
        statusText: String? = nil,
        caption: String,
        weekValues: [Double?],
        startLabel: String,
        endLabel: String,
        identifier: String? = nil,
        zoom: BSZoomSource? = nil,
        action: @escaping () -> Void
    ) {
        self.value = value
        self.availability = availability
        self.statusText = statusText
        self.caption = caption
        self.weekValues = weekValues
        self.startLabel = startLabel
        self.endLabel = endLabel
        self.identifier = identifier
        self.zoom = zoom
        self.action = action
    }

    public var body: some View {
        BSCard {
            layout
        }
    }

    @ViewBuilder
    private var layout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: BSSpace.m) {
                leftColumn
                trendColumn
            }
        } else {
            HStack(alignment: .top, spacing: BSSpace.m) {
                leftColumn
                Rectangle()
                    .fill(BSColor.separator)
                    .frame(width: BSChartStroke.grid)
                trendColumn
            }
        }
    }

    private var leftColumn: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: BSSpace.xs) {
                HStack(spacing: BSSpace.xs) {
                    BSIconBlock(kind: .recovery)
                    Text("恢复")
                        .bsText(.cardTitle)
                }
                HStack(alignment: .firstTextBaseline, spacing: BSSpace.xxs) {
                    Text(valueText)
                        .bsText(.heroNumber)
                    Text("/ 100")
                        .bsText(.label)
                }
                statusTag
                Text(caption)
                    .bsText(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("查看恢复详情 →")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BSColor.recovery)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bsPressable)
        .accessibilityElement(children: .combine)
        .modifier(BSZoomIdentifier(identifier: identifier, zoom: zoom, zoomKey: MetricKind.recovery.rawValue))
    }

    @ViewBuilder
    private var statusTag: some View {
        if let text = availability.reasonText ?? statusText, !text.isEmpty {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BSColor.recovery)
                .padding(.horizontal, BSSpace.xs)
                .padding(.vertical, BSSpace.xxs)
                .background(BSColor.recovery.opacity(BSOpacity.faint), in: Capsule())
        }
    }

    private var trendColumn: some View {
        VStack(alignment: .leading, spacing: BSSpace.xs) {
            Text("近 7 天恢复")
                .bsText(.caption)
            MiniAreaLine(values: weekValues, tint: BSColor.recovery, domain: 0...100)
                .frame(height: BSSize.ringM)
            HStack {
                Text(startLabel)
                Spacer(minLength: BSSpace.xs)
                Text(endLabel)
            }
            .bsText(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private var valueText: String {
        switch availability {
        case .available: value.map(String.init) ?? "--"
        case .knownZero: "0"
        case .missing, .excluded: "--"
        }
    }
}

/// 同时设置无障碍标识和 zoom 转场来源。
struct BSZoomIdentifier: ViewModifier {
    let identifier: String?
    let zoom: BSZoomSource?
    let zoomKey: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if let zoom {
            content
                .modifier(BSOptionalIdentifier(identifier: identifier))
                .bodyseekZoomSource(id: zoom.prefix + zoomKey, in: zoom.namespace)
        } else {
            content
                .modifier(BSOptionalIdentifier(identifier: identifier))
        }
    }
}
