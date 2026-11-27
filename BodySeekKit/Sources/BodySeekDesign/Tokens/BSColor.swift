import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// V6 颜色令牌。
///
/// 中性色直接使用系统语义色，深色模式、高对比度和系统配色调整会自动跟随；
/// 五个领域色暂时引用 `BevelTheme` 里的现有值，保持视觉一致。
/// 第一轮不删除、不修改 `BevelTheme`，后续迁移完成后再由 `BSColor` 取代它。
public enum BSColor {
    // MARK: - 中性色（系统语义色）

    /// 页面背景。iOS 使用 `systemGroupedBackground`。
    public static var canvas: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    /// 卡片表面。iOS 使用 `secondarySystemGroupedBackground`。
    public static var surface: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    /// 卡片内的嵌套块、轨道、区间带底色。iOS 使用 `tertiarySystemGroupedBackground`。
    public static var surfaceInset: Color {
        #if canImport(UIKit)
        Color(uiColor: .tertiarySystemGroupedBackground)
        #else
        Color(nsColor: .underPageBackgroundColor)
        #endif
    }

    /// 分隔线与网格线。iOS 使用 `separator`。
    public static var separator: Color {
        #if canImport(UIKit)
        Color(uiColor: .separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }

    /// 选中状态下其余数据的降级色。iOS 使用 `systemGray4`，macOS 使用最接近的 `systemGray`。
    public static var dimmed: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGray4)
        #else
        Color(nsColor: .systemGray)
        #endif
    }

    // MARK: - 领域色（暂时引用 BevelTheme）

    /// 恢复。
    public static var recovery: Color { BevelTheme.recoveryColor }
    /// 睡眠。
    public static var sleep: Color { BevelTheme.sleepColor }
    /// 负荷。
    public static var strain: Color { BevelTheme.strainColor }
    /// 压力。
    public static var stress: Color { BevelTheme.stressColor }
    /// 能量。
    public static var energy: Color { BevelTheme.energyColor }

    // MARK: - 体征色（v4）

    /// 静息心率。
    public static var heart: Color { BevelTheme.heartColor }
    /// 呼吸率。
    public static var respiration: Color { BevelTheme.respirationColor }
    /// 血氧。
    public static var oxygen: Color { BevelTheme.oxygenColor }

    // MARK: - 强调色

    /// App 全局强调色，等于恢复色。
    public static var tint: Color { recovery }
}
