# BodySeek M3 Coach 智能体重构与评测验证报告（2026-11-20）

- 分支：`codex/ui/ios26-native-bodyseek`
- 关联提交：
  - Commit 1（`[M3][AGENT]`）：`48679366`（拆出 `BodySeekAgent`、移除 `SpeziLLM`/`swift-openapi-*`、自研 `OpenAICompatibleClient`/四态工具/数字溯源/三层记忆选择器/主动洞察引擎与 30 题评测集）
  - Commit 2（`[M3][UI]`）：待提交（以 `48679366` 为基线，上线三层记忆管理、提案确认卡片、主动洞察与隐私数据预览）
- 环境：Apple M5 Pro / SwiftPM Debug + iOS Simulator `iPhone 17 Pro` (`3BB779BD-022F-4E60-A3BB-70DC5A0BF987`) + `generic/platform=iOS`

---

## 1. M3 架构与能力改造摘要

1. **移除外部包装并独立 `BodySeekAgent` 模块 (`48679366`)**
   - 从 `BodySeekKit/Package.swift` 彻底移除 `SpeziLLM`、`swift-openapi-generator`、`swift-openapi-runtime`、`swift-http-types` 依赖，保留 `Spezi` 与 `SpeziHealthKit` 仅用于 HealthKit 采集。
   - 删除遗留 `DynamicServerURLMiddleware.swift`、旧 `CoachAIClient.swift` 与 `CoachAgentTools.swift`；清理 `BodySeekStandard.swift` 中 `LLMRunner` 注入，并在 `Vela.xcodeproj` / `project.yml` / `VelaApp.swift` 挂载 `BodySeekAgent`。
2. **自研 `OpenAICompatibleClient` 与显式路由表 (`BodySeekAgent/OpenAICompatibleClient.swift`)**
   - 原生 `URLSession` + 纯 `Codable` DTO，支持 SSE 分块流式 `tool_calls` 拼接、多轮工具调用（最多 6 轮）、30 秒超时与瞬态 `429`/`5xx`/`URLError` 重试。
   - 内置 `ToolMarkupScrubber`，清除 DeepSeek/Qwen 偶发的 `<tool_call>`、嵌套 `<｜DSML｜function_calls>` / `<｜DSML｜invoke>`、`<function_calls>` 与 `<think>` 泄漏标签，并清除工具参数中的 Markdown 代码块围栏。
   - `AgentRoutingPolicy` 将云端 OpenAI 兼容接口与端侧 `FoundationModels` 路由表显式化并记录 `Logger`（零 `try?`）。
3. **四态工具体系与 Confirm-to-Write 提案约束 (`BodySeekAgent/CoachToolRegistry.swift`)**
   - 所有只读工具统一返回带 `state`（`available`/`knownZero`/`missing`/`excluded`）、`coverage`、`reason`、`algorithmVersion` 的结构化 JSON：
     - `get_today_context`、`get_metric_trend`、`get_workouts_and_muscles`（分离 `effortUser` 与 `effortEstimated`，肌群标注「启发式估计」）、`get_sleep_detail`、`get_patterns`（标注相关性非因果）、`find_similar_days`（严格禁止未来数据泄露的历史类比）、`get_eating_context`（未记录返回 `missing`）、`search_exercise_catalog`。
   - 所有写入只能通过提案工具生成待确认卡片：`propose_plan_change`、`propose_memory`、`propose_workout_annotation`，不在对话回合内静默写库。
4. **数字溯源校验 (`BodySeekAgent/NumericProvenanceVerifier.swift`) & 三层记忆 (`MemoryContextSelector.swift`)**
   - 校验助手回复中带健康单位或指标前缀的数字是否源于本轮工具 JSON 输出或用户原文，未核实数字内联标注`（未核实）`并记录至 `CoachMessage.unverifiedNumbers`。
   - 严格区分 `profile`、`activeConstraint`（过期自动失效）、`verifiedPattern`（未关联 `confirmed` `pattern_finding` 禁止写入），按问句领域检索相关性后注入上下文。
