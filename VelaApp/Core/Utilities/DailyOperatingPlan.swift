import Foundation
import SwiftData

enum DailyOperatingPlanActionDomain: String, Codable, Hashable, CaseIterable, Sendable {
    case training
    case movement
    case eatingRhythm = "eating_rhythm"
    case stressRecovery = "stress_recovery"
    case sleep
}

/// A reviewable action in the canonical Daily Operating Plan.
///
/// The action stores its user-facing copy because the same persisted plan is consumed by
/// Today, Training, Vela, notifications, and the Watch projection. `destination` is a
/// stable navigation hint; it is not an instruction to perform a side effect silently.
struct DailyOperatingPlanAction: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var domain: DailyOperatingPlanActionDomain
    var title: String
    var detail: String
    var destination: String
    var evidence: String?
    var scheduledAt: Date? = nil
    var completedAt: Date? = nil
    var userEditedAt: Date? = nil
}

struct DailyOperatingPlanPayload: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var decision: DailyTrainingDecisionType
    var volumeMultiplier: Double
    var intensityCap: Int
    var summary: String
    var targetSessionTitle: String?
    var primaryAction: DailyOperatingPlanAction?
    var supportingActions: [DailyOperatingPlanAction]
    /// Once present, automatic recomputation must propose changes instead of
    /// overwriting the user's plan. Completion and scheduling are user-owned.
    var userEditedAt: Date?
    /// Additive provenance for newly evaluated confidence. Legacy payloads
    /// decode with nil; this does not change user actions or kernel source.
    var feedbackEvidencePolicyVersion: String? = nil
    var feedbackEvidenceAsOf: Date? = nil

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        decision: DailyTrainingDecisionType,
        volumeMultiplier: Double,
        intensityCap: Int,
        summary: String,
        targetSessionTitle: String?,
        primaryAction: DailyOperatingPlanAction? = nil,
        supportingActions: [DailyOperatingPlanAction] = [],
        userEditedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.decision = decision
        self.volumeMultiplier = volumeMultiplier
        self.intensityCap = intensityCap
        self.summary = summary
        self.targetSessionTitle = targetSessionTitle
        self.primaryAction = primaryAction
        self.supportingActions = Self.boundedSupportingActions(
            supportingActions,
            excluding: primaryAction?.domain
        )
        self.userEditedAt = userEditedAt
    }

    /// True only for the versioned, bounded cross-domain contract. Legacy payloads still
    /// decode and continue to provide their training boundary while the next refresh
    /// upgrades them through `DailyOperatingPlanCoordinator`.
    var hasCanonicalActionSequence: Bool {
        guard schemaVersion >= 2 else {
            return false
        }
        if primaryAction == nil {
            return userEditedAt != nil && supportingActions.count <= 2
        }
        guard let primaryAction else { return false }
        let domains = supportingActions.map(\.domain)
        return supportingActions.count <= 2
            && !domains.contains(primaryAction.domain)
            && Set(domains).count == domains.count
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case decision
        case volumeMultiplier
        case intensityCap
        case summary
        case targetSessionTitle
        case primaryAction
        case supportingActions
        case userEditedAt
        case feedbackEvidencePolicyVersion
        case feedbackEvidenceAsOf
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        decision = try values.decode(DailyTrainingDecisionType.self, forKey: .decision)
        volumeMultiplier = try values.decode(Double.self, forKey: .volumeMultiplier)
        intensityCap = try values.decode(Int.self, forKey: .intensityCap)
        summary = try values.decode(String.self, forKey: .summary)
        targetSessionTitle = try values.decodeIfPresent(String.self, forKey: .targetSessionTitle)
        primaryAction = try values.decodeIfPresent(DailyOperatingPlanAction.self, forKey: .primaryAction)
        let decodedSupporting = try values.decodeIfPresent(
            [DailyOperatingPlanAction].self,
            forKey: .supportingActions
        ) ?? []
        supportingActions = Self.boundedSupportingActions(
            decodedSupporting,
            excluding: primaryAction?.domain
        )
        userEditedAt = try values.decodeIfPresent(Date.self, forKey: .userEditedAt)
        feedbackEvidencePolicyVersion = try values.decodeIfPresent(String.self, forKey: .feedbackEvidencePolicyVersion)
        feedbackEvidenceAsOf = try values.decodeIfPresent(Date.self, forKey: .feedbackEvidenceAsOf)
    }

    private static func boundedSupportingActions(
        _ actions: [DailyOperatingPlanAction],
        excluding primaryDomain: DailyOperatingPlanActionDomain?
    ) -> [DailyOperatingPlanAction] {
        var seen = Set<DailyOperatingPlanActionDomain>()
        return Array(actions.filter { action in
            guard action.domain != primaryDomain,
                  seen.insert(action.domain).inserted else {
                return false
            }
            return true
        }.prefix(2))
    }
}

