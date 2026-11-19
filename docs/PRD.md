# BodySeek (Vela) Product Requirements Document (PRD)

> Status: Canonical
> Last verified: 2026-11-16
> Scope: 现行 BodySeek 的唯一正式产品规格、核心主线、iOS 26 原生信息架构与功能边界
> External product name: BodySeek; home-screen name: BodySeek; bundle: `com.sunweizhou.Vela4`; engineering/repository identity: Vela
> Does not define: 领域术语严格定义（见 [CONTEXT.md](../CONTEXT.md)）、技术代码架构细节（见 [TECH_ARCHITECTURE.md](TECH_ARCHITECTURE.md)）、架构决策背景（见 [adr/0018-ios26-native-architecture-and-bevel-visual-reset.md](adr/0018-ios26-native-architecture-and-bevel-visual-reset.md)）
> Supersedes: 旧 Design D 单色与顶部分段规格（2026-10-23）

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
Apple Health / Watch 身体信号同步
    ↓
BodySeekDomain.DailyHealthComputation 生成规范 Scored Health Evidence
    ↓
HealthTrendEngine 计算多尺度趋势（7d / 30d / 6m / 3y）
    ↓
Personal Health Brief + DailyIntelligenceAssemblyModule
    ↓
Apple iOS 26 原生 TabView（Liquid Glass 悬浮底栏）
├── Tab 0: 今日（Today）   — 五分彩色仪表盘 + 日内可视化 + 简报 + 感受校准
├── Tab 1: 趋势（Trends）  — 多尺度 Swift Charts 主图 + 五项序列 + 原始体征库
├── Tab 2: 计划（Plan）    — 训练决策 + 用户拥有的每日安排 + 训练轮转热力图
└── Search Role: 问身体（Coach）— 右侧独立悬浮玻璃入口 + 上下文追问工作台
```

---

## 5. 一级信息架构（Apple iOS 26 原生四位一体导航）

生产导航遵循 Apple 官方 iOS 26 Liquid Glass `TabView` 规范，不再手绘顶部分段下划线或底部常驻聊天气泡栏：

```text
BodySeek iOS 26 App (IPHONEOS_DEPLOYMENT_TARGET = 26.0)
├── 底部悬浮 Liquid Glass TabView（随滚动自动收缩 .tabBarMinimizeBehavior(.onScrollDown)）
│   ├── 今日（Today）：NavigationStack + 大标题/工具栏（日期切换、+ 快速记录、个人档案/设置）
│   ├── 趋势（Trends）：NavigationStack + 7d/30d/6m/3y 分段 + Swift Charts 交互主图
│   ├── 计划（Plan）：NavigationStack + 今日定调 + 行动清单 + 训练负荷与轮转分析
│   └── 问身体（Coach · TabRole.search）：右侧独立悬浮圆形玻璃按钮，点开直接进入 Coach 工作台
└── 二级系统页面（标准 NavigationStack Push / Sheet）
    ├── 五项指标详情页（Recovery / Sleep / Strain / Stress / Energy 高精度多图钻取）
    ├── 个人空间 / 设置（Apple 健康授权、数据覆盖、历史回填、信任中心、联网 Agent 授权、导出与清理）
    └── 记录 Sheets（主观感受 Lived State、随手记/实验、体重、血检化验、手动运动/力量回顾）
