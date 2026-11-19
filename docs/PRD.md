# BodySeek (Vela) Product Requirements Document (PRD)

> Status: Canonical
> Last verified: 2026-11-19
> Scope: 现行 BodySeek 的唯一正式产品规格、核心主线、iOS 26 原生信息架构与功能边界
> External product name: BodySeek; home-screen name: BodySeek; bundle: `com.sunweizhou.Vela4`; engineering/repository identity: Vela
> Does not define: 领域术语严格定义（见 [../CONTEXT.md](../CONTEXT.md)）、技术代码架构细节（见 [TECH_ARCHITECTURE.md](TECH_ARCHITECTURE.md)）、架构决策背景（见 [adr/0019-bodyseek-v5-architecture-and-modeling-baseline.md](adr/0019-bodyseek-v5-architecture-and-modeling-baseline.md)）
> Supersedes: 旧 Design D 单色与顶部分段规格（2026-10-23）及独立 Plan Tab 草案（2026-11-16）

---

## 1. 产品定位与核心理念

### 1.1 一句话定位
**BodySeek（工程身份 Vela）是建立在 Apple 健康之上的 iOS 原生个人身体状态仪表与 AI 分析助手：先用五个独立分数、个人基线与丰富生理可视化量化当下状态，再由 Coach 解释变化、支持追问，并把必要的调整组织成用户拥有的日常计划。**

### 1.2 核心原则
> **核心原则**：让用户直观看见“这不是意志力问题，而是身体确实发生了可观察的变化”；Apple 原生质感与清晰多彩的生理可视化负责建立直觉，Coach 负责解释与协同决策。

### 1.3 核心价值层级（不可颠倒）
1. **看见身体数据**：把 Apple Health / Apple Watch 的心率、HRV、睡眠分期、日内压力、能量余量与运动负荷汇聚为高可读原生地带图表；
2. **理解当前状态与长期变化**：通过 Recovery、Sleep、Strain、Physiological Stress、Energy 五条独立时间序列，以及 7天 / 30天 / 6个月 / 3年个人基线，理解身体稳态与偏离；
3. **由 Coach 解释原因、联系不同信号**：AI 分析师提供跨系统关联观察与候选影响因素假设，探讨体征、压力、睡眠与行为之间的联系；
4. **在需要时给出训练与生活建议**：将对身体的理解落地为克制、明确、符合生理负荷边界的行动方案。

---

## 2. 目标用户与使用场景

### 2.1 Primary User（核心用户）
- **定义**：拥有长期真实 Apple 健康数据积累、佩戴 Apple Watch、日常从事高强度脑力/科研工作、保持力量训练习惯且有长期健康管理目标的产品作者本人。
- **阶段原则**：在个人 Daily Driver 阶段，真实作者的连续使用体验、真实 iPhone（iOS 26+）日用观感与真实健康数据闭环是最高优先级需求。

### 2.2 真实使用习惯契约
- **手表主导记录**：Apple Watch 负责全天体征监控、心率采集以及运动现场记录；用户在训练过程中不操作手机记组、记动作；
- **手机主导决策与解释**：iPhone 负责同步数据、计算身体状态、呈现丰富多尺度趋势、由 AI 深度推理原因并给出行动建议；
- **长线柔性轮转**：力量训练按肌群轮转推进（如背、胸、肩、腿、手臂/核心），不强制绑定星期几；
- **保护健康节律**：当短期目标、训练打卡与身体恢复产生冲突时，BodySeek 始终优先保护并恢复可持续的健康节律。

---

## 3. 北极星指标：Trusted Health Brief Day

**`Trusted Health Brief Day`（可信身体简报日）** 是 BodySeek 的唯一北极星标准：
> **评判标准**：一天中，BodySeek 是否可靠地回答了用户的三个根本问题：
> 1. **我现在身体总体怎么样？**（How am I overall right now?）
> 2. **最近发生了什么值得注意的变化？**（What has changed recently?）
> 3. **我是否需要采取行动？**（Do I need to take action?）

- **价值均等原则**：身体状态稳定、无需改变计划的一天，与触发减量或调整的一天具有同等完整的价值；
- **非目标指标**：不以打开次数、停留时长、聊天消息数或单纯刷高健康分数作为北极星。

---

## 4. 核心产品主线

