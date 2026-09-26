一、当前版本的总体审查
1. 产品方向：正确，但功能组织还不够“操作系统化”

现在 Vela 的产品目标已经很清晰：它不是普通健身记录软件，而是本地优先的 AI 健康操作系统。Blueprint 里已经明确 Vela 应成为 private AI health operating system，而不是 fitness dashboard。

但代码和产品实际体验上，现在仍然有明显的“模块并列”问题：

Home 是 Home，Fitness 是 Fitness，Coach 是 Coach，Wiki 是 Wiki，Journal 是 Journal，Training Plan 是 Training Plan。
它们都存在，但用户每天打开 App 时，心智上还没有一个非常明确的主线。

你真正想做的应该是：

今天身体怎么样？
为什么是这样？
今天应该练什么？
练完记录了吗？
明天身体怎么反馈？
Vela 学到了什么？
下次怎么调整？

这才是 Vela 的核心产品闭环。

2. 工程架构：已有分层，但 Domain 边界还不够硬

技术文档现在已经定义了比较完整的分层：SwiftUI Views、ViewModels、Application Layer、Domain Layer、Infrastructure Layer。

这个方向是对的，但目前代码里仍然存在几个问题：

第一，ViewModel 仍然承担太多应用编排职责。比如 CoachChatVM 既管 UI 状态、聊天会话、Keychain、Prompt 构造、工具注册、模型调用、Wiki 更新解析、Food Photo 写入，又处理后台任务续租。这会让 Coach 后续越来越难维护。

第二，DailySummaryUseCase 和 HealthKit sync 绑定较重。Dashboard 刷新时会触发最近 HealthKit 同步，虽然 DashboardViewModel 已经有刷新防抖逻辑，但 loadDashboard 本身仍然默认执行 syncPastDays(syncDays)。

第三，数据模型越来越大。DailyHealthSummaryRecord 已经承担了睡眠、恢复、strain、stress、energy、body、workout、ATL/CTL/TSB 等大量字段。它适合作为缓存 summary，但不适合继续无限扩展成“万能表”。

第四，架构文档里写的 5 个产品域是正确的：Health、Scoring、Memory、Intelligence、Experience。这个应该成为下一版真正的代码边界，而不是只停留在文档里。

3. 数据闭环：已经搭起来，但还没有完全打通

你现在最有价值的进展是训练闭环。代码已经有：

StrengthWorkoutRecord
ActiveWorkoutDraftRecord
ExerciseDefinitionRecord
WorkoutTemplateRecord
TrainingResponseRecord
WorkoutEventRecord
XunjiWorkoutMirrorRecord

这些都已经注册进 VelaModelContainer。

WorkoutAggregationService 也已经能把力量训练转成 WorkoutEventRecord，更新日摘要，并关联 active training plan。

但是关键问题是：

训练记录 → 训练分析 → 次日恢复反应 → Coach 主动调整计划 这条链路还没有成为默认主链路。

代码中 HealthKitSyncEngine 已经会在同步后调用训练反应洞察服务，捕获训练后的恢复反应和周报。

但 Coach 构建上下文时，主要传入的是 FoodLogRecord 和最近 14 天 StrengthWorkoutRecord，没有稳定把 TrainingResponseRecord 传给 AIContextBuilder。而 AIContextBuilder 本身已经设计了 trainingResponses 参数。

这意味着你最想要的高级能力——“Vela 知道我上次练腿后恢复掉了，所以今天自动减量”——还没有真正稳定进入 Coach。

4. AI Coach：Prompt 已经很强，但 Agent 架构还偏弱

CoachPromptComposer 已经比之前成熟很多。它有时间上下文、用户 Wiki、个人基线、今日身体 JSON、训练处方规则、Wiki 长期记忆和 Daily Log 的分流规则。尤其是 Wiki 规则里明确禁止把单日事件写入长期记忆，这是正确的。

ToolFactory 也已经集中注册了 web search、Wiki update、health data、strength history、food log、training plan、chart render 等工具。

但当前 AgentLoop 有一个核心架构问题：它看起来像多轮 tool-call loop，但实际逻辑是一旦模型调用工具，就执行工具，然后直接 stream 最终回答并 return。

这不是完整 Agent。真正的 Active Coach 至少需要：

查今天恢复数据 → 查最近训练历史 → 查训练计划 → 查次日恢复反应 → 生成调整建议 → 必要时生成 artifact 或 memory proposal。

现在的 loop 大概率只能完成一轮工具调用，这会限制 Coach 从“会调用工具的聊天机器人”升级为“主动编排系统”。

二、下一大版本的核心方向

我建议下个大版本聚焦一个主题：

