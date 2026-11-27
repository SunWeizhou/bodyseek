# BodySeek 顶层设计交接

本轮请先做产品与工程顶层设计评审。交付一份设计方案，暂缓修改生产代码。请从 iPhone 与 Apple Watch 的真实使用路径出发，明确用户每天能完成什么，以及后续开发可以按什么顺序验收。

## 阅读顺序

1. [产品规格](../PRD.md) 与 [领域术语](../../CONTEXT.md) 描述产品目标和现有词汇。以个人日用为当前阶段，用户主要通过 Apple Watch 采集，通过 iPhone 理解、复盘与调整。
2. [V6 蓝图](v6-blueprint.md)、[动作层 ADR](../adr/0020-coach-autonomy-and-action-layer.md) 和 [身体模型 ADR](../adr/0021-body-model-layers-and-daily-brief.md) 是已批准的目标结构。请明确哪些决策值得继承、哪些应调整，以及理由。
3. [接手验证报告](../validation/development-takeover-2026-11-27.md) 与 [UI v4 验证](../validation/ui-v4-2026-11-23.md) 记录运行结果和暂未解决的问题。报告中的合成样例、模拟器和历史证据各有适用范围。
4. 从 [应用壳](../../VelaApp/App/VelaApp.swift) 与 [根 reducer](../../BodySeekKit/Sources/BodySeekFeatures/Reducers/AppFeature.swift) 进入源码，按需追到 [健康同步](../../BodySeekKit/Sources/BodySeekHealth/SyncEngine.swift)、[数据观察](../../BodySeekKit/Sources/BodySeekStore/BodyModelStore.swift)、[动作执行](../../BodySeekKit/Sources/BodySeekStore/ActionExecutor+ActionLayer.swift)、[每日简报](../../BodySeekKit/Sources/BodySeekAgent/Brief/DailyBriefGenerator.swift) 和 [Coach 工具](../../BodySeekKit/Sources/BodySeekAgent/CoachToolRegistry.swift)。

## 已知的设计问题

- 五个入口已有各自的职责。以一次真实日用为单位，明确今日、健身、营养、趋势和 Coach 各自承担的决策，解释何处需要跨页，以及研究功能何时可以从实验室提升到主流程。
- HealthKit、GRDB、评分和 TCA 已经连接。健康仪表盘与业务表有两套观察，根 reducer 负责同步多个页面状态。设计应给出读模型的所有权、更新时机、缺测与过期状态，以及日期和时区合同。
- 页面和 Coach 的部分操作已共享执行器，但入口、确认与撤销语义仍不统一。体感打卡同时写偏好文件和 GRDB。设计应说明人工操作、Coach 操作、系统同步的职责，以及提交、重试、审计和撤销如何生效。
- `DailyBrief` 已有三种引擎和缓存。页面规则建议与 Coach 工具派生仍并行。请确定可追溯的数字在哪里产生、跨页面解释如何保持一致、用户如何看见证据及数据出站权限。

## 期望交付

- 一张产品信息架构图和一条完整日用流程，写明各一级页面的职责和成功标准。
- 一张工程架构图，标清数据所有权、读取、写入、Coach 和离线兜底，并说明关键接口的时间、来源和失败语义。
- 有顺序的迁移任务，给出第一条端到端切片、验收条件、数据兼容要求及真机验证范围。
- 用源码或文档指认影响方案的当前事实，标出设计假设和需要项目负责人决定的问题。
