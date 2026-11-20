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
