# BodySeek M2 Watch-First 健身与肌群恢复验证报告（2026-11-20）

- 分支：`codex/ui/ios26-native-bodyseek`
- 关联提交：
  - Commit 1（`[M2][CORE-STORE]`）：`d8771ad2`（Watch-First 肌群恢复启发式引擎、自动归因、一句话复盘解析器与 55 例评测集）
  - Commit 2（`[M2][UI]`）：待提交（以 `d8771ad2` 为基线，本文档记录完整代码树的验证结果）
- 环境：Apple M5 Pro / SwiftPM Debug + iOS Simulator `iPhone 17 Pro` (`3BB779BD-022F-4E60-A3BB-70DC5A0BF987`) + `generic/platform=iOS`

---

## 1. M2 交付范围摘要

1. **Commit 1（`[M2][CORE-STORE]`，`d8771ad2`）**
   - `BodySeekKit/Sources/BodySeekCore/MuscleRecoveryEngine.swift`：
     - 实现 `recovery-heuristic-v1`（模型卡见 [MUSCLE_RECOVERY_HEURISTIC_V1_MODEL_CARD.md](file:///Users/sunweizhou/Developer/BodySeek/bodyseek-1/docs/model_cards/MUSCLE_RECOVERY_HEURISTIC_V1_MODEL_CARD.md)），采用指数衰减 $R_m = e^{-F_m}$ 避免线性减法出现负恢复度；
     - 系统衰减因子 $\alpha_{\text{sys}}$ 仅依赖先验恢复指标（睡眠时长对比个人目标、夜间 HRV 与静息心率相对个人基线），不引入今日 Strain/ACWR 形成循环依赖；
     - 实现 `WorkoutAutoAttributor`：跑步/步行自动归因下肢负荷，羽毛球结合 `DominantHand` 归因持拍侧肩与前臂及核心/下肢；力量训练保持 `unreviewed` 进入待复盘 Inbox。
   - `BodySeekKit/Sources/BodySeekCore/WorkoutReviewParser.swift`：
     - 实现 `ChineseWorkoutLexiconParser`、`WorkoutLoadBuilder`、`WorkoutAnnotationProposal`、`WorkoutBodySignal`（零 `try?`）。
   - `BodySeekKit/Sources/BodySeekCore/PreviewSeedFactory.swift`：
     - 确定性 `deterministicWorkoutUUID(slot:)` 生成昨日 Watch 力量训练 `unreviewed`（`00000000-0000-4000-8000-000000000001`）与跑步/羽毛球记录。
   - `BodySeekKit/Sources/BodySeekStore/BodySeekRepository.swift` & `BodySeekKit/Sources/BodySeekHealth/{BodySeekStoreClient,WorkoutReviewParserClient}.swift`：
     - 新增 `loadAllMuscleLoads`、`loadWorkoutAnnotations`、`applyAutoWorkoutAttribution` 与 `WorkoutReviewParserClient`（`FoundationModels` `@Generable` → `ChineseWorkoutLexiconParser` 显式日志降级，零 `try?`）。

2. **Commit 2（`[M2][UI]`，当前工作树）**
   - **Watch-First 健身主页 (`BodySeekKit/Sources/BodySeekFeatures/{Reducers/WorkoutFeature.swift,Views/WorkoutView.swift}`)**：
     - `LazyVStack` 布局按「待复盘 Inbox (`workout-review-inbox`) → ACWR 负荷卡 → 全身肌群恢复热图 (`启发式估计`) → Apple Watch 训练档案与归因 (`workout-archive-section`) → 降权手动补录与模板」排序；
     - 主观 `effortUser` 与系统估算 `effortEstimated` 分离展示，不混合覆盖；
     - 预计算 `recoverySnapshot`，避免在渲染视图内重算。
   - **一句话复盘确认卡 (`Views/Workout/WorkoutReviewSheetView.swift`)**：
     - 支持快捷短语、自定义输入、即时“智能解析”、主/次肌群增删徽章、RPE 调整与身体信号 14 天 `Active Constraint` 记忆勾选；
     - 确认后通过 `ActionProposal` 分别执行 `.annotateWorkout` 与 `.commitMemory` 写入 `ActionExecutor` 与审计日志 `action_audit`。
   - **肌群恢复详情 & 单次训练详情 (`Views/Workout/{MuscleRecoveryDetailSheet,WorkoutDetailSheetView}.swift`)**：
     - 显式标注 `启发式估计`（`muscle-recovery-heuristic-badge`）、预计就绪时间（`muscle-recovery-eta-text`）、$\alpha_{\text{sys}}$ 依据与关联训练刺激记录；
     - 训练详情页分离展示 `用户主观用力 (EffortUser)` 与 `Apple 系统估算 (Estimated)`、心率分区 `ZoneBar` 与 TRIMP。
   - **设置页与 App 联动 (`SettingsFeature.swift`, `SettingsView.swift`, `AppFeature.swift`)**：
     - 新增「持拍手 / 惯用手（右手/左手）」分段选择（`settings-dominant-hand-picker`），切换后重算羽毛球等单侧归因。
   - **交互热区与可测性修复**：
     - 为 `WorkoutView` 肌群恢复列表行与训练档案卡片补充 `.contentShape(...)`，修复行间空白区域点击不触发详情弹窗的问题。

---

## 2. 一句话复盘解析器 55 例评测 (`WorkoutReviewParserTests`)

测试文件：`BodySeekKit/Tests/BodySeekKitTests/WorkoutReviewParserTests.swift`（`testParserAccuracyAcrossFiftyFiveRealChineseWorkoutReviews`）

| 评估维度 | 样本量 | 实测准确率 |
|---|---:|---:|
| 主肌群识别 (`primary`) | 55 | **100.0%** |
| 次肌群与否定表达过滤 (`secondary_negation`) | 55 | **100.0%** |
| RPE 提取 (`rpe`) | 55 | **100.0%** |
| 动作识别 (`exercises`) | 55 | **100.0%** |
| 身体信号提取 (`bodySignals`) | 55 | **100.0%** |

日志摘要：`PARSER_ACCURACY_M2: n=55 primary=100.0% secondary_negation=100.0% rpe=100.0% exercises=100.0% bodySignals=100.0%`

---

## 3. 肌群恢复引擎与端到端单测 (`MuscleRecoveryEngineTests` & Reducer Tests)

1. `testExponentialRecoveryRemainsStrictlyPositiveUnderHeavyStackedLoads`：连续叠加高负荷后 $R_m = e^{-F_m} > 0$ 且带有 `recovery-heuristic-v1` 与「启发式估计」标注。
2. `testSystemicAlphaDependsOnlyOnPriorSleepHRVRHRWithoutCircularStrainDependency`：篡改当日热量/运动分钟数/马拉松记录后，$\alpha_{\text{sys}}$ 数值保持完全一致（无循环依赖）。
3. `testAutoAttributionSeparatesCardioBadmintonDominantHandFromStrengthInbox`：力量训练返回 `nil` 留在 Inbox；跑步归因下肢；羽毛球按左/右持拍手切换归因文本与负荷。
4. `testDatabaseReviewWorkflowPersistsAnnotationLoadsMemory14dAndAuditTrail`：`ActionExecutor` 原子写入 `.annotateWorkout` 与 `.commitMemory`（14 天过期）、分离保存 `effortUser` 与 `effortEstimated`，并立即反映于后续肌群恢复计算。
5. `WorkoutAndCoachReducerTests.testWatchFirstReviewInboxParsesCommits14DayMemoryAndUpdatesMuscleRecovery`：在 `TestStore` 中验证 Inbox 打开、解析、确认提交、写入 14 天 `Active Constraint` 记忆与更新恢复快照全链路。

---

## 4. 验证命令与实测结果（最终代码树）

1. `grep -rn 'try?' BodySeekKit/Sources/`
   - 退出码：`1`（**0 处匹配**）
2. `grep -rn 'Liveline\|SleepChartKit\|repeatForever' BodySeekKit/Sources/`
   - 退出码：`1`（**0 处匹配**）
3. `grep -rn 'import Charts' BodySeekKit/Sources/BodySeekFeatures/`
   - 退出码：`1`（**0 处匹配**）
4. `git diff --check`
   - 退出码：`0`
5. `swift test --package-path BodySeekKit`
   - 退出码：`0`，**44/44 通过**（耗时 `1.614s`，`WorkoutAndCoachReducerTests` 4/4，`WorkoutReviewParserTests` 1/1，`MuscleRecoveryEngineTests` 4/4）。
   - `BENCHMARK_M1_DATA: compute60d=4.91ms compute365d=34.47ms compute1095d=105.89ms horizonSwitch3Y=0.56ms trendsScrub60xMonth=0.08ms trendsScrub60x3Y=0.05ms`
   - `PARSER_ACCURACY_M2: n=55 primary=100.0% secondary_negation=100.0% rpe=100.0% exercises=100.0% bodySignals=100.0%`
6. `xcodebuild test -project Vela.xcodeproj -scheme Vela -destination 'id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987' -parallel-testing-enabled NO -skipMacroValidation -skipPackagePluginValidation`
   - 退出码：`0`，**`** TEST SUCCEEDED **`**：
     - `VelaTests`（`BodySeekAppIntegrationTests`）：**4/4 通过**（耗时 `0.114s`）
     - `VelaUITests`（`BodySeekUITests`）：**6 项执行，5 通过 / 1 预期跳过（`testCaptureLightAndDarkScreenshotsWhenRequested` 未传 `BODYSEEK_WALKTHROUGH_DIR`）/ 0 失败**（耗时 `105.818s`），含 `testM2WatchFirstReviewInboxMuscleRecoveryAndArchive`（`23.058s`）。
7. `xcodebuild -project Vela.xcodeproj -scheme Vela -destination 'generic/platform=iOS' -skipMacroValidation -skipPackagePluginValidation -allowProvisioningUpdates build`
   - 退出码：`0`，**`** BUILD SUCCEEDED **`**。

---

## 5. 未验证风险

- **真实 Apple Watch + 真机 HealthKit 链路**：本轮 UI 与 Store 测试基于 `PreviewSeedFactory` 确定性预览与内存 SQLite 夹具运行；真实手表记录的力量 `HKWorkout` 与手打 `HKQuantityTypeIdentifierWorkoutEffortScore` / `estimatedWorkoutEffortScore` 在真机上的端到端延迟与体感节奏尚未完成真机实测。
- **端侧 `FoundationModels` 实机推理**：iOS 模拟器不支持 Apple Intelligence 端侧模型，`WorkoutReviewParserClient` 自动记录降级日志并路由至 `ChineseWorkoutLexiconParser`；端侧 `@Generable` 真实响应延迟需后续真机实测补充。

## 6. 今日建议与训练复盘同步修复

本地分支 `codex/ui/ios26-native-bodyseek`，HEAD `ed7ab2c2`，工作树含此前改动。回归以早上快照、当天胸部训练和昨天腿部训练重现旧逻辑。修复前胸部恢复仍为 100%，晨间建议仍显示（`/tmp/bodyseek-workout-red.log`，退出码 `1`）。

- `swift test --package-path BodySeekKit --disable-automatic-resolution` 退出码 `0`，54 项包测试和 12 项 Agent 测试通过。覆盖复盘后即时重算、当天练后建议、延迟到达的旧建议和跨日训练绑定（`/tmp/bodyseek-workout-release-unit.log`）。
- `xcodebuild build -project Vela.xcodeproj -scheme Vela -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /tmp/bodyseek-deploy-20261120 -disableAutomaticPackageResolution -skipMacroValidation -skipPackagePluginValidation` 退出码 `0`（`/tmp/bodyseek-workout-release-build.log`）。
- CoreDevice 安装到 iPhone 16 Pro，安装序列 `1804`，并成功启动。按用户要求跳过模拟器。真机安装和启动已确认，历史标注归属与本次实际胸训的展示未读取核对。

## 7. 新训练到达后的前台刷新

- 基线 `ed7ab2c2`，工作区含既有修改。新增回归先复现已存在训练档案时，新力量训练未进入待复盘列表。单测初次运行退出码 1，日志 `/tmp/bodyseek-nov20-recovery-red.log`。修复后，新跑步参与下肢恢复估算，新力量训练进入待复盘，已有用户复盘结果得以保留。
- HealthKit 快照使用原始参考时刻。新请求替代过时的窗口刷新，缓存与同步回调均合并最新快照里的训练。恢复模型继续使用 `recovery-heuristic-v1`。
- `swift test --package-path BodySeekKit --disable-automatic-resolution` 退出码 0。默认字号的 iPhone 17 Pro / iOS 26.5 上，`testM2WatchFirstReviewInboxMuscleRecoveryAndArchive` 通过。实际 Apple Watch 回流时延待真机验证。