enum DailyOperatingPlanMutation {
    case toggleCompletion(actionID: String, at: Date)
    case update(action: DailyOperatingPlanAction, at: Date)
    case add(action: DailyOperatingPlanAction, at: Date)
    case delete(actionID: String, at: Date)
}

/// A failed save restores only the records touched by this operation. A global
/// ModelContext rollback would also discard unrelated edits in the shared context.
@MainActor
private final class DailyOperatingPlanWriteTransaction {
    private let context: ModelContext
    private var undo: [() -> Void] = []

    private init(context: ModelContext) { self.context = context }

    static func run<T>(
        context: ModelContext,
        saveChanges: (ModelContext) throws -> Void,
        changes: (DailyOperatingPlanWriteTransaction) throws -> T
    ) throws -> T {
        try PersistenceWriteGate.shared.assertWritable(operation: "Save daily operating plan")
        let transaction = DailyOperatingPlanWriteTransaction(context: context)
        do {
            let result = try changes(transaction)
            try saveChanges(context)
            return result
        } catch {
            transaction.undo.reversed().forEach { $0() }
            throw error
        }
    }

    func capture(_ record: DailyOperatingPlanRecord) {
        let previous = (
            record.bodyStateHash, record.generatedAt, record.primaryActionType,
            record.title, record.payloadJSON, record.reasonsJSON, record.confidence,
            record.status, record.source, record.safetyNotice
        )
        undo.append {
            (record.bodyStateHash, record.generatedAt, record.primaryActionType,
             record.title, record.payloadJSON, record.reasonsJSON, record.confidence,
             record.status, record.source, record.safetyNotice) = previous
        }
    }

    func capture(_ record: AgentArtifactRecord) {
        let previous = (
            record.title, record.payloadJSON, record.sourceContextHash,
            record.status, record.confidence, record.source, record.safetyNotice
        )
        undo.append {
            (record.title, record.payloadJSON, record.sourceContextHash,
             record.status, record.confidence, record.source, record.safetyNotice) = previous
        }
    }

    func insert<T: PersistentModel>(_ record: T) {
        context.insert(record)
        undo.append { [context] in context.delete(record) }
    }
}

enum DailyOperatingPlanEditor {
    static func applying(
        _ mutation: DailyOperatingPlanMutation,
        to payload: DailyOperatingPlanPayload
    ) -> DailyOperatingPlanPayload {
        var result = payload

        switch mutation {
        case let .toggleCompletion(actionID, date):
            result = mapAction(in: result, id: actionID) { action in
                var action = action
                action.completedAt = action.completedAt == nil ? date : nil
                action.userEditedAt = date
                return action
            }

        case let .update(action, date):
            var edited = action
            edited.userEditedAt = date
            result = mapAction(in: result, id: action.id) { _ in edited }

        case let .add(action, date):
            guard result.primaryAction == nil || result.supportingActions.count < 2 else {
                return result
            }
            let usedDomains = Set(result.allActions.map(\.domain))
            guard !usedDomains.contains(action.domain) else { return result }
            var edited = action
            edited.userEditedAt = date
            if result.primaryAction == nil {
                result.primaryAction = edited
            } else {
                result.supportingActions.append(edited)
            }

        case let .delete(actionID, _):
            if result.primaryAction?.id == actionID {
                result.primaryAction = result.supportingActions.first
                result.supportingActions = Array(result.supportingActions.dropFirst())
            } else {
                result.supportingActions.removeAll { $0.id == actionID }
            }
        }

        let editedAt: Date
        switch mutation {
        case let .toggleCompletion(_, date), let .update(_, date), let .add(_, date), let .delete(_, date):
            editedAt = date
        }
        result.schemaVersion = DailyOperatingPlanPayload.currentSchemaVersion
        result.userEditedAt = editedAt
        return result
    }

