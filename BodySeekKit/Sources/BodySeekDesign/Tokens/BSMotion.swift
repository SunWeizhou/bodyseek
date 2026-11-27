import SwiftUI

/// V6 动效令牌。
///
/// Apple 用阻尼比和响应时间描述弹簧：阻尼比 1.0 表示不回弹，越小越弹；响应时间表示多快到达目标，不是时长。
/// 默认不回弹，回弹只用于带动量的手势松手。交互动画只用弹簧，保证可以在任意时刻被打断。
public enum BSMotion {
    /// 默认弹簧：展开、收起、切换、位置变化。响应 0.35，阻尼比 1.0（不回弹）。
    public static var standard: Spring { Spring(response: 0.35, dampingRatio: 1.0) }

    /// 按压缩放弹簧。响应 0.15，阻尼比 1.0（不回弹）。
    public static var press: Spring { Spring(response: 0.15, dampingRatio: 1.0) }

    /// 带动量的弹簧，只用于手势松手，例如甩走回执、拖拽面板。响应 0.30，阻尼比 0.8。
    public static var momentum: Spring { Spring(response: 0.30, dampingRatio: 0.8) }

    /// 把弹簧转换成动画；开启"减弱动态效果"时降级为 0.2 秒淡入淡出。
    ///
    /// - Parameters:
    ///   - spring: 正常情况下使用的弹簧。
    ///   - reduceMotion: 通常取自 `@Environment(\.accessibilityReduceMotion)`。
    /// - Returns: 对应的 `Animation`。
    public static func animation(_ spring: Spring, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(spring)
    }
}

/// 统一的按压反馈样式：按下的瞬间缩到 0.97 并略微变暗，松开后弹回。
///
/// 取代 `.buttonStyle(.plain)`，后者会去掉系统的按压高亮。
/// 开启"减弱动态效果"时不缩放，只保留亮度变化。
public struct BSPressableStyle: ButtonStyle {
    private static let pressedScale: CGFloat = 0.97
    private static let pressedBrightness: Double = -0.03

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 创建按压反馈样式。
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed && !reduceMotion ? Self.pressedScale : 1)
            .brightness(configuration.isPressed ? Self.pressedBrightness : 0)
            .animation(
                BSMotion.animation(BSMotion.press, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

public extension ButtonStyle where Self == BSPressableStyle {
    /// 便捷写法：`.buttonStyle(.bsPressable)`。
    static var bsPressable: BSPressableStyle { BSPressableStyle() }
}
