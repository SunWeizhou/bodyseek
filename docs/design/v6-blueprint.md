# BodySeek V6 重构蓝图：一个身体模型，四个视角，一个大脑

> 状态：Accepted（2026-11-22，项目负责人批准）
> 日期：2026-11-22
> 基线：分支 `codex/ui/ios26-native-bodyseek`，HEAD `34fba68e`
> 依据：作者在 2026-11-22 定下的产品设想，以及对现有代码和文档的全量审阅
> 已取代（见 [ADR 0020](../adr/0020-coach-autonomy-and-action-layer.md)、[ADR 0021](../adr/0021-body-model-layers-and-daily-brief.md)）：ADR 0008（AI 提案、用户确认）里的授权模型，以及 ADR 0012/0019 中与页面职责有关的描述

---

## 0. 一句话定义

**BodySeek 是由 Coach Agent 驱动的个人身体模型。** 本地身体模型负责算出每一个数字；Coach 负责解释、关联、建议，并替用户操作整个 App。五个一级页面是同一个身体模型的五个视角。

```
                 ┌──────────────────────────────────┐
                 │        Coach Agent（大脑）          │
                 │ 每日简报 · 页面解读 · 对话 · 操作 · 跟进 │
                 └──────┬──────────────────┬──────────┘
                  读：工具 │                  │ 写：动作层（AppAction）
 ┌──────────────────────▼──────────────────▼────────────────────┐
 │                       身体模型层（Body Model）                   │
 │  状态模型       肌群与表现模型      营养账本        长期模型         │
 │（五项评分）   （疲劳 · 进步）    （热量 · 营养素）  （周期走向）       │
 └──────────────────────▲───────────────────────────────────────┘
                        │
 ┌──────────────────────┴───────────────────────────────────────┐
 │ 数据层：Apple 健康同步 + 用户主动记录 · 四态真值 · GRDB 唯一存储     │
 └──────────────────────────────────────────────────────────────┘

  今日 → 状态模型     健身 → 肌群与表现模型     营养 → 营养账本
  趋势 → 长期模型     Coach → 大脑本身
```

---

## 1. 五条架构原则（所有改动都要过这五条）

| # | 原则 | 含义 | 违反时的症状（现状） |
|---|---|---|---|
| P1 | **数字归模型，解读归 Coach** | 所有分数、统计和预测都由本地确定性代码算出，Coach 只读不算。回答里的数字必须能溯源到工具结果。 | —（现有四态真值和数字溯源已经做到，需保持） |
| P2 | **数据只有一份** | GRDB 是唯一的持久化存储；每类业务对象只有一个模型。 | SwiftData 和 GRDB 并存，记忆有两种模型 |
| P3 | **写入只走动作层** | 页面按钮和 Coach 调用同一套 `AppAction`；每个动作都会写审计记录，并且可以撤销。 | 各 Reducer 自己写库，刷新时机靠 `AppFeature` 手工协调 |
| P4 | **结论只有一个来源** | 每天由 Coach 生成一份 `DailyBrief`，所有页面只引用它，不再各自产出结论；离线时由本地模板兜底。 | 今日页上有 4–5 个结论来源，互不知情 |
| P5 | **实验室准入** | 新模型和研究功能先放在「实验室」，通过离线回测和 14 天日用验证后才能上一级页面。 | 预测、规律、N-of-1、归因图直接堆在趋势页 |

---

## 2. 身体模型层

身体模型层是 `BodySeekCore` 的核心，只依赖 Foundation，可以在 macOS 上用 `swift test` 回放。每个子模型的输出都带 `AlgorithmVersion`、四态可用性和贡献因子。

### 2.1 状态模型（State Model）→ 服务「今日」

回答「我现在怎么样」。

- **五项独立评分**：恢复、睡眠、负荷、压力、能量。
- **score-v3 的方向**（离线回放胜过 v2 才替换）：
  1. **解耦**：恢复分不再含睡眠分；压力分不再含负荷分；能量分改为独立的日内电量模型，不再由其他四项加权推导。
  2. **个人化尺度**：基线偏离用个人的稳健离散度（MAD 或 IQR）来标准化，替代固定的「基线 × 22%」。
  3. **负荷用心率区间**：负荷分改为基于 TRIMP 或心率区间加权，不再只看动态热量。
  4. **压力剔除训练时段**：计算压力时屏蔽锻炼窗口及其后的恢复期，避免把运动重复计入。
  5. **启用已同步但闲置的信号**：手腕温度、呼吸率、血氧作为恢复分的偏离修正项。