    @MainActor
    static func persist(
        _ payload: DailyOperatingPlanPayload,
        to record: DailyOperatingPlanRecord,
        modelContext: ModelContext,
        saveChanges: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try DailyOperatingPlanWriteTransaction.run(context: modelContext, saveChanges: saveChanges) { transaction in
            try persist(payload, to: record, modelContext: modelContext, transaction: transaction)
        }
    }

    @MainActor
    private static func persist(
        _ payload: DailyOperatingPlanPayload,
        to record: DailyOperatingPlanRecord,
        modelContext: ModelContext,
        transaction: DailyOperatingPlanWriteTransaction
    ) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        transaction.capture(record)
        record.payloadJSON = json
        record.title = payload.primaryAction?.title ?? "今日计划"
        record.primaryActionType = payload.decision.rawValue
        record.status = "active"

        let artifactType = AgentArtifactType.dailyPlan.rawValue
        let contextHash = record.bodyStateHash
        let descriptor = FetchDescriptor<AgentArtifactRecord>(
            predicate: #Predicate<AgentArtifactRecord> {
                $0.type == artifactType && $0.sourceContextHash == contextHash
            }
        )
        if let artifact = try modelContext.fetch(descriptor).first {
            transaction.capture(artifact)
            artifact.title = record.title
            artifact.payloadJSON = json
            artifact.status = "active"
        } else {
            transaction.insert(AgentArtifactRecord(
                type: artifactType,
                title: record.title,
                payloadJSON: json,
                sourceContextHash: contextHash,
                confidence: record.confidence,
                source: record.source ?? "DailyOperatingPlanEditor",
                safetyNotice: record.safetyNotice
            ))
        }
    }

    /// Records the user's decision to keep their edited plan after the upstream
    /// Body State changes, and moves the matching Agent artifact to the same context.
    @MainActor
    static func acknowledgeCurrentPlan(
        _ payload: DailyOperatingPlanPayload,
        record: DailyOperatingPlanRecord,
        bodyStateHash: String,
        modelContext: ModelContext,
        saveChanges: (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        try DailyOperatingPlanWriteTransaction.run(context: modelContext, saveChanges: saveChanges) { transaction in
            let artifactType = AgentArtifactType.dailyPlan.rawValue
            let previousHash = record.bodyStateHash
            let descriptor = FetchDescriptor<AgentArtifactRecord>(
                predicate: #Predicate<AgentArtifactRecord> {
                    $0.type == artifactType && $0.sourceContextHash == previousHash
                }
            )
            let previousArtifact = try modelContext.fetch(descriptor).first
            transaction.capture(record)
            if let previousArtifact { transaction.capture(previousArtifact) }
            record.bodyStateHash = bodyStateHash
            record.generatedAt = Date()
            previousArtifact?.sourceContextHash = bodyStateHash
            try persist(payload, to: record, modelContext: modelContext, transaction: transaction)
        }
    }

    private static func mapAction(
        in payload: DailyOperatingPlanPayload,
        id: String,
        transform: (DailyOperatingPlanAction) -> DailyOperatingPlanAction
    ) -> DailyOperatingPlanPayload {
        var result = payload
        if let primary = result.primaryAction, primary.id == id {
            let candidate = transform(primary)
            guard !result.supportingActions.contains(where: { $0.domain == candidate.domain }) else {
                return payload
            }
            result.primaryAction = candidate
            return result
        }
        guard let index = result.supportingActions.firstIndex(where: { $0.id == id }) else {
            return payload
        }
        let candidate = transform(result.supportingActions[index])
        if result.primaryAction?.domain == candidate.domain
            || result.supportingActions.enumerated().contains(where: { offset, action in
                offset != index && action.domain == candidate.domain
            }) {
            return payload
        }
        result.supportingActions[index] = candidate
        return result
    }
}

extension DailyOperatingPlanPayload {
    var allActions: [DailyOperatingPlanAction] {
        [primaryAction].compactMap { $0 } + supportingActions
    }

    /// Preserve the user's canonical action order when presenting what is next.
    var nextIncompleteAction: DailyOperatingPlanAction? {
        allActions.first { $0.completedAt == nil }
    }