```text
Apple Health / Watch 身体信号同步（SpeziHealthKit + SyncEngine）
    ↓
BodySeekCore.BevelScoringEngine（score-v2）生成规范五项评分与贡献因子
    ↓
28天/90天个人基线 + 多尺度趋势（7d / 30d / 6m / 3y）+ 规律/预测模型
    ↓
Apple iOS 26 原生 TabView（Liquid Glass 悬浮底栏）
├── Tab 0: 今日（Today）   — 3+2 五分彩色仪表 + 今日行动卡 + 每日主观打卡 + AI 简报
├── Tab 1: 健身（Workout） — Watch-First 待复盘 Inbox + 肌群恢复热图 + ACWR 轮转 + 档案
├── Tab 2: 趋势（Trends）  — 原生 Swift Charts 多尺度主图 + 我的规律 + N-of-1 实验 + 指标钻取
└── Search Role: 问身体（Coach）— 右侧独立悬浮玻璃入口 + 本体驱动私人教练与确认提案
```

---

## 5. 一级信息架构（Apple iOS 26 原生四位一体导航）

生产导航遵循 Apple 官方 iOS 26 Liquid Glass `TabView` 与 L1/L2/L3 纵深规范，不再手绘顶部分段下划线或底部常驻聊天气泡栏：

```text
BodySeek iOS 26 App (IPHONEOS_DEPLOYMENT_TARGET = 26.0)
├── 底部悬浮 Liquid Glass TabView（随滚动自动收缩 .tabBarMinimizeBehavior(.onScrollDown)）
│   ├── 今日（Today）：NavigationStack + 五分仪表（状态语义非闭合打卡环）+ 今日行动卡（承接 ADR 0007/0008）+ 每日打卡入口
│   ├── 健身（Workout）：NavigationStack + Watch 待复盘 Inbox + 一句话练后复盘 + 肌群恢复热图 + ACWR 节律
│   ├── 趋势（Trends）：NavigationStack + 7d/30d/6m/3y 原生 Swift Charts + 五项纵览 + 我的规律 / N-of-1 实验
│   └── 问身体（Coach · TabRole.search）：右侧独立悬浮圆形玻璃按钮，点开直接进入 Coach 工作台
└── 二级系统页面（标准 NavigationStack Push / Sheet）
    ├── 五项指标独立详情页（Recovery / Sleep / Strain / Stress / Energy 各自专用排版与原生图型）
    ├── 健身二级页（全部训练档案时间线、单次心率/次日响应分析、动作参考库、手动补录回退入口）
    ├── 个人空间 / 设置（Apple 健康授权、持拍手设置、三年回填、Keychain 模型配置、Outbound 数据审计与重置）
    └── 每日主观体感打卡 Sheet（`DailyCheckIn`：精力 / 情绪 / 主观压力 / 肌群酸痛 / 备注）
```

### 5.1 今日（Today）
- **核心定位**：L1 首屏 3 秒看清五项身体状态、日内波动与今日行动定调。
- **Bevel / Apple Fitness 原生仪表 + L1/L2/L3 纵深**：
  - **三主环 Hero 卡（Recovery / Sleep / Strain）**：三项各自保留独立语义色（恢复翠绿、睡眠靛蓝、负荷橙红）与个人基线刻度；明确表达“当前生理状态储备”而非 Apple 活动环的“闭环达标目标”。缺失/已知零/排除四态严格区分，绝不伪造正常环或合并为单一总健康分；
  - **实时生理双卡（Stress & Energy）**：并排呈现 **日内压力 24h 分色柱**（含运动后排除区淡斜纹标识）与 **能量储备充放电曲线**；
  - **今日行动卡（承接 ADR 0007 / ADR 0008）**：融合一句 AI 状态定调与 1 个主行动 + 至多 2 个辅助行动，支持用户直接完成/编辑；Coach 提案以 diff 候选形式经确认后生效；
  - **每日体感打卡入口（`DailyCheckIn`）**：低摩擦 10 秒采集精力、情绪、主观压力与肌群酸痛，既校准今日解读，也作为个人建模核心标签。

### 5.2 趋势（Trends）
- **核心定位**：3 年纵向数据智能与个人规律探索（7 天、30 天、6 个月、3 年）。
- **交互与图表**：
  - 顶部原生分段控件切换 7d / 30d / 6m / 3y（查询本地 GRDB 预聚合，零卡顿）；
  - **原生 `Swift Charts` 组件族（`BodySeekChart`）**：7d/30d 为带 IQR 基线带与缺失断线的折线图，6m/3y 为周/月 p25–p75 范围胶囊柱 + 中位点；手指拖拽时顶部读数区实时锁定数值并配触觉刻度；
  - **五项对比纵览 +「我的规律 / N-of-1 实验」入口**：展示经样本量与置信区间验证的个人分布滞后规律（严禁对观测模型宣称因果），并提供个人对照实验模板与回测报告查看。

