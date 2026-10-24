# Visual Body wave22 — Design D 深化（排版 / CoachHistory / Sheets / 二级页）

- 分支：`cursor/visual-body-wave22-20261024`
- 基线：`main` @ `b26ca525`（#23 / wave21 tip）
- 日期：2026-10-24
- 性质：**visual-only**。无评分公式、schema、HealthKit、Store、导航 IA、对话历史列表行为改动。
- 范围：MUST #1–#8 的 D 深化（CoachHistoryDrawer chrome、共享 DS 泄漏、VelaLogoMark、Typography density、硬编码圆角→tokens、Sheets/modal chrome、Training/Plan/详情二级、Onboarding 预览 mono）+ 可覆盖的 SHOULD #9–#11。

## 环境

| 项 | 值 |
| --- | --- |
| Xcode | 27.1 (27A9275)（仓库 pin 26.5.0，与 #20/#23 同一已知不一致，未改 CI） |
| 模拟器 | iPhone SE (3rd gen) 375pt / iOS 26.5 (23F77) arm64，`BodySeek Wave21 Disposable` |
| 构建 | Debug，`CODE_SIGNING_ALLOWED=NO`，`-derivedDataPath build/DerivedData` |
| 语言 | `-testLanguage zh -testRegion CN` |
| 数据 | `-velaPreviewDashboard` 合成样例（非临床证据） |

## 关键改动（按 MUST）

| MUST | 表面 / 文件 | 改动 |
| --- | --- | --- |
| #1 | `CoachHistoryDrawer.swift` | 6 处 `design: .rounded` → VelaTheme 语义字阶；选中行 `rhythmDeep.opacity(0.3)` → `rhythmInk` 1pt 选中描边 + `rhythmCanvasRaised`；新建对话按钮 14pt 圆角 → ink `Capsule()`；搜索框 12→`radiusSm` + hairline；Divider → hairline token；AX 字号下标题/元信息放开 `lineLimit` + `fixedSize` |
| #2 | `Core/DesignSystem/VelaCard.swift` | `VelaMetricCard` 的 `domain.color.opacity(0.16)/0.75pt` → `hairline`/`hairlineWidth`；`InsightCard` 去 `.ultraThinMaterial` + 左侧 3pt 色条 + 0.5pt soft 描边 → 实色 `cardBg` + hairline + `radiusCard`；`EmptyStateCard` 虚线 `border` → hairline、accent 空心胶囊 CTA → ink 填充胶囊；`VelaEmptyState` CTA 同步 mono |
| #3 | `SharedComponents/VelaLogoMark.swift` | `LinearGradient` 底 + `accent.opacity(0.2)` 描边 → `surfaceFloating` + hairline + solid ink；Canvas sail/mast/marks 全部 ink |
| #4 | Coach / Journal / Training / Settings 高频文字 | 本波触及文件中 `design: .rounded` **63 → 1**（剩余 1 处为 `VelaDesignSystem` 内 SF Symbol 图标字号）；非图标固定字号按语义档位迁入 `VelaTheme`；所有保留的 `.font(.system(size:))` 均为 SF Symbol/几何图标（逐文件核对，见各文件 `swiftc -parse` 与 reviewer 记录） |
| #5 | TrustCenter / Biology / CoachHistoryDrawer / WorkoutDetailSubComponents / Quick Actions / Sheets | 触及文件数字圆角字面量 **183 → 16**，其余为数据 mark（2.5/3/3.5/4/6pt 图表/图例）与 DS 内部小 tile（下一波） |
| #6 | `VelaQuickActionsSheet` / `JournalComposeSheet` / `TodayEvidenceSheet` / `WeightLogSheetView` | QuickActions padding/cancel 对齐 D sheet（cancel 58→44pt，space/pagePadding token）；Journal logger 五张 sheet 卡片 20/16→`radiusCard`、内嵌输入/chip 14/10→`radiusSm`、ink CTA→`Capsule()`、padding 对齐 `pagePadding`；Evidence 26→`radiusCard`；Weight 保存 CTA→`Capsule()` 并保留 #20 的 AX DatePicker 分支 |
| #7 | Training/Strength 详情 + Recovery + Plan | Fitness/Strength/Log sheet/subcomponents 的 `.rounded` 清零、chrome 半径 token 化；**保留**图表 AreaMark/折线/数据点/心率区间数据 mark；`RecoveryDetailV2` 分数环 **3.5pt → 2.5pt**（轨 `scoreTrack`、填充 `rhythmInk`，仍 mono）；`VelaTrainingPlanView` 非 approval 边框归 hairline，**approval ink 1.2 描边与 pill 按钮保留** |
| #8 | `VelaOnboardingView.swift` | sample 预览 `previewBar` 填充 `domain.color` → `VelaTheme.rhythmInk`（track 保持）；两处 `VelaMetricScoreRing` 显式 `accent: rhythmInk`；`trustPill` 14→`radiusCard`、图标 tile 11→`radiusSm`；Watch/Widget 配色未动 |

