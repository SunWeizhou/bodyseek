# Visual Body wave23 — Design D 收尾（Trends / Journal / BodyModel / DS chrome）

- 分支：`cursor/visual-body-wave23-20261024`
- 基线：**stacks on #24 / wave22 tip `259e991b`**（PR base = `main`；#24 merge 后本分支可 rebase 或一并 squash）
- 日期：2026-10-24
- 性质：**visual-only**。无评分公式、schema、HealthKit、Store、导航 IA、对话历史列表行为改动。
- 范围：MUST #1–#7（Trends / JournalCorrelation / BodyModel / WorkoutDetail / Settings 壳 / 共享 DS 第二刀 / legacy material）+ 能盖到的 SHOULD #8–#11。

## 环境

| 项 | 值 |
| --- | --- |
| Xcode | 27.1 (27A9275)（仓库 pin 26.5.0，与 #20/#23/#24 同一已知不一致，未改 CI） |
| 模拟器 | `BodySeek Wave21 Disposable`（iPhone SE 3rd gen 375pt / iOS 26.5 23F77，wave22 沿用的已 boot SE） |
| 构建 | Debug，`CODE_SIGNING_ALLOWED=NO`，`-derivedDataPath build/DerivedData` |
| 语言 | `-testLanguage zh -testRegion CN` |
| 数据 | `-velaPreviewDashboard` 合成样例（非临床证据）；hosted 快照为 isolated in-memory container |

## 关键改动（按 MUST）

| MUST | 表面 / 文件 | 改动 |
| --- | --- | --- |
| #1 | `Features/Trends/VelaTrendsView.swift` | 数字圆角 **11→1**：满宽卡/面板 16/18→`radiusCard`、44pt 图标 tile 12→`radiusSm`；仅剩 2pt 图例 band swatch（data mark）。chrome 描边 5 处 `lineWidth: 1`→`VelaTheme.hairlineWidth`；窗口选择器、五分序列、图表 data mark 与 IA 未动 |
| #2 | `Features/Minimal/JournalCorrelationSection.swift` | 数字圆角 **18→0**：空态卡/Impact Matrix 外层卡/实验卡/证据卡 16–20→`radiusCard`，claim 卡/protocol 块/detailStat 12–14→`radiusSm`，完成动作按钮 13→`Capsule()`；Impact Matrix 散点/标注/confidence 语义色保留。固定字号 2 处均 SF Symbol 图标 → 书面 SKIP |
| #3 | `Features/Minimal/BodyModelViews.swift` | 数字圆角 **7→0**：header/静态偏好/生理稳态卡 22→`radiusCard`，36pt 图标 tile 12→`radiusSm`（`rhythmMist` 实色 mono）；模型 builder/存储/读取逻辑未动。固定字号 1 处为 SF Symbol 图标 → SKIP |
| #4 | `Features/Training/WorkoutDetailView.swift` | 数字圆角 **5→0**：fact box 14→`radiusSm`，地图 skeleton/clip、GPS 卡 16→`radiusCard`；4 处 `.velaNativeCard(radius: 20/18)` + 1 处 `VelaGlassCard(cornerRadius: 20)`→token。AreaMark/LineMark/RuleMark/BarMark、MapPolyline、GPS 起终点、心率区间语义色、AxisGridLine 0.5/0.6 保留 |
| #5 | `Features/Minimal/VelaSettingsView.swift` | 数字圆角 **4→0**：section 卡 22→`radiusCard`，图标 tile 10、指引 row 14→`radiusSm`；壳/列表布局、AX 分支与列表行为不变。#20 二级页与 #23 联网 Agent 修复未动 |
| #6 | `Core/DesignSystem/VelaCard.swift`、`VelaDesignSystem.swift` + 调用点 | `VelaStatusBadgeCompat` tint wash + 0.5pt tint 描边 → `rhythmMist` 实底 + `hairline` 1pt（`foregroundStyle(tint)` 保留状态语义）；`VelaHeroSurface` 删除 tint wash → `cardBg` + `hairline`，删除 `tint` 参数并同步 5 个调用点；`.velaNativeCard(radius: <literal>)` **16→0**；DS 内数字圆角 5→0；仅剩唯一 `design: .rounded` 为 `Image(systemName:)` 图标字 → 书面 SKIP |
| #7 | `Compatibility/Today/TodayLegacyCompatibility.swift` | `LivedStateCheckInSheet` 底部 `.ultraThinMaterial` → `cardBg` + 顶部 1pt hairline。该 sheet 有 `-velaOpenLivedStateCheckIn` 真实入口，会露到 D 表面，故不 SKIP |

