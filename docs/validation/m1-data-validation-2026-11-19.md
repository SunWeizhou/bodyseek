# BodySeek M1-Data 验证报告（2026-11-19）

- 分支：`codex/ui/ios26-native-bodyseek`
- 关联基线提交：
  - M0 性能基线：`a9f32e64`
  - M0-7 每日主观 Check-in：`07a7e859`
  - M1D-1 GRDB 7 Store + Core 契约 + SleepMergePolicy + O(N) 滑窗：`c76edda9`
  - M1D-2 SyncEngine + HealthKit 后台传递与扩展信号：`759e28a4`
  - M1D-3 ReadModel + SHA256 去重 + Trends 预计算 + 每日营养素 v2 数据层：待提交（本文档记录本次验证结果）
- 环境：Apple M5 Pro / Xcode 27.1 (`27A9275`) / Swift 6.4 / iPhone 17 Pro 模拟器 (`3BB779BD-022F-4E60-A3BB-70DC5A0BF987`)

## 1. M1-Data 交付范围摘要

1. **GRDB 7 (`BodySeekStore`) 持久化与迁移 (`c76edda9` / M1D-3)**
   - Schema `v1_initial_schema`：建立 15 张 V5 业务表、连续性状态表，以及面向动作/伤病标签与长记忆的 `trigram` FTS5 索引与触发器（`memory_fts`、`workout_annotation_fts`，对 1–2 字 CJK/ASCII 查询自动回退 `LIKE ... ESCAPE '\'`）。
   - Schema `v2_nutrition_schema`：落地`每日营养素`数据层 5 张表（`nutrition_profile`、`nutrition_target_plan`、`food_library_item`、`daily_nutrition_log`、`meal_entry`）及 `food_library_fts` trigram 检索。
   - `BodySeekDatabase` 采用 WAL 模式 `DatabasePool`；`LegacyDataImporter` 与 `FitnessStoreClient.exportLegacyPayloadIfStoreExists()` 仅在旧 SwiftData store 真实存在时单向迁移，避免新建空 SwiftData store。
   - `BodySeekRepository` 在 `saveDailyRawMetrics` / `upsertDayMetrics` 中调用 `invalidateComputedArtifactsSync`，防止原始日指标更新与分数重算分离写入时出现中间态旧分读取。
   - `ActionExecutor` 以数据库事务执行 `.recordCheckIn` 与 4 个营养动作（`.upsertNutritionProfile`、`.commitNutritionTargets`、`.logNutritionMeal`、`.closeNutritionDay`）并保留完整审计记录。

2. **增量计算、睡眠合并与图序列契约 (`c76edda9` / M1D-3)**
   - `SleepMergePolicy`（`sleep-merge-v1`）与 `RawSleepSampleStage`；`DayKey.fromCalendarDay` / `calendarDayStart` 对齐自然日语义。
   - `TrendHorizon.threeYears.dayCount = 1095` 及 `usesRangeCapsules`。
   - `BevelScoringEngine.computeWindow` 优化为 $O(N)$ 双指针 28 日滑窗，并补充 `recomputeIncremental`、`buildAllChartSnapshots`、`buildChartSeriesSnapshot`。
   - `BodySeekReadModel` 通过 `ValueObservation.tracking` + `CryptoKit.SHA256` `contentDigest` 去重，避免无效 UI 刷新。

3. **HealthKit 后台传递与可恢复历史回填 (`759e28a4`)**
   - `VelaApp/App/Vela.entitlements` 启用 `com.apple.developer.healthkit.background-delivery = true`。
   - `BodySeekStandard.RequestReadAccess` 增补 `.estimatedWorkoutEffortScore`、`.physicalEffort`、`.walkingHeartRateAverage`、`.vo2Max`、`.heartRateRecoveryOneMinute`、`.bodyMass`；`SpeziHealthKitFetcher` 增加 `.badminton` 显示映射。
   - `SyncEngine` + `LiveHealthKitSyncSource` 实现 30 天锚点增量同步、3 秒防抖、可恢复 36 个月历史回填（低电量模式 / 热节流时暂停），窗口手腕温度中位数，以及用户主观用力 `effortUser` 与系统估算 `effortEstimated` 分离。

4. **每日营养素领域模型与 TCA 接线 (M1D-3)**
   - `NutritionModels.swift`：`NutritionCatalog`（8 项宏量/核心指标、14 种维生素、15 种矿物质、7 个 MEXT 基础食物模板）、`NutritionProfile`、`NutritionTargetPlan`、`NutritionTargetEvaluator`（四状态：`met` `#4A9D72`、`low` `#D79939`、`over` `#D65C5C`、`unknown` `#8A9099`；坚持 `missingAsZero == false`）、`MealEntry`、`DailyNutritionLog`、`NutritionBoardAggregator`（仅在 `dietDayComplete == true && bmrKcalUsed > 0 && sportKcal >= 0` 时计算 `calorieSurplusKcal`）与 `NutritionMarkdownExporter`。
   - `BodySeekStoreClient` 为 `testValue` 每次构建隔离内存库；`TrendsFeature` 改为预计算并缓存 `chartCache` / `activeChartSnapshot` / `allMetricSnapshots` / `activeSeries` / `allMetricSeries`；`AppFeature` 启动优先加载 GRDB 缓存快照、后台无阻塞同步/回填并在 `checkInSaved` 触发 `.recordCheckIn` 审计写入。

