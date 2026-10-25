# Visual Body wave25 — 今日 hero + 趋势信息层级（构图）

- 分支：`cursor/visual-body-wave25-20261024`
- 基线：从 wave24 tip **`b9cb374c`**（draft PR #26 分支 tip）开出；**stacks on #24 + #25 + #26**。PR base = `main`，GitHub diff 因此含 #24/#25/#26 + 本波增量；review 本波请以相对 `b9cb374c` 的 delta 为准。
- 日期：2026-10-24
- 性质：**visual-only / composition-only**。无评分公式、schema、HealthKit、Store、导航 IA、对话历史列表行为、顶栏分段语义、AskBar mic/「问问你的身体」/context chip 产品行为改动。
- 本波目标：不是再扫 token，而是修 **构图与信息层级** — Today 一屏有「一个主数字 + 一句判断」，Trends 图/分先于说明、五条 metric 行异构，Plan 与 Today 共享字阶/间距/hairline。

## 环境

| 项 | 值 |
| --- | --- |
| Xcode | 27.1 (27A9275)（仓库 `.xcode-version` pin 26.5.0，与 #20–#26 同一已知不一致，本波未改 CI） |
| 模拟器 | `iPhone 17 Pro`（iOS 26.5，1206×2622 @3x） |
| 构建 | Debug，`CODE_SIGNING_ALLOWED=NO`，`-derivedDataPath build/Wave25DerivedData` |
| 数据 | `-velaPreviewDashboard` 合成样例（非临床证据）；空状态截图额外用无 preview 启动 |
| 语言 | `-vela_app_language simplifiedChinese`，AX 用 `UICTContentSizeCategoryAccessibilityXXXL` |

## 量级 / Diff metrics（相对 wave24 tip `b9cb374c`）

| 指标 | before | after |
| --- | --- | --- |
| 本波代码文件 | — | 6 个 `VelaApp` 文件 + 1 个 UI 测试文件（+ 本证据目录） |
| Today fold 结构 | byline + 3 行灰文案 + 五等宽仪表盘 + 大 recent-change 卡 + 3 chips + 灰底下一件 | byline + 1 行判断 + 1 段次级 caption + **hero 主分卡** + 4 项 support strip + 单行 recent-change + 2 chips + 单行行动条 |
| Today 主分数值字号 | `instrumentValue()` = title2/22pt，五项相同 | **`heroValue()` = largeTitle/34pt + 基线 gauge**；四项 `supportValue()` = callout/16pt |
| Today 顶部 5 分卡 | 5 × 等宽（一张卡） | 1 hero card + 4 项 strip（1 行；AX 时 2×2） |
| Today 灰 caption 行数（fold 内） | agent 句 2 行 + comparison 2 行 ≈ 4 行 | 判断 1–2 行（headline）+ 次级 caption ≤2 行 |
| Today follow-up chips | 3 颗（wrap） | **2 颗**（第三颗仍由 `BodySeekAskSuggestions` 生成，仅不呈现） |
| Trends 小结占高（空状态） | `30天小结` + statement/22pt headline（2 行）+ subheadline detail（2 行）+ 灰胶囊 chip ≈ 170pt | eyebrow + title3 headline（≤2 行）+ caption1 detail（1 行）+ 纯文字 coverage 行 ≈ 110pt |
| Trends metric 行 | 5 × 同构 minHeight 72pt | **focus 104pt（44pt sparkline + heroValue 数字）+ 4 × 60pt（24pt sparkline + callout 数字）** |
| Trends 图例 | 3 行灰 caption | 1 行 caption2（完整语义保留在 AX label） |
| 固定字号 `check_fixed_fonts.py` | 179 / 阈值 216 | **179**（未新增文本固定字号） |
| `audit_design_tokens.sh` 合计 | 585 | **586**（+6 token 半径 hairline overlay 被脚本归入 `RoundedRectangle` 分类，−5 处被替换的内联 chrome；无新增 `Color(hex:)` / `.font(.system(size:))` / 系统语义色） |
| `check_contrast.py` | OK | OK（`textColor(for:)` / `deviationInk` ≥ 4.5:1） |
| schema fingerprint | 32 live / 32 frozen V3 | 32 / 32（未变） |
| 评分 / 数据路径 | — | 未触碰（仅视图层展示投影） |