SHOULD：
- #8 抽检：本波触及文件数字圆角 **50→1**（仅 Trends 2pt 图例 data mark；`VelaCard` 的 10pt DS 内部图标 tile 未动，书面 SKIP）；固定字号文本站点 **0**（24 处全部为 SF Symbol/几何/品牌比例字，逐文件 SKIP）。
- #9 AccessibilityXXXL 抽检：Trends 首屏、Settings 壳、WorkoutDetail、Journal correlation，见「AX 观察」与截图。
- #10 四项 audit + contrast + schema 全跑，见命令表。
- #11 新增 `testVisualBodyWave23Snapshots`（UI：Trends/Settings；hosted：JournalCorrelation/BodyModel/WorkoutDetail），12 张 dark/AX 证据。

## 命令与退出码

| # | 命令 | 结果 | exit |
| --- | --- | --- | --- |
| 1 | `xcodebuild build -project Vela.xcodeproj -scheme Vela -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO` | **BUILD SUCCEEDED**，0 warnings（工程已固化 warnings-as-errors） | 0 |
| 2 | `xcodebuild test ... -only-testing:VelaTests` | **TEST SUCCEEDED**：Executed 679 tests，0 failures | 0 |
| 3 | `xcodebuild test ... -only-testing:VelaUITests/VelaSmokeUITests/testVisualBodyWave23Snapshots`（本波新增） | **passed**（31.34s） | 0 |
| 4 | `xcodebuild test ... -only-testing:VelaUITests/VelaSmokeUITests/{testVisualBodyWave22Snapshots,testVisualResidualSnapshots,testVisualNextWaveSheetsAndCoachSnapshots,testUpgradeSurfaceSnapshots}` | **4/4 passed** | 0 |
| 5 | `python3 scripts/check_fixed_fonts.py --strict` | exit 0；179 sites / 阈值 216（与 wave22 baseline 持平） | 0 |
| 6 | `bash scripts/audit_design_tokens.sh` | exit 0；`Color(hex:)` 0、`RoundedRectangle` 412（wave22 413）、合计 **589**（wave22 590）；脚本对 token 化圆角也计数，故看下方数字字面量指标 | 0 |
| 7 | `python3 scripts/check_contrast.py` | 通过 | 0 |
| 8 | `python3 scripts/schema_fingerprint.py --check` | 通过（schema 未变：32 live / 32 frozen V3） | 0 |
| 9 | `git diff --check` | 通过 | 0 |
| 10 | `xcrun swiftc -parse <16 个改动 .swift>` | 全部 exit 0、无输出 | 0 |

原始日志摘要：[`build-success.txt`](build-success.txt)、[`unit-tests.txt`](unit-tests.txt)、[`ui-wave23.txt`](ui-wave23.txt)、[`ui-regression.txt`](ui-regression.txt)、[`hosted-wave23.txt`](hosted-wave23.txt)、[`design-token-after.txt`](design-token-after.txt)、[`fixed-font-after.txt`](fixed-font-after.txt)、[`contrast-after.txt`](contrast-after.txt)、[`schema-fingerprint-after.txt`](schema-fingerprint-after.txt)。

### 圆角 / 字体 / DS 密度 before → after（相对 #24 tip `259e991b`）

| 指标 | before | after |
| --- | --- | --- |
| 本波触及文件数字圆角 `RoundedRectangle(cornerRadius: [0-9])` | 50 | **1**（Trends 2pt 图例 band data mark） |
| 全仓 VelaApp 数字圆角字面量 | 118 | **69** |
| `.velaNativeCard(radius: <literal>)` | 16 | **0** |
| `VelaHeroSurface(tint:)` tint wash 调用点 | 5 | **0** |
| App 内 `.ultraThinMaterial` | 1 | **0** |
| `design: .rounded`（DS / WidgetKit） | 1 / 11 | 1（SF Symbol 图标，书面 SKIP）/ 11（WidgetKit，out of scope 未动） |
| 固定字号（`.font(.system(size:))`）报告站点 | 179 | 179（本波目标文件无文本固定字号，24 处全为图标/几何/品牌比例） |
| `audit_design_tokens.sh` 合计 | 590 | **589** |

## 截图（Dark / SE 375pt / iOS 26.5 / 合成样例）

| 表面 | 证据 |
| --- | --- |
| Trends 首屏（radiusCard 卡 / hairline / 五分序列保留） | [wave23-trends-dark.png](wave23-trends-dark.png) |
| Trends 滚动（三年轨迹/问 Vela 卡 token 化） | [wave23-trends-dark-scrolled.png](wave23-trends-dark-scrolled.png) |
| Trends AccessibilityXXXL | [wave23-trends-accessibility.png](wave23-trends-accessibility.png) |
| Settings 壳（section 卡 radiusCard / 图标 tile radiusSm） | [wave23-settings-dark.png](wave23-settings-dark.png) |
| Settings 壳滚动 | [wave23-settings-dark-scrolled.png](wave23-settings-dark-scrolled.png) |
| Settings AccessibilityXXXL | [wave23-settings-accessibility.png](wave23-settings-accessibility.png) |
| Journal correlation（Impact Matrix + claim 卡，data mark 保留） | [wave23-journal-correlation-dark.png](wave23-journal-correlation-dark.png) |
| Journal correlation AccessibilityXXXL（AX 观察见下） | [wave23-journal-correlation-accessibility.png](wave23-journal-correlation-accessibility.png) |
| BodyModel 详情首屏（22→radiusCard / 图标 tile radiusSm / 基线数据带保留） | [wave23-body-model-dark.png](wave23-body-model-dark.png) |
| BodyModel 详情滚动至行为信号区（correlation 空态卡） | [wave23-body-model-dark-scrolled.png](wave23-body-model-dark-scrolled.png) |
| WorkoutDetail（hero/intelligence/心率卡 token 化；心率卡空态） | [wave23-workout-detail-dark.png](wave23-workout-detail-dark.png) |
| WorkoutDetail AccessibilityXXXL（AX 观察见下） | [wave23-workout-detail-accessibility.png](wave23-workout-detail-accessibility.png) |

