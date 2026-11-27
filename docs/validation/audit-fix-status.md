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


`FullAppFixed.xcresult` 已通过本机全部 673 项 App 测试（退出 0）。完整 UI 初轮进一步发现既有 smoke 仍寻找第四个 Coach Tab、已隐藏的系统导航栏标题/返回按钮，而生产版本已改为三段顶部导航、页内 Coach 和自定义详情导航。初步查询适配后，再用初轮失败的原生 AX 附件核对实际入口（见下）。没有为匹配旧测试恢复过时导航，也未修改生产页面。完整 UI 结果以 PR 最新检查为准。


初轮完整 UI 运行退出 65，共 24 项（含 opt-in walkthrough 跳过 1 项），11 项旧查询失败。已导出原生附件到 build/branch-consolidation/initial-ui-attachments。AX 明确显示：Today 的 instrument 仍是 push，按钮标签为「返回」；深链详情是 sheet，标签「关闭」；顶层 metric-detail 标识传播到直接子元素，使旧 close identifier 查询不可用。测试改为操作真实「返回」/「关闭」按钮，保留 push/深链 sheet 两种路径的关闭行为断言，并将标题查询改为自定义标题 Text。首页依据改为点击真实 today-advice-evidence 按钮；Coach 截图改查 inline-coach-panel 和 coach-surface-header。未改生产导航、布局或弱化为只查底层首页 exists。


UI 查询第二轮还确认两个既有标识变化：Strain 当前标题是「负荷」，不再是「耗力」；页内 Coach 的直接子标识被 inline-coach-panel 覆盖。保留 panel 存在断言，并用实际「收起对话」按钮检查 Coach 已可交互。以上仍只修正测试查询，不改生产界面。


## 2026-10-24 · Visual Body full-app residual（Design D）

替代中途失败且未推分支/PR 的 Cursor cloud agent `bc-529d55a7` 那轮，按同一 visual-only 范围重做。起点为最新 `origin/main` / 本地 HEAD `dddf4b31a1876e18648ef21bb4e24c2e6d741202`（已含 #12–#17），开始时 working tree 干净；推送前再次 fetch，main 未变化。实现提交 `1b0ed1bfc2f9953781f6f5935468ef81ef674b4b`；下列最终验证和截图来自提交前同内容的 dirty working tree，提交后没有再改 Swift 源码。分支 `cursor/visual-body-full-app-residual-20261024`，仅创建 draft PR，不 merge / ready / request review。

### 改动边界

- Stroke hygiene：旧 `0.5/0.75/0.8pt` 容器描边统一到现有 `VelaTheme.hairline` / `hairlineWidth`；数据图轴线、基线、曲线保留各自语义线宽。
- Today：仅去掉宿主残留的硬编码紫色渐变描边、Lived State / vitals 渐变边框和天气装饰色；不重排 #17 的 Agent brief、五分条、chips 或下一步。
- Metric detail：Sleep / Strain 细纯色环、Stress mono dial、详情卡片与 Sheet hairline；Recovery editorial 字阶回到现有语义 token。大字体下隐藏重复事实图标和详情 AskBar 上的重复 context pill，保留完整文字、上下文和按钮动作；修正关闭图标随字号过度放大。日历读数环改 mono 细线，读数计算不变。
- Onboarding：CTA 已是 ink，不重新引入配色；收口 solid canvas、卡片半径和 hairline，预览环收细，CTA 高度可随文本增长，次级动作保留 44pt 点击区域。
- Journal / Sheets：分类 badge、实验入口、日历选中态使用 mono 且匹配 `rhythmDeepOn`；记录面板、详情与证据 Sheet 收口描边。
- Training：Workout / Strength / Fitness 详情和统计子页的装饰色、glow、渐变 stroke 改 mono，字号转既有 caption token；保留真实心率区间与错误/安全颜色语义。Plan 二级训练计划头部只移除 ambient glow。
- Coach：只改视觉 chrome，包括档案完整度条、自动报告图标、恢复动作与输入边框、通用分析卡和 Quick Actions；legacy `AppleIntelligenceOrb` 压为静态 mono mark。
- 共 40 个生产 Swift 文件 + 1 个现有 UI test harness 文件；[完整清单](rhythm-horizon/visual-body-residual-2026-10-24/changed-files.txt)。没有更改 `VelaTheme` 的颜色/token 定义，也没有新增 palette。

刻意跳过：评分公式、阈值与数据投影、Store / schema、导航和信息架构、Watch / WidgetKit 实际视图、对话历史、Coach 文案、#17 已正确的主表面布局、AskBar 麦克风与听写发送行为。共享组件改动不改业务动作；未新增生产调试入口或功能。

### 验证与证据

工具链 Xcode 27.1 (`27A9275`)，与仓库锁定的 `.xcode-version` 26.5.0 不同，没有修改 CI 配置或声称固定工具链验证通过。最终设备 iPhone SE (3rd generation)，375pt 宽 / 750×1334px，iOS 26.5 (`23F77`)，arm64 Simulator；中文。所有截图是运行中的 SwiftUI，使用既有 preview dashboard / 空手记 fixture，不含个人健康导出。

```sh
xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug \
  -destination 'platform=iOS Simulator,id=66EFE656-F33C-483B-B8D2-06C9CA85533A' \
  -derivedDataPath build/VisualResidualDerivedData \
  -resultBundlePath build/VisualResidual-verified-SE-20261024.xcresult \
  -only-testing:VelaTests/VelaThemeTests \
  -only-testing:VelaUITests/VelaSmokeUITests/testVisualResidualSnapshots \
  -only-testing:VelaUITests/VelaSmokeUITests/testThreePrimarySurfacesAndInlineCoachAreReachable \
  -only-testing:VelaUITests/VelaSmokeUITests/testSleepDetailPushNavigationAndReturn \
  CODE_SIGNING_ALLOWED=NO test
python3 scripts/check_fixed_fonts.py --strict
bash scripts/audit_design_tokens.sh
git diff --check
```

