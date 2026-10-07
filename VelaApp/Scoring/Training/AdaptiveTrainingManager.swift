import Foundation
import SwiftData

// MARK: - Training Plan Adaptation Record

@Model
final class TrainingPlanAdaptationRecord {
    @Attribute(.unique) var id: UUID
    var planId: UUID
    var dayId: UUID
    var createdAt: Date
    var adjustment: String  // keep, reduce, swap, rest, reschedule, deloadWeek
    var reason: String
    var suggestedAlternative: String?
    var status: String  // proposed, accepted, rejected
    var acceptedAt: Date?
    var rejectedAt: Date?
    var originalDayTitle: String
    var agentRunId: String?

    init(
        id: UUID = UUID(),
        planId: UUID,
        dayId: UUID,
        createdAt: Date = Date(),
        adjustment: AdaptiveTrainingEngine.Adjustment,
        reason: String,
        suggestedAlternative: String? = nil,
        status: AdaptationStatus = .proposed,
        acceptedAt: Date? = nil,
        rejectedAt: Date? = nil,
        originalDayTitle: String = "",
        agentRunId: String? = nil
    ) {
        self.id = id
        self.planId = planId
        self.dayId = dayId
        self.createdAt = createdAt
        self.adjustment = adjustment.rawValue
        self.reason = reason
        self.suggestedAlternative = suggestedAlternative
        self.status = status.rawValue
        self.acceptedAt = acceptedAt
        self.rejectedAt = rejectedAt
        self.originalDayTitle = originalDayTitle
        self.agentRunId = agentRunId
    }
}

enum AdaptationStatus: String, Codable, Hashable, CaseIterable {
    case proposed
    case accepted
    case rejected
}

// MARK: - Adaptive Training Manager 2.0

struct AdaptiveTrainingManager {

    /// Creates at most one state-driven proposal for the executable plan day each calendar day.
    /// The user remains the decision maker: this method never mutates the plan itself.
    @MainActor
    func refreshDailyProposal(
        plan: TrainingPlanRecord,
        dashboard: DashboardSummary,
        events: [WorkoutEventRecord],
        foodLogs: [FoodLogRecord],
        journalEntries: [JournalEntryRecord],
        modelContext: ModelContext,
        date: Date = Date(),
        calendar: Calendar = .current
    ) throws -> TrainingPlanAdaptationRecord? {
        guard dashboard.source != .empty,
              dashboard.recovery.hasData,
              let day = TrainingScheduleResolver.resolve(
                plan: plan.dto,
                on: date,
                events: events.map { $0.dto },
                calendar: calendar
              ),
              day.focus != "rest" else {
            return nil
        }

        let dayIdentifier = DailyHealthSummaryRecord.dayIdentifier(for: date, calendar: calendar)
        let runID = "daily-plan-review:\(plan.id.uuidString):\(day.id.uuidString):\(dayIdentifier)"
        var descriptor = FetchDescriptor<TrainingPlanAdaptationRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        if let existing = try modelContext.fetch(descriptor).first(where: { $0.agentRunId == runID }) {
            return existing.status == AdaptationStatus.proposed.rawValue ? existing : nil
        }

        let interpretation = BodyInterpreterEngine().interpret(
            dashboard: dashboard,
            wiki: [:],
            activePlan: plan,
            foodLogs: foodLogs,
            journalEntries: journalEntries
        )
        guard interpretation.overallConfidence != .unavailable,
              let adjusted = AdaptiveTrainingEngine.adjust(day: day, interpretation: interpretation),
              adjusted.adjustment != .keep else {
            return nil
        }

        let proposal = TrainingPlanAdaptationRecord(
            planId: plan.id,
            dayId: day.id,
            adjustment: adjusted.adjustment,
            reason: adjusted.reason,
            suggestedAlternative: adjusted.suggestedAlternative,
            status: .proposed,
            originalDayTitle: day.title,
            agentRunId: runID
        )
        modelContext.insert(proposal)
        try modelContext.save()
        return proposal
    }