- **验收**：在 BodySeekML 里用 3 年数据回放；以每日打卡体感、次日 HRV 和静息心率作为外部效度，v3 的相关性要胜过 v2，并且五项分数之间的相关性要明显下降。

### 2.2 肌群与表现模型（Muscle & Performance Model）→ 服务「健身」

回答「哪些肌群累了，我有没有在进步」。

| 子模块 | 现状 | 目标 |
|---|---|---|
| 肌群疲劳 | `recovery-heuristic-v1`（指数衰减，用睡眠和 HRV 修正） | 保留；用打卡里的酸痛反馈校准各肌群的时间常数 τ |
| 整体负荷 | ACWR | 改为体能-疲劳双曲线（慢性负荷 CTL、急性负荷 ATL、状态差 TSB），与长期模型共用一套计算 |
| **力量进步** | 未记录表现 | 一句话复盘里顺带解析主项、重量和次数，估算 e1RM，按动作记录趋势 |
| **有氧进步** | VO2max、心率恢复已同步，但未使用 | 跟踪 VO2max、1 分钟心率恢复，以及有氧效率（同心率下的配速或功率） |
| **体型变化** | 体重已同步，体脂和瘦体重未同步 | 新增同步 `bodyFatPercentage`、`leanBodyMass`；体重用 7 天指数移动平均去噪 |

**进步判断**：每个进步维度都输出「上升 / 持平 / 下降 / 数据不足」，并附带窗口、样本数和置信度。

### 2.3 营养账本（Nutrition Ledger）→ 服务「营养」

回答「吃了什么，够不够，偏差在哪里」。

- 保留：记录、食物库、AI 估算（手工值 > 食物库 > AI 估算），热量区间，四态和估算标记。
- 一级页面只展示：热量、三大宏量营养素、纤维、饮水，以及 Coach 点名的 1–3 个营养素缺口。
- 29 项微量营养素放到二级页「营养素明细」，默认收起。
- 饮食建议统一由 Coach 给出（营养页的解读槽位，见 §3.2），营养模块本身不再单独调用大模型生成建议。

### 2.4 长期模型（Longitudinal Model）→ 服务「趋势」

回答「这个周期，我的身体是变强了、稳定，还是在透支」。

**灰箱建模**：骨架用有生理含义的结构，神经网络只学骨架解释不了的残差。

| 轴 | 骨架模型 | 输入 |
|---|---|---|
| 训练适应 | 体能-疲劳模型（Banister / CTL-ATL） | 每日训练负荷 |
| 恢复能力 | HRV 和静息心率的慢基线（28–90 天）及其斜率 | HRV、静息心率 |
| 睡眠 | 睡眠债（相对个人需求的累计差额）、作息规律度 | 睡眠时长、入睡和起床时间 |
| 有氧体能 | VO2max 与心率恢复的平滑趋势 | VO2max、心率恢复 |
| 体型 | 体重 / 体脂的 EMA 和斜率 | 体重、体脂 |

**周期走向判断（核心输出）**：对所选周期（4 周、12 周或 6 个月），每条轴输出：

- 走向：`变强` / `稳定` / `透支` / `恢复中` / `数据不足`
- 依据：起止值、斜率、置信区间、有效样本天数
- 综合判断：由规则汇总，例如「训练适应上升，同时恢复能力下降」→ `透支风险`

Coach 拿到这份结构化结果后，用人话讲给用户听；但走向本身由模型决定，不由大模型决定。

**神经网络的位置**：只作为残差修正器，必须继续通过现有的 walk-forward 配对检验门槛（显著胜过骨架模型才上线）。M4c 已证明纯黑箱模型在当前数据量下没有优势。

---

## 3. Coach：大脑

### 3.1 职责

| 职责 | 说明 | 触发 |
|---|---|---|
| **每日简报** `DailyBrief` | 回答北极星的三个问题：现在怎么样、最近有什么变化、要不要行动 | 早晨后台生成 + 打开 App 时检查是否过期 |
| **页面解读** | 每个一级页面有且只有一个「Coach 解读」槽位 | 进入页面时引用当日简报，或按页面范围增量生成 |
| **对话** | 问答、追问、协同决策 | 用户发起 |
| **操作** | 调用动作层替用户改动 App 中的数据 | 用户指令，或 Coach 主动执行 |
| **跟进** | 持续观察任务（例如「两周后看看咖啡和睡眠的关系」） | 定时或数据到达时 |

### 3.2 `DailyBrief`：唯一的结论对象

