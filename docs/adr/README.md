# Architecture Decision Records (ADRs)

> Status: Canonical
> Last verified: 2026-11-22
> Scope: Vela 核心架构决策记录索引、状态与演进关系
>
> 现行软件以 **ADR 0019 Accepted** 为最新总体架构与 V5 工程基线（`BodySeekCore` 纯领域核心、GRDB 7 本地持久化、原生 Swift Charts 组件族、Watch-First 健身与启发式肌群恢复、Keychain + 轻量双引擎 Agent、Walk-Forward 基线优先个人建模）；`ADR 0018` 的 iOS 26 原生 `TabView` / Liquid Glass 壳层与五域语义色继续作为交互底座，`ADR 0001–0011` 核心边界保持有效。Superseded 记录只供追溯。
>
> 2026-11-22：V6 重构设计获批。[ADR 0020](0020-coach-autonomy-and-action-layer.md)（Coach 高度自主与分级动作层）取代 ADR 0008 的授权部分；[ADR 0021](0021-body-model-layers-and-daily-brief.md)（身体模型层与每日简报）定义四个子模型与唯一结论来源。两者的实施按 [V6 蓝图](../design/v6-blueprint.md) 分阶段进行，落地前代码仍按 V5 行为。

---

## 决策索引清单

| 编号 | 标题 | 状态 | 核心决策摘要 |
| :--- | :--- | :--- | :--- |
| [0001](0001-single-daily-health-computation.md) | Single Daily Health Computation | Accepted | 前台刷新、后台同步与历史回填共用同一个单一、确定性的每日评分计算入口。 |
| [0002](0002-canonical-agent-fact-snapshot.md) | Canonical Agent Fact Snapshot | Accepted | 所有 AI 提示词与工具调用基于确定性、无时区偏差的 Agent Fact Snapshot，排除生成时间噪声。 |
| [0003](0003-independent-scored-health-evidence.md) | Independent Scored Health Evidence | Accepted | 恢复、睡眠、负荷、压力、能量等 5 大评分独立存在，不合并为单一虚假“总健康分”。 |
| [0004](0004-external-in-session-training-execution.md) | External In-Session Training Execution | Accepted | 训练执行与实时心率监控完全由 Apple Watch 承担；iPhone 端不要求用户在训练中手动记组或操作计时器。 |
| [0005](0005-prioritize-health-rhythm-over-compensation.md) | Prioritize Health Rhythm Over Compensation | Accepted | 优先恢复可持续的生活节律；严禁用惩罚性有氧或极端节食来“代偿”过量进食。 |
| [0006](0006-behavior-first-eating-context.md) | Behavior-First Eating Context | Accepted | 饮食记录按行为节律与进食模式理解，不以强制热量/宏量营养素记账为前置条件。 |
| [0007](0007-cross-domain-daily-operating-plan.md) | Cross-Domain Daily Operating Plan | Accepted | 每日行动计划跨域但有界：1 个主行动 + 最多 2 个辅助行动，不做泛日程管理器。 |
| [0008](0008-ai-proposes-user-confirms-plan-changes.md) | AI Proposes, User Confirms Plan Changes | Accepted（授权部分被 0020 取代） | 本地确定性规则生成正式计划；AI 只能生成候选 Proposal，重要修改必须经用户显式确认。 |
| [0009](0009-single-user-daily-driver-before-generalization.md) | Single-User Daily Driver Before Generalization | Accepted | 当前阶段优先为产品作者本人的真实数据（~1100 天 Apple 健康数据）与真实习惯打造高可信 Daily Driver 闭环。 |
| [0010](0010-personal-health-brief-as-canonical-product-projection.md) | PersonalHealthBrief as Canonical Product Projection | Accepted | `PersonalHealthBrief` 作为全局权威认知投影对象，训练决策作为下游衍生；一级工作区部分已由 ADR 0012 取代。 |
| [0011](0011-daily-intelligence-assembly-module.md) | Shared Daily Intelligence Assembly Module | Accepted | 两个日常 Adapter 跨同一 Seam；确定性 Module 统一 Body State → Personal Health Brief → Training Decision，并显式注入时间语义。 |
| [0012](0012-score-led-today-and-primary-surfaces.md) | Score-led Today and Primary Surfaces | Accepted | Today 采用固定 3+2 五分层级：恢复/睡眠/负荷为圆环，压力为趋势，能量为余量；一级导航收敛为 Today / Trends / Plan / Coach。 |
| [0013](0013-target-ios-26-and-watchos-26-for-the-rebuild.md) | Target iOS 26 and watchOS 26 | Superseded | 被 ADR 0017 取代；现行 shipping floor 保持 iOS 17 / watchOS 10，iOS 26 能力按可用性渐进增强。 |
| [0014](0014-product-identity-and-primary-surface-labels.md) | Product Identity and Primary Surface Labels | Superseded | 被 ADR 0017 取代；工程身份仍为 Vela，BodySeek 固定为对外产品名。 |
| [0015](0015-platform-floor-and-transition.md) | Platform Floor and Transition | Superseded | 被 ADR 0017 取代；现行 shipping floor 固定为 iOS 17 / watchOS 10。 |
| [0016](0016-widget-scope-for-current-release.md) | Widget Scope for Current Release | Superseded | 被 ADR 0017 吸收；Widget 继续是 bounded preview，不进入当前 critical path。 |
| [0017](0017-bodyseek-architecture-and-product-baseline-v2.md) | BodySeek Architecture and Product Baseline v2 | Superseded (by 0018 / 0019) | 确立 BodySeek/Vela 身份、纯 Domain Core 与 PR0–PR8 迁移；iOS 17 底线由 ADR 0018 升级，持久化与引擎由 ADR 0019 接续。 |
| [0018](0018-ios26-native-architecture-and-bevel-visual-reset.md) | iOS 26 Native Architecture and Bevel-Inspired Visual Reset | Partially Superseded (by 0019) | 升级 iOS 26.0 部署底线，采用原生 `TabView` + `TabRole.search` Coach + Liquid Glass，废除 Design D 单色限制。 |
| [0019](0019-bodyseek-v5-architecture-and-modeling-baseline.md) | BodySeek V5 Architecture, GRDB Persistence & Modeling Baseline | Accepted | 确立纯 `BodySeekCore`、`score-v2`、GRDB 7、原生 `BodySeekChart`、Watch-First 健身、Keychain/可控 Agent 与 Walk-Forward 基线建模。 |
| [0020](0020-coach-autonomy-and-action-layer.md) | Coach 高度自主与分级动作层 | Accepted | 所有写入统一走 `AppAction` 动作层；A 自动执行、B 自动执行并突出提示（24 小时可撤销）、C 必须确认；取代 ADR 0008 的授权部分。 |
| [0021](0021-body-model-layers-and-daily-brief.md) | 身体模型层与每日简报 | Accepted | 四个身体子模型；`DailyBrief` 是唯一结论来源；数字归模型、解读归 Coach；新功能先进实验室。 |