    /// An intentionally empty plan is different from a completed plan.
    var allActionsCompleted: Bool {
        !allActions.isEmpty && nextIncompleteAction == nil
    }

    var hasUserEdits: Bool { userEditedAt != nil }

    /// Decision plus action outline. Used to avoid offering a candidate that
    /// would not change what the user sees.
    var actionOutline: String {
        let actions = allActions.map { "\($0.domain.rawValue):\($0.title)" }
        return ([decision.rawValue] + actions).joined(separator: "|")
    }
}

/// Automatic refresh may create a missing plan or migrate a legacy payload.
/// A canonical plan is kept when the body state changes; Plan offers a
/// candidate instead of replacing it.
enum DailyOperatingPlanRefreshPolicy {
    static func shouldRegenerate(
        usedPersistedDecision: Bool,
        persistedPayload: DailyOperatingPlanPayload?
    ) -> Bool {
        // A canonical plan stays put when the body state changes. The Plan
        // surface offers a candidate instead of replacing it, whether or not
        // the user has edited it. Legacy payloads still migrate.
        if persistedPayload?.hasCanonicalActionSequence == true {
            return false
        }
        guard persistedPayload?.hasUserEdits != true else { return false }
        return !usedPersistedDecision || persistedPayload?.hasCanonicalActionSequence != true
    }
}

/// Deterministic Implementation of ADR-0007's bounded, cross-domain plan contract.
/// Training remains the downstream decision source; this builder coordinates the rest
/// of the day without introducing an aggregate health score or a general task manager.
enum DailyOperatingPlanBuilder {
    static func build(
        bodyState: BodyState,
        decision: DailyTrainingDecision,
        brief: PersonalHealthBrief?,
        language: AppLanguage
    ) -> DailyOperatingPlanPayload {
        let isChinese = language.isChinese
        let primary = primaryAction(for: decision, isChinese: isChinese)
        let candidates = supportCandidates(
            bodyState: bodyState,
            decision: decision,
            brief: brief,
            isChinese: isChinese
        )
        let supports = candidates
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority { return lhs.action.id < rhs.action.id }
                return lhs.priority > rhs.priority
            }
            .map(\.action)

