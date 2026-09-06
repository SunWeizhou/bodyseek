# ARCH-03 / PR3：Today `Store / ViewState / Action` 迁移契约

> 阅读范围（2026-09-06）：下文保留 `cdd25b9` 的迁移前勘察，不是当前源码地图。当前 `VelaMinimalShell` 持有 `TodayStore`，`VelaMinimalTodayView` 接收 Store；请勿据本文重新实施一次迁移。当前接手路径见 `docs/collaboration/UI_WORKFLOW.md`，运行时完成度仍需针对目标提交验证。


> 状态：**contract-ready**（只读勘察与接口定稿；本文件不表示运行时已经迁移）  
> 勘察基线：`cdd25b9298fe5de8766ebe270984d3be80a302fa`  
> 关联：ADR 0017、`docs/architecture/bodyseek-dependencies-pr2-contract.md`、PR0 `docs/baselines/`

本契约把 BodySeek（工程身份 Vela）的 Today 页面从“带副作用的巨大 View”收敛为
`ViewState → View`、`View → Action`。它是 PR2 显式依赖接缝之后的最小安全迁移，目标
是让首屏可以替换读取器、可在 Preview/Test 中运行，并为后续 3+2 UI 重做保留稳定的
行为边界。

本 PR **不**重写评分公式、SwiftData schema、HealthKit adapter、BodySeekDomain
package 或首屏视觉布局；也不宣称当前 Today 已经完成迁移。当前生产代码仍是 Vela
Target 内的 Apple-native modular monolith，旧 `DashboardViewModel`、`VelaServices`
和 resolver 仍需兼容一段时间。

## 1. 当前事实：Today 不是纯 View

### 1.1 当前调用链与触发源

`VelaTodayView` 在 `VelaApp/Features/Minimal/VelaMinimalTodayView.swift`（当前约
1493 行）中同时定义渲染、状态投影、刷新触发、导航和持久化副作用。关键路径如下：

```text
VelaTodayView.body
  ├─ .task(id: isActiveSurface)                         [:696–709]
  │    ├─ dashboardVM.hydrateFromCache(modelContext:)
  │    ├─ refreshDashboard() → dashboardVM.refresh(modelContext:)
  │    ├─ loadDataCoverageSummary()
  │    ├─ loadTodayLivedStateAlignment()
  │    └─ trackDailyDecisionViewed()
  ├─ .refreshable → refreshDashboard(force: true)       [:710–714]
  ├─ scenePhase active → refreshDashboard(force: false) [:715–732]
  ├─ selectedDate change → hydrate + secondary + refresh [:734–741]
  ├─ localDataRevision change → force refresh + secondary [:743–753]
  └─ location change → fetchLocalWeather()               [:754–756]
```

`VelaApp/AppCoordinator.swift` 又会在启动时执行同一 `DashboardViewModel` 的
`hydrateFromCache` 与 `refresh`（`:60–72`）。因此 Today 不是唯一同步入口；Trends、
Plan、Coach 的深链启动也可能先改变共享 VM。PR3 必须避免将这些触发器复制一遍，
而是由 `TodayStore` 对同一日请求做 coalescing，并把启动调度留给 composition root。

### 1.2 View 的直接依赖

| 位置 | 现有直接依赖 | 迁移含义 |
|---|---|---|
| `VelaMinimalTodayView.swift:26–36` | `@Environment(\.modelContext)`、`@EnvironmentObject DashboardViewModel`、`VelaAppState.shared`、`LocationManager.shared` | View 持有持久化 context 和全局路由/定位对象 |
| `VelaMinimalTodayView.swift:220` | `@AppStorage("vela_daily_calorie_target")` | 营养目标从 UserDefaults 直接进入首屏计算 |
| `VelaMinimalTodayView.swift:110–121, 292–312` | `Date()`、`Calendar.current` | 新鲜度和文案随墙钟变化，难以固定回放 |
| `VelaMinimalTodayView.swift:696–753` | hydrate、refresh、coverage、lived-state、feedback 全由 View 触发 | 生命周期和业务协调混在渲染层 |
| `VelaMinimalTodayView.swift:915–1000` | `LivedStateJournalAdapter(modelContext:)`、`DailyDecisionFeedbackService`、`FetchDescriptor` | Action effect 直接写 SwiftData |
| `VelaTodayViewData.swift:37–96, 198–212` | `DashboardViewModel` 和 `ModelContext` | secondary/nutrition 读取不经过 Today 接缝 |
| `VelaTodayViewData.swift:102–149` | `LocationManager.shared`、`WeatherLocationStore`、`WeatherService.shared`、`CLGeocoder` | 天气网络/定位副作用与健康读取耦合 |
| `VelaMinimalTodayView.swift:792, 825, 998` | `VelaAppState.shared` | 导航和 local-data revision 由 View 直接驱动 |

