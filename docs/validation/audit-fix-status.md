# 工程审计修复状态总表（2026-08-23 起）

> 追踪 docs/validation/engineering-audit-2026-08-23.md 各项的修复状态。
> 每个修复均通过：警告即错误构建 + 全量测试套件（约 470+ 测试）。

| 编号 | 审计项 | 状态 | 关键提交 | 备注 |
| :--- | :--- | :--- | :--- | :--- |
| C1 | SwiftData schema 版本管理 | ✅ 完成 | 26906c18 | 冻结快照 + `schema_fingerprint.py` CI 守卫（模型图变更必须与版本提升同提交）；经验证 SwiftData 拒绝同 checksum 双 schema，故 V3=live + 冻结预案；迁移测试恢复通过 |
| C2 | HealthKit 错误吞没 | ✅ 完成 | 26906c18 | 仅 errorNoData 放行；组件级失败分类；核心组件全失败不落全空快照；`lastSuccessfulSyncAt` 条件推进 |
| C3 | 本地化基础设施 | ✅ 完成（决策 C） | edbd1afc | 用户拍板方案 C（中文优先 + English Beta 如实说明）；已修：未选择时跟随系统语言、a11y 字符串走 L10n；方案 A/B 留作升级路径（见 `docs/validation/i18n-coverage-2026-08-23.md`） |
| H1 | Dynamic Type | ✅ 大部分（设计项除外） | a300c63c, 35e97839, dc461878, 23ab73e8 | 主题字号 + 设计系统 + 视图层共约 355 处文字字号转系统 TextStyle；剩余 481 处为图标/显示级设计决策项（`scripts/check_fixed_fonts.py` 追踪） |
| H2 | 全表扫描/主线程重计算 | ✅ 完成 | 26906c18, 4863e883 | fetchLimit 有界化、fetchCount、流式 markdown 缓存、BodyModelBuilder 值类型化 + loadDashboard/缓存路径离线计算、bodyModel 记忆化（等价性测试守护） |
| H3 | 后台任务预算 | ✅ 完成 | a300c63c | BGAppRefreshTask 复用 App 容器（省去重复打开 store/迁移检查） |
| H4 | 崩溃上报/日志 | ✅ 完成（云端集成已验证） | 50f96090, 94cc8dba | 本地：os.Logger 迁移 + 崩溃日志时间戳化轮转（CrashLogStore）；云端：Sentry 集成（sentry-cocoa@8.x，DSN 存 Keychain、缺省零上传、禁 PII/面包屑/采样）已通过警告即错误构建 + 全量测试；填写 DSN 后生效（见 sentry-integration-guide.md） |
| H5 | CI 门禁与工具链 | ✅ 完成 | 26906c18, 432f8c5f, c295d26d | schema 守卫、对比度守卫、固定字号扫描、SwiftLint（brew 安装真正执行，report-only）、覆盖率采集+报告、xcresult 上传、.xcode-version、工具链校验、日志出仓；**发布链路**（TestFlight/fastlane）需 Apple 账号，未列 |
| H6 | 对比度/硬编码色 | ✅ 完成 | a300c63c, 432f8c5f | `textColor(for:)` 文字变体（WCAG AA ≥4.5:1 实测达标）+ 6 处文字切换 + `check_contrast.py` CI 硬门禁；85 处视图层 `Color(hex:)` 为暗色变体设计项（lint 规则追踪） |
| H7 | 数据删除盲区 | ✅ 完成 | 26906c18 | daily_logs 明文归档 + VelaRecovery 备份纳入「清空本地数据」+ 确认文案明示 Keychain/Apple Health/iCloud 备份；4 个删除完整性测试 |
| H8 | 命中区/VoiceOver | ✅ 完成 | a300c63c, 35e97839, dc461878, c295d26d | 命中区 44pt（+ 月份切换等）、Tab 标识符、3 处手势 accessibilityAction、装饰图标隐藏、关闭/步进/月份按钮标签（L10n 双语）；主屏（Hero/Trends/Fitness/Coach）语义化标签此前已达标 |

## 建议下一步（按价值排序）