以上命令退出码均为 0。最终 build + 152 项测试通过（149 项现有 `VelaThemeTests`，3 项 UI tests），0 failures、0 skips；[test summary](rhythm-horizon/visual-body-residual-2026-10-24/test-summary.json)。较早的 iPhone 18 Pro / iOS 27.0 迭代也通过 152 项，但其截图发现大字体重叠，已修复并以上述 SE 最终复验为准。首轮 7 个详情/导航 UI 路由与 149 项测试共 156 项通过；不把早期结果替代最终源码验收。

固定字号 strict 检查为 183 处，低于既有阈值 216；全仓 token report-only 仍报告 596 处，包括既有图标字号和内联圆角，未声称全仓无硬编码。[字体报告](rhythm-horizon/visual-body-residual-2026-10-24/fixed-font-audit.txt)、[token 报告](rhythm-horizon/visual-body-residual-2026-10-24/design-token-audit.txt)。新增 diff 没有硬编码颜色。

[截图与输入上下文](rhythm-horizon/visual-body-residual-2026-10-24/capture-context.json)：五项详情 Dark / 默认字号、三步 Onboarding Dark、Quick Actions / Journal Dark、Sleep Light / AccessibilityXXXL（首屏及滚动后），共 12 张，已逐张检查。大字体可滚动阅读；重复图标不再压住事实文字，详情 context pill 不再截断。

| 样本 | 截图 |
| --- | --- |
| Sleep mono 详情 | [Dark](rhythm-horizon/visual-body-residual-2026-10-24/residual-sleep-dark.png) |
| Stress mono dial | [Dark](rhythm-horizon/visual-body-residual-2026-10-24/residual-stress-dark.png) |
| Onboarding CTA / 预览环 | [Dark](rhythm-horizon/visual-body-residual-2026-10-24/residual-onboarding-body-dark.png) |
| Journal | [Dark](rhythm-horizon/visual-body-residual-2026-10-24/residual-journal-dark.png) |
| AccessibilityXXXL | [首屏](rhythm-horizon/visual-body-residual-2026-10-24/residual-sleep-light-accessibility.png) / [滚动后](rhythm-horizon/visual-body-residual-2026-10-24/residual-sleep-light-accessibility-scrolled.png) |

未验证：真实 HealthKit / 长训练历史和真实训练路线、所有二级 Settings / Coach artifact 状态的逐屏截图、完整 Light/Dark × 字号 × 缺失/零/排除矩阵、iOS 17 真机、VoiceOver 手工操作和 Reduce Motion 手工矩阵。训练与 Settings 子页有编译和静态 diff 验证，不将这 12 张截图解释为全应用所有状态的视觉认证。未做真机部署、发布或 merge。

## 2026-10-24 · Visual Body next wave（Design D，接 #18）

起点：fetch 后最新 `origin/main` / 本地 HEAD `f2b83b9cac059f775ad7614b3124fe2051d05cfc`（#18 squash），起始 `git status --short` 为空。分支 `cursor/visual-body-next-wave-20261024`，任务 [#19](https://github.com/SunWeizhou/bodyseek/issues/19)。先落盘[残留文件清单](rhythm-horizon/visual-body-next-wave-2026-10-24/residual-inventory.md)，再修改。实现提交 `c8893a11`；最终源码与截图 harness 见 `e6e5d2ba`。本波只创建 draft PR，不 merge / ready / request review，不真机部署或发布。

### 变更与合同边界

- **Token / contrast**：视图内白/黑/shorthand 彩色改用语义 VelaTheme tokens；scrim 收进 token，透明度不变；卡片统一 `hairline` / `hairlineWidth`。修正 `fillSoft` 的 RGBA/ARGB 字节顺序错误：Dark 训练建议此前显示为不透明亮黄，现在为低透明度中性色。没有修改 hex helper 或其它调色板规则。[修复前截图](rhythm-horizon/visual-body-next-wave-2026-10-24/before-soft-fill-dark.png)来自实施中的首轮 SwiftUI 托管截图，尚未修 token；不将其称为精确 main 页面截图。新回归在未修改 main 生产代码上失败（exit 65），修复后通过：[red 证据](rhythm-horizon/visual-body-next-wave-2026-10-24/fill-soft-red-on-main.txt)。
- **Settings**：Account 保存 CTA / 大字体表单 reflow、模型配置保存 CTA、健康授权/同步按钮、CGM 单序列/卡片、Coach personality、Trust / Biology / Privacy 的面板与对比收口。文案、字段、Keychain/授权/导出动作不变。
- **Coach 次态**：报告 / artifact 列表和详情的装饰 indigo/orange 改 mono；档案保存、输入边框、相关图卡片对齐 hairline；大字体 pills 和空态标题允许换行。没有改消息、工具路由或历史列表。
- **Training / Plan 二级**：Strength 的蓝色 tile / 金色奖杯 / warmup / 完成态装饰色收为 mono，修复白色指标面板与组号对比；GPS marker 去阴影、边框用 token；Plan 二级完成标记与面板边框一致。训练事实、组类型、推荐策略不变。
- **Sheets / AccessibilityXXXL**：Evidence 面板；Weight CTA 可增长，AccessibilityXXXL 单独采用 graphical 日期布局，修复 compact 日期控件撑宽视口；Quick Actions 大字体改为可滚动的两列，默认三列保持；Recovery 样本 badge、依据列、缺失天数说明纵向 reflow，图高按字号扩展。没有更改 Recovery model、分数、统计或说明字符串。

生产改动均在 View / DesignSystem / Theme；[文件清单](rhythm-horizon/visual-body-next-wave-2026-10-24/changed-files.txt)。没有评分公式、阈值、输入语义、schema、HealthKit、Store、数据投影、算法版本或 IA/导航变更。Today 五分横条、Speak pill、chips、顶部分段、AskBar mic、主表面布局保留。