        return DailyOperatingPlanPayload(
            decision: decision.decision,
            volumeMultiplier: decision.volumeMultiplier,
            intensityCap: decision.intensityCap,
            summary: decision.userFacingSummary,
            targetSessionTitle: decision.targetSessionTitle,
            primaryAction: primary,
            supportingActions: supports
        )
    }

    private struct Candidate {
        var priority: Int
        var action: DailyOperatingPlanAction
    }

    private static func primaryAction(
        for decision: DailyTrainingDecision,
        isChinese: Bool
    ) -> DailyOperatingPlanAction {
        let evidence = decision.reasons.first
        let volume = Int((decision.volumeMultiplier * 100).rounded())
        switch decision.decision {
        case .keep:
            return DailyOperatingPlanAction(
                id: "primary_keep_training",
                domain: .training,
                title: isChinese ? "按计划开展训练" : "Follow today's training plan",
                detail: isChinese
                    ? "在 Apple Watch 开始训练，RPE 不超过 \(decision.intensityCap)，动作质量下降时及时收尾。"
                    : "Start on Apple Watch, stay at or below RPE \(decision.intensityCap), and stop adding work if technique declines.",
                destination: "training",
                evidence: evidence
            )
        case .reduce:
            return DailyOperatingPlanAction(
                id: "primary_reduce_training",
                domain: .training,
                title: isChinese ? "执行减量训练" : "Run a reduced session",
                detail: isChinese
                    ? "保留关键刺激，将容量控制在 \(volume)%，RPE 不超过 \(decision.intensityCap)。"
                    : "Keep the key stimulus, limit volume to \(volume)%, and stay at or below RPE \(decision.intensityCap).",
                destination: "training",
                evidence: evidence
            )
        case .swap:
            return DailyOperatingPlanAction(
                id: "primary_swap_training",
                domain: .training,
                title: isChinese ? "替换今日训练内容" : "Swap today's session",
                detail: isChinese
                    ? "避开高疲劳部位，保留约 \(volume)% 的低风险刺激，RPE 不超过 \(decision.intensityCap)。"
                    : "Avoid highly fatigued areas, keep about \(volume)% of the lower-risk stimulus, and cap RPE at \(decision.intensityCap).",
                destination: "training",
                evidence: evidence
            )
        case .rest:
            return DailyOperatingPlanAction(
                id: "primary_recovery_day",
                domain: .stressRecovery,
                title: isChinese ? "安排恢复日" : "Make today a recovery day",
                detail: isChinese
                    ? "停止追求训练量，把今天留给休息、放松和不费力的日常活动。"
                    : "Stop chasing training volume and leave today for rest, downshifting, and effortless daily activity.",
                destination: "recovery",
                evidence: evidence
            )
        }
    }

    private static func supportCandidates(
        bodyState: BodyState,
        decision: DailyTrainingDecision,
        brief: PersonalHealthBrief?,
        isChinese: Bool
    ) -> [Candidate] {
        var candidates: [Candidate] = []
        let sleepNeedsSupport = (bodyState.sleep.hasData && bodyState.sleep.score < 75)
            || brief?.suggestedActionCategory == .sleep
        if sleepNeedsSupport {
            let scoreEvidence = bodyState.sleep.hasData
                ? (isChinese
                    ? "睡眠评分 \(Int(bodyState.sleep.score.rounded()))"
                    : "Sleep score \(Int(bodyState.sleep.score.rounded()))")
                : brief?.actionDetail
            candidates.append(Candidate(
                priority: 95,
                action: DailyOperatingPlanAction(
                    id: "support_protect_sleep",
                    domain: .sleep,
                    title: isChinese ? "保护今晚睡眠" : "Protect tonight's sleep",
                    detail: isChinese
                        ? "固定结束时间，减少晚间刺激，为今晚留出完整睡眠窗口。"
                        : "Set a clear stopping time, reduce late stimulation, and preserve a full sleep window.",
                    destination: "evidence",
                    evidence: scoreEvidence
                )
            ))
        }

        let negativeLivedState = bodyState.drivers.contains {
            $0.kind == .journal && $0.impact < 0
        }
        let stressNeedsSupport = (bodyState.stress.hasData && bodyState.stress.score > 70)
            || bodyState.drivers.contains { $0.kind == .stress && $0.impact < 0 }
            || negativeLivedState
            || brief?.suggestedActionCategory == .recovery
            || brief?.suggestedActionCategory == .lifestyle
        if stressNeedsSupport {
            let stressEvidence: String? = bodyState.drivers.first {
                ($0.kind == .stress || $0.kind == .journal) && $0.impact < 0
            }?.detail ?? (bodyState.stress.hasData
                ? (isChinese
                    ? "压力评分 \(Int(bodyState.stress.score.rounded()))"
                    : "Stress score \(Int(bodyState.stress.score.rounded()))")
                : brief?.actionDetail)
            candidates.append(Candidate(
                priority: 90,
                action: DailyOperatingPlanAction(
                    id: "support_downshift",
                    domain: .stressRecovery,
                    title: isChinese ? "安排降压恢复块" : "Schedule a downshift block",
                    detail: isChinese
                        ? "留出 10–20 分钟散步、呼吸或安静休息，不把它变成额外训练。"
                        : "Use 10–20 minutes for a walk, breathing, or quiet rest without turning it into extra training.",
                    destination: "recovery",
                    evidence: stressEvidence
                )
            ))
        }

        if decision.decision != .keep {
            candidates.append(Candidate(
                priority: decision.decision == .rest ? 85 : 70,
                action: DailyOperatingPlanAction(
                    id: "support_light_movement",
                    domain: .movement,
                    title: isChinese ? "用轻量活动维持节律" : "Keep rhythm with light movement",
                    detail: isChinese
                        ? "只做能轻松交谈的步行或活动度练习；感觉变差就停止。"
                        : "Choose only conversational-pace walking or mobility work, and stop if you feel worse.",
                    destination: "recovery",
                    evidence: isChinese
                        ? "今日训练决定：\(localizedDecision(decision.decision, isChinese: true))"
                        : "Today's training decision: \(localizedDecision(decision.decision, isChinese: false))"
                )
            ))
        }

        // A recovery-oriented plan may include a neutral Eating Rhythm guardrail. It is
        // deliberately non-quantified and non-compensatory (ADR-0005/0006).
        if decision.decision == .rest || decision.decision == .reduce {
            candidates.append(Candidate(
                priority: 40,
                action: DailyOperatingPlanAction(
                    id: "support_normal_eating_rhythm",
                    domain: .eatingRhythm,
                    title: isChinese ? "维持正常进食节律" : "Keep a normal eating rhythm",
                    detail: isChinese
                        ? "按平常节奏进食和补水，不因一次波动额外限制或安排补偿性运动。"
                        : "Eat and hydrate on your normal rhythm; do not add restriction or compensatory exercise for a single disruption.",
                    destination: "evidence",
                    evidence: isChinese ? "恢复优先，不做补偿" : "Recovery first; no compensation"
                )
            ))
        }

        if candidates.isEmpty {
            candidates.append(Candidate(
                priority: 30,
                action: DailyOperatingPlanAction(
                    id: "support_preserve_sleep_rhythm",
                    domain: .sleep,
                    title: isChinese ? "保持今晚睡眠节律" : "Preserve tonight's sleep rhythm",
                    detail: isChinese
                        ? "保持稳定作息，让今天的正常节奏延续到明天。"
                        : "Keep a stable bedtime so today's rhythm carries into tomorrow.",
                    destination: "evidence",
                    evidence: brief?.confidenceLabel
                )
            ))
        }
        return candidates
    }

    private static func localizedDecision(
        _ decision: DailyTrainingDecisionType,
        isChinese: Bool
    ) -> String {
        switch decision {
        case .keep: return isChinese ? "按计划" : "keep"
        case .reduce: return isChinese ? "减量" : "reduce"
        case .swap: return isChinese ? "替换" : "swap"
        case .rest: return isChinese ? "恢复" : "rest"
        }
    }
}