    /// Applies a user-confirmed adaptation to the training plan.
    ///
    /// The proposal state is intentionally not promoted here. Callers that
    /// have an explicit user confirmation (for example, the Today decision
    /// helper) mark the record as accepted only after this method succeeds.
    /// Replaying an already-accepted record is a no-op so a duplicated UI
    /// event cannot append another suffix or halve a duration a second time.
    /// A proposed record older than one calendar day is no longer actionable;
    /// the attempted acceptance closes it as rejected instead of applying a
    /// stale recommendation to the current plan.
    func applyAdaptation(
        _ record: TrainingPlanAdaptationRecord,
        to plan: TrainingPlanRecord,
        at date: Date = Date()
    ) -> Bool {
        guard record.planId == plan.id else { return false }

        switch record.status {
        case AdaptationStatus.accepted.rawValue:
            // The first acceptance already applied the plan mutation. Treat
            // retries as successful no-ops to make the state transition
            // idempotent without changing timestamps or rich day metadata.
            return true
        case AdaptationStatus.proposed.rawValue:
            break
        default:
            // Rejected and unknown states require a fresh proposal and must
            // never mutate the plan implicitly.
            return false
        }

        if date >= record.createdAt,
           date.timeIntervalSince(record.createdAt) >= Self.proposalExpirationInterval {
            record.status = AdaptationStatus.rejected.rawValue
            record.rejectedAt = date
            return false
        }

        guard let dayIndex = plan.days.firstIndex(where: { $0.id == record.dayId }) else { return false }

        switch record.adjustment {
        case "keep":
            // AI 练后边界常以 keep 表达「维持计划但遵守容量/RPE 边界」。
            // 确认后无需改计划结构，但必须返回 true 让提案状态机走到 accepted，
            // 否则 keep 提案永远停在待确认列表。
            return true
        case "rest":
            var updated = plan.days[dayIndex]
            updated.title = AppLanguage.stored.isChinese ? "休息日（调整后）" : "Rest Day (Adjusted)"
            updated.description = record.reason
            updated.focus = "rest"
            updated.durationMinutes = 0
            updated.intensity = "low"
            plan.days[dayIndex] = updated
        case "reduce":
            let halfDuration = max(15, plan.days[dayIndex].durationMinutes / 2)
            var modified = plan.days[dayIndex]
            modified.title += AppLanguage.stored.isChinese ? "（减量）" : " (Reduced)"
            modified.description = record.suggestedAlternative ?? modified.description
            modified.durationMinutes = halfDuration
            modified.intensity = "moderate"
            plan.days[dayIndex] = modified
        case "swap":
            var updated = plan.days[dayIndex]
            updated.title = AppLanguage.stored.isChinese ? "主动恢复（调整后）" : "Active Recovery (Adjusted)"
            updated.description = record.suggestedAlternative ?? updated.description
            updated.focus = "flexibility"
            updated.durationMinutes = 30
            updated.intensity = "low"
            plan.days[dayIndex] = updated
        case "reschedule":
            // Move the training day to the next available rest day
            var moved = plan.days[dayIndex]
            guard let nextRestIndex = plan.days.indices
                .first(where: { $0 > dayIndex && (plan.days[$0].focus == "rest" || plan.days[$0].focus == "flexibility") }) else {
                return false
            }
            moved.weekNumber = plan.days[nextRestIndex].weekNumber
            moved.dayNumber = plan.days[nextRestIndex].dayNumber
            moved.title += AppLanguage.stored.isChinese ? "（改期）" : " (Rescheduled)"
            // Mark original day as rest
            var restDay = plan.days[dayIndex]
            restDay.title = AppLanguage.stored.isChinese ? "休息日" : "Rest Day"
            restDay.description = AppLanguage.stored.isChinese ? "训练已改期" : "Training rescheduled"
            restDay.focus = "rest"
            restDay.durationMinutes = 0
            restDay.intensity = "low"
            plan.days[dayIndex] = restDay
            plan.days[nextRestIndex] = moved
        case "deloadWeek":
            // Convert all remaining days this week to light recovery
            let currentWeek = plan.days[dayIndex].weekNumber
            for i in plan.days.indices where plan.days[i].weekNumber == currentWeek && plan.days[i].focus != "rest" {
                var updated = plan.days[i]
                updated.title = AppLanguage.stored.isChinese ? "减载周（调整后）" : "Deload Week (Adjusted)"
                updated.description = record.reason
                updated.focus = "flexibility"
                updated.durationMinutes = 20
                updated.intensity = "low"
                plan.days[i] = updated
            }
        default:
            return false
        }

        // Keep the plan's revision timestamp aligned with the explicit
        // mutation while leaving it untouched for a keep/no-op proposal.
        plan.updatedAt = date
        return true
    }