```

### 5.1 今日（Today）
- **核心定位**：一眼看见五项身体状态、日内生理波动与当前行动结论。
- **Bevel 风格彩色仪表 + 丰富可视化**：
  - **三主环 Hero 卡（Recovery / Sleep / Strain）**：三项各自保留独立语义色（恢复翠绿、睡眠靛蓝、负荷橙红）与个人基线刻度；缺失状态使用虚线空环与 `--`，绝不伪造正常环或合并为单一总健康分；
  - **实时生理双卡（Stress & Energy）**：并排呈现 **日内压力 Swift Charts 曲线**（含运动后 90 分钟排除标识）与 **能量储备充放电条/走势**；
  - **今日解读与感受校准（Brief + Lived State）**：简洁一句话简报（可查看依据或带上下文直接跳转 Coach）+ 一键「一致 / 更差 / 更好 / 不确定」校准；
  - **睡眠阶段条与体征基线对照**：在 Today 直接呈现昨晚睡眠分期微缩条、HRV / 静息心率 / 呼吸率 / 体温 / 血氧相对于个人基线的当前站位，以及今日下一步计划入口。

### 5.2 趋势（Trends）
- **核心定位**：多尺度（7 天、30 天、6 个月、3 年）深度趋势探索与历史信号下钻。
- **交互与图表**：
  - 顶部原生分段控件切换 7d / 30d / 6m / 3y；
  - **交互式 Swift Charts 主图**：五项评分自由切换，支持个人常见范围带（`RectangleMark`）、基线偏离高亮点、手势拖动十字准星 Lollipop 选点、前/后日步进，以及缺失日断线与真实零值区分；
  - **五项对比概览卡 + 原始生理指标库**：完整浏览 HRV、静息心率、睡眠时长、呼吸率、腕温、血氧、活动消耗、步数等，支持直接进入指标详情与历史评分补算检查。

### 5.3 计划（Plan）
- **核心定位**：训练决定优先、用户全权掌控的每日健康安排与长期训练节律。
- **内容与可视化**：
  - **训练决定卡**：清晰给出 Keep / Reduce / Swap / Rest 决定与目标负荷区间；
  - **用户拥有的行动清单**：1 个主行动 + 最多 2 个辅助行动，支持快捷打卡、菜单编辑/删除/改期；Agent 提出实质修改时展示清晰 diff 候选卡，经用户确认后生效；
  - **训练轮转与热力图分析**：展示肌群轮转序列、周/月训练频次热力图、近期运动心率区间分布，以及训记力量数据回顾入口。

### 5.4 问身体（Coach · `TabRole.search`）
- **核心定位**：最贴近苹果原生交互的 AI 生理分析工作台。
- **入口与连续性**：
  - 通过 TabBar 右侧独立悬浮圆形玻璃按钮随时一键直达；同时 Today、Trends、Plan、五项详情页均提供带语义上下文的「问 Coach」入口，点击后自动携带 `CoachScreenContext` 进入对话；
  - 工作台支持本地健康简报兜底、DeepSeek API 流式问答、受控工具调用（`AgentFactSnapshot` + 有界历史查询）、长按复制、听写输入（停止听写不自动发送）、结构化图表 Artifact、以及待确认 Memory / Plan Proposal 卡片。

### 5.5 个人空间与信任控制（Settings）
- 由 Today 工具栏头像或快捷菜单以原生 Sheet / Push 拉起；
- 先展示用户所有权（本地计算、Apple 健康只读、联网 Agent 逐类授权、计划/记忆确认前写入控制、本地导出与清空），再提供数据来源、数据覆盖、三年历史回填、训记同步、模型配置与诊断审计。

### 5.6 首次使用（Onboarding）
- 三步原生引导：五项彩色独立分数预览 → 用户数据主权与 Agent 边界 → Apple 健康只读授权（支持稍后连接，绝不以空白页或问卷阻断使用）。

---

## 6. 数据与 AI 交互边界

| 领域 | 本地计算引擎（Local Engine） | AI Agent / Cloud LLM |
| :--- | :--- | :--- |
| **健康评分** | 唯一负责（`BodySeekDomain` 确定性计算 0–100） | **禁止重算**；仅读取并引用已有分数 |
| **偏离与缺失** | 严格区分 `observed` / `knownZero` / `missing` / `excluded` | 不得把 `--` 编造成 0 或正常值；不得把“对你而言不寻常”夸大成医疗诊断 |
| **原因解释与关联** | 计算统计基线偏离与多尺度趋势 | 提出“候选影响因素”与“观察到的关联”，禁止断言确定生理因果 |
| **每日计划** | 生成默认本地计划与安全约束 | 实质调整生成可审查候选 diff，**必须经用户显式确认** |

---

## 7. 产品非目标（Non-Goals）

1. **不做单一总健康分或虚假生物年龄主指标**：五个分数保持独立，Body State 不包装成第六个分数；
2. **不做训练中手机手动记组工具**：现场采集交给 Apple Watch，手机专注事前决策与事后洞察；
3. **不做强制热量记账与惩罚性代偿运动**：不以“惩罚有氧”抵消饮食波动；
4. **不做医疗诊断**：所有指标仅作个人健康节律参考；
5. **不静默改写用户计划或长期记忆**：必须经过用户显式确认。