### 静态审计与保留项

`python3 scripts/check_fixed_fonts.py --strict`、`bash scripts/audit_design_tokens.sh`、`git diff --check` 均 exit 0。固定字号 **183 → 180 / 216**，其余主要是 SF Symbols、显示几何、wordmark 与本轮跳过的 Widget 文本。[before](rhythm-horizon/visual-body-next-wave-2026-10-24/fixed-font-before.txt) / [after](rhythm-horizon/visual-body-next-wave-2026-10-24/fixed-font-after.txt)。旧 token report 为 **596 → 601**：它将所有内联 RoundedRectangle（包括消费 token 的圆角/新增 hairline overlay）计入报告；不是新增 5 个颜色违规，也不是全仓零硬编码认证。[before](rhythm-horizon/visual-body-next-wave-2026-10-24/design-token-before.txt) / [after](rhythm-horizon/visual-body-next-wave-2026-10-24/design-token-after.txt)。

扩大后的[直接色常量复核](rhythm-horizon/visual-body-next-wave-2026-10-24/ui-color-review.txt)为 **37 → 5**；剩余 5 处在 `VelaMetricDetailWidgets.swift` 的 Widget 预览段，本轮按范围跳过。保留心率区间 / 心率序列、地图起终点、睡眠阶段、错误 / 破坏性操作、数据覆盖 / 新鲜度等语义色。线图、路线、进度环是数据 mark，未机械改为面板宽度。`appleIntelligenceGlow` 在起点已是 no-op；剩余调用名不等于渲染 glow。灰阶 loading shimmer 与图表 area fill 也不是渐变描边。

### 验证命令、退出码与环境

Xcode **27.1 / 27A9275**，与仓库 `.xcode-version` **26.5.0** 不同；未改 CI 配置，未声称固定工具链 CI 通过。设备 iPhone SE (3rd generation)，375pt / 750×1334px，iOS **26.5 / 23F77**，arm64 Simulator；中文，Dark 默认字号 / Light 与 Dark AccessibilityXXXL。截图输入为现有 preview dashboard、空/本地生成的模拟器记录，以及 isolated in-memory fixture，不是个人 HealthKit 数据导出或临床有效性证据。

```sh
# 基线：exit 0
xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/VisualResidualDerivedData CODE_SIGNING_ALLOWED=NO build

# 最终源码复验：使用此前 test 构建的产物，exit 0
xcodebuild test-without-building -project Vela.xcodeproj -scheme Vela -configuration Debug \
  -destination 'platform=iOS Simulator,id=66EFE656-F33C-483B-B8D2-06C9CA85533A' \
  -derivedDataPath build/VisualResidualDerivedData \
  -resultBundlePath build/VisualNext-final-source-20261024.xcresult \
  -parallel-testing-enabled NO -only-testing:VelaTests/VelaThemeTests \
  -only-testing:VelaUITests/VelaSmokeUITests/testThreePrimarySurfacesAndInlineCoachAreReachable \
  -only-testing:VelaUITests/VelaSmokeUITests/testVisualNextWavePlanEditorSnapshots \
  CODE_SIGNING_ALLOWED=NO

# 最终 UI 复跑：exit 0
xcodebuild -project Vela.xcodeproj -scheme Vela -configuration Debug \
  -destination 'platform=iOS Simulator,id=66EFE656-F33C-483B-B8D2-06C9CA85533A' \
  -derivedDataPath build/VisualResidualDerivedData \
  -resultBundlePath build/VisualNext-final-ui-20261024.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:VelaUITests/VelaSmokeUITests/testDraftSurvivesExpandedChatAndCancelledConsent \
  -only-testing:VelaUITests/VelaSmokeUITests/testVisualNextWaveSettingsSnapshots \
  -only-testing:VelaUITests/VelaSmokeUITests/testVisualNextWaveAccessibilitySnapshots \
  -only-testing:VelaUITests/VelaSmokeUITests/testVisualNextWaveSheetsAndCoachSnapshots \
  CODE_SIGNING_ALLOWED=NO test
python3 scripts/check_fixed_fonts.py --strict
bash scripts/audit_design_tokens.sh
git diff --check
```

最终去重覆盖 **151 项 VelaThemeTests + 6 项 UI tests = 157 项**，在修正 harness 并复跑后全部通过，0 skips；不是声称中间所有运行均通过。

- 最终源码 `e6e5d2ba` 的 test-without-building：**153 passed / 0 failed**（151 单元/托管截图 + 三主表面/Coach + Plan editor），exit 0：[summary](rhythm-horizon/visual-body-next-wave-2026-10-24/final-source-summary.json)。
- 修正选择器后的四项 UI 复跑：**4 passed / 0 failed**，exit 0：[summary](rhythm-horizon/visual-body-next-wave-2026-10-24/final-ui-summary.json)。
- 之后 Weight 日期布局修复：同一设备/derivedData，结果路径 `build/VisualNext-weight-accessibility-20261024.xcresult`，只跑 `-only-testing:VelaUITests/VelaSmokeUITests/testVisualNextWaveSheetsAndCoachSnapshots`，其余参数与 UI 命令一致：**1 passed / 0 failed**，exit 0；包含视口边界断言及新的滚动截图。[summary](rhythm-horizon/visual-body-next-wave-2026-10-24/final-weight-summary.json)。最后的 153 项源码复验使用该构建产物。
- 首次完整截图矩阵为 157 项、3 个 harness failures（发送同名 / LazyVStack 未 materialize / NavigationLink 选择器），exit 65；[中间 summary](rhythm-horizon/visual-body-next-wave-2026-10-24/source-validation-summary.json)保留为失败记录，不用于替代最终结果。托管 Model CTA 的 Form 估算高度也通过重复布局/滚动到末尾后重拍。