    /// Daily proposals are based on a point-in-time readiness snapshot. Once
    /// they are more than one day old, accepting them would apply stale
    /// guidance to a different training day.
    static let proposalExpirationInterval: TimeInterval = 24 * 60 * 60
}

// MARK: - Workout Adaptation Service

/// The post-workout review needs both sides of its factual contract: local
/// training facts and the health/recovery signals used to interpret them.
/// Keep this gate separate from the broader network-AI gate so callers cannot
/// accidentally send a partial, misleading review when only one category is
/// authorized.
enum PostWorkoutAIGenerationGate {
    static func allows(policy: AgentOutboundConsentPolicy) -> Bool {
        policy.canSendNetworkAI
            && policy.allows(.health)
            && policy.allows(.training)
    }
}

typealias PostWorkoutAIGeneratorInvocation = @MainActor @Sendable (
    _ apiKey: String,
    _ factsText: String
) async throws -> PostWorkoutAIBoundary

typealias PostWorkoutOutboundPolicyProvider = @MainActor @Sendable () -> AgentOutboundConsentPolicy

@MainActor
struct WorkoutAdaptationService: Sendable {
    private let postWorkoutAIGenerator: PostWorkoutAIGeneratorInvocation
    private let outboundPolicyProvider: PostWorkoutOutboundPolicyProvider

    init(
        postWorkoutAIGenerator: @escaping PostWorkoutAIGeneratorInvocation = { apiKey, factsText in
            try await PostWorkoutAIGenerator.generate(apiKey: apiKey, factsText: factsText)
        },
        outboundPolicyProvider: @escaping PostWorkoutOutboundPolicyProvider = {
            AgentOutboundConsentPolicy.current
        }
    ) {
        self.postWorkoutAIGenerator = postWorkoutAIGenerator
        self.outboundPolicyProvider = outboundPolicyProvider
    }

    /// Main entry point for closed-loop post-workout training adaptation.
    /// Called when a workout is completed or post-workout check-in sheet is submitted.
    @discardableResult
    func processWorkoutCompletion(
        workoutID: UUID?,
        modelContext: ModelContext,
        now: Date = Date()
    ) async throws -> TrainingPlanAdaptationRecord? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        // 1. Fetch active plan
        let activePlans = (try? modelContext.fetch(FetchDescriptor<TrainingPlanRecord>(
            predicate: #Predicate { $0.isActive }
        ))) ?? []
        guard let activePlan = activePlans.first else {
            return nil
        }

        // Completion is a canonical product fact even when the current body
        // snapshot cannot produce a new plan proposal. Persist it before the
        // optional adaptation pass so a transient HealthKit failure never
        // erases the completed-workout event.
        VelaEventService.shared.log(
            modelContext: modelContext,
            type: VelaProductEventType.workoutCompleted,
            title: "完成训练记录打卡",
            detail: "训练事实已保存；Vela 会在可用信号足够时更新下一次训练边界。",
            metadata: ["workout_id": workoutID?.uuidString ?? ""]
        )
        try modelContext.save()