## AX 观察（AccessibilityXXXL 抽检）

- **Trends 首屏**：可滚动、卡片文字未裁切；顶栏分段在 AX 下收敛为圆点属 #17–#24 既有顶栏行为，本波未动（顶栏分段为 out of scope）。
- **Settings 壳**：列表/CTA 不溢出，图标 tile 与 section 卡半径随 token 收紧后仍可读。
- **WorkoutDetail**：hero 三列指标网格在 AX5 下数值以省略号显示（**pre-existing**：固定 3 列网格 IA，本波只改半径/token，未改布局；`FitnessActivitySummaryDetailView` 同类）。列为下一波候选。
- **Journal correlation**：Impact Matrix 轴标签/点标注在 AX5 下重叠（**pre-existing** 图表标注布局问题；本波只改圆角/token，未改图表 marks/标注/布局）。列为下一波候选；常态 dark 截图见上。

## 有意保留的数据语义色 / 厚边（Design D 允许）

- Impact Matrix 散点（正/负相关语义色）+ 图例、confidence 语义色、BaselineRangeIndicator 轨道/基线带/1.5pt 中位线/10pt 今日点。
- Trends/详情图表：AreaMark/LineMark/RuleMark/BarMark（含 BarMark 1.5pt 数据 mark 圆角）、sparkline 数据点、图例 band swatch（2pt）。
- WorkoutDetail：心率 Chart 渐变/区间渐变、MapPolyline 4.5pt 路线、GPS 起终点 systemGreen/systemRed、心率区间语义色、AxisGridLine 0.5/0.6 图表轴 chrome。
- 状态/错误/破坏性语义色（如 WorkoutDetail 删除按钮 `systemRed`）；`VelaStatusBadge` 的 `foregroundStyle(tint)` 保留语义色，仅 chrome 收 mono。
- Watch / WidgetKit（含 `VelaMetricDetailWidgets`）全部未动。

## 刻意跳过（SKIP）

- Watch / WidgetKit / `VelaMetricDetailWidgets`（其 11 处 `.rounded`、小 tile 保留）。
- 评分公式 / schema / HealthKit / Store / 导航 IA / Dock / 对话历史列表行为 / Today 五分横条 / Speak pill / chips / 顶栏分段 / AskBar mic 布局。
- `VelaMetricPill` 的 tint wash（不在本波 MUST；tint 承载覆盖/信任状态语义）。
- `VelaCard` 内 `VelaEvidenceRow` 10pt 图标 tile、`VelaEmptyStateCompat` 图标圆 wash、`VelaMakeIconTile` 比例半径（DS 内部小 tile，不在本波清单）。
- `VelaDesignSystem` 唯一 `design: .rounded`（`Image(systemName:)` 图标字）；DS 品牌 wordmark/ring 数字比例字；`heroCardSurface(accent:)` 定义（内部已是 `radiusCard`）；`appleIntelligenceGlow` no-op 默认 radius。
- 未做真机、Reduce Motion、VoiceOver、iOS 17 最低版本、全量 UI 套件（CI 会跑）、Watch/Widget 构建验证。

## 风险 / 未验证

- 视觉变化为 SwiftUI 截图人工核对（dark/AX），未做像素级 diff。
- 半径 16/22→`radiusCard(18)`、14/12/10→`radiusSm(8)`、`VelaStatusBadge`/`VelaHeroSurface` tint wash→mono、LivedState 底栏 material→`cardBg` 属有意视觉变化；布局语义与可点击区域未改。
- `VelaHeroSurface` 删除 `tint` 参数是 DS API 变更：全仓 5 个调用点已同步，`grep 'VelaHeroSurface(tint'` = 0；`coverageColor`/`colorFor` 仍被内容使用。
- 工具链不一致：本机 Xcode 27.1（仓库 pin 26.5.0，与 #20/#23/#24 同样未改 CI）；未声称 pinned 工具链 CI 通过。
- 首次单元测试在另一台 SE 模拟器（`BodySeek Residual SE`）遇到 `SBMainWorkspace` launch denial（模拟器环境问题，与应用无关）；切换到 wave22 所用、已 boot 的 `BodySeek Wave21 Disposable` 后 build / 679 unit tests / UI snapshots 全部通过。
