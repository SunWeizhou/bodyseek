# BodySeek Design System v1.0

> 状态：Accepted（2026-11-22，项目负责人批准）
> 日期：2026-11-22
> 适用范围：`BodySeekDesign` 模块，以及 `BodySeekFeatures` 里的全部视图
> 关系：本规范取代 [`VELA_DESIGN_LANGUAGE.md`](../VELA_DESIGN_LANGUAGE.md)；图表的视觉画法由 [dataviz.md](dataviz.md) 取代 [`chart-grammar.md`](chart-grammar.md)，chart-grammar 的四态语义（第 5 章）和 X 轴刻度规则（3.1）继续有效；本规范第 8 章补充图表的使用规则
> 设计依据：Apple 设计原则，来源为 WWDC《Designing Fluid Interfaces》《The Details of UI Typography》《Principles of Great Design》。作者提供的 apple-design 指南原本面向 Web，本规范把它翻译成 SwiftUI 的写法，见第 1 章和第 7 章
> 配套：[V6 重构蓝图](v6-blueprint.md)（产品结构与页面职责）

---

## 0. 为什么需要这份规范

对现有界面代码（`BodySeekFeatures` 与 `BodySeekDesign`）的统计结果：

| 维度 | 现状 | 正式软件的常见做法 |
|---|---|---|
| 内边距取值 | 17 种（1、2、3、4、5、6、7、8、9、10、11、12、14、16、18、24、28），直接写数字 197 处 | 4–6 级 |
| 圆角取值 | 11 种（2–22），直接写数字 55 处 | 2–3 级 |
| 透明度取值 | 15 种以上（0.09–0.75），直接写数字 95 处 | 3–4 级，或改用系统层级色 |
| 固定尺寸 `frame` | 58 处直接写数字 | 由组件内部决定 |
| 颜色 | 31 处 hex 自制颜色，其中 canvas、card、ink 只是在近似系统色 | 直接使用系统语义色 |
| 系统组件 | 自制卡片 78 处；`Gauge` 0 处，`List`/`Form` 不到 10 处 | 能用系统组件就用 |
| 字体 | 518 处使用系统文字样式，固定字号仅 2 处 | ✅ 已经做对 |
| 按压反馈 | 61 处 `.buttonStyle(.plain)`，系统的按压高亮被去掉，按下去没有任何反应 | 按下瞬间就有反馈 |
| 动效 | 全 App 只有 1 处 `withAnimation`；唯一的默认弹簧 `BodySeekMotion.standard` 阻尼为 0.82，会回弹 | 状态变化都有过渡，默认弹簧不回弹 |
| 无障碍设置 | 只有 2 处适配"减弱动态效果"；"降低透明度""增强对比度""区分颜色"三项都没有适配 | 四项全部内置在组件里 |

结论：**手搓感有静态和动态两个来源，都不是 Swift 语言造成的。**
- **静态**：每个数都"差不多"，却没有一套刻度；样式直接写在页面里。
- **动态**：按下去没有反馈，状态瞬间跳变，界面"不会动"。正式软件的质感，有一半来自交互。

本规范只做四件事：

1. **定刻度**：所有尺寸、颜色、字号都只能从有限的令牌（token）里取。
2. **定组件**：页面只允许组合标准组件，不允许在页面里直接写样式。
3. **定层级**：每个页面都按 L0–L3 四层组织，每层有固定的组件和视觉分量。
4. **定交互**：按压、过渡、手势、触觉和无障碍行为全部内置在组件里，遵循 Apple 的流畅界面原则（第 7 章）。

---

## 1. 设计依据与原则

### 1.1 Apple 八条设计原则在 BodySeek 中的落地

**情绪目标：平静、可信。** 按 Apple 的说法，"愉悦"是前七条做对的结果，不是额外加上去的彩带。所以下面每一条决定，都要服务于"让人平静地信任自己的身体数据"。

| # | Apple 原则 | 含义 | BodySeek 的落地 |
|---|---|---|---|
| 1 | **Purpose 目的** | 每个功能都在消耗用户的时间、注意力和信任；先决定不做什么 | L0–L3 层级；实验室准入（蓝图原则 P5）；今日页从 11 个模块减到 5 个 |
| 2 | **Agency 自主** | 让人保持控制；失误能轻松撤销；确认只留给不可逆的操作 | Coach 动作层 A/B/C 三级：A、B 级直接执行并可撤销，只有 C 级弹确认；不滥用确认弹窗 |
| 3 | **Responsibility 责任** | 隐私和安全，AI 场景尤其要防伤害 | 原始 HealthKit 数据不上云；外发前告知；Coach 不做诊断、不宣称因果；伤病期加量这类高风险建议必须附上依据 |
| 4 | **Familiarity 熟悉** | 建立在用户已知的模式上；外观相同的东西行为相同 | 使用系统 TabView、NavigationStack、sheet、List 和系统返回手势；所有分数环点了都进详情；标签按内容命名 |
| 5 | **Flexibility 灵活** | 适配不同情境和能力 | 动态字号到最大档；深浅色；减弱动态效果、降低透明度、增强对比度、区分颜色四项设置；任意页面都能唤起 Coach |
| 6 | **Simplicity 简单而非极简** | 去掉多余的，让核心突出；常用路径在前，进阶在下一层 | L0/L1 占首屏，L3 和实验室下沉；必要时反而要加上下文，例如图表下的覆盖率说明 |
| 7 | **Craft 匠心** | 没有随意的数值，每个间距和时长都能说出理由 | 令牌加门禁；动效参数也是令牌 |
| 8 | **Delight 愉悦** | 想清楚要用户感受到什么，并贯彻到每个决定 | 情绪目标"平静、可信"：不用红色报警，不用彩带庆祝，动效克制 |