[迭代命令与退出码索引](rhythm-horizon/visual-body-next-wave-2026-10-24/validation-runs.json)。

迭代中的失败如实保留：首次 AnyLayout 条件分支编译失败（65）已修正类型擦除；早期 preview Plan 的只读路径不能作为 editor 证据，改用空模拟器本地计划并只打开/取消；XCTest 的“发送”同名键盘按钮、offscreen LazyVStack row、NavigationLink 的 Button/StaticText 选择器已修正并复跑。首次基线对照 runner 启动遇到 Mach -308（65），之后串行对照可复现模型入口卡顿，非视觉测试通过的替代品。

**基线未解决问题**：Settings → 联网 Agent 在该 Xcode 27.1 / iOS 26.5 环境出现持续 SwiftUI 更新、停留在 Settings。未修改的 #18 生产源码、同一 UI harness 的独立 worktree 也复现；等待约 100 秒后中止（75），未称为通过。[观察日志](rhythm-horizon/visual-body-next-wave-2026-10-24/baseline-navigation-observation.txt)。模型页改用真实 UIHostingController 托管生产 View 采集首屏 / 保存 CTA / 大字体证据；这证明页面渲染，不证明该导航入口已恢复。未改导航以绕过问题。

### 截图与验收范围

[41 张最终截图与逐张上下文](rhythm-horizon/visual-body-next-wave-2026-10-24/capture-context.json)，另有 1 张实施中 token 修复前图，已逐张目视检查。32 张是运行 App 的 XCUITest screen capture；9 张是 production SwiftUI 的 UIHostingController 托管截图。托管样例：1 个内存报告、1 个 artifact、2 组力量训练；页面内容明确标注为视觉验收样例。字体/日期样式仅作可读性验证。

| 表面 | 证据 |
| --- | --- |
| Account CTA / 大字体 | [Dark](rhythm-horizon/visual-body-next-wave-2026-10-24/next-account-dark-scrolled.png) / [AccessibilityXXXL](rhythm-horizon/visual-body-next-wave-2026-10-24/next-account-accessibility-scrolled.png) |
| Model Settings（hosted） | [Dark 保存 CTA](rhythm-horizon/visual-body-next-wave-2026-10-24/next-hosted-model-settings-cta.png) / [大字体](rhythm-horizon/visual-body-next-wave-2026-10-24/next-hosted-model-settings-accessibility.png) |
| Settings 子页 | [Sources](rhythm-horizon/visual-body-next-wave-2026-10-24/next-sources-dark-scrolled.png) / [CGM](rhythm-horizon/visual-body-next-wave-2026-10-24/next-cgm-dark.png) / [Personality](rhythm-horizon/visual-body-next-wave-2026-10-24/next-personality-dark.png) / [Trust](rhythm-horizon/visual-body-next-wave-2026-10-24/next-trust-dark.png) |
| Coach 次态 | [完整 workspace](rhythm-horizon/visual-body-next-wave-2026-10-24/next-coach-full-dark.png) / [报告与 artifact（hosted）](rhythm-horizon/visual-body-next-wave-2026-10-24/next-hosted-reports-populated.png) / [详情（hosted）](rhythm-horizon/visual-body-next-wave-2026-10-24/next-hosted-artifact-populated.png) |
| Training / Plan | [Strength detail（hosted）](rhythm-horizon/visual-body-next-wave-2026-10-24/next-hosted-strength-detail.png) / [Strength editor（hosted）](rhythm-horizon/visual-body-next-wave-2026-10-24/next-hosted-strength-edit.png) / [Workout（hosted）](rhythm-horizon/visual-body-next-wave-2026-10-24/next-hosted-workout-detail.png) / [Plan editor](rhythm-horizon/visual-body-next-wave-2026-10-24/next-plan-editor-dark.png) |
| Sheets | [Evidence](rhythm-horizon/visual-body-next-wave-2026-10-24/next-evidence-dark.png) / [Quick Actions 大字体](rhythm-horizon/visual-body-next-wave-2026-10-24/next-quick-actions-accessibility.png) / [Weight 大字体](rhythm-horizon/visual-body-next-wave-2026-10-24/next-weight-accessibility.png) / [日期与 CTA](rhythm-horizon/visual-body-next-wave-2026-10-24/next-weight-accessibility-scrolled.png) |
| Detail 大字体 | [Recovery 依据](rhythm-horizon/visual-body-next-wave-2026-10-24/next-recovery-accessibility-observations.png) / [Strain](rhythm-horizon/visual-body-next-wave-2026-10-24/next-strain-accessibility.png) / [Stress](rhythm-horizon/visual-body-next-wave-2026-10-24/next-stress-accessibility.png) / [Energy](rhythm-horizon/visual-body-next-wave-2026-10-24/next-energy-accessibility.png) |

CGM / Trust 在无 HealthKit entitlement 的模拟器中如实显示读取失败，未填入假数据绕过。Quick Actions 大字体可滚动；Weight TextField 的 frame 已断言位于视口内，日期和保存动作可通过纵向滚动访问。Recovery 依据不再被固定三列挤成拆字/截断。主表面背景在大字体 sheet 下可能只显示部分文字，不把这些截图当成完整 Today 大字体认证。

未验证：真实 HealthKit / GPS 路线与长训练历史、所有 Settings 子页与所有 artifact payload 的完整逐屏矩阵、全 Light/Dark × 字号 × known zero/unknown/excluded 组合、iOS 17 真机、VoiceOver 与 Reduce Motion 手工矩阵、完整远端固定工具链 CI。Watch / WidgetKit 视图与产品逻辑、对话历史列表明确跳过。没有把模拟/托管截图解释为评分有效性或端到端数据链验证。


## 2026-10-25 · iPhone 镜像实机视觉问题清单

