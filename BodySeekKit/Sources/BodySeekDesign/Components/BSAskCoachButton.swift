import SwiftUI

/// 浮动的"问 Coach"按钮：iOS 26 使用 Liquid Glass，只用于导航层。
///
/// 开启"降低透明度"时改为 `surface` 实底加描边；macOS 15 没有 Liquid Glass，同样使用实底。
public struct BSAskCoachButton: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let title: String
    private let action: () -> Void

    /// 创建按钮。
    /// - Parameters:
    ///   - title: 按钮文字。
    ///   - action: 带当前页面上下文打开 Coach。
    public init(_ title: String = "问 Coach", action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            chrome(
                Label(title, systemImage: "sparkles")
                    .bsText(.cardTitle)
                    .padding(.horizontal, BSSpace.m)
                    .frame(minHeight: BSSize.hitTarget)
            )
        }
        .buttonStyle(BSPressableStyle())
    }

    @ViewBuilder
    private func chrome<Label: View>(_ label: Label) -> some View {
        if reduceTransparency {
            solid(label)
        } else {
            #if os(iOS)
            label.glassEffect(.regular, in: Capsule())
            #else
            if #available(macOS 26.0, *) {
                label.glassEffect(.regular, in: Capsule())
            } else {
                solid(label)
            }
            #endif
        }
    }

    private func solid<Label: View>(_ label: Label) -> some View {
        label
            .background(BSColor.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(BSColor.separator, lineWidth: BSChartStroke.rule))
    }
}