**导航（wayfinding）**：每个页面都要回答"我在哪、能去哪、那里有什么、怎么回去"。具体做法见 7.7。

### 1.2 BodySeek 执行原则

| # | 原则 | 落地规则 |
|---|---|---|
| D1 | **系统优先** | 能用系统组件、系统语义色、系统文字样式的地方，一律不自制。自制组件需要说明系统组件为什么不够用。 |
| D2 | **层级先于装饰** | 视觉分量由 L0–L3 层级决定，不由开发者临场决定。一屏只有一个最重的元素。 |
| D3 | **颜色只表达含义** | 颜色只用于五个领域和四态真值；装饰性渐变、光晕、彩色背景全部取消。 |
| D4 | **数字是主角** | 核心数字使用 SF Rounded 等宽数字，单位和说明降一级。 |
| D5 | **诚实可视化** | 缺失、已知为零、排除三种状态各有固定画法（沿用 chart-grammar 第 5 章），绝不用 0 或插值掩盖。 |
| D6 | **一种做法** | 同一种信息在全 App 只用一种组件呈现，例如"与基线比较"永远是 `BSDeltaBadge`。 |
| D7 | **交互即设计** | 交互和视觉一起设计，"分不出哪里是交互、哪里是视觉"。每个可点击元素都有按压反馈，每次状态变化都有过渡，所有动画都可中断（第 7 章）。 |

---

## 2. 设计令牌（Design Tokens）

所有令牌定义在 `BodySeekDesign/Tokens/`。**页面代码禁止出现数字字面量和 hex 颜色**（见第 10 章的门禁）。

### 2.1 间距 `BSSpace`（以 4pt 为单位，共 6 级）

| 令牌 | 值 | 用途 |
|---|---|---|
| `xxs` | 4 | 图标与文字之间、数值与单位之间 |
| `xs` | 8 | 组件内部的紧凑行距、chip 内边距 |
| `s` | 12 | 组件内部的标准行距、两个小组件之间 |
| `m` | 16 | 卡片内边距、页面左右边距 |
| `l` | 24 | 两个区块（Section）之间 |
| `xl` | 32 | 页面顶部 L0 与 L1 之间、页面底部留白 |

**现有取值的映射**：1/2/3 → 删除或改用 `xxs`；5/6/7 → `xs`；9/10/11 → `xs` 或 `s`；14 → `s` 或 `m`；18 → `m`；28 → `l` 或 `xl`。

### 2.2 圆角 `BSRadius`（共 3 级，一律使用 `.continuous` 连续曲率）

| 令牌 | 值 | 用途 |
|---|---|---|
| `s` | 8 | chip、标签、柱状图的柱子、小色块 |
| `m` | 14 | 卡片内的嵌套块（指标格、输入框、内嵌图表底） |
| `l` | 22 | 卡片 |
| `capsule` | — | 按钮、分段胶囊、进度条，使用 `Capsule()` |

- 嵌套形状要同心：内层圆角 = 外层圆角 − 内边距。iOS 26 上优先使用 `ConcentricRectangle` 和 `containerShape`，由系统自动计算。
- 禁止使用 `.cornerRadius()` 修饰符，统一用 `.clipShape(.rect(cornerRadius: BSRadius.l, style: .continuous))`。

### 2.3 颜色 `BSColor`

**① 中性色：全部改用系统语义色，删除自制 hex**

| 令牌 | 系统色 | 取代的现有令牌 |
|---|---|---|
| `canvas` | `Color(.systemGroupedBackground)` | `BevelTheme.canvas` |
| `surface` | `Color(.secondarySystemGroupedBackground)` | `BevelTheme.card` |
| `surfaceInset` | `Color(.tertiarySystemGroupedBackground)` | `surfaceElevated`、`scoreTrack`、`rangeBand` |
| `separator` | `Color(.separator)` | `hairline` |
| 文字一级 / 二级 / 三级 | `.primary` / `.secondary` / `.tertiary`（层级样式） | `ink`、`inkSecondary`、`deviationInk` |

使用系统色后，深色模式、高对比度模式、未来的系统配色调整都会自动跟上，这是"原生感"的重要来源。

**② 领域色：五项指标，每项 3 个色调**

| 领域 | `solid`（图形、环、强调） | `soft`（浅底、区间带） | `text`（彩色文字，需过 AA 对比度） |
|---|---|---|---|
| 恢复 recovery | 现有 `recoveryColor` | solid × 不透明度 `faint` | 深一档，过对比度门禁 |
| 睡眠 sleep | 现有 `sleepColor` | 同上 | 同上 |
| 负荷 strain | 现有 `strainColor` | 同上 | 同上 |
| 压力 stress | 现有 `stressColor` | 同上 | 同上 |
| 能量 energy | 现有 `energyColor` | 同上 | 同上 |