用户要求记录主表面问题并继续检查二级页。本轮为只读实机审查，问题清单是待修 backlog，不表示已修复。起点 clean HEAD `53d173c3ab69aef9d5ec798a77e4e257cbb58c79`（wave25）；手机安装 BodySeek 4.0.0，未核对到设备 Git SHA，画面与 wave25 布局吻合。实测入口：iPhone 镜像；当前浅色外观。个人健康及训练截图不进入公共仓库，表格只记录布局/交互现象。

### 已确认的主表面问题

| ID | 优先级 | 页面与复现 | 实测现象 / 源码证据 | 建议验收 |
| --- | --- | --- | --- | --- |
| VB-01 | P1 | Today，今日五分未同步 | 状态提示卡被顶栏遮住；署名前出现明显空间断层。`VelaMinimalTodayView.swift:408` 固定 `padding(.top, 72)` 解释部分留白；顶栏遮挡的 safe-area 根因待定位。 | 顶部提示完整可见，按统一 section spacing 接到正文；小屏/大字均无覆盖。 |
| VB-02 | P1 | Today，五分均缺失 | 恢复 `--` 仍独占 Hero，其余四项为 support strip。`TodaySignalGrid.primaryReadingID` 的无数据分支默认 first/recovery。 | 空态使用五项一致的紧凑读数，不放大没有数据的主仪表；不改变分数语义。 |
| VB-03 | P2 | 三主表面，AskBar 空闲无草稿 | 空闲也常驻两行输入+按钮，挤压正文。`VelaMinimalShell` 的 `isCompact` 只影响 TextField 行数，两排仍同时挂载。 | 空闲与编辑状态分别实机验收，压缩空闲高度且保留麦克风、上下文、44pt 点击区域。 |
| VB-04 | P2 | Trends，历史稀疏 / 今日缺失 | 5 张灰色卡片配零散点和短线，时间关系不清；小结、覆盖说明、空读数共同占据首屏。 | 统一列对齐和时间参照，保留缺口；不得连接缺失日或补假数据来美化曲线。 |
| VB-05 | P2 | Plan，已保存安排 | 决定/主标题/第一条行动重复；空心完成圈、badge 和菜单偏重。 | 字阶职责明确；缩小可见图形但保留点击区域；用户安排及确认行为不变。 |
| VB-06 | P2 | Plan→训练、Settings | 大标题、品牌导语/装饰、卡片及胶囊尺度与 Today 不一致；Settings 控制项被导语推后。 | 统一页面字阶和 section 节奏，控制页优先呈现可操作内容。 |
| VB-07 | P1 / 另核语义 | Today 未同步→Plan 已保存安排 | 未同步、不必改计划、已保存减量安排同时出现，界面未讲清今日证据不足与沿用计划的关系。不据此推断评分错误。 | 先核对显示合同并明确标识来源/时效；不可借视觉任务改评分或覆盖用户计划。 |

### 二级页面问题（只记录，待修）

| ID | 优先级 | 页面与复现 | 观察 / 源码对应 | 建议验收 |
| --- | --- | --- | --- | --- |
| VB-08 | P2 | 睡眠 / 负荷 / 压力 / 能量详情，今日缺失 | 大虚线环/空仪表、事实 `--`、指导、解读三格、后续证据卡反复表达暂无数据；空态仍占用完整仪表版式。 | 单一主空态说明，折叠重复证据容器，保留历史及已知事实入口。 |
| VB-09 | P1 | Trends→睡眠→下滚到时间轴明细 | 上方“实际睡眠 --”、时间轴暂无记录，下方却显示“睡眠时长 0 分钟”。`SleepTimelineCard.stageBreakdownSection` 无分期分支直接插入 `summary.totalSleepMinutes`（当前源码 1589 行），未复用上方缺失判断。 | 区分 unknown / known zero / 无分期但有总睡眠；各行与无障碍摘要一致，不改评分。 |
| VB-10 | P1 | Trends→能量，今日无数据 | 早间储备和当前剩余均为 `--`，能量变化标题显示 `0 → --`。`MetricCustomWidgetsSection`（492 行）直接格式化非可选 morningEnergy；`energyReserveComparison` 则按 hasData 处理。 | 标题、对比条、事实栏按同一缺失状态展示；known zero 仍可显示 0。 |
| VB-11 | P2 | Trends→负荷→空态心率区间卡 | 同一列的时间线卡全宽，心率区间空态卡明显窄于同级卡片，右边缘不齐。 | 同级容器边界与 padding 一致；窄屏/长文案也对齐。 |
| VB-12 | P2 | AskBar + →记录面板 | 六个图标集中在上方，下面大片留白，取消按钮独立沉底；占用空间与操作数量不匹配。 | 使用与 6 个操作匹配的 sheet 高度与分组；取消和关闭语义一致。 |
| VB-13 | P2 | 记录面板→手记 | 日历 + 两张引导大卡把“今天的条目”推到下方；实际记录比实验/宣传入口弱。 | 记录页首屏以条目与新增为主，引导不持续抢占主要空间。 |
| VB-14 | P2 | 手记→随手记，半屏 Sheet | 说明卡和嵌套输入卡占据大部分可见区域；保存动作在当前半屏下方。编辑框已聚焦；镜像使用硬件键盘，未验证软键盘遮挡。 | 首屏清楚呈现输入与保存；验证半屏/全屏/软键盘/大字状态。 |
| VB-15 | P2 / 文案 | 随手记说明与底部辅助文案 | 直接呈现 Body Model、低摩擦信号、进入 AI 上下文等实现术语；同一标题重复。 | 用户能直接理解记录用途，不需要了解内部架构；术语变更单独审查。 |
| VB-16 | P1 候选 / 待隔离 | 手记→随手记→点击空白编辑框→关闭 | 镜像中多次点击“关闭”后仍停留原表单；未输入或保存内容。Esc 和镜像滚动退出也未成功，用户手动退出重开后恢复首页。`BehaviorQuickNoteSheet` cancellation toolbar 调用环境 dismiss；根因未确定，不将镜像现象直接断言为全部设备故障。 | 在真实触摸与 UI 自动化中分别复现，验证编辑前/后关闭、嵌套 Sheet 的 dismiss 作用域及手势取消。 |