1. **你拍板 C3**（读 i18n-coverage 报告；推荐方案 C 归档，或确认 B 后我分批抽取）
2. **Sentry 接入**：在你网络环境下加 SPM 依赖 + 填 DSN（我提供完整 diff 与启用说明）
3. **H1 剩余 481 处**：真机过一遍大字号 AX 设置为设计评审依据
4. **发布链路**：fastlane 配置（需 Apple 账号）

## 2026-10-22：趋势概览图可读性

本节独立记录本次 UI 变更，不更新上面的历史审计结论。

- 起点：`236f236becce0035cd7c6bf958a58dda4940a14a`，开始时工作树干净；本地分支 `codex/ui/readable-trend-charts`，以下为未提交变更。
- 范围：`VelaTrendsView.swift`、`TrendsOneMetricChart.swift`、`TrendsStoreTests.swift`、`VelaSmokeUITests.swift`。评分、Store 数据合同、HealthKit 读取、数据库和算法版本未改变。
- 结果：五项指标各自使用整行图表；标题/当前值与曲线分层；保留黑白主题，增加日期和统一的 0–100 刻度。仅连接原有连续非空段，保留孤立点、真实零值和空档；个人范围只显示已有基线。密集序列减少圆点，最新观察点保持可见。记录不足时展示明确的天数进度，图例按实际数据出现。
- 实现：概览由 SwiftUI Canvas 绘制，详情的 Swift Charts 路径保持原样。固定五项概览使用 `VStack`，时间选择器支持大字体横向滚动；图内坐标标签限制最大显示字号，卡片数值与 VoiceOver 摘要仍跟随完整字体设置。

### 本地验证

环境：Xcode 27.0（27A266a），iPhone 17 / iOS 26.5 模拟器，简体中文。仓库固定工具链仍为 26.5.0，本次不代表该版本 CI 或真机验收。

```sh
xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug \
  -destination 'platform=iOS Simulator,id=80FFA19E-69E6-499F-B246-F071A2D369BF' \
  -parallel-testing-enabled NO -derivedDataPath build/UIOnboardingDerivedData \
  -resultBundlePath build/trend-chart-review/TrendsFinal.xcresult \
  -only-testing:VelaTests/TrendsStoreTests \
  -only-testing:VelaUITests/VelaSmokeUITests/testTrendsScoreContentAndMetricRouting \
  -only-testing:VelaUITests/VelaSmokeUITests/testTrendsChartLayoutsAndHorizons \
  -testLanguage zh -testRegion CN CODE_SIGNING_ALLOWED=NO test
```

- 最终退出码 0：4 项 App 测试和 2 项 UI 测试通过，0 失败。包含缺失分段/来源传递、稀疏/零/全缺失原生渲染、四个时间窗口切换、五项卡片可滚动到达、恢复详情跳转、明暗模式及 Accessibility XXXL 截图。
- `git diff --check` 退出码 0。基线通用模拟器构建也为 0；没有进行真机安装、发布或远端 CI。
- 原生证据：`build/trend-chart-review/TrendsFinal.xcresult`；导出清单 `build/trend-chart-review/final-attachments/manifest.json`，共 9 张截图，均为界面预览或固定合成输入，不是用户真实健康记录。浅色/深色/大字体及 320pt 图表样例已人工查看。
- 复核入口：`build/trend-chart-review/before-light.png`、`after-light.png`、`trends-dark.png`、`trends-accessibility-chart.png`，以及三个 `trends-chart-*-320pt.png`。
- 被测源码差异保存在 `build/trend-chart-review/source.diff`；构建、截图、结果包均位于已忽略的 `build/`，未加入版本控制。

### 调试边界与剩余限制

初轮新增 UI 测试将卡片误按 Button 类型查询而失败（退出码 65），已改用现有页面的稳定标识。随后两次滚动实验暴露持续布局，均人工中止（退出码 75）；采样保存在 `/tmp/bodyseek-trends-*-scroll-sample.txt`。最终采用 Canvas 概览与非惰性固定卡片布局，滚动流程和最终定向回归均通过；未分别证明单独一个修改足以解决该系统上的布局循环。