        // 2. Re-evaluate from the latest local evidence. Completing a workout
        // must stay fast and deterministic; the normal dashboard refresh owns
        // HealthKit synchronization and can retry independently.
        let dashboard = (try? await DailySummaryUseCase().loadCachedDashboard(
            for: now,
            modelContext: modelContext
        )) ?? DashboardSummary.empty(date: today)

        let events = (try? modelContext.fetch(FetchDescriptor<WorkoutEventRecord>())) ?? []
        let foods = (try? modelContext.fetch(FetchDescriptor<FoodLogRecord>())) ?? []
        let journals = (try? modelContext.fetch(FetchDescriptor<JournalEntryRecord>())) ?? []

        // 3. Trigger AdaptiveTrainingManager refreshDailyProposal
        let manager = AdaptiveTrainingManager()
        let proposal: TrainingPlanAdaptationRecord?
        do {
            proposal = try manager.refreshDailyProposal(
                plan: activePlan,
                dashboard: dashboard,
                events: events,
                foodLogs: foods,
                journalEntries: journals,
                modelContext: modelContext,
                date: now,
                calendar: calendar
            )
        } catch {
            // A training fact is more durable than an optional proposal. Keep
            // the saved completion and let a later refresh retry adaptation.
            VelaAppState.shared.markLocalDataChanged()
            return nil
        }

        if let proposal {
            VelaEventService.shared.log(
                modelContext: modelContext,
                type: VelaProductEventType.trainingPlanAdapted,
                title: "智能训练处方微调",
                detail: proposal.reason,
                metadata: [
                    "adjustment": proposal.adjustment,
                    "plan_id": activePlan.id.uuidString
                ]
            )
        }

        try modelContext.save()
        VelaAppState.shared.markLocalDataChanged()

        // 深度专项批次 4（管线 C）：练后 AI 复盘——异步、失败静默；
        // 本机训练事实与提案已落库，AI 只追加观察 + 待确认边界建议。
        // Resolve consent at the outbound boundary, after local facts and any
        // local proposal have been persisted.  This deliberately precedes the
        // Keychain lookup: denied paths must not even prepare a provider call.
        let outboundPolicy = outboundPolicyProvider()
        guard PostWorkoutAIGenerationGate.allows(policy: outboundPolicy),
              let aiKey = try? KeychainService.shared.read(account: "deepseek_api_key"),
              !aiKey.isEmpty else {
            return proposal
        }