### 设置子页新增问题

| ID | 优先级 | 页面与复现 | 观察 / 源码对应 | 建议验收 |
| --- | --- | --- | --- | --- |
| VB-17 | P1 | Settings→基本资料，有已填值 | 年龄、体重、身高字段名消失，只剩数值、单位、来源徽章，左侧大面积留白。`AccountSettingsView` 将字段名仅作为 TextField placeholder，没有独立可见 label。 | 已填/空白/自动/手动状态都有稳定可见字段名，保留单位与来源；不修改个人值。 |
| VB-18 | P2 | Settings→健康档案→打开一项 | 列表直接展示 .md 文件名和 Markdown 源符号/英文模板；点击直接进入编辑，表单模式仍显示源码型备注与更新标题，正常阅读负担大。列表模板摘要与进入后的内容观感也不一致，内容一致性需另核。 | 阅读摘要面向用户；源码入口保留在明确位置；区分内容、模板和更新元数据；不改写既有记忆。 |
| VB-19 | P2 | Settings→沟通方式 | 当前设备上“健康守护”的图标呈现为实心黑圆，其他选项能辨识图形。源码 systemImage 为 shield.heart.fill；尚未确认是符号可用性还是渲染问题。 | 符号在 shipping OS 上可见，必要时有回退；验证默认/选中/深浅色。 |
| VB-20 | P2 | Settings→主动智能，开关均关闭 | 入口状态仍固定显示“已配置”。`VelaSettingsView` 直接传入静态 value，而非实际启用状态。页内 Wiki / Check-ins 等术语也与上一级命名不一致。 | 状态反映配置/启用/授权的区别；名称在入口与子页一致；不更改实际开关。 |
| VB-21 | P2 / 状态表达 | Settings→数据来源 | 页面标题“已同步健康传感器”，唯一来源卡却为绿色“待同步”且显示无可用数据；3 个授权按钮都以同等黑色主 CTA 呈现。`DataSourceSettingsView` 的状态标题与着色为固定表达。 | 将连接、授权、已读到样本与已完成计算区分；等待状态不伪装成功；CTA 主次明确。 |
| VB-22 | P1 / 另核数据合同 | Today / 指标详情→Settings→数据覆盖 / 信任中心 | 前者仍未同步/无读数，数据覆盖却显示多项信号可分析、部分分组满覆盖，审计有近期健康管道成功记录。仅记录跨页矛盾，不据此判定算法错；可能涉及实时 HealthKit、缓存快照、窗口、刷新等不同来源。 | 同日/同源/同窗口回放，标明样本覆盖与可计算评分的区别、刷新时间和来源；覆盖不能代替分数。 |
| VB-23 | P2 | Settings→数据覆盖 / 信任中心 | 导航标题与页面标题重复；覆盖首屏 8pt 粗环、数字、比例、badge重复编码；信任中心外卡包内卡再加多个 pill，容器层级重。 | 复用全应用字号/线宽/间距；信息只在必要层级重复；保留所有授权/审计含义。 |
| VB-24 | P3 | 信任中心→Agent 活动 | 中文界面里审计日期采用英文月份/at 格式，和其他中文时间不一致。源码使用 startedAt.formatted(date:time:)。 | 跟随应用语言，时间与时区解释一致。 |
| VB-25 | P2 | 信任中心→联网 Agent→AI 模型设置 | 入口名称与页标题不同；密钥、模型、数据流长说明、逐类授权纵向堆叠，授权控制被说明推到更下方；密钥以很长的掩码串占据整行。实际导航可用、密钥默认掩码正常，未测试连接或改配置。 | 不改权限的前提下，明确配置状态、说明、控制的层次；优先展示用户需要判断的状态。 |

### 训练导航新增问题

| ID | 优先级 | 页面与复现 | 观察 / 源码对应 | 建议验收 |
| --- | --- | --- | --- | --- |
| VB-26 | P1 / 导航可理解性 | Plan→训练→Today→再切回 Plan | 保留训练二级页，但顶上仍为三段主导航，页面没有可见的返回计划入口；用户难以理解当前位于 Plan 内部。`VelaTrainingView`（VelaMinimalFitnessView.swift:284）隐藏系统 navigationBar；Shell 有意保留各 surface 的 NavigationStack。 | 保留现有导航结构与返回状态，同时给二级页清楚的返回/位置提示；验证主表面切换与手势返回。 |

### 本轮实测覆盖与边界