超大字体截图仍能看到全局 Shell 的导航文字、图标与提问栏已有截断；本次没有修改共享 Shell。图表坐标与卡片正文已分别核对。加载失败分支未做运行时故障注入；本次也不验证真实 HealthKit 授权、完整评分正确性或全部机型。

## 2026-10-22：主页面复用、页内对话与听写修复

本节记录后续交互工作，不将定向回归扩写为上表的全量测试结论。

- 起点仍为 `236f236becce0035cd7c6bf958a58dda4940a14a` / `codex/ui/readable-trend-charts`，接续上一节尚未提交的趋势图及证据改动；保留工作树，未提交或推送。
- 真机基线：通过 iPhone 镜像操作，旧版点击「说话」两次均退出应用。`build/interaction-review/voice-before.ips` 对应 `Vela-2026-10-22-212945.ips`：系统 Speech 授权回调在后台队列执行，进入隐式 MainActor 隔离闭包后触发 `_dispatch_assert_queue_fail` / `_swift_task_checkIsolatedSwift`。原有麦克风及 Speech 权限描述已存在。
- 加载复现：重复 `.appear` 的 reader 调用次数为 3，新增用例期待 1；原版明确发送按钮、语音入口回归也失败。结果包 `build/interaction-review/Before.xcresult`。

### 最终行为

- TodayStore 在同一选定日期、成功加载后的 15 分钟内复用已发布状态，页面返回不再触发缓存读取及 live load。显式刷新、日期变化和已有数据失效流程保留；不伪造健康数据更新时间。
- 输入草稿由独立可观察对象管理，逐字输入不再使整个健康页面随之重算。移除键盘通知的全局动画、进入计划/完整对话时的额外 dashboard 刷新及计划页面的强制 identity 重建。
- 全局提问栏在当前主页面展开对话，复用同一 Coach VM、历史、授权与工具确认流程；完整工作区成为可选展开。草稿跨收起、展开及取消联网同意保留。麦克风、发送、停止回复分开；停止听写只保留可编辑文字，不自动发送。
- Speech 授权、音频 tap 与识别回调通过非隔离桥接，再将结果送回 MainActor；启动支持取消及 generation 检查。使用本机 Speech 识别，并检查输入及格式；异常可见，不清空草稿。
- 今日建议独立为卡片，连接现有「判断依据」入口及页内对话。去除首页/计划中的大块人为留白。趋势继续使用上一节的五项独立图表；对话上下文携带当前可见趋势窗口与指标。评分、持久化 schema 和 HealthKit 输入含义未改变。

### 本地构建与定向回归

环境仍为 Xcode 27.0（27A266a），iPhone 17 / iOS 26.5 模拟器、中文；仓库固定版本仍为 26.5.0。下面两条命令均退出 0，共 **30 项不同检查通过、0 失败**：24 项 App 测试及 6 项 UI 测试，非全量套件或远端 CI。

```sh
xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug \
  -destination 'platform=iOS Simulator,id=80FFA19E-69E6-499F-B246-F071A2D369BF' \
  -parallel-testing-enabled NO -derivedDataPath build/UIOnboardingDerivedData \
  -resultBundlePath build/interaction-review/Validated.xcresult \
  -only-testing:VelaTests/TodayStoreTests \
  -only-testing:VelaTests/TodayViewStateTests \
  -only-testing:VelaTests/TrendsStoreTests \
  -only-testing:VelaTests/StabilizationTests \
  -only-testing:VelaUITests/VelaSmokeUITests/testAskBarOffersExplicitSendAndStaysOnCurrentPage \
  -only-testing:VelaUITests/VelaSmokeUITests/testDraftSurvivesExpandedChatAndCancelledConsent \
  -only-testing:VelaUITests/VelaSmokeUITests/testSpeechPermissionCallbackDoesNotTerminateApp \
  -only-testing:VelaUITests/VelaSmokeUITests/testPrimaryPageStateAndInlineConversationSnapshots \
  -only-testing:VelaUITests/VelaSmokeUITests/testTrendsScoreContentAndMetricRouting \
  -only-testing:VelaUITests/VelaSmokeUITests/testTrendsChartLayoutsAndHorizons \
  -testLanguage zh -testRegion CN CODE_SIGNING_ALLOWED=NO test

xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug \
  -destination 'platform=iOS Simulator,id=80FFA19E-69E6-499F-B246-F071A2D369BF' \
  -parallel-testing-enabled NO -derivedDataPath build/UIOnboardingDerivedData \
  -resultBundlePath build/interaction-review/BoundaryChecks.xcresult \
  -only-testing:VelaTests/CoachInteractionBoundaryTests \
  -testLanguage zh -testRegion CN CODE_SIGNING_ALLOWED=NO test
```