```swift
struct DailyBrief: Codable, Sendable {
    let dayKey: DayKey
    let generatedAt: Date
    let modelInputsDigest: String        // 输入快照摘要，数据变化时判定过期
    let engine: BriefEngine              // .cloud / .onDevice / .localTemplate
    let headline: String                 // 一句话：现在怎么样
    let changes: [BriefChange]           // 最近值得注意的变化（附证据键）
    let actions: [BriefAction]           // 要不要行动；每条可直接执行为 AppAction
    let pageNotes: [AppTab: String]      // 各页面解读槽位的文案
    let evidence: [EvidenceRef]          // 所有数字的溯源
}
```

- 取代以下现有来源：`TodayActionGenerator`、`ProactiveInsightEngine`、`generateBriefing`、两处 `generatePageInsight`、今日页的「快速结论条」。
- `TodayActionGenerator` 降级为 `.localTemplate` 引擎：只在离线或模型不可用时使用。
- 持久化到 GRDB 新表 `daily_brief`，按 `dayKey` 和输入摘要缓存；输入变化时标记过期，并重新生成。
- **北极星度量**：简报下方提供「准 / 不准 / 没用」一键反馈，写入 `brief_feedback` 表，形成每周的可信度指标。

### 3.3 动作层 `AppAction` 与高度自主授权

作者选择了**高度自主**。为了在自主的同时守住安全，所有写入统一走动作层，按风险分三级：

| 级别 | 行为 | 例子 |
|---|---|---|
| **A 自动执行** | 直接执行，回执里给出撤销按钮 | 记一餐、补训练标注、记录打卡、保存记忆、跳转页面、开始或结束一个实验 |
| **B 自动执行并突出提示** | 直接执行，展示改动前后对比，24 小时内可撤销 | 修改训练计划、修改营养目标、修改睡眠目标、停用记忆 |
| **C 必须确认** | 先出提案，确认后才执行 | 删除记录、批量操作、清空数据、写回 Apple 健康、向云端发送新的数据类别 |

- 每个 `AppAction` 都定义：输入 schema、风险级别、前置校验、单事务执行、审计快照（before/after）、撤销逻辑。
- 由现有 `ActionProposal` + `ActionExecutor`（v5 审计与撤销）扩展而来，不重写。
- 设置里提供：各级别的总开关、「本周 Coach 做了什么」审计页、一键撤销最近一次操作。
- 见 [ADR 0020：Coach 高度自主与分级动作层](../adr/0020-coach-autonomy-and-action-layer.md)，取代 ADR 0008 的授权部分。

### 3.4 工具面（Coach 读取身体模型的接口）

| 工具 | 读取的子模型 | 状态 |
|---|---|---|
| `get_state`（原 `get_today_context`） | 状态模型 | 已有，需改名并对齐 v3 |
| `get_metric_trend`、`get_weekly_recovery_evidence`、`get_sleep_detail` | 状态模型 / 长期模型 | 已有 |
| `get_muscle_and_performance`（原 `get_workouts_and_muscles`） | 肌群与表现模型 | 已有，需加入进步数据 |
| `get_nutrition_ledger`（原 `get_eating_context`） | 营养账本 | 已有，需补齐微量营养素读取范围 |
| `get_period_assessment` | 长期模型 | **新增** |
| `get_daily_brief`、`get_action_history` | Coach 自身 | **新增** |
| `execute_action(AppAction)` | 动作层 | **新增**，取代三个 `propose_*` 工具 |

---

## 4. 五个页面的规格

### 今日（像 Apple Health / Bevel 的首页）
- **首屏**：五项分数仪表（点击进入详情）→ Coach 一句话简报 → 昨夜睡眠分期 → 关键体征（HRV、静息心率、呼吸率、血氧、手腕温度）。
- **第二屏**：简报里的「要不要行动」（每条可一键执行）、今日训练、营养摘要（只显示一行，跳转到营养页）。
- **移出首屏**：主动洞察卡（并入简报的 `changes`）、快速结论条（并入 `headline`）、打卡卡（改为简报里的一条行动，或通知入口）。

### 健身（身体建模，帮助进步）
- **首屏**：肌群疲劳热图 → 整体负荷（CTL/ATL/TSB）→ 进步卡（力量、有氧、体型三栏）→ Coach 解读。
- **第二屏**：待复盘列表（一句话复盘，Coach 解析，A 级自动执行）、训练档案。
- **二级页**：单个肌群详情、单个动作的 e1RM 曲线、动作库。

### 营养（记录 → AI 统计 → 建议）
- **首屏**：记一餐（文字或照片）→ 今日热量和宏量营养素 → 当天餐次 → Coach 解读（点名 1–3 个缺口）。
- **二级页**：周/月看板、营养素明细（29 项）、营养目标设置。
- 联网搜营养保留在 AI 记餐流程内部，不单独作为功能入口。

