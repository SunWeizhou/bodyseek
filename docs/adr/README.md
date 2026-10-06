# Architecture Decision Records (ADRs)

> Status: Canonical
> Last verified: 2026-10-06
> Scope: Vela 核心架构决策记录索引、状态与演进关系
>
> 现行软件仍遵守 Accepted ADR。ADR 0017 的部署底线、五项独立分数和 BodySeek/Vela 身份保持有效。Today 仍是 ADR 0012 的 3+2，不把 0012 标成被取代。Superseded 记录只供追溯。

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
| [0008](0008-ai-proposes-user-confirms-plan-changes.md) | AI Proposes, User Confirms Plan Changes | Accepted | 本地确定性规则生成正式计划；AI 只能生成候选 Proposal，重要修改必须经用户显式确认。 |
| [0009](0009-single-user-daily-driver-before-generalization.md) | Single-User Daily Driver Before Generalization | Accepted | 当前阶段优先为产品作者本人的真实数据（~1100 天 Apple 健康数据）与真实习惯打造高可信 Daily Driver 闭环。 |
| [0010](0010-personal-health-brief-as-canonical-product-projection.md) | PersonalHealthBrief as Canonical Product Projection | Accepted | `PersonalHealthBrief` 作为全局权威认知投影对象，训练决策作为下游衍生；一级工作区部分已由 ADR 0012 取代。 |
| [0011](0011-daily-intelligence-assembly-module.md) | Shared Daily Intelligence Assembly Module | Accepted | 两个日常 Adapter 跨同一 Seam；确定性 Module 统一 Body State → Personal Health Brief → Training Decision，并显式注入时间语义。 |
| [0012](0012-score-led-today-and-primary-surfaces.md) | Score-led Today and Primary Surfaces | Accepted | Today 采用固定 3+2 五分层级：恢复/睡眠/负荷为圆环，压力为趋势，能量为余量；一级导航收敛为 Today / Trends / Plan / Coach。 |
| [0013](0013-target-ios-26-and-watchos-26-for-the-rebuild.md) | Target iOS 26 and watchOS 26 | Superseded | 被 ADR 0017 取代；现行 shipping floor 保持 iOS 17 / watchOS 10，iOS 26 能力按可用性渐进增强。 |
| [0014](0014-product-identity-and-primary-surface-labels.md) | Product Identity and Primary Surface Labels | Superseded | 被 ADR 0017 取代；工程身份仍为 Vela，BodySeek 固定为对外产品名。 |
| [0015](0015-platform-floor-and-transition.md) | Platform Floor and Transition | Superseded | 被 ADR 0017 取代；现行 shipping floor 固定为 iOS 17 / watchOS 10。 |
| [0016](0016-widget-scope-for-current-release.md) | Widget Scope for Current Release | Superseded | 被 ADR 0017 吸收；Widget 继续是 bounded preview，不进入当前 critical path。 |
| [0017](0017-bodyseek-architecture-and-product-baseline-v2.md) | BodySeek Architecture and Product Baseline v2 | Accepted | BodySeek/Vela 身份、iOS 17/watchOS 10 floor、纯 Domain Core 与 PR0–PR9 分阶段迁移顺序。 |
