import BodySeekCore
import Foundation
import os

// MARK: - Captured Side Effects (Confirm-to-Write Proposals & Tool Provenance)

public actor AgentCapturedSideEffects: Sendable {
    public private(set) var workoutProposal: WorkoutProposal?
    public private(set) var memoryProposal: TieredMemoryRecord?
    public private(set) var workoutAnnotationProposal: CoachWorkoutAnnotationProposal?
    public private(set) var workoutAnnotationCandidates: [CoachWorkoutAnnotationCandidate] = []
    public private(set) var toolOutputs: [String] = []
    public private(set) var toolsInvoked: [String] = []
    /// 通过动作层自动执行（A、B 级）并返回的回执。
    public private(set) var appliedActions: [AppActionReceipt] = []

    public init() {}

    public func recordAppliedAction(_ receipt: AppActionReceipt) {
        appliedActions.append(receipt)
    }

    public func recordProposal(_ proposal: WorkoutProposal) {
        workoutProposal = proposal
    }

    public func recordMemoryProposal(_ record: TieredMemoryRecord) {
        memoryProposal = record
    }

    public func recordWorkoutAnnotationProposal(_ proposal: CoachWorkoutAnnotationProposal) {
        workoutAnnotationProposal = proposal
    }

    public func recordWorkoutAnnotationCandidates(_ candidates: [CoachWorkoutAnnotationCandidate]) {
        workoutAnnotationCandidates = candidates
    }

    public func recordToolInvocation(name: String, output: String) {
        toolsInvoked.append(name)
        toolOutputs.append(output)
    }
}

public struct AgentExecutionContext: Sendable {
    public let conversationHistory: [CoachMessage]
    public let snapshot: BodySeekDashboardSnapshot
    public let asOf: Date
    public let sessions: [LoggedWorkoutSession]
    public let templates: [WorkoutTemplate]
    public let memories: [AthleteMemoryItem]
    public let tieredMemories: [TieredMemoryRecord]
    public let deletedWorkoutUUIDs: Set<String>
    public let storedWorkouts: [StoredWorkoutRecord]
    public let annotationsByWorkoutUUID: [String: WorkoutAnnotationRecord]
    public let muscleLoads: [WorkoutMuscleLoadRecord]
    public let patternFindings: [PatternFindingRecord]
    public let todayNutritionLog: DailyNutritionLog?
    public let nutritionTargetPlan: NutritionTargetPlan?
    public let nutritionLogs: [DailyNutritionLog]
    public let checkIns: [DailyCheckIn]
    public let dominantHand: DominantHand
    public let sleepGoalMinutes: Int
    public let effects: AgentCapturedSideEffects
    /// 动作层入口；为 `nil` 时提案工具只生成确认卡片，不直接写入。
    public let actionGateway: AgentActionGateway?

    public init(
        snapshot: BodySeekDashboardSnapshot,
        sessions: [LoggedWorkoutSession] = [],
        templates: [WorkoutTemplate] = [],
        memories: [AthleteMemoryItem] = [],
        tieredMemories: [TieredMemoryRecord] = [],
        storedWorkouts: [StoredWorkoutRecord] = [],
        deletedWorkoutUUIDs: Set<String> = [],
        annotationsByWorkoutUUID: [String: WorkoutAnnotationRecord] = [:],
        muscleLoads: [WorkoutMuscleLoadRecord] = [],
        patternFindings: [PatternFindingRecord] = [],
        todayNutritionLog: DailyNutritionLog? = nil,
        nutritionTargetPlan: NutritionTargetPlan? = nil,
        nutritionLogs: [DailyNutritionLog] = [],
        checkIns: [DailyCheckIn] = [],
        dominantHand: DominantHand = .right,
        sleepGoalMinutes: Int = 450,
        asOf: Date? = nil,
        conversationHistory: [CoachMessage] = [],
        effects: AgentCapturedSideEffects = AgentCapturedSideEffects(),
        actionGateway: AgentActionGateway? = nil
    ) {
        self.snapshot = snapshot
        self.conversationHistory = Array(conversationHistory.suffix(6))
        self.asOf = asOf ?? snapshot.referenceDate
        self.sessions = sessions
        self.templates = templates
        self.memories = memories
        self.tieredMemories = tieredMemories.isEmpty && !memories.isEmpty
            ? MemoryContextSelector.bridgeFromLegacy(memories)
            : tieredMemories
        self.deletedWorkoutUUIDs = deletedWorkoutUUIDs
        self.storedWorkouts = (storedWorkouts.isEmpty ? Self.fallbackStoredWorkouts(from: snapshot) : storedWorkouts)
            .filter { !deletedWorkoutUUIDs.contains($0.hkUUID.lowercased()) }
        self.annotationsByWorkoutUUID = annotationsByWorkoutUUID
        self.muscleLoads = muscleLoads
        self.patternFindings = patternFindings
        self.todayNutritionLog = todayNutritionLog
        self.nutritionTargetPlan = nutritionTargetPlan
        self.nutritionLogs = nutritionLogs.isEmpty
            ? (todayNutritionLog.map { [$0] } ?? [])
            : nutritionLogs
        self.checkIns = checkIns
        self.dominantHand = dominantHand
        self.sleepGoalMinutes = sleepGoalMinutes
        self.effects = effects
        self.actionGateway = actionGateway
    }

    private static func fallbackStoredWorkouts(from snapshot: BodySeekDashboardSnapshot) -> [StoredWorkoutRecord] {
        snapshot.historyDays.flatMap { day in
            day.raw.workouts.map { summary in
                let uuid = (summary.healthKitUUID ?? summary.id).uuidString
                let end = summary.endDate
                return StoredWorkoutRecord(
                    hkUUID: uuid,
                    type: summary.activityName,
                    start: summary.startDate,
                    end: end,
                    energy: summary.activeEnergyKcal,
                    avgHR: summary.averageHeartRate,
                    zones: summary.heartRateZones,
                    effortUser: summary.effortScore,
                    effortEstimated: summary.estimatedEffortScore,
                    reviewState: .unreviewed
                )
            }
        }
    }
}

// MARK: - 4-State Tool Response Envelope

private struct ToolEnvelope<Payload: Encodable>: Encodable {
    let ontologyVersion = "bodyseek-evidence-v1"
    let tool: String
    let state: String
    let coverage: Double?
    let reason: String?
    let algorithmVersion: String
    let data: Payload
    /// Typed numbers for the provenance verifier. Only tools that can bind a value
    /// to a metric, window/date and unit populate this.
    let evidence: [EvidenceFact]?
    let truncated: Bool?
}

private struct AnnotationCandidateSummary: Encodable {
    let workoutUUID: String
    let workoutTitle: String
    let dayKey: String
    let start: Date
    let end: Date
    let reviewState: String
    let latestAnnotation: String?

    init(_ candidate: CoachWorkoutAnnotationCandidate) {
        self.workoutUUID = candidate.proposal.workoutUUID
        self.workoutTitle = candidate.proposal.workoutTitle
        self.dayKey = candidate.dayKey
        self.start = candidate.start
        self.end = candidate.end
        self.reviewState = candidate.reviewState.rawValue
        self.latestAnnotation = candidate.proposal.recordState?.latestAnnotationRawText
    }
}

