# BodySeek 开源图表复用评估

2026-11-20 · 以 `ed7ab2c2` 为基线 · 源码与上游资料核对，尚未跑候选原型

建议先在两张图上试用社区已有实现。一张是**昨夜睡眠分期**，复用 SleepChartKit 的轨道布局与轻量读图方式，验证并修正对缺失时段的处理。另一张是**长期睡眠趋势**，复用已有区间图的表达方式和 Swift Charts 的选点交互。两者沿用 BodySeek 的取数与统计结果，最适合验证减掉自绘控件以后，图表好不好看、好不好读。

## 可复用的实现

| 候选 | 上游证据 | 在 BodySeek 的用途 |
| :--- | :--- | :--- |
| **SleepChartKit v1.2.0** | MIT。纯 SwiftUI 组件接受 `[SleepSample]`，有独立的极简模式、分期配色和显示名称。它的 Canvas 在前后分期不同时会绘制连接线，即使两段之间有时间缺口。GitHub 的最新发行版发布于 2025-10-21。 | **睡眠分期首选参考，可有条件地复用组件代码。** 接入已有去重后分期，连线只用于实际相邻的时段。保留上游许可和归属，另外核对语音反馈和跨午夜时间轴。默认组件直接接入会掩盖部分缺口。 [发行版](https://github.com/DanielJamesTronca/SleepChartKit/releases/tag/v1.2.0) · [许可证](https://github.com/DanielJamesTronca/SleepChartKit/blob/v1.2.0/LICENSE) · [睡眠图入口](https://github.com/DanielJamesTronca/SleepChartKit/blob/v1.2.0/Sources/SleepChartKit/Components/SleepChartView.swift#L65-L83) · [分期连接实现](https://github.com/DanielJamesTronca/SleepChartKit/blob/v1.2.0/Sources/SleepChartKit/Components/SleepTimelineGraph.swift#L124-L147) |
| **AppPear SwiftUICharts 2.0.0** | MIT。公开示例展示折线、条形、共享选点、连续数值轴和轴对齐。2.0.0 发布于 2026-03-02。 | 用于参考轻量折线和共享时间选点。现有公开示例没有证明可以原样覆盖缺失与排除、IQR 与中位数、读屏。通用包不作为本轮生产依赖。 [发行版](https://github.com/AppPear/ChartView/releases/tag/2.0.0) · [示例和许可证](https://github.com/AppPear/ChartView/tree/2.0.0) |
| **Liveline Swift 0.7.0** | MIT。0.7.0 的 Canvas 图库已提供区间带、时间线、箱线图等样式，发行于 2026-08-09。 | 可看其区间图、时间线和示例工作台。BodySeek 早期引入的版本下限为 0.6.1，后续明确移除了该依赖。上游覆盖范围扩大，但同一套健康数据和真机上的体验尚未验证。 [发行版](https://github.com/ParthJadhav/liveline-swift/releases/tag/0.7.0) · [图库和许可证](https://github.com/ParthJadhav/liveline-swift) |
| **DGCharts 5.1.0** | Apache-2.0。iOS 图表基类是 UIKit 视图体系中的 `NSUIView`，源码含内置无障碍支持。GitHub API 报告该发行版发布于 2024-02-16。 | 图型丰富，但 iOS SwiftUI 页面需要桥接，还要适配选点、中文读数和 BodySeek 的数据状态。本轮缺少引入第二个通用绘图体系的具体收益。 [发行版](https://github.com/ChartsOrg/Charts/releases/tag/5.1.0) · [图表基类](https://github.com/ChartsOrg/Charts/blob/5.1.0/Source/Charts/Charts/ChartViewBase.swift) · [许可证](https://github.com/ChartsOrg/Charts/blob/5.1.0/LICENSE) |

其中，AppPear 和 Liveline 适合借鉴社区已经做好的图形与交互。长期趋势的落地优先沿用现有 Swift Charts：系统支持显式区间柱和手指选点，已经足够构成一张「周／月四分位区间带 + 中位点」图。先用系统选点替换重复的手势实现，读数放在固定标题下，减少相邻摘要卡和自定义控件。 [区间柱](https://developer.apple.com/documentation/charts/barmark/init(x:ystart:yend:width:stacking:)) · [系统图表交互示例](https://developer.apple.com/videos/play/wwdc2023/10037/) · [Apple 图表设计指南](https://developer.apple.com/design/human-interface-guidelines/charts)

## 与当前项目的关系

- V3 曾使用 SleepChartKit。M1-UI 的 `0bbf6ce8` 移除了 SleepChartKit 与 Liveline 并把绘图集中到 `BodySeekDesign`。当前图表规范明确禁止第三方渲染套壳，测试会拒绝这两个包的导入。任何准备合入的包依赖都需要通过原型判断收益，再同步更新规范和测试。 [V3 记录](../validation/v3-opensource-ecosystem-2026-11-16.md) · [当前图表规范](chart-grammar.md#1-模块与边界铁律) · [源码门禁](../../BodySeekKit/Tests/BodySeekKitTests/BodySeekChartTests.swift#L233)
- 复用范围留在 `BodySeekDesign` 的绘制和交互层。睡眠输入沿用已有合并结果。趋势输入继续读取 `ChartSeriesSnapshot`，让已知零、缺失和排除可区分，且排除原因可读。相同输入下换渲染组件应保持数值、日期、聚合口径和覆盖率一致。 [图表输入合同](../../BodySeekKit/Sources/BodySeekCore/ChartContracts.swift) · [四态约定](chart-grammar.md#5-四态真值视觉表现honest-representation)

## 原型验收

1. 用同一组固定样本对照现版和原型。睡眠样本覆盖跨午夜、有断档、非常短的分期和未知分期。趋势样本覆盖连续、缺失、已知零、排除和仅少量有效日。逐图核对选中日期、分期区间、聚合统计和单位。
2. 做两张可操作的视图。睡眠分期先看最重要的总时长与时段，拖动可探查单段。长期趋势近看按日，远看按周或月，默认显示可解释的读数和区间。核对竖向可滚、横拖可靠、读数位置稳定。
3. 在 iPhone 尺寸下对照默认字号的中文浅色和深色画面。用 VoiceOver 检查选中的日期、数值及缺失原因。候选组件原样接入、适配源码、复用设计方式三者之中，采用实际通过验收且维护成本最低的方式。

以上是第一轮调研记录。上游发行日期来自各项目的 [GitHub Releases API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)，只表示核对时的最新发行情况。

## 直接接入结果

- **今日睡眠摘要**：`BodySeekDesign` 接入 SleepChartKit 1.2.0 的 `SleepTimelineGraph`。适配层只传数据、阶段色和中文图例。分期只在连续、无重叠的情况下使用上游组件。有缺测或者需要拖动查看具体阶段时，继续使用原有图表。旧图表的分期间连线只用于首尾相接的分期，点到空档时不再跳到邻近分期。 [上游渲染器](https://github.com/DanielJamesTronca/SleepChartKit/blob/v1.2.0/Sources/SleepChartKit/Components/SleepTimelineGraph.swift#L124-L147)
- **长期趋势**：Liveline 已有箱线图，但当前时间域以墙上时钟或尾样本为锚点，选点会吸附到最近有效数据。BodySeek 的 6 个月与 3 年图使用固定日期窗口，选到缺测或排除时要能读到对应状态。该候选现阶段未接入。 [时间域实现](https://github.com/ParthJadhav/liveline-swift/blob/0.7.0/Sources/Liveline/LivelineRenderer.swift#L509-L515) · [选点实现](https://github.com/ParthJadhav/liveline-swift/blob/0.7.0/Sources/Liveline/LivelineInteractionBuilder.swift#L105-L118)
- **其他可视化**：Liveline 已有分类圆环，可评估用于训练详情的单次心率区间分布，零分钟区间仍需在图例呈现。压力的按时分桶和排除原因、能量和恢复的日内/跨天断线、营养的未知状态，后续分别用现成组件和固定样本验证再替换。 [Liveline 图型接口](https://github.com/ParthJadhav/liveline-swift/blob/0.7.0/Docs/API.md)
