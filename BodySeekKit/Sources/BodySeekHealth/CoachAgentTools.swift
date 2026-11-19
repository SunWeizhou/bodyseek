import BodySeekCore
import Foundation
import SpeziLLMOpenAI

#if canImport(FoundationModels)
import FoundationModels
#endif

public actor AgentCapturedSideEffects: Sendable {
    public private(set) var workoutProposal: WorkoutProposal?
    public private(set) var savedMemories: [AthleteMemoryItem] = []

    public init() {}

    public func recordProposal(_ proposal: WorkoutProposal) {
        workoutProposal = proposal
    }

    public func recordMemory(_ memory: AthleteMemoryItem) {
        savedMemories.append(memory)
    }
}

public struct AgentExecutionContext: Sendable {
    public let snapshot: BodySeekDashboardSnapshot
    public let sessions: [LoggedWorkoutSession]
    public let templates: [WorkoutTemplate]
    public let memories: [AthleteMemoryItem]
    public let effects: AgentCapturedSideEffects

    public init(
        snapshot: BodySeekDashboardSnapshot,
        sessions: [LoggedWorkoutSession],
        templates: [WorkoutTemplate],
        memories: [AthleteMemoryItem],
        effects: AgentCapturedSideEffects = AgentCapturedSideEffects()
    ) {
        self.snapshot = snapshot
        self.sessions = sessions
        self.templates = templates
        self.memories = memories
        self.effects = effects
    }
}

public enum AgentToolLogic {
    public static func physiologyAndTrainingReport(context: AgentExecutionContext) -> String {
        let day = context.snapshot.today
        let load = context.snapshot.trainingLoad
        let ratioText = load.acwrRatio.map { String(format: "%.2f", $0) } ?? "--"
        let recentWorkouts = context.snapshot.historyDays.suffix(7).flatMap(\.raw.workouts)
        let workoutSummary = recentWorkouts.prefix(5).map { w in
            let zoneSummary = w.heartRateZones.map { "Z2:\($0.zone2Minutes)m Z3:\($0.zone3Minutes)m Z4:\($0.zone4Minutes)m" } ?? "无心率分区"
            return "- \(w.activityName) (\(w.durationMinutes)分, \(Int(w.activeEnergyKcal)) kcal, 努力度 \(w.effortScore.map { String(format: "%.1f", $0) } ?? "--"), \(zoneSummary))"
        }.joined(separator: "\n")

        let strengthSummary = context.sessions.prefix(4).map { s in
            "- \(s.title): \(s.durationMinutes)分, 总容量 \(Int(s.totalVolumeKg))kg, RPE \(s.rpe)"
        }.joined(separator: "\n")

        let memoryText = context.memories.isEmpty
            ? "暂无长期记忆"
            : context.memories.map { "- [\($0.category.title)] \($0.content)" }.joined(separator: "\n")

        return """
        今日生理分: 恢复 \(day.recovery.formattedScore)(\(day.recovery.subtitle)), 睡眠 \(day.sleep.formattedScore)(\(day.sleep.subtitle)), 负荷 \(day.strain.formattedScore), 压力 \(day.stress.formattedScore), 能量 \(day.energy.formattedScore)
        ACWR 训练负荷比: \(ratioText) (\(load.zone.title), 近7天 \(Int(load.acute7dLoad)))
        近7天手表体能训练:
        \(workoutSummary.isEmpty ? "- 暂无" : workoutSummary)
        近期力量记录:
        \(strengthSummary.isEmpty ? "- 暂无" : strengthSummary)
        运动员长期记忆:
        \(memoryText)
        """
    }

    public static func saveMemory(
        categoryRaw: String,
        content: String,
        context: AgentExecutionContext
    ) async -> String {
        let category = AthleteMemoryCategory(rawValue: categoryRaw) ?? .preference
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "记忆内容为空，未保存。" }
        let item = AthleteMemoryItem(category: category, content: cleaned)
        await context.effects.recordMemory(item)
        return "已记住[\(category.title)]：\(cleaned)"
    }

    public static func searchExercises(muscleFilter: String?) -> String {
        let trimmed = (muscleFilter ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = ExerciseCatalog.all.filter { def in
            guard !trimmed.isEmpty else { return true }
            return def.id.contains(trimmed)
                || def.name.lowercased().contains(trimmed)
                || def.primaryMuscles.contains(where: { $0.rawValue.contains(trimmed) || $0.title.contains(trimmed) })
        }
        return matches.prefix(8).map {
            "\($0.id): \($0.name) (\($0.equipment), 主肌群: \($0.primaryMuscles.map(\.title).joined(separator: "/")))"
        }.joined(separator: "\n")
    }

    public static func proposeWorkout(
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
            ? ["barbell-bench-press", "lat-pulldown", "romanian-deadlift"]
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
        return "已生成今日健身处方建议「\(title)」，包含 \(items.count) 个动作，等待用户在界面确认后加入健身页。"
    }
}

// MARK: - SpeziLLMOpenAI Function Calling DSL Tools

public struct SpeziPhysiologyTool: LLMFunction {
    public static let name = "query_physiology_and_training"
    public static let description = "读取用户今日五项恢复/睡眠/负荷/压力/能量分、ACWR、近期手表体能训练和长期记忆。"

