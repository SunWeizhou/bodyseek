# BodySeek 文档导航

> Status: Canonical
> Last reviewed: 2026-11-21（更新 V5 开发入口与 Coach 顶层设计）
> Scope: Vela 仓库文档信息架构、权威层级、阅读顺序与冲突裁决原则
> Does not define: 产品业务细节、代码实现细节

> Platform status: Accepted ADR 0018 确定 iOS 26 平台，ADR 0019 确定 BodySeekKit、GRDB 和 Watch-First 采集架构。工具链由 `.xcode-version` 与 CI 指定。

---

## 1. 快速入门：Agent 推荐阅读顺序

任何进入本仓库的新 Agent 或开发者，必须严格按以下顺序建立认知：

```text
1. docs/PRD.md                  # 第一步：理解唯一当前产品规格、北极星与业务边界
       ↓
2. CONTEXT.md                   # 第二步：掌握唯一领域术语表与认知概念
       ↓
3. docs/adr/README.md (及 ADRs) # 第三步：理解核心技术与架构决策背景
       ↓
4. docs/TECH_ARCHITECTURE.md    # 第四步：掌握真实代码架构与数据流管道
       ↓
5. 专项文档 (AI/评分/设计)       # 第五步：查阅对应模块的实现与协议
   ├── docs/design/v6-blueprint.md      # V6 重构蓝图（Accepted）
   ├── docs/design/design-system.md     # 设计系统（取代 VELA_DESIGN_LANGUAGE.md）
   ├── docs/design/dataviz.md           # 数据可视化规范
   ├── docs/AI_AGENT_SPEC.md       # Coach、今日 AI 建议与 AI 记饮食的现有实现
   ├── docs/design/coach-agent.md  # Coach 产品目标与 Ontology
   ├── docs/design/coach-agent-implementation.md # 近期实施工单与验收
   └── docs/model_cards/        # 对照当前评分引擎与算法版本
```

---

## 2. 文档权威层级与分类清单

### 2.1 权威核心规范（Canonical Specifications）
当产品或技术细节存在疑问时，以下文档拥有最终决定权：

| 文档 | 职责范围 | 状态 |
| :--- | :--- | :--- |
| [`docs/PRD.md`](PRD.md) | **唯一当前产品规格**：产品定位、Primary User、五个一级表面、北极星指标、功能与非目标 | Canonical |
| [`CONTEXT.md`](../CONTEXT.md) | **唯一领域术语表**：Health Signal, Baseline, Brief, Body State, Lived State, Training Decision 等语言定义 | Canonical |
| [`docs/TECH_ARCHITECTURE.md`](TECH_ARCHITECTURE.md) | **技术实现架构**：实际代码架构、GRDB/HealthKit 数据流、状态管理与管道 | Canonical |
| [`docs/design/v6-blueprint.md`](design/v6-blueprint.md) | **V6 重构蓝图**：身体模型层、DailyBrief、AppAction 三级授权、迁移路线（决策见 ADR 0020/0021） | Accepted（2026-11-22） |
| [`docs/design/design-system.md`](design/design-system.md) | **设计系统 v1.0**：令牌、组件、L0–L3 层级、交互与动效、设计门禁 | Accepted（2026-11-22） |
| [`docs/design/dataviz.md`](design/dataviz.md) | **数据可视化规范 v2**：图表令牌、统计头、各组件画法（取代 chart-grammar 的视觉画法） | Accepted（2026-11-22） |
| [`docs/VELA_DESIGN_LANGUAGE.md`](VELA_DESIGN_LANGUAGE.md) | 旧设计语言（Rhythm 视觉语言）。已被 design-system.md 取代，仅供追溯 | Superseded |
| [`docs/AI_AGENT_SPEC.md`](AI_AGENT_SPEC.md) | **V5 AI Agent 开发指南**：生产入口、分路由工具与证据、提案确认、营养估算及验证边界 | Canonical |
| [Coach Agent 顶层设计](design/coach-agent.md) | 私人健康助手、Ontology、数据治理、对话授权与持续跟进 | 已确认设计，待分阶段实现 |
| [Coach 实施工单](design/coach-agent-implementation.md) | 近期开发顺序、证据与写入合同、验收 | 工单 1/2 模拟器闭环已完成，待真机/线上复核 |
| [Coach 数据治理与持续跟进设计](design/coach-data-governance.md) | 目标版本、跨页面数据、时间语义、授权和复盘合同 | 后续设计参考 |
| [`docs/SCORING_SYSTEM_V1_0.md`](SCORING_SYSTEM_V1_0.md) | **旧版评分设计参考**。当前字段与公式对照 `BodySeekCore/BevelScoringEngine.swift` 和对应版本模型卡 | Historical / reconciliation pending |
| [`docs/adr/README.md`](adr/README.md) | **架构决策记录索引**：Accepted 决策为当前依据，Superseded 决策仅供追溯 | Canonical |