## MUST #1 — Today 主屏构图（`TodaySignalGrid` / `TodayScoreInstrument` / `BodySeekInstrument`）

**主分是谁（hero selection）** — `TodaySignalGrid.primaryReadingID(readings:statement:)`，纯展示投影，不重算分数：

1. 优先 **Agent statement 已点名的指标**（`sentence.contains(reading.title)`，且该读数有值）。截图中 statement「现在恢复 69，今天不必改计划。」→ hero = 恢复 69。
2. 否则取 **有值且 `isUnusual`** 的第一项（notable）。
3. 否则取第一个有值的读数；全部缺失时回落第一项（保留 `--` 空态，不伪造数字）。

`TodayScoreInstrument` 改造为 **1 hero card + 4 support strip**：

- hero：`恢复` + 「低于/高于平时」hollow marker + 右上「基线 60」/caption；主数字 `VelaTheme.heroValue()`（largeTitle 34pt semibold，monospacedDigit）；下方复用既有 `BaselineGauge` 画「今天 vs 个人基线」位置差；整卡可点 → 对应 metric detail。
- support strip：其余四项单行（`callout` 16pt 数字 + caption2 标题 + 偏离 hollow dot），hairline 分隔、无卡底；AX 尺寸自动切 2×2 `LazyVGrid`。
- 所有既有 identifier 保留：`today-score-instrument`、`today-score-recovery/sleep/strain`、`today-secondary-stress/energy`，点击仍进 `VelaMetricDetailView`。

**Statement 压缩** — 新增 `TodaySignalGrid.statementParts(_:)`，**只做呈现切分，不改 `TodayAgentBriefCopy` 生成逻辑**：

- lead = 首 clause + 决策 clause（含「建议 / 不必 / 需要调整 / 优先恢复」），`headline()` 17pt semibold、最多 2 行；
- 其余基线/中位数 clause + 既有 `comparisonLine` 合成 **一段 caption1 次级说明**（≤2 行）；
- byline「BodySeek · 时间」与示例数据/未同步标记保留。

**其他降权**：

- recent-change 从 32pt icon + 双层灰卡 → **单行 caption/footnote 导航行**（44pt hit），仍跳 Trends。
- follow-up chips 只呈现 **2 颗**（`Array(suggestions.prefix(2))`，wrap 布局），不抢 hero。
- `TodayPlanSection` 从灰底卡 → **顶部 hairline + 单行行动条**：`下一件` caption2 + 行动标题 callout semibold + `依据` capsule；identifier `today-advice-panel` / `today-plan-title` / `today-next-action` / `today-open-plan` / `today-advice-evidence` 全保留。

## MUST #2 — Trends 信息层级（`VelaTrendsView`）

- **空状态 / 小结压缩**：`periodSummary` 改为紧凑 banner — eyebrow「30天小结」+ judgment line（数据不足时 `title3`，有数据时仍 `statement()`，≤2 行）+ 一行 `caption1` detail（截断，完整上下文在 coverage sheet）+ **纯文字 calendar coverage 行**（44pt hit，去掉灰胶囊）。`TrendsPeriodSummary.make` 与所有文案生成逻辑未改；`trends-period-summary` / `trends-history-coverage` 保留。
- **Metric 行异构**：`focusMetric` = notable → 第一个 available → 第一个 descriptor；focus 行置顶、104pt、44pt sparkline、`heroValue()` 数字；其余四行 60pt、24pt sparkline、`callout` semibold 数字、单行短 caption（完整 caption 仍进 VoiceOver label）。`trends-score-*` / `trends-overview-chart-*`、tap → detail sheet 全保留。
- **图例**：3 行灰 caption → 1 行 caption2；完整含义保留在 accessibility label。
- 窗口分段（7天/30天/6个月/3年）选项与语义未改；error card / metric catalog / recovery chart 未改。

## MUST #3 — Plan 页轻对齐（有限 diff）

参考截图实际是 **Plan → 训练** 进入的 `TrainingHeroSection` 落地页（`VelaTrainingView`），因此两处都做视觉对齐、不改 IA：