struct DailyOperatingPlanDisplayModel: Codable, Hashable {
    var decision: DailyTrainingDecisionType
    var actionLabel: String
    var statusTitle: String
    var summary: String
    var primaryActionTitle: String
    var supportingActionLines: [String]
    var evidenceLine: String
    var confidenceLabel: String

    static func build(
        payload: DailyOperatingPlanPayload?,
        primaryActionType: String?,
        source: String?,
        safetyNotice: String?,
        confidence: Double,
        isChinese: Bool = AppLanguage.stored.isChinese
    ) -> DailyOperatingPlanDisplayModel {
        let decision = payload?.decision
            ?? primaryActionType.flatMap(DailyTrainingDecisionType.init(rawValue:))
            ?? .keep
        let intensityCap = payload?.intensityCap ?? (decision == .rest ? 2 : 7)
        let volumeMultiplier = payload?.volumeMultiplier ?? defaultVolumeMultiplier(for: decision)
        let summary = localizedSummary(
            payloadSummary: payload?.summary,
            decision: decision,
            volumeMultiplier: volumeMultiplier,
            intensityCap: intensityCap,
            isChinese: isChinese
        )
        let evidence = localizedEvidenceLine(
            source: source,
            safetyNotice: safetyNotice,
            isChinese: isChinese
        )
        let evidenceLabel: String
        if confidence >= 0.8 {
            evidenceLabel = isChinese ? "判断依据充分" : "Strong supporting evidence"
        } else if confidence >= 0.55 {
            evidenceLabel = isChinese ? "判断依据部分" : "Partial supporting evidence"
        } else {
            evidenceLabel = isChinese ? "判断依据有限" : "Limited supporting evidence"
        }

        return DailyOperatingPlanDisplayModel(
            decision: decision,
            actionLabel: actionLabel(for: decision, isChinese: isChinese),
            statusTitle: statusTitle(for: decision, intensityCap: intensityCap, isChinese: isChinese),
            summary: summary,
            primaryActionTitle: payload?.primaryAction?.title
                ?? actionLabel(for: decision, isChinese: isChinese),
            supportingActionLines: (payload?.supportingActions ?? []).map {
                "\($0.title)：\($0.detail)"
            },
            evidenceLine: evidence,
            confidenceLabel: evidenceLabel
        )
    }

    private static func defaultVolumeMultiplier(for decision: DailyTrainingDecisionType) -> Double {
        switch decision {
        case .keep: 1
        case .reduce: 0.75
        case .swap: 0.65
        case .rest: 0
        }
    }

