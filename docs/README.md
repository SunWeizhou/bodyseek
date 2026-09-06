# Vela 文档导航与权威层级（Documentation Map）

> Status: Canonical
> Last reviewed: 2026-09-06（交接导航与文档状态）
> Scope: Vela 仓库文档信息架构、权威层级、阅读顺序与冲突裁决原则
> Does not define: 产品业务细节、代码实现细节

> Platform status: Accepted ADR 0017 确定 iOS 17 / watchOS 10 shipping floor；ADR 0013–0016 已被取代。工具链由 `.xcode-version` 与 CI 指定。

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
   ├── docs/VELA_DESIGN_LANGUAGE.md
   ├── docs/AI_AGENT_SPEC.md
   └── docs/SCORING_SYSTEM_V1_0.md
```

---

## 2. 文档权威层级与分类清单

### 2.1 权威核心规范（Canonical Specifications）
当产品或技术细节存在疑问时，以下文档拥有最终决定权：

| 文档 | 职责范围 | 状态 |
| :--- | :--- | :--- |
| [`docs/PRD.md`](PRD.md) | **唯一当前产品规格**：产品定位、Primary User、四大 Tab、北极星指标、功能与非目标 | Canonical |
| [`CONTEXT.md`](../CONTEXT.md) | **唯一领域术语表**：Health Signal, Baseline, Brief, Body State, Lived State, Training Decision 等语言定义 | Canonical |
| [`docs/TECH_ARCHITECTURE.md`](TECH_ARCHITECTURE.md) | **技术实现架构**：实际代码架构、SwiftData/HealthKit 数据流、状态管理与管道 | Canonical |
| [`docs/VELA_DESIGN_LANGUAGE.md`](VELA_DESIGN_LANGUAGE.md) | **设计系统与交互规范**：Rhythm 视觉语言、色板、排版、组件规范、动效与无障碍原则 | Canonical |
| [`docs/AI_AGENT_SPEC.md`](AI_AGENT_SPEC.md) | **AI Agent 与上下文规格**：Canonical Fact Snapshot、Prompting、Wiki 记忆体系与安全协议 | Canonical |
| [`docs/SCORING_SYSTEM_V1_0.md`](SCORING_SYSTEM_V1_0.md) | **旧版评分设计参考**：需要逐项对照当前 `VelaApp/Scoring`；不作为最新输出字段或公式依据 | Historical / reconciliation pending |
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
历史归档主要位于 `docs/archive/`。根目录 `START_HERE.md`、`FIRST_MESSAGE.md`、`NEXT_MESSAGE.md` 及 `tasks/`、`reference/` 是此前导入的接手/执行资料，仍按其原基点保留；新 UI 开发者从 [`collaboration/ONBOARDING.md`](collaboration/ONBOARDING.md) 开始。**严禁将其作为当前代码实现的依据**：

| 归档子目录 | 包含内容 |
| :--- | :--- |
| [`docs/archive/product-eras/`](archive/product-eras/) | 历史 PRD、旧蓝图（`VELA_FULL_STRENGTH_PRODUCT_BLUEPRINT`、`TRAINING_INTELLIGENCE_V3`）、旧方向文档 |
| [`docs/archive/audits/`](archive/audits/) | 历史稳定性审计与 UI 走查报告（`VELA_3_AUDIT`、`VELA_4_STABILIZATION_REPORT` 等） |
| [`docs/archive/handoffs/`](archive/handoffs/) | 历史 Agent 交接记录（`AGENT_HANDOFF_*`） |
| [`docs/archive/plans/`](archive/plans/) | 历史 Bevel 对标计划、已完成或废弃的实施计划（`superpowers-plans` 等） |
| [`docs/archive/v2/`](archive/v2/) | Vela 2.0 时代历史架构与规格文档 |

---

## 3. 文档冲突裁决规则（Conflict Resolution）

当不同文档之间出现描述不一致时，严格遵循以下优先级判定：

1. **产品定位与需求冲突**：以 [`docs/PRD.md`](PRD.md) 为最高准则；
2. **术语与概念冲突**：以 [`CONTEXT.md`](../CONTEXT.md) 为最高准则；
3. **实现与代码冲突**：以当前代码实际实现与 [`docs/TECH_ARCHITECTURE.md`](TECH_ARCHITECTURE.md) 为准；
4. **架构决策背书**：以 [`docs/adr/README.md`](adr/README.md) 中标记为 `Accepted` 的最新有效 ADR 为准；`Superseded` 仅供追溯，未接受的方向不得单独改变代码或发布契约；
5. **归档文档无效原则**：任何位于 `docs/archive/` 下的内容若与当前 Canonical 文档冲突，一律视归档内容为已废弃历史。
