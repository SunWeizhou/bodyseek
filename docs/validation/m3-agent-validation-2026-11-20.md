# BodySeek M3 Coach 智能体重构与评测验证报告（2026-11-20）

- 分支：`codex/ui/ios26-native-bodyseek`
- 关联提交：
  - Commit 1（`[M3][AGENT]`）：`48679366`（拆出 `BodySeekAgent`、移除 `SpeziLLM`/`swift-openapi-*`、自研 `OpenAICompatibleClient`/四态工具/数字溯源/三层记忆选择器/主动洞察引擎与 30 题评测集）
  - Commit 2（`[M3][UI]`）：`6f577833`（以 `48679366` 为基线，上线三层记忆管理、提案确认卡片、主动洞察与隐私数据预览）
- 环境：Apple M5 Pro / SwiftPM Debug + iOS Simulator `iPhone 17 Pro` (`3BB779BD-022F-4E60-A3BB-70DC5A0BF987`) + `generic/platform=iOS`；CI 固定工具链为 `.xcode-version` 26.5.0，本机 27.1 结果用于模拟器走查，固定版本判定以 GitHub Actions 为准

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
3. `grep -rn 'Liveline\|repeatForever' BodySeekKit/Sources/` 与 `grep -rn 'SleepChartKit' BodySeekKit/Sources/`
   - 前者 **0 处匹配**；后者仅 `BodySeekDesign/Charts/SleepStageChart.swift` 3 处（`BodySeekFeatures` 层 0 处，允许范围见 `docs/design/chart-grammar.md`）
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

## 9. 2026-11-21 质量修复复测

起点为干净的 `b03f2bb8` 工作树。本节记录本地实现与回归。