允许保留的 SwiftUI 本地状态仅限 sheet、动画、焦点和临时编辑值；它们不能成为
评分、决策或持久化事实的第二份来源。

### 1.3 `DashboardViewModel` 的实际职责

`VelaApp/Features/SharedComponents/DashboardViewModel.swift` 是共享的 `@MainActor`
`ObservableObject`，目前同时持有：

- `dashboard`、五项 `MetricResult` 的投影、`lastUpdated`、error/loading/freshness；
- selected date、streak、周比较、sleep/recovery/strain/stress/vitals trend、heatmap；
- `dailyTrainingDecision`、`todayCommandState`、`todayExperience`；
- Daily Operating Plan、active training plan、pending adaptation、AI insight；
- nutrition aggregates、体征 sparkline、Watch publish 和反馈校准。

它的 `hydrateFromCache`、`refresh`、`loadSecondaryData` 和各个 trend 方法都接受
`ModelContext`（`:178–998`），内部还直接使用 `FetchDescriptor`、`Date()`、
`Calendar.current`、`UserDefaults.standard`（secondary assembler `:938`）以及
`WristSnapshotBridge.shared`（`:787`）。它是 PR3 需要拆出的共享热点，不是可直接
暴露给 View 的新 Store。

### 1.4 Today 的值模型与算法接缝

- `VelaApp/Core/Utilities/TodayCommandState.swift` 的 `TodayCommandState`、
  现有 `TodayAction`（渲染后的 command action）和 `ReadinessDecision` 是
  Codable/Hashable/Sendable 值类型；
  `TodayCommandBuilder.build`（`:143–193`）统一 readiness、signals 和 actions，
  不能在 Store getter 或 View loading fallback 中再次运行另一套决策树。
- 同文件的 `DecisionFeedbackCalibrator` 仍直接接收 `DailyDecisionFeedbackRecord`
  （`:68–121`），并在 `TodayCommandBuilder` 中使用 `Calendar.current`（`:261`）。
  这说明它是 App-side projection，不是可跨层传播的 Domain API；PR3 只消费已装配
  的值，不改公式或把 SwiftData record 带进 Store。
- `VelaApp/Core/Utilities/TodayExperienceModel.swift` 的 `TodayExperienceModel.build`
  （`:87–235`）负责五张 signal card、baseline 进度、actions、nutrition 和 Coach
  preview；它是纯投影，但当前仍 import SwiftUI，并依赖 `DashboardSummary`、
  `DailyHealthSummaryDTO`、`DailyOperatingPlanPayload` 等 App 值类型。PR3 不在 View
  中重新 build；Store/adapter 应接收一次装配结果。

## 2. PR3 的最小安全目标

### 2.1 分层与单向数据流

```text
AppDependencies (PR2 composition root)
        │
        ▼
TodayReadingModule.cached/load  ──► TodayReadSnapshot (Sendable DTO)
        │                                      │
        │                                      ▼
        └──────────────────────────────► TodayStore (@MainActor)
                                               │
                                  @Published TodayViewState
                                               │
                                               ▼
                                  TodayScreen / section Views
                                               │
                                  TodayStoreAction (intent only)
                                               │
                                               ▼
                         TodayEffectRouter / injected effect adapters
```