- 品牌色 `brand` 与恢复色合并：只保留 `tint`（App 全局强调色 = 恢复绿）。
- 营养素四态色（达标、偏低、偏高、未知）沿用 chart-grammar 4.2。
- **周期走向色**（趋势页）：变强 = 恢复色，稳定 = 二级文字色，透支 = 负荷色，恢复中 = 睡眠色，数据不足 = 三级文字色。不使用红色报警，与 PRD"不做医疗诊断、不制造焦虑"的原则一致。

**③ 颜色使用规则**

- 一张卡片最多出现**一种**领域色（跨领域对比图除外）。
- 与基线比较的变化值（delta）用二级文字色加箭头表示，不用红绿着色。HRV 升高不一定是"好"，颜色会误导。
- 禁止装饰性渐变。现有的 `BevelAmbientAura`（MeshGradient 背景光晕）删除。

### 2.4 不透明度 `BSOpacity`（共 4 级）

| 令牌 | 值 | 用途 |
|---|---|---|
| `faint` | 0.12 | 领域色浅底（soft 色调）、选中行背景 |
| `muted` | 0.24 | 个人基线区间带、图表网格线 |
| `disabled` | 0.40 | 禁用状态 |
| `scrim` | 0.70 | 遮罩、图片上的文字底 |

**文字和图标不允许用不透明度降级**，一律改用 `.secondary` / `.tertiary` 层级样式。现有 95 处不透明度里，大部分属于这种情况。

### 2.5 字体 `BSText`（共 7 个角色，全部基于系统文字样式，支持动态字号）

| 角色 | 系统样式 | 字重 / 设计 | 用途 |
|---|---|---|---|
| `heroNumber` | `.largeTitle` | bold，rounded，等宽数字 | L0 核心分数 |
| `number` | `.title2` | semibold，rounded，等宽数字 | 指标格数值、图表锁定读数 |
| `pageSection` | `.title3` | semibold | 区块标题 |
| `cardTitle` | `.headline` | — | 卡片标题 |
| `body` | `.body` | — | Coach 解读正文 |
| `label` | `.subheadline` | 二级色 | 单位、指标名、说明 |
| `caption` | `.footnote` | 二级色 | 数据来源、覆盖率、时间戳 |

- 页面大标题使用 `NavigationStack` 的系统大标题（`.navigationBarTitleDisplayMode(.large)`），不自制标题。
- 数值统一写成 `Text(value).bsText(.number)`，由修饰符负责 rounded、等宽数字和 `.contentTransition(.numericText())`。
- **字距：不手动设置 `kerning` 或 `tracking`。** SF Pro 带光学尺寸，系统会按字号自动应用字距表：大字收紧，小字放松。手动设一个固定值，必然在某个字号上出错。
- **行距：使用系统默认值。** 大数字只显示一行；Coach 正文不额外加 `lineSpacing`。
- **层级由字号、字重和颜色层级共同构成。** 需要强调时优先加字重，而不是放大字号。

### 2.6 尺寸 `BSSize`

| 令牌 | 值 | 用途 |
|---|---|---|
| `hitTarget` | 44 | 最小点击区域 |
| `ringL` | 112 | L0 主分数环 |
| `ringM` | 64 | 五项分数里的次级环 |
| `ringS` | 28 | 列表行和 chip 里的小环 |
| `chartMicro` | 32 | 迷你折线（sparkline） |
| `chartCompact` | 120 | 卡片内的小图 |
| `chartStandard` | 200 | 标准图表卡 |
| `chartDetail` | 280 | 详情页的主图 |
| `stroke` | 1 / 2 | 分隔线 / 折线（圆环线宽按尺寸取值：L 10、M 7、S 4） |
| `dismissDistance` | 120 | 拖拽关闭的投射阈值：投射位移超过这个值才关闭 |
| `offscreen` | 600 | 关闭时滑出的目标位移 |

### 2.7 材质与层级

| 层级 | 材质 | 规则 |
|---|---|---|
| 背景 | `canvas` | 每个页面一个 |
| 内容 | `surface` 卡片 | 不加阴影，不加描边 |
| 导航与浮动控件 | Liquid Glass（系统 Tab 栏、工具栏、浮动的"问 Coach"按钮） | **Liquid Glass 只用于导航层，不用在内容卡片上**，这符合 Apple 的设计规范 |
| 临时层 | 系统 `sheet`、`popover`、`confirmationDialog` | 不自制弹层 |

- **不叠加两层半透明材质**，例如不把玻璃按钮放在玻璃工具栏上，否则文字会看不清。
- **彩色放在实底层**，不放在玻璃前景上。玻璃上的小字可以加一档字重来保证可读性，不要用灰色降级。
- **滚动边缘使用系统的滚动边缘效果**（现有 `bodyseekScrollEdgeEffect`），不画 1pt 分隔线。
- **模态与非模态**：需要专注完成的任务（记一餐、训练复盘）用系统 sheet，系统会压暗并后推背景；不阻断流程的信息（动作回执）用不压暗的浮层。
- 降低透明度和增强对比度两种设置下的表现见 7.6。

### 2.8 动效 `BSMotion`

Apple 用两个参数描述弹簧：**阻尼比**（1.0 表示不回弹，越小越弹）和**响应时间**（多快到达目标）。弹簧没有固定时长，响应时间也不是时长。