| 页面 / 路径 | 已检查内容 | 结果边界 |
| --- | --- | --- |
| Today / Trends / Plan / 训练落地 | 首屏比例、空态、主表面切换、导航位置 | 主表面问题见 VB-01～07；训练位置见 VB-26。 |
| 恢复详情 | 上一轮本日镜像已检查缺失读数与历史布局 | 本轮没有重新测试所有恢复子状态。 |
| 睡眠详情 / 关于睡眠 | 上部仪表、滚动至时间轴/统计、更多菜单、说明弹窗 | 菜单和说明可打开关闭；睡眠 0 与 -- 的矛盾已实测。 |
| 负荷 / 压力 / 能量详情 | 缺失状态、主卡、解释卡、计算证据 | 能量 0→-- 与卡片宽度问题已实测；未验证所有有数据状态。 |
| Trends→有评分的天数 | medium sheet 的说明、分项覆盖与滚动 | 正常打开关闭；没有完成所有底部修复入口测试。 |
| + 记录面板 / Journal | 入口密度、日历、引导卡、实际条目区 | 未切换或保存任何习惯状态。 |
| Journal→随手记 | 空白表单、文本编辑聚焦、关闭按钮、手势/键盘取消尝试 | 未输入/保存内容；关闭问题为镜像复现。用户随后手动退出重开并确认回到首页。镜像为硬件输入环境，软键盘矩阵未验证。 |
| Settings→基本资料 | 已填写表单标签、来源与 CTA | 没有改动字段、选择性别或保存。报告不复制个人数值。 |
| Settings→健康档案→一项编辑 | 列表、文件名、摘要、表单/源码暴露、取消 | 编辑页取消成功；没有保存、更改或复制私人档案正文。 |
| Settings→沟通方式 / 主动智能 | 图标、选中状态、开关状态、命名与说明 | 未更改选项、开关、时间或创建提醒。 |
| Settings→数据来源 / 数据覆盖 | 连接与覆盖说明、分组、样本状态、可见图形尺度 | 未点击授权、同步或回填按钮；未将原始样本覆盖认作评分覆盖。 |
| Settings→信任中心→联网 Agent | 层级、审计状态、日期、模型配置、掩码、授权区滚动 | 导航可用，密钥默认掩码；未测试连接、发送消息、更改密钥或授权。 |
| 训练记录 / 动作 / 组详情 | 仅定位到训练记录入口并定向阅读源码 | 尝试点击时镜像工具连续返回 noWindowsAvailable；重新绑定 App、Raise 窗口后仍不可点击。没有进入详情，不标成已实测；列为下一批待补。 |

本轮最终仅修改这份验证报告，未提交/推送、部署或修改生产 Swift。原始实机截图可能含私人健康/训练/授权信息，未加入仓库。本轮没有主动发送 Coach 请求、运行连接测试、保存新记录、执行删除/导出或修改手机授权设置。打开页面触发的既有后台刷新/审计不等于本轮验证了数据管线正确性。

### 后续顺序

1. 先隔离 P1 展示/交互问题：VB-01、09、10、16、17、22、26；VB-07 单独审查显示合同。不把 unknown 与 zero 的修复混入评分公式变更。
2. 再做完整视觉重排：主表面与详情共用字阶/间距/空态规范，减少灰卡嵌套与重复徽章；明确表单标签和 CTA 层次。
3. 恢复镜像交互后补查训练记录、动作/组详情，以及咖啡因/补水/心情、个人实验、隐私/导出、回填、通知/外观等尚未实测子页。
4. 复验真实设备的未同步、部分缺失、known zero、正常有值，配合 Light/Dark、大字体与软键盘；布局通过与数据语义通过分开记录。


## 2026-10-25 · 实机清单修复（device-audit-fixes）

在上述只读审查之后，用户明确要求“去修吧”。修复基于 `53d173c3ab69aef9d5ec798a77e4e257cbb58c79` 的当前 wave25 代码，新分支 `codex/ui/device-audit-fixes-20261025`；起始仅本报告有未提交的审查记录。已重新 fetch，`origin/main` 为 `b26ca52580b9ef507ee5de824f3347a04d9e66d7`。保留 wave22–25 的已有修改，不覆盖现有草稿分支。

### 本轮代码边界与文件

- Today / Shell：`VelaMinimalTodayView.swift`、`VelaMinimalShell.swift`、`TodaySignalGrid.swift`、`BodySeekInstrument.swift`，修复摘要遮挡、空态层级和输入栏高度。保留三段导航、现有导航栈、上下文检查和麦克风。
- Trends / Plan / Training：`VelaTrendsView.swift`、`VelaTrainingPlanView.swift`、`VelaMinimalFitnessView.swift`、`TrainingHeroSection.swift`，增加概览图日期参照，减少重复标题与可见控制图形，恢复训练二级页系统返回栏。
- 五项详情：`VelaMetricDetailWidgets.swift`、`VelaMetricDetailData.swift`、`VelaMinimalComponents.swift`，压缩无评分仪表，统一卡片边缘，修复睡眠和能量的缺失值格式。仅消费已有值，不重算评分。
- Journal / sheets：`VelaJournalView.swift`、`JournalComposeSheet.swift`、`JournalCorrelationSection.swift`、`VelaQuickActionsSheet.swift`，压缩入口卡和 sheet 空间，固定随手记保存操作，移除面向用户的内部术语。
- Settings：`SettingsAccountView.swift`、`SettingsCoachModelView.swift`、`VelaSettingsView.swift`、`DataCoverageView.swift`、`TrustCenterView.swift`、`CoachPersonality.swift`，补资料常驻标签、档案阅读模式、实际自动任务状态、来源/覆盖说明、授权控制层次、应用语言时间和可用图标。
- 大字体追加：`CoachMessageBubble.swift` 的长 chip 按提议宽度测量与摆放，允许换行；署名/状态与三段导航在 AX 尺寸重排。Trends 移除另一处 72pt 顶部留白。
- 验证：`VelaThemeTests.swift`、`VelaSmokeUITests.swift`；`DailySummaryUseCase.swift` 只在现有 DEBUG preview 路径增加只读空数据 fixture，不写 HealthKit / SwiftData。

### 逐项处理状态

