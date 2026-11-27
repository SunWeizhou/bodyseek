# BodySeek M1-UI 验证报告（2026-11-20）

最新补充验证见[餐食草稿、证据合同与同步回归](m3-agent-validation-2026-11-20.md#6-餐食草稿证据合同与同步回归)。

- 分支：`codex/ui/ios26-native-bodyseek`
- 关联提交：
  - Phase A（`[M1-UI][DESIGN]`）：`0bbf6ce8`（`BodySeekDesign` 拆分、`docs/design/chart-grammar.md`、`BodySeekChart` 8 类原生组件族、移除 `liveline-swift`）
  - Phase B（`[M1-UI][VIEWS]`）：`3f34382a`（今日行动卡、五项详情、趋势胶囊与营养看板）
- 环境：Apple M5 Pro / Xcode 27.1 (`27A9275`) / Swift 6.4 / iPhone 17 Pro 模拟器 (`3BB779BD-022F-4E60-A3BB-70DC5A0BF987`)；CI 固定工具链为 `.xcode-version` 26.5.0，本机 27.1 结果用于模拟器走查，固定版本判定以 GitHub Actions 为准

## 1. M1-UI 交付范围摘要

1. **Phase A：设计系统独立与原生 `BodySeekChart` 组件族 (`0bbf6ce8`)**
   - 依据 `docs/design/chart-grammar.md` 拆分独立模块 `BodySeekDesign`（在 `BodySeekKit/Package.swift` 与 `project.yml` 挂载，重新生成 `Vela.xcodeproj`）。
   - 移除第三方包装 `liveline-swift`，同步清除 `BevelAmbientAura` 的常驻 `.repeatForever` 循环动画。`SleepChartKit` 于当晚 `6b207556` 因睡眠摘要复用重新引入（仅 `BodySeekDesign`，见文末补记）。
   - 在 `BodySeekKit/Sources/BodySeekDesign/Charts/` 构建 8 类原生图表组件：`TrendLineChart`、`RangeCapsuleChart`、`SleepStageChart`、`IntradayBarChart`、`EnergyAreaChart`、`LoadRecoveryComboChart`、`ZoneBar`、`MiniSparkline`，统一通过 `ChartAxisSupport` 显式计算最多 4 个起止对称 X 轴刻度，并落实四态真值（`available` / `knownZero` / `missing` 真实断线 / `excluded` 斜纹带）、`BodySeekMotion.standard` 与 `AXChartDescriptorRepresentable` 无障碍支持。
   - 在 `BodySeekKit/Tests/BodySeekKitTests/BodySeekChartTests.swift` 增加 48 组 `ImageRenderer` 矩阵测试（8 类图表 × `{normal, sparse, empty, extreme, ax5, dark}`）及架构边界静态扫描。

2. **Phase B：今日行动卡、五项专属详情页、趋势 3 年胶囊与每日营养素看板**
   - **Core 与行动计划生成 (`TodayActionEngine.swift`, `ChartContracts.swift`)**：新增 `VitalSparkPoint`、`TodayActionItem`、`PlanItemRecord` 编解码扩展、`TodayActionGenerator.generateDefaultPlanItems`（确定性生理规则生成，绝不使用未来数据或模型幻觉）及 `NutritionPlanFactory`（Mifflin-St Jeor BMR 估算、DRIs 2023 目标计划校验构造与 7 日预览日志构造）。
   - **今日页 (`TodayFeature`, `TodayView`)**：采用 `LazyVStack` 与预计算 `recentHRVSeries` / `recentRHRSeries` / `recentRespiratorySeries` / `recentSpO2Series`；新增 `today-action-card`（一键「采纳」/「跳过」并经 `ActionExecutor.adjustPlan` 持久化与写入审计日志）、`today-nutrition-card`（展示今日已记热量、近 7 日日均能量缺口、四态圆圈速览）以及工具栏 `+` 菜单入口「记录饮食与营养」。
   - **五项专属详情页 (`Views/MetricDetails/*`, `MetricDetailView`, `MetricDetailFeature`)**：使用 Trends 预计算 O(1) `chartCache`，针对 5 项生理指标提供定制布局：
     - `RecoveryDetailView`：HRV & RHR 趋势 + 28 天体征偏离基线对比 + 归因明细；
     - `SleepDetailView`：原生阶梯 `SleepStageChart` + 阶段构成占比条 + 14 天入睡规律性与 7 天睡眠债分析；
     - `StrainDetailView`：ACWR 甜蜜区间仪表盘 + 锻炼列表（区分 `effortUser` 与 `effortEstimated`、展示 `ZoneBar` 与 `TRIMP`）；
     - `StressDetailView`：可交互 24 小时 `IntradayBarChart`（含运动窗口斜纹排除标注）+ 压力分档统计胶囊；
     - `EnergyDetailView`：可交互 `EnergyAreaChart` + 昼夜充放电关键事件列表；
     - 底部统一保留 L3 数据溯源与算法边界卡片（版本、覆盖度、04:00 日切点、来源、缺口原因）。
   - **趋势页 (`TrendsFeature`, `TrendsView`)**：`LazyVStack` 布局、`horizonPills(selected:)` 选中态独立刷新、`6个月（周胶囊）/ 3年（月胶囊）` 自动切换 `RangeCapsuleChart`、「恢复 × 负荷演化对照」`LoadRecoveryComboChart`、以及「我的规律」卡片（`trends-patterns-card`）。
   - **每日营养素原生看板 (`NutritionFeature`, `NutritionBoardView`, `NutritionSheets`)**：从 Today 卡片及 `+` 菜单以独立 `.sheet`（内嵌 `NavigationStack`）承载，保持根底栏 Canonical 4 Tab 不变；支持周/月切换、宏量四态圆圈矩阵（达标 `#4A9D72`、偏低 `#D79939`、偏高 `#D65C5C`、未知 `#8A9099`，坚持 `missingAsZero == false`）、能量平衡与今日结账门禁、14 种维生素与 15 种矿物质折叠追踪、FTS5 快速记一餐 sheet、食物营养库、个人档案与 DRIs 2023 目标激活、以及 Obsidian Markdown 导出预览。

## 2. Light / Dark 模拟器视觉走查与缺陷闭环

在 `iPhone 17 Pro`（iOS 26）模拟器分别以浅色与深色外观抓取并逐张审视 `01-today-top` 至 `10-coach` 共 10 个界面（完成验证后已清理 `/tmp/bodyseek-m1-ui-{light,dark}` 临时截图目录），发现并闭环修复 3 项真实视觉/状态问题：

1. **`IntradayBarChart` 24 小时分时压力柱不可见**：原实现将离散 `Int` x 轴 `.ratio` `BarMark` 与连续 `Double` x 轴 `RectangleMark` 混用，导致 iOS 26 Swift Charts 柱宽退化。已重构为统一 `Double` x 轴与按可用宽度计算的固定柱宽 `BarMark(x:yStart:yEnd:width:.fixed(barWidth))` + 运动窗口斜纹 `RectangleMark`，并在浅/深色 `02-today-vitals` 与 `05-stress-detail` 截图复核柱体清晰可见。
2. **`NutritionBoardView` 宏量矩阵右列 `"均值"` 数值裁切**：原定 `62pt` 列宽导致 `1825mL` / `27.9%E` 出现截断。已将指标标签微调至 `68pt`、每日圆圈格调至 `20pt`（间距 `3pt`）、均值列加宽至 `80pt` 并启用 `.minimumScaleFactor(0.72)`，浅/深色 `06-nutrition-board` 截图数值完整无裁切。
3. **`TrendsView` 切换至 `3年` 后胶囊按钮高亮状态延迟**：显式向 `horizonPills(selected: store.horizon)` 传值并为胶囊附加 `.id("\(horizon.rawValue)-\(isSelected)")`，同时加强 `bodySeekLiquidPill` 选中态边框对比度（`tint.opacity(0.20)` 填充 + `tint.opacity(0.70)` 描边），浅/深色 `08-trends-3y-capsules` 高亮与 15 根月胶囊显示正确。
4. **UI 测试 TabBar 折叠兼容 (`VelaUITests/BodySeekUITests.swift`)**：针对 iOS 26 `.tabBarMinimizeBehavior(.onScrollDown)` 下滑后 TabBar 折叠为 `'今日' (已折叠)` 胶囊导致切换 `趋势` 失败的问题，在 `tapTab(_:in:)` 增加先点击折叠胶囊展开 TabBar 的交互逻辑。

## 3. 性能对照基准（M0 vs M1-Data vs M1-UI）

测试平台：Apple M5 Pro，数据来源：`PerformanceBaselineTests`。

| 指标 | M0 Debug | M1-Data Debug | M1-UI Debug | M0 Release | M1-Data Release | M1-UI Release | V5 预算 / 说明 |
|---|---:|---:|---:|---:|---:|---:|---|
| `compute60d` | 6.38 ms | 4.81 ms | 4.88 ms | 4.37 ms | 2.59 ms | 2.57 ms | 60 日重算保持稳定 |
| `compute365d` | 100.78 ms | 34.82 ms | 34.24 ms | 70.20 ms | 14.97 ms | 14.98 ms | 28 日双指针滑窗 |
| `compute1095d` | 706.38 ms | 107.02 ms | 105.39 ms | 540.43 ms | 38.81 ms | 41.25 ms | 3 年全量重算 |
| `horizonSwitch3Y` (1095d) | — | 0.55 ms | 0.54 ms | — | 0.25 ms | 0.26 ms | **远优于 `≤ 150 ms`** |
| `trendsScrub60xMonth` | 159.76 ms | 0.08 ms | 0.08 ms | 92.05 ms | 0.10 ms | 0.11 ms | Trends O(1) 缓存 |
| `trendsScrub60x3Y` | 676.61 ms (365d) | 0.05 ms (1095d) | 0.05 ms (1095d) | 300.45 ms (365d) | 0.02 ms (1095d) | 0.02 ms (1095d) | **远优于 `< 50 ms`** |

## 4. 验证命令与实测结果（最终代码树）

1. `grep -rn "try?" BodySeekKit/Sources/`
   - 结果：退出码 `1`（**`0` 处匹配**，无隐式吞错）。
2. `grep -rn "Liveline\|repeatForever" BodySeekKit/Sources/` 与 `grep -rn "SleepChartKit" BodySeekKit/Sources/`
   - 前者 **`0` 处匹配**；后者仅 `BodySeekDesign/Charts/SleepStageChart.swift` **3 处**，`BodySeekFeatures` 层 0 处（允许范围见 `docs/design/chart-grammar.md`）。
3. `grep -rn "import Charts" BodySeekKit/Sources/BodySeekFeatures/`
   - 结果：退出码 `1`（**`0` 处匹配**，Features 层无直接 Swift Charts 调用）。
4. `swift test --package-path BodySeekKit`（Debug）
   - 结果：退出码 `0`，**38/38 通过**（耗时 `1.580s`），覆盖 11 个测试集：
     - `AppAndTodayFeatureTests` (3/3)
     - `BevelScoringEngineTests` (7/7)
     - `BodySeekChartTests` (2/2，含 48 项图表矩阵快照渲染与架构边界校验)
     - `BodySeekStoreTests` (6/6)
     - `ContractsTests` (5/5)
     - `NutritionEngineTests` (3/3)
     - `PerformanceBaselineTests` (1/1)
     - `SecurityAndReliabilityTests` (3/3)
     - `SyncEngineTests` (3/3)
     - `TodayActionAndNutritionFeatureTests` (2/2)
     - `WorkoutAndCoachReducerTests` (3/3)
   - 输出：`BENCHMARK_M1_DATA: compute60d=4.88ms compute365d=34.24ms compute1095d=105.39ms horizonSwitch3Y=0.54ms trendsScrub60xMonth=0.08ms trendsScrub60x3Y=0.05ms`
5. `swift test -c release --package-path BodySeekKit --filter PerformanceBaselineTests`（Release）
   - 结果：退出码 `0`，**1/1 通过**（耗时 `0.122s`）。
   - 输出：`BENCHMARK_M1_DATA: compute60d=2.57ms compute365d=14.98ms compute1095d=41.25ms horizonSwitch3Y=0.26ms trendsScrub60xMonth=0.11ms trendsScrub60x3Y=0.02ms`
6. `xcodebuild test -project Vela.xcodeproj -scheme Vela -destination 'id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987' -parallel-testing-enabled NO -skipMacroValidation -skipPackagePluginValidation`
   - 结果：退出码 `0`，`** TEST SUCCEEDED **`：
     - `VelaTests`（`BodySeekAppIntegrationTests`）：**4/4 通过**（耗时 `0.111s`）
     - `VelaUITests`（`BodySeekUITests`）：**5 项执行（4 通过 / 1 预期跳过 / 0 失败**，耗时 `84.972s`；`testCaptureLightAndDarkScreenshotsWhenRequested` 因未设置 `BODYSEEK_WALKTHROUGH_DIR` 按预期 `XCTSkip`）。
7. `xcodebuild -project Vela.xcodeproj -scheme Vela -destination 'generic/platform=iOS' -skipMacroValidation -skipPackagePluginValidation -allowProvisioningUpdates build`
   - 结果：退出码 `0`，`** BUILD SUCCEEDED **`（`BodySeek*` 与 `Vela` 零新增编译器警告）。
8. `git diff --check`
   - 结果：退出码 `0`（无空白字符或冲突标记问题）。

## 5. 未验证风险与后续里程碑

- **真机硬件未测项**：由于无真机自动化授权，真机（`iPhone 16 Pro`）Release 构建下的 Instruments 真实滚动 Hitch Time Ratio（目标 `< 5 ms/s`）、真实冷启动到首帧耗时（目标 `< 400 ms`）与真实 HealthKit 增量同步尚待真机手测/专项性能测试确认。
- **下一步**：执行 **M4a**（基于真实 3 年 HealthKit 导出包 `/Users/sunweizhou/Downloads/导出.zip` 构建 `BodySeekML/` 离线解析、设备去重审计与分布滞后个人规律分析）。

## 今日建议与开放源代码图表复用补充

- 基线为 `ed7ab2c2` 加本地工作区修改。首屏「今日建议」只展开主行动，详细依据、其他建议和次要提醒可按需展开。建议文案调整沿用原判断规则。
- `swift test --package-path BodySeekKit --disable-automatic-resolution --filter 'BodySeekChartTests|TodayActionAndNutritionFeatureTests'` 退出码 `0`，5 项通过。SleepChartKit 路径使用同一份已规整分期，测试验证跨午夜时间、缺口与重叠拒绝、替代路径和现成组件渲染。
- `xcodebuild test` 使用 `Vela` Debug 和 iPhone 17 Pro / iOS 26.5 模拟器。M1 建议采纳、睡眠和压力详情、营养、三年趋势在最终文案下通过（退出码 `0`，`/tmp/bodyseek-advice-chart-final-20261120.xcresult`）。M3 Coach 流程在文案收口前的同一集成版本通过。
- `xcodebuild build` 使用 `Vela` Debug 通用 iOS 目标，退出码 `0`。构建产物为 `/tmp/bodyseek-deploy-20261120/Build/Products/Debug-iphoneos/Vela.app`，包含 SleepChartKit 许可。未做本轮真机安装或真实 HealthKit 数据验收。

## 今日数据看板优先补充验证

- 基线 `ed7ab2c2` 加本地修改。Vela Debug 的「今日」将五项读数、压力与能量走势、昨夜睡眠移到建议之前。使用默认字号的 iPhone 17 Pro / iOS 26.5 模拟器和合成数据核对首屏。
- `swift test --package-path BodySeekKit --disable-automatic-resolution --filter 'AppAndTodayFeatureTests|TodayActionAndNutritionFeatureTests|BodySeekAgentEvals'`，退出码 0，14 项通过，脚本问答 30/30。
- `xcodebuild test` 的未授权空态、完整页面流和 M1 建议及营养流共 3 项通过，退出码 0，结果在 `/tmp/bodyseek-dashboard-first-20261120.xcresult`。新增断言核对压力和能量首屏可点、简短 AI 建议文本显示和参考依据默认折叠。
- 通用 iOS Debug 构建退出码 0，产物 `/tmp/bodyseek-deploy-20261120/Build/Products/Debug-iphoneos/Vela.app`。本次验证使用模拟回复，未调用线上模型或在真机验收。

## 今日紧凑页头补充验证

- 基线 `ed7ab2c2` 加本地修改。系统内联导航栏显示「今日」，日期和数据来源并入身体状态卡，未授权时保留单个清晰的授权按钮。iPhone 17 Pro 模拟器同尺寸前后截图中，身体状态卡顶部从约 200 px 上移到约 126 px（截图高度 911 px）。
- `xcodebuild test` 使用 Vela Debug 和 iOS 26.5 模拟器，未授权空态和完整页面流 2 项通过，退出码 0，产物 `/tmp/bodyseek-compact-header-20261120.xcresult`。通用 iOS Debug 构建退出码 0。

## 其余一级页紧凑页头补充验证

- 基线 `ed7ab2c2` 加本地修改。健身、趋势、Coach 使用系统内联标题，营养与健身、趋势的内容上沿对齐至 4 pt。iPhone 17 Pro / iOS 26.5 模拟器默认字号的四张截图已逐页核对。
- Vela Debug 的完整页面切换及 M1 营养、趋势流程共 2 项通过，退出码 0，结果为 `/tmp/bodyseek-compact-tabs-20261120.xcresult`。通用 iOS Debug 构建退出码 0，产物为 `/tmp/bodyseek-deploy-20261120/Build/Products/Debug-iphoneos/Vela.app`。

## 身体状态读数排版补充验证

- 基线 `ed7ab2c2` 加本地修改。三列各用统一的指标名称和读数两行，保留数据单位，示例首屏默认字号下均完整显示。无数据与已排除的状态仍分别显示。
- Vela Debug 的 iPhone 17 Pro / iOS 26.5 模拟器未授权空态和完整导航流程均通过，退出码 0，结果 `/tmp/bodyseek-overview-readouts-20261120.xcresult`。通用 iOS Debug 构建退出码 0。

## 健身、营养、趋势、Coach 文案整理

- 基线为 `ed7ab2c2` 加本地工作区修改。健身简化待复盘和负荷说明。营养按餐次折叠条目，仅在对应数据完整时汇总，估算读数显示「约」。趋势把模型资料和回测移入「预测依据」，显示目标日期及预测范围。Coach 的欢迎语与提问入口使用日常措辞，回复来源放入可点开的菜单。
- iOS 26.5 / iPhone 17 的四张示例数据首屏截图已逐页核对。通用 iOS 的 Vela Debug 构建通过，退出码 0，产物在 `/tmp/bodyseek-deploy-20261120/Build/Products/Debug-iphoneos/Vela.app`。本轮未安装到真机。
- `swift test --package-path BodySeekKit --disable-automatic-resolution --filter 'WorkoutAndCoachReducerTests|TodayActionAndNutritionFeatureTests'` 退出码 0，7 项通过。iPhone 17 Pro / iOS 26.5 的 UI 回归中，训练复盘、页面跳转、M1 记餐、M4 趋势实验均通过；新增用例验证餐次默认折叠，展开早餐可见食物明细。
- UI 结果见 `/tmp/bodyseek-content-edit-final-20261120.xcresult`。单独重跑 Coach 的回复、确认记忆和隐私设置通过，退出码 0，结果 `/tmp/bodyseek-content-edit-coach-20261120.xcresult`。旧测试的首屏提醒前置条件已移除，设置页检查入口可用性。

## 2026-11-20 版式决定

- 取消独立大字版，停止大字版的专项布局与验收。标准版使用单套 UI，文字随 iOS 系统设置。当前发布验收以 iPhone 17 Pro、iOS 26.5 和默认字号为基线。
- 基线 `ed7ab2c2`，工作区含既有修改。Vela Debug 的 `xcodebuild test -project Vela.xcodeproj -scheme Vela -destination 'id=3BB779BD-022F-4E60-A3BB-70DC5A0BF987' -parallel-testing-enabled NO -skipMacroValidation -skipPackagePluginValidation -disableAutomaticPackageResolution -resultBundlePath /tmp/bodyseek-nov20-standard.xcresult` 退出码 0。4 项 iOS 集成测试和 10 项 UI 测试通过。只在提供截图目录时运行的批量截图用例按预期跳过。
- 已核对默认字号的 Coach 欢迎页、回复与证据卡，以及全天饮食草稿。截图和肌群复盘详情附件见 `/tmp/bodyseek-nov20-standard-attachments/manifest.json`。

## 2026-11-20 补记：SleepChartKit 复用与文档更正

- `0bbf6ce8` 当时确实移除了 `liveline-swift` 与 `SleepChartKit` 依赖。当晚 `6b207556` 为睡眠摘要引入 `SleepChartKit 1.2.0`：连续片段走上游 `SleepTimelineGraph`，交互、缺测与重叠仍走原生 Canvas；`BodySeekDesign` 保留许可资源，`BodySeekFeatures` 不直接依赖。
- 因此第 1 节原「彻底移除 SleepChartKit」与第 4 节原 grep 门禁已按当前代码更正。图表规范同步更新于 `docs/design/chart-grammar.md`，取舍依据见 `docs/design/chart-reuse-evaluation-2026-11-20.md`。
- 当前门禁：`grep SleepChartKit BodySeekKit/Sources` 只命中 `BodySeekDesign/Charts/SleepStageChart.swift`；`grep Liveline` 与 `grep repeatForever` 仍为 0。