第一条实际执行 21 项 App + 6 项 UI。`StabilizationTests.swift` 不在工程 target 中，其过滤器没有运行任何用例，不能计入通过数；新增的三个回调/取消/上下文测试已移到工程注册的 `TodayStoreTests.swift` 中，以 `CoachInteractionBoundaryTests` 单独执行，第二条实际通过 3 项。

覆盖重复 appearance、过期及强制刷新、后台 Speech 授权回调、取消启动、上下文窗口、三主页面往返、建议依据、输入/发送、页内回复与继续对话、完整页草稿交接、取消联网同意，以及趋势窗口/缺失/零值/明暗与大字体。联网回复使用 DEBUG 离线边界；同意流程测试只取消，不批准或上传健康信息。调试中曾修正 UI 查询标识传播、按钮实际命中区，以及仅发送 no-op adapter 而未打开依据 sheet 的入口问题。

原生截图与导出清单：`build/interaction-review/validated-attachments/manifest.json`，可读副本包括 `interaction-today-light.png`、`interaction-advice-evidence.png`、`interaction-plan-light.png`、`interaction-inline-draft-light.png`、`interaction-inline-answer-light.png`、`interaction-inline-resumed-light.png` 和 `interaction-consent-cancelled-draft.png`。这些是模拟器预览/固定样例，不是用户真实健康数据。已查看主要布局及键盘状态。

### 授权后的覆盖安装与真机操作

用户明确选择「覆盖安装并继续验证」，保留现有数据，不卸载。以下构建、签名、安装、启动均退出 0：

```sh
xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build/DeviceDeployDerivedData build
codesign --verify --deep --strict build/DeviceDeployDerivedData/Build/Products/Debug-iphoneos/Vela.app
xcrun devicectl device install app --device 00008140-00164DE022C3801C \
  build/DeviceDeployDerivedData/Build/Products/Debug-iphoneos/Vela.app \
  --json-output build/interaction-review/device-install.json
xcrun devicectl device process launch --device 00008140-00164DE022C3801C \
  com.sunweizhou.Vela4 --json-output build/interaction-review/device-launch.json
```

设备为 iPhone 16 Pro / iOS 27.0.1，bundle `com.sunweizhou.Vela4`。本地包版本 4.0.0 (1)；以安装回执、新版实际 UI 和源码/二进制哈希共同标识，不能仅依赖版本号。`device-build-receipt.json` 保存构建哈希；`source.diff` SHA-256 为 `085e4bbe5d05c49d56fc49b71448f6a850ecd73f37a434650f5ed026824f146c`。安装回执的新 bundle 路径为 `40499019-65AF-4733-9F49-478B5D65EC11/Vela.app`，启动 PID 78553，未传测试样例或禁用联网参数。

2026-10-22 22:24–22:26（Asia/Shanghai）通过 computer use 实际检查：

- 首页新建议卡片及五项指标正常；「查看依据」打开真实判断依据页并可关闭。
- 趋势呈现独立日期/坐标/空档图；今日、趋势、计划多次往返，已显示内容及首页数据时间没有重置为加载画面。
- 计划仍显示既有三项全部完成（3/3）。安装前后 `Vela.store`、WAL、SHM 均存在（主 store 14,041,088 → 14,106,624 bytes，应用继续正常写入）；这是容器文件与可见记录核对，不是全部数据库记录的逐项审计。
- 输入非敏感单字符草稿直接展开当前页对话，发送箭头出现；收起后草稿保留，再打开后可清空。未将真实健康信息或该草稿发送给 AI 服务。
- 点击麦克风没有重现退出，进入「正在听写」，可停止并回到空输入状态。macOS iPhone 镜像弹出「无法从 Mac 使用 iPhone 麦克风。」系统限制提示；未扩展权限，不能据此声称实际收音/转写通过。需要用户在 iPhone 本机完成一句话听写验收。
- 结束时回到今日页，测试草稿已清空，录音已停止；读取的最新 Vela crash 仍是修复前 `Vela-2026-10-22-212945.ips`。安装、启动、文件元数据和 crash 列表回执均保存于本地忽略目录 `build/interaction-review/`。