        let facts = PostWorkoutAIGenerator.factsText(
            modelContext: modelContext,
            dashboard: dashboard,
            workoutID: workoutID,
            policy: outboundPolicy
        )
        let ctx = modelContext
        let plan = activePlan
        let completedAt = now
        let completedWorkoutID = workoutID
        let generate = postWorkoutAIGenerator
        let policyProvider = outboundPolicyProvider
        Task { @MainActor in
            // Consent can be revoked while the local completion task is
            // waiting to start. Re-check immediately before invoking the
            // network provider so revocation wins without affecting local
            // training facts or confirmation/idempotency semantics.
            guard PostWorkoutAIGenerationGate.allows(policy: policyProvider()) else {
                return
            }
            do {
                let boundary = try await generate(aiKey, facts)
                let runID = "ai-post-workout-\(completedWorkoutID?.uuidString ?? "unknown")"
                let existingArtifacts = (try? ctx.fetch(FetchDescriptor<CoachArtifactRecord>(
                    predicate: #Predicate<CoachArtifactRecord> { $0.sourceContextHash == runID }
                ))) ?? []
                let existingProposals = (try? ctx.fetch(FetchDescriptor<TrainingPlanAdaptationRecord>())) ?? []
                let alreadyHasArtifact = existingArtifacts.contains { $0.sourceContextHash == runID }
                let alreadyHasProposal = existingProposals.contains { $0.agentRunId == runID }

                // ① 观察性复盘 → CoachArtifactRecord（AI 标注）。
                if !alreadyHasArtifact {
                    let artifact = CoachArtifact(
                        type: .postWorkoutReview,
                        title: "AI 练后复盘",
                        summary: boundary.observation,
                        createdAt: Date(),
                        relatedDate: completedAt,
                        decision: nil,
                        confidence: 0.6,
                        reasons: [
                            CoachArtifactReason(
                                signal: "ai_review",
                                value: boundary.rationale,
                                explanation: "AI 复盘基于本机训练事实；训练事实为唯一真值，边界建议需用户确认。"
                            )
                        ],
                        actions: [],
                        sourceContextHash: runID,
                        followUpQuestion: nil
                    )
                    ctx.insert(CoachArtifactRecord(artifact: artifact))
                }
                // ② 下次训练边界建议 → 提案状态机（proposed，用户确认才生效）。
                // 下一个训练日同样走 TrainingScheduleResolver：跳过今天已完成的计划日，
                // 再退回「未完成 + 非休息」的简单兜底。
                let events = (try? ctx.fetch(FetchDescriptor<WorkoutEventRecord>())) ?? []
                let nextEvaluationDate = Calendar.current.date(byAdding: .day, value: 1, to: completedAt) ?? completedAt
                let resolvedNextDay = TrainingScheduleResolver.resolve(
                    plan: plan.dto,
                    on: nextEvaluationDate,
                    events: events.map { $0.dto }
                )
                let fallbackNextDay = plan.days
                    .filter({ !$0.isCompleted && $0.focus.lowercased() != "rest" })
                    .sorted(by: { $0.dayNumber < $1.dayNumber })
                    .first
                if !alreadyHasProposal,
                   let nextDay = resolvedNextDay ?? fallbackNextDay {
                    ctx.insert(TrainingPlanAdaptationRecord(
                        planId: plan.id,
                        dayId: nextDay.id,
                        adjustment: .keep,
                        reason: "AI 建议：容量 \(Int((boundary.nextVolumeMultiplier * 100).rounded()))% · RPE ≤ \(boundary.nextIntensityCap)"
                            + (boundary.nextSuggestedFocus.map { " · 建议部位 \($0)" } ?? "")
                            + "。依据：\(boundary.rationale)",
                        suggestedAlternative: nil,
                        status: .proposed,
                        originalDayTitle: nextDay.title,
                        agentRunId: runID
                    ))
                }
                try ctx.save()
            } catch {
                // 静默：本机复盘与提案不受影响。
            }
        }

        return proposal
    }
}

// MARK: - 深度专项批次 4：练后 AI 复盘（管线 C）
// 训练完成后异步生成：① 观察性复盘（CoachArtifactRecord，AI 标注）
// ② 下次训练边界建议（TrainingPlanAdaptationRecord，proposed，用户确认才生效）。
// 本机训练事实是唯一真值；AI 失败静默回退本机流程（ADR 0008）。

struct PostWorkoutAIBoundary: Codable, Hashable, Sendable {
    var observation: String
    var nextVolumeMultiplier: Double
    var nextIntensityCap: Int
    var nextSuggestedFocus: String?
    var rationale: String

    static func parse(from text: String) -> PostWorkoutAIBoundary? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
        }
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}"),
              start < end else { return nil }
        guard let data = String(cleaned[start...end]).data(using: .utf8) else { return nil }
        guard var boundary = try? JSONDecoder().decode(PostWorkoutAIBoundary.self, from: data) else {
            return nil
        }
        // 护栏：容量/RPE 钳制在保守区间，防止模型输出异常值。
        boundary.nextVolumeMultiplier = min(1.0, max(0.3, boundary.nextVolumeMultiplier))
        boundary.nextIntensityCap = min(10, max(1, boundary.nextIntensityCap))
        return boundary
    }
}