从“功能集合”升级为“身体智能闭环”

不要再优先加新功能。你现在已经有太多功能了。下一版要把它们组织成一个体验闭环。

Vela 4.0 的北极星体验

用户早上打开 Vela，10 秒内应该得到：

我今天身体状态如何？
为什么是这个状态？
今天应该练、减量、休息还是补恢复？
这个建议和我的长期目标有什么关系？
Vela 正在观察我身上的哪个模式？

Blueprint 里对 Home 的要求其实已经写得非常准确：Home 应该按 State、Cause、Plan、Watch、Memory 的顺序回答问题。

所以 Vela 4.0 的核心不是“再做一个页面”，而是做：

Today Operating Loop
三、Vela 4.0 推荐信息架构

我建议保留现在的 5 个主入口，但重新定义它们的职责。

1. Home：今日身体操作台

Home 不再是指标 Dashboard，而是今日决策页。

结构建议：

今日状态 Hero
Recovery / Sleep / Strain / Energy 组合判断。
今日训练决策
Train / Reduce / Swap / Rest 四选一。
今日原因
最多 3 条 driver：例如 HRV 下降、睡眠碎片化、腿部局部疲劳高。
今日行动
一个主要 CTA：开始训练、记录恢复、补充日记、查看计划。
Vela 正在观察
例如“过去 3 次高腿部容量训练后，次日恢复平均下降 8 分”。

这会比现在单纯展示很多分数更有产品力。

2. Fitness：训练执行系统

Fitness 负责训练计划、训练记录、训练历史、肌群疲劳、PR、训练响应。

它不应该只是活动摘要页，而应该是：

当前 active plan
今天建议训练
一键开始训练
上次表现自动填充
肌群局部疲劳
训练后总结
次日恢复反馈

你现在的训练记录页已经具备草稿保存、动作选择、模板、休息计时、RPE/RIR、未完成组处理和保存后刷新。

下一步应该把它从“记录表单”升级为“训练执行器”。

3. Intelligence：不是聊天页，而是 Coach 工作台

Blueprint 里已经提出 Coach 应该变成 Vela Intelligence，包括 chat、proactive check-ins、Wiki/Files、artifacts、plans、reminders。

我建议 Intelligence 首页结构为：

今日主动建议
未处理 Memory Proposal
最近生成的 Artifact
训练计划调整卡
Wiki / Files
Chat

Chat 应该退到工作台的一部分，而不是整个 Intelligence 的主体。

4. Vitals：身体信号监控

Vitals 专注于数据新鲜度、异常、趋势、confidence，不要承担训练建议。

它回答：

哪些指标今天可用？
哪些指标过期？
哪些指标异常？
这个指标和我的个人基线相比如何？
5. Journal / Nutrition：行为上下文层

Journal 不应该被 Coach 对话污染。现在 persistInteraction 会把用户发给 Coach 的问题写成 JournalEntryRecord。

这会影响后续相关性分析，因为“我问了一句 Coach”不是生活行为。

建议拆成：

JournalEntryRecord：用户主动记录的行为/状态；
CoachInteractionRecord：AI 对话归档；
FoodLogRecord：结构化饮食；
CheckInRecord：系统主动问询结果。
四、下一大版本的目标架构

我建议你把 Vela 4.0 重构成 7 个核心内核。

1. BodyStateKernel：身体状态内核

负责统一生成今日身体状态。

输入：

HealthKit snapshot
DailyHealthSummaryRecord
SleepSummaryRecord
WorkoutEventRecord
StrengthWorkoutRecord
FoodLogRecord
JournalEntryRecord
ActiveStatusSettings

输出：

struct BodyState {
    let date: Date
    let readiness: ReadinessState
    let recovery: MetricResult
    let sleep: MetricResult
    let strain: MetricResult
    let energy: MetricResult
    let stress: MetricResult
    let localFatigue: [MuscleGroup: LocalMuscleFatigue]
    let drivers: [BodyStateDriver]
    let confidence: DataConfidence
    let freshness: DataFreshness
}

现在这些信息散落在 DashboardSummary、TrainingDecisionEngine、AIContextBuilder、DailySummaryUseCase 里。下一版应该有一个唯一的 BodyStateKernel 作为身体状态 source of truth。

2. TrainingDecisionKernel：训练决策内核

负责回答今天练什么。

输入：

BodyState
ActiveTrainingPlan
RecentStrengthSummary
TrainingResponseHistory
User constraints
Available equipment

输出：

