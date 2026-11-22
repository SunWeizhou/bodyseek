# 0021. 身体模型层与每日简报（DailyBrief）

- **Status**: Accepted
- **Date**: 2026-11-22
- **Supersedes / Updates**: 更新 [ADR 0012](0012-score-led-today-and-primary-surfaces.md) 与 [ADR 0019](0019-bodyseek-v5-architecture-and-modeling-baseline.md) 中与页面职责、结论来源有关的描述；ADR 0001–0011 的数据真值、安全与 AI 归属底线继续有效。与 [ADR 0010](0010-personal-health-brief-as-canonical-product-projection.md)（`PersonalHealthBrief` 作为权威投影）的关系见下文第 2 节。
- **Source**: [V6 重构蓝图](../design/v6-blueprint.md) §0–§3；批准人：项目负责人（2026-11-22）。

> 实施状态：本 ADR 确定目标结构。四个子模型、`DailyBrief` 和 `daily_brief` 表按蓝图第 3–6 阶段逐步落地；落地前，今日页等现有结论来源保持原样。

## Context

V5 的现状：

- 今日页有 4–5 个互不知情的结论来源（`TodayActionGenerator`、`ProactiveInsightEngine`、`generateBriefing`、两处 `generatePageInsight`、快速结论条）。
- 五个一级页面是各自独立生长的功能，没有共同的模型作为根基。
- 预测、规律发现、N-of-1、归因图直接堆在趋势页，没有准入门槛。

## Decision

### 1. 一句话定义

**BodySeek 是由 Coach Agent 驱动的个人身体模型。** 本地身体模型负责算出每一个数字；Coach 负责解释、关联、建议，并通过动作层（[ADR 0020](0020-coach-autonomy-and-action-layer.md)）替用户操作整个 App。五个一级页面是同一个身体模型的五个视角。

### 2. 四个身体子模型

身体模型层是 `BodySeekCore` 的核心，只依赖 Foundation，可在 macOS 上用 `swift test` 回放。每个子模型的输出都带 `AlgorithmVersion`、四态可用性和贡献因子。

| 子模型 | 回答的问题 | 服务页面 |
| :--- | :--- | :--- |
| 状态模型 | 我现在怎么样（五项独立评分，score-v3 方向） | 今日 |
| 肌群与表现模型 | 哪些肌群累了，我有没有在进步（肌群疲劳、CTL/ATL/TSB、力量/有氧/体型进步） | 健身 |
| 营养账本 | 吃了什么，够不够，偏差在哪里 | 营养 |
| 长期模型 | 这个周期身体在变强、稳定，还是透支（灰箱建模，周期走向判断） | 趋势 |

Coach 本身是第五个视角，是大脑而不是模型。

### 3. 数字归模型，解读归 Coach

- 所有分数、统计和预测都由本地确定性代码计算，Coach 只读不算。
- 回答里的数字必须能溯源到工具结果（沿用 `NumericProvenanceVerifier`）。
- 周期走向由模型的规则决定，不由大模型决定；Coach 只负责把结构化结果讲成人话。
- 神经网络只作为骨架解释不了的残差修正器，必须继续通过 walk-forward 配对检验门槛（显著胜过骨架模型）才能上线。

### 4. `DailyBrief` 是唯一的结论来源

- 每天由 Coach 生成一份 `DailyBrief`（headline、changes、actions、pageNotes、evidence），所有页面只引用它，不再各自产出结论。
- 三种引擎：云端、端侧、本地模板。`TodayActionGenerator` 降级为 `.localTemplate`，只在离线或模型不可用时使用。
- 持久化到 GRDB 新表 `daily_brief`，按 `dayKey` 和输入摘要缓存，输入变化时标记过期并重新生成。
- 每个一级页面有且只有一个「Coach 解读」槽位，内容来自 `DailyBrief.pageNotes`。
- 北极星度量：简报下方提供「准 / 不准 / 没用」反馈，写入 `brief_feedback` 表。
- `PersonalHealthBrief`（ADR 0010）作为模型输入侧的认知投影保留；面向用户的结论文案统一由 `DailyBrief` 承载，两者的合并方式在蓝图第 3 阶段落地时记录。

### 5. 实验室准入

- 新模型和研究功能（明日预测、规律发现、N-of-1 实验、特征归因）先放在趋势页的「实验室」入口，默认收起。
- 升入一级页面的条件：通过离线回测（BodySeekML），并完成 14 天真机日用验证。
- 新功能一律先进实验室（蓝图原则 P5），开分支前先写一页规格。

### 6. 数据层原则

- GRDB 是唯一持久化存储，每类业务对象只有一个模型（P2）。
- 写入只走动作层，读取走 `ValueObservation` → `BodyModelStore` → 各页面只读快照。

## Consequences

- 页面职责清晰：今日、健身、营养、趋势各对应一个子模型，Coach 是大脑。
- 今日页只剩一个结论来源，离线也有简报；结论质量可以通过反馈度量。
- 新增研究类功能有明确的准入门槛，避免范围再次膨胀。
- 代价：需要分阶段迁移（数据层统一、读写通路、简报、score-v3 等，见蓝图 §7），每阶段都要单独上线并真机验证。
- 在对应阶段完成前，PRD、`TECH_ARCHITECTURE.md`、`AI_AGENT_SPEC.md` 仍描述 V5 现状；它们按蓝图 §8 的清单在各阶段更新。