| 令牌 | 值 | 用途 |
|---|---|---|
| `standard` | `Spring(response: 0.35, dampingRatio: 1.0)` | 默认：展开、收起、切换、位置变化（临界阻尼，不回弹） |
| `press` | `Spring(response: 0.15, dampingRatio: 1.0)` | 按压缩放 |
| `momentum` | `Spring(response: 0.3, dampingRatio: 0.8)` | **只用于**带动量的手势松手，例如甩走回执、拖拽面板 |
| `reduced` | `.easeInOut(duration: 0.2)`，只改透明度 | 开启"减弱动态效果"时，替代以上全部动画 |
| `number` | `.contentTransition(.numericText())` | 数值变化 |

- **默认不回弹。** 现有 `BodySeekMotion.standard` 的阻尼 0.82 会让普通展开也回弹，改为 1.0。回弹只在用户真的"甩"过时出现：甩出去的卡片回弹是自然的，淡入的菜单回弹就显得奇怪。
- **交互动画只用弹簧**，不用固定时长的 `easeInOut` 或 `linear`（`reduced` 除外），原因见 7.2。
- 禁止循环动画，沿用 chart-grammar 规则 3。也要避免全屏移动的背景、约 5 秒一个周期的缓慢摆动，以及明暗突变。
- 触觉反馈规则见 7.5。

### 2.9 图标

- 只使用 SF Symbols，渲染模式统一为 `.hierarchical`。
- 每个领域固定一个符号，在 `MetricKind.systemImage` 里统一定义，页面不得另选。
- 图标大小跟随文字样式，不写固定尺寸。

---

## 3. 层级模型：L0–L3

每个一级页面都用同一个页面骨架 `BSPage` 组织内容。层级决定组件的选择和视觉分量。

```
┌─────────────────────────────────┐
│ 大标题（系统）           工具栏    │
├─────────────────────────────────┤
│ L0 一眼   BSHero                 │  ← 每页唯一的最重元素
│           分数环 / 人体图 / 热量环  │
├─────────────────────────────────┤
│ L1 一句话 BSCoachNote             │  ← Coach 写，每页只有一条
├─────────────────────────────────┤
│ L2 展开   BSSection × N           │  ← 图表卡、指标格、行动行
│           每个 Section 最多 3 张卡  │
├─────────────────────────────────┤
│ L3 明细   BSNavRow 列表           │  ← 跳转二级页
├─────────────────────────────────┤
│ 实验室    BSLabEntry（可选）       │  ← 默认收起
└─────────────────────────────────┘
```

| 层级 | 允许使用的组件 | 规则 |
|---|---|---|
| **L0** | `BSHero` + `BSScoreRing` / `BSBodyMap` / `BSIntakeRing` / `BSVerdictGrid` | 首屏必须完整可见；每页只有一个 Hero |
| **L1** | `BSCoachNote` | 只有一条；内容来自 `DailyBrief.pageNotes`；离线时显示本地模板 |
| **L2** | `BSSection` 内放 `BSChartCard`、`BSMetricTile`、`BSActionRow`、`BSCard` | 一个页面最多 4 个 Section；每个 Section 最多 3 张卡 |
| **L3** | `BSNavRow`（基于系统 `List` 行样式） | 一级页面上只放入口，不放明细内容 |
| **实验室** | `BSLabEntry` | 一个入口行，点进去是二级页 |

**页面骨架的 API 草图**：

```swift
BSPage("今日") {
    BSHero { BSScoreRing.group(scores) }              // L0
} note: {
    BSCoachNote(brief.pageNotes[.today])              // L1
} sections: {
    BSSection("昨夜睡眠") { BSChartCard(.sleepStages(...)) }
    BSSection("关键体征") { BSMetricGrid(vitals) }
    BSSection("今天要不要行动") { ForEach(brief.actions) { BSActionRow($0) } }
} links: {
    BSNavRow("五项指标详情", destination: ...)        // L3
}
```

`BSPage` 内部统一负责：背景色、滚动、页面边距、区块间距、下拉刷新、底部留白、加载骨架屏。**页面代码不再写任何 `padding`、`spacing` 和背景色。**

---

## 4. 组件目录

所有组件都以 `BS` 为前缀，放在 `BodySeekDesign/Components/`。每个组件都必须覆盖四态（有数据、已知为零、缺失、排除）以及加载状态。

### 4.1 结构组件

| 组件 | 说明 | 基于 |
|---|---|---|
| `BSPage` | 页面骨架（见第 3 章） | `ScrollView` + `NavigationStack` |
| `BSSection` | 区块标题 + 可选的"全部"按钮 + 内容 | 系统 `Section` 的标题样式 |
| `BSCard` | 唯一的卡片样式：`surface` 底色、`l` 圆角、`m` 内边距 | — |
| `BSNavRow` | 跳转行：图标 + 标题 + 次要值 + 箭头 | 系统 `NavigationLink` + `LabeledContent` |
| `BSLabEntry` | 实验室入口行，带"实验"标签 | `BSNavRow` |

### 4.2 数据组件