`git diff --check` 通过。未完成物理设备 Instruments/FPS 测量（xctrace 当时将设备列为 offline）、真实 AI 网络问答或所有页面/机型的无障碍验收，因此不宣称已消除全部卡顿、语音端到端完成或医疗判断有效。

## 2026-10-23：AI 协议恢复、历史评分补算与数据呈现

起点：`9444b04e975ba846cb822d3402f979b5cf70b237`，分支 `codex/ui/readable-trend-charts`，开始时工作树干净。本轮为未提交修改，不推送、不发布。此前真机已复现普通 assistant 回复直接显示 `<tool_call>` / JSON、基线与图表天数含义不清、调整建议遮住正式行动等现象。

### 诊断与修改

- `Before.xcresult` 首次测试因测试语言枚举拼写失败，未计为症状复现。修正为 `simplifiedChinese` 后，`Before2.xcresult` 的两个测试确实失败（退出 65）：短健康问题被划为无工具闲聊；文本化工具协议被当成最终答案。
- 健康词判断现在先于招呼语和文本长度判断；「恢复？」「今天能跑吗」「今晚怎么睡更好」以及混合招呼的健康问题进入原有正式工具链。提示词中的旧 `check_health_data` 改为已注册的 `get_health_history` / `get_today_health`。
- AgentLoop 遇到文本化协议最多要求模型纠正一次，只有正式 tool_calls 可以执行，原有 allowlist、写操作确认和预算仍有效。重复异常抛出可重试错误。旧会话原文保留；界面显示明确失败，可恢复对应问题为未发送草稿，并移除失败回复下的行动追问。上下文装配不再将旧协议片段回送给模型。
- 6 与 7 的主要差异并非算术错误：基线排除所选当天，图表包含当天。现明确写「基线历史，不含当天」及「图中评分日，含当天」，保持既有评分窗口、样本门槛和算法不变。参考范围只在该窗口 finding 可用时显示；七天偏离提示注明七天，能量读数保留百分号。恢复图增加 0/50/100 纵轴，保留已有日期选择、真实零值和空档。
- 历史覆盖页分别显示本机已有原始信号、尚无任何评分的原始日及空记录。原始回填不再承诺五项评分立即可用，查询失败不再被吞成空字典后推进游标。
- 新增本机历史评分补算：只处理已结束、已有原始信号、没有任何既有评分且没有计算证据的日期。复用生产 `DailyHealthComputation` 和当前个人设置，历史健康证据截止该日末；按时间正序计算，后续日期使用已补算的前序结果。已有部分评分和已评估但不可用的结果均保留。写入使用独立 ModelContext、串行写门禁及旧记录版本检查，只填计算字段，不覆盖原始汇总；并发更新会暂停并提示重试。已保存结果支持暂停后续算。
- 首页先显示下一项未完成行动，其他行动可展开；正式计划与完成记录仍由原编辑器维护。调整建议默认摘要，展开完整差异后才出现确认按钮，并明确区分已保存安排和新建议。
- 页内对话按内容选择较小初始高度，支持拖动高度和主动全屏；空闲输入栏用继续对话替代重复加号，给输入留空间。打开长回答及键盘出现时定位回答开头，避免只看到末尾快捷问题。切换趋势窗口读取期间不复用上一窗口的曲线和覆盖数字。

### 定向回归与实际 SwiftUI 证据

环境：Xcode 27.0 / 27A266a；仓库固定版本仍为 26.5.0。iPhone 17 / iOS 26.5 模拟器，中文、常用字号，明暗模式；大字体不作为本轮专项。

