# BodySeek 模块化现状与分阶段路线

> 状态：当前源码地图（2026-10-15，五项评分引擎已进入领域包）
> 勘察基线：`6518c967`；恢复分抽取在此基线之后
> 权威决策：[ADR 0017](../adr/0017-bodyseek-architecture-and-product-baseline-v2.md)
> 抽取不改评分公式、部署底线、SwiftData schema 或 Vela 标识。

本文取代下列契约里对“当前源码”的描述。那些文件仍是当时的迁移契约和勘察记录，不能再当成现在的源码地图：

- [ARCH-01 / PR1](bodyseek-domain-pr1-contract.md)（勘察基线 `4d87be95`；文中“package 尚未接入主工程”已过时）
- [ARCH-02 / PR2](bodyseek-dependencies-pr2-contract.md)（勘察基线 `4f8d0eaa`；文中“本 PR 不接入 `Vela.xcodeproj`”已过时）
- [ARCH-03 / PR3](bodyseek-today-pr3-contract.md)（勘察基线 `cdd25b92`；正文保留的是迁移前调用链）

PR5、PR7 与各项 PR8 回放报告继续描述各自切片，不由本文作废。

## 1. 现在实际长什么样

生产链路是：HealthKit / SwiftData 适配器产出日快照，App 的 `DailyHealthComputation` 把快照和长线上下文映射进领域包，由领域包的 `DailyHealthComputation` 装配五项分数，再映射回 App 的 `MetricResult`。

```text
HealthKitSyncEngine
  └─ DailyHealthSnapshot
       └─ VelaApp.DailyHealthComputation          ← 映射快照与长线上下文
            └─ BodySeekDomain.DailyHealthComputation   ← 五项装配
                 ├─ SleepScoreEngine
                 ├─ RecoveryScoreEngine
                 ├─ StrainScoreEngine
                 ├─ StressIndexEngine
                 └─ EnergyBankEngine
       PersonalHealthBrief
            ├─ DashboardViewModel ──┐
            └─ TodayStore ──────────┴─ Today / Trends / Plan / Coach
```

[BodySeekDomain](../../BodySeekDomain/Package.swift) 只依赖 Foundation。五项评分的装配在领域包的 [DailyHealthComputation.swift](../../BodySeekDomain/Sources/BodySeekDomain/DailyHealthComputation.swift)。App 的同名类型只映射快照、睡眠证据和长线上下文，再把领域包的 `MetricResult` 映射回 App。长线基线报告本身仍留在 App，因为里面还有 Wiki 和三年统计；传入领域包的是已经算出的恢复上下文和静息心率中位数。

## 2. 各阶段落到哪了

- PR0 基线在 [docs/baselines/](../baselines/README.md)。金样例覆盖五项分数。回放夹具现有睡眠、恢复、负荷、压力、能量。
- PR1 引擎抽取完成。五项引擎都在领域包。中位数、样本标准差和稳健标准差在 `ScoringMath`；日负荷观察值 `DailyLoadObservation` 也在领域包。`MetricConfidence` 与 `TrainingLoadStatus` 以领域包为准，App 用类型别名接上。其余个人基线和趋势引擎仍在 [VelaApp/Scoring](../../VelaApp/Scoring)。心率区间展示仍留在 App，因为它直接消费 `HeartRateSample`。
- PR2 部分完成。[VelaServices.swift](../../VelaApp/Core/Utilities/VelaServices.swift) 里有 `AppDependencies`，但 `UserDefaults`、Wiki 和全局服务仍留在评分与界面侧。
- PR3 部分完成。Shell 持有 [TodayStore.swift](../../VelaApp/Features/Today/TodayStore.swift)，[VelaMinimalTodayView.swift](../../VelaApp/Features/Minimal/VelaMinimalTodayView.swift) 不再直接 `import SwiftData`。同一视图仍 `@EnvironmentObject` 持有 [DashboardViewModel.swift](../../VelaApp/Features/SharedComponents/DashboardViewModel.swift)。
- PR4 产品面已是 Today / Trends / Plan / Coach。架构上的 3+2 仪表盘没有独立收口记录。
- PR5 五项分数的趋势序列都经 `TrendsStore`。SwiftData 读取在 `PersistedTrendsWindowLoader`，`VelaTrendsView` 不再持有 `ModelContext` 或 `DashboardViewModel`。选中日、发现和修订号由 `VelaTrendsHost` 传入。指标详情收到调用方传入的选中日和仪表盘快照。见 [PR5 契约](bodyseek-trends-pr5-contract.md)。
- PR6 持久化与同步并发没有独立契约，也没有开始迁移。[PersistenceModels.swift](../../VelaApp/Persistence/SwiftDataModels/PersistenceModels.swift) 约 2,498 行，旁边还有一份约 1,381 行的冻结 schema。
- PR7 只有契约和领域包里的合同类型。App 侧 [ScoringCore.swift](../../VelaApp/Scoring/ScoringCore.swift) 仍是界面实际使用的结果类型。见 [PR7 契约](bodyseek-score-pr7-contract.md)。
- PR8 五项评分引擎和日装配都在领域包的 `DailyHealthComputation`。App 同名类型只做快照、睡眠证据和长线上下文映射。
- 正式产品之外的生物年龄 / 健康年龄仍出现在设置、体征、Coach 和 `DashboardSummary`。ADR 0017 不把它算进五项分数。

体量上，`VelaApp` 约 194 个 Swift 文件。`Features/Minimal` 约 28,000 行，单文件超过 1,000 行的包括训练 Hero、Today 子表、指标详情、营养条和恢复详情。`AI` 约 12,000 行，`Scoring` 约 8,500 行。Watch 是单文件约 1,400 行。`VelaBackend` 是独立服务端包，不在这条 iOS 领域迁移链上。