| 组件 | 说明 | 层级 |
|---|---|---|
| `BSScoreRing` | 0–100 分数环：环 + 数字 + 指标名 + 状态词；三种尺寸（L/M/S） | L0 |
| `BSScoreRing.group` | 五项分数的固定排布：首项为大环，其余四项为中环，2×2 排列 | L0 |
| `BSMetricTile` | 指标格：名称、数值 + 单位、`BSDeltaBadge`、可选迷你折线 | L2 |
| `BSMetricGrid` | 指标格的 2 列网格，最大字号时自动变成 1 列 | L2 |
| `BSDeltaBadge` | 与基线比较：箭头 + 变化量 + "vs 28 天"；二级文字色 | L2 |
| `BSVerdictChip` | 周期走向标签：变强 / 稳定 / 透支 / 恢复中 / 数据不足 | L0 / L2 |
| `BSVerdictGrid` | 趋势页 L0：五条轴各一个 `BSVerdictChip` + 一行依据 | L0 |
| `BSIntakeRing` | 营养页 L0：热量环 + 三大宏量营养素进度条 | L0 |
| `BSBodyMap` | 健身页 L0：包装现有 MuscleMap，统一配色和图例 | L0 |
| `BSStateView` | 统一的状态视图：缺失、未授权、空数据、出错，附带原因和下一步操作 | 任意 |

### 4.3 Coach 组件

| 组件 | 说明 |
|---|---|
| `BSCoachNote` | L1 解读条：Coach 徽记 + 一段话 + 依据 chip（点开查看证据）+ "问 Coach" 按钮；标注生成引擎（云端、端侧、本地） |
| `BSActionRow` | 一条行动建议：标题 + 依据 + "执行"按钮；执行后变成回执状态 |
| `BSReceipt` | 动作回执：改了什么、改在哪一天、撤销按钮；A 级动作显示为底部浮层，B 级显示改动前后对比 |
| `BSEvidenceChip` | 数字溯源 chip：指标 · 日期 / 窗口 · 单位；点开后显示原始工具结果 |
| `BSAskCoachButton` | 浮动的 Liquid Glass 按钮，带当前页面上下文打开 Coach |

### 4.4 图表组件

沿用 chart-grammar 里的 8 个图表组件，**另外增加一个外壳 `BSChartCard`**。页面里不能直接放裸图表：

```
┌ BSChartCard ────────────────────┐
│ 标题                  周期切换（可选） │
│ 锁定读数栏（数值 · 日期 · 基线）   │
│ ┌ 图表（BSSize.chartStandard）┐ │
│ └──────────────────────────┘ │
│ 覆盖 23/28 天 · 数据来源        │  ← caption
└────────────────────────────────┘
```

---

## 5. 五个页面的层级规格

| 页面 | L0 一眼 | L1 一句话 | L2 展开（按顺序） | L3 明细 | 实验室 |
|---|---|---|---|---|---|
| **今日** | `BSScoreRing.group`（五项分数） | 今日简报 headline | ① 今天要不要行动（`BSActionRow` × ≤3）② 昨夜睡眠（`BSChartCard` 睡眠分期）③ 关键体征（`BSMetricGrid`：HRV、静息心率、呼吸率、血氧、手腕温度）④ 今日训练与营养（各一行摘要） | 五项指标详情 | — |
| **健身** | `BSBodyMap` + 整体状态（体能、疲劳、状态差三个数） | 今天练什么、避开什么 | ① 待复盘（`BSActionRow`）② 进步（力量、有氧、体型三张 `BSMetricTile`）③ 负荷曲线（`BSChartCard`） | 训练档案、单个动作、动作库 | — |
| **营养** | `BSIntakeRing` | 吃得怎么样、缺什么（点名 1–3 个营养素） | ① 记一餐（主按钮）② 当天餐次（列表）③ 本周热量（`BSChartCard`） | 周月看板、29 项营养素明细、营养目标 | — |
| **趋势** | `BSVerdictGrid`（五条轴的走向） | 这个周期身体在变强还是透支 | ① 各轴趋势图（`BSChartCard` × 5，由周期切换控制）② 五项分数纵览 | 单指标钻取 | 明日预测、规律、N-of-1、归因 |
| **Coach** | 对话流 | — | 动作回执、证据卡 | 记忆、跟进任务、"Coach 做了什么" | — |

**今日页的削减清单**（对照现在的 11 个模块）：

| 现有模块 | 处置 |
|---|---|
| `healthOverviewCard` + `stressAndEnergyRow` | 合并为 L0 的 `BSScoreRing.group` |
| `todayQuickVerdictBanner` | 删除，由 L1 简报取代 |
| `todayActionCard` + `aiSuggestion` | 合并为 L2 ①，内容来自简报 |
| `proactiveInsightsSection` | 删除，并入简报的 `changes` |
| `sleepCard`、`vitalsGrid` | 保留，换成标准组件 |
| `workoutsCard`、`todayNutritionCard` | 各缩成一行摘要，跳转对应页面 |
| `checkInCard` | 改为简报里的一条行动，或通过通知进入 |
| `errorBanner`、`unauthorizedBanner` | 统一为 `BSStateView` |

---

## 6. 状态设计

