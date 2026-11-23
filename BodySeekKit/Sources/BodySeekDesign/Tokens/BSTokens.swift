import SwiftUI

// V6 设计令牌：间距、圆角、不透明度、尺寸、图表线宽。
// 取值来自 docs/design/design-system.md 第 2 章与 docs/design/dataviz.md 第 2 章。
// 页面和图表代码只能引用这些令牌，不允许直接写数字（见 scripts/check_design_system.py）。

/// 间距令牌，以 4pt 为单位，共 6 级。
public enum BSSpace {
    /// 0：不留间距（紧贴的两个元素）。
    public static let none: CGFloat = 0
    /// 4：图标与文字之间、数值与单位之间。
    public static let xxs: CGFloat = 4
    /// 8：组件内部的紧凑行距、chip 内边距。
    public static let xs: CGFloat = 8
    /// 12：组件内部的标准行距、两个小组件之间。
    public static let s: CGFloat = 12
    /// 16：卡片内边距、页面左右边距。
    public static let m: CGFloat = 16
    /// 24：两个区块（Section）之间。
    public static let l: CGFloat = 24
    /// 32：页面顶部 L0 与 L1 之间、页面底部留白。
    public static let xl: CGFloat = 32
}

/// 圆角令牌，共 3 级。一律配合 `.continuous` 连续曲率使用；按钮和进度条使用 `Capsule()`。
public enum BSRadius {
    /// 8：chip、标签、柱状图的柱子、小色块。
    public static let s: CGFloat = 8
    /// 14：卡片内的嵌套块（指标格、输入框、内嵌图表底）。
    public static let m: CGFloat = 14
    /// 22：卡片。
    public static let l: CGFloat = 22
}

/// 不透明度令牌，共 4 级。文字和图标不用不透明度降级，改用 `.secondary` / `.tertiary` 层级样式。
public enum BSOpacity {
    /// 0.12：领域色浅底（soft 色调）、选中行背景。
    public static let faint: Double = 0.12
    /// 0.24：个人基线区间带、图表网格线、估算部分。
    public static let muted: Double = 0.24
    /// 0.40：禁用状态。
    public static let disabled: Double = 0.40
    /// 0.70：遮罩、图片上的文字底。
    public static let scrim: Double = 0.70
}

/// 尺寸令牌：点击区域、分数环、图表高度，以及拖拽关闭的阈值。
public enum BSSize {
    /// 148：人体肌群图的宽度。
    public static let bodyMapWidth: CGFloat = 148
    /// 245：人体肌群图的高度。
    public static let bodyMapHeight: CGFloat = 245
    /// 8：圆点、色块标记。
    public static let dot: CGFloat = 8
    /// 24：行内图标、固定宽度的小标签。
    public static let glyph: CGFloat = 24
    /// 36：圆形图标底、头像。
    public static let avatar: CGFloat = 36
    /// 44：最小点击区域。
    public static let hitTarget: CGFloat = 44
    /// 112：L0 主分数环。
    public static let ringL: CGFloat = 112
    /// 64：五项分数里的次级环。
    public static let ringM: CGFloat = 64
    /// 28：列表行和 chip 里的小环。
    public static let ringS: CGFloat = 28
    /// 32：迷你折线（sparkline）高度。
    public static let chartMicro: CGFloat = 32
    /// 120：卡片内的小图高度。
    public static let chartCompact: CGFloat = 120
    /// 200：标准图表卡的图表高度。
    public static let chartStandard: CGFloat = 200
    /// 280：详情页主图高度。
    public static let chartDetail: CGFloat = 280
    /// 120：拖拽关闭的投射位移阈值，投射位移超过它才关闭。
    public static let dismissDistance: CGFloat = 120
    /// 600：关闭时滑出的目标位移。
    public static let offscreen: CGFloat = 600
}

/// 图表线宽令牌（单位 pt）。图表代码里的 `lineWidth:` 只能取这些值。
public enum BSChartStroke {
    /// 虚线节奏：只用于"估算 / 预测"部分（数据可视化规范 V5：虚线只表示估算）。
    public static let estimateDash: [CGFloat] = [4, 4]
    /// 0.5：横向网格线。
    public static let grid: CGFloat = 0.5
    /// 1：参考线、选中竖线、分隔线。
    public static let rule: CGFloat = 1
    /// 2：主折线。
    public static let data: CGFloat = 2
    /// 1.5：迷你折线。
    public static let micro: CGFloat = 1.5
    /// 10：`BSSize.ringL` 圆环的线宽。
    public static let ringL: CGFloat = 10
    /// 7：`BSSize.ringM` 圆环的线宽。
    public static let ringM: CGFloat = 7
    /// 4：`BSSize.ringS` 圆环的线宽。
    public static let ringS: CGFloat = 4
}