    private static func actionLabel(for decision: DailyTrainingDecisionType, isChinese: Bool) -> String {
        switch decision {
        case .keep: return isChinese ? "按计划" : "KEEP"
        case .reduce: return isChinese ? "减量" : "REDUCE"
        case .swap: return isChinese ? "替换" : "SWAP"
        case .rest: return isChinese ? "恢复" : "REST"
        }
    }

    private static func statusTitle(
        for decision: DailyTrainingDecisionType,
        intensityCap: Int,
        isChinese: Bool
    ) -> String {
        if decision == .rest {
            return isChinese ? "建议恢复或休息" : "Recovery or rest advised"
        }
        return isChinese ? "建议训练 · RPE \(intensityCap)" : "Train today · RPE \(intensityCap)"
    }

    private static func localizedSummary(
        payloadSummary: String?,
        decision: DailyTrainingDecisionType,
        volumeMultiplier: Double,
        intensityCap: Int,
        isChinese: Bool
    ) -> String {
        if !isChinese, let payloadSummary, !payloadSummary.isEmpty {
            return payloadSummary
        }

        let volumePercent = Int((volumeMultiplier * 100).rounded())
        if isChinese {
            switch decision {
            case .keep:
                return "按计划训练，使用 RPE \(intensityCap) 作为上限，并根据动作质量做自我调节。"
            case .reduce:
                return "建议将今天训练容量降至 \(volumePercent)%，RPE 控制在 \(intensityCap) 以内；动作质量下降时停止加量。"
            case .swap:
                return "替换高疲劳部位的训练内容，保留约 \(volumePercent)% 的有效刺激，RPE 控制在 \(intensityCap) 以内。"
            case .rest:
                return "今天优先恢复：选择低强度活动、拉伸和睡眠补偿，避免追求训练量。"
            }
        }

        switch decision {
        case .keep:
            return "Keep the planned session with RPE capped at \(intensityCap) and autoregulate by technique quality."
        case .reduce:
            return "Reduce volume to \(volumePercent)% and keep RPE at or below \(intensityCap); stop adding load if technique deteriorates."
        case .swap:
            return "Swap away from highly fatigued areas, keep about \(volumePercent)% of the stimulus, and cap RPE at \(intensityCap)."
        case .rest:
            return "Prioritize recovery today with low-intensity activity, mobility, and sleep support instead of chasing volume."
        }
    }

    private static func localizedEvidenceLine(
        source: String?,
        safetyNotice: String?,
        isChinese: Bool
    ) -> String {
        if isChinese {
            let sourceText = (source?.isEmpty == false) ? "本地身体状态 + 训练决策" : "本地训练决策"
            let safetyText = (safetyNotice?.isEmpty == false) ? "一般健康与训练建议，不构成医疗诊断。" : "一般建议，不构成医疗诊断。"
            return "\(sourceText) · \(safetyText)"
        }
        let sourceText = source?.isEmpty == false ? source! : "Local training decision"
        let safetyText = safetyNotice?.isEmpty == false ? safetyNotice! : "General guidance only; not a medical diagnosis."
        return "\(sourceText) · \(safetyText)"
    }
}