| 状态 | 表现 | 组件 |
|---|---|---|
| 加载中 | 组件保持原尺寸，套 `.redacted(reason: .placeholder)` 显示骨架，不使用转圈 | 所有数据组件内置 |
| 有数据 | 正常显示 | — |
| 已知为零 | 数值显示 0，并附原因（例如"今日休息"） | 内置 |
| 缺失 | 数值显示 `--`；环只画轨道（虚线只用于表示估算，见数据可视化规范 V5）；附原因和下一步操作 | 内置 |
| 排除 | 数值显示 `--` + 排除原因；图表里画斜纹 | 内置 |
| 未授权 / 出错 | `BSStateView`：图标 + 一句原因 + 一个操作按钮 | `BSStateView` |
| Coach 生成中 | `BSCoachNote` 先显示本地模板，生成完成后原地替换文字 | `BSCoachNote` |

- 缺失值统一显示为 `--`。现有代码里 `--` 和 `—` 混用，需要统一。
- 页面级的出错提示只出现在 L0 上方，一页最多一条。

---

## 7. 交互与动效（Apple 流畅界面原则的 SwiftUI 落地）

核心思路：**界面要像真实物体一样，响应即时、运动连续、带着惯性，而且随时能被抓住改变方向。** SwiftUI 已经内置了其中很多能力（动画可叠加、手势末端的动量预测、系统弹簧），所以规则的重点是"不要把这些能力关掉"，再补上缺的部分。

| Apple 原则（Web 写法） | SwiftUI 对应写法 |
|---|---|
| 在 pointer-down 时给反馈 | `ButtonStyle` 里使用 `configuration.isPressed` |
| 用 Pointer Events 1:1 跟手 | `DragGesture` 的 `translation` 直接驱动位置，不加动画 |
| 用弹簧库从当前值出发 | SwiftUI 弹簧默认从当前呈现值出发，重新定向时保留速度 |
| 速度交接 | `.interpolatingSpring(_:initialVelocity:)`，速度取自 `DragGesture.Value.velocity` |
| 动量投射函数 | `DragGesture.Value.predictedEndTranslation`（系统已经按减速曲线投射好） |
| `backdrop-filter` 半透明层 | Liquid Glass（`glassEffect`、系统 Tab 栏和工具栏）与系统材质 |
| `prefers-reduced-motion` 等媒体查询 | `accessibilityReduceMotion` 等环境值（见 7.6） |
| 按字号设定的 `letter-spacing` | 系统字体自动处理，不手动设置（见 2.5） |

### 7.1 即时响应

- **每个可点击元素在按下的瞬间就给反馈。** 现有 61 处 `.buttonStyle(.plain)` 把系统的按压高亮去掉了，这是"按着发木"的主要原因。统一替换为 `BSPressableStyle`。
- 能用系统按钮样式的地方就用系统样式：`.bordered`、`.borderedProminent`；导航层用 `.glass`。
- **输入路径上不加人为延迟。** SyncEngine 的 3 秒防抖只用于后台同步，不能影响界面反馈。动作层先乐观更新界面，再回填持久化结果。

```swift
public struct BSPressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.spring(BSMotion.press), value: configuration.isPressed)
    }
}
```

### 7.2 跟手与可中断：最重要的一条

> "想法和手势是同时发生的。"任何动画都必须能在任意时刻被打断和反转。

- **交互动画一律使用弹簧。** SwiftUI 的弹簧从当前呈现值出发，重新定向时会继承速度，天然可中断。固定时长曲线、`keyframeAnimator` 和 `PhaseAnimator` 做不到中途被抓住反转，只能用于非交互的装饰性场景，而本规范已经禁止装饰性动画。
- **动画期间不锁输入。** 不使用 `.disabled(isAnimating)` 或 `.allowsHitTesting(false)` 去等动画结束。
- **拖拽时保留抓取偏移**：元素跟着手指走，而不是跳到手指的中心点。
- **二维运动的 X 和 Y 分别做动画。**
- BodySeek 中的应用场景：图表拖动选点（现有 `chartXSelection`，保持 1:1，读数实时更新）、动作回执下滑关闭、证据卡展开和收起。

### 7.3 速度交接与动量投射

手势结束时，动画要以手指当时的速度继续运动，拖拽和动画之间不能有"接缝"。落点由投射位置决定，而不是松手的位置。

```swift
@State private var offset: CGFloat = 0

DragGesture()
    .onChanged { offset = max(0, $0.translation.height) }      // 1:1 跟手
    .onEnded { value in
        let projected = value.predictedEndTranslation.height    // 系统的动量投射
        let target: CGFloat = projected > BSSize.dismissDistance ? BSSize.offscreen : 0
        let distance = max(abs(target - offset), 1)
        withAnimation(.interpolatingSpring(BSMotion.momentum,
                                           initialVelocity: value.velocity.height / distance)) {
            offset = target                                     // 速度归一化：手势速度 ÷ 剩余距离
        }
    }
```

- 自制拖拽越过边界时，用阻力函数做橡皮筋效果，不要硬停：`阻力位移 = 越界量 × 尺寸 × 0.55 ÷ (尺寸 + 0.55 × |越界量|)`。系统 `ScrollView` 已经内置了这个效果。

### 7.4 空间一致性