public enum CoachToolRegistry {
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "CoachToolRegistry")

    public static let openAIToolDefinitions: [OpenAIToolDefinition] = [
        OpenAIToolDefinition(function: OpenAIFunctionDefinition(
            name: "get_today_context",
            description: "读取今日五项评分、原始生理体征（四态+覆盖度）、ACWR负荷比与主观打卡状态。",
            parameters: OpenAIToolParametersObject()
        )),
        OpenAIToolDefinition(function: OpenAIFunctionDefinition(
            name: "get_metric_trend",
            description: "查询恢复/睡眠/负荷/压力/能量在7天、30天、6个月或3年内的覆盖度与变化统计。",
            parameters: OpenAIToolParametersObject(
                properties: [
                    "metric": OpenAIToolParameterSchema(type: "string", description: "recovery, sleep, strain, stress, energy", enumValues: ["recovery", "sleep", "strain", "stress", "energy"]),
                    "horizon": OpenAIToolParameterSchema(type: "string", description: "7d, 30d, 6m, 3y", enumValues: ["7d", "30d", "6m", "3y"]),
                ],
                required: ["metric", "horizon"]
            )
        )),
        OpenAIToolDefinition(function: OpenAIFunctionDefinition(
            name: "get_weekly_recovery_evidence",
            description: "按本地 04:00 生理日比较最近 7 天与此前不重叠的 28 天：恢复、睡眠、训练、体感和饮食的逐日观测、覆盖率、四态计数与统计样本数。用于回答「这周恢复为什么下降」等问题。",
            parameters: OpenAIToolParametersObject(
                properties: [
                    "end_day_key": OpenAIToolParameterSchema(type: "string", description: "可选结束日 YYYY-MM-DD；省略使用当前生理日"),
                ]
            )
        )),
        OpenAIToolDefinition(function: OpenAIFunctionDefinition(
            name: "get_workouts_and_muscles",
            description: "读取近N天Apple Watch训练（严格区分EffortUser与Estimated）及肌群恢复度（启发式估计）。",
            parameters: OpenAIToolParametersObject(
                properties: [
                    "days": OpenAIToolParameterSchema(type: "integer", description: "回看天数，例如7或14"),
                    "muscle": OpenAIToolParameterSchema(type: "string", description: "可选肌群ID或中文名，如 chest、quadriceps、胸部"),
                ],
                required: ["days"]
            )
        )),
        OpenAIToolDefinition(function: OpenAIFunctionDefinition(
            name: "get_sleep_detail",
            description: "读取指定日期或昨晚睡眠分期时长、睡眠效率和目标差值。",
            parameters: OpenAIToolParametersObject(
                properties: [
                    "day": OpenAIToolParameterSchema(type: "string", description: "可选日期 YYYY-MM-DD，省略则查今日"),
                ]
            )
        )),
        OpenAIToolDefinition(function: OpenAIFunctionDefinition(
            name: "get_patterns",
            description: "读取历史已发现且非因果的个人统计规律（Correlation/Bootstrap CI）。",
            parameters: OpenAIToolParametersObject(
                properties: [
                    "topic": OpenAIToolParameterSchema(type: "string", description: "可选关键词，如 sleep, hrv, caffeine, strain"),
                ]
            )
        )),
        OpenAIToolDefinition(function: OpenAIFunctionDefinition(
            name: "find_similar_days",
            description: "基于目标日之前的客观生理状态（无未来数据泄露），检索历史最相似日期及其次日实际结局。",
            parameters: OpenAIToolParametersObject(
                properties: [
                    "day": OpenAIToolParameterSchema(type: "string", description: "可选目标日 YYYY-MM-DD，默认为今日"),
                ]
            )
        )),
        OpenAIToolDefinition(function: OpenAIFunctionDefinition(
            name: "get_eating_context",
            description: "读取近N天饮食热量、宏量/微量营养素、达标与能量平衡记录；AI 估算与记录不完整会单独标注；未记录时如实返回缺失。",
            parameters: OpenAIToolParametersObject(
                properties: [
                    "days": OpenAIToolParameterSchema(type: "integer", description: "查询天数，默认7"),
                ]
            )
        )),
        OpenAIToolDefinition(function: OpenAIFunctionDefinition(
            name: "get_personal_forecast",
            description: "调用端侧 CoreML 个人统计预测模型（仅基于历史因果特征），输出次日夜间 HRV、静息心率与睡眠效率的点估计及 80%/90% Split-Conformal 区间，附“个人统计预测，非医学诊断”声明。",
            parameters: OpenAIToolParametersObject()
        )),
        OpenAIToolDefinition(function: OpenAIFunctionDefinition(
            name: "search_exercise_catalog",
            description: "按肌群或关键词检索内置动作库ID，用于构造训练提案。",
            parameters: OpenAIToolParametersObject(
                properties: [
                    "query": OpenAIToolParameterSchema(type: "string", description: "肌群或动作关键词"),
                ],
                required: ["query"]
            )
        )),
        OpenAIToolDefinition(function: OpenAIFunctionDefinition(
            name: "propose_plan_change",
            description: "生成待用户确认的结构化今日训练处方卡片（C 级：必须用户确认，不会静默写入数据库）。",
            parameters: OpenAIToolParametersObject(
                properties: [
                    "title": OpenAIToolParameterSchema(type: "string", description: "课表标题"),
                    "focusTag": OpenAIToolParameterSchema(type: "string", description: "强度标签，如 减量、维持、推进"),
                    "exerciseIDsCSV": OpenAIToolParameterSchema(type: "string", description: "逗号分隔动作ID"),
                    "intensityMultiplier": OpenAIToolParameterSchema(type: "number", description: "强度系数 0.5 到 1.2"),
                    "restSeconds": OpenAIToolParameterSchema(type: "integer", description: "组间休息秒数"),
                    "rationale": OpenAIToolParameterSchema(type: "string", description: "基于生理与记忆的理由"),
                ],
                required: ["title", "focusTag", "exerciseIDsCSV", "intensityMultiplier", "restSeconds", "rationale"]
            )
        )),
        OpenAIToolDefinition(function: OpenAIFunctionDefinition(
            name: "propose_memory",
            description: "保存一条记忆（profile 或 activeConstraint）。A 级：直接保存并返回可撤销的回执；动作层不可用或失败时退回待用户确认的提案卡片。",
            parameters: OpenAIToolParametersObject(
                properties: [
                    "tier": OpenAIToolParameterSchema(type: "string", description: "profile, activeConstraint 或 verifiedPattern", enumValues: ["profile", "activeConstraint", "verifiedPattern"]),
                    "content": OpenAIToolParameterSchema(type: "string", description: "清晰简洁的记忆内容"),
                    "category": OpenAIToolParameterSchema(type: "string", description: "可选兼容标签: injury, goal, preference, schedule"),
                    "expiresDays": OpenAIToolParameterSchema(type: "integer", description: "activeConstraint 过期天数，默认14"),
                    "patternID": OpenAIToolParameterSchema(type: "string", description: "verifiedPattern 必填的已确认规律UUID"),
                ],
                required: ["tier", "content"]
            )
        )),
        OpenAIToolDefinition(function: OpenAIFunctionDefinition(
            name: "propose_workout_annotation",
            description: "解析用户的一句话训练描述并给 Watch 训练补肌群标注。A 级：唯一匹配时直接标注并返回可撤销的回执；有多条候选或动作层不可用时退回待确认卡片。保留用户所说的训练日期。",
            parameters: OpenAIToolParametersObject(
                properties: [
                    "rawText": OpenAIToolParameterSchema(type: "string", description: "用户描述今天练了什么与感受的一句话"),
                    "workoutUUID": OpenAIToolParameterSchema(type: "string", description: "可选 Watch 训练 UUID。省略时按描述中的日期匹配，未说明日期时只查今天。"),
                ],
                required: ["rawText"]
            )
        )),
        OpenAIToolDefinition(function: OpenAIFunctionDefinition(
            name: "execute_action",
            description: "通过动作层执行写入。A 级（save_memory、annotate_workout）直接执行并返回可撤销回执；B 级（retire_memory）直接执行，24 小时内可撤销；C 级（delete_meal）不会执行，只返回需要用户确认。",
            parameters: OpenAIToolParametersObject(
                properties: [
                    "action": OpenAIToolParameterSchema(type: "string", description: "save_memory、retire_memory、annotate_workout 或 delete_meal", enumValues: ["save_memory", "retire_memory", "annotate_workout", "delete_meal"]),
                    "content": OpenAIToolParameterSchema(type: "string", description: "save_memory：记忆内容"),
                    "tier": OpenAIToolParameterSchema(type: "string", description: "save_memory：profile 或 activeConstraint", enumValues: ["profile", "activeConstraint", "verifiedPattern"]),
                    "category": OpenAIToolParameterSchema(type: "string", description: "save_memory：injury、goal、preference 或 schedule"),
                    "expiresDays": OpenAIToolParameterSchema(type: "integer", description: "save_memory：activeConstraint 过期天数，默认 14"),
                    "patternID": OpenAIToolParameterSchema(type: "string", description: "save_memory：verifiedPattern 必填的已确认规律 UUID"),
                    "memoryID": OpenAIToolParameterSchema(type: "string", description: "retire_memory：要停用的记忆 UUID"),
                    "rawText": OpenAIToolParameterSchema(type: "string", description: "annotate_workout：用户描述训练的一句话"),
                    "workoutUUID": OpenAIToolParameterSchema(type: "string", description: "annotate_workout：可选 Watch 训练 UUID"),
                    "dayKey": OpenAIToolParameterSchema(type: "string", description: "delete_meal：YYYY-MM-DD"),
                    "entryID": OpenAIToolParameterSchema(type: "string", description: "delete_meal：餐食记录 UUID"),
                ],
                required: ["action"]
            )
        )),
    ]

    public static func execute(
        name: String,
        argumentsJSON: String,
        context: AgentExecutionContext
    ) async -> String {
        let args = decodeArgs(argumentsJSON, toolName: name)
        let output: String

        switch name {
        case "get_today_context":
            output = todayContextJSON(context: context)
        case "get_metric_trend":
            output = metricTrendJSON(
                metricRaw: stringArg(args, "metric") ?? "recovery",
                horizonRaw: stringArg(args, "horizon") ?? "7d",
                context: context
            )
        case "get_weekly_recovery_evidence":
            output = weeklyRecoveryEvidenceJSON(
                endDayKeyString: stringArg(args, "end_day_key"),
                context: context
            )
        case "get_workouts_and_muscles":
            output = workoutsAndMusclesJSON(
                days: intArg(args, "days") ?? 7,
                muscleFilter: stringArg(args, "muscle"),
                context: context
            )
        case "get_sleep_detail":
            output = sleepDetailJSON(dayString: stringArg(args, "day"), context: context)
        case "get_patterns":
            output = patternsJSON(topic: stringArg(args, "topic"), context: context)
        case "find_similar_days":
            output = similarDaysJSON(dayString: stringArg(args, "day"), context: context)
        case "get_eating_context":
            let compactArg: Bool
            if case let .bool(flag) = args["compact"] {
                compactArg = flag
            } else {
                compactArg = false
            }
            output = eatingContextJSON(days: intArg(args, "days") ?? 7, compact: compactArg, context: context)
        case "get_personal_forecast":
            output = personalForecastJSON(context: context)
        case "search_exercise_catalog":
            output = searchExercisesJSON(query: stringArg(args, "query") ?? "")
        case "propose_plan_change":
            output = await proposePlanChangeJSON(
                title: stringArg(args, "title") ?? "适配训练",
                focusTag: stringArg(args, "focusTag") ?? "维持",
                exerciseIDsCSV: stringArg(args, "exerciseIDsCSV") ?? "barbell-bench-press,lat-pulldown",
                intensityMultiplier: doubleArg(args, "intensityMultiplier") ?? 0.85,
                restSeconds: intArg(args, "restSeconds") ?? 90,
                rationale: stringArg(args, "rationale") ?? "结合今日生理状态制定",
                context: context
            )
        case "propose_memory":
            output = await proposeMemoryJSON(
                tierRaw: stringArg(args, "tier") ?? "activeConstraint",
                content: stringArg(args, "content") ?? "",
                categoryRaw: stringArg(args, "category") ?? "preference",
                expiresDays: intArg(args, "expiresDays") ?? 14,
                patternIDString: stringArg(args, "patternID"),
                context: context
            )
        case "propose_workout_annotation":
            output = await proposeWorkoutAnnotationJSON(
                rawText: stringArg(args, "rawText") ?? "",
                workoutUUID: stringArg(args, "workoutUUID"),
                context: context
            )
        case "execute_action":
            output = await executeActionJSON(argumentsJSON: argumentsJSON, context: context)
        default:
            output = encodeEnvelope(tool: name, state: "missing", coverage: 0, reason: "未知工具 \(name)", data: ["error": "unknown_tool"])
        }

        await context.effects.recordToolInvocation(name: name, output: output)
        return output
    }

    // MARK: - Tool Implementations

    private static func todayContextJSON(context: AgentExecutionContext) -> String {
        struct MetricEntry: Encodable {
            let kind: String
            let value: Int?
            let state: String
            let reason: String?
            let baselineDelta: Int?
        }
        struct TodayPayload: Encodable {
            let dayKey: String
            let isAuthorized: Bool
            let sourceLabel: String
            let scores: [MetricEntry]
            let hrvMs: Double?
            let restingHeartRateBpm: Double?
            let sleepAsleepMinutes: Int?
            let activeEnergyKcal: Double?
            let acwrRatio: Double?
            let acwrZone: String
            let acute7dLoad: Double
            let acuteCoveredDays: Int
            let chronicCoveredDays: Int
            let priorBaselineDays: Int
            let unreviewedWatchWorkouts: Int
            let todayCheckInEnergy: Int?
            let todayCheckInStress: Int?
            /// 预先算好的派生值（UI v4 §6.1），回答里直接引用，不必自己换算。
            let derived: TodayDerivedValues
        }


        let today = context.snapshot.today
        let scores = MetricKind.allCases.map { kind in
            let s = today.score(for: kind)
            return MetricEntry(
                kind: kind.rawValue,
                value: s.value,
                state: stateLabel(for: s.availability),
                reason: s.availability.reasonText,
                baselineDelta: s.baselineDelta
            )
        }
        let availableCount = scores.filter { $0.state == "available" }.count
        let coverage = Double(availableCount) / Double(MetricKind.allCases.count)
        let todayCheckIn = context.checkIns.first(where: { $0.dayKey == today.dayKey })
        let unreviewed = context.storedWorkouts.filter { $0.reviewState == .unreviewed }.count

        let stateStr: String
        let reasonStr: String?
        if !context.snapshot.isAuthorized {
            stateStr = "missing"
            reasonStr = "Apple 健康尚未授权"
        } else if availableCount == 0 {
            stateStr = "missing"
            reasonStr = "今日五项生理数据均处于待同步或缺失状态"
        } else {
            stateStr = "available"
            reasonStr = nil
        }

        let payload = TodayPayload(
            dayKey: today.dayKey.isoString,
            isAuthorized: context.snapshot.isAuthorized,
            sourceLabel: context.snapshot.sourceLabel,
            scores: scores,
            hrvMs: today.raw.hrvMs,
            restingHeartRateBpm: today.raw.restingHeartRateBpm,
            sleepAsleepMinutes: today.raw.sleepAsleepMinutes,
            activeEnergyKcal: today.raw.activeEnergyKcal,
            acwrRatio: context.snapshot.trainingLoad.acwrRatio,
            acwrZone: context.snapshot.trainingLoad.zone.title,
            acute7dLoad: (context.snapshot.trainingLoad.acute7dLoad * 10).rounded() / 10,
            acuteCoveredDays: context.snapshot.trainingLoad.acuteCoveredDays,
            chronicCoveredDays: context.snapshot.trainingLoad.chronicCoveredDays,
            priorBaselineDays: context.snapshot.trainingLoad.priorBaselineDays,
            unreviewedWatchWorkouts: unreviewed,
            todayCheckInEnergy: todayCheckIn?.energy,
            todayCheckInStress: todayCheckIn?.stress,
            derived: todayDerived(today: today, context: context)
        )
        return encodeEnvelope(
            tool: "get_today_context",
            state: stateStr,
            coverage: coverage,
            reason: reasonStr,
            algorithmVersion: context.snapshot.scoreAlgorithmVersion.description,
            data: payload
        )
    }

    private static let percentScale = 100.0
    private static let derivedWindowDays = 14
    private static let recoveryWindowDays = 7

    private static func oneDecimal(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private static func difference(_ lhs: Double?, _ rhs: Double?) -> Double? {
        guard let lhs, let rhs else { return nil }
        return oneDecimal(lhs - rhs)
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// 今日关键值与近期窗口均值的差值，以及睡眠时长的两种写法（x.y 小时 / x 小时 y 分）。
    private static func todayDerived(today: DailyComputedDay, context: AgentExecutionContext) -> TodayDerivedValues {
        let prior = context.snapshot.historyDays.filter { $0.dayKey != today.dayKey }
        let window = Array(prior.suffix(derivedWindowDays))
        let hrvMean = mean(window.compactMap(\.raw.hrvMs))
        let rhrMean = mean(window.compactMap(\.raw.restingHeartRateBpm))
        let recoveryMean = mean(prior.suffix(recoveryWindowDays).compactMap { $0.recovery.value.map(Double.init) })
        let minutes = today.raw.sleepAsleepMinutes
        return TodayDerivedValues(
            sleepAsleepHours: minutes.map { oneDecimal(Double($0) / 60) },
            sleepAsleepHourPart: minutes.map { $0 / 60 },
            sleepAsleepMinutePart: minutes.map { $0 % 60 },
            sleepAsleepText: minutes.map { "\($0 / 60) 小时 \($0 % 60) 分" },
            hrv14dMeanMs: hrvMean.map(oneDecimal),
            hrvVs14dMeanMs: difference(today.raw.hrvMs, hrvMean),
            restingHeartRate14dMeanBpm: rhrMean.map(oneDecimal),
            restingHeartRateVs14dMeanBpm: difference(today.raw.restingHeartRateBpm, rhrMean),
            recovery7dMean: recoveryMean.map(oneDecimal),
            recoveryVs7dMean: difference(today.recovery.value.map(Double.init), recoveryMean),
            recordedDays14d: window.filter { $0.raw.hrvMs != nil || $0.raw.sleepAsleepMinutes != nil }.count
        )
    }

    private static func metricTrendJSON(metricRaw: String, horizonRaw: String, context: AgentExecutionContext) -> String {
        struct TrendPayload: Encodable {
            let metric: String
            let horizon: String
            let startDayKey: String?
            let endDayKey: String?
            let unit: String
            let coveredDays: Int
            let totalDays: Int
            let median: Int?
            let minValue: Int?
            let maxValue: Int?
            let deltaFromFirstHalf: Int?
            let latestValue: Int?
            let latestState: String
            let excludedDays: Int
            let knownZeroDays: Int
            let missingDays: Int
            /// 预先算好的派生值（UI v4 §6.1）。
            let mean: Double?
            let firstHalfMean: Double?
            let secondHalfMean: Double?
            let deltaPercentFromFirstHalf: Double?
            let latestVsMean: Double?
        }

        let kind = MetricKind(rawValue: metricRaw.lowercased()) ?? .recovery
        let horizon: TrendHorizon = switch horizonRaw.lowercased() {
        case "30d", "month": .month
        case "6m", "sixmonths": .sixMonths
        case "3y", "threeyears": .threeYears
        default: .week
        }

        let slice = Array(context.snapshot.historyDays.suffix(horizon.dayCount))
        let total = slice.count
        var vals: [Int] = []
        var excluded = 0
        var knownZero = 0
        var missing = 0

        for day in slice {
            let s = day.score(for: kind)
            switch s.availability {
            case .available:
                if let v = s.value { vals.append(v) }
            case .excluded:
                excluded += 1
            case .knownZero:
                knownZero += 1
            case .missing:
                missing += 1
            }
        }

        let sortedVals = vals.sorted()
        let median: Int? = sortedVals.isEmpty ? nil : sortedVals[sortedVals.count / 2]
        var deltaFirstHalf: Int?
        if vals.count >= 4 {
            let mid = vals.count / 2
            let firstMean = Double(vals.prefix(mid).reduce(0, +)) / Double(mid)
            let secondMean = Double(vals.suffix(vals.count - mid).reduce(0, +)) / Double(vals.count - mid)
            deltaFirstHalf = Int((secondMean - firstMean).rounded())
        }

        let latestScore = slice.last?.score(for: kind)
        let windowMean = mean(vals.map(Double.init))
        let halves: (first: Double, second: Double)? = {
            guard vals.count >= 4 else { return nil }
            let mid = vals.count / 2
            guard let first = mean(vals.prefix(mid).map(Double.init)),
                  let second = mean(vals.suffix(vals.count - mid).map(Double.init))
            else { return nil }
            return (first, second)
        }()
        let coverage = total > 0 ? Double(vals.count + knownZero) / Double(total) : 0
        let stateStr = vals.isEmpty && knownZero == 0 ? "missing" : "available"
        let reasonStr = stateStr == "missing" ? "该窗口内 \(kind.title) 无有效观测值" : nil

        return encodeEnvelope(
            tool: "get_metric_trend",
            state: stateStr,
            coverage: coverage,
            reason: reasonStr,
            algorithmVersion: context.snapshot.scoreAlgorithmVersion.description,
            data: TrendPayload(
                metric: kind.rawValue,
                horizon: horizon.title,
                startDayKey: slice.first?.dayKey.isoString,
                endDayKey: slice.last?.dayKey.isoString,
                unit: "score_0_100",
                coveredDays: vals.count,
                totalDays: total,
                median: median,
                minValue: sortedVals.first,
                maxValue: sortedVals.last,
                deltaFromFirstHalf: deltaFirstHalf,
                latestValue: latestScore?.value,
                latestState: latestScore.map { stateLabel(for: $0.availability) } ?? "missing",
                excludedDays: excluded,
                knownZeroDays: knownZero,
                missingDays: missing,
                mean: windowMean.map(oneDecimal),
                firstHalfMean: halves.map { oneDecimal($0.first) },
                secondHalfMean: halves.map { oneDecimal($0.second) },
                deltaPercentFromFirstHalf: halves.flatMap { pair in
                    pair.first > 0 ? oneDecimal((pair.second - pair.first) / pair.first * percentScale) : nil
                },
                latestVsMean: difference(latestScore?.value.map(Double.init), windowMean)
            )
        )
    }

    private static func weeklyRecoveryEvidenceJSON(
        endDayKeyString: String?,
        context: AgentExecutionContext
    ) -> String {
        do {
            let endDay: DayKey? = try endDayKeyString.map { raw in
                guard let key = DayKey(isoString: raw) else {
                    throw WeeklyRecoveryEvidenceError.invalidDayKey(raw)
                }
                return key
            }
            let evidence = try WeeklyRecoveryEvidenceBuilder.build(
                endDayKey: endDay,
                asOf: context.asOf,
                context: context
            )
            let state = evidence.recovery.evidenceSufficient ? "available" : "missing"
            let reason = evidence.recovery.evidenceSufficient ? nil : evidence.recovery.note
            return encodeEnvelope(
                tool: "get_weekly_recovery_evidence",
                state: state,
                coverage: evidence.target.metricStats.first { $0.metric == MetricKind.recovery.rawValue }?.coverage,
                reason: reason,
                algorithmVersion: context.snapshot.scoreAlgorithmVersion.description,
                data: evidence,
                evidence: evidence.evidence,
                truncated: evidence.truncated
            )
        } catch {
            return encodeEnvelope(
                tool: "get_weekly_recovery_evidence",
                state: "excluded",
                coverage: 0,
                reason: error.localizedDescription,
                data: ["error": "invalid_or_future_day"]
            )
        }
    }

    private static func workoutsAndMusclesJSON(
        days: Int,
        muscleFilter: String?,
        context: AgentExecutionContext
    ) -> String {
        struct WorkoutItem: Encodable {
            let uuid: String
            let source: String
            let manualSessionID: String?
            let type: String
            let dayKey: String
            let durationMinutes: Int
            let energyKcal: Int?
            let estimatedEnergyKcal: Int?
            let avgHR: Double?
            let effortUser: Double?
            let effortEstimated: Double?
            let reviewState: String
            let annotationText: String?
            let manualVolumeKg: Double?
        }
        struct MuscleItem: Encodable {
            let muscleID: String
            let muscleTitle: String
            let recoveryPercent: Int
            let hoursUntilReady: Double
            let isReady: Bool
            let lastTrainedTitle: String?
        }
        struct WorkoutsAndMusclesPayload: Encodable {
            let windowDays: Int
            let startDayKey: String
            let endDayKey: String
            let workoutCount: Int
            let estimationLabel: String
            let systemicAlpha: Double
            let systemicSummary: String
            let workouts: [WorkoutItem]
            let muscleEstimates: [MuscleItem]
        }

        let clampedDays = min(90, max(1, days))
        let dayEnd = context.asOf
        let endDay = dayEnd.physiologicalDayKey()
        let startDay = endDay.addingDays(1 - clampedDays)
        let recentWorkouts = context.storedWorkouts.filter {
            $0.start.physiologicalDayKey() >= startDay && $0.end <= dayEnd
        }
        let manual = context.sessions.filter {
            $0.startedAt.physiologicalDayKey() >= startDay && $0.completedAt <= dayEnd
        }
        let linked = Dictionary(grouping: manual.compactMap { session in
            session.syncedHealthKitUUID.map { ($0.lowercased(), session) }
        }, by: { $0.0 })
        let importedIDs = Set(recentWorkouts.map { $0.hkUUID.lowercased() })

        let recSnap = MuscleRecoveryEngine.compute(
            asOf: dayEnd,
            storedWorkouts: context.storedWorkouts,
            muscleLoads: context.muscleLoads,
            manualSessions: context.sessions,
            historyDays: context.snapshot.historyDays,
            sleepGoalMinutes: context.sleepGoalMinutes,
            dominantHand: context.dominantHand,
            deletedWorkoutUUIDs: context.deletedWorkoutUUIDs
        )

        let filterClean = muscleFilter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredMuscles = BodyRegionMuscle.allCases.compactMap { m -> MuscleItem? in
            if let f = filterClean, !f.isEmpty {
                let matched = m.rawValue.lowercased().contains(f) || m.title.lowercased().contains(f)
                guard matched else { return nil }
            }
            let est = recSnap.estimate(for: m)
            return MuscleItem(
                muscleID: m.rawValue,
                muscleTitle: m.title,
                recoveryPercent: est.recoveryPercent,
                hoursUntilReady: (est.hoursUntilReady * 10).rounded() / 10,
                isReady: est.isReadyForPrimaryWork,
                lastTrainedTitle: est.lastWorkoutTitle
            )
        }

        let importedItems: [(Date, WorkoutItem)] = recentWorkouts.map { w in
            let supplement = linked[w.hkUUID.lowercased()]?.first?.1
            return (w.start, WorkoutItem(
                uuid: w.hkUUID,
                source: "healthkit",
                manualSessionID: supplement?.id.uuidString,
                type: w.type,
                dayKey: w.start.physiologicalDayKey().isoString,
                durationMinutes: max(1, Int((w.end.timeIntervalSince(w.start) / 60).rounded())),
                energyKcal: supplement == nil ? Int(w.energy.rounded()) : nil,
                estimatedEnergyKcal: supplement.map { Int($0.estimatedCalories.rounded()) },
                avgHR: w.avgHR,
                effortUser: w.effortUser ?? supplement.map { Double($0.rpe) },
                effortEstimated: w.effortEstimated,
                reviewState: w.reviewState.rawValue,
                annotationText: context.annotationsByWorkoutUUID[w.hkUUID]?.rawText,
                manualVolumeKg: supplement?.totalVolumeKg
            ))
        }
        let manualItems: [(Date, WorkoutItem)] = manual.filter { session in
            !(session.syncedHealthKitUUID.map { importedIDs.contains($0.lowercased()) } ?? false)
        }.map { session in
            (session.startedAt, WorkoutItem(
                uuid: session.id.uuidString, source: "manual", manualSessionID: session.id.uuidString,
                type: session.title, dayKey: session.startedAt.physiologicalDayKey().isoString,
                durationMinutes: session.durationMinutes, energyKcal: nil,
                estimatedEnergyKcal: Int(session.estimatedCalories.rounded()), avgHR: nil,
                effortUser: Double(session.rpe), effortEstimated: nil,
                reviewState: "manual", annotationText: session.notes.isEmpty ? nil : session.notes,
                manualVolumeKg: session.totalVolumeKg
            ))
        }
        let workoutItems = (importedItems + manualItems).sorted { $0.0 > $1.0 }.prefix(8).map(\.1)

        return encodeEnvelope(
            tool: "get_workouts_and_muscles",
            state: workoutItems.isEmpty ? "missing" : "available",
            coverage: nil,
            reason: workoutItems.isEmpty ? "未读取到这段时间的训练，无法判断是否训练" : nil,
            algorithmVersion: AlgorithmVersion.recoveryHeuristicV1.description,
            data: WorkoutsAndMusclesPayload(
                windowDays: clampedDays,
                startDayKey: startDay.isoString,
                endDayKey: endDay.isoString,
                workoutCount: importedItems.count + manualItems.count,
                estimationLabel: "全身及局部肌群恢复百分比均为启发式估计，仅供参考",
                systemicAlpha: (recSnap.systemicFactor.alpha * 100).rounded() / 100,
                systemicSummary: recSnap.systemicFactor.summary,
                workouts: workoutItems,
                muscleEstimates: workoutItems.isEmpty ? [] : filteredMuscles
            )
        )
    }

    private static func sleepDetailJSON(dayString: String?, context: AgentExecutionContext) -> String {
        struct SleepPayload: Encodable {
            let dayKey: String
            let score: Int?
            let scoreState: String
            let asleepMinutes: Int?
            let asleepHours: Double?
            let inBedMinutes: Int?
            let deepMinutes: Int?
            let remMinutes: Int?
            let coreMinutes: Int?
            let awakeMinutes: Int?
            let efficiencyPct: Int?
            let sleepGoalMinutes: Int
        }

        let targetDay: DailyComputedDay
        if let dayString {
            guard let parsed = DayKey(isoString: dayString),
                  let matched = context.snapshot.historyDays.first(where: { $0.dayKey == parsed })
                    ?? (context.snapshot.today.dayKey == parsed ? context.snapshot.today : nil)
            else {
                return encodeEnvelope(tool: "get_sleep_detail", state: "missing", coverage: 0,
                                      reason: "指定日期无睡眠资料：\(dayString)", data: nil as SleepPayload?)
            }
            targetDay = matched
        } else {
            targetDay = context.snapshot.today
        }

        let raw = targetDay.raw
        let eff: Int? = if let asleep = raw.sleepAsleepMinutes, let inBed = raw.sleepInBedMinutes, inBed > 0 {
            Int((Double(asleep) / Double(inBed) * 100.0).rounded())
        } else {
            nil
        }
        let hasSleep = raw.sleepAsleepMinutes != nil
        let stateStr = hasSleep ? "available" : "missing"
        let reasonStr = hasSleep ? nil : (targetDay.sleep.availability.reasonText ?? "无有效睡眠分期数据")

        return encodeEnvelope(
            tool: "get_sleep_detail",
            state: stateStr,
            coverage: hasSleep ? 1.0 : 0.0,
            reason: reasonStr,
            algorithmVersion: AlgorithmVersion.sleepMergeV1.description,
            data: SleepPayload(
                dayKey: targetDay.dayKey.isoString,
                score: targetDay.sleep.value,
                scoreState: stateLabel(for: targetDay.sleep.availability),
                asleepMinutes: raw.sleepAsleepMinutes,
                asleepHours: raw.sleepAsleepMinutes.map { ((Double($0) / 60.0) * 10).rounded() / 10 },
                inBedMinutes: raw.sleepInBedMinutes,
                deepMinutes: raw.deepMinutes,
                remMinutes: raw.remMinutes,
                coreMinutes: raw.coreMinutes,
                awakeMinutes: raw.awakeMinutes,
                efficiencyPct: eff,
                sleepGoalMinutes: context.sleepGoalMinutes
            )
        )
    }

    private static func patternsJSON(topic: String?, context: AgentExecutionContext) -> String {
        struct PatternItem: Encodable {
            let id: String
            let statement: String
            let effect: Double
            let ciLow: Double
            let ciHigh: Double
            let sampleSize: Int
            let method: String
            let status: String
        }
        struct PatternsPayload: Encodable {
            let causalDisclaimer: String
            let findings: [PatternItem]
        }

        let filterClean = topic?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let active = context.patternFindings.filter { finding in
            guard finding.status != .dismissed else { return false }
            if let f = filterClean, !f.isEmpty {
                return finding.statement.lowercased().contains(f) || finding.method.lowercased().contains(f)
            }
            return true
        }

        let stateStr = active.isEmpty ? "missing" : "available"
        let reasonStr = active.isEmpty ? "暂无匹配的个人规律统计发现" : nil
        let items = active.prefix(6).map {
            PatternItem(
                id: $0.id.uuidString,
                statement: $0.statement,
                effect: $0.effect,
                ciLow: $0.ciLow,
                ciHigh: $0.ciHigh,
                sampleSize: $0.sampleSize,
                method: $0.method,
                status: $0.status.rawValue
            )
        }

        return encodeEnvelope(
            tool: "get_patterns",
            state: stateStr,
            coverage: active.isEmpty ? 0.0 : 1.0,
            reason: reasonStr,
            algorithmVersion: "personal-patterns-v1",
            data: PatternsPayload(
                causalDisclaimer: "以下为历史观测序列的相关性发现（滞后分布检验与置信区间），不构成因果推断，可通过 N-of-1 自实验进一步检验。",
                findings: items
            )
        )
    }

    private static func similarDaysJSON(dayString: String?, context: AgentExecutionContext) -> String {
        struct SimilarDayOutcome: Encodable {
            let dayKey: String
            let distance: Double
            let hrvMs: Double?
            let restingHeartRateBpm: Double?
            let sleepMinutes: Int?
            let activeEnergyKcal: Double?
            let nextDayRecoveryScore: Int?
            let nextDayHRVMs: Double?
            let nextDaySleepMinutes: Int?
        }
        struct SimilarDaysPayload: Encodable {
            let targetDayKey: String
            let note: String
            let matches: [SimilarDayOutcome]
        }

        let sortedDays = context.snapshot.historyDays.sorted { $0.dayKey < $1.dayKey }
        let targetKey = dayString ?? context.snapshot.today.dayKey.isoString
        guard let parsedTarget = DayKey(isoString: targetKey),
              let targetDay = sortedDays.first(where: { $0.dayKey == parsedTarget })
        else {
            return encodeEnvelope(
                tool: "find_similar_days", state: "missing", coverage: 0,
                reason: "指定日期无历史生理数据",
                data: SimilarDaysPayload(targetDayKey: targetKey, note: "", matches: [])
            )
        }

        let daysByKey = Dictionary(sortedDays.map { ($0.dayKey, $0) }, uniquingKeysWith: { _, latest in latest })
        let historicalCandidates = sortedDays.compactMap { day -> (day: DailyComputedDay, nextDay: DailyComputedDay)? in
            let nextKey = day.dayKey.addingDays(1)
            guard nextKey < targetDay.dayKey, let nextDay = daysByKey[nextKey] else { return nil }
            return (day, nextDay)
        }
        guard historicalCandidates.count >= 3 else {
            return encodeEnvelope(
                tool: "find_similar_days",
                state: "missing",
                coverage: 0,
                reason: "历史基线天数不足（需至少 3 天历史记录）",
                data: SimilarDaysPayload(targetDayKey: targetDay.dayKey.isoString, note: "", matches: [])
            )
        }

        func stats(_ values: [Double]) -> (mean: Double, sd: Double)? {
            guard values.count >= 3 else { return nil }
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
            return (mean, max(1e-3, sqrt(variance)))
        }

        let priorDays = historicalCandidates.map(\.day)
        let hrvStat = stats(priorDays.compactMap(\.raw.hrvMs))
        let rhrStat = stats(priorDays.compactMap(\.raw.restingHeartRateBpm))
        let sleepStat = stats(priorDays.compactMap { $0.raw.sleepAsleepMinutes.map(Double.init) })
        let strainStat = stats(priorDays.compactMap(\.raw.activeEnergyKcal))

        var scoredMatches: [SimilarDayOutcome] = []
        for (day, nextDay) in historicalCandidates {
            var sqSum = 0.0
            var dimCount = 0

            if let s = hrvStat, let t = targetDay.raw.hrvMs, let h = day.raw.hrvMs {
                let d = (t - h) / s.sd
                sqSum += d * d
                dimCount += 1
            }
            if let s = rhrStat, let t = targetDay.raw.restingHeartRateBpm, let h = day.raw.restingHeartRateBpm {
                let d = (t - h) / s.sd
                sqSum += d * d
                dimCount += 1
            }
            if let s = sleepStat, let t = targetDay.raw.sleepAsleepMinutes, let h = day.raw.sleepAsleepMinutes {
                let d = (Double(t) - Double(h)) / s.sd
                sqSum += d * d
                dimCount += 1
            }
            if let s = strainStat, let t = targetDay.raw.activeEnergyKcal, let h = day.raw.activeEnergyKcal {
                let d = (t - h) / s.sd
                sqSum += d * d
                dimCount += 1
            }

            guard dimCount >= 2 else { continue }
            let rmsDistance = (sqrt(sqSum / Double(dimCount)) * 100).rounded() / 100
            scoredMatches.append(
                SimilarDayOutcome(
                    dayKey: day.dayKey.isoString,
                    distance: rmsDistance,
                    hrvMs: day.raw.hrvMs,
                    restingHeartRateBpm: day.raw.restingHeartRateBpm,
                    sleepMinutes: day.raw.sleepAsleepMinutes,
                    activeEnergyKcal: day.raw.activeEnergyKcal,
                    nextDayRecoveryScore: nextDay.recovery.value,
                    nextDayHRVMs: nextDay.raw.hrvMs,
                    nextDaySleepMinutes: nextDay.raw.sleepAsleepMinutes
                )
            )
        }

        let top3 = Array(scoredMatches.sorted { $0.distance < $1.distance }.prefix(3))
        guard !top3.isEmpty else {
            return encodeEnvelope(
                tool: "find_similar_days",
                state: "missing",
                coverage: 0,
                reason: "目标日或历史日中可比特征不足两项，无法计算相似日",
                data: SimilarDaysPayload(targetDayKey: targetDay.dayKey.isoString, note: "", matches: [])
            )
        }

        return encodeEnvelope(
            tool: "find_similar_days",
            state: "available",
            coverage: Double(top3.count) / 3.0,
            reason: nil,
            algorithmVersion: "similar-days-v1",
            data: SimilarDaysPayload(
                targetDayKey: targetDay.dayKey.isoString,
                note: "仅检索目标日之前历史相似状态及其实际次日变化，属于类比参考而非因果反事实。",
                matches: top3
            )
        )
    }

    private static func eatingContextJSON(days: Int, compact: Bool = false, context: AgentExecutionContext) -> String {
        struct NutrientAdequacy: Encodable {
            let metricID: String
            let name: String
            let unit: String
            let value: Double?
            let status: String
            let targetSummary: String
            let isEstimated: Bool
        }
        struct RecentNutrientAdequacy: Encodable {
            let metricID: String
            let name: String
            let unit: String
            let metDays: Int
            let lowDays: Int
            let overDays: Int
            let unknownDays: Int
            let estimatedDays: Int
            let averageValue: Double?
        }
        struct DayNutritionSummary: Encodable {
            let energy: MealEnergySummary
            let dayKey: String
            let mealCount: Int
            let estimatedEntryCount: Int
            let partialFields: [String]
            let evidenceKey: String
            let kcal: Double?
            let proteinG: Double?
            let carbsG: Double?
            let fatG: Double?
            let fiberG: Double?
            let waterMl: Double?
            let complete: Bool
            let calorieSurplusKcal: Double?
            let adequacy: [NutrientAdequacy]
        }
        struct EatingPayload: Encodable {
            let targetPlanVersion: String?
            let targetEffectiveFrom: String?
            let targets: [NutritionTargetItem]
            let recentAdequacy: [RecentNutrientAdequacy]
            let trackedDays: Int
            let completedDays: Int
            let startDayKey: String
            let endDayKey: String
            let logs: [DayNutritionSummary]
        }

        let clampedDays = min(30, max(1, days))
        let end = context.snapshot.referenceDate.physiologicalDayKey()
        let start = end.addingDays(1 - clampedDays)
        let recent = context.nutritionLogs
            .filter { $0.dayKey >= start && $0.dayKey <= end }
            .filter { !$0.entries.isEmpty || $0.dietKcal != nil || $0.dietWaterMl != nil }
            .sorted { $0.dayKey > $1.dayKey }
        let targetPlan = context.nutritionTargetPlan
        let validated = NutritionTargetEvaluator.validate(plan: targetPlan, on: end)
        let adoptedIDs = validated.validAdoptedItems.keys.sorted()
        let targets = validated.isActive ? adoptedIDs.compactMap { validated.validAdoptedItems[$0] } : []
        let recentAdequacy: [RecentNutrientAdequacy] = adoptedIDs.compactMap { metricID in
            let descriptor = NutritionCatalog.descriptor(forID: metricID)
            var met = 0
            var low = 0
            var over = 0
            var unknown = 0
            var estimated = 0
            var sum = 0.0
            var count = 0
            for log in recent {
                let eval = NutritionTargetEvaluator.evaluate(
                    metricID: metricID,
                    log: log,
                    validatedPlan: validated,
                    allowEstimates: true
                )
                switch eval.status {
                case .met: met += 1
                case .low: low += 1
                case .over: over += 1
                case .unknown: unknown += 1
                }
                if eval.status != .unknown, let value = eval.value {
                    sum += value
                    count += 1
                    if eval.isEstimated { estimated += 1 }
                }
            }
            guard met + low + over + unknown > 0 else { return nil }
            return RecentNutrientAdequacy(
                metricID: metricID,
                name: descriptor?.name ?? metricID,
                unit: validated.validAdoptedItems[metricID]?.unit ?? descriptor?.unit ?? "",
                metDays: met,
                lowDays: low,
                overDays: over,
                unknownDays: unknown,
                estimatedDays: estimated,
                averageValue: count > 0 ? sum / Double(count) : nil
            )
        }

        guard !recent.isEmpty else {
            return encodeEnvelope(
                tool: "get_eating_context",
                state: "missing",
                coverage: 0.0,
                reason: "近 \(clampedDays) 天尚未记录饮食或饮水数据",
                data: EatingPayload(
                    targetPlanVersion: validated.isActive ? targetPlan?.targetVersion : nil,
                    targetEffectiveFrom: validated.isActive ? targetPlan?.effectiveFrom?.isoString : nil,
                    targets: targets,
                    recentAdequacy: recentAdequacy,
                    trackedDays: 0, completedDays: 0, startDayKey: start.isoString, endDayKey: end.isoString,
                    logs: []
                )
            )
        }

        let items = recent.map { log in
            let dayAdequacy: [NutrientAdequacy]
            if compact {
                // On-device Foundation Models (~4K context): omit verbose 24-item per-day adequacy breakdown.
                dayAdequacy = []
            } else {
                dayAdequacy = adoptedIDs.compactMap { metricID in
                    let eval = NutritionTargetEvaluator.evaluate(
                        metricID: metricID,
                        log: log,
                        validatedPlan: validated,
                        allowEstimates: true
                    )
                    guard eval.status != .unknown || eval.value != nil else { return nil }
                    let descriptor = NutritionCatalog.descriptor(forID: metricID)
                    return NutrientAdequacy(
                        metricID: metricID,
                        name: descriptor?.name ?? metricID,
                        unit: eval.displayUnit,
                        value: eval.value,
                        status: eval.status.rawValue,
                        targetSummary: eval.targetSummary,
                        isEstimated: eval.isEstimated
                    )
                }
            }
            return DayNutritionSummary(
                energy: MealEnergySummary(entries: log.entries),
                dayKey: log.dayKey.isoString,
                mealCount: log.entries.count,
                estimatedEntryCount: log.entries.filter(\.isEstimated).count,
                partialFields: log.dietPartialFields,
                evidenceKey: "nutrition_day:\(log.dayKey.isoString)",
                kcal: log.dietKcal,
                proteinG: log.dietProteinG,
                carbsG: log.dietCarbsG,
                fatG: log.dietFatG,
                fiberG: log.dietFiberG,
                waterMl: log.dietWaterMl,
                complete: log.dietDayComplete ?? false,
                calorieSurplusKcal: log.dietDayComplete == true && log.dietPartialFields.isEmpty
                    ? log.calorieSurplusKcal : nil,
                adequacy: dayAdequacy
            )
        }
        let payloadAdequacy: [RecentNutrientAdequacy]
        if compact {
            // Keep highlights (macros + any non-met / notable nutrients) within compact context budget.
            let prioritized = recentAdequacy.filter {
                ["diet_kcal", "diet_protein_g", "diet_carbs_g", "diet_fat_g", "diet_fiber_g", "diet_water_ml"].contains($0.metricID)
                    || $0.lowDays > 0 || $0.overDays > 0
            }
            payloadAdequacy = Array(prioritized.prefix(12))
        } else {
            payloadAdequacy = recentAdequacy
        }
        return encodeEnvelope(
            tool: "get_eating_context",
            state: "available",
            coverage: Double(items.count) / Double(clampedDays),
            reason: nil,
            algorithmVersion: "nutrition-v1",
            data: EatingPayload(
                targetPlanVersion: validated.isActive ? targetPlan?.targetVersion : nil,
                targetEffectiveFrom: validated.isActive ? targetPlan?.effectiveFrom?.isoString : nil,
                targets: compact ? Array(targets.prefix(8)) : targets,
                recentAdequacy: payloadAdequacy,
                trackedDays: items.count,
                completedDays: items.filter { $0.complete && $0.partialFields.isEmpty }.count,
                startDayKey: start.isoString, endDayKey: end.isoString,
                logs: items
            )
        )
    }

    private static func personalForecastJSON(context: AgentExecutionContext) -> String {
        struct ForecastTargetDTO: Encodable {
            let name: String
            let title: String
            let unit: String
            let point: Double
            let interval80Low: Double
            let interval80High: Double
            let interval90Low: Double
            let interval90High: Double
            let walkForwardMAE: Double
            let walkForwardCov80: Double
        }
        struct PersonalForecastPayload: Encodable {
            let disclaimer: String
            let referenceDayKey: String
            let targetDayKey: String
            let modelVersion: String
            let runtimeBackend: String
            let observedDays: Int
            let targets: [ForecastTargetDTO]
        }

        let eatingDays = Set(
            context.nutritionLogs
                .filter { $0.dietDayComplete == true || !$0.entries.isEmpty }
                .map(\.dayKey)
        )
        let state = PersonalForecasterEngine.forecast(
            historyDays: context.snapshot.historyDays,
            referenceDate: context.snapshot.referenceDate,
            eatingAvailableDayKeys: eatingDays
        )

        switch state {
        case let .insufficientData(observedDays, minimumRequired, reason):
            let cov = min(1.0, max(0.0, Double(observedDays) / Double(max(1, minimumRequired))))
            return encodeEnvelope(
                tool: "get_personal_forecast",
                state: "missing",
                coverage: cov,
                reason: reason,
                algorithmVersion: "personal-forecaster-v1@1.0.0",
                data: PersonalForecastPayload(
                    disclaimer: "个人统计预测，非医学诊断",
                    referenceDayKey: context.snapshot.referenceDate.physiologicalDayKey().isoString,
                    targetDayKey: context.snapshot.referenceDate.physiologicalDayKey().addingDays(1).isoString,
                    modelVersion: "personal-forecaster-v1@1.0.0",
                    runtimeBackend: "CoreML",
                    observedDays: observedDays,
                    targets: []
                )
            )
        case let .available(summary):
            let dtos = summary.targets.map { t in
                let scale = t.name == "sleep_efficiency" ? 1000.0 : 10.0
                return ForecastTargetDTO(
                    name: t.name,
                    title: t.title,
                    unit: t.unit,
                    point: (t.point * scale).rounded() / scale,
                    interval80Low: (t.interval80Low * scale).rounded() / scale,
                    interval80High: (t.interval80High * scale).rounded() / scale,
                    interval90Low: (t.interval90Low * scale).rounded() / scale,
                    interval90High: (t.interval90High * scale).rounded() / scale,
                    walkForwardMAE: (t.walkForwardMAE * scale).rounded() / scale,
                    walkForwardCov80: (t.walkForwardCov80 * 1000.0).rounded() / 1000.0
                )
            }
            return encodeEnvelope(
                tool: "get_personal_forecast",
                state: "available",
                coverage: 1.0,
                reason: nil,
                algorithmVersion: summary.modelVersion,
                data: PersonalForecastPayload(
                    disclaimer: "个人统计预测，非医学诊断",
                    referenceDayKey: summary.referenceDayKey.isoString,
                    targetDayKey: summary.targetDayKey.isoString,
                    modelVersion: summary.modelVersion,
                    runtimeBackend: summary.runtimeBackend,
                    observedDays: summary.observedDays,
                    targets: dtos
                )
            )
        }
    }

    private static func searchExercisesJSON(query: String) -> String {
        struct ExerciseMatch: Encodable {
            let id: String
            let name: String
            let equipment: String
            let primaryMuscles: [String]
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = ExerciseCatalog.all.filter { def in
            guard !trimmed.isEmpty else { return true }
            return def.id.contains(trimmed)
                || def.name.lowercased().contains(trimmed)
                || def.englishName.lowercased().contains(trimmed)
                || def.primaryMuscles.contains(where: { $0.rawValue.contains(trimmed) || $0.title.contains(trimmed) })
        }
        let items = matches.prefix(8).map {
            ExerciseMatch(
                id: $0.id,
                name: $0.name,
                equipment: $0.equipment,
                primaryMuscles: $0.primaryMuscles.map(\.rawValue)
            )
        }
        return encodeEnvelope(
            tool: "search_exercise_catalog",
            state: items.isEmpty ? "missing" : "available",
            coverage: items.isEmpty ? 0.0 : 1.0,
            reason: items.isEmpty ? "未找到匹配动作" : nil,
            data: items
        )
    }

    private static func proposePlanChangeJSON(
        title: String,
        focusTag: String,
        exerciseIDsCSV: String,
        intensityMultiplier: Double,
        restSeconds: Int,
        rationale: String,
        context: AgentExecutionContext
    ) async -> String {
        let requestedIDs = exerciseIDsCSV
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { ExerciseCatalog.find(id: $0) != nil }

        let finalIDs = requestedIDs.isEmpty
            ? ["barbell-bench-press", "lat-pulldown", "face-pull"]
            : requestedIDs

        let safeScale = min(1.25, max(0.5, intensityMultiplier))
        let items = finalIDs.map { exID in
            let def = ExerciseCatalog.find(id: exID)
            let baseSets = def?.category == .cardio ? 1 : max(2, Int((3.0 * safeScale).rounded()))
            let baseReps = def?.category == .cardio ? 25 : 10
            let baseWeight: Double = def?.equipment == "自重" || def?.equipment == "有氧" ? 0 : (40.0 * safeScale).rounded()
            return PlannedExerciseItem(
                exerciseID: exID,
                targetSets: baseSets,
                targetReps: baseReps,
                targetWeightKg: baseWeight,
                restSeconds: max(30, min(180, restSeconds))
            )
        }

        let template = WorkoutTemplate(
            title: title,
            subtitle: rationale,
            focusTag: focusTag,
            estimatedMinutes: items.count * 8 + 10,
            exercises: items,
            isAIGenerated: true
        )
        let proposal = WorkoutProposal(template: template, rationale: rationale)
        await context.effects.recordProposal(proposal)

        struct ProposedPlanAck: Encodable {
            let status: String
            let proposalID: String
            let title: String
            let exerciseCount: Int
            /// 训练计划修改在动作目录里按 C 级处理：必须用户确认后才会写入。
            let authorization: String
        }
        return encodeEnvelope(
            tool: "propose_plan_change",
            state: "available",
            coverage: 1.0,
            reason: nil,
            data: ProposedPlanAck(
                status: "pending_user_confirmation",
                proposalID: proposal.id.uuidString,
                title: title,
                exerciseCount: items.count,
                authorization: "C"
            )
        )
    }

    private static func proposeMemoryJSON(
        tierRaw: String,
        content: String,
        categoryRaw: String,
        expiresDays: Int,
        patternIDString: String?,
        context: AgentExecutionContext
    ) async -> String {
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return encodeEnvelope(tool: "propose_memory", state: "missing", coverage: 0, reason: "记忆内容为空，未生成提案", data: ["status": "rejected"])
        }

        let tier: MemoryTier
        switch tierRaw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case MemoryTier.profile.rawValue:
            tier = .profile
        case MemoryTier.verifiedPattern.rawValue:
            tier = .verifiedPattern
        default:
            tier = .activeConstraint
        }

        let patternUUID = patternIDString.flatMap(UUID.init(uuidString:))
        let gate = MemoryContextSelector.validateCandidateMemory(
            tier: tier,
            linkedPatternID: patternUUID,
            confirmedFindings: context.patternFindings
        )
        guard gate.allowed else {
            return encodeEnvelope(tool: "propose_memory", state: "excluded", coverage: 0, reason: gate.reason, data: ["status": "rejected"])
        }

        let now = context.snapshot.referenceDate
        let expiresAt: Date? = (tier == .activeConstraint)
            ? now.addingTimeInterval(Double(max(1, min(90, expiresDays))) * 86_400)
            : nil
        let safeCategory = AthleteMemoryCategory(rawValue: categoryRaw)?.rawValue
            ?? (tier == .activeConstraint ? AthleteMemoryCategory.injury.rawValue : AthleteMemoryCategory.preference.rawValue)
        let scopeJSON = patternUUID.map { "{\"category\":\"\(safeCategory)\",\"pattern_id\":\"\($0.uuidString)\"}" }
            ?? "{\"category\":\"\(safeCategory)\"}"

        let record = TieredMemoryRecord(
            tier: tier,
            content: cleaned,
            scopeJSON: scopeJSON,
            confidence: 0.9,
            expiresAt: expiresAt,
            confirmedAt: now,
            retiredAt: nil
        )
        // A 级：有动作层时直接保存并返回回执；失败或需要确认时退回确认卡片。
        if let proposal = makeProposal(
            kind: .commitMemory,
            payload: CommitMemoryPayload(memory: record),
            rationale: "Coach 根据对话保存[\(tier.titleLabel)]记忆",
            context: context
        ), case let .applied(receipt)? = await runThroughGateway(proposal, context: context) {
            return appliedEnvelope(tool: "propose_memory", receipt: receipt)
        }
        await context.effects.recordMemoryProposal(record)

        struct ProposedMemAck: Encodable {
            let status: String
            let memoryID: String
            let tier: String
            let content: String
            let expiresInDays: Int?
        }
        return encodeEnvelope(
            tool: "propose_memory",
            state: "available",
            coverage: 1.0,
            reason: nil,
            data: ProposedMemAck(
                status: "pending_user_confirmation",
                memoryID: record.id.uuidString,
                tier: tier.rawValue,
                content: cleaned,
                expiresInDays: (tier == .activeConstraint) ? max(1, min(90, expiresDays)) : nil
            )
        )
    }

    private static func proposeWorkoutAnnotationJSON(
        rawText: String,
        workoutUUID: String?,
        context: AgentExecutionContext
    ) async -> String {
        let resolution = WorkoutAnnotationResolver.resolve(
            rawText: rawText,
            workoutUUID: workoutUUID,
            asOf: context.asOf,
            workouts: context.storedWorkouts,
            deletedWorkoutUUIDs: context.deletedWorkoutUUIDs,
            annotationsByWorkoutUUID: context.annotationsByWorkoutUUID
        )

        struct AnnotationAck: Encodable {
            let status: String
            let workoutUUID: String?
            let workoutTitle: String?
            let dayKey: String?
            let primaryMuscles: [String]
            let rpe: Int?
            let candidates: [AnnotationCandidateSummary]
            let windowDescription: String?
        }

        switch resolution {
        case let .unique(candidate):
            if let applied = await applyAnnotationDirectly(candidate, context: context) {
                return applied
            }
            await context.effects.recordWorkoutAnnotationProposal(candidate.proposal)
            await context.effects.recordWorkoutAnnotationCandidates([candidate])
            return encodeEnvelope(
                tool: "propose_workout_annotation",
                state: "available",
                coverage: 1.0,
                reason: nil,
                data: AnnotationAck(
                    status: "pending_user_confirmation",
                    workoutUUID: candidate.proposal.workoutUUID,
                    workoutTitle: candidate.proposal.workoutTitle,
                    dayKey: candidate.dayKey,
                    primaryMuscles: candidate.proposal.proposal.primaryMuscles.map(\.title),
                    rpe: candidate.proposal.proposal.rpe,
                    candidates: [AnnotationCandidateSummary(candidate)],
                    windowDescription: nil
                )
            )
        case let .multiple(candidates, windowDescription):
            await context.effects.recordWorkoutAnnotationCandidates(candidates)
            return encodeEnvelope(
                tool: "propose_workout_annotation",
                state: "needs_selection",
                coverage: 0,
                reason: "\(windowDescription) 有多条训练，请让用户按开始时间和训练类型选择",
                data: AnnotationAck(
                    status: "needs_selection",
                    workoutUUID: nil,
                    workoutTitle: nil,
                    dayKey: nil,
                    primaryMuscles: [],
                    rpe: nil,
                    candidates: candidates.map(AnnotationCandidateSummary.init),
                    windowDescription: windowDescription
                )
            )
        case let .none(reason):
            return encodeEnvelope(
                tool: "propose_workout_annotation",
                state: "missing",
                coverage: 0,
                reason: reason,
                data: AnnotationAck(
                    status: "missing",
                    workoutUUID: nil,
                    workoutTitle: nil,
                    dayKey: nil,
                    primaryMuscles: [],
                    rpe: nil,
                    candidates: [],
                    windowDescription: nil
                )
            )
        case let .conflict(reason):
            return encodeEnvelope(
                tool: "propose_workout_annotation",
                state: "excluded",
                coverage: 0,
                reason: reason,
                data: AnnotationAck(
                    status: "needs_clarification",
                    workoutUUID: nil,
                    workoutTitle: nil,
                    dayKey: nil,
                    primaryMuscles: [],
                    rpe: nil,
                    candidates: [],
                    windowDescription: nil
                )
            )
        }
    }

    // MARK: - Action Layer (A / B / C)

    private enum GatewayResult {
        case applied(AppActionReceipt)
        case needsConfirmation(String)
        case failed(String)
    }

    private struct AppliedActionAck: Encodable {
        let status: String
        let receiptID: String
        let kind: String
        let authorization: String
        let title: String
        let detail: String
        let undoable: Bool
        let undoWindowHours: Int?
    }

    private static func makeProposal<P: Encodable>(
        kind: ActionProposal.Kind,
        payload: P,
        rationale: String,
        context: AgentExecutionContext
    ) -> ActionProposal? {
        guard context.actionGateway != nil else { return nil }
        do {
            return try ActionProposal(
                kind: kind,
                origin: .agent,
                encodablePayload: payload,
                rationale: rationale,
                createdAt: context.asOf
            )
        } catch {
            logger.error("Failed building action proposal \(kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func runThroughGateway(_ proposal: ActionProposal, context: AgentExecutionContext) async -> GatewayResult? {
        guard let gateway = context.actionGateway else { return nil }
        do {
            switch try await gateway.execute(proposal) {
            case let .executed(receipt):
                await context.effects.recordAppliedAction(receipt)
                return .applied(receipt)
            case let .needsConfirmation(_, title):
                return .needsConfirmation(title)
            }
        } catch {
            logger.error("Action layer failed \(proposal.kind.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    private static func appliedEnvelope(tool: String, receipt: AppActionReceipt) -> String {
        encodeEnvelope(
            tool: tool,
            state: "available",
            coverage: 1.0,
            reason: nil,
            data: AppliedActionAck(
                status: "applied",
                receiptID: receipt.id.uuidString,
                kind: receipt.kind.rawValue,
                authorization: receipt.risk.rawValue.uppercased(),
                title: receipt.title,
                detail: receipt.detail,
                undoable: receipt.isUndoable,
                undoWindowHours: receipt.undoDeadline == nil ? nil : 24
            )
        )
    }

    private static func applyAnnotationDirectly(
        _ candidate: CoachWorkoutAnnotationCandidate,
        context: AgentExecutionContext
    ) async -> String? {
        let annotation = candidate.proposal
        guard let proposal = makeProposal(
            kind: .annotateWorkout,
            payload: AnnotateWorkoutPayload(
                workoutUUID: annotation.workoutUUID,
                rawText: annotation.rawText,
                parserVersion: annotation.proposal.parserVersion,
                muscleLoads: annotation.muscleLoads,
                expectedRecordState: annotation.recordState
            ),
            rationale: "Coach 根据用户描述给训练补标注",
            context: context
        ) else { return nil }
        guard case let .applied(receipt)? = await runThroughGateway(proposal, context: context) else { return nil }
        return appliedEnvelope(tool: "propose_workout_annotation", receipt: receipt)
    }

    private static func executeActionJSON(argumentsJSON: String, context: AgentExecutionContext) async -> String {
        guard context.actionGateway != nil else {
            return encodeEnvelope(
                tool: "execute_action",
                state: "missing",
                coverage: 0,
                reason: "动作层未接入，不能直接执行；请改用提案工具生成确认卡片",
                data: ["status": "unavailable"]
            )
        }
        switch ExecuteActionRequest.parse(argumentsJSON: argumentsJSON) {
        case let .failure(error):
            return encodeEnvelope(
                tool: "execute_action",
                state: "missing",
                coverage: 0,
                reason: error.message,
                data: ["status": "invalid_arguments"]
            )
        case let .success(request):
            switch request {
            case let .saveMemory(tier, content, category, expiresDays, patternID):
                return await proposeMemoryJSON(
                    tierRaw: tier,
                    content: content,
                    categoryRaw: category,
                    expiresDays: expiresDays,
                    patternIDString: patternID,
                    context: context
                )
            case let .annotateWorkout(rawText, workoutUUID):
                return await proposeWorkoutAnnotationJSON(rawText: rawText, workoutUUID: workoutUUID, context: context)
            case let .retireMemory(memoryID):
                return await retireMemoryJSON(memoryID: memoryID, context: context)
            case let .deleteMeal(dayKey, entryID):
                return await deleteMealJSON(dayKey: dayKey, entryID: entryID, context: context)
            }
        }
    }

    private static func retireMemoryJSON(memoryID: UUID, context: AgentExecutionContext) async -> String {
        guard let memory = context.tieredMemories.first(where: { $0.id == memoryID && $0.retiredAt == nil }) else {
            return encodeEnvelope(
                tool: "execute_action",
                state: "missing",
                coverage: 0,
                reason: "没有找到生效中的这条记忆",
                data: ["status": "not_found"]
            )
        }
        guard let proposal = makeProposal(
            kind: .retireMemory,
            payload: RetireMemoryPayload(memoryID: memoryID, retiredAt: context.asOf),
            rationale: "Coach 停用记忆：\(String(memory.content.prefix(30)))",
            context: context
        ) else {
            return encodeEnvelope(tool: "execute_action", state: "missing", coverage: 0, reason: "动作提案生成失败", data: ["status": "failed"])
        }
        switch await runThroughGateway(proposal, context: context) {
        case let .applied(receipt)?:
            return appliedEnvelope(tool: "execute_action", receipt: receipt)
        case let .needsConfirmation(title)?:
            return encodeEnvelope(
                tool: "execute_action",
                state: "available",
                coverage: 1.0,
                reason: "\(title)需要用户先确认",
                data: ["status": "needs_confirmation"]
            )
        case let .failed(message)?:
            return encodeEnvelope(tool: "execute_action", state: "missing", coverage: 0, reason: message, data: ["status": "failed"])
        case nil:
            return encodeEnvelope(tool: "execute_action", state: "missing", coverage: 0, reason: "动作层未接入", data: ["status": "unavailable"])
        }
    }

    private static func deleteMealJSON(dayKey: DayKey, entryID: UUID, context: AgentExecutionContext) async -> String {
        guard let proposal = makeProposal(
            kind: .deleteNutritionMeal,
            payload: DeleteNutritionMealPayload(dayKey: dayKey, entryID: entryID),
            rationale: "Coach 建议删除一条餐食记录",
            context: context
        ) else {
            return encodeEnvelope(tool: "execute_action", state: "missing", coverage: 0, reason: "动作提案生成失败", data: ["status": "failed"])
        }
        // C 级：网关只会返回"需要确认"，不会写入；删除要由用户在饮食页确认。
        switch await runThroughGateway(proposal, context: context) {
        case let .needsConfirmation(title)?:
            return encodeEnvelope(
                tool: "execute_action",
                state: "available",
                coverage: 1.0,
                reason: "\(title)需要用户先确认，请让用户在饮食页自己删除",
                data: ["status": "needs_confirmation"]
            )
        case let .applied(receipt)?:
            return appliedEnvelope(tool: "execute_action", receipt: receipt)
        case let .failed(message)?:
            return encodeEnvelope(tool: "execute_action", state: "missing", coverage: 0, reason: message, data: ["status": "failed"])
        case nil:
            return encodeEnvelope(tool: "execute_action", state: "missing", coverage: 0, reason: "动作层未接入", data: ["status": "unavailable"])
        }
    }

    // MARK: - Decoding & Encoding Helpers

    private static func stateLabel(for availability: MetricAvailability) -> String {
        switch availability {
        case .available: "available"
        case .knownZero: "knownZero"
        case .missing: "missing"
        case .excluded: "excluded"
        }
    }

    private static func decodeArgs(_ json: String, toolName: String) -> [String: JSONValue] {
        guard let data = json.data(using: .utf8), !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return [:]
        }
        do {
            let val = try JSONValue.parseData(data)
            if case let .object(dict) = val {
                return dict
            }
            return [:]
        } catch {
            logger.error("Failed decoding arguments for \(toolName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    private static func stringArg(_ args: [String: JSONValue], _ key: String) -> String? {
        guard let val = args[key] else { return nil }
        switch val {
        case let .string(s): return s
        case let .integer(i): return String(i)
        case let .number(d): return String(d)
        default: return nil
        }
    }

    private static func intArg(_ args: [String: JSONValue], _ key: String) -> Int? {
        guard let val = args[key] else { return nil }
        switch val {
        case let .integer(i): return i
        case let .number(d): return Int(d.rounded())
        case let .string(s): return Int(s)
        default: return nil
        }
    }

    private static func doubleArg(_ args: [String: JSONValue], _ key: String) -> Double? {
        guard let val = args[key] else { return nil }
        switch val {
        case let .number(d): return d
        case let .integer(i): return Double(i)
        case let .string(s): return Double(s)
        default: return nil
        }
    }

    private static func encodeEnvelope<Payload: Encodable>(
        tool: String,
        state: String,
        coverage: Double?,
        reason: String?,
        algorithmVersion: String = "v1",
        data: Payload,
        evidence: [EvidenceFact]? = nil,
        truncated: Bool? = nil
    ) -> String {
        let envelope = ToolEnvelope(
            tool: tool,
            state: state,
            coverage: coverage,
            reason: reason,
            algorithmVersion: algorithmVersion,
            data: data,
            evidence: evidence,
            truncated: truncated
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let jsonData = try encoder.encode(envelope)
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            logger.error("Failed encoding ToolEnvelope for \(tool, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return "{}"
        }
    }
}

/// `get_today_context` 里预先算好的派生值（UI v4 §6.1）：窗口均值、差值、睡眠时长两种写法。
struct TodayDerivedValues: Encodable {
    let sleepAsleepHours: Double?
    let sleepAsleepHourPart: Int?
    let sleepAsleepMinutePart: Int?
    let sleepAsleepText: String?
    let hrv14dMeanMs: Double?
    let hrvVs14dMeanMs: Double?
    let restingHeartRate14dMeanBpm: Double?
    let restingHeartRateVs14dMeanBpm: Double?
    let recovery7dMean: Double?
    let recoveryVs7dMean: Double?
    let recordedDays14d: Int
}