@MainActor
enum DailyOperatingPlanCoordinator {
    @discardableResult
    @MainActor
    static func upsert(
        bodyState: BodyState,
        decision: DailyTrainingDecision,
        brief: PersonalHealthBrief? = nil,
        modelContext: ModelContext,
        calendar: Calendar = .current,
        saveChanges: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> DailyOperatingPlanRecord {
        try DailyOperatingPlanWriteTransaction.run(context: modelContext, saveChanges: saveChanges) { transaction in
            let dayIdentifier = DailyHealthSummaryRecord.dayIdentifier(for: bodyState.date, calendar: calendar)
            var payload = DailyOperatingPlanBuilder.build(
                bodyState: bodyState,
                decision: decision,
                brief: brief,
                language: AppLanguage.stored
            )
            let feedbackAsOf = DecisionFeedbackCalibrator.evidenceCutoff(for: bodyState.date, calendar: calendar)
            payload.feedbackEvidencePolicyVersion = DecisionFeedbackCalibrator.evidencePolicyVersion
            payload.feedbackEvidenceAsOf = feedbackAsOf
            let payloadJSON = Self.json(payload)
            let reasonsJSON = Self.json(decision.reasons)
            let planTitle = payload.primaryAction?.title ?? title(for: decision.decision)
            // 算法打通（批次 C）：计划置信度与今日页 readiness 吃同一份反馈校准
            // （DecisionFeedbackCalibrator，rest↔recover 已归一）。每次 upsert 从
            // kernel 原始置信度重新校准，不会因历史记录累积缩放。
            let feedbackRecords = (try? modelContext.fetch(FetchDescriptor<DailyDecisionFeedbackRecord>())) ?? []
            let storedConfidence = feedbackAsOf.map { asOf in
                DecisionFeedbackCalibrator.calibratedPlanConfidence(
                    base: decision.confidence,
                    decision: decision.decision,
                    records: feedbackRecords,
                    now: asOf,
                    calendar: calendar
                )
            } ?? decision.confidence
            let descriptor = FetchDescriptor<DailyOperatingPlanRecord>(
                predicate: #Predicate<DailyOperatingPlanRecord> { $0.dayIdentifier == dayIdentifier }
            )
            let record: DailyOperatingPlanRecord
            if let existing = try modelContext.fetch(descriptor).first {
                record = existing
                transaction.capture(record)
                record.bodyStateHash = bodyState.hash
                record.generatedAt = Date()
                record.primaryActionType = decision.decision.rawValue
                record.title = planTitle
                record.payloadJSON = payloadJSON
                record.reasonsJSON = reasonsJSON
                record.confidence = storedConfidence
                record.status = "active"
                record.source = decision.source
                record.safetyNotice = decision.safetyNotice
            } else {
                record = DailyOperatingPlanRecord(
                    dayIdentifier: dayIdentifier,
                    bodyStateHash: bodyState.hash,
                    primaryActionType: decision.decision.rawValue,
                    title: planTitle,
                    payloadJSON: payloadJSON,
                    reasonsJSON: reasonsJSON,
                    confidence: storedConfidence,
                    status: "active",
                    source: decision.source,
                    safetyNotice: decision.safetyNotice
                )
                transaction.insert(record)
            }

            let artifactType = AgentArtifactType.dailyPlan.rawValue
            let sourceContextHash = bodyState.hash
            let artifactDescriptor = FetchDescriptor<AgentArtifactRecord>(
                predicate: #Predicate<AgentArtifactRecord> {
                    $0.type == artifactType && $0.sourceContextHash == sourceContextHash
                }
            )
            if let artifact = try modelContext.fetch(artifactDescriptor).first {
                transaction.capture(artifact)
                artifact.title = record.title
                artifact.payloadJSON = payloadJSON
                artifact.confidence = storedConfidence
                artifact.status = "active"
                artifact.source = decision.source
                artifact.safetyNotice = record.safetyNotice
            } else {
                transaction.insert(AgentArtifactRecord(
                    type: AgentArtifactType.dailyPlan.rawValue,
                    title: record.title,
                    payloadJSON: payloadJSON,
                    sourceContextHash: bodyState.hash,
                    confidence: storedConfidence,
                    source: decision.source,
                    safetyNotice: decision.safetyNotice
                ))
            }
            return record
        }
    }

    private static func json<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func title(for decision: DailyTrainingDecisionType) -> String {
        switch decision {
        case .keep: "Keep today's plan"
        case .reduce: "Reduce today's training"
        case .swap: "Swap today's session"
        case .rest: "Recovery day"
        }
    }
}

extension DailyOperatingPlanRecord {
    var operatingPlanPayload: DailyOperatingPlanPayload? {
        guard let payloadData = payloadJSON.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(DailyOperatingPlanPayload.self, from: payloadData)
    }

    var operatingPlanReasons: [String] {
        guard let reasonsData = reasonsJSON.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([String].self, from: reasonsData)) ?? []
    }

    var trainingDecision: DailyTrainingDecision? {
        guard let payload = operatingPlanPayload else {
            return nil
        }
        return DailyTrainingDecision(
            decision: payload.decision,
            targetSessionTitle: payload.targetSessionTitle,
            volumeMultiplier: payload.volumeMultiplier,
            intensityCap: payload.intensityCap,
            reasons: operatingPlanReasons,
            userFacingSummary: payload.summary,
            confidence: confidence,
            source: source ?? "BodyStateKernel + TrainingDecisionKernel",
            safetyNotice: safetyNotice ?? "General wellness guidance only; not a medical diagnosis."
        )
    }
}
