# BodySeek Design Language — Native Apple Rhythm

> Status: Canonical
> Last verified: 2026-11-16
> Scope: BodySeek iOS 26 原生视觉系统、Bevel 启发色彩与材质、排版字阶、多维可视化规范与品牌标识
> Does not define: 本地评分算法实现（见 [SCORING_SYSTEM_V1_0.md](SCORING_SYSTEM_V1_0.md)）、业务边界（见 [PRD.md](PRD.md)）
> Supersedes: 旧 Design D 纯黑白单色限制规范（2026-10-26）

---

## 1. 设计总纲（Apple Native + Bevel Clarity）

BodySeek 不再手搓“自定义黑白网页壳”，而是以 **Apple iOS 26 原生系统控件 + Bevel 式温和卡片质感 + Apple 健身级丰富数据可视化** 为唯一设计语言：

1. **System Chrome First（系统壳层优先）**：主导航直接使用 iOS 26 原生 Liquid Glass `TabView`（含 `TabRole.search` 独立圆形问身体入口）、`NavigationStack` 大标题、系统 `Toolbar` 与原生 `Sheet`；不在页面顶部手绘分段下划线，也不在底部长期遮盖聊天条。
2. **Adaptive Grouped Surfaces（系统分组材质）**：浅色模式采用系统分组灰底（`#F2F2F7`）衬托纯白柔和卡片（`#FFFFFF`）；深色模式采用纯黑底（`#000000`）衬托深灰抬升卡片（`#1C1C1E`），辅以极细分隔线或原生 Liquid Glass 浮层。
3. **Semantic Domain Hues（恢复五维指标语义色）**：废除主屏纯黑白限制，为五项独立评分赋予清晰克制的 Apple 语义色，让用户在 0.5 秒内分辨生理维度。
4. **Rich, Honest Visualization（丰富且诚实的可视化）**：优先用环形进度、睡眠阶段甘特条、日内分时面积图、个人基线阴影带、心率区间柱图与训练热力图呈现信息；缺失数据保持虚线空环/断线缺口与 `--`，绝不用 0 或插值掩盖未知状态。
5. **SF Pro + SF Rounded（苹果原生态字体排印）**：取消衬线混搭；正文与标题使用系统 SF Pro（`.default`），核心数值、圆环读数与图表坐标使用 SF Rounded（`.rounded` + `.monospacedDigit()`）。

---

## 2. 色彩系统（Semantic Tokens）

| 角色 | Light | Dark | 用途 |
| :--- | :--- | :--- | :--- |
| **Canvas（系统分组底）** | `#F2F2F7` | `#000000` | 页面根背景 |
| **Card Surface（卡片面）** | `#FFFFFF` | `#1C1C1E` | 内容卡片与列表分组 |
| **Inset / Control（内嵌槽）** | `#E5E5EA` | `#2C2C2E` | 轨道底、胶囊底、次级控件 |
| **Primary Ink** | `.label` | `.label` | 主标题与核心数值 |
| **Secondary Ink** | `.secondaryLabel` | `.secondaryLabel` | 说明文案与单位 |
| **Brand Accent（品牌强调色）** | `#168B70` | `#34D399` | 主品牌互动与恢复强调 |
| **Recovery（恢复）** | `#168B70` | `#34D399` | 恢复环、HRV/RHR 曲线 |
| **Sleep（睡眠）** | `#5E5CE6` | `#8F8DFF` | 睡眠环、睡眠阶段条、时钟 |
| **Strain（负荷）** | `#EA580C` | `#FF8A4C` | 负荷环、TRIMP/心率区间 |
| **Stress（压力）** | `#E11D48` | `#FB7185` | 压力仪表、日内分时压力曲线 |
| **Energy（能量）** | `#D97706` | `#FBBF24` | 能量电量槽、充放电走势 |

> 所有在浅色/深色表面用于正文文本的 token（`ink`、`inkSecondary`、`deviationInk`、`brand`）必须继续通过 `scripts/check_contrast.py`（WCAG AA ≥ 4.5:1）静态门禁。

---

## 3. 品牌视觉与图标（Direction 1 · 精密双弧节律 B）

- **主图标（`BodySeekIcon.icon` / `AppIcon`）**：深邃玄墨午夜底（`#0B101B` → `#141E30`）承载双层精密钛银同心玻璃弧构成的建筑感几何 `B` 徽记，内环间隙透出克制的翡翠微光，支持 iOS 26 Liquid Glass 默认 / 深色 / 透明 / 色调外观。
- **应用内徽记（`BodySeekBrandMark` / `LaunchMark`）**：与主图标严格同源的双轨几何 `B` 轮廓 + SF Pro SemiBold `BodySeek` 字标，替代旧 Vela 紫色帆船与单线草图。

---

## 4. 质量门禁（Quality Gate）

1. **Xcode 26+ / iOS 26.0 原生编译零警告**（`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`）。
2. **Dark / Light + Dynamic Type 完整适配**：正文与数值响应缩放，大字号自动从并排切换为纵向流式布局，不截断、不溢出视口。
3. **无障碍与减动效**：所有图表提供 `AXChartDescriptorRepresentable` 或清晰无障碍摘要；`accessibilityReduceMotion` 开启时停止装饰缩放或转场偏移。
4. **真机与模拟器双图复核**：任何主表面改动均须同时核对 Light 与 Dark 真实 SwiftUI 截图。