- 饮食结账只读同日期的健康数据。缺失活动消耗保留为空，真实零值继续可用。过去七天的平均缺口使用日历窗口，今日摘要以今天为终点。
- 全天解析若含有无法读取的必填条目，使用现有重试，并在仍失败时保留原文和此前草稿。已保存餐食复用手动表单编辑，同一条目沿用原 ID。删除须确认，删除后重新打开日结状态。已修改餐次的缺项按当前条目重算。
- AI 粗估保留区间，日汇总和饮食工具提供区间、已有数值小计和缺项计数。历史库仍保留中点字段供兼容的汇总读取。
- Coach 云端复用当前聊天接口最近最多六条消息，端侧用原生会话记录恢复最近最多四条。历史仅供理解追问，当前数值仍由本轮工具核实。训练复盘提案以消息 ID 复用 GRDB 审计事务，即使重试也只生效一次。旧版只记录成功动作的提案按内容及审计时间恢复确认状态。 [GRDB 事务接口](https://github.com/groue/GRDB.swift/blob/master/GRDB/Core/DatabaseWriter.swift) · [Foundation Models 会话记录](https://developer.apple.com/documentation/foundationmodels/inspecting-session-transcripts-and-reporting-model-feedback)
- `swift test --package-path BodySeekKit --disable-automatic-resolution` 退出码 0，62 项包测试、20 项 Agent 测试通过。回归包含错日结账、餐食编辑与删除、Coach 提案重开及重试、混合有效性模型响应、饮食热量区间和历史日期查询。日志 `/tmp/bodyseek-quality-fix-final.log`。

- 默认字号的 iPhone 17 Pro / iOS 26.5 模拟器上，4 项集成测试以及 Watch 复盘、Coach 记忆与隐私、全天草稿确认、展开早餐用例均通过。编辑入口从菜单改为直接按钮后，单独复跑编辑用例退出码 0，已验证把保存的早餐条目移到加餐并保存。结果为 `/tmp/bodyseek-quality-fix-edit-labels.xcresult`，截图在 `/tmp/bodyseek-quality-edit-labels-ui`。线上服务和真机同步未实测。

### 复查发现

- 设置页「重置训练日志、记忆与设置」实际还会删除饮食、聊天和打卡。入口缺少二次确认，正在处理的聊天也可能在重置后再写回。真实设备上未触发重置。
- 前台刷新用 60 天窗口计算并持久化历史分数。窗口开头最多 28 天可能缺基线，覆盖原先基线更完整的同版本分数。应补全计算窗口并用固定输入对拍前台与回填结果。
- Coach 趋势覆盖率使用返回记录数作分母。数据稀疏时仍可能显示高覆盖率，应按日历窗口统计有效数据天数，并统一已知零的口径。

### iPhone 16 Pro 安装

基于 `b03f2bb8` 加本地质量修复。Vela Debug 通用 iOS 构建退出码 0，日志 `/tmp/bodyseek-quality-phone-build.log`。CoreDevice 原地安装成功，安装序列 `1908`，启动命令退出码 0。实际 Apple Watch 删除回流和线上模型追问仍待实测。

### AI 记餐的可选补充与估算

在 `b03f2bb8` 加本地质量修复上，餐食草稿优先采用手动填写，其次采用食物库换算，并用带标记的 AI 粗估补齐可估算的份量、热量和宏量营养。修改同单位份量时，在合理比例内换算原估算。极端或缺乏依据的值继续留空。包测试 83 项通过，覆盖宏量估算字段的有效性。默认字号 iPhone 17 Pro 模拟器的全天草稿确认用例通过。此后补充的食物库单项缺失回退通过包测试。该阶段的真机安装见下方扩展估算版记录。

### 扩展 AI 营养估算

基线为 `b03f2bb8` 和既有本地改动。估算扩展到看板的膳食纤维、ALA、EPA＋DHA、14 项维生素和 15 项矿物质，饮水只计明确可识别的白水。提示词直接引用现有指标和单位合同，解析校验标识、单位与份量。手动值优先于食物库和 AI 粗估。逐项记录估算标记，日看板显示估算量，但该值不触发营养达标或限量判定，也不纳入有效周期均值。

`swift test --package-path BodySeekKit --disable-automatic-resolution` 退出码 0，63 项包测试和 22 项 Agent 测试通过。iPhone 17 Pro / iOS 26.5 模拟器的全天草稿确认回归通过，产物为 `/tmp/bodyseek-micro-ui.xcresult`。在线模型的估算质量待实测。

扩展估算版的 Vela Debug 通用 iOS 构建成功，日志 `/tmp/bodyseek-micro-phone-build.log`。已覆盖安装至 iPhone 16 Pro，安装序列 `1916`。启动请求被设备锁屏拦截，线上估算仍待实测。

## 10. 2026-11-21 Coach 近 7 天恢复取证（工单 1）

基线为 `03051a4d`（工单 1 提交）。本轮新增 `get_weekly_recovery_evidence`，云端与 Apple Foundation Models 共用 `WeeklyRecoveryEvidenceBuilder` 的确定性查询。目标窗是最近 7 个本地 04:00 生理日，对照窗是此前不重叠的 28 个生理日；逐日五项、睡眠、训练、体感和饮食按同一时间线返回，覆盖率与统计样本数分列，四态和已知零保持原样。饮食只给保存时间，进食时刻保持未知；咖啡名称作为未确认线索。证据信封新增带 metric/window/day/unit/estimated 的 `evidence` facts，核验器会拒绝错日期、错指标和错单位。

改前使用同一问题从当前 `get_metric_trend` 取证：30 天 `median=69`、`deltaFromFirstHalf=+3`、`coverage=1.0`（30 条记录），没有 7/28 拆分、逐日观测、睡眠/训练/体感/饮食时间线，预览回复无法回答“为什么下降”。

改后同一夹具（35 天预览种子）：目标 7 天恢复中位 77，对照 28 天中位 68，变化 +9，方向 improved；对照覆盖 26/28、样本 26、缺失 2、排除 0，逐日 7 天和 120 条证据 facts 一并返回。因此正确首答是“没有下降”，而不是编造下降原因。

- `swift test --package-path BodySeekKit --disable-automatic-resolution` 退出码 0，89 项包测试和 22 项 Agent 测试通过。`WeeklyRecoveryEvidenceTests` 覆盖 04:00 切日、未来日期、当前日部分、窗口不重叠、3 天缺失 + 2 天排除得到 23/28 覆盖与 23 样本、已知零、同日 09:00 力量与 20:00 羽毛球各计一次、缺失睡眠、咖啡时间未知，以及错日期/错指标/错单位/数值替换负例。Agent 评测新增 W1 用例，31/31 通过。
- `xcodebuild test -project Vela.xcodeproj -scheme Vela -destination 'id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987' -only-testing:VelaUITests` 退出码 0，13 项中 12 项通过、1 项按预期跳过。
- 未验证：线上 DeepSeek/OpenAI 对同一问题的实际回复质量、Apple 端侧 `FoundationModels` 真机调用、真机 HealthKit 数据。上述 7/28 数值来自固定合成夹具，不是临床证据。

## 11. 2026-11-21 全量审查与代码优化

审查基于 `efe97829` 加当时 7 个用户文档改动。静态扫描 `BodySeekKit/Sources` 与 `VelaApp`：`try!`、`fatalError`、`as!`、`TODO/FIXME`、`print(` 均为 0；未发现 `DispatchQueue.main.sync` 或 `Task.detached`；6 处 `@unchecked Sendable` 均有锁/系统对象封装，未改动。重点复核了周恢复、溯源核验、标注撤销、数据库迁移和 Coach 刷新路径。

本轮修复：

- **混合工具溯源误报**：此前一回合并存 `evidence` facts 和无 facts 的旧工具结果时，只要 facts 非空，旧工具的数字（如 `get_today_context` 的 HRV）就会被判未核实。现在只有数字确实出现在 typed facts 中才强制 metric/日期/单位校验；不在 facts 中的数字回退到旧工具白名单。新增“周恢复 facts + HRV 46 ms”回归，负例（错日期/指标/单位）仍被拒绝。
- **周恢复重复扫描**：原实现对目标/对照窗口和逐日展示反复调用 `dayWorkouts`，每次全量过滤训练并为每条训练再过滤肌群负荷。改为一次构建 `WorkoutEvidenceIndex`（按生理日分组、按训练 UUID 索引负荷和标注），窗口和逐日共用；训练/负荷行为不变，扫描从约 70 次全量过滤降为 1 次。
- **溯源正则重复编译**：单位、日期和数字正则改为静态缓存，避免每个候选数字重复编译。
- **多候选“忽略”无效**：多候选选中后消息本身没有 `workoutAnnotationProposal`，原 reducer 直接返回。现在回退到 `annotationCandidateSelections`，清空选择并按 rejected 审计。
- **撤销按钮禁用条件用错集合**：从 `pendingAnnotationDecisionMessageIDs` 改为 `pendingAnnotationUndoMessageIDs`。
- **静默 `try?`**：撤销快照解析失败现在返回明确的 `undoUnsupported`；预览周恢复的构建失败改为显式 do/catch。

验证：

- `swift test --package-path BodySeekKit --disable-automatic-resolution` 退出码 0，89 项包测试和 22 项 Agent 测试通过。
- `xcodebuild test … -only-testing:VelaTests` 退出码 0，4/4 通过。
- `xcodebuild test … -only-testing:VelaUITests` 退出码 0，13 项中 12 项通过、1 项按预期跳过，294–296 秒。
- 模拟器 Debug 构建 `BUILD SUCCEEDED`。
- 未验证项与第 10 节相同：线上模型、Apple 端侧和真机数据未在本轮重新验证。

## 12. 2026-11-22 深扫同步、读模型与审计查询

在 `6a2105ee` 基础上继续审查 Coach 以外的链路。静态扫描仍为 0 个 `try!`/`fatalError`/`as!`/`TODO`/源码 `print`；`swift build` 只出现 SpeziHealthKit 的 pkg-config 提示，无 Swift 编译警告。6 处 `@unchecked Sendable` 逐一核对，均有锁、系统对象或串行 actor 约束。

本轮发现并修复：

- **同步每次都重算完整历史**：`SyncEngine.persistAndRecompute` 传给 `recomputeIncremental` 的 `existingByDayKey` 一直是空字典，导致每次锚点同步都重新计算整个三年窗口。新增 `BodySeekRepository.loadComputedDays`（复用已存 `score_snapshot` + `day_computed_artifact` + raw days），同步改为加载缓存后传入；缓存损坏时记录日志并回退为全量重算，不阻塞同步。新增存储往返和 `recomputeIncremental` 复用测试。
- **读模型重复解析 computed day**：`BodySeekReadModel.loadCachedDashboardSync` 原先有一份与仓库层近似的 score/artifact 解码，现已统一调用 `loadComputedDaysSync`；读模型遇到损坏 artifact 时回退重算，新增损坏快照回归。
- **审计列表全量加载**：设置页只取最近 N 条，但 `loadActionAuditEntries(limit:)` 先取全部再截断。`loadAuditEntries` 增加可选 SQL `LIMIT`，客户端直接下推；新增数据库层限量测试。
- **失效删除的参数上限**：`invalidateComputedArtifactsSync` 把最多约 29×N 个日期放进单个 `IN` 列表，长回填可能逼近 SQLite 参数上限。改为每 500 个一批删除，行为不变。
- **睡眠目标变化后的缓存观察**：`AppFeature` 在睡眠目标变化时重启 `observeDashboard`，避免旧的观察闭包继续用旧目标重算并把旧分数写回；`loadSnapshotEffect` 会先重算并持久化新目标的结果。仍有一个已知边界：`day_computed_artifact` 未记录睡眠目标，极端竞态下重启观察后可能短暂读到旧缓存，直到新快照写入；已在下方列为未验证风险。
- **固定字号**：肌群恢复详情的 40pt 百分比改为 `.largeTitle` Dynamic Type，支持大字号。

验证：

- `swift test --package-path BodySeekKit --disable-automatic-resolution` 退出码 0，92 项包测试和 22 项 Agent 测试通过。
- `xcodebuild test … -only-testing:VelaTests -only-testing:VelaUITests` 退出码 0；VelaTests 4/4，UI 13 项中 12 通过、1 项按预期跳过。
- 模拟器 Debug 构建 `BUILD SUCCEEDED`。
- 未验证：真机、线上模型、真实 Watch 回流；多候选选择卡仍无 UI 自动化；睡眠目标缓存边界仅做了代码级防护，尚无专门的竞态回归。

## 13. 2026-11-22 清单 1–6 优化

按上一轮列出的六项继续：

1. **睡眠目标进入 computed cache 身份**：`DailyComputedDay` 新增 `sleepGoalMinutes`，`scoreDay` 写入；`day_computed_artifact` v6 新增 `sleep_goal_minutes`（旧行默认 `-1`）。`recomputeIncremental` 仅在 raw、算法版本和睡眠目标都一致时复用缓存；v4/v5 旧 artifact 因 `-1` 不匹配而自动失效一次。回归确认同一 raw 在目标 450→500 时重算并返回 500。
2. **启动同步合并**：`loadSnapshotEffect` 先走 `syncRecentWindow`（同时推进 HealthKit 锚点并写库），再读 ReadModel 缓存；只有同步失败或缓存为空时才回退到直接 60 天查询。`triggerBackgroundBackfillEffect` 只负责历史回填，不再重复 recent sync；冷启动的简报、回填和训练同步只调度一次。
3. **批量写入 prepared statements**：`saveDailyRawMetrics` 的 22 个指标 upsert、`saveComputedDays` 的 5 个 score upsert 和 artifact upsert 改为每个事务准备一次 `cachedStatement`，循环内只绑定参数。
4. **legacy annotation 查询索引**：v6 增加 `idx_action_audit_kind` 表达式索引（`json_extract(proposal_json,'$.kind')`），配合上一轮已下推的 `LIMIT`。
5. **chart cache 按 digest 复用**：ReadModel 先算 `contentDigest`，命中进程内 8 条 LRU chart cache 时跳过 `buildAllChartSnapshots`；数据变化时 digest 改变，仍在写入后重建。
6. **多候选 UI 自动化**：新增 `-velaPreviewAnnotationCandidates` 预览种子（昨晚 18:30 与 20:00 两条力量训练），UI 测试选择候选、确认卡出现、点“忽略”后候选与提案卡都消失。

验证：

- `swift test --package-path BodySeekKit --disable-automatic-resolution` 退出码 0，93 项包测试和 22 项 Agent 测试通过。
- `xcodebuild test … -only-testing:VelaTests -only-testing:VelaUITests` 退出码 0；VelaTests 4/4，UI 14 项中 13 通过、1 项按预期跳过。
- 模拟器 Debug 构建 `BUILD SUCCEEDED`。
- 未验证：真实 HealthKit 启动路径（本轮只有模拟器预览路径）、真实 Watch 回流/删除、线上与 Apple 端侧模型；启动合并后的首屏时延也还没有真机 Instruments 数据。