### 2.2 辅助材料（Supporting Materials）
为特定工作流、外部参考和测试证据提供支持，不定义产品需求：

| 目录 / 文档 | 职责范围 |
| :--- | :--- |
| [`docs/agents/`](agents/) | Agent 工作流配置（Issue Tracker 规范、分类标签、领域定义） |
| [`docs/collaboration/`](collaboration/) | 双人开发的 GitHub 流程、算法/UI 责任边界、任务和交接模板 |
| [`docs/reference/`](reference/) | 外部竞品设计与 Token 参考素材（**仅供灵感参考，不是功能需求**） |
| [`docs/validation/`](validation/) | 真机测试截图、回归验证报告、UI 证据库 |

### 2.3 归档历史档案（Archived Documents）
历史归档主要位于 `docs/archive/`。根目录不再放置 `START_HERE.md`、`FIRST_MESSAGE.md`、`NEXT_MESSAGE.md`、`DESIGN.md`、`Vela_4.0.md`、`PROGRESS.md`、`ORIGINAL_REQUEST.md`。这些旧文稿只留在归档里，不是现行规格。新 UI 开发者从 [`collaboration/ONBOARDING.md`](collaboration/ONBOARDING.md) 开始。**归档不能作为当前实现的依据**：

| 归档子目录 | 包含内容 |
| :--- | :--- |
| [`docs/archive/product-eras/`](archive/product-eras/) | 历史 PRD、旧蓝图、旧方向文档。从根目录移入的 `DESIGN-signal-intelligence.md`、`Vela_4.0.md`、`PROGRESS-q0-s8-board.md`、`ORIGINAL_REQUEST-2026-08-05.md`。同一份 `Vela_4.0` 历史评述也以 `Vela_4.0-product-review.md` 留在这里，两份都是归档，不是现行文稿。 |
| [`docs/archive/architecture/`](archive/architecture/) | 已过时的架构文档（`bodyseek-modularization-map.md`：BodySeekDomain 时代的模块化路线） |
| [`docs/archive/audits/`](archive/audits/) | 历史稳定性审计与 UI 走查报告（`VELA_3_AUDIT`、`VELA_4_STABILIZATION_REPORT` 等） |
| [`docs/archive/handoffs/`](archive/handoffs/) | 历史 Agent 交接记录（`AGENT_HANDOFF_*`）；含已归档的 `ORIGINAL_REQUEST-2026-08-05.md`（旧 orchestrator 缺陷修复清单，非当前产品规格） |
| [`docs/archive/plans/`](archive/plans/) | 历史 Bevel 对标计划、已完成或废弃的实施计划（`superpowers-plans` 等） |
| [`docs/archive/v2/`](archive/v2/) | Vela 2.0 时代历史架构与规格文档 |

---

旧版 [AI Coach 规格（2026-08-23）](archive/product-eras/AI_AGENT_SPEC-2026-08-23.md) 保留 L1–L4、Wiki 与固定报告设计供追溯。

## 3. 文档冲突裁决规则（Conflict Resolution）

当不同文档之间出现描述不一致时，严格遵循以下优先级判定：

1. **已实现行为**按当前生产接线、工作树与对应验证记录确认。产品目标和约束以现行规格与有效 ADR 为准。
2. **产品定位与需求冲突**：以 [`docs/PRD.md`](PRD.md) 为最高准则；
3. **术语与概念冲突**：以 [`CONTEXT.md`](../CONTEXT.md) 为最高准则；
4. **实现描述冲突**：以当前代码实际实现与 [`docs/TECH_ARCHITECTURE.md`](TECH_ARCHITECTURE.md) 为准；
5. **架构决策背书**：以 [`docs/adr/README.md`](adr/README.md) 中标记为 `Accepted` 的最新有效 ADR 为准；`Superseded` 仅供追溯，未接受的方向不得单独改变代码或发布契约；
6. **归档文档无效原则**：任何位于 `docs/archive/` 下的内容若与当前 Canonical 文档或现行源码冲突，一律视归档内容为已废弃历史。
