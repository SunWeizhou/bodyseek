# M0 `os_signpost` Instrumentation & Pre-M1 Performance Baseline Report

- **日期**: 2026-11-19
- **分支 / 基线**: `codex/ui/ios26-native-bodyseek`（在 `54a95cc9` 之上）
- **测试硬件与工具链**: Apple M5 Pro (`24 GB RAM`) · Xcode 27.1 (`27A9275`) · Swift 6.4 · 模拟器 `iPhone 17 Pro` (`id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987`)

---

## 一、`os_signpost` 埋点清单

`OSSignposter` 统一注册在 `BodySeekKit/Sources/BodySeekCore/PerformanceSignposts.swift`（`subsystem: "com.sunweizhou.Vela4"`, `category: "Performance"`）：

| Signpost 名称 | 埋点位置 | 用途 |
| :--- | :--- | :--- |
| `AppColdStartToFirstFrame` | `AppFeature`（`.onAppear` → 首次 `.snapshotLoaded`） | 度量启动后到首屏数据就绪的阻塞窗口 |
| `HealthKitWindowFetch` | `SpeziHealthKitFetcher.fetchWindow(...)` | 度量 HealthKit 统计/样本并发查询与睡眠切分耗时 |
| `ScoringComputeWindow` | `BevelScoringEngine.computeWindow(...)` | 度量全窗口历史滚动基线与每日五项评分计算耗时 |
| `TrendsSeriesCompute` | `BevelScoringEngine.trendSeries(...)` | 度量单指标时间序列生成与分位数统计耗时 |
| `TabSwitch` | `AppFeature`（`.tabSelected` emitEvent） | 标记 `今日 / 健身 / 趋势 / 问身体` 切页事件 |
| `ChartScrub` | `BevelComponents` 图表拖拽回调 emitEvent | 标记趋势图/双轴图十字准星拖拽选点触发点 |

*(注：本轮已在真机模拟器编译中同步修复 `SpeziHealthKitFetcher.runLogged` 在 Swift 6.4 `#if os(iOS)` 下 `healthKit.query(.heartRate, ...)` 的泛型推断编译问题。)*

---

## 二、M0 量化性能基线测试结果

### 1. Core 算法与 Trends 拖拽重算开销（`BodySeekKitTests.PerformanceBaselineTests`）

| 基准项 | Debug 构建耗时 | Release 构建耗时 | 观察结论（Pre-M1 瓶颈实证） |
| :--- | :---: | :---: | :--- |
| `BevelScoringEngine.computeWindow(days: 60)` (`58` 有效天) | `6.38 ms` | `4.37 ms` | 短窗口尚可，但每次 `healthUpdateTick` 全量触发 |
| `computeWindow(days: 365)` (`363` 有效天) | `100.78 ms` | `70.20 ms` | 随天数呈 **$O(N^2)$** 增长（每日遍历 `sorted.filter` 匹配 28d 窗） |
| `computeWindow(days: 1095)` (`1093` 有效天，3 年全量) | `706.38 ms` | `540.43 ms` | **冷启动若全算 3 年将超 500 ms**；M1 必须改为读 GRDB 快照 + 仅增量重算脏天 |
| `TrendsFeature` 60 次拖拽读取 `activeSeries + allMetricSeries` (`30天`窗) | `159.76 ms` (`2.66 ms/次`) | `92.05 ms` (`1.53 ms/次`) | 每次 hover 改动无谓重算全部 5 项+主图共 **6 遍**序列 |
| `TrendsFeature` 60 次拖拽读取 `activeSeries + allMetricSeries` (`3年`窗) | **`676.61 ms` (`11.28 ms/次`)** | **`300.45 ms` (`5.01 ms/次`)** | Debug 下单次拖拽已超 120Hz `8.33ms` 帧预算，Release 下占满半帧且叠加 7 个 `Liveline` Canvas 重绘，直接导致用户体感卡顿 |

### 2. Build & Automated Suite Gate

| 验证命令 | 退出码 | 结果 |
| :--- | :---: | :--- |
| `swift test --package-path BodySeekKit` (Debug) | `0` | **19 / 19 passed** (`1.773s`) |
| `swift test -c release --package-path BodySeekKit --filter PerformanceBaselineTests` | `0` | **1 / 1 passed** (`1.019s`, Release clean build `119.10s`，含 `SpeziLLM` / `OpenAPIGenerator`) |
| `xcodebuild test -project Vela.xcodeproj -scheme Vela -destination 'id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987' -parallel-testing-enabled NO -skipMacroValidation -skipPackagePluginValidation` | `0` | **VelaTests: 4 / 4 passed** (`0.075s`); **VelaUITests: 2 passed, 1 skipped** (`33.190s`; `testCaptureLightAndDarkScreenshotsWhenRequested` 因未设 `BODYSEEK_WALKTHROUGH_DIR` 按预期 `XCTSkip`) |

---

## 三、已核实的 Pre-M1 架构瓶颈总结

1. **`BevelScoringEngine.computeWindow` 的 $O(N^2)$ 滚动过滤**：3 年 1,095 天在 M5 Pro Release 上即耗时 `540 ms`，在 iPhone 端会明显更慢且阻塞冷启动与后台更新。
2. **`TrendsFeature.State` 无缓存计算属性 + 拖拽走 Reducer 重渲染**：每次手势滑动触发 `activeSeries` + `allMetricSeries`（6 次 `trendSeries` 计算），在 3 年窗上直接占用 `5–11 ms/次`。
3. **重编译链路**：Release 从零构建耗时 `119.10s`，主要由 `SpeziLLM` 拉入的 `swift-openapi-generator` 与未使用的 `mlx-swift` 贡献（M3 移除 `SpeziLLM` 将显著减重）。

---

## 四、未验证边界声明（重要）

- **真实 iPhone 16 Pro Release 包 Instruments（`SwiftUI` / `Hitches` / `Time Profiler`）Trace 尚未采集**：遵守 V5 §14 第 5 条，未获用户当次明确真机部署授权前不执行 `devicectl` 安装与真机 trace；真机实测门禁保留给 M1 完成后经用户授权执行，目标指标遵循 V5 §7.4（冷启动首有效帧 `≤ 400 ms`、Tab 切换 `≤ 100 ms` 无 hitch、拖动与滚动 `hitch time ratio < 5 ms/s`、`3y` 切换 `≤ 150 ms`）。