`TodayStore` 只服务 Today Dashboard。它不是新的全局容器，也不拥有 Coach、Trends、
Plan 或 Nutrition 的长期状态；这些下游只通过已经装配的轻量投影显示。

### 2.2 `TodayViewState` 最小形状

实现可以按当前命名微调，但必须保留以下语义，且只包含值类型、ID、字符串和可选
投影，不包含 `ModelContext`、`@Model`、`FetchDescriptor`、`HKHealthStore` 或全局
服务：

```swift
struct TodayViewState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case loading(previous: Bool)
        case ready
        case empty
        case failed(TodayLoadFailure)
    }

    let selectedDay: Date
    var phase: Phase
    var source: DashboardSummary.DataSource
    var freshness: DataFreshness
    var scores: TodayScoreState       // Recovery/Sleep/Strain/Stress/Energy, nil-aware
    var command: TodayCommandState?
    var experience: TodayExperienceModel?
    var coverage: DataCoverageSummaryModel
    var livedState: TodayLivedStateProjection
    var feedback: TodayFeedbackProjection
    var plan: TodayPlanProjection?
    var nutrition: TodayNutritionProjection?
    var nonCritical: TodayNonCriticalState // weather/AI/downstream errors only
    var error: TodayLoadFailure?
}
```

以上类型是契约示意；若复用现有 `MetricResult`、`TodayCommandState` 或
`TodayExperienceModel`，必须先确认它们为值语义并由 adapter 一次性装配。`scores`
必须维持五个独立分数、各自的 `nil`/`missingInputs`/`algorithmVersion`/coverage；
不得引入 aggregate health score、将缺失转换成 `0` 或在 getter 中调用 scoring kernel。
`phase` 与 `error` 必须区分“正在加载”“无数据”“读取失败”；失败的 Weather、AI、
Nutrition 或 Plan 不得覆盖主健康 evidence 的 phase。

`TodayReadSnapshot`（由 PR2 的 `TodayDashboardSnapshot` 演进而来）应至少包含上述
主链所需的 value DTO；若某个下游尚未可安全装配，返回 `nil`/`.unavailable` 投影，
而不是让 Store 重新访问 SwiftData。旧 `TodayDashboardSnapshot` API 可暂留兼容桥，
但不能把 `DashboardSummary` 继续作为 View 的万能依赖。

### 2.2.1 PR3 小型 DTO delta（ARCH-03 follow-up）

当前实现先采用兼容性最小增量，而不改动 `DashboardSummary`、评分 kernel 或
composition root：`TodayDashboardSnapshot` 在一次 reader load 中额外携带已经装配好的
`bodyState`、`trainingDecision`、`command`、`experience`、AI insight、nutrition、
operating-plan payload、last-updated、vital trend，以及主/secondary error 文案。
`TodayViewState` 对应保存这些值，并同时保存当前 `dashboard` read-model；根 View 只能从
`todayStore.state` 读取它们。命令与体验缺失时使用状态层的显式、值语义
`unavailable` projection，不得调用 `TodayCommandBuilder` 或
`TodayExperienceModel.build`。

本 delta 刻意不把 `TrainingPlanRecord`、`TrainingPlanAdaptationRecord`、
`DailyDecisionFeedbackRecord` 或 `ModelContext` 放进 Sendable state；这些 SwiftData
对象仍是兼容 effect 的 P1 边界。完成它们的迁移需要另一个值 DTO/写入 adapter 设计，
不是本次 root 接线的隐式扩张。

### 2.3 Store Action 是意图，不是副作用

当前代码已经有一个名为 `TodayAction` 的结构体（`TodayCommandState.swift:17–32`），
它是 command state 的渲染模型，不是用户事件。Swift 模块中不能再声明同名 enum，
因此实现 worker 必须在两者之间做显式选择：要么先把旧结构体改名为
`TodayCommandAction`（保留 Codable 解码兼容），要么暂时把事件 enum 命名为
`TodayStoreAction`。下文用 `TodayStoreAction` 表示事件意图；它与产品讨论中的
“TodayAction”语义相同，但不能与现有值模型静默重名。

建议的最小 Action 集合：