`Final.xcresult`：64 项 App + 4 项 UI 通过，退出 0。App 分组为 AgentActionParserTests 27、BodySeekInstrumentCopyTests 2、DataPresentationCopyTests 2、HistoricalScoreRepairTests 6、RecoveryDetailV2Tests 10、TodayStoreTests 13、TrendsStoreTests 4。最后两个纯 UI 修正（长回答定位、窗口加载隔离）后，`FinalUI.xcresult` 重跑相同四项 UI，退出 0。合计 **68 项不同检查通过**，不重复计数。

```sh
xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug \
  -destination 'platform=iOS Simulator,id=80FFA19E-69E6-499F-B246-F071A2D369BF' \
  -parallel-testing-enabled NO -derivedDataPath build/UIOnboardingDerivedData \
  -resultBundlePath build/data-presentation-repair/Final.xcresult \
  -only-testing:VelaTests/AgentActionParserTests \
  -only-testing:VelaTests/HistoricalScoreRepairTests \
  -only-testing:VelaTests/BodySeekInstrumentCopyTests \
  -only-testing:VelaTests/DataPresentationCopyTests \
  -only-testing:VelaTests/RecoveryDetailV2Tests \
  -only-testing:VelaTests/TrendsStoreTests \
  -only-testing:VelaTests/TodayStoreTests \
  -only-testing:VelaUITests/VelaSmokeUITests/testDataRepairLayoutsAndLegacyProtocolRecovery \
  -only-testing:VelaUITests/VelaSmokeUITests/testHistoryRepairEntryIsReachableWithoutStartingHealthQueries \
  -only-testing:VelaUITests/VelaSmokeUITests/testPeriodSummaryCoverageAndCompactComposer \
  -only-testing:VelaUITests/VelaSmokeUITests/testAskBarOffersExplicitSendAndStaysOnCurrentPage \
  -testLanguage zh -testRegion CN CODE_SIGNING_ALLOWED=NO test
```

最后 UI 重跑沿用上述环境、四个 UI 过滤器，结果包改为 `FinalUI.xcresult`。历史补算测试覆盖写入原始值保留、重复运行、部分评分保留、并发更新不覆盖、未来数据不影响历史，以及批量补算与逐日补算一致。真实零值与无数据分开统计。

调试记录：`Core.xcresult` 中已有的三个详情文案预期与起点 HEAD 的生产文案不符（原期望旧「信号基线」字样，当前显示「平时」或 nil），已按当前公开文案修订，数值断言保留。`Regression.xcresult` 的 UI 初轮按 Button 查询被组合为其他类型的图表入口失败，改用原有稳定 identifier 并继续验证详情实际打开；未删除行为断言。以上失败不计为通过。

原生附件清单：`build/data-presentation-repair/final-ui-attachments/manifest.json`；`Final.xcresult` 的 App 图表样例另在 `final-attachments/manifest.json`。主要可读副本包括 `repair-today-light.png`、`repair-today-dark.png`、`repair-trends-light.png`、`repair-coverage-light.png`、`repair-recovery-chart-light.png`、`repair-legacy-protocol.png`、`repair-restored-question.png`、`repair-plan-collapsed.png`、`repair-plan-diff.png`、`repair-history-entry.png`。已人工查看主要布局、键盘状态、失败提示与调整差异。均为本机预览或合成输入，不是真实健康记录；未触发真实 HealthKit 回填或联网 AI。

### 构建产物与边界

签名设备构建及 `codesign --verify --deep --strict` 均退出 0：

```sh
xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build/DeviceDeployDerivedData build
codesign --verify --deep --strict build/DeviceDeployDerivedData/Build/Products/Debug-iphoneos/Vela.app
```

构建身份为 `com.sunweizhou.Vela4` / 4.0.0 (1)，以源码差异和二进制哈希区分本轮，不依赖版本号。`build/data-presentation-repair/source.diff` SHA-256 为 `c978872f29bf89416fa3fda9d438d7c5591a80f4f4488bfc64270090725efe3b`；`device-build-receipt.json` 保存主程序、dylib、Info.plist 的哈希。`git diff --check` 通过。尚未覆盖安装本轮构建，需新的明确部署授权。

上述是定向本地回归、原生布局及签名构建证据，不是全套 CI、完整评分科学有效性或所有设备验收。真实 provider 网络问答、HealthKit 授权/三年真实数据运行、设备听写和 FPS 尚未验证。评分补算入口已实现，但没有对用户真实数据库自动运行。


## 2026-10-23：分支归并与 Xcode 26.5 构建修复

用户明确要求将各开发分支合入 main 并保留单一分支。起点 `a4580e4991a9de08aaf874ce3b009b4b2d935293`，工作树干净；远端 main 为 `caf2f5cc751611c5f0fe868e1eae52967d971dd8`。四个远端开发分支是同一提交链：`cursor/recovery-detail-v2-1d20` → `cursor/neutral-deviation-missing-labels-d427` → `cursor/d-monochrome-tokens` → `codex/ui/readable-trend-charts`。本地 recovery 分支另有 `0ff8effd`，只新增 15 份 D 方向设计资料，已用保留历史的 merge 纳入；设计稿是历史参考，不覆盖当前 PRD。归并 PR 为 #11。删除分支前逐条检查 tip 已被 main 包含；本机另有 `build/branch-consolidation/before-cleanup.bundle` 和 refs-before.txt 可恢复，bundle verify 退出 0。

最新起点 CI run 39927750097 的 iOS build 退出 65：CoachView.swift 的过长 body 修饰器表达式在 Xcode 26.5 无法完成类型推断；Backend tests 通过。本机只有 Xcode 27，不能据本机通过声称 26.5 兼容。修复 `a5e1f6e7` 将原视图链分为 conversationContent、conversationLifecycle、conversationSessions、body 四个 opaque return type 边界，不改变修饰器顺序、状态所有权或业务行为。26.5 的最终判定以 PR 的 GitHub Actions 为准。

本地验证（Xcode 27，iPhone 17 / iOS 26.5 模拟器）：

- `xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/UIOnboardingDerivedData CODE_SIGNING_ALLOWED=NO build`：退出 0。
- `swift test --package-path BodySeekDomain`：退出 0，41 项通过。
- `python3 scripts/schema_fingerprint.py --check`：退出 0，live/frozen V3 均 32 个模型。
- `python3 scripts/check_contrast.py`：退出 0，保留既有非文本调色板 informational warnings。
- `git diff --check`：退出 0。
- `xcodebuild ... -destination 'platform=iOS Simulator,id=80FFA19E-69E6-499F-B246-F071A2D369BF' -parallel-testing-enabled NO -derivedDataPath build/UIOnboardingDerivedData -resultBundlePath build/branch-consolidation/CoachUI.xcresult -only-testing:VelaUITests/VelaSmokeUITests/testDataRepairLayoutsAndLegacyProtocolRecovery -only-testing:VelaUITests/VelaSmokeUITests/testAskBarOffersExplicitSendAndStaysOnCurrentPage -testLanguage zh -testRegion CN CODE_SIGNING_ALLOWED=NO test`：退出 0，两项通过，覆盖旧协议失败展示与恢复草稿、页内发送及对话恢复。

本轮只归并版本与修复编译阻塞，没有部署真机或触发真实健康数据补算。分支清理不是新的完整设备验收，既有产品验证边界继续适用；最新完整 CI 状态及最终合并身份记录在 PR #11。


后续 CI run 39928961539 已通过 Xcode 26.5 的完整 App 构建及后端测试，但测试 target 编译发现旧截图 walkthrough 的同步 setUpWithError 在该工具链中是 nonisolated，不能设置 @MainActor 的 outputDirectory。将这段仅用于 opt-in 截图的目录初始化移到其 @MainActor 测试方法开头，保留环境变量缺失时的 XCTSkip；不更改 App 生产代码或跳过标准 smoke 测试。下一轮 CI 验证该兼容修复。


同步期间远端 Cursor 提交 `a220e130` 也处理 walkthrough 问题，已正常 merge 保留历史；最终目录仍限定主线程，不需要 nonisolated(unsafe)。本机完整 673 项 App 测试初轮有 1 项旧断言失败：TodayExperienceModel 在既有 `236f236b` 已将趋势从 7 个读数扩为 14 个，测试仍期待 7。核对原提交后将测试更名为 IncludesFourteenSignalValues，使用 20 条历史并断言只保留最近 13 条加当天值，其他四项当天读数断言保留；生产窗口不变。