## 2. 性能对比基准（M0 vs M1-Data）

测试平台：Apple M5 Pro，数据来源：`PerformanceBaselineTests`（记录 `BENCHMARK_M1_DATA` 指标及 `BodySeekSignposts`：`AppColdStartToFirstFrame`、`HealthKitWindowFetch`、`ScoringComputeWindow`、`TrendsSeriesCompute`、`TabSwitch`、`ChartScrub`）。

| 指标 | M0 Debug | M1-Data Debug | M0 Release | M1-Data Release | 目标/说明 |
|---|---:|---:|---:|---:|---|
| `compute60d` | 6.38 ms | 4.81 ms | 4.37 ms | 2.59 ms | 保持高效 |
| `compute365d` | 100.78 ms | 34.82 ms | 70.20 ms | 14.97 ms | 28d 双指针滑窗优化 |
| `compute1095d` | 706.38 ms | 107.02 ms | 540.43 ms | 38.81 ms | 真实 3 年 O(N) 窗口 |
| `horizonSwitch3Y` (1095d) | — | 0.55 ms | — | 0.25 ms | 远低于 `< 150 ms` V5 预算 |
| `trendsScrub60xMonth` | 159.76 ms | 0.08 ms | 92.05 ms | 0.10 ms | Trends scrub O(1) 缓存命中 |
| `trendsScrub60x3Y` | 676.61 ms (365d) | 0.05 ms (1095d) | 300.45 ms (365d) | 0.02 ms (1095d) | 远低于 `< 50 ms` 预算 |

## 3. 验证命令与实测结果

在提交 M1D-3 前针对最终代码树执行全部 6 项门禁，退出码均为 `0`：

1. `grep -rn "try?" BodySeekKit/Sources/`
   - 结果：`0` 处匹配（零隐式吞错）。
2. `swift test --package-path BodySeekKit`（Debug）
   - 结果：**34/34 通过**（耗时 `1.225s`），涵盖 9 个测试集：
     - `AppAndTodayFeatureTests` (3/3)
     - `BevelScoringEngineTests` (7/7)
     - `BodySeekStoreTests` (6/6)
     - `ContractsTests` (5/5)
     - `NutritionEngineTests` (3/3)
     - `PerformanceBaselineTests` (1/1)
     - `SecurityAndReliabilityTests` (3/3)
     - `SyncEngineTests` (3/3)
     - `WorkoutAndCoachReducerTests` (3/3)
   - 输出：`BENCHMARK_M1_DATA: compute60d=4.81ms compute365d=34.82ms compute1095d=107.02ms horizonSwitch3Y=0.55ms trendsScrub60xMonth=0.08ms trendsScrub60x3Y=0.05ms`
3. `swift test -c release --package-path BodySeekKit --filter PerformanceBaselineTests`（Release）
   - 结果：**1/1 通过**（耗时 `0.122s`）
   - 输出：`BENCHMARK_M1_DATA: compute60d=2.59ms compute365d=14.97ms compute1095d=38.81ms horizonSwitch3Y=0.25ms trendsScrub60xMonth=0.10ms trendsScrub60x3Y=0.02ms`
4. `xcodebuild test -project Vela.xcodeproj -scheme Vela -destination 'id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987' -parallel-testing-enabled NO -skipMacroValidation -skipPackagePluginValidation`
   - 结果：`** TEST SUCCEEDED **`
     - `VelaTests`：**4/4 通过**
     - `VelaUITests`：**3 通过 / 1 跳过 / 0 失败**（`testCaptureLightAndDarkScreenshotsWhenRequested` 因未设置 `BODYSEEK_WALKTHROUGH_DIR` 跳过）
5. `xcodebuild -project Vela.xcodeproj -scheme Vela -destination 'generic/platform=iOS' -skipMacroValidation -skipPackagePluginValidation -allowProvisioningUpdates build`
   - 结果：`** BUILD SUCCEEDED **`
6. `git diff --check`
   - 结果：退出码 `0`（无空白或冲突标记错误）。

## 4. 未验证风险与下一阶段依赖

- **真机硬件未测项**：HealthKit 后台传递实际唤醒频率、以及真实物理设备（`iPhone 16 Pro` + `Apple Watch`）上 3 年全量回填的耗电与 Release Instruments trace 尚待后续授权真机联调确认。
- **下一阶段入口**：进入 **M1-UI**（建立 `BodySeekDesign` 与自研 `BodySeekChart` 替换 `liveline-swift`、落盘 `chart-grammar.md`、精修 5 项详情页与 Today 动作卡、实现`每日营养素`周/月圆圈看板与餐次/目标交互）及 **M4a**（基于 `/Users/sunweizhou/Downloads/导出.zip` 的真实 3 年 HealthKit 导出离线特征表与延迟关联分析）。
