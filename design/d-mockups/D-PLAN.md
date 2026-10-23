# BodySeek D 方向落地方案（摘自「BodySeek 视觉改版方案」第三轮，原文为页面源码格式）

代码行号基于 2026-10-22 15:11 的拷贝，可能已偏移，以实际代码为准。

```
      <Section heading="第三轮：选定 D 的落地方案" caption="2026-10-22 第三轮。你选定 D（Agent-first）。下面给出 5 屏 mockup、token 规格、导航改动、组件增删、文档修改和 PR 顺序。代码引用基于 src2 拷贝（VelaApp/…），VT = VelaApp/Core/Theme/VelaTheme.swift，DS = VelaApp/Core/DesignSystem/VelaDesignSystem.swift，Shell = VelaApp/Features/Minimal/VelaMinimalShell.swift。">
        <Callout lead="D 已选定：这一节取代前面 C 方案和 E 方案的结构建议" tone="info">
          选 D 等于接受信息架构变化：底部四个 Tab（今日 / 趋势 / 计划 / Coach）改成顶部三段（今日 / 趋势 / 计划），Coach 不再是 Tab，而是每屏底部常驻的提问栏，点开进入对话。PRD.md:80-87 的四 Tab 结构图和 §5.4（PRD.md:120）必须同步改，否则代码和 PRD 会互相矛盾。
        </Callout>

        <Text>Mockup（393×852 @2x，全部标“示例数据”，HTML 源在 `/workspace/bodyseek/mockups/d/`）：</Text>
        <Table
          columns={["屏幕", "深色", "浅色", "要点"]}
          rows={[
            ["今日", "`mockups/d-today-dark.png`", "`d-today-light.png`", "与已选 D 一致：一条 Agent 消息（现在 → 行动）、五分等宽条、“最近变化”嵌入卡、3 个追问、底部提问栏"],
            ["趋势", "`d-trends-dark.png`", "`d-trends-light.png`", "范围切换 7 天 / 30 天 / 6 个月 / 3 年；一句 30 天小结；五行等高：名称 + 状态、带“常见范围”灰带的迷你折线、今日值；偏离 = 空心圆，图例写明“不代表不好”"],
            ["恢复详情", "`d-recovery-dark.png`", "`d-recovery-light.png`", "全 App 只在这里出现圆环（单色细环）；30 天折线 + 常见范围 52–71；依据 4 行（HRV、静息心率、睡眠分、昨日负荷，各带“平时”值）；一行“置信度 中 · 数据覆盖 主要数据 · 缺：呼吸率”，下附“缺少的数据不会用 0 代替”"],
            ["计划", "`d-plan-dark.png`", "`d-plan-light.png`", "今天 3 项 + 进度；顶部是“BodySeek 建议 · 待你确认”卡（墨色描边，不用警示色），两个等宽按钮：改成减量版 / 保持原计划；完成项变灰，不加删除线"],
            ["对话", "`d-chat-dark.png`", "`d-chat-light.png`", "从“为什么恢复偏低？”追问进入；回答是无气泡正文；内嵌 HRV 14 天证据图（灰带 = 常见范围，今天空心圆）；明确写“不能确定因果”；底部是审批式“计划变更 · 需要你确认”卡；提问栏显示已带上下文“今日数据 · 恢复”"],
            ["对比图", "`mockups/d-compare-dark.png`", "`mockups/d-compare-light.png`", "5 屏并排"],
          ]}
        />

        <Text>1. Token 规格（D）。颜色均已算过对比度（WCAG 2.x）：正文 ink 在两种模式下约 19:1；次级文字 ink2 在画布上 6.5:1（浅）/ 7.5:1（深）；三级文字 ink3 在画布和卡片上至少 4.7:1，只有深色输入栏内的占位符是 4.4:1。</Text>
        <Table
          columns={["D token", "浅色", "深色", "映射到现有符号（文件:行）", "做法"]}
          rows={[
            ["canvas 画布", "#FFFFFF", "#000000", "`rhythmCanvas` VT:52、`backgroundUIColor`/`bg` VT:35-36、`surface` VT:40（现 #F5F5F7 / #111113）", "改值"],
            ["surface 卡片", "#F7F7F8", "#111112", "`rhythmCanvasRaised` VT:53、`cardBg` VT:41、`glassCardBgAdaptive` VT:66", "改值；后者删除"],
            ["surface2 输入栏 / 圆按钮 / 用户气泡", "#F2F2F3", "#1B1B1C", "`surfaceFloating` VT:47、`elevatedBg` VT:42", "改值"],
            ["ink 正文", "#111111", "#F2F2F2", "`rhythmInk` VT:54（#111111 / #F5F5F5）", "深色微调"],
            ["ink2 次级", "#5E5E63", "#9A9A9E", "`rhythmInkSecondary` VT:55；`fg2`/`muted` VT:78-79 仍用系统 secondaryLabel", "改值；新增偏离文字 `deviationInk` = ink2"],
            ["ink3 三级 / 元信息", "#6E6E73", "#808086", "`meta` VT:82（现为偏绿 #6B726D / #A6B0AA）", "改值"],
            ["hairline 描边", "#E5E5E8", "#262628", "`hairline` VT:160（#E5E5EA / #3A4048）、`rhythmMist` VT:56", "改值"],
            ["band 常见范围带", "#E3E3E6", "#2C2C2E", "无", "新增 `rangeBand`"],
            ["track 环 / 进度轨道", "#EFEFF1", "#1E1E20", "无", "新增 `scoreTrack`"],
            ["segmentOn 分段选中底", "#ECECEE", "#2A2A2C", "无", "新增"],
            ["primary 主操作（胶囊）", "#111111 底 / #FFFFFF 字", "#FFFFFF 底 / #000000 字", "`rhythmDeep` VT:58-59、`rhythmDeepOn` VT:61-62、`accent` VT:87-91、`brand*` VT:96-102（现在都是行动蓝 #175CD3）", "改为墨色；rhythmDeep 有 313 处引用，改值即可全局生效，不必逐处替换"],
            ["五个指标色", "D 的屏幕上不用", "同左", "`recoveryColor`…`energyColor` VT:176-184（各 40–51 处引用）、`Gradients` VT:614-618、`glass*Glow` VT:66-72", "待你决定（见下方“需要你决定”）；建议 D 屏幕全部单色，指标色只留给 Watch 和小组件"],
            ["状态色", "只用于错误与安全", "同左", "`stateGood/Moderate/Poor` VT:107-131；`ConfidenceBadge` DS:514-553 用绿 / 橙 / 红标 HIGH/MED/LOW", "ConfidenceBadge 改为中文中性文字“置信度 高/中/低”"],
          ]}
        />
        <Table
          columns={["字阶（mockup px = pt）", "Dynamic Type 文本样式", "用在", "现有符号"]}
          rows={[
            ["Agent 消息正文 17 / 行高 1.7", "`.body`，`.lineSpacing(6)`；强调用 `.body.weight(.semibold)`", "今日、趋势、对话的消息", "`body()` VT:318；新增 `briefBody()`"],
            ["五分数字 23 medium", "`.title2.weight(.medium)` + `.monospacedDigit()`，design 用 `.default`", "五分条", "替代固定 30pt 的 `cardValue()` VT:375（2 处引用）"],
            ["详情环内数字 34", "`.largeTitle.weight(.medium)`", "仅恢复等 5 个详情页头部", "替代 `heroScore` 64 / `displayValue` 60 / `metricHeroValue` 48（VT:372-385，这三个已 0 处引用，可直接删）"],
            ["详情结论 / 计划标题 22–26 semibold", "`.title2` / `.title` semibold", "“今天适合轻量”“今天 3 项”", "`title2()` VT:315、`title1()` VT:314"],
            ["分段控件、行标题 14–15.5", "`.subheadline` / `.callout`", "顶部 今日/趋势/计划、列表行", "`subheadline()` VT:320、`callout()` VT:319"],
            ["输入栏占位 16", "`.callout`", "提问栏", "—"],
            ["标签 / 元信息 12–12.5", "`.caption` / `.footnote`", "分数名称、“BodySeek · 早上 7:40”", "`caption1()` VT:322、`footnote()` VT:321"],
            ["偏离 / 图例 10.5–11.5", "`.caption2`", "“低于平时”", "`caption2()` VT:323"],
            ["去掉 rounded", "—", "全部数字", "`design: .rounded` 现在 29 个文件 128 处，随组件重写逐步移除；`vitalValue()` VT:391 一并删"],
          ]}
        />
        <Properties items={[
          { label: "间距", value: "保留 4pt 网格（VT:334-341）。`pagePadding` 20 不变（VT:347）；`cardPadding` 18→16（VT:346）；`compactCardPadding` 14 不变；消息与五分条之间 20，追问按钮间距 8（= `inlineGap` VT:342）。" },
          { label: "底部留白", value: "`bottomContentClearance` 104→132（VT:350），给提问栏（约 86pt 高 + 底部 30）和上方渐隐让位；`tabBarHeight` 84（VT:351）和 `VelaFloatingNavigationMetrics`（Shell:11-16）随底部 Dock 删除。" },
          { label: "圆角", value: "9 个合并为 5 个：`radiusSm` 8（范围带）、`radiusCard` 18（卡片，替代 VT:357-363 的 20/24 共 7 个）、`radiusInput` 26（提问栏，新增）、`radiusPill` 980（VT:365）、`radiusSheet` 32（VT:364）。" },
          { label: "描边代替阴影", value: "卡片 = surface 填充 + 1pt hairline；审批卡 = 1.2pt ink 描边；增强对比度模式下 hairline 改成 ink。删除 `cardShadow` / `nativeShadow`（VT:397-403）和 Dock 阴影（Shell:588）；全仓 `.shadow(` 有 17 个文件 31 处、`.ultraThinMaterial` 有 12 个文件，逐步改成实色。" },
          { label: "一处改动的最大收益", value: "`VelaNativeCardModifier`（DS:709-737）现在是上下渐变描边，改成实色 1pt hairline 后，所有 `.velaNativeCard(...)`（14 个文件 40 处）会一起变成 D 的卡片样式。" },
          { label: "动效", value: "保留 VT:407-452 的 spring 和 `interfaceAnimation(reduceMotion:)`；Agent 消息逐句淡入，开启 Reduce Motion 时直接显示。" },
        ]} />

        <Text>2. 导航改动（iOS 17 是最低支持版本，见 VELA_DESIGN_LANGUAGE.md:91，所以顶部分段要自己实现，不能依赖 iOS 26 的玻璃组件）：</Text>
        <Table
          columns={["位置", "现在", "改成"]}
          rows={[
            ["`VelaShell.VelaTab`（Shell:93-98）", "today / trends / plan / coach 四个 case", "删除 `.coach`；`BodySeekDestination.coach`（Shell:27-33）保留，语义改为“打开对话”，用于深链和通知"],
            ["`legacyFloatingNavigation`（Shell:461-540）", "四个 Tab 表面（Coach 嵌入在 Shell:501-515）+ 底部 `safeAreaInset` 放 Dock（Shell:519-525）", "三个表面；顶部放新 `BodySeekSegmentedHeader`（☰ / 今日·趋势·计划 / 头像）；底部 `safeAreaInset` 改放 `AskBar`"],
            ["`bodySeekDock` / `dockBackground` / `customTabButton`（Shell:543-567、:570-590、:613-651）", "悬浮玻璃 Dock，中间蓝色 +，带阴影", "删除；+ 的记录功能（`BodySeekQuickAction` Shell:35-41）移到 AskBar 左侧 + 按钮"],
            ["`nativeTabNavigation`（Shell:377-459）", "iOS 26 系统 TabView，仅作参考，未启用（Shell:369-373）", "删除"],
            ["对话入口", "已有 `.fullScreenCover(isPresented: $showCoach)` 打开 `VelaCoachView(presentation: .quickCover)`（Shell:224-234）", "直接复用：点 AskBar 或追问按钮即打开，并按当前屏幕传 `CoachScreenContext`（CoachChatVM.swift:20-24），surface 用现有的 `.home / .trends / .plan / .metricDetail`（CoachChatVM.swift:7-16）"],
            ["`CoachPresentationStyle.embedded`（CoachView.swift:15-18）", "Coach Tab 使用", "Tab 删除后不再需要，保留 `.quickCover`"],
            ["左上 ☰", "无", "打开侧边面板：对话历史、记忆收件箱、数据覆盖、设置（对应 Grok 的左侧栏）"],
            ["键盘弹出", "`VelaNavigationVisibility.shouldShowBottomBar`（Shell:5-9）隐藏 Dock", "AskBar 随键盘上移，不再隐藏"],
          ]}
        />

        <Text>3. 组件增删</Text>
        <Table
          columns={["动作", "组件", "说明 / 依据"]}
          rows={[
            [{ text: "新建", tone: "success" }, "`BodySeekSegmentedHeader`", "可以改造目前 0 处引用的 `BodySeekTopBar`（DS:268-312）"],
            [{ text: "新建", tone: "success" }, "`AskBar`", "提问栏：占位、+、上下文胶囊（“带上今日数据”等）、说话 / 发送胶囊；每屏共用一个实例；“说话”复用 `CoachDictationController`（CoachView.swift:535）"],
            [{ text: "新建", tone: "success" }, "`AgentBriefMessage`", "BodySeek 署名 + 时间 + 正文；文案来自 `HealthTrendEngine` 的 headline 和 `evaluateAction`，与 `MorningBriefScheduler`（VelaApp/AI/Proactive/）共用同一段文字"],
            [{ text: "新建", tone: "success" }, "`FiveScoreStrip`", "五等分、竖线分隔、偏离空心圆；替代 `TodaySignalGrid` 的 3+2 布局（TodaySignalGrid.swift:57-58、:128-163）以及 `TodayStressGauge` / `TodayEnergyGauge`（:520、:564）"],
            [{ text: "新建", tone: "success" }, "`FollowUpChips`", "最多 3 个；点按后带上下文打开对话"],
            ["改造", "`SparklineLineGraph` / `DateAwareSparkline`（VelaChart.swift:456、:522）", "加 `band: ClosedRange<Double>?` 参数和“今天”空心圆端点，用于趋势行、详情 30 天图和对话证据卡"],
            ["改造", "`VelaMetricScoreRing`（VelaChart.swift:5）", "只在详情页使用：单色、无超出弧（删除 :100-109 的 danger 色）、数字取消 `lineLimit(1)` / `minimumScaleFactor(0.7)`（:112-117），大字号时数字移到环下方"],
            ["改造", "`PlanProposalDiffCard`（TodayTrainingPlanAdaptationCard.swift:7）、`CoachArtifactCard`（DS:315）", "统一为 `ApprovalCard`：墨色描边、两个等宽按钮；状态沿用 `CoachArtifactStatus` 的 acted / dismissed（AgentActionParser.swift:51-56），类型用 `.trainingAdjustment`（:28）"],
            ["改造", "`ConfidenceBadge`（DS:514-553）", "改成一行中性文字，和“数据覆盖 / 缺：…”放在一起"],
            ["改造", "CoachView.swift（1700 行）的消息渲染", "AI 回复去掉气泡改为正文；用户消息是 surface2 细描边气泡"],
            [{ text: "退役", tone: "warning" }, "`BevelScoreRing`、`DottedCircleGauge`、`SegmentedBatteryBar`（VelaChart.swift:352、:374、:423）", "引用数（含定义）分别 3 / 1 / 4"],
            [{ text: "退役", tone: "warning" }, "`AppleIntelligenceGlowModifier`（DS:779-807，含定义 7 处）、`ambientGlow`（DS:811）、`heroCardSurface`（DS:826，含定义 3 处）、`VelaGlassSurfaceModifier`（DS:739）、`velaInteractiveGlass`（VelaNavigation.swift:5-33）", "光晕、玻璃、渐变描边都不符合 D"],
            [{ text: "退役", tone: "warning" }, "`MetricLandscapeHeader` + VelaMetricDetailLandscapes.swift + `Landscape` 调色板（VT:272-304）", "装饰插画"],
            [{ text: "退役", tone: "warning" }, "Coach Tab 的空会话首屏 `CoachWelcomeWorkspace`", "五分和追问已经在 Today 上；对话打开时直接聚焦输入"],
          ]}
        />

        <Text>4. 文档修改</Text>
        <Table
          columns={["文件:行", "现在", "改成"]}
          rows={[
            ["PRD.md:76-87", "“四大工作区”，四 Tab 树（Tab 4: Coach）", "三个工作区（今日 / 趋势 / 计划）用顶部分段切换；Coach 是“对话层”，每屏底部有提问栏"],
            ["PRD.md:92", "固定 3+2 状态仪表，三个主圆环", "五项等宽分数条；Today 不用圆环；偏离只用中性标记"],
            ["PRD.md:93", "主卡内 Agent 指导，一句话", "Agent 消息：先说现在，再说要不要行动；变化放进“最近变化”卡"],
            ["PRD.md:120-127 §5.4", "Tab 4 · Coach", "对话层：入口（提问栏、追问按钮、通知）、上下文胶囊、审批卡"],
            ["VELA_DESIGN_LANGUAGE.md:24-35 §2", "暖灰绿画布 #F2F5F1、节律绿 #17A35C（代码已是 #F5F5F7 / #175CD3，文档本来就过时）", "D 的单色 token 表（上表）"],
            ["VELA_DESIGN_LANGUAGE.md:40", "Today ── Trends ── Plan ── Coach", "今日 ── 趋势 ── 计划，加上贯穿全局的对话层"],
            ["VELA_DESIGN_LANGUAGE.md:46-49 §3.1", "三个主圆环；“通过固定的 3+2 尺寸层级表达重要性”", "五项平等、位置固定；稳定的是顺序，不是大小"],
            ["VELA_DESIGN_LANGUAGE.md:61-66 §3.4", "Tab 3 · Coach 工作台", "对话层规范：AI 回复不加气泡、证据卡、审批卡"],
            ["VELA_DESIGN_LANGUAGE.md:75", "首次使用预演 3+2 仪表", "预演五分条和提问栏"],
            ["VELA_DESIGN_LANGUAGE.md:82-91 §4 质量门禁", "—", "增加：新 token 对比度表；圆环只出现在详情页"],
          ]}
        />

        <Text>5. 分阶段 PR（S ≈ 半天，M ≈ 1–3 天，L ≈ 3–5 天）</Text>
        <Table
          columns={["PR", "内容", "工作量", "风险", "验收"]}
          rows={[
            ["PR1 先做", "缺失标签去重 bug（见下方 Bug 一节）；新增 `deviationInk`，替换 5 处偏离点的 `stressColor`（TodaySignalGrid.swift:85、:407、:435；VelaTrendsView.swift:254、:295）；`ConfidenceBadge` 改中性中文", "S", "低：不改布局和导航", "单测；Today 和 Trends 不再有玫红点"],
            ["PR2", "D 颜色 token 改值（上表）+ `VelaNativeCardModifier` 改实色描边 + 删除阴影 token；圆角合并", "M（1–2 天）", "中：全局视觉变化，没有逻辑改动", "浅色 / 深色 / 增强对比度三套截图"],
            ["PR3", "新组件 `FiveScoreStrip`、`AgentBriefMessage`、`FollowUpChips`、带范围带的 sparkline；Today 改成 D 布局（放在功能开关后面）", "M（2–3 天）", "中", "五种状态 + 最大字号截图，无“…”"],
            ["PR4", "导航：删 `.coach` Tab 和 Dock，加 `BodySeekSegmentedHeader` + `AskBar`，复用 quickCover 对话；☰ 侧边面板", "M（2–3 天）", "高：信息架构变化，涉及深链和通知路由", "所有 `BodySeekDestination` 路由测试；UI 测试改选择器"],
            ["PR5", "对话视图重绘（正文式回答、证据卡、`ApprovalCard`）", "M–L", "中", "审批流程端到端：采纳 / 拒绝后状态写回"],
            ["PR6", "趋势页 + 5 个详情页（先做恢复）", "L（3–5 天）", "中", "每页深浅色对照截图"],
            ["PR7", "计划页；退役组件清理；PRD 和设计语言文档更新", "S–M", "低", "删除的组件 0 处引用；文档与代码一致"],
          ]}
        />

        <Callout lead="需要你决定" tone="warning">
          1）顶部分段代替底部 Tab 栏，偏离 iOS 惯例（Grok 是这么做的），请确认接受。2）深色模式用纯黑 #000000，还是保留略亮的 #111113？纯黑在 OLED 上更像 Grok，但会和系统 sheet 的颜色有差别。3）五个指标色要不要保留？建议 D 屏幕全部单色，指标色只用在 Watch 和小组件。4）对话历史、记忆收件箱放进 ☰ 侧边面板，可以吗？5）“说话”胶囊可以直接复用 Coach 现有的听写（`CoachDictationController`，CoachView.swift:535，基于 SFSpeechRecognizer），但这意味着每个屏幕都能触发麦克风权限请求，是否接受？
        </Callout>
      </Section>

      <Section heading="结论">
        <Callout lead="推荐 C 方案：三问结构 + 常见范围条">
          Today 按“现在 / 最近变化 / 要不要行动”三段排列，正好对应 PRD 的三个问题。五项分数改成等宽、等字号的行，每行一条“常见范围条”：灰带是你的个人常见范围，圆点是今天。偏离只用中性灰空心圆加“低于平时”表示，不再用玫红点。开头一句话取 A 方案的写法。B 方案可以作为以后的“晨间简报”卡片。
        </Callout>
        <Steps steps={[
          { title: "先修 bug 和偏离点颜色（S）", detail: "去重缺失标签；所有偏离点从 `VelaTheme.stressColor` 改成新 token `deviationInk`。" },
          { title: "换 token（M）", detail: "五个指标色降饱和，压力不再用玫红；字号改用语义字阶，圆角从 9 个合并成 3 个，去掉阴影、光晕和渐变。" },
          { title: "Today 改成 C 结构（M）", detail: "新增 `RangeStripRow` 组件，替换 `TodaySignalGrid` 的 3+2 布局；同步修改 PRD:92、:175 和设计语言 §3.1。" },
          { title: "Trends 与 5 个详情页跟进（M–L）", detail: "去掉风景插画头图，详情页头部只保留一个圆环；两个“基线”数字统一成一个来源。" },
          { title: "Plan、Coach 收尾（S）", detail: "沿用 09-22 原型的方向，只换 token 和间距。" },
        ]} />
      </Section>

      <Section heading="三个 mockup 对比" caption="尺寸 393×852 @2x，HTML 用 Chrome headless 渲染；数值是验证截图里的示例数据，常见范围是示意值。">
        <Table
          columns={["方案", "结构", "优点", "风险"]}
          rows={[
            ["A", "一句话结论 + 五行等宽列表（Apple 健康摘要风格）", "最安静；行高随 Dynamic Type 自然增长，不会出现“…”", "Q2“最近变化”没有专门的位置"],
            ["B", "身体状态主卡（文字，不打分）+ 五个等大小环", "一眼看懂；最像 Oura", "主卡容易被读成“第六个分数”（CONTEXT.md:68 禁止）；五个小环在大字号下仍会被截断"],
            [{ text: "C（推荐）", tone: "success" }, "三问结构 + 常见范围条 + 最近变化 + 一项行动", "偏离、常见范围和今天的值在同一条线上；统计上诚实；完整回答三个问题", "范围条是新组件，需要讲清图例"],
          ]}
        />
        <Text>文件位置：`/workspace/bodyseek/mockups/today-A.png`、`today-B.png`、`today-C.png`，对比图 `today-compare.png`（现状 + A/B/C 并排），HTML 源在 `mockups/src/`。下面是 C 方案“现在”区的范围条示意，用示例数据画成：</Text>
        <RangeStripDemo />
      </Section>

```