## 3. 后续顺序

每一刀单独做，前后都用现有金样例对照。抽取不改公式、不改部署底线、不改 SwiftData schema、不重命名 Vela 标识。

1. 恢复分已完成。引擎在 `BodySeekDomain`；[RecoveryScoreEngine.swift](../../VelaApp/Scoring/Recovery/RecoveryScoreEngine.swift) 只做结果映射。中位数、样本标准差和稳健标准差只留在 `ScoringMath`。
2. 负荷分已完成。引擎在 `BodySeekDomain`；[StrainScoreEngine.swift](../../VelaApp/Scoring/Strain/StrainScoreEngine.swift) 只做结果映射，心率区间计算仍留在该文件。`DailyLoadObservation` 跟负荷证据一起进入领域包。
3. 压力分已完成。夹具在 [stress-replay-fixtures.json](../baselines/stress-replay-fixtures.json)。引擎在 `BodySeekDomain`；[StressIndexEngine.swift](../../VelaApp/Scoring/Stress/StressIndexEngine.swift) 只做结果映射。
4. 能量分已完成。夹具在 [energy-replay-fixtures.json](../baselines/energy-replay-fixtures.json)。引擎在 `BodySeekDomain`；[EnergyBankEngine.swift](../../VelaApp/Scoring/EnergyBank/EnergyBankEngine.swift) 只做结果映射。领域包的能量算法版本常量已与生产 `energy.v2.1.0` 对齐。
5. 五项装配已收进领域包的 `DailyHealthComputation`。App 同名类型只映射输入和结果。`MetricResult` 仍是 App 的展示类型。长线基线报告还在 App。
6. Today 主界面和指标详情都不再读取 `DashboardViewModel`。页面数据来自 `TodayViewState`。指标详情的选中日和仪表盘快照由 Today、Trends、训练和体征在打开时传入。计划页和训练页用 `PlanTrainingDecisionResolver` 选择训练决定：已发布的决定优先，否则沿用当天已保存计划里的决定。Coach 欢迎页接收 Coach 已经持有的仪表盘快照。恢复、睡眠、负荷、压力和能量的整数展示统一用 `MetricResult.formattedScore`：有分数时四舍五入，缺失时为 `--`。手表快照用同一个 `roundedScore`，缺失保持空。
7. Trends 五项分数已接到 `TrendsStore`，持久化读取已离开趋势页。窗口读取走 `SwiftDataDailyHealthSummaryRepository`，行到快照走 `DailyHealthSummaryRecord.toSnapshot()`，并用 `updatedAt` 保持同日最新写入优先。趋势页打开指标详情时传入自己的选中日和仪表盘快照。见 [PR5 契约](bodyseek-trends-pr5-contract.md)。
8. 持久化与同步并发（原 PR6）放在评分入口唯一之后。日摘要、手记、饮食、训练、报告、生成物、经营计划、决策反馈、引导状态、Coach 产物和训练计划提案的公共读取都进了对应仓库。历史报告页和生成物库按创建时间从新到旧读取生成物，删除后依赖本地数据变更重新加载。每日计划按生成物类型和身体状态哈希查找已有记录，再更新或插入。训练事件从某个时刻起的开放查询，以及训练计划按标识和幂等键的查找，都走仓库。待确认记忆提案经 `MemoryLedger.pendingProposals()`。训练轮转页的计划、训练事件和待确认提案改走仓库；采纳与拒绝使用 `TodayTrainingPlanAdaptationDecision`。身体模型编辑用训练反应仓库计算下一轮重点，力量训练详情和记录表用同一套力量记录排序做历史对照。训练模板按标题排序，已删除训练的黑名单只从 `DeletedWorkoutRepository` 读取。当日饮食用半开区间 `[start, end)`，导出按时间从旧到新。同一类型的报告走 `SwiftDataAIReportRepository`：只要最新一条的用 `recent(type:limit:)`，需要在同类型里继续找今天记录的用 `fetch(type:)`。体征和 Coach 的生物标志按测量时间读取，导出按时间从旧到新；生物标志编辑页仍用实时查询，因为页面会增删记录。日内压力和能量曲线的采样桶走 `HealthSnapshotRepository.fetchIntradayBuckets(from:until:)`，结束时间不包含在窗口里。动作定义、未完成训练草稿和训记镜像分别走各自仓库。信任中心与晚间同步的 Agent 运行记录走 `AgentRunRepository`，成功记录按开始时间从新到旧。动作选择器在写入默认库之后再读取。手记页的个人实验按创建时间从新到旧，打卡按日期从新到旧，并在出现、换日和本地数据变更时重新加载。开始实验只取消仍为进行中的实验，当日打卡按稳定标识更新。产品事件的质量窗口两端都包含，诊断读取全部事件。已确认的观察类记忆、按来源读取的记忆，都走 `MemoryLedger`。Wiki 同步读取全部文档，健康档案按更新时间从新到旧展示。未归档的教练会话按更新时间从新到旧。记录表的训练模板和删除黑名单在打开、删除、保存和本地数据变更时重新读取。引导编辑、Wiki 提案和生物标志编辑页仍持有可写记录。Wiki 里确认或拒绝提案的界面仍用实时查询持有可写记录。周热力图与月热力图共用 `TrainingHeatmapData.tier`。
9. `Features/Minimal` 的大文件拆分、生物年龄是否退出正式表面，各自另开产品决定。不放进领域抽取。

明确不做：把 Health、Scoring、AI、UI 一次性拆成多个 Swift Package；在抽取时改评分公式；把空包或生物年龄推进领域核心。