### 趋势（周期身体建模）
- **首屏**：周期选择（4 周 / 12 周 / 6 个月 / 3 年）→ **周期走向卡**（五条轴的走向与综合判断）→ Coach 解读。
- **第二屏**：各轴的趋势图（体重、睡眠、HRV、静息心率、VO2max、负荷），以及五项分数纵览。
- **实验室入口**（默认收起）：明日预测、规律发现、N-of-1 实验、特征归因。

### Coach（大脑与对话）
- 对话窗口；动作回执卡（带撤销）；证据卡；记忆管理；跟进任务列表；「Coach 最近做了什么」审计。
- 每个页面都可以带上下文打开 Coach（现有能力，保留）。

---

## 5. 现有功能去留表

| 现有功能 | 处置 | 去向 |
|---|---|---|
| 五项评分 `BevelScoringEngine` | 保留，重构为 v3 | 状态模型 |
| 今日行动卡 `TodayActionGenerator` | 降级 | `DailyBrief` 的离线模板 |
| 主动洞察 `ProactiveInsightEngine` | 合并 | `DailyBrief.changes` |
| 今日 AI 建议 `generateBriefing` | 合并 | `DailyBrief` 的云端 / 端侧引擎 |
| 趋势 / 营养 AI 解读 `generatePageInsight` | 合并 | `DailyBrief.pageNotes` + 按需增量 |
| 今日快速结论条 | 删除 | `DailyBrief.headline` |
| 肌群恢复热图 | 保留 | 健身首屏 |
| ACWR 卡片 | 替换 | CTL/ATL/TSB |
| 待复盘 Inbox + 一句话复盘 | 保留并增强 | 额外解析重量和次数 |
| 手动记组 `ActiveWorkoutSheetView` | 降级 | 二级页补录入口 |
| 组间计时 `RestTimerClient` | 评估 | 与 Watch-First 原则冲突，建议移除 |
| AI 记餐 + 联网搜营养 | 保留 | 营养首屏「记一餐」 |
| 29 项微量营养素看板 | 收起 | 营养二级页 |
| 营养月矩阵、能量平衡 | 保留 | 营养二级页 |
| 明日预测 `PersonalForecasterEngine` | 移入实验室 | 趋势 → 实验室 |
| 规律发现、N-of-1、归因图 | 移入实验室 | 趋势 → 实验室 |
| 双轴图 | 合并 | 各轴趋势图 |
| 三层记忆 | 保留，统一模型 | Coach |
| `propose_*` 三个提案工具 | 替换 | `execute_action` |
| `FitnessStoreClient`（SwiftData） | 迁移后删除 | GRDB |
| `AthleteMemoryItem` 旧记忆模型 | 迁移后删除 | `TieredMemoryRecord` |
| `VelaBackend`（Vapor） | 归档 | 移到 `archive/` 或独立仓库 |
| `LegacyDataImporter` | 保留一个版本后删除 | — |

---

## 6. 代码结构的目标形态

```
BodySeekKit/Sources/
├── BodySeekCore/              纯计算
│   ├── Contracts/             DayKey、HealthObservation、AlgorithmVersion、AppAction 定义
│   ├── StateModel/            五项评分 v3、基线
│   ├── MusclePerformance/     肌群疲劳、CTL/ATL、e1RM、有氧效率、体型
│   ├── NutritionLedger/       营养模型（由 2032 行的 NutritionModels 拆分）
│   └── Longitudinal/          周期走向、灰箱模型、预测（实验室）
├── BodySeekStore/             GRDB 唯一存储
│   ├── Repositories/          按领域拆分现有 2213 行的 BodySeekRepository
│   └── ActionExecutor         动作层执行、审计、撤销
├── BodySeekHealth/            HealthKit 同步（新增体脂、瘦体重）
├── BodySeekAgent/
│   ├── Brief/                 DailyBrief 生成（云端 / 端侧 / 本地模板）
│   ├── Tools/                 工具注册（按子模型拆分 1618 行的 CoachToolRegistry）
│   ├── Actions/               execute_action 与分级授权
│   └── Client/                OpenAI 兼容客户端、Foundation Models 适配
├── BodySeekDesign/
└── BodySeekFeatures/
    ├── App/                   AppFeature 只做 Tab 路由和生命周期
    ├── BodyModelStore/        订阅 GRDB ValueObservation，向各页面广播只读快照
    └── Today/ Workout/ Nutrition/ Trends/ Coach/ Settings/
```

