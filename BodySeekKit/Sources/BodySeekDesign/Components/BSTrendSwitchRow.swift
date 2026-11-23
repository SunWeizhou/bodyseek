import BodySeekCore
import SwiftUI

/// 趋势页纵览列表的一行，同时是大图的指标切换器（UI v4 §5.4）：
/// 领域图标块 + 名称 + 领域色迷你线（负荷用迷你柱，由调用方传入）+ 右侧周期均值与变化。
/// 选中行用领域色 soft 底，并带 `.isSelected` 无障碍特征。
public struct BSTrendSwitchRow<Mini: View>: View {
    private let title: String
    private let systemImage: String
    private let tint: Color
    private let meanText: String
    private let changeText: String
    private let isSelected: Bool
    private let identifier: String?
    private let action: () -> Void
    private let mini: Mini

    /// 创建切换行。
    /// - Parameters:
    ///   - title: 指标名。
    ///   - systemImage: 图标。
    ///   - tint: 领域色。
    ///   - meanText: 周期均值，例如"72"或"7 小时 12 分"。
    ///   - changeText: 周期变化，例如"+3"；没有时传"--"。
    ///   - isSelected: 是否为当前大图指标。
    ///   - identifier: 无障碍标识。
    ///   - action: 点击切换。
    ///   - mini: 迷你线或迷你柱。
    public init(
        title: String,
        systemImage: String,
        tint: Color,
        meanText: String,
        changeText: String,
        isSelected: Bool,
        identifier: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder mini: () -> Mini
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.meanText = meanText
        self.changeText = changeText
        self.isSelected = isSelected
        self.identifier = identifier
        self.action = action
        self.mini = mini()
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: BSSpace.s) {
                BSIconBlock(systemImage: systemImage, tint: tint)
                Text(title)
                    .bsText(.cardTitle)
                    .lineLimit(1)
                Spacer(minLength: BSSpace.xs)
                mini
                    .frame(width: BSSize.ringM, height: BSSize.glyph)
                VStack(alignment: .trailing, spacing: BSSpace.xxs) {
                    Text(meanText)
                        .bsText(.number)
                        .lineLimit(1)
                    Text(changeText)
                        .bsText(.caption)
                }
                .frame(minWidth: BSSize.ringM, alignment: .trailing)
            }
            .padding(.horizontal, BSSpace.s)
            .padding(.vertical, BSSpace.xs)
            .frame(minHeight: BSSize.hitTarget)
            .background(rowBackground)
        }
        .buttonStyle(.bsPressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .modifier(BSOptionalIdentifier(identifier: identifier))
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: BSRadius.m, style: .continuous)
            .fill(isSelected ? tint.opacity(BSOpacity.faint) : Color.clear)
    }
}

/// 纵览列表行里的领域色迷你折线（1.5pt 线 + 末端圆点），不可交互。
public struct BSMiniTrendLine: View {
    private let points: [Double]
    private let tint: Color

    /// 创建迷你折线；少于 2 个点时不画。
    public init(points: [Double], tint: Color) {
        self.points = points
        self.tint = tint
    }

    public var body: some View {
        BSMiniLine(points: points, color: tint, endDotColor: tint)
    }
}