```swift
enum TodayStoreAction: Sendable {
    case appear
    case selectDay(Date)
    case refresh(force: Bool)
    case retry
    case openCalendar
    case openMetric(TodayMetricID)
    case openEvidence
    case openPlan
    case openSettings
    case askCoach(String)
    case startTraining
    case requestWeather
    case setLivedStateAlignment(LivedStateAlignment)
    case saveLivedState(LivedStateCheckIn)
    case submitFeedback(DailyDecisionFeedbackValues)
}
```

Action 的命名可以匹配现有 UI，但必须遵循：

1. 不携带 `ModelContext`、SwiftData record、`HKHealthStore` 或 Service Locator；
2. Store 负责校验 selected day、发起读取、更新 phase 和去重；
3. 导航、Haptic、天气、SwiftData 写入、Coach/Plan 路由交给注入的 effect router；
4. 用户 action 不因 analytics/telemetry 写入失败而被阻塞；
5. 写入成功后的 local-data revision 通过 effect 回传，再触发 Store 的显式 refresh，
   不由 View 直接访问 `VelaAppState.shared`。

### 2.4 `TodayStore` 的行为契约

```swift
@MainActor
final class TodayStore: ObservableObject {
    @Published private(set) var state: TodayViewState

    init(
        reader: any TodayReadingModule,
        clock: any AppClock,
        calendar: Calendar,
        effects: any TodayEffectRouter
    )

    func send(_ action: TodayStoreAction) async
}
```

实现必须满足：

- `reader.cached(for:)` 是无 HealthKit 副作用的首帧路径；`reader.load(for:policy:)`
  是唯一主链刷新入口。`ModelContext` 和 HealthKit 只存在于 adapter。
- 同一 `healthDayKey` 的并发 load 只执行一次；后续 caller 等待同一 task。切换日期
  后，旧 task 可以完成但不得覆盖新日期的 state；取消必须把 `loading` 收束为
  `idle`/上一个稳定 phase，而不是永久卡住。
- 先 cache、后 live load 的顺序不得让历史日短暂显示前一天的 command/experience；
  选中日期变化时清空或标记过期的日级 projection。
- `force == false` 尊重 PR2/Health cache TTL；`force == true` 只绕过 Today 的刷新
  节流，不复制另一套 HealthKit 同步器。TodayStore 不读取 `VelaDailyOrchestrator`
  的静态字典，也不在 View 中实现 coalescing。
- 只有在完整的 `TodayReadSnapshot` 到达后才一次性发布 ready state；部分下游读取
  失败时保留上次成功的主 evidence，并在 `nonCritical`/error 中标注。
- 任何空值都保持显式：五项 score 的 `nil` 渲染为 `--`，缺失原因和 Data Coverage
  可见；不得用 `0`、默认目标或“看起来正常”的静默 fallback。

## 3. View 迁移规则

### 3.1 `VelaTodayView` 的目标接口

PR3 的最终 root View（可暂时保留旧文件名）只应读取：

```swift
@EnvironmentObject private var todayStore: TodayStore
@Environment(\.velaSurfaceIsActive) private var isActiveSurface
@State private var presentedSheet: TodaySheet?

var body: some View {
    TodaySections(state: todayStore.state) { action in
        Task { await todayStore.send(action) }
    }
}
```

视觉层可以继续复用现有 `TodaySignalGrid`、`TodayDailyPlanCard`、`TodayVitalsGrid`
等组件；PR3 不调整它们的布局、颜色、文案或 3+2 顺序。迁移期间如果仍需向嵌套
sheet 传递数据，应传 value projection 和 effect closure，不能把 `modelContext` 从
root View 继续下传。

### 3.2 硬禁区（静态 guard）

PR3 迁移后的 Today production files（root、Store、ViewState、Action）不得：

- import 或引用 `SwiftData`、`ModelContext`、`@Query`、`FetchDescriptor`；
- import 或实例化 `HealthKit`、`HKHealthStore`、`HealthKitQueryService`；
- 读取 `UserDefaults.standard`、`@AppStorage` 作为 score/decision 输入；
- 访问 `VelaResolver.shared`、`VelaServices` locator 属性或任何 `.shared` feature
  singleton（包括 `VelaAppState.shared`、`LocationManager.shared`、
  `WeatherService.shared`）；
