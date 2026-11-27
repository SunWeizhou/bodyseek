import SwiftUI

/// 文字角色。全部基于系统文字样式，支持动态字号。
public enum BSTextRole: Sendable, Hashable, CaseIterable {
    /// L0 核心分数：`.largeTitle`，bold，rounded，等宽数字。
    case heroNumber
    /// 指标格数值、图表锁定读数：`.title2`，semibold，rounded，等宽数字。
    case number
    /// 区块标题：`.title3`，semibold。
    case pageSection
    /// 卡片标题：`.headline`。
    case cardTitle
    /// Coach 解读正文：`.body`。
    case body
    /// 单位、指标名、说明：`.subheadline`，二级文字色。
    case label
    /// 数据来源、覆盖率、时间戳：`.footnote`，二级文字色。
    case caption
}

private extension BSTextRole {
    var font: Font {
        switch self {
        case .heroNumber: .system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
        case .number: .system(.title2, design: .rounded, weight: .semibold).monospacedDigit()
        case .pageSection: .system(.title3, weight: .semibold)
        case .cardTitle: .headline
        case .body: .body
        case .label: .subheadline
        case .caption: .footnote
        }
    }
}

private struct BSTextModifier: ViewModifier {
    let role: BSTextRole

    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        switch role {
        case .heroNumber, .number:
            content
                .font(role.font)
                .contentTransition(.numericText())
        case .label, .caption:
            content
                .font(role.font)
                .foregroundStyle(
                    contrast == .increased ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary
                )
        case .pageSection, .cardTitle, .body:
            content
                .font(role.font)
        }
    }
}

public extension View {
    /// 应用 BodySeek 文字角色。
    ///
    /// 开启"增强对比度"时，二级文字（`label`、`caption`）自动升为一级文字色。
    ///
    /// 数值统一写成 `Text(value).bsText(.number)`：由修饰符负责 rounded、等宽数字和数字过渡。
    /// 不要手动设置 `kerning` 或 `tracking`，系统会按字号自动处理字距。
    func bsText(_ role: BSTextRole) -> some View {
        modifier(BSTextModifier(role: role))
    }
}
