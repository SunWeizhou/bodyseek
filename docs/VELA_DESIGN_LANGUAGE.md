# Vela Design Language — Calm Rhythm

> Status: Canonical
> Last verified: 2026-10-23
> Scope: Vela 视觉系统、排版层级、颜色规范、交互原则与设计质量门禁
> Does not define: 数据计算算法（见 [SCORING_SYSTEM_V1_0.md](SCORING_SYSTEM_V1_0.md)）、产品业务需求（见 [PRD.md](PRD.md)）

Vela 致力于提供高度私密、沉浸、克制且有生命感的个人身体智能体验，而非通用的数据仪表盘模板。界面完全基于 iOS 原生设计规范，在日常使用中保持安静，在需要行动时清晰笃定。

---

## 1. 核心交互原则（Product Principles）

1. **一个页面先回答一个问题（One screen, one answer）**：每个一级工作区必须优先回答该视图最核心的一个问题，再按需展开支持细节。
2. **内容优先于容器（Content before containers）**：优先使用间距与排版字阶进行视觉分组；仅在表达独立对象或主要行动时使用卡片容器，避免卡片上层层叠卡片。
3. **分数先于结论（Scores before conclusions）**：Today 先让五个独立分数建立直觉，再给一句 Agent 状态表达与下游行动；完整证据链、覆盖度和统计方法下沉至指标详情。
4. **克制而非空洞（Calm, not empty）**：极简界面仍需具备温度与明确的下一步指引；空状态保持紧凑，并始终提供有价值的下一步操作。
5. **缺失不能伪装成正常（Confidence is part of the data）**：数据缺失或未授权时，必须客观反映并调整建议边界，严禁使用虚假数值或伪造正常状态。
6. **原生优先（Native by default）**：优先使用 iOS 系统导航、标准排版层级、Sheets、原生手势、Dynamic Type 与 SF Symbols。
7. **动效服务于解释变化（Motion explains change）**：动效仅用于解释数据状态迁移；开启 Reduce Motion 时转为短淡入或静态呈现，禁止无意义的纯装饰循环动画。

---

## 2. 视觉识别系统（Visual Identity）

BodySeek D 使用单色 **Rhythm** 体系。token 名仍是 `rhythmCanvas` / `rhythmInk` / `accent`，语义已不再是暖灰绿画布。

- **画布背景**：浅色白底、深色纯黑（`rhythmCanvas` `#FFFFFF` / Dark `#000000`）
- **抬升表面**：卡片与输入底（`rhythmCanvasRaised` `#F7F7F8` / Dark `#111112`；`surfaceFloating` `#F2F2F3` / Dark `#1B1B1C`）
- **文字体系**：墨色正文（`rhythmInk` `#111111` / Dark `#F2F2F2`），次级 `rhythmInkSecondary` `#5E5E63` / Dark `#9A9A9E`
- **主操作**：与正文同族的墨色，而不是节律绿（`accent` / `rhythmDeep` `#111111` / Dark `#FFFFFF`）
- **五项指标色**：主屏幕保持单色；Recovery / Sleep / Strain / Stress / Energy 的色相只用于 Watch 与小组件
- **状态色**：只表达错误、安全或明确好坏，不装饰画布
- **品牌主对象**：
  - **主屏幕**：名称是 BodySeek，图标是既有深色字母 B。节律地平线不再充当 App Icon；
  - **健康地平线（Rhythm Horizon）**：作为个人基线、时间序列与偏离检测的趋势语言，主要用于 Trends，不再占据 Today Hero；
  - **训练节律（Training Rhythm）**：展示背、胸、肩、腿、手臂/核心的柔性轮转路径。

---

## 3. 三个主表面与对话层（Primary Surfaces + Conversation）

生产壳层与 `VelaMinimalShell.swift` 一致：顶部三段切换三个主表面；Coach 是底部 AskBar 拉起的对话层，不是第四个底部 Tab。

```text
Today (五分身体状态) ── Trends (时间序列与偏离) ── Plan (健康行动安排)
        └── 对话层：AskBar（含听写）+ 页内 Coach + 可展开完整会话
            └── Settings / 记忆 / 数据覆盖（二级；☰ 侧边面板本波不新增对话历史列表）
```

### 3.1 Today（五分身体状态）
- **核心问题**：“我现在身体怎么样？它是否与我的感受一致？”
- **固定层级流**：BodySeek 署名与时间（`.who`）→ Agent 正文（`briefBody` + 约 6pt 行距：现在 → 要不要行动）→ 五项等宽分数条 → 最近变化 → 最多 3 个 FollowUpChips → 一行「今天的安排 · 下一件」→ 底部 AskBar。圆环不出现在 Today 首屏。
- **五分条**：恢复 / 睡眠 / 负荷 / 压力 / 能量等宽、等字号（`instrumentValue` ≈ title2 medium + `monospacedDigit`）；名称用 caption；偏离只用空心圆 + 「低于平时 / 高于平时」。五项平等，没有总分，也没有 3+2 主次圆环。
- **对照行**：偏离摘要降为 ink2 短句，不和 Agent 正文抢对比度。
- **位置稳定**：五个分数不可按每日异常动态换位；稳定的是顺序，不是大小。
- **基线状态克制呈现**：前 7 个有效观察日只增加一行 `初始基线 · n/7 天`；形成后自动消失。Personal Baseline Deviation 只用空心标记，不写置信度辩解。完整计划列表在 Plan，Today 只保留下一件。

