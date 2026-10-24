# Visual Body wave21 · 联网 Agent 导航卡死修复 + Design D 残留（2026-10-24）

- 基线：`origin/main` / `7e102927`（PR #20 squash，含 #17/#18/#20 的 Design D 视觉主线）。
- 分支：`cursor/visual-body-wave21-20261024`；Issue [#21](https://github.com/SunWeizhou/bodyseek/issues/21)。
- 工作树起点：`git status --short` 仅有此前 wave21 会话遗留的 `VelaUITests/VelaSmokeUITests.swift` 复现用例与本目录 before 扫描；本轮在其上继续。
- 环境：macOS 27.0.1 / Xcode **27.1 (27A9275)**（仓库 `.xcode-version` 为 **26.5.0**，不一致，未改 CI/工具链）；iPhone SE (3rd gen) 375pt / 750×1334px，iOS **26.5 (23F77)**，arm64 Simulator；中文（`-testLanguage zh -testRegion CN`）；Dark 默认字号，另做 Light + AccessibilityXXXL 抽检。
- 数据：`-velaPreviewDashboard` 预览数据与空的本机模拟器记录；不含个人 HealthKit 数据，不构成临床有效性证据。

## 1. MUST：Settings →「联网 Agent」导航卡死

### 1.1 修复前复现

用户路径：Today → 个人空间（Settings sheet）→ 向下滚动 → 点「联网 Agent」。修复前该操作可能停留在 Settings，并出现持续 SwiftUI 更新。

UI 用例 `testNetworkAgentNavigationAfterFullSwipe`：`-velaOpenSettings` 直接打开 Settings → `swipeUp()` 深滚一次 → 点「联网 Agent」→ 断言 `AI 模型设置` NavigationBar。

- 修复前 **2/2 命中卡死**（同一 HEAD `7e102927` 生产码，仅测试文件不同）：
  - Run 1（2026-10-24 11:00 +0800，`BodySeek Wave21 Disposable`）：tap 于 8.19s，等待 idle 直到 **68.20s** 才报 `App event loop idle notification not received`；`AI 模型设置` 查询 85.51s / 124.80s / 155.81s 全部超时；测试于 **199.65s** 以 `Failed to get matching snapshots: Timed out while evaluating UI query` 失败（exit 65）。
  - Run 2（12:38 +0800，`BodySeek Residual SE`，重新 `xcodebuild test` 构建）：tap 9.29s → idle 9.72–69.73s 超时 → 查询 87.35s 起读不到；**201.98s** 失败（exit 65）。
- 对照（修复前）：同一 destination 不经过深滚直接进入时 6/6 通过（direct tap / Trust→Agent / 大字体 / 深链，见 `build/wave21/red.log`、`baseline-matrix.log`、`baseline-consent-large.log`）；destination 页面本身渲染正常（[before-agent-destination-dark.png](before-agent-destination-dark.png)）。
- 时间线与原始日志：[before-navigation-hang.txt](before-navigation-hang.txt)；深滚后画面：[before-settings-full-swipe-dark.png](before-settings-full-swipe-dark.png)。

### 1.2 根因定位

卡死发生在 **tap 触发的 push 布局事务内部**，不是 Keychain、网络或 IO 阻塞：

- 修复前在卡死窗口内对 App 进程取 `sample`（tap 后约 12s 与 32s，两次）：main thread 两次都 100% 处于 UIKit update cycle → SwiftUI `GraphHost.flushTransactions` → `AG::UpdateStack::update` → **`DynamicLayoutComputer.updateValue`**；其它线程空闲。XCUITest 侧 spindump 同时显示主线程 **438/438 samples** 都在这条事务链里。
- 更早的 #18 基线完整符号化采样（401 samples，`/tmp/bodyseek-next-stack.txt`）显示该事务最大子树为 `LazyStack.measureEstimates` / `LazySubviewPlacements` / `ScrollViewAdjustedState`，并反复复制兄弟行的 `NavigationLink` destination。
- 归因（中高置信度，样本 + 控制矩阵推断）：Settings 根 `ScrollView` + `LazyVStack` 在深滚动后 push 一个 `Form` destination（`AIModelSettingsView`）时，lazy 行测量/滚动调整与 push transition 互相触发，形成**不收敛的 layout 更新事务**；“直接点能过、深滚后点必挂”与“浅滚源通过、深滚源卡死”的矩阵一致。`AIModelSettingsView` 自身没有 `.onAppear`/`task` 循环或发布风暴（#20 已用 production `UIHostingController` 独立托管证明其可正常渲染）。
- 证据摘录：[hang-stack-excerpt.txt](hang-stack-excerpt.txt)（A：#18 401-sample 符号化指纹；B：本轮修复前 12:38 采样）。

### 1.3 修复

- `VelaApp/Features/Minimal/VelaSettingsView.swift`：Settings 根列表 `LazyVStack` → **`VStack`**（1 行结构变化 + 说明注释）。Settings 只有约 22 行轻量设置行与 profile 卡，eager 渲染无性能顾虑；不改设计、文案、IA、导航语义、授权语义，也不改其它 Settings 子页。
- 回归用例（`VelaUITests/VelaSmokeUITests.swift`，本 wave 新增/固化）：
  - `testNetworkAgentNavigationAfterFullSwipe` — 本 bug 的复现路径（深滚 → 联网 Agent → 目标页）；
  - `testNetworkAgentNavigationAndReturn` — 进入 → 返回 → 再次进入；
  - `testNetworkAgentNavigationFromTrustAndLargeType` — Trust 入口 → 联网 Agent，含 AccessibilityXXXL；
  - `testNetworkAgentNavigationWithReviewedConsent` — 已授权状态下 destination consent 区可滚动可达；
  - `testNetworkAgentDirectNavigationLargeType` — AccessibilityXXXL 直达；
  - `testSettingsRowAfterFullSwipePushesScrollViewDestination` / `testSettingsRowAfterFullSwipePushesFormDestination` — E1/E2 判别：深滚后 ScrollView / Form destination 都必须可 push。

### 1.4 修复后证据

- 卡死用例 **3/3 通过**（`-test-iterations 3`）：12.360s / 12.358s / 12.376s，`** TEST SUCCEEDED **`，exit 0。tap 后 8.47s → 10.99s 即出现 `AI 模型设置`，不再有 idle 超时。
- 导航矩阵：return 18.773s、Trust+大字体 54.102s、reviewed consent 18.950s 全通过；E1 ScrollView destination 14.259s、E2 Form destination 12.398s 全通过；大字体直达 30.200s 通过。
- 既有回归：#20 的 `testVisualNextWaveSettingsSnapshots`（Settings 子页矩阵）72.523s 通过、`testSettingsDeepLaunch` 通过；`VelaThemeTests` **151 tests / 0 failures**。
- 端到端截图（Dark、SE、iOS 26.5、Xcode 27.1）：
  - 同一深滚 Settings 画面 [before](before-settings-full-swipe-dark.png) → [after](after-settings-full-swipe-dark.png)；
  - 点击后目标页可见：[after-agent-from-full-swipe-dark.png](after-agent-from-full-swipe-dark.png)（Settings → 点入口 → **AI 模型设置**）；
  - 直点 destination / consent 首屏 / 已授权 consent / Trust 大字体：[destination](after-agent-destination-dark.png)、[consent](after-agent-consent-dark.png)、[reviewed consent](after-agent-reviewed-consent-dark.png)、[accessibility](after-trust-agent-accessibility.png)、[direct accessibility](after-agent-accessibility.png)；
  - E1/E2 深滚后其它 destination：[Trust](after-full-swipe-trust-dark.png)、[隐私与数据控制](after-full-swipe-privacy-dark.png)。
- 完整命令、输出与退出码：[after-navigation-pass.txt](after-navigation-pass.txt)；静态扫描：[fixed-font-after.txt](fixed-font-after.txt)、[token-after.txt](token-after.txt)。

### 1.5 诚实保留的失败/边界

- `verify-nav-matrix` 首次运行 exit 65：E1+E2 合并版用例因 UI 自动化反复滚动被 runner 以 `signal kill` 终止（不是 app 卡死；3 个导航用例已通过）。随后拆成两个 fresh-launch 用例并重跑通过，失败 run 不计为通过。
- 根因机制为 sample/控制矩阵推断（medium-high），未做 SwiftUI 内部源码级验证；修复以行为回归为准。
- 工具链不一致：Xcode 27.1 ≠ 仓库 pin 26.5.0，未声称固定工具链 CI 通过；未验证 pinned Xcode 是否本就难复现（若不复现则为工具链相关布局回归，本修复是结构性规避）。

## 2. SHOULD：#20 tip 后 Design D 残留

- 静态审计（修复后）：`python3 scripts/check_fixed_fonts.py --strict` exit 0（180 处 / 阈值 216，与 baseline 相同）；`bash scripts/audit_design_tokens.sh` exit 0（`Color(hex:)` **0** 处；178 处 `system(size:)` 均为图标/显示几何等，非本轮清理目标）；`bash scripts/check_contrast.py` exit 0；`git diff --check` exit 0。token report 的 inline `RoundedRectangle` 计数是报告项（多数在消费 token 的圆角），不作为硬编码违规数。
- 本轮实际改动（2 处 view-only，全部使用既有 `VelaTheme` tokens，不改布局/文案/行为）：
  1. `VelaApp/Features/Minimal/MetricHighlightsSection.swift`：`MetricInterpretationSection` 面板 `tint.opacity(0.22), lineWidth: 0.75` 描边 → `VelaTheme.hairline` / `hairlineWidth`（与 #18/#20 已收口的同族卡片一致，去除装饰色描边）。
  2. `VelaApp/Features/Minimal/VelaJournalView.swift`：周条“今天”圆环 1.5pt accent 描边 → `hairlineWidth`（chrome 厚度收口，非数据 mark，圆环半径/颜色不变）。
- 明确保留（数据/语义色，不视为残留）：心率区间、睡眠阶段、五项指标序列 tint、地图起终点、进度环/折线/面积填充等数据 mark；错误/破坏性/数据新鲜度；灰度 loading shimmer；`appleIntelligenceGlow` 在主线已是 no-op（不把删除调用名当视觉修复）。
- 明确跳过：Watch / WidgetKit（含 `VelaMetricDetailWidgets` 预览段 5 处直接色与 shadow，沿用 #20 的跳过理由）、`CoachHistoryDrawer`、对话历史列表、Today 五分横条 / Speak pill / chips / 顶栏分段 / AskBar mic 主布局、Settings 二级页（#20 已收口）。
- 范围纪律：扫描中出现的 `design: .rounded` 等字体样式候选不属于“颜色/厚边/glow/渐变描边”残留类别，且 #18 曾有意保留；为避免本波扩大成 UI 重绘，**未纳入**本轮（这些候选不计入本 PR 的修复清单）。

## 3. 未验证 / 风险

- 未覆盖：所有 Settings 子页的全量矩阵、每档 Dynamic Type × Light/Dark 组合、iOS 17 真机、VoiceOver / Reduce Motion 手工矩阵、真实 HealthKit / GPS / 长训练历史、全量 UI 测试套件、Watch/Widget 构建与部署。
- 未改：评分公式、schema、HealthKit 算法、Store/数据投影、授权与同意语义、对话历史列表、IA/Dock。
- 未验证 remote 固定工具链 CI；本目录命令均在 Xcode 27.1 / iOS 26.5 模拟器执行。

## 4. 附件清单

| 文件 | 含义 |
| --- | --- |
| [before-navigation-hang.txt](before-navigation-hang.txt) | 修复前 2 次卡死的时间线（含 t= 值、错误与时长） |
| [hang-stack-excerpt.txt](hang-stack-excerpt.txt) | 卡死时 main thread 的 SwiftUI update-transaction 指纹（#18 401-sample + 本轮采样） |
| [after-navigation-pass.txt](after-navigation-pass.txt) | 修复后 6 组命令的通过输出（含 3/3 深滚回归） |
| `before-settings-full-swipe-dark.png` / `after-settings-full-swipe-dark.png` | 同一深滚 Settings 画面，修复前/后 |
| `after-agent-from-full-swipe-dark.png` | 深滚后点「联网 Agent」→ 目标页（端到端） |
| `after-agent-destination-dark.png`、`after-agent-consent-dark.png`、`after-agent-reviewed-consent-dark.png` | 直点目标页 / consent 首屏 / 已授权状态 |
| `after-trust-agent-accessibility.png`、`after-agent-accessibility.png` | Trust 入口与大字体抽检 |
| `after-full-swipe-trust-dark.png`、`after-full-swipe-privacy-dark.png` | E1/E2 深滚后其它 destination |
| `before-agent-destination-dark.png`、`before-agent-consent-dark.png` | 修复前 destination 渲染本身正常（hosted 前的直点证据） |
| `fixed-font-before/after.txt`、`token-before/after.txt`、`color-candidates-before.txt` | 静态审计 before/after 与候选清单 |