### 5.3 健身（Workout · Watch-First）
- **核心定位**：不打断健身房心流的 Watch-First 训练闭环与启发式肌群恢复导航。
- **L1/L2 结构**：
  - **待复盘 Inbox**：Apple Watch 体能训练结束后自动同步时长、Z1–Z5 心率区间、`WorkoutEffortScore`（区分系统 `EstimatedWorkoutEffortScore`）。用户只需输入或听写一句话练后复盘，经 `FoundationModels` + 中文词典兜底解析成结构化肌群负荷提案，确认后写入账本与审计日志；
  - **交互式肌群恢复热图（`MuscleMap`）**：基于 `recovery-heuristic-v1`（$F_m(t)=\sum L_{m,i}e^{-\Delta t/(\tau_m\alpha)}$，$R_m=e^{-F_m}$，$\alpha$ 仅读取前一晚睡眠与 HRV 偏差）着色，UI 显式标注“启发式估计”；跑步/步行按配速与心率自动分配下肢负荷，羽毛球结合 `dominantHand`（默认右手）分配肩袖/前臂与下肢负荷；
  - **负荷节律卡与二级页**：ACWR 甜蜜区与柔性肌群轮转进度，训练档案时间线、动作参考库与手动记组补录统一收进 L2 二级页。

### 5.4 问身体（Coach · `TabRole.search`）
- **核心定位**：绑定强类型健康数据与受控写回提案的个人身体科学家助手。
- **入口与连续性**：
  - 通过 TabBar 右侧独立悬浮圆形玻璃按钮随时一键直达；Today、Workout、Trends 与五项详情页携带语义上下文一键跳转；
  - 工作台采用自定义 `OpenAICompatibleClient`（默认 DeepSeek，API Key 存 Keychain，仅发送任务型工具聚合结果）与端侧 `FoundationModels`（显式降级日志），支持任务型工具（含 `find_similar_days` 历史相似日、预留 `get_eating_context`）、数字溯源核验（未命中本轮工具结果标注“未核实”）、三层可审阅记忆及可关闭的主动洞察（每日最多 2 条）。

### 5.5 个人空间与信任控制（Settings）
- 由 Today 工具栏头像或快捷菜单拉起；
- 先展示用户所有权（本地计算、Apple 健康只读/受控训练写回、Keychain 凭据、云端发送内容透明审查、确认前写入控制），再提供持拍手配置、3 年断点续传回填进度、模型基线配置、数据导出与一键清空。

### 5.6 首次使用（Onboarding）
- 三步原生引导：五项彩色独立分数预览 → 用户数据主权与 Agent 边界 → Apple 健康只读授权（支持稍后连接，绝不以空白页或问卷阻断使用）。

---

## 6. 数据与 AI 交互边界

| 领域 | 本地计算引擎（Local Engine） | AI Agent / Cloud LLM |
| :--- | :--- | :--- |
| **健康评分** | 唯一负责（`BodySeekCore` `score-v2` 确定性计算 0–100） | **禁止重算**；仅读取并引用已有分数，回复数字须可溯源至本轮工具结果 |
| **偏离与缺失** | 严格区分 `available` / `knownZero` / `missing` / `excluded` | 不得把 `--` 编造成 0 或正常值；不得把“对你而言不寻常”夸大成医疗诊断 |
| **原因解释与关联** | 计算统计基线偏离、规律置信区间与历史相似日 | 提出“候选影响因素”与“观察到的关联”，禁止对观测模型宣称因果或反事实 |
| **每日计划与记录** | 生成默认本地行动建议与安全约束 | 实质调整、记忆写入与练后标注只生成可审查 `ActionProposal`，**必须经用户显式确认** |

---

## 7. 产品非目标（Non-Goals）

1. **不做单一总健康分或虚假生物年龄主指标**：五个分数保持独立，Body State 不包装成第六个分数；
2. **不做训练中手机手动记组工具**：现场采集交给 Apple Watch，手机专注事前决策与事后洞察；
3. **不做强制热量记账与惩罚性代偿运动**：不以“惩罚有氧”抵消饮食波动；
4. **不做医疗诊断**：所有指标仅作个人健康节律参考；
5. **不静默改写用户计划或长期记忆**：必须经过用户显式确认。
