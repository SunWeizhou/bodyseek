import SwiftUI

/// 唯一的卡片样式：`surface` 底色、`BSRadius.l` 圆角、`BSSpace.m` 内边距，不加阴影。
///
/// 开启"增强对比度"时自动加 `separator` 描边。
public struct BSCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast

    private let content: Content

    /// 创建卡片。
    /// - Parameter content: 卡片内容。
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(BSSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                BSColor.surface,
                in: RoundedRectangle(cornerRadius: BSRadius.l, style: .continuous)
            )
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: BSRadius.l, style: .continuous)
                        .strokeBorder(BSColor.separator, lineWidth: BSChartStroke.rule)
                }
            }
    }
}