5. **UI、审计与隐私透明 (`[M3][UI]`)**
   - **三层记忆管理（[CoachMemorySheetView.swift](file:///Users/sunweizhou/Developer/BodySeek/bodyseek-1/BodySeekKit/Sources/BodySeekFeatures/Views/Coach/CoachMemorySheetView.swift)）**：按 `Profile / Active Constraint / Verified Pattern` 分组展示，展示剩余有效天数，支持停用（`.retireMemory` 审计）及候选统计规律一键确认晋升。
   - **提案确认卡片（[CoachView.swift](file:///Users/sunweizhou/Developer/BodySeek/bodyseek-1/BodySeekKit/Sources/BodySeekFeatures/Views/CoachView.swift), [CoachFeature.swift](file:///Users/sunweizhou/Developer/BodySeek/bodyseek-1/BodySeekKit/Sources/BodySeekFeatures/Reducers/CoachFeature.swift)）**：渲染记忆确认卡、Watch 训练标注确认卡、课表处方卡与「含未核实数字」徽章；确认后经 `ActionExecutor` 原子落库并写 `action_audit`。
   - **主动洞察（[ProactiveInsightEngine.swift](file:///Users/sunweizhou/Developer/BodySeek/bodyseek-1/BodySeekKit/Sources/BodySeekAgent/ProactiveInsightEngine.swift), [TodayView.swift](file:///Users/sunweizhou/Developer/BodySeek/bodyseek-1/BodySeekKit/Sources/BodySeekFeatures/Views/TodayView.swift)）**：连续 3 日基线偏离 > 练后待复盘提醒 > 晨间定调，每日严格 `≤ 2` 条且跳过 `missing` 日，支持「设置」一键开关（`settings-proactive-insights-toggle`）。
   - **外发数据预览（[SettingsView.swift](file:///Users/sunweizhou/Developer/BodySeek/bodyseek-1/BodySeekKit/Sources/BodySeekFeatures/Views/SettingsView.swift)）**：记录最近一次发往云端的请求 JSON 快照（`AgentPayloadRecorder`，不含 Keychain API Key），提供「查看最近发往云端 AI 的数据」（`settings-privacy-payload-sheet`）。

---

## 2. 30 题真实场景评测集与协议单元测试 (`BodySeekAgentEvals`)

测试文件：[BodySeekAgentEvalsTests.swift](file:///Users/sunweizhou/Developer/BodySeek/bodyseek-1/BodySeekKit/Tests/BodySeekAgentEvals/BodySeekAgentEvalsTests.swift)、[OpenAICompatibleClientTests.swift](file:///Users/sunweizhou/Developer/BodySeek/bodyseek-1/BodySeekKit/Tests/BodySeekAgentEvals/OpenAICompatibleClientTests.swift)

- **`BodySeekAgentEvalsTests.testRunThirtyCaseAgentEvalSuite`**：
  - `AGENT_EVALS_M3: passed=30/30 rate=100.0% tool_leak=0 provenance_pass=30/30 direct_write_violations=0`
  - 覆盖 7 个维度共 30 题：今日状态（4）、四态缺失诚实度（4）、睡眠细节（4）、Watch 训练/肌群启发式与标注提案（6）、三层记忆门禁（4）、个人规律与历史相似日类比（3）、饮食上下文与防提示注入/标签泄露（5）。
- **`OpenAICompatibleClientTests`（8/8 通过）**：
  - `testEndpointURLNormalizerHandlesTrailingSlashesAndChatSuffixes`
  - `testDeepSeekSSEStreamAssemblesSplitToolCallsAndRunsMultiTurnLoop`
  - `testDeepSeekFixtureScrubsLeakedToolCallAndDSMLTagsWithoutDataLoss`
  - `testTransientHTTP429AndTimeoutRetrySucceedsWhileHard401FailsFast`
  - `testNumericProvenanceVerifierFlagsHallucinatedMetricsAndPassesToolNumbers`
  - `testMemoryContextSelectorFiltersExpiredRetiredRelevanceAndVerifiedPatternGate`
  - `testProactiveInsightEngineCapsAtTwoAndIgnoresMissingDays`
  - `testFindSimilarDaysNeverLeaksFutureDays`

---

## 3. 验证命令与实测结果（最终代码树）

1. `grep -rn 'try?' BodySeekKit/Sources/`
   - 退出码：`1`（**0 处匹配**）
2. `grep -rn 'SpeziLLM\|DynamicServerURLMiddleware\|OpenAPIRuntime' BodySeekKit/Sources BodySeekKit/Package.swift VelaApp/ project.yml`
   - 退出码：`1`（**0 处匹配**，`SpeziLLM` 与 OpenAPI 运行时彻底清除）
3. `grep -rn 'Liveline\|SleepChartKit\|repeatForever' BodySeekKit/Sources/`
   - 退出码：`1`（**0 处匹配**）
4. `grep -rn 'import Charts' BodySeekKit/Sources/BodySeekFeatures/`
   - 退出码：`1`（**0 处匹配**）
5. `git diff --check`
   - 退出码：`0`
6. `swift test --package-path BodySeekKit`
   - 退出码：`0`：
     - `BodySeekKitTests`：**45/45 通过**（耗时 `1.627s`，`WorkoutAndCoachReducerTests` 5/5 含未确认前零写入、确认后写 `action_audit` 与候选规律晋升测试）
     - `BodySeekAgentEvals`：**9/9 通过**（耗时 `0.186s`，`AGENT_EVALS_M3: passed=30/30 rate=100.0% tool_leak=0 provenance_pass=30/30 direct_write_violations=0`）
7. `xcodebuild test -project Vela.xcodeproj -scheme Vela -destination 'id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987' -parallel-testing-enabled NO -skipMacroValidation -skipPackagePluginValidation`
   - 退出码：`0`，**`** TEST SUCCEEDED **`**：
     - `VelaTests`（`BodySeekAppIntegrationTests`）：**4/4 通过**（耗时 `0.114s`）
     - `VelaUITests`（`BodySeekUITests`）：**7 项执行，6 通过 / 1 预期跳过（`testCaptureLightAndDarkScreenshotsWhenRequested` 未设 `BODYSEEK_WALKTHROUGH_DIR`）/ 0 失败**（耗时 `147.070s`），含 `testM3CoachProposalsTieredMemoryProactiveInsightsAndPrivacyViewer`（`30.247s`）。
8. `xcodebuild -project Vela.xcodeproj -scheme Vela -destination 'generic/platform=iOS' -skipMacroValidation -skipPackagePluginValidation -allowProvisioningUpdates build`
   - 退出码：`0`，**`** BUILD SUCCEEDED **`**。

---

## 4. 未验证风险

- **线上真实 DeepSeek / OpenAI 兼容服务调用**：本轮 30 题评测与客户端多轮 SSE 测试均在可控传输夹具（`MockAgentTransport` / `ScriptedEvalTransport`）上完成，以确保确定性与离线可复现；真实公网 API Key 下的实时流式首字延迟与服务端限流恢复未在 CI 环境中联网实测。
- **真机 Apple Intelligence 端侧 `FoundationModels` 工具链**：iOS 模拟器不支持 Apple Intelligence 端侧权重，端侧对话 `LanguageModelSession` 与 5 个 `Tool` 适配器在真机上的实际响应稳定度待真机验收补充。

## 5. Coach Markdown 回复补充验证

基于 `ed7ab2c2` 的本地修改，把助手回复文本交给 Textual 0.5.0 的结构化渲染器。图片保留替代文字，渲染时不请求模型给出的图片地址。模拟器用 Xcode 27.1 和 iOS 26.5 的 iPhone 17 Pro 运行。

- `swift test --package-path BodySeekKit --disable-automatic-resolution --filter 'CoachMarkdownParserTests|BodySeekAgentEvals'`，退出码 `0`。Markdown 解析测试 1 项通过，覆盖中文标题、列表、加粗、表格和移除图片地址。Agent 测试 9 项通过，脚本问答 30/30。
- `xcodebuild test -project Vela.xcodeproj -scheme Vela -destination 'id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987' -derivedDataPath /tmp/bodyseek-deploy-20261120 -disableAutomaticPackageResolution -parallel-testing-enabled NO -skipMacroValidation -skipPackagePluginValidation -only-testing:VelaUITests/BodySeekUITests/testM3CoachProposalsTieredMemoryProactiveInsightsAndPrivacyViewer -resultBundlePath /tmp/bodyseek-coach-markdown-final-20261120.xcresult`，退出码 `0`。模拟回复的 Markdown 标题独立显示，记忆提案可确认，隐私预览可打开。产物为 `/tmp/bodyseek-coach-markdown-final-20261120.xcresult`。
- 模型输出格式使用合成回复和脚本传输验证，真机上的排版和实际在线服务回复待核对。

## 6. 餐食草稿、证据合同与同步回归

分支为 `codex/ui/ios26-native-bodyseek`，HEAD 为 `ed7ab2c2eafda0ff07a1c6a7a18ccaa1197b4f0b`。测试覆盖本地工作树，包含本轮开始前已有的 UI、依赖和文档改动。

- 文字和照片只生成待确认的食物和份量。营养值由已匹配的食物库条目换算。缺少营养资料的条目保留为空，相应餐次记为部分记录。部分记录可显示已知小计，整个日次不纳入达标评价和能量盈余。
- `bodyseek-evidence-v1` 让 Coach 的工具返回可用状态、版本、日期范围和单位。营养工具读取生效的目标及部分记录，训练工具按 HealthKit UUID 关联设备记录与手动训练，保留未匹配的手动记录。HealthKit 返回空时，训练覆盖率未知。[Apple HealthKit 授权行为](https://developer.apple.com/documentation/HealthKit/authorizing-access-to-health-data)
- 启动时通过现有 GRDB 观察首次读取缓存并接收更新。缓存内容相同的通知不重复应用。快照保留实际参考时刻，避免营养与训练查询在本地凌晨四点的切日边界取错日期。
- `swift test --package-path BodySeekKit --disable-automatic-resolution`（日志 `/tmp/bodyseek-pipeline-unit-v3.log`）退出码 `0`，53 项包测试、11 项 Agent 测试通过。脚本问答 30/30。包含 03:59:59 与 04:00 切日、确认写入的事务和重试、部分营养数据、图片传输与审计脱敏、训练 UUID 合并。
- `xcodebuild test -project Vela.xcodeproj -scheme Vela -destination 'id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987' -derivedDataPath /tmp/bodyseek-deploy-20261120 -disableAutomaticPackageResolution -parallel-testing-enabled NO -skipMacroValidation -skipPackagePluginValidation`，用 `-only-testing` 选择今日与三年趋势、训练复盘、Coach、趋势探索、文字记餐五项。退出码 `0`，产物 `/tmp/bodyseek-pipeline-ui-v3.xcresult`。初次扩跑在今日页滚动时卡住，主线程采样落在 SwiftUI 的懒加载布局。今日外层切换为标准 `VStack` 后同一路径通过。
- `xcodebuild build -project Vela.xcodeproj -scheme Vela -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/bodyseek-deploy-20261120 -disableAutomaticPackageResolution -skipMacroValidation -skipPackagePluginValidation`，退出码 `0`，日志 `/tmp/bodyseek-pipeline-ios-final.log`。
- 最终源码单独复跑 `testNutritionTextDraftRequiresConfirmationBeforeSaving`，退出码 `0`，产物 `/tmp/bodyseek-pipeline-meal-final.xcresult`。
- 线上模型用测试传输验证请求结构。真机相机、实际供应商的图片识别、Apple Watch 数据回流与 Release 冷启动性能仍需用真实环境验证。

## 7. 全天饮食、肌群恢复和 Coach 布局

本地分支 `codex/ui/ios26-native-bodyseek`，HEAD `ed7ab2c2`，工作树保留此前改动。全天文字草稿按餐次拆分，保留原始份量描述，标明估算，支持在同一事务中保存份量未知的条目。数据库升级验证保留已有餐食。健身页停留时定时重算，支持下拉同步。按同一训练 ID 合并设备与手动数据时补入缺少的肌群，避免重复累计已记录的肌群。

- `swift test --package-path BodySeekKit --disable-automatic-resolution` 退出码 `0`，56 项包测试和 13 项 Agent 测试通过，脚本问答 30/30。日志 `/tmp/bodyseek-daymeal-verified-unit.log`。
- `xcodebuild build -project Vela.xcodeproj -scheme Vela -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/bodyseek-deploy-20261120 -disableAutomaticPackageResolution -skipMacroValidation -skipPackagePluginValidation` 退出码 `0`。日志 `/tmp/bodyseek-daymeal-verified-build.log`。
- CoreDevice 安装到 iPhone 16 Pro，序列 `1812`，并成功启动。按既定要求跳过模拟器。本次个人饮食未写入真机，未调用真实模型核对个人饮食，也未测量 Apple Watch 到 iPhone 的时延。

## 8. 标准版全天记餐与 Coach 回归

- 基线 `ed7ab2c2` 加本地工作区修改。标准版从营养页直接打开全天饮食草稿，选定日期贯穿分析与确认。食品成分采用食物库来源，未知条目标记为待补。Coach 欢迎页可发起四类常用提问，新对话清空前需要确认。
- `swift test --package-path BodySeekKit --disable-automatic-resolution` 退出码 0，57 项包测试和 13 项 Agent 测试通过，脚本问答 30/30。全天餐食回归以中文样例和模拟模型响应核对四餐归类、原始份量、价格与毫升单位，日志为 `/tmp/bodyseek-nov20-standard-unit.log`。
- iPhone 17 Pro / iOS 26.5 默认字号的 Coach 快捷提问、清空确认、记忆和训练提案用例通过。本次改动尚未安装到真机，模拟传输覆盖接口与保存流程，线上模型的实际输出待验证。

## 外食与混合饮品热量区间

工作树基于 `ed7ab2c2`，保留此前改动。模型可根据餐食类型、人均消费和饮品体积给出热量情景范围。草稿与保存后的单项显示范围和估算依据，既有热量汇总采用区间中点。未估算三大营养素。回归验证火锅无克重时可返回区间、饮品体积保留和反向区间被丢弃。

- `swift test --package-path BodySeekKit --disable-automatic-resolution` 退出码 `0`，57 项包测试和 14 项 Agent 测试通过。日志 `/tmp/bodyseek-energy-estimate-unit.log`。
- `xcodebuild build -project Vela.xcodeproj -scheme Vela -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/bodyseek-deploy-20261120 -disableAutomaticPackageResolution -skipMacroValidation -skipPackagePluginValidation` 退出码 `0`。安装并启动 iPhone 16 Pro 版本，安装序列 `1820`。未用真实账号提交个人饮食。日志 `/tmp/bodyseek-energy-estimate-build.log`。

## 全天饮食回复兼容性

基于本地工作树 `ed7ab2c2`，保留既有改动。修复前两项回归均失败，分别复现份量字段返回数字字符串，以及输出被截断（`/tmp/bodyseek-meal-reply-red.log`）。修复后兼容常见单位和餐次格式，忽略无效的可选估算字段，回复无法读取时只补试一次。

- `swift test --package-path BodySeekKit --disable-automatic-resolution` 退出码 `0`，57 项包测试和 16 项 Agent 测试通过（`/tmp/bodyseek-meal-reply-unit.log`）。
- Vela Debug 通用 iOS 构建退出码 `0`（`/tmp/bodyseek-meal-reply-build.log`）。安装到 iPhone 16 Pro，序列 `1828`。自动启动被锁屏挡住，未验证该账号的实时模型回复。
