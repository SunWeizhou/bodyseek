# BodySeek M4d CoreML 端侧推理与 V5 全里程碑终验报告

## 1. 基线与工作区状态

- **分支**：`codex/ui/ios26-native-bodyseek`
- **前置提交 (`HEAD`)**：`f0203f6b`（`[M4B-C][ML] 完成 M4b 滚动回测、M4c Masked TCN/PatchTST-Lite 配对检验与 M4d CoreML 导出管线`）
- **本次提交 (`[M4D][COREML-UI]`) 改动范围**：
  - `BodySeekCore`：`PersonalForecasterEngine.swift`、`NOfOneExperimentModels.swift`、`Resources/BodySeekPersonalForecasterV1.mlpackage`、`Resources/personal_forecaster_v1_spec.json`
  - `BodySeekStore` / `BodySeekHealth`：`BodySeekRepository.loadExperimentPlanItems()` 与 `BodySeekStoreClient.loadExperimentPlanItems`
  - `BodySeekAgent`：`CoachToolRegistry.get_personal_forecast` 只读工具与 `CoachAIClient` 系统提示及预览路由
  - `BodySeekFeatures`：`TrendsFeature`、`TrendsView`、`AppFeature` 接入「明天身体预测」卡片（含「个人统计预测 · 非医学诊断」标注与 80% Split-Conformal 区间）、N-of-1 14 天自实验模板与缺失天严格排除评估器、M4a `.candidate` 统计规律种子与一键确认晋升 `Verified Pattern`
  - 测试：`PersonalForecasterParityTests.swift`（24 组 Golden Vectors 双端对拍与零未来泄漏校验）与 `VelaUITests.testM4DPersonalForecastAndNOfOneExperimentFlow`
- **提交前工作区**：仅上述 9 个已跟踪修改文件与 4 个新增源码/测试/报告文件；无任何 `.parquet`、`.sqlite`、`.venv` 或个人健康导出原文件进入 Git。

---

## 2. 端侧 CoreML × Python 双端对拍与因果不变量

| 校验维度 | 方法与样本 | 实测结果 | 门禁要求 |
|---|---|---|---|
| Python NumPy vs CoreML `.mlpackage` | 导出侧 24 组合成与边界向量 (`run-m4bcd`) | 最大相对误差 `9.40e-08` | `<= 1e-3` |
| Swift `PersonalForecasterEngine` vs NumPy 参考值 | `Bundle.module` 24 组 Golden Vectors | `swift_max_rel_err = 5.72e-08` | `<= 1e-3` |
| Apple `CoreMLPersonalForecaster` 运行时 vs CoreML 参考值 | `MLModel.compileModel` 实跑 `BodySeekPersonalForecasterV1.mlpackage` | `coreml_max_rel_err = 0.00e+00` | `<= 1e-3` |
| 零未来数据泄露与不足样本诚实降级 | 篡改 `t+1` 后指标 / `< 7` 观测日输入 | `vecBefore == vecAfter`；`< 7` 天返回 `.insufficientData` | 严格零泄露、不零填充 |
| N-of-1 实验评估缺失日隔离 | 达标/未达标配对含 `nil` 结局日 | `excludedMissingDays` 精确排除，不作零计 | 禁止把缺失当零 |

---

## 3. 全量验证命令与退出码（均在最终代码定稿后执行）