- 在 `body`、computed property、`TodayViewState` getter 或 loading fallback 中运行
  `TodayCommandBuilder`、`TodayExperienceModel.build`、BodyState/TrainingDecision
  kernel 或五项评分；
- 让天气、AI、Nutrition、Plan 或 analytics 错误替换主健康 evidence 的错误状态。

以下内容仍可存在于独立下游文件，直到各自 owner 收口：`TodayHeroCard` 小时图的
HealthKit 直连、`TodayNutritionStrip` 的 `@Query/@AppStorage`、`TodaySubSheets`
中的训练/HealthKit 读取，以及 `LivedStateCheckInSheet` 的本地编辑状态。它们不能
重新成为 TodayStore 的隐含输入。

## 4. 精确 owned paths 与变更边界

### 4.1 ARCH-03 worker 可修改的路径

首个实现 worker 应只在以下路径工作；新文件目录可在 Xcode 现有 target 约定下命名，
但必须保持职责边界：

| 路径 | PR3 责任 | 规则 |
|---|---|---|
| `VelaApp/Features/Today/TodayViewState.swift` | 新增状态值类型与 phase/error/projection | 不 import SwiftData/HealthKit；不保存 `@Model` |
| `VelaApp/Features/Today/TodayStoreAction.swift` | 新增 Action intent 类型（逻辑名 TodayAction） | 不携带 context/record/store；可复用现有值 DTO |
| `VelaApp/Features/Today/TodayStore.swift` | 新增 `@MainActor` Store、coalescing、action dispatch | 只依赖 PR2 reader/clock/calendar/effect protocols |
| `VelaApp/Features/Minimal/VelaMinimalTodayView.swift` | 把 root/lifecycle 读写改为 state + send；保留现有布局 | 不在此文件新增业务读取、写入或公式 |
| `VelaApp/Features/Minimal/VelaTodayViewData.swift` | 将 action/weather/secondary 入口改成 effect closure 或 adapter 调用 | 天气迁出主链；不再用 View 的 ModelContext 读取主数据 |
| `VelaAppTests/TodayStoreTests.swift` | reader、clock、effect spy 与 phase/action/concurrency 测试 | 不启动真实 HealthKit、网络或持久化 store |
| `VelaAppTests/TodayViewStateTests.swift` | 值投影、空值、freshness、legacy snapshot parity 测试 | 对照 PR0 golden，不改 golden 数值 |

若 Xcode target 需要新增文件，project 文件的编辑必须交给单独的
`project-integration` owner；ARCH-03 worker 不直接并行编辑 `Vela.xcodeproj/project.pbxproj`。

### 4.2 明确不 owned（只读或另行 handoff）

- `VelaApp/Core/Utilities/VelaServices.swift`、`DailySummaryUseCase.swift`：ARCH-02
  依赖/factory owner。PR3 只消费现有 `TodayReadingModule`，不重排 resolver、sync 或
  HealthKit query 签名。
- `VelaApp/Features/SharedComponents/DashboardViewModel.swift`：ARCH-03 共享热点，
  只能做一次最小 adapter/injection 接缝；不得在同一提交顺带删除 Trends、Plan、Coach、
  Watch 或 secondary 管线。若要删除字段，另开拆分 PR。
- `VelaApp/App/AppCoordinator.swift`、`VelaApp/App/VelaApp.swift`：composition-root
  owner。只接收 Store 的 factory/environment wiring handoff，不在 Today worker 中改变
  schema、fallback store、后台任务、权限启动顺序。
- `VelaApp/Core/Utilities/TodayCommandState.swift`、`TodayExperienceModel.swift`：
  算法/投影 owner。PR3 不改 readiness 分支、五项 score、copy 或公式；需要 DTO 化时
  另开纯值契约提交。
- `VelaApp/Features/Minimal/TodayHeroCard.swift`：PR4/hourly Health adapter owner；
  当前 `HealthKitQueryService()` 直建仍是已知缺口。