### 3.2 Trends（多尺度趋势与指标详情）
- **核心问题**：“最近身体发生了什么长期变化？”
- **层级流**：多尺度时间切换（7d / 30d / 6m / 3y）→ 核心指标卡片（恢复、睡眠、负荷、压力、能量）→ 基线偏离标记 → 二级详情高精图表与分布统计。

### 3.3 Plan（健康行动与安排）
- **核心问题**：“今天该怎么练、下一项是什么？是否需要改计划？”
- **层级流**：今日训练决定（keep / 减量 / 换部位 / 恢复日等）→ 主行动标题 → 稳定日可声明计划无需改动 → `completed/total` 仅作脚注 → 主行动与最多两项辅助行动 → 时间窗与必要边界 → 用户编辑 / 删除 / 替换 / 改期 → Agent 候选行动与确认。
- **交互所有权**：完成与编辑即时写入正式计划；新的身体状态只能生成候选更新，不能覆盖用户安排。

### 3.4 对话层（AskBar + Coach）
- **核心问题**：“为什么会发生这种变化？如何联系不同体征？”
- **入口**：三屏共用底部 AskBar（对话层，不是第四个 Tab）。栏内是 callout 占位、「+」记录、上下文胶囊，以及闲置时对比度最高的墨底白字「说话」胶囊（听写能力保留，`bodyseek-speak`）。有草稿时「说话」换成「发送」。点输入、FollowUpChips 或追问后在当前页展开对话。
- **层级流**：当前上下文 → 对话与结构化 artifact → 计划提案 → 已确认记忆 / Memory Proposal。AI 回复是齐左正文（无气泡）；用户消息是 `surfaceFloating` 细描边气泡。侧边面板可进新对话、记忆、数据覆盖与设置；本波不新增对话历史列表。
- **追问**：Today 在最近变化下最多三个 FollowUpChips；对话里同样最多三个。不用寒暄、通用灵感列表或置信度样板文字占据首屏。
- **入口连续性**：从 Today、Trends、Plan、指标详情、手记、营养或训练进入时，问题必须携带对应的结构化 `screen_context`；界面仍保持同一对话工作台，不复制上游详情页。
- **训练呈现**：训练不再是一级工作区；事前边界进入 Plan，运动现场由 Apple Watch / 系统完成，事后观察进入 Plan 与 Coach。

### 3.5 Settings（设置、权限与控制）
- **定位**：二级 Sheet / 导航子页，不占用三个主表面，也不进入顶部分段；
- **内容**：Apple Health 权限、数据覆盖度、联网 Agent 逐类授权、API Key 管理、计划与记忆确认、数据导出与删除；
- **信任中心层级**：先呈现“身体数据 / 联网 Agent / 计划与长期记忆 / 导出与删除”四项可控制边界，再呈现 Agent 审计日志；失败状态使用警示色，禁止与恢复绿混淆。

### 3.6 首次使用（First Use）
- **一个阶段一个认知目标**：第一屏理解五项身体状态，第二屏理解 Agent 只能解释与提议，第三屏理解 Apple 健康只读授权；
- **视觉连续性**：首屏直接预演五项等宽分数条和底部 AskBar 对话层，让用户进入主界面后无需重新学习；
- **最小输入**：不以训练问卷、模型配置或通知授权打断价值理解；默认计划在本机建立，所有偏好以后可改；
- **可退出权限**：Apple 健康必须提供“稍后连接”；联网 Agent 不在首次使用中预授权；
- **原生质量**：整行交互至少 44pt，支持 Dynamic Type、Reduce Motion、Light / Dark，并在最窄 iPhone 与 Pro Max 验收。

---

## 4. 设计质量门禁（Quality Gate）

每个页面在发布前必须满足以下验收标准：
1. **原型先行**：每个一级工作区先通过可运行高保真原型评审，再进入生产 SwiftUI；Today 至少验证三种结构和五种状态（稳定、Recovery 低、Strain/Stress 高、部分缺失、Lived State 不一致）；
2. **模式适配**：同时通过 Light / Dark 模式的色彩对比度校验；
3. **文字缩放**：完整支持 Dynamic Type 大号字阶，无文本截断或布局重叠；
4. **动效适配**：按压立即反馈，交互可打断；开启 Reduce Motion 时所有过渡降级为静态或短淡入；
5. **数据状态**：稳定、偏离、缺失、同步中、Lived State 不一致都不得破坏层级；
6. **辅助功能**：圆环不是唯一编码，VoiceOver 必须读出分数方向、偏离、覆盖度与详情入口；
7. **设备尺寸**：在 ADR 0017 shipping floor（iOS 17 / watchOS 10）支持的最窄 iPhone 与 Pro Max 尺寸上通过布局测试；iOS 26 能力仅作渐进增强，不作为布局验收门槛。