- `VelaPlanView`（Plan tab）：decision line → caption1 semibold secondary eyebrow；主陈述保留 `statement()`；灰注释 → caption1；卡间距 → `cardGap`/`sectionGap`；proposal 卡 `deviationWash` → `rhythmCanvasRaised` + hairline（`plan-proposal-card` 等 identifier 全保留）；训练入口图标/重点 badge 的 opacity wash → 实底 `rhythmMist` + hairline。
- `VelaTrainingRotationView`：页面间距 30/14 → `sectionGap`/`cardGap`；hero 标题 → `statement()`；`todayDecisionSection` 灰 wash → raised + hairline；展开面板同样去 wash。
- `TrainingHeroSection`（顶部 hero 区）：**保留 largeTitle 落地页大标题**（与 Today hero 数字同一 display 步进），`下一站` → caption1 eyebrow，boundary chips / 规划卡 / 洞察卡 / 证据面板去掉 opacity 灰叠层 → 实底 raised + hairline，卡间距 → `cardGap`。Watch sync 文案/语义、heatmap/landscape/analysis portal 内部未改。

## MUST #4 — 三屏共用节奏（visual-only）

- 主列边距统一 `VelaTheme.pagePadding` (20)；页内 section 间距 `sectionGap` (24)；卡间距 `cardGap` (12)；卡面 `rhythmCanvasRaised` + **1pt `hairline`**；只用既有 token，**未新增 palette**。
- 新增两个**排版** token（语义字号步进，非颜色）：`VelaTheme.heroValue()`（surface hero 数字）与 `VelaTheme.supportValue()`（次级 strip 数字）；Today hero / Trends focus 行共用 `heroValue()`。
- AskBar 产品行为未改（mic / 文案 / context chip / 顶栏分段语义全部保留）。

## SHOULD #5 — 快照测试

`VelaUITests/VelaSmokeUITests/testVisualBodyWave25Snapshots()`（dark + AccessibilityXXXL，preview 合成数据）：

| 状态 | attachment |
| --- | --- |
| Today hero dark | `wave25-today-hero-dark` |
| Today hero AccessibilityXXXL | `wave25-today-hero-accessibility` |
| Trends 层级 dark | `wave25-trends-hierarchy-dark` / `-scrolled` |
| Trends 层级 AccessibilityXXXL | `wave25-trends-hierarchy-accessibility` |
| Plan tab dark | `wave25-plan-dark` |

> 参考截图中的 Plan→训练 landing 页需从 Plan 底部「训练」portal 进入（portal 位于浮动 AskBar 下方），快照测试只覆盖 Plan tab；训练 landing 的字阶/间距/hairline 对齐见 MUST #3 的 diff 说明。

### 测试 / 审计结果

| 项 | 结果 | 证据 |
| --- | --- | --- |
| `testVisualBodyWave25Snapshots`（dark + AX） | **Passed** 1/1 | `ui-wave25.txt` |
| `VelaTests` 全量 | **Passed** 679 / 0 failed | `unit-tests.txt` |
| `xcodebuild build`（simulator, final code） | **BUILD SUCCEEDED** | `build-success.txt` |
| `check_fixed_fonts.py --strict` | 179 ≤ 216（未新增） | `fixed-font-before/after.txt` |
| `audit_design_tokens.sh` | 585 → 586（+6 token 半径 overlay 分类，−5 内联 chrome；无新增颜色/字号） | `design-token-before/after.txt` |
| `check_contrast.py` | OK | `contrast-before/after.txt` |
| `schema_fingerprint.py --check` | 32 live / 32 frozen V3 | `schema-fingerprint-before/after.txt` |

## 截图 / Before → After

- before（用户真机）：`before-today.png`、`before-trends.png`、`before-plan.png`（本目录）
- after（simulator，iPhone 17 Pro / iOS 26.5）：见本目录 `wave25-*.png`

## 明确 SKIP / 未做

- 未再扫全仓数字圆角 / `VelaMetricPill` tint（#26 已做）。
- Watch / WidgetKit / `VelaMetricDetailWidgets` 未动。
- 评分公式 / schema / HealthKit / Store / Dock / Speak / 顶栏分段语义 / AskBar 产品行为未动。
- 未合并、未 ready、未 request review；未 force-push 任何既有 wave 分支。
- `VelaRhythmSectionHeader`（`TodayHeroCard.swift`，共享 DS，不在本波范围）仍是 title2；若后续统一 section title 字阶，可再对齐。
- 训练落地页大标题保持 largeTitle，未按「plan 轻对齐」压到 statement（保留原页 hero 层级）。