- `VelaApp/Features/Minimal/TodayNutritionStrip.swift`：Nutrition 下游 owner；当前
  `@Query FoodLogRecord` 和多组 `@AppStorage` 不纳入 P0 TodayStore。
- `VelaApp/Features/Minimal/TodaySubSheets.swift`：训练/反馈 sheet owner；其中的
  `PostWorkoutImpactSheet` 具体 HealthKit query 另行收口。
- `BodySeekDomain/**`、`VelaWatch/**`、SwiftData schema/fixture：PR1/CC-04/Watch
  owners；本 PR 不接入 package、不迁移模型、不复制类型。

## 5. Shared locks 与并行规则

| 锁 | Owner | 并行规则 |
|---|---|---|
| `VelaApp/Features/SharedComponents/DashboardViewModel.swift` | ARCH-03 | Today worker 独占编辑窗口；Trends/Plan/Coach agent 只读，避免同时删 `@Published` 或 refresh 方法 |
| `VelaApp/Features/Minimal/VelaMinimalTodayView.swift` | ARCH-03 → PR4 | PR3 只做 state/action 接线；PR4 负责 3+2 视觉。两者不得交叉改同一 body 区块 |
| `VelaApp/Features/Minimal/VelaTodayViewData.swift` | ARCH-03 | 迁移 effect/天气入口时锁定；天气 owner 不要并行重写同一 helper |
| `VelaApp/Core/Utilities/VelaServices.swift` | ARCH-02 | 只由依赖图 owner 编辑；PR3 不把 `AppDependencies` 再包一层 locator |
| `VelaApp/Core/Utilities/DailySummaryUseCase.swift` | ARCH-02 | 保持当前 reader bridge；任何 query/use-case 调整另开提交 |
| `VelaApp/App/AppCoordinator.swift` / `VelaApp/App/VelaApp.swift` | composition-root | 仅做一次 environment/factory wiring；禁止 feature agent 同时改启动和 persistence |
| `VelaApp/Features/Minimal/TodayHeroCard.swift`、`TodaySubSheets.swift` | PR4/下游 | PR3 通过 projection/closure 兼容现状，不在这里做 hourly/Workout 迁移 |
| `Vela.xcodeproj/project.pbxproj` | project-integration | 单一 owner；新文件/本地 package 依赖一次性接入，禁止多 agent 同时编辑 |
| `VelaAppTests/*` 聚合测试文件 | test owner | 新增 Today 专用测试文件优先；不要把并行 worker 的断言散落进大型共享文件 |

冲突解决顺序：先保留已接受 ADR/PR0 golden 的数据和缺失语义；其次保留 PR2
reader API 的兼容桥；最后才处理文件重排。不要通过 `git reset --hard` 或覆盖他人
未提交改动解决冲突。

## 6. 测试门禁

### 6.1 Store 行为与并发

必须用可观察 fake 覆盖：

1. `appear` 先 cache 后 load，`cacheOnly` 不创建 HealthKit；
2. 同日并发 `load` 只调用 reader 一次；不同日期的旧结果不会覆盖当前 state；
3. `refresh(force:)` 的 TTL/force 行为与 PR2 policy 一致；取消后 phase 可恢复；
4. loading/empty/failed/ready 四态可区分，保留上次成功 state 的规则可断言；
5. `selectDay` 不允许未来日，并在新日加载期间不闪现旧日 command/experience；
6. Action spy 能观察 open evidence/coach/training、lived-state、feedback、weather
   effect，且 analytics 写入失败不阻塞用户 action。

### 6.2 数据与产品语义

- 将 PR0 golden fixture 映射到 `TodayViewState`，验证五项顺序、每项 score、
  `algorithmVersion`、source、freshness 和 `nil/--/missingInputs` 完全一致；
- 空 fixture 必须仍显示五项 unavailable，不产生 aggregate score、伪造 0 或默认
  confidence；
- `TodayCommandState` 和 `TodayExperienceModel` 只验证“已装配值被原样投影”，不在
  Store 测试中复制 readiness/experience 公式；