| 项目 | 本轮处理 | 验证 / 尚存边界 |
| --- | --- | --- |
| VB-01 | 顶栏与导航内容明确纵向布局；移除 72pt 空白 | 新启动 UI 回归先失败（摘要 y=35.5，导航底 y=69），布局修复后通过；同时断言输入栏仍在屏内。 |
| VB-02 | 全部缺失时五项同等紧凑，不指定 hero | 空数据真实 SwiftUI 截图；读数均保持 `--`。 |
| VB-03 | 空闲单行；编辑时展开；保留 44pt 麦克风与上下文入口 | 原版 99pt 高度断言失败；新布局通过 ≤76pt 和屏内断言。 |
| VB-04 | 稀疏概览图增加起止日期 | 保留原始点、缺失日断线与基线，不插值；深色和大字体截图。 |
| VB-05 | 标题改为行动数量概述；完成圈可见 24pt，点击区 44pt | 保留原行动顺序、决定和编辑/完成逻辑。 |
| VB-06 | 训练标题降至 title2；设置/资料移除大幅装饰导语 | 控制项优先，深色和大字体截图。 |
| VB-07 | 今日五分全缺失时只说尚未就绪和同步，不再说“不必改计划” | 不覆盖已保存计划，不改变训练决定或评分。 |
| VB-08 | 缺失评分改紧凑 `--` + 一次引导；依据可展开 | 已有可用原始事实和历史仍保留。 |
| VB-09 | 睡眠时长按观测是否存在格式化 | unknown=`--`，有正时长/评分/非卧床观测时保留已知值，known zero 仍显示 0；单元和 UI 回归。 |
| VB-10 | 能量比较标题、事实与储备条统一读取可选值 | unknown=`-- → --`，已知 0 保留；已知早间储备不会因当前值缺失而被隐藏；单元和 UI 回归。 |
| VB-11 | 心率分区空卡展开至可用全宽 | 与相邻卡片统一边缘。 |
| VB-12 | 快捷操作 sheet 按内容高度，取消跟随网格 | 保留全部原入口；大字体采用大 sheet。 |
| VB-13 | 日历、随手记、无实验入口缩成紧凑表达 | 不改变日记数据、日期选择或实验行为。 |
| VB-14 | 随手记单层输入、短说明、底部固定保存 | 保存前不写入，聚焦/关闭回归。 |
| VB-15 | 去掉 Body Model / 低摩擦信号 / Check-ins 等内部术语 | 只改用户界面显示，不改提示词和内容合同。 |
| VB-16 | 保留 dismiss；关闭时先释放输入焦点 | **未关闭**：模拟器原路径在修复前后均通过，不能据此声称定位了那次实机失效；仍需安装候选后实机重复验证。 |
| VB-17 | 已填资料常驻字段名、单位和来源 | 28 / 72 / 175 合成资料 UI 回归，未改变个人真实值。 |
| VB-18 | 档案默认阅读，编辑和源码显式选择；文件名移入文件信息 | 空模板显示待填写，不自动翻译或改写已保存正文；正文使用既有 MarkdownText 渲染。 |
| VB-19 | 健康守护使用系统通用 heart.fill | 保留各风格选择行为；深色截图。 |
| VB-20 | 入口从实际任务/提醒开关与联网授权计算展示状态 | 不改开关或通知授权；页标题统一“主动智能”。 |
| VB-21 | 中性“健康数据连接”与等待状态；基础/可选授权 CTA 分主次 | 评分快照日期单独显示；请求同步时间不冒称同步成功。 |
| VB-22 | 覆盖明确为最近 7/30 天原始样本，显示检查时间，不能代替所选日评分 | **未关闭**：未取得那次同日/同源/同窗口的真实回放，未更改 TodayStore、缓存 TTL、HealthKit→计算管线或评分合同。 |
| VB-23 | 覆盖页去重复标题/badge/8pt 环；信任中心去嵌套内卡 | 保留覆盖、授权与审计含义，未移除诊断信息。 |
| VB-24 | 审计日期跟随 AppLanguage locale | 时间值与时区未改变。 |
| VB-25 | 入口/标题统一联网 Agent；状态与逐类授权在前，说明可展开 | 保留原密钥和模型配置/撤销/测试操作；未测试连接、未外发上下文。 |
| VB-26 | 恢复训练二级页 navigationBar 与系统返回 | Plan→训练→Today→Plan→返回计划 UI 路径通过，保留导航栈状态。 |

### 复现与验证记录

最终代码 `07b85e8ba98bd3c3a526723ad50c6dd984495fc5`；draft [PR #28](https://github.com/SunWeizhou/bodyseek/pull/28)。完整命令、22 张合成数据原始截图、源码/截图 manifest 与失败尝试见 [本轮证据](rhythm-horizon/device-audit-fixes-2026-10-25/README.md)。

- `DeviceAuditCandidateFinal.xcresult`：683 unit + 12 UI，exit 0；`DeviceAuditScreenshotQA.xcresult`：683 unit + 档案/训练 2 UI，exit 0。
- 最大字号追加 viewport 回归先失败（Today 左缘 -219pt），限制 chip 宽度并重排后通过。`DeviceAuditAXGreen.xcresult` 2 UI，exit 0。
- 最终 `DeviceAuditVerifiedTip.xcresult`：683 unit + 4 UI，687/687，exit 0。共 13 条不同 UI 路径分批通过，未把重复执行累加为独立覆盖。
- 字体 strict 178/216、contrast、schema 32/32、diff check 均 exit 0；token audit 577 为 report-only，不是零残留声明。
- Xcode 27.1 / 27A9275；pin 26.5.0 未改。SE 3 375pt 与 iPhone 17 Pro Simulator，iOS 26.5，L / AccessibilityXXXL，深浅色。并行 clone 未完成的尝试以退出 143 保留，未算作通过；后改串行完成。

真实 iPhone 仍为旧安装包；2026-10-25 镜像后续读取显示 Touch ID 锁定，未代填设备或 Mac 凭证，未部署修复包。模拟器合成样例只证明布局与指定交互，不是该次真实健康数据问题的闭环证据。


### 2026-10-25 · 用户授权后的手机安装

用户明确要求“推送到手机”后，已将 `7c62a0d1` 的签名构建覆盖安装到 iPhone 16 Pro，构建、签名验证和安装均 exit 0；没有卸载或执行数据删除。两次启动均被 iOS `Locked` 拒绝，已请求解锁，启动与真机 UI 验收仍待确认。此前“未部署”描述保留为历史阶段状态，当前安装以此更新及 [脱敏凭据](rhythm-horizon/device-audit-fixes-2026-10-25/phone-install-receipt.json) 为准。