| 验证项 | 命令 | 退出码 | 实测输出摘要 |
|---|---|---|---|
| Xcode 工程生成 | `/opt/homebrew/bin/xcodegen generate` | `0` | 生成 `Vela.xcodeproj` |
| Python ML 测试 | `/Users/sunweizhou/.local/bin/uv run --project BodySeekML pytest -v` | `0` | `5 passed, 432 warnings in 8.38s`（覆盖率/M4a/M4b/M4c/M4d 导出对拍全部通过） |
| 静态代码门禁 | `grep -rn 'try?' BodySeekKit/Sources/` 等四项门禁 + `git diff --check` | `0` | `TRY_OP=0`, `SPEZI_LLM=0`, `BANNED=0`, `FEATURE_CHARTS=0`, `git diff --check` 零告警 |
| SwiftPM 单测与 Agent 评测 | `swift test --package-path BodySeekKit` | `0` | `BodySeekKitTests`: `49 tests, 0 failures`；`COREML_PARITY_M4D: vectors=24 swift_max_rel_err=5.72e-08 coreml_max_rel_err=0.00e+00`；`PARSER_ACCURACY_M2: 100.0%`；`BENCHMARK_M1_DATA: compute60d=4.81ms compute365d=35.73ms compute1095d=110.93ms horizonSwitch3Y=0.58ms`；`BodySeekAgentEvals`: `9 tests, 0 failures` (`AGENT_EVALS_M3: passed=30/30 rate=100.0% tool_leak=0 provenance_pass=30/30 direct_write_violations=0`) |
| iOS 模拟器集成 + UI 测试 | `xcodebuild test -project Vela.xcodeproj -scheme Vela -destination 'id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987' -parallel-testing-enabled NO -skipMacroValidation -skipPackagePluginValidation` | `0` | `** TEST SUCCEEDED **`；`VelaTests`: `4 tests, 0 failures`；`VelaUITests`: `8 tests, 1 test skipped`（仅截图采集用例因未设置 `BODYSEEK_WALKTHROUGH_DIR` 按预期跳过）, `0 failures`（含 M1–M4d 全部端到端 UI 流程） |
| 真机目标构建与签名 | `xcodebuild -project Vela.xcodeproj -scheme Vela -destination 'generic/platform=iOS' -skipMacroValidation -skipPackagePluginValidation -allowProvisioningUpdates build` | `0` | `** BUILD SUCCEEDED **`；完成 `Vela.app` 编译、签名与校验 |

---

## 4. Blueprint V5 全里程碑完成核对

- **M0 基线加固**：Keychain API Key、零 `try?`、`os_signpost` 冷启动/交互探针、`DailyCheckIn`。
- **M1 数据底座与 Apple 原生重设计**：GRDB 7 本体表 + `ActionExecutor` 单写闸门 + `SleepMergePolicy`；零 `Liveline` / `SleepChartKit`，8 个自研 Swift Charts 交互图表组件、五项详情页、3 年跨度、`每日营养素` 记录与能量平衡周/月看板。
- **M2 Watch-First 训练引擎**：18 项肌群启发式恢复模型、中文自然语言训练解析（55 样本 100%）、Watch 未复盘收件箱与一句话快速标注闭环。
- **M3 原生 Agent 与三层记忆**：移除 `SpeziLLM` / OpenAPI 生成层，自研 SSE 流式工具循环、9 个只读/提案工具、`NumericProvenanceVerifier` 数值溯源、Confirm-to-Write、三层记忆生命周期、主动洞察与外发隐私预览。
- **M4a–M4d 个人建模闭环**：3 年导出 1,510 天无偏解析与 FDR 多重检验、M4b 月度滚动回测、M4c `MaskedTCN` / `PatchTSTLite` 配对检验（基于诚实统计显著性门禁保留低方差正则化架构上机）、端侧 `.mlpackage` CoreML 推理与 N-of-1 自实验对照闭环。

---

## 5. 未覆盖风险与声明

- 真机 Apple Watch / HealthKit 现场长窗口历史增量拉取与后台投递未在本机自动化中接入真实佩戴硬件，需真机安装后授权验证。
- 云端 DeepSeek/OpenAI 实时网络延迟与配额依赖用户自行配置 API Key（`OpenAICompatibleClient` 已通过本地 SSE fixture 与 HTTP 429/timeout 重试测试验证）。
- 所有 M4a 统计规律、M4d 预测区间与 N-of-1 自实验均值差均已标注「非医学诊断 / 非临床因果结论」。