- **从哪里来，就回哪里去。** 指标卡进入详情页使用 zoom 转场（现有 `bodyseekZoomSource`，共 7 处），返回时缩回原卡片。同样的做法扩展到肌群热图 → 肌群详情、餐次 → 餐次编辑。
- **从触发点出现。** "问 Coach"浮动按钮从按钮位置展开；菜单和 popover 使用系统组件，自动从触发点弹出；sheet 从底部进出。
- **中间帧要指向结果。** 切换周期时，图表沿时间方向平移（切到更长的周期就向左收），而不是原地淡入淡出。

### 7.5 多感官反馈：因果、同步、有用

| 时刻 | 触觉 | 同一帧的视觉 |
|---|---|---|
| 图表选点跨过一个数据点 | `.selection` | 读数栏更新 |
| 动作执行成功（A、B 级） | `.success` | 回执出现 |
| 撤销 | `.impact(weight: .light)` | 回执变成"已撤销" |
| 动作失败 | `.error` | 回执显示失败原因 |

- **因果**：只在真正引起反馈的事件上触发。
- **同步**：触觉和视觉绑定同一个状态值（`sensoryFeedback(_:trigger:)` 与视图用同一个 trigger），不允许一个先一个后。
- **有用**：上表之外的场景一律不加触觉。反馈太多，用户会习惯性地全部忽略。

### 7.6 四项无障碍设置

| 系统设置 | SwiftUI 环境值 | BodySeek 的处理 |
|---|---|---|
| 减弱动态效果 | `accessibilityReduceMotion` | 缩放、位移和弹簧全部换成 `BSMotion.reduced`（0.2 秒淡入淡出）；zoom 转场换成系统默认的推入转场 |
| 降低透明度 | `accessibilityReduceTransparency` | 玻璃浮动按钮改为实底 `surface` |
| 增强对比度 | `colorSchemeContrast == .increased` | 卡片加 `separator` 描边；二级文字升为一级 |
| 区分颜色 | `accessibilityDifferentiateWithoutColor` | 领域色之外加图标或文字；四态用形状和文字区分（空轨道加 `--`、灰色排除带加说明） |

这些行为全部内置在 `BS` 组件里，页面代码不需要单独处理。"减弱动态效果"不是取消反馈，而是换成更温和的反馈。

### 7.7 导航与标签

- **我在哪**：系统大标题。**能去哪**：L3 入口。**怎么回去**：系统返回按钮和边缘返回手势。不自制返回按钮，不拦截边缘返回手势。
- **标签要具体**：按内容命名，例如"昨夜睡眠""本周热量"，不用"概览""更多"这类笼统的词。具体的标签让人能预测点进去会看到什么。
- **控件靠近它影响的内容**：只影响一张卡的控件放在卡片里；影响整页的控件（例如趋势页的周期切换）放在页面顶部。如果一个控件需要说明文字才能看懂，说明它的位置放错了。

### 7.8 原型先行

- **"一个可交互的原型，胜过一百万张静态设计稿。"** 新组件要先在 Gallery 里做出可点、可拖、能切换四态的版本，再接入页面。
- 动效用慢动作检查：在模拟器中打开 Debug → Slow Animations，逐帧观察。
- 静态截图无法验收交互。页面验收时，要录一段操作视频作为证据。

### 7.9 `BSMotion` API 草图

```swift
public enum BSMotion {
    public static let standard = Spring(response: 0.35, dampingRatio: 1.0)
    public static let press    = Spring(response: 0.15, dampingRatio: 1.0)
    public static let momentum = Spring(response: 0.30, dampingRatio: 0.8)

    /// 页面调用这个方法，减弱动态效果时自动降级为淡入淡出
    public static func animation(_ spring: Spring, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(spring)
    }
}
```

---

## 8. 数据可视化的使用规则（补充 chart-grammar）

> 完整规范见 [BodySeek 数据可视化规范 v2](dataviz.md)，包括图表令牌、统计头、每个组件的新画法和可交互原型。下面只列出最核心的规则。

1. **按问题选图**：

| 要回答的问题 | 使用的组件 |
|---|---|
| 0–100 的状态有多好 | `BSScoreRing` |
| 现在的数值和平时比怎么样 | `BSMetricTile` + `BSDeltaBadge` + 迷你折线 |
| 一段时间的分布和走势 | `TrendHorizonChart`（胶囊图 / 折线图） |
| 一天内的变化 | `IntradayBarChart` / `EnergyAreaChart` |
| 睡眠结构 | `SleepStageChart` |
| 两个指标的关系 | `LoadRecoveryComboChart`（只允许这一种双指标图） |
| 周期走向 | `BSVerdictGrid` |

2. **每张卡片只放一张图**；图表高度只能取 `BSSize` 里的 4 档。
3. **个人基线永远可见**：时间序列图都要画个人基线区间带（`muted` 不透明度）和中位线。
4. **结论不放在图里**：图表负责呈现，解读由 L1 的 Coach 负责；图表卡的 caption 只写覆盖率和数据来源。
5. **每张图都要有无障碍描述**（沿用 chart-grammar 第 6 章）。

---

## 9. 文案规则

- 数值和单位之间加空格：`52 ms`、`7 小时 12 分`。
- 日期：当年内写 `11月22日`，跨年写 `2025年11月22日`；相对日期只用"今天"和"昨晚"。
- 指标名称以 `CONTEXT.md` 为准，全 App 统一。
- 状态词每个领域固定 3 档，例如恢复为"充沛 / 平时 / 偏疲劳"，不允许各页面自己造词。
- Coach 文案不出现"证明""导致""诊断"。

