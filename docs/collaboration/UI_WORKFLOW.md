# UI 与交互工作流

UI 主责维护 Today、Trends、Plan、Coach 及其详情页、设计系统和交互证据。

UI 读取算法合同中的分数、方向、覆盖、原因和版本；页面不把缺失值显示成零，不在视图层复制评分公式。每项页面变更都要验证：

- loading、known zero、unknown、`excluded(reason)`；
- 小屏、动态字体、深浅色和无障碍；
- 离线和数据覆盖不足时的表达；
- 同一输入在 Today、Trends 和详情页中的含义一致；
- 当前 SHA 的真实 SwiftUI 截图或录屏。

视觉变化与数据合同变化分开提交，便于回滚和审查。

## 当前源码入口与共享例外

2026-09-06 按当前源码核对；下表是分工约定，不宣称已经完成所有解耦。

| 文件/模块 | 主责与修改方式 |
| --- | --- |
| `VelaApp/Features/Minimal/VelaMinimalTodayView.swift` | UI 主责布局与交互；当前接收 `TodayStore`，数据/刷新行为变更需共同审查 |
| `VelaApp/Features/Trends/TrendsOneMetricChart.swift` | UI 主责图表；缺失日期断线、指标含义等合同保持一致 |
| `VelaApp/Core/Theme/VelaTheme.swift`、`Core/DesignSystem/` | UI 主责设计 token 和通用组件，检查影响到的页面 |
| `VelaApp/Features/Minimal/VelaMetricDetailWidgets.swift`、`VelaMetricDetailLandscapes.swift` | UI 主责视觉与布局 |
| `VelaApp/Features/Today/TodayStore.swift`、`TodayViewState.swift`、`TodayStoreAction.swift` | 共享状态/动作合同；双方确定语义，一位实现 |
| `VelaApp/Features/Trends/TrendsStore.swift`、`TrendsViewState.swift`、`TrendsStoreAction.swift` | 共享序列、日界线和选择状态；不按 UI 目录归属直接修改 |
| `VelaApp/Features/Trends/VelaTrendsView.swift` | 混合宿主：恢复图已接 Store/Chart，但仍有 SwiftData 读取与旧路径；仅布局可独立改，读取/历史筛选共同审查 |
| `VelaApp/Features/Minimal/VelaMetricDetailData.swift` | 含 `MetricRecommendationPolicy` 建议阈值与数据投影；算法/数据主责语义，UI 主责格式需双方核对 |
| `VelaApp/Features/Minimal/VelaMinimalShell.swift`、`VelaApp/App/VelaApp.swift` | 共享装配和导航；由指定一人修改 |
| `VelaApp/Core/Utilities/DailySummaryUseCase.swift`、`Features/SharedComponents/DashboardViewModel.swift` | 算法/数据主责装配与兼容桥接，UI 消费输出 |
| `Vela.xcodeproj/project.pbxproj`、共享模型、schema | 共同审查、单人写入；UI 新文件的工程注册也需协调 |

## 并行工作的交接内容

算法负责人提供同一提交上的输出类型、单位、分数方向、缺失/排除含义、数据窗口与原因字段，以及正常/零/缺失/错误等合成固定输入。UI 可以基于这份合同先做 Preview 或测试，算法同时实现；这些样例不进入生产默认值。合同改变时在同一 Issue 记录改了哪些字段，由 UI 明确适配后集成。

每个 UI PR 附输入场景、SHA（dirty 时附 diff）、设备/系统、语言、动态字体和明暗模式。真实 SwiftUI 截图证明布局；算法正确性由生产路径测试另外证明。
