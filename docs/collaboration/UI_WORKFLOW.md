# UI 与交互工作流

UI 主责维护今日、健身、营养、趋势、Coach 及其详情页、设计系统和交互证据。计划的日常入口位于今日行动卡。

UI 读取算法合同中的分数、方向、覆盖、原因和版本；页面不把缺失值显示成零，不在视图层复制评分公式。每项页面变更都要验证：

- 加载、已知零、缺失和 `excluded(reason)`；
- 默认字号基线、小屏、深浅色和无障碍；
- 离线和数据覆盖不足时的表达；
- 同一输入在 Today、Trends 和详情页中的含义一致；
- 当前 SHA 的真实 SwiftUI 截图或录屏。

视觉变化与数据合同变化分开提交，便于回滚和审查。

## 当前源码入口与共享例外

2026-11-21 核对 BodySeekKit 入口。下表沿用原协作责任。

| 文件或模块 | 主责与修改方式 |
| --- | --- |
| [BodySeekFeatures/Views](../../BodySeekKit/Sources/BodySeekFeatures/Views/) | UI 主责界面和交互。今日、健身、营养、趋势与 Coach 的展示均由此进入。 |
| [BodySeekDesign](../../BodySeekKit/Sources/BodySeekDesign/) | UI 主责视觉 token、原生图表和通用组件。变更时检查下游页面。 |
| [BodySeekFeatures/Reducers](../../BodySeekKit/Sources/BodySeekFeatures/Reducers/) | 共享 Feature 状态、数据投影和动作合同。涉及刷新、历史筛选、覆盖口径或提案持久化时共同审查。 |
| [VelaApp](../../VelaApp/) 与 `AppFeature` | 共享生产装配和导航。临时固定输入限预览与测试。 |
| [BodySeekCore](../../BodySeekKit/Sources/BodySeekCore/) 与 [BodySeekStore](../../BodySeekKit/Sources/BodySeekStore/) | 算法与数据主责评分、来源、缺失语义、GRDB schema 和 ReadModel。 |
| [V5 AI Agent 开发指南](../AI_AGENT_SPEC.md) | 涉及 Coach、今日 AI 建议或 AI 记饮食时核对工具、证据和确认合同。 |

工程配置、共享模型或 schema 由双方共同审查并指定一位修改。

## 并行工作的交接内容

算法负责人提供同一提交上的输出类型、单位、分数方向、缺失/排除含义、数据窗口与原因字段，以及正常/零/缺失/错误等合成固定输入。UI 可以基于这份合同先做 Preview 或测试，算法同时实现；这些样例不进入生产默认值。合同改变时在同一 Issue 记录改了哪些字段，由 UI 明确适配后集成。

每个 UI PR 附输入场景、SHA（dirty 时附 diff）、设备/系统、语言、动态字体和明暗模式。真实 SwiftUI 截图证明布局；算法正确性由生产路径测试另外证明。