---

## 10. 落地与门禁

### 10.1 代码组织

```
BodySeekDesign/
├── Tokens/        BSSpace、BSRadius、BSColor、BSOpacity、BSText、BSSize、BSMotion
├── Components/    第 4 章的全部组件
├── Charts/        现有 8 个图表 + BSChartCard
└── Gallery/       DesignSystemGallery：所有组件 × 四态 × 浅色/深色 × 默认/最大字号
```

- `BevelTheme` 重命名为 `BSColor`。Bevel 是竞品的名字，不应出现在自己的代码里。过渡期保留一个类型别名。
- `DesignSystemGallery` 作为调试入口（启动参数 `-bodyseekGallery`）。它也是视觉评审和截图测试的对象。

### 10.2 令牌 API 草图

```swift
public enum BSSpace { public static let xxs: CGFloat = 4, xs: CGFloat = 8, s: CGFloat = 12,
                      m: CGFloat = 16, l: CGFloat = 24, xl: CGFloat = 32 }
public enum BSRadius { public static let s: CGFloat = 8, m: CGFloat = 14, l: CGFloat = 22 }
public enum BSOpacity { public static let faint = 0.12, muted = 0.24, disabled = 0.40, scrim = 0.70 }

public enum BSTextRole { case heroNumber, number, pageSection, cardTitle, body, label, caption }
public extension View {
    func bsText(_ role: BSTextRole) -> some View { modifier(BSTextModifier(role: role)) }
}
```

### 10.3 设计门禁 `scripts/check_design_system.py`

对 `BodySeekFeatures/` 执行检查（`BodySeekDesign/Tokens` 本身除外）：

| 规则 | 检测方式 | 现有违例数 |
|---|---|---|
| 禁止直接写间距数字 | `.padding(数字)`、`spacing: 数字` | 197 |
| 禁止直接写圆角数字 | `cornerRadius: 数字` | 55 |
| 禁止直接写不透明度 | `.opacity(0.xx)` | 95 |
| 禁止直接写尺寸数字 | `.frame(width/height: 数字)` | 58 |
| 禁止 hex 颜色 | `adaptive("#`、`Color(red:` | 32 |
| 禁止固定字号 | `.font(.system(size:` | 2 |
| 禁止直接画图表 | `import Charts` | 沿用现有门禁 |
| 禁止自制阴影和装饰渐变 | `.shadow(`、`Gradient` | 8 |
| 禁止去掉按压反馈 | `.buttonStyle(.plain)` | 61 |
| 交互动画禁止固定时长曲线 | `.easeInOut(`、`.easeOut(`、`.linear(`（`BSMotion` 内部除外） | 1 |
| 禁止回弹的默认弹簧 | `BSMotion` 之外出现 `dampingFraction` 或 `dampingRatio` | 1 |
| 禁止手动字距 | `.kerning(`、`.tracking(` | 0 |

**执行节奏**：
1. 先以"只报告"模式加入 CI，记录违例数作为基线。
2. 每迁移完一个页面，就把这个页面切换为"阻断"模式。
3. 五个页面全部迁移完成后，整个 `BodySeekFeatures` 改为"阻断"模式。

### 10.4 PR 自查清单

- [ ] 页面只组合了 `BS*` 组件，没有新写数字和颜色
- [ ] 这个页面只有一个 L0，只有一条 L1
- [ ] 四态和加载状态都看过
- [ ] 浅色和深色、默认字号和最大字号四张截图都核对过
- [ ] 每个可点击元素按下时都有反馈
- [ ] 动效可中断，并在模拟器慢动作下检查过；附上操作录屏
- [ ] 打开减弱动态效果、降低透明度、增强对比度，各检查一次
- [ ] 新组件已经加入 Gallery

---

## 11. 迁移顺序

| 步骤 | 内容 | 验收 |
|---|---|---|
| 1 | 建立令牌，`BevelTheme` 改为 `BSColor` 并接入系统色；`BodySeekMotion` 改为 `BSMotion`（阻尼 1.0）；门禁以只报告模式上线 | 构建通过，视觉无明显变化 |
| 2 | 实现第 4 章的组件 + Gallery，组件内置第 7 章的交互行为（按压、可中断、四项无障碍设置） | Gallery 四种组合截图评审通过，交互录屏评审通过 |
| 3 | 今日页按第 5 章重排，门禁切换为阻断 | 今日页零违例；首屏只有 L0 + L1 |
| 4 | 健身页 | 同上 |
| 5 | 营养页 | 同上 |
| 6 | 趋势页（依赖蓝图里的周期走向模型；模型完成前，L0 先显示五项分数纵览） | 同上 |
| 7 | Coach 页与指标详情页；整个 `BodySeekFeatures` 门禁改为阻断 | 全模块零违例 |
| 8 | 删除 `VELA_DESIGN_LANGUAGE.md`、`BevelAmbientAura`，以及 `design/` 下过时的设计稿 | 设计文档只剩本规范和 chart-grammar |

第 1–2 步可以和蓝图的第 0–2 阶段并行进行；第 3 步开始，与蓝图第 3 阶段（每日简报）一起做。