struct DailyTrainingDecision {
    let decision: TrainDecisionType // keep, reduce, swap, rest
    let targetSession: PlannedSession?
    let adjustedSession: PlannedSession?
    let volumeMultiplier: Double
    let intensityCap: Int
    let reasons: [DecisionReason]
    let userFacingSummary: String
}

现在 TrainingDecisionEngine、RecoveryTrainingAdapter、TrainingAnalyticsService 已经有基础，但需要统一为一个清晰的决策入口。

3. EventStore / Timeline：事件层

你现在有很多 record，但缺少统一“事件流”。

建议新增或整理：

enum VelaEventType {
    case healthSnapshotUpdated
    case workoutLogged
    case foodLogged
    case journalLogged
    case coachConversation
    case trainingResponseCaptured
    case memoryProposalCreated
    case planAdjusted
}

对应：

@Model
final class VelaEventRecord {
    var id: UUID
    var type: String
    var occurredAt: Date
    var source: String
    var payloadJSON: String
    var relatedRecordId: UUID?
}

这样 Evening Review、Weekly Report、Memory Proposal、Coach Context 都可以从统一事件流构建，而不是每次各自 fetch 一堆表。

4. ContextPackBuilder：AI 上下文包

现在 AIContextBuilder 已经很强，但它承担的东西过多。下一版建议分成：

BodyStateContextBuilder
TrainingContextBuilder
NutritionContextBuilder
MemoryContextBuilder
TimelineContextBuilder
ContextPackBuilder

最终输出：

struct CoachContextPack {
    let schemaVersion: String
    let bodyState: BodyStateContext
    let training: TrainingContext
    let nutrition: NutritionContext
    let memory: MemoryContext
    let recentEvents: [TimelineEventContext]
    let availableTools: [ToolDescriptor]
    let safetyPolicy: SafetyPolicyContext
}

这比现在把一堆 JSON 拼到 Prompt 里更可控。

5. AgentOrchestrator：真正的 Agent 编排器

当前 AgentLoop 需要升级。它应该支持：

多轮 tool calls；
工具调用预算；
工具结果压缩；
final response 强制；
trace 保存；
tool error fallback；
artifact creation；
memory proposal creation；
read-only / write mode 分离。

目标结构：

final class AgentOrchestrator {
    func run(request: CoachRequest) async throws -> CoachResponse {
        // 1. Build context pack
        // 2. Select tools
        // 3. Run multi-step tool loop
        // 4. Generate final response
        // 5. Extract artifacts/memory proposals
        // 6. Persist trace
    }
}

当前 AgentRunTrace 已经有 trace 模型雏形，但还没有真正形成可审计 Agent 运行历史。

6. Artifact System：把 AI 输出变成产品对象

Blueprint 已经提到需要 AgentArtifactRecord，用于 chart/table/plan/reminder/wiki-diff payload。

这是 Vela 4.0 很关键的一步。

不要让 AI 只输出 markdown。它应该输出：

今日计划卡
训练调整卡
周报卡
相关性图表
Wiki diff
饮食建议卡
恢复风险卡

新增：

@Model
final class AgentArtifactRecord {
    var id: UUID
    var type: String
    var title: String
    var createdAt: Date
    var payloadJSON: String
    var sourceContextHash: String
    var status: String // active, archived, dismissed
}

这样 Intelligence 就能成为真正的工作台。

7. MemoryLedger 2.0：长期记忆与日记彻底分离

你现在 Wiki proposal 方向是对的，但下一版应该更明确：

Daily Log：事实记录，自动生成；
Journal：用户主动输入；
Memory Proposal：AI 提出的长期记忆候选；
Wiki：用户确认后的长期档案；
WikiChangeRecord：每次变更可审计。

文档里已经把 WikiChangeRecord 列为下一步数据模型，这是必须做的。

五、Vela 4.0 推荐实施路线
P0：先修闭环，不加新功能

这是最重要的。

1. 修 AgentLoop

目标：支持真正多轮工具调用。

验收标准：

用户问“根据今天恢复和最近训练，帮我调整今天计划”；
Agent 可以先调用 health/trends 工具；
再调用 strength history；
再调用 training response；
最后生成回答；
必要时生成 artifact；
全部过程可 trace。
2. 接入 TrainingResponseRecord 到 Coach Context

现在 AIContextBuilder 已经支持 trainingResponses 参数，但 Coach 构建上下文时没有稳定传进去。

要做：

fetch 最近 28/60 天 TrainingResponseRecord；
传入 AIContextBuilder.build；
在 Coach prompt 里明确可用；
在 UI 上展示“Vela 学到的训练反应”。

验收标准：

用户问：“我今天适合练腿吗？”
Vela 可以回答：“你最近两次腿部高容量训练后，次日恢复平均下降 X 分，所以今天建议降容量。”

