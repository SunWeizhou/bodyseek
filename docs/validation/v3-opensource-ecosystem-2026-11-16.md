# BodySeek V3 开源生态与智能体系统升级验证报告

- **日期**: 2026-11-16
- **当前分支**: `codex/ui/ios26-native-bodyseek`
- **基准 `HEAD` 提交**: `f5271882a683a82ca998a272c8840dc41d107742`（工作区包含 V2/V3 重构本地改动，未提交/未推送）
- **核心架构升级摘要**:
  - **四标签结构重组**: 放弃静态「计划」标签，升级为 `今日` · `健身` · `趋势` · `问身体`（`.search` 独立液态玻璃气泡）。
  - **开源视觉与交互生态**:
    - `melihcolpan/MuscleMap` (`1.9.0`, MIT): 36 肌群解剖正/背面交互热图，基于近 72 小时力量训练负荷染色与按部位筛选动作库 (`ExerciseCatalog` 19 项双语动作，对齐 `free-exercise-db` 分类)。
    - `DanielJamesTronca/SleepChartKit` (`1.2.0`, MIT): Apple Health 风格分期阶梯睡眠时间线 (`SleepStageTimelineView`)。
    - iOS 26 原生图表与微交互: `MeshGradient` (`BevelAmbientAura`)、24 小时离散 `StressHeatmapChart`、昼夜电量波形 `EnergyBatteryCurveChart`、`DualAxisLoadRecoveryChart`（负荷柱形 × 恢复折线 + `ACWR 0.8–1.3` 甜蜜区卡片）、`.contentTransition(.numericText())`、`.navigationTransition(.zoom)`（`@Namespace` 从 `TodayView`/`TrendsView` 贯通到 `MetricDetailView`）、`.sensoryFeedback(.selection, trigger:)`。
  - **双引擎真 AI 智能体与工具链**:
    - 云端 OpenAI 兼容协议由 `StanfordSpezi/SpeziLLM` (`0.13.8`, `SpeziLLMOpenAI`, `swift-openapi-generator 1.12.2`, `swift-openapi-runtime 1.13.4`) 驱动（默认端点 `https://api.deepseek.com/v1`，通过 `DynamicServerURLMiddleware` 注入），端侧优先使用 Apple `FoundationModels` (`SystemLanguageModel.default`)。
    - 注册真实工具回调：`query_physiology_and_training`、`save_athlete_memory`、`search_exercise_catalog`、`propose_adapted_workout`，移除任何硬编码规则话术兜底。
  - **精简 SwiftData 模型 + 手表联动替代独立 Watch Target**:
    - `BodySeekSwiftDataBackend` 仅保留 4 个持久化 `@Model`：`StoredWorkoutTemplate`、`StoredWorkoutSession`、`StoredAthleteMemory`、`StoredCoachMessage`（偏好与主观感受使用原子 JSON `PreferencesClient`）。
    - 利用 `SpeziHealthKit` 提取手表训练的 5 区间心率停留 (`Z1–Z5` / TRIMP) 与 iOS `HKWorkoutEffortScore`，并在力量训练完成时使用 `HKWorkoutBuilder` 写回 Apple 健康（带 `NSHealthUpdateUsageDescription`），组间休息结束触发 `UNUserNotificationCenter` 通知镜像到手表。

## 自动化验证与真机签名检查结果

| 验证项 | 执行命令 / 目标 | 结果 | 退出码 | 说明 |
| --- | --- | --- | --- | --- |
| Swift Package 单元测试 (`BodySeekKitTests`) | `swift test --package-path BodySeekKit` | **10 / 10 passed** (`0.422s`) | `0` | 覆盖 `BevelScoringEngineTests` (含 ACWR、11点能量轨迹、12段压力节律、零未来数据泄露)、`WorkoutAndCoachReducerTests`（含 SwiftData 错误显式暴露）、`AppAndTodayFeatureTests` |
| iOS 主工程单元测试 + 全流程 UI 回归 (`iPhone 17 Pro` iOS 26.5 浅色模式) | `TEST_RUNNER_BODYSEEK_WALKTHROUGH_DIR=... xcodebuild -project Vela.xcodeproj -scheme Vela -destination 'id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987' -skipMacroValidation -skipPackagePluginValidation test` | **VelaTests (4 tests) + VelaUITests (3 tests) 全部通过** | `0` | 生成 7 张浅色全流程截图 (`01-today-top.png` .. `07-trends.png`) 并逐张目视检查 |
| 深色模式 UI 截图走查 (`iPhone 17 Pro` iOS 26.5 Dark Mode) | `xcrun simctl ui ... appearance dark && xcodebuild ... -only-testing:VelaUITests/BodySeekUITests/testCaptureLightAndDarkScreenshotsWhenRequested test` | **1 / 1 passed** (`34.528s`) | `0` | 生成 7 张深色截图 (`v3-dark/01` .. `07`) 并逐张核对暗黑表面对比度与字体可读性 |
| 后端服务测试 (`VelaBackend`) | `swift test --package-path VelaBackend` | **3 / 3 passed** | `0` | `AppTests.PromptServiceTests` |
| 真机架构签名构建 (`generic/platform=iOS`) | `xcodebuild -project Vela.xcodeproj -scheme Vela -destination 'generic/platform=iOS' -skipMacroValidation -skipPackagePluginValidation -allowProvisioningUpdates build` | `** BUILD SUCCEEDED **` | `0` | 签名证书 `Apple Development: 2973815845@qq.com (FHC2HKZ288)`，Bundle ID `com.sunweizhou.Vela4` |
| 补丁卫生检查 | `git diff --check` | Clean | `0` | 无尾随空白、无冲突标记 |

## 未验证边界与后续说明

1. **物理真机安装与实时 HealthKit/Watch 数据链**: 本次验证期间执行 `xcrun devicectl list devices` 显示 `Joe’s iPhone`（`00008140-00164DE022C3801C`, `iPhone 16 Pro`）状态为 `unavailable`（未连线或已锁定断开），因此尚未将 V3 包推入物理机实测；签名真机构建已通过，待设备重连后可直接执行 `xcrun devicectl device install app` 安装验证真实 HealthKit 读/写授权、Apple Watch 实时 `HKWorkoutEffortScore` / `Z1–Z5` 心率样本提取与 `FoundationModels` 端侧推理响应质量。
2. **真机外部网络 AI 调用**: 模拟器自动化测试采用确定性 `-velaPreviewDashboard` 工具夹具覆盖 UI 状态闭环，真实 DeepSeek 云端 Tool-Calling 与端侧 `FoundationModels` 需在真机填写真实 Key 或在支持 Apple 智能的机型交互触发验证。