    private let context: AgentExecutionContext

    public init(context: AgentExecutionContext) {
        self.context = context
    }

    public func execute() async throws -> String? {
        AgentToolLogic.physiologyAndTrainingReport(context: context)
    }
}

public struct SpeziSaveMemoryTool: LLMFunction {
    public static let name = "save_athlete_memory"
    public static let description = "将用户的伤病限制、长期训练目标或训练时间偏好持久化记住。"

    @Parameter(description: "分类: injury, goal, preference, schedule 之一")
    public var category: String

    @Parameter(description: "简洁清晰的记忆内容，例如 '左膝半月板微痛，避免跳跃动作'")
    public var content: String

    private let context: AgentExecutionContext

    public init(context: AgentExecutionContext) {
        self.context = context
    }

    public func execute() async throws -> String? {
        await AgentToolLogic.saveMemory(categoryRaw: category, content: content, context: context)
    }
}

public struct SpeziSearchExercisesTool: LLMFunction {
    public static let name = "search_exercise_catalog"
    public static let description = "按肌群或关键词检索内置动作库 ID，便于后续生成具体可练动作。"

    @Parameter(description: "肌群或动作关键词，例如 chest, upper-back, quadriceps, 卧推, 深蹲")
    public var query: String

    public init() {}

    public func execute() async throws -> String? {
        AgentToolLogic.searchExercises(muscleFilter: query)
    }
}

public struct SpeziProposeWorkoutTool: LLMFunction {
    public static let name = "propose_adapted_workout"
    public static let description = "根据恢复分与肌肉疲劳为用户生成一套待确认的今日训练处方，供界面展示确认卡片。"

    @Parameter(description: "训练课表标题，如 '减量上肢维持'")
    public var title: String

    @Parameter(description: "强度标签，如 '推进', '维持', '减量', '主动恢复'")
    public var focusTag: String

    @Parameter(description: "逗号分隔的动作 ID，如 'barbell-bench-press,lat-pulldown'")
    public var exerciseIDsCSV: String

    @Parameter(description: "容量/强度倍率 0.5 到 1.2")
    public var intensityMultiplier: Double

    @Parameter(description: "组间休息秒数，通常 60 到 150")
    public var restSeconds: Double

    @Parameter(description: "结合生理数据与记忆的简明推荐原因")
    public var rationale: String

    private let context: AgentExecutionContext

    public init(context: AgentExecutionContext) {
        self.context = context
    }

    public func execute() async throws -> String? {
        await AgentToolLogic.proposeWorkout(
            title: title,
            focusTag: focusTag,
            exerciseIDsCSV: exerciseIDsCSV,
            intensityMultiplier: intensityMultiplier,
            restSeconds: Int(restSeconds.rounded()),
            rationale: rationale,
            context: context
        )
    }
}

// MARK: - Apple FoundationModels Native On-Device Tools

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
struct FMPhysiologyTool: Tool {
    let name = "query_physiology_and_training"
    let description = "查询用户今日恢复/睡眠/负荷数据、ACWR 与近期训练记录"
    let context: AgentExecutionContext

    @Generable
    struct Arguments {
        @Guide(description: "需要查询的重点方面，例如 recovery 或 training")
        var aspect: String
    }

    func call(arguments: Arguments) async throws -> String {
        AgentToolLogic.physiologyAndTrainingReport(context: context)
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct FMSaveMemoryTool: Tool {
    let name = "save_athlete_memory"
    let description = "保存用户伤病约束、目标或训练习惯到长期记忆"
    let context: AgentExecutionContext

    @Generable
    struct Arguments {
        @Guide(description: "category: injury, goal, preference, or schedule")
        var category: String
        @Guide(description: "需要长期记住的内容")
        var content: String
    }

    func call(arguments: Arguments) async throws -> String {
        await AgentToolLogic.saveMemory(categoryRaw: arguments.category, content: arguments.content, context: context)
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct FMProposeWorkoutTool: Tool {
    let name = "propose_adapted_workout"
    let description = "根据用户生理状态生成待确认的今日健身模板处方"
    let context: AgentExecutionContext

    @Generable
    struct Arguments {
        @Guide(description: "训练名称")
        var title: String
        @Guide(description: "标签如 推进/减量/主动恢复")
        var focusTag: String
        @Guide(description: "逗号分隔的动作 ID，例如 barbell-bench-press,lat-pulldown")
        var exerciseIDsCSV: String
        @Guide(description: "强度系数 0.6~1.1")
        var intensityMultiplier: Double
        @Guide(description: "组间休息秒数")
        var restSeconds: Int
        @Guide(description: "依据生理指标的推荐理由")
        var rationale: String
    }

    func call(arguments: Arguments) async throws -> String {
        await AgentToolLogic.proposeWorkout(
            title: arguments.title,
            focusTag: arguments.focusTag,
            exerciseIDsCSV: arguments.exerciseIDsCSV,
            intensityMultiplier: arguments.intensityMultiplier,
            restSeconds: arguments.restSeconds,
            rationale: arguments.rationale,
            context: context
        )
    }
}
#endif