SHOULD：
- #9 复核：`MessageBubble`（用户 = `surfaceFloating` + hairline；AI = 纯正文无泡）在 #18/#20 已完成，本波未回退；`TypingIndicator` 去掉气泡 chrome，只留 ink dots。
- #10 `VelaMemoryProposalCard`：`.borderedProminent` + accent → ink 确认胶囊 + hairline 拒绝/编辑等宽按钮。
- #11 AccessibilityXXXL：CoachHistoryDrawer / Journal logger / Quick Actions / Onboarding 预览已截图抽检，文字未裁切、CTA 不溢出。

## 命令与退出码

| # | 命令 | 结果 | exit |
| --- | --- | --- | --- |
| 1 | `xcodebuild build -project Vela.xcodeproj -scheme Vela -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO` | **BUILD SUCCEEDED**，0 warnings（warnings-as-errors 已固化在工程） | 0 |
| 2 | `xcodebuild test ... -only-testing:VelaTests` | **TEST SUCCEEDED**：676 tests，0 failed | 0 |
| 3 | `xcodebuild test ... -only-testing:VelaUITests/VelaSmokeUITests/testVisualBodyWave22Snapshots` | **passed**（56.0s） | 0 |
| 4 | `xcodebuild test ... -only-testing:VelaUITests/VelaSmokeUITests/{testVisualResidualSnapshots,testVisualNextWaveSheetsAndCoachSnapshots,testUpgradeSurfaceSnapshots}` | **3/3 passed**（53.2s / 47.8s / 38.6s） | 0 |
| 5 | `python3 scripts/check_fixed_fonts.py --strict` | exit 0；179 sites / 阈值 216（与 wave21 baseline 180 持平且略降） | 0 |
| 6 | `bash scripts/audit_design_tokens.sh` | exit 0；`Color(hex:)` 0、直写语义色 0、合计 590（baseline 601；该脚本把 token 化后的 `RoundedRectangle(cornerRadius:` 也计数，故用「数字字面量」指标衡量本波） | 0 |
| 7 | `python3 scripts/check_contrast.py` | 通过 | 0 |
| 8 | `python3 scripts/schema_fingerprint.py --check` | 通过（schema 未变） | 0 |
| 9 | `git diff --check` | 通过 | 0 |

原始日志：[`build-success.txt`](build-success.txt)（0 warnings / BUILD SUCCEEDED）、[`unit-tests.txt`](unit-tests.txt)、[`ui-wave22.txt`](ui-wave22.txt)、[`ui-regression.txt`](ui-regression.txt)、`design-token-after.txt`、`fixed-font-after.txt`、`contrast-after.txt`、`schema-fingerprint-after.txt`。

### 圆角 / 字体密度 before → after（仅本波触及文件）

| 指标 | before | after |
| --- | --- | --- |
| 数字圆角字面量 `RoundedRectangle(cornerRadius: [0-9])` | 183 | **16**（剩余全为数据 mark 或 DS 内部小 tile） |
| `design: .rounded` | 63 | **1**（剩余 1 处为 SF Symbol 图标字号） |
| `.font(.system(size:))` 文本站点 | 97 | 96（保留者均为图标） |
| `.ultraThinMaterial`（app 内） | 3 | 1（剩余 `Compatibility/Today/TodayLegacyCompatibility.swift`，非本波表面） |

## 截图（Dark / SE 375pt / iOS 26.5）

| 表面 | 证据 |
| --- | --- |
| Coach 历史抽屉（新建 pill / 搜索 / 选中行 hairline） | [wave22-coach-history-dark.png](wave22-coach-history-dark.png) |
| 同上 AccessibilityXXXL | [wave22-coach-history-accessibility.png](wave22-coach-history-accessibility.png) |
| Quick Actions（D sheet padding / 44pt cancel） | [wave22-quick-actions-dark.png](wave22-quick-actions-dark.png) |
| 同上 AccessibilityXXXL | [wave22-quick-actions-accessibility.png](wave22-quick-actions-accessibility.png) |
| Journal「随手记」logger sheet（radiusCard + ink pill CTA） | [wave22-journal-quick-note-dark.png](wave22-journal-quick-note-dark.png) |
| Onboarding 预览（mono 环/条） | [wave22-onboarding-preview-dark.png](wave22-onboarding-preview-dark.png) |
| Recovery 详情（2.5pt mono 细环） | [wave22-recovery-detail-dark.png](wave22-recovery-detail-dark.png) |
| Plan（approval ink 1.2 + pill 保留；主 CTA pill） | [wave22-plan-dark.png](wave22-plan-dark.png) |

## 有意保留的数据语义色 / 厚边（D 允许）

- Recovery 分数环：`scoreTrack` 轨 + `rhythmInk` 填充（单色，2.5pt）；趋势 sparkline、个人范围带、today 空心点。
- 图表：AreaMark/LineMark、心率 Ribbon、心率区间、睡眠阶段、地图起终点/路线、进度/环形作数据、sparkline 数据点。
- 训练详情：`FitnessActivitySummaryDetailView` 面积图渐变、2pt 折线、1.5pt 数据点圆环；`StrengthWorkoutDetailView` Chart AreaMark/LineMark。
- Plan approval 卡：ink 1.2pt 描边 + 两枚 pill 按钮（D 有意）。
- 状态/错误/破坏性/新鲜度语义色；`appleIntelligenceGlow` 已是 no-op（未改名，避免无谓 diff）。
- Watch / WidgetKit（含 `VelaMetricDetailWidgets`）全部未动。

## 刻意跳过（SKIP）

- Watch / WidgetKit / `VelaMetricDetailWidgets`（其 `.rounded` 仍保留，属 widget 范围）。
- 评分 / schema / HealthKit / Store / 导航 IA / 对话历史列表功能（#1 只改 drawer chrome）。
- Today 五分横条 / Speak pill / chips / 顶栏分段 / AskBar mic 布局；#23 Settings → 联网 Agent 修复。
- `JournalCorrelationSection`、`VelaTrendsView`、`BodyModelViews`、`WorkoutDetailView`、`VelaSettingsView` 等未列入本波 MUST 的表面仍有数字圆角/字面量半径（下一波统一）。
- `Compatibility/Today/TodayLegacyCompatibility.swift` 的 `.ultraThinMaterial`（legacy 兼容层）与 `VelaNativeCard` 调用点上的 `radius:` 字面量（全仓同类残留，下一波统一）。
- 未做真机、Reduce Motion、VoiceOver、iOS 17 最低版本、全量 UI 测试套件、Watch/Widget 构建验证。

## 风险 / 未验证

- 视觉变化为 SwiftUI 快照/截图人工核对（dark/light/AX 抽检），未做像素级 diff。
- 圆角从 16/20/22/24 收敛到 18（`radiusCard`）与 pill CTA 属有意视觉变化；不影响布局语义与可点击区域（最小 44pt）。
- 未提交 xcresult 大文件；仅保留截图与日志摘要。