3. 修力量训练保存边界

必须避免空训练、未完成组污染、容量口径不一致。

当前 validExercises 只判断动作名不为空。

要做：

没有完成组不能保存；
planned volume 和 completed volume 分开；
Coach history 使用 TrainingAnalyticsService 统一口径；
未完成组只保留在 draft，不进入完成记录。
4. 拆分 Coach 对话和 Journal

persistInteraction 不应该把 Coach 用户提问写入普通 Journal。

要做：

新增 CoachInteractionRecord；
JournalCorrelationEngine 默认排除 coach 对话；
Daily Log 可以引用 Coach summary，但不能把对话当行为标签。
5. 统一 workout 聚合 source of truth

现在 WorkoutAggregationService 已经是正确方向。它应该成为唯一训练聚合入口。

要做：

DailyHealthSummaryRecord.apply(snapshot) 不再自己合并 local workouts；
所有 HealthKit / strength / xunji / manual workout 都进入 WorkoutEventRecord；
每日 summary 只由 WorkoutAggregationService.aggregateDay 更新。
P1：搭建 Vela 4.0 新内核
1. 新增 BodyStateKernel

把现在 scattered 的 dashboard / scoring / training decision 聚合为一个身体状态内核。

输出直接供：

Home Hero
Today Plan
Coach Context
Morning Brief
Notification
Training Decision
2. 新增 DailyOperatingPlan

这是下一版最核心的产品对象。

@Model
final class DailyOperatingPlanRecord {
    var dayIdentifier: String
    var generatedAt: Date
    var bodyStateHash: String
    var primaryActionType: String
    var primaryActionTitle: String
    var primaryActionPayloadJSON: String
    var reasonsJSON: String
    var confidence: String
    var status: String // proposed, accepted, completed, skipped
}

这样 Home 不再只是“显示指标”，而是显示今天的操作计划。

3. 新增 AgentArtifactRecord

AI 生成的训练计划、周报、相关性图、Wiki diff 都应保存成 Artifact，而不是混在聊天气泡里。

4. 新增 HealthTrendTool / TrainingResponseTool

当前 HealthDataTool 主要查 today dashboard，不够支撑历史分析。要新增：

get_health_trends(days, metrics)
get_training_response_history(days, muscleGroup?)
get_active_plan_status()
get_local_muscle_fatigue(days)

这样 Coach 才能真正从“知道今天”变成“理解一段时间”。

P2：体验产品化
1. Home 重构为 Today OS

不是展示一堆卡片，而是围绕一个今日计划组织。

建议首屏：

顶部：今天 / 数据新鲜度 / 同步状态
Hero：Readiness + Recovery 主状态
Plan：今天建议
Why：3 个原因
Watch：Vela 正在观察的模式
Action：开始训练 / 记录状态 / 问 Coach
2. Fitness 重构为 Training Execution

训练中页面要优先优化真实使用体验：

大按钮完成组；
上次表现常驻；
自动进入下一组；
Rest timer 可调整；
RPE/RIR 默认折叠；
保存后立刻生成总结；
总结页给出下次建议。
3. Intelligence 重构为 Workspace

Intelligence 不应该一打开就是空聊天框，而应该是：

Proactive Insight
Today Plan Artifact
Memory Inbox
Recent Artifacts
Wiki Files
Chat

这会让你的 AI 能力更像产品，而不是 Chatbot。

六、PRD 和架构文档也要同步改

现在文档里有一个重要冲突：PRD 一方面写 local-first、不做云同步、不搭建后端，API Key 保存在 Keychain。

另一方面又写 VelaBackend 提供 Coach chat、Today Plan、Training Adaptations 等路由。

这会影响后续开发判断。

建议统一成：

Vela 是 local-first health data system。健康原始数据、本地摘要、Wiki、训练记录、Journal 默认保存在设备端；AI 执行层可以是本地直连 Provider，也可以是可选 VelaBackend Provider。后端只能接收结构化摘要，不接收原始 HealthKit 数据。

这样架构才清楚。

七、我建议的大版本命名与范围
推荐版本名
Vela 4.0: Active Coach OS
版本目标

把 Vela 从“健康数据 + AI 聊天 + 训练记录”升级为：

一个每天能主动判断身体状态、生成训练/恢复计划、记录执行、学习反馈、维护记忆的个人身体操作系统。

版本不做什么

为了避免继续膨胀，Vela 4.0 不建议优先做：

更复杂的 Biology；
更多第三方平台导入；
社交；
云同步；
大规模商业化账户体系；
更多花哨 UI 页面；
大量新评分指标。

先把已有能力做成闭环。