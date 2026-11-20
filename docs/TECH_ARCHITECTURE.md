# BodySeek (Vela) Technical Architecture Specification

> Status: Canonical
> Last verified: 2026-11-19
> Scope: BodySeek V5 工程架构、模块依赖 DAG、HealthKit 同步、GRDB 持久化、计算与体验分层规范
> Authoritative ADRs: [ADR 0019](adr/0019-bodyseek-v5-architecture-and-modeling-baseline.md)（架构与建模基线）、[ADR 0018](adr/0018-ios26-native-architecture-and-bevel-visual-reset.md)（iOS 26 原生导航与五域视觉）
> Does not define: 业务需求与产品边界（见 [docs/PRD.md](PRD.md)）、领域术语（见 [../CONTEXT.md](../CONTEXT.md)）

> 说明：2026-11-16 起仓库已从旧 `BodySeekDomain/` + 手写 `VelaApp/` + `VelaWatch/` 迁移为本地 Swift 6 Package `BodySeekKit`（TCA + `SpeziHealthKit`）与薄壳 `VelaApp/App/VelaApp.swift`。旧版 32 模型 SwiftData 与 `BodySeekDomain` 说明均已由 ADR 0019 取代；本文件随 M0–M4 逐步实现持续同步状态。

---

## 1. 架构总览与技术栈

- **平台**: iOS 26.0+（`IPHONEOS_DEPLOYMENT_TARGET = 26.0`）。CI 工具链严格匹配 `.xcode-version`（当前 26.5.0）；本机验证环境可为更新版本（当前 Xcode 27.1 / Swift 6.4），报告必须注明实际工具链，固定版本判定以 CI 为准。Watch 端由系统“体能训练”App 采集（无独立 `VelaWatch` target）。
- **对外产品名**: BodySeek（仓库、Xcode 工程、Bundle ID `com.sunweizhou.Vela4` 与内部日志子系统保持 Vela 约定）。
- **架构核心**: Point-Free TCA（`swift-composable-architecture` + `swift-dependencies`）+ `StanfordSpezi/SpeziHealthKit` + **GRDB 7**（M1 引入）+ **原生 `Swift Charts`**（M1-UI 全量替代 `Liveline`）+ **`BodySeekML/`** 离线 Python 建模实验室。
- **状态与性能原则**:
  - 启动首屏只读本地持久化快照，不阻塞等待 HealthKit 全量回填；
  - `DayKey` 采用本地时区凌晨 `04:00` 切日，配合 UTC 时间戳与源时区；
  - 持久化、Keychain、HealthKit、网络与模型调用禁止静默 `try?`，全部采用结构化错误传播与 `os.Logger` 诊断日志。
- **安全与凭据**: 云端 LLM（默认 DeepSeek）API Key 严格存储在 iOS Keychain（`com.sunweizhou.Vela4`），永不回落到 `UserDefaults`。

---

## 2. 模块依赖拓扑（单向无环 DAG）

按需求增量拆分，禁止预建空包：

```text
VelaApp (Thin iOS 26 Entry Shell + Assets + Entitlements)
  └── BodySeekFeatures (TCA Reducers + L1/L2/L3 Views, ViewState snapshots only)
        ├── BodySeekDesign   (M1-UI split: Tokens + BodySeekChart Swift Charts family)
        ├── BodySeekAgent    (M3 split: OpenAICompatibleClient + FoundationModels + Tools + Memory + Evals)
        ├── BodySeekStore    (M1-Data split: GRDB 7 + DatabaseMigrator + ReadModels + ActionAuditLog)
        ├── BodySeekHealth   (SpeziHealthKit SyncEngine + 3y Backfill + sleepMergePolicy + KeychainService)
        └── BodySeekCore     (Pure Foundation: Contracts, score-v2 BevelScoringEngine, Baselines, recovery-heuristic-v1, feature_spec)
```

---

## 3. 分层规范与数据流管道

### 3.1 合同与真值边界（`BodySeekCore/Contracts.swift`）
- **`DayKey`**：本地 `04:00` 生理日标识（`YYYY-MM-DD`），前向/后向跨午夜夜生活与晚睡归属同一生理日。
- **`HealthObservation<Value>`**：`available(Value, Provenance)`、`knownZero(reason, Provenance)`、`missing(MissingReason)`、`excluded(ExclusionReason, Provenance)` 四态贯穿采集 → 存储 → 评分 → UI → Agent 工具 → ML 缺失掩码（命名避开 Apple `Observation` 系统模块冲突）。
- **`AlgorithmVersion`**：每个评分、合并、恢复、解析和 ML 工件均携带版本标识（`score-v2`、`recovery-heuristic-v1`、`sleep-merge-v1`、`workout-parser-v1`）。
- **`ActionProposal`**：所有由 Agent 或解析器生成的写入（`annotateWorkout`、`commitMemory`、`retireMemory`、`adjustPlan`、`recordCheckIn`）必须先产出结构化提案，经用户确认后进入审计日志并生效。

### 3.2 采集与持久化（M0 现状 → M1-Data GRDB 演进）
- **HealthKit 采集（`SpeziHealthKit` + `SyncEngine`）**：
  - M0 现状：通过 `SpeziHealthKitFetcher` 查询 60 天聚合、睡眠切分、训练与心率分区；
  - M1-Data 目标：`HKAnchoredObjectQuery`（anchor 持久化）+ 3 年分月可续传回填，补齐 `PhysicalEffort`、`AppleSleepingWristTemperature`、`WalkingHeartRateAverage`、`VO2Max`、`HeartRateRecoveryOneMinute` 并严格区分用户 `WorkoutEffortScore` 与系统 `EstimatedWorkoutEffortScore`；建立 `sleepMergePolicy`（Apple Watch > AutoSleep > iPhone）；变更 3 秒防抖且内容哈希一致时不重发 UI 刷新。
- **本地持久化**：
  - M0 过渡：`FitnessStoreClient` 暂用 4 个 `@Model` SwiftData 容器 + `PreferencesClient`（JSON 存储 `DailyCheckIn` 每日打卡与 `dominantHand`），并清除了全部静默 `try?`；
  - M1-Data 目标：整体迁移至 **GRDB 7**（`day_metric`、`hourly_metric`、`sleep_episode`、`workout`、`workout_annotation`、`workout_muscle_load`、`score_snapshot`、`muscle_recovery`、`check_in`、`plan_item`、`memory`、`action_audit`、`coach_message`、`pattern_finding`），原始高频心率留存在 HealthKit 不作全量镜像。

### 3.3 计算层（`BodySeekCore`）
- **五项评分 `score-v2`（`BevelScoringEngine`）**：
  - 使用严格不含当日与未来日的 28 天滚动中位基线（零未来数据泄露）；
  - 输出 Recovery、Sleep、Strain、Stress、Energy 五项独立 `0–100` 评分，附带 `AlgorithmVersion` 与结构化 `MetricContributor` 列表；
  - 详细分布比对见 `docs/validation/m0-score-v1-vs-v2-replay-2026-11-19.md` 与 `docs/model_cards/`。
- **动态肌群恢复 `recovery-heuristic-v1`（M2 上线）**：
  - 累计疲劳 $F_m(t) = \sum_i L_{m,i}\exp(-(t-t_i)/(\tau_m \cdot \alpha))$，恢复度 $R_m = \exp(-F_m)$；
  - $\alpha$ 仅读取**前一晚**睡眠与 HRV 基线偏离，不读取当天恢复分。

### 3.4 体验与 Agent 层（M1-UI / M2 / M3）
- **一级导航**：`今日`（五项读数与今日行动卡 + `DailyCheckIn` 打卡）、`健身`（Watch-First 待复盘 Inbox + 肌群恢复热图 + ACWR 轮转）、`营养`（餐次、AI 记饮食草稿与周/月看板）、`趋势`（7d/30d/6m/3y + 我的规律 + N-of-1 实验）、尾部 `.search` 入口的 `Coach`。
- **图表规范**：M1-UI 起在 `docs/design/chart-grammar.md` 下以统一组件族 `BodySeekChart`（纯 Apple `Swift Charts`）重构全部图表，选中态隔离在局部 `@State`，性能埋点由 `PerformanceSignposts` (`os_signpost`) 追踪并在 iPhone 16 Pro Release 包验证。
- **Coach Agent**：M3 移除 `SpeziLLM` 与 OpenAPI 生成链，使用自研轻量 `OpenAICompatibleClient` + 端侧 `FoundationModels`、任务型工具、`find_similar_days` 历史相似日、数字溯源后置核验与 30 题评测集 `BodySeekAgentEvals`。
- **个人建模（`BodySeekML/`）**：Mac 本地 Python (`uv`) 基于 Walk-Forward 时间序列切分先评测 Persistence / Ridge / Banister / LightGBM 基线，再研究 Masked TCN / PatchTST-Lite，通过显著性检验并完成双端特征一致性测试后以 Core ML 上机。