- 反馈和 Lived State 只通过 value DTO/Action 进入 effect spy，不在测试中把
  `DailyDecisionFeedbackRecord` 或 `ModelContext` 传给 Store。

### 6.3 静态依赖 guard 与回归

对 PR3 production files 运行至少以下检查：

```sh
rg -n 'import (SwiftData|HealthKit)|ModelContext|FetchDescriptor|@Query|@AppStorage|UserDefaults\.standard|VelaResolver\.shared|VelaAppState\.shared|LocationManager\.shared|WeatherService\.shared|HealthKitQueryService\(|\.shared' \
  VelaApp/Features/Today VelaApp/Features/Minimal/VelaMinimalTodayView.swift \
  VelaApp/Features/Minimal/VelaTodayViewData.swift
```

允许的命中必须限定为迁移注释或非 Today 下游，并在 review 中逐项说明；Store/ViewState/
Action 生产文件不得有命中。回归门禁包括：

- `swift test --package-path BodySeekDomain`；
- Vela host focused Today/Context/Scoring/Persistence tests；
- 完整 iOS unit + UI suite（不得降低当前 baseline 的 passed/failed/skipped 记录）；
- `git diff --check`、schema guard、PR0 golden diff；
- 现有 `VelaUITests/VelaSmokeUITests.swift` 的 Today empty/loading 与 lived-state
  deep-launch 场景保持通过。若 UI 外观有意改变，应留给 PR4 的 screenshot gate，不能
  在 PR3 中以 snapshot 变化掩盖行为回归。

## 7. 非目标（本 PR 明确不做）

1. 不修改 Recovery、Sleep、Strain、Physiological Stress、Energy 任一公式、阈值、
   baseline 或缺失规则；
2. 不把 `BodySeekDomain` 接入 Xcode target，不提升 iOS/watchOS deployment target，
   不修改 Watch contract；
3. 不迁移 SwiftData schema、历史 fixture、写入 gate 或 persistence actor；
4. 不同时重做 3+2 Dashboard、删除天气/重复内容、改字体、颜色、动效、AXXXL 或截图；
5. 不删除 `DashboardViewModel`、`VelaServices`、`VelaResolver` 或所有 singleton；只
   建立可替换接缝，删除 locator 是后续逐 feature 的工作；
6. 不把 TodayStore 变成全 App session store，也不让 Nutrition、AI、Plan、Coach、
   Trends 反向拥有 P0 健康读取；
7. 不让 View 直接写 Lived State/feedback、读 HealthKit/SwiftData/UserDefaults，或
   通过“临时 helper”绕过 Store；
8. 不要求真实 iPhone↔Apple Watch 配对 runtime 证据作为 PR3 的完成条件；该证据属于
   CC-08/发布 gate，但 PR3 不得破坏其 adapter 接口。

## 8. PR3 退出条件与下一 handoff

PR3 只有在以下事实均成立时才可标记 integrated：

```text
TodayStore/ViewState/Action 已有明确 constructor 和 fake seams
Today root View 只读 state、只发 Action；静态 guard 无违规生产依赖
主链 refresh/cache/date race/empty/error 语义由 focused tests 固定
PR0 five-score golden 与缺失/版本/source 语义保持一致
天气、Nutrition、AI、Plan、feedback 等非关键失败不会遮蔽主 evidence
AppCoordinator 可由 composition-root owner 一次性注入 Store（无重复 singleton）
```

推荐实现顺序：先新增值类型和 Store/fake tests；再由 composition-root owner 接入
`AppDependencies.today.reader`；最后在 root View 做机械性的 state/action 接线并跑
静态 guard。若需要扩大 `TodayDashboardSnapshot` 或增加辅助 repository，应先在本
契约或独立 DTO PR 中锁定字段，不要在 UI 改动中隐式扩大接口。

本文件的最终状态仍为 **contract-ready**。在 root View 移除 `ModelContext`、
`VelaAppState.shared`、`LocationManager.shared`、`@AppStorage` 以及生命周期副作用，
并完成上述测试前，不能宣称“Today 已完成显式依赖迁移”。