enum PostWorkoutAIGenerator {
    /// 联通专项批次 4：练后复盘事实改走 AgentFactSnapshot（ADR 0002），
    /// 不再自拼 contextText。
    @MainActor
    static func factsText(
        modelContext: ModelContext,
        dashboard: DashboardSummary,
        workoutID: UUID?,
        isChinese: Bool = AppLanguage.stored.isChinese,
        policy: AgentOutboundConsentPolicy? = nil
    ) -> String {
        let input = AgentFactInputLoader().load(modelContext: modelContext, asOf: Date())
        let bodyState = input.bodyState(dashboard: dashboard)
        let snapshot = AIContextBuilder().buildFacts(
            dashboard: dashboard,
            journalEntries: input.journalContext,
            historicalReports: input.reportContext,
            userWiki: WikiFileService.loadPopulatedDictionary(),
            weeklyTrends: input.weeklyTrends,
            foodLogs: input.foodLogs,
            workoutEvents: input.workoutEvents,
            strengthWorkouts: input.strengthWorkouts,
            trainingResponses: input.trainingResponses,
            onboardingState: input.onboardingState,
            bodyState: bodyState,
            trainingDecision: input.canonicalTrainingDecision(for: bodyState),
            dataCoverage: nil,
            scoringContext: dashboard.scoringContext,
            dailyOperatingPlan: AIContextBuilder.compactDailyOperatingPlan(input.dailyOperatingPlan),
            activePlan: input.activePlan?.dto,
            generatedAt: Date()
        ).snapshot
        return AgentFactAdapters.postWorkoutFacts(
            snapshot: snapshot,
            workoutID: workoutID,
            isChinese: isChinese,
            policy: policy
        )
    }

    static func generate(
        apiKey: String,
        factsText: String,
        language: AppLanguage = .stored
    ) async throws -> PostWorkoutAIBoundary {
        let provider = RetryingLLMProvider(base: DeepSeekProvider(apiKey: apiKey))
        let systemPrompt = language.isChinese ? """
        你是 Vela 的训练后复盘助手。基于本机训练事实输出严格 JSON，不要输出任何其他文字。

        输出格式：
        {"observation":"一句练后观察（人话）","nextVolumeMultiplier":0.0到1.0,"nextIntensityCap":1到10,"nextSuggestedFocus":"建议下次训练部位或 null","rationale":"一句依据，引用具体数值"}

        硬性规则：
        1. 训练事实是唯一真值；你只解释与提议，不改写事实。
        2. 边界建议必须保守：恢复/睡眠/压力差时容量≤0.7、RPE≤7。
        3. 你的建议只是提案，用户确认后才生效。
        4. 只输出 JSON 本身。
        """ : """
        You are Vela's post-workout review assistant. Output strict JSON only, nothing else.

        Format:
        {"observation":"one-sentence review","nextVolumeMultiplier":0.0-1.0,"nextIntensityCap":1-10,"nextSuggestedFocus":"suggested muscle group or null","rationale":"one reason citing numbers"}

        Rules:
        1. Training facts are the single source of truth; interpret and propose, never rewrite facts.
        2. Boundaries must be conservative: volume<=0.7 and RPE<=7 when recovery/sleep/stress are poor.
        3. Your output is a proposal only; it takes effect after user confirmation.
        4. Output JSON only.
        """
        let response = try await LLMProviderDeadline.withTimeout(seconds: 20) {
            try await provider.complete(request: LLMRequest(
                systemPrompt: systemPrompt,
                userPrompt: factsText,
                contextJSON: ""
            ))
        }
        guard let boundary = PostWorkoutAIBoundary.parse(from: response.content) else {
            throw LLMProviderError.invalidResponse
        }
        return boundary
    }
}