**数据流统一为一条**：

```
写：页面 / Coach → AppAction → ActionExecutor（单事务 + 审计）→ GRDB
读：GRDB → ValueObservation → BodyModelStore → 各页面只读快照
```

页面之间不再互相推送数据。`AppFeature` 里 71 个 action 中的跨页刷新逻辑，由数据库观察自动完成。

---

## 7. 迁移路线

每一步都要能单独上线，前后用现有的金样例和回放夹具对照，不做大爆炸式重写。

| 阶段 | 内容 | 验收 | 预计 |
|---|---|---|---|
| **0 止血** | 冻结新功能；同步 CHANGELOG；归档模块化地图和 `VelaBackend`；清理 `build/` 下的 12 份 DerivedData；把 m3 验证报告里的非 Agent 内容拆回各自文档；写入本蓝图和 ADR 0020 | 文档和代码一致；CI 绿 | 3–5 天 |
| **1 数据层统一** | GRDB 迁移 v7：把 SwiftData 的 4 类数据导入 GRDB，统一记忆模型；删除 `FitnessStoreClient` | 导入 → 重启 → 清空 → 再导入全通过；数据无丢失 | 1 周 |
| **2 读写通路** | 建立 `BodyModelStore`（ValueObservation）；`AppAction` 目录与三级授权；Coach 接入 `execute_action` | 现有 15 个 UI 测试通过；新增「Coach 一句话记一餐 → 营养页刷新 → 撤销」端到端测试 | 1.5 周 |
| **3 每日简报** | `DailyBrief` 对象、三种引擎、缓存与过期；今日页按 §4 做减法；简报反馈 | 今日页只剩一个结论来源；离线也能生成简报；开始记录反馈 | 1 周 |
| **4 状态模型 v3** | BodySeekML 离线回放 → 各项改动逐一验证 → 移植到 Swift → 对拍 | v3 外部效度胜过 v2；五项分数之间的相关性下降；双端误差 ≤ 1e-3 | 2–3 周 |
| **5 健身进步** | 复盘解析重量和次数；e1RM；有氧效率；体型同步；CTL/ATL 替换 ACWR | 进步卡三栏都有数据；数据不足时如实显示 | 1.5 周 |
| **6 周期走向** | 长期模型五条轴 + 综合判断；`get_period_assessment`；趋势页重排；实验室入口 | 用 3 年历史回放，人工抽查 10 个周期的判断是否合理 | 2 周 |
| **7 营养瘦身 & 主动性** | 营养页按 §4 重排；早晨后台生成简报 + 本地通知；跟进任务 | 连续 14 天真机日用，每天都有简报，并记录可信度 | 1.5 周 |

**每个阶段结束都做一次真机验证**：冷启动、后台同步、杀进程重启、线上模型、端侧模型。这一直是现有验证报告里的空白。

---

## 8. 需要新建或更新的文档

| 文档 | 动作 |
|---|---|
| `docs/PRD.md` | 按 §0、§4 重写第 4–5 节 |
| `docs/adr/0020-coach-autonomy-and-action-layer.md` | 新建：高度自主与分级动作层 |
| `docs/adr/0021-body-model-layers-and-daily-brief.md` | 新建：四个子模型、`DailyBrief` 是唯一结论来源 |
| `docs/TECH_ARCHITECTURE.md` | 按 §6 更新 |
| `docs/AI_AGENT_SPEC.md` | 工具面和动作层按 §3 更新 |
| `CONTEXT.md` | 新增术语：Body Model、Daily Brief、AppAction、Period Assessment、实验室 |
| `CHANGELOG.md` | 恢复维护，每个阶段一条 |
| `docs/architecture/bodyseek-modularization-map.md` | 已归档至 `docs/archive/architecture/`（2026-11-22 第一轮） |
| `docs/validation/` | 每个阶段一份独立报告，不再追加进 m3 |

---

## 9. 主要风险

| 风险 | 应对 |
|---|---|
| 高度自主导致误写数据 | A/B 级全部可撤销；C 级必须确认；审计页可见；任何动作都能一键撤销 |
| Coach 依赖云端，离线时页面空白 | `DailyBrief` 有本地模板引擎兜底；所有数字由本地模型计算 |
| score-v3 改变了用户熟悉的分数 | v2 和 v3 并行回放；切换时标注算法版本，历史分数不重算 |
| 迁移期间数据丢失 | 每次迁移都有「导入 → 清空 → 再导入」回归；迁移前自动备份 |
| 再次范围膨胀 | 原则 P5：新功能一律先进实验室 |
