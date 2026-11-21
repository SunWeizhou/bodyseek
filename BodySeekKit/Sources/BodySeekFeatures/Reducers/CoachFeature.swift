import BodySeekAgent
import BodySeekCore
import BodySeekHealth
import ComposableArchitecture
import Foundation

@Reducer
public struct CoachFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var snapshot: BodySeekDashboardSnapshot
        public var sessions: [LoggedWorkoutSession]
        public var templates: [WorkoutTemplate]
        public var memories: [AthleteMemoryItem]
        public var tieredMemories: [TieredMemoryRecord]
        public var deletedWorkoutUUIDs: Set<String> = []
        public var storedWorkouts: [StoredWorkoutRecord] = []
        public var annotationsByWorkoutUUID: [String: WorkoutAnnotationRecord] = [:]
        public var muscleLoads: [WorkoutMuscleLoadRecord] = []
        public var patternFindings: [PatternFindingRecord] = []
        public var todayNutritionLog: DailyNutritionLog?
        public var nutritionTargetPlan: NutritionTargetPlan?
        public var nutritionLogs: [DailyNutritionLog] = []
        public var checkIns: [DailyCheckIn] = []
        public var dominantHand: DominantHand = .right
        public var sleepGoalMinutes: Int = 450

        public var messages: [CoachMessage] = []
        public var draftText: String = ""
        public var isSending: Bool = false
        public var isResettingConversation: Bool = false
        public var showMemorySheet: Bool = false
        public var dismissedProposalMessageIDs: Set<UUID> = []
        public var dismissedMemoryProposalMessageIDs: Set<UUID> = []
        public var dismissedAnnotationProposalMessageIDs: Set<UUID> = []
        public var confirmedMemoryProposalMessageIDs: Set<UUID> = []
        public var confirmedAnnotationProposalMessageIDs: Set<UUID> = []
        public var annotationCandidateSelections: [UUID: CoachWorkoutAnnotationProposal] = [:]
        public var undoneAnnotationMessageIDs: Set<UUID> = []
        var pendingAnnotationDecisionMessageIDs: Set<UUID> = []
        var pendingAnnotationUndoMessageIDs: Set<UUID> = []
        public var lastError: String?

        public init(
            snapshot: BodySeekDashboardSnapshot,
            sessions: [LoggedWorkoutSession] = [],
            templates: [WorkoutTemplate] = ExerciseCatalog.defaultTemplates,
            memories: [AthleteMemoryItem] = [],
            tieredMemories: [TieredMemoryRecord] = [],
            messages: [CoachMessage]? = nil
        ) {
            self.snapshot = snapshot
            self.sessions = sessions
            self.templates = templates
            self.memories = memories
            self.tieredMemories = tieredMemories.isEmpty && !memories.isEmpty
                ? MemoryContextSelector.bridgeFromLegacy(memories)
                : tieredMemories
            self.messages = messages ?? [Self.makeWelcomeMessage()]
        }

        public static func makeWelcomeMessage() -> CoachMessage {
            CoachMessage(
                role: .assistant,
                text: welcomeText
            )
        }

        private static let welcomeText = "今天想了解什么？可以问我睡眠、恢复或训练。"

        public var isAtWelcome: Bool {
            messages.isEmpty || (messages.count == 1 && messages.first?.role == .assistant
                && messages.first?.text == Self.welcomeText)
        }

        public var quickPrompts: [(title: String, question: String)] {
            [
                ("看恢复", "我今天的恢复和平时相比怎么样？"),
                ("看睡眠", "昨晚睡得怎么样？和我平时比有什么不同？"),
                ("排训练", "结合我今天的恢复和近一周训练，帮我安排今天的训练。"),
                ("看饮食", "根据我今天已记录的饮食，汇总热量、蛋白质和待补数据。"),
            ]
        }

        public func activeTieredMemories(at now: Date = Date()) -> [TieredMemoryRecord] {
            MemoryContextSelector.activeMemories(from: tieredMemories, now: now)
        }

        public func activeTieredMemories(for tier: MemoryTier, at now: Date = Date()) -> [TieredMemoryRecord] {
            activeTieredMemories(at: now).filter { $0.tier == tier }
        }

        public func sparklinePoints(for kind: MetricKind) -> [(date: Date, value: Double?)] {
            snapshot.historyDays.suffix(14).map { day in
                switch kind {
                case .recovery: (day.date, day.raw.hrvMs)
                case .sleep: (day.date, day.raw.sleepAsleepMinutes.map { Double($0) / 60.0 })
                case .strain: (day.date, day.raw.activeEnergyKcal)
                case .stress: (day.date, day.stress.value.map(Double.init))
                case .energy: (day.date, day.energy.value.map(Double.init))
                }
            }
        }
    }

    public enum Action: Equatable, Sendable {
        case draftChanged(String)
        case sendTapped
        case quickPromptTapped(String)
        case externalPromptSubmitted(String)
        case aiReplyReceived(CoachMessage, storeError: String?)
        case newConversationTapped
        case conversationResetFinished(error: String?)
        case applyProposalTapped(messageID: UUID, proposal: WorkoutProposal, startImmediately: Bool)
        case dismissProposalTapped(UUID)
        case confirmMemoryProposalTapped(messageID: UUID, memory: TieredMemoryRecord)
        case memoryProposalCommitted(messageID: UUID, memory: TieredMemoryRecord)
        case dismissMemoryProposalTapped(UUID)
        case confirmAnnotationProposalTapped(messageID: UUID, proposal: CoachWorkoutAnnotationProposal)
        case selectAnnotationCandidate(messageID: UUID, candidate: CoachWorkoutAnnotationCandidate)
        case annotationProposalCommitted(messageID: UUID, proposal: CoachWorkoutAnnotationProposal)
        case dismissAnnotationProposalTapped(UUID)
        case annotationProposalRejected(UUID)
        case annotationDecisionFailed(UUID, String)
        case undoAnnotationTapped(messageID: UUID)
        case annotationUndone(messageID: UUID)
        case annotationUndoFailed(messageID: UUID, String)
        case memorySheetPresented(Bool)
        case deleteMemoryTapped(UUID)
        case retireTieredMemoryTapped(UUID)
        case confirmCandidatePatternTapped(PatternFindingRecord)
        case candidatePatternConfirmed(PatternFindingRecord, TieredMemoryRecord)
        case storeOperationFailed(String)
        case openSettingsTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case applyWorkoutProposal(WorkoutProposal, startImmediately: Bool)
            case memoriesUpdated([AthleteMemoryItem])
            case tieredMemoriesUpdated([TieredMemoryRecord])
            case patternFindingsUpdated([PatternFindingRecord])
            case workoutAnnotationCommitted
            case workoutAnnotationUndone
            case openSettings
        }
    }

    @Dependency(\.coachAIClient) var coachAIClient
    @Dependency(\.fitnessStoreClient) var fitnessStoreClient
    @Dependency(\.bodySeekStoreClient) var bodySeekStoreClient
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .draftChanged(text):
                state.draftText = text
                return .none

            case .sendTapped:
                let query = state.draftText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !query.isEmpty, !state.isSending, !state.isResettingConversation else { return .none }
                state.draftText = ""
                return enqueueQuestion(query, state: &state)

            case let .quickPromptTapped(prompt):
                guard !state.isSending, !state.isResettingConversation else { return .none }
                return enqueueQuestion(prompt, state: &state)

            case let .externalPromptSubmitted(prompt):
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !state.isSending, !state.isResettingConversation else { return .none }
                return enqueueQuestion(trimmed, state: &state)

            case let .aiReplyReceived(reply, storeError):
                state.isSending = false
                state.lastError = storeError
                state.messages.append(reply)
                return .none

            case .newConversationTapped:
                guard !state.isSending, !state.isResettingConversation, state.pendingAnnotationDecisionMessageIDs.isEmpty else { return .none }
                state.isResettingConversation = true
                return .run { send in
                    do {
                        try await fitnessStoreClient.clearMessages()
                        await send(.conversationResetFinished(error: nil))
                    } catch {
                        await send(.conversationResetFinished(error: "清空对话历史失败：\(error.localizedDescription)"))
                    }
                }

            case let .conversationResetFinished(error):
                state.isResettingConversation = false
                state.lastError = error
                guard error == nil else { return .none }
                state.draftText = ""
                state.dismissedProposalMessageIDs.removeAll()
                state.dismissedMemoryProposalMessageIDs.removeAll()
                state.dismissedAnnotationProposalMessageIDs.removeAll()
                state.confirmedMemoryProposalMessageIDs.removeAll()
                state.confirmedAnnotationProposalMessageIDs.removeAll()
                state.annotationCandidateSelections.removeAll()
                state.undoneAnnotationMessageIDs.removeAll()
                state.messages = [State.makeWelcomeMessage()]
                return .none

            case let .applyProposalTapped(messageID, proposal, startImmediately):
                state.dismissedProposalMessageIDs.insert(messageID)
                let dayKey = state.snapshot.today.dayKey
                return .merge(
                    .send(.delegate(.applyWorkoutProposal(proposal, startImmediately: startImmediately))),
                    .run { send in
                        do {
                            let payloadData = try JSONEncoder().encode(["title": proposal.template.title, "focus": proposal.template.focusTag])
                            let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"
                            let item = PlanItemRecord(
                                dayKey: dayKey,
                                kind: .trainingFocus,
                                payloadJSON: payloadJSON,
                                state: .adopted,
                                origin: .agent
                            )
                            let auditProposal = try ActionProposal(
                                kind: .adjustPlan,
                                origin: .agent,
                                encodablePayload: AdjustPlanPayload(item: item),
                                rationale: "用户采纳 AI 训练处方：\(proposal.template.title)"
                            )
                            _ = try await bodySeekStoreClient.executeProposal(auditProposal)
                        } catch {
                            await send(.storeOperationFailed("记录训练处方审计失败：\(error.localizedDescription)"))
                        }
                    }
                )

            case let .dismissProposalTapped(messageID):
                state.dismissedProposalMessageIDs.insert(messageID)
                return .none

            case let .confirmMemoryProposalTapped(messageID, memory):
                return .run { send in
                    do {
                        let proposal = try ActionProposal(
                            kind: .commitMemory,
                            origin: .agent,
                            encodablePayload: CommitMemoryPayload(memory: memory),
                            rationale: "用户确认智能体提出的[\(memory.tier.titleLabel)]记忆提案"
                        )
                        _ = try await bodySeekStoreClient.executeProposal(proposal)
                        await send(.memoryProposalCommitted(messageID: messageID, memory: memory))
                    } catch {
                        await send(.storeOperationFailed("写入确认记忆失败：\(error.localizedDescription)"))
                    }
                }

            case let .memoryProposalCommitted(messageID, memory):
                state.confirmedMemoryProposalMessageIDs.insert(messageID)
                if let idx = state.tieredMemories.firstIndex(where: { $0.id == memory.id }) {
                    state.tieredMemories[idx] = memory
                } else {
                    state.tieredMemories.insert(memory, at: 0)
                }
                let legacyItem = AthleteMemoryItem(
                    id: memory.id,
                    category: memory.tier == .activeConstraint ? .injury : .preference,
                    content: memory.content,
                    updatedAt: memory.confirmedAt ?? now
                )
                if let idx = state.memories.firstIndex(where: { $0.id == legacyItem.id }) {
                    state.memories[idx] = legacyItem
                } else {
                    state.memories.insert(legacyItem, at: 0)
                }
                let updatedTiered = state.tieredMemories
                let updatedLegacy = state.memories
                return .merge(
                    .send(.delegate(.tieredMemoriesUpdated(updatedTiered))),
                    .send(.delegate(.memoriesUpdated(updatedLegacy)))
                )

            case let .dismissMemoryProposalTapped(messageID):
                state.dismissedMemoryProposalMessageIDs.insert(messageID)
                return .none

            case let .confirmAnnotationProposalTapped(messageID, proposal):
                return decideAnnotation(messageID: messageID, proposal: proposal, decision: .applied, state: &state)

            case let .selectAnnotationCandidate(messageID, candidate):
                state.annotationCandidateSelections[messageID] = candidate.proposal
                return .none

            case let .undoAnnotationTapped(messageID):
                let message = state.messages.first(where: { $0.id == messageID })
                let committed = message?.annotationDecision == .applied
                    || state.confirmedAnnotationProposalMessageIDs.contains(messageID)
                guard !state.pendingAnnotationUndoMessageIDs.contains(messageID),
                      !state.undoneAnnotationMessageIDs.contains(messageID),
                      committed
                else { return .none }
                state.pendingAnnotationUndoMessageIDs.insert(messageID)
                return .run { send in
                    do {
                        _ = try await bodySeekStoreClient.undoWorkoutAnnotation(messageID)
                        await send(.annotationUndone(messageID: messageID))
                    } catch {
                        await send(.annotationUndoFailed(messageID: messageID, "撤销训练标注失败：\(error.localizedDescription)"))
                    }
                }

            case let .annotationUndone(messageID):
                state.pendingAnnotationUndoMessageIDs.remove(messageID)
                state.undoneAnnotationMessageIDs.insert(messageID)
                state.confirmedAnnotationProposalMessageIDs.remove(messageID)
                state.annotationCandidateSelections[messageID] = nil
                return .send(.delegate(.workoutAnnotationUndone))

            case let .annotationUndoFailed(messageID, message):
                state.pendingAnnotationUndoMessageIDs.remove(messageID)
                state.lastError = message
                return .none

            case let .annotationProposalCommitted(messageID, _):
                state.pendingAnnotationDecisionMessageIDs.remove(messageID)
                state.confirmedAnnotationProposalMessageIDs.insert(messageID)
                state.undoneAnnotationMessageIDs.remove(messageID)
                return .send(.delegate(.workoutAnnotationCommitted))

            case let .dismissAnnotationProposalTapped(messageID):
                let proposal = state.messages.first(where: { $0.id == messageID })?.workoutAnnotationProposal
                    ?? state.annotationCandidateSelections[messageID]
                guard let proposal else { return .none }
                state.annotationCandidateSelections[messageID] = nil
                return decideAnnotation(messageID: messageID, proposal: proposal, decision: .rejected, state: &state)

            case let .annotationProposalRejected(messageID):
                state.pendingAnnotationDecisionMessageIDs.remove(messageID)
                state.dismissedAnnotationProposalMessageIDs.insert(messageID)
                state.annotationCandidateSelections[messageID] = nil
                return .none

            case let .annotationDecisionFailed(messageID, message):
                state.pendingAnnotationDecisionMessageIDs.remove(messageID)
                state.lastError = message
                return .none

            case let .memorySheetPresented(presented):
                state.showMemorySheet = presented
                return .none

            case let .deleteMemoryTapped(id):
                state.memories.removeAll { $0.id == id }
                state.tieredMemories.removeAll { $0.id == id }
                let updatedLegacy = state.memories
                let updatedTiered = state.tieredMemories
                return .merge(
                    .send(.delegate(.memoriesUpdated(updatedLegacy))),
                    .send(.delegate(.tieredMemoriesUpdated(updatedTiered))),
                    .run { send in
                        do {
                            try await fitnessStoreClient.deleteMemory(id)
                        } catch {
                            await send(.storeOperationFailed("删除长期记忆失败：\(error.localizedDescription)"))
                        }
                    }
                )

            case let .retireTieredMemoryTapped(id):
                if let idx = state.tieredMemories.firstIndex(where: { $0.id == id }) {
                    state.tieredMemories[idx].retiredAt = now
                }
                state.memories.removeAll { $0.id == id }
                let updatedTiered = state.tieredMemories
                let updatedLegacy = state.memories
                let retiredAt = now
                return .merge(
                    .send(.delegate(.tieredMemoriesUpdated(updatedTiered))),
                    .send(.delegate(.memoriesUpdated(updatedLegacy))),
                    .run { send in
                        do {
                            let proposal = try ActionProposal(
                                kind: .retireMemory,
                                origin: .user,
                                encodablePayload: RetireMemoryPayload(memoryID: id, retiredAt: retiredAt),
                                rationale: "用户在记忆管理页停用记忆"
                            )
                            _ = try await bodySeekStoreClient.executeProposal(proposal)
                        } catch {
                            await send(.storeOperationFailed("停用记忆失败：\(error.localizedDescription)"))
                        }
                    }
                )

            case let .confirmCandidatePatternTapped(finding):
                var updatedFinding = finding
                updatedFinding.status = .confirmed
                let findingToSave = updatedFinding
                let mem = TieredMemoryRecord(
                    tier: .verifiedPattern,
                    content: finding.statement,
                    scopeJSON: "{\"pattern_id\":\"\(finding.id.uuidString)\"}",
                    confidence: 1.0,
                    expiresAt: nil,
                    confirmedAt: now,
                    retiredAt: nil
                )
                return .run { send in
                    do {
                        try await bodySeekStoreClient.savePatternFinding(findingToSave)
                        let proposal = try ActionProposal(
                            kind: .commitMemory,
                            origin: .user,
                            encodablePayload: CommitMemoryPayload(memory: mem),
                            rationale: "用户确认统计规律并晋升为 Verified Pattern"
                        )
                        _ = try await bodySeekStoreClient.executeProposal(proposal)
                        await send(.candidatePatternConfirmed(findingToSave, mem))
                    } catch {
                        await send(.storeOperationFailed("确认个人规律失败：\(error.localizedDescription)"))
                    }
                }

            case let .candidatePatternConfirmed(finding, mem):
                if let idx = state.patternFindings.firstIndex(where: { $0.id == finding.id }) {
                    state.patternFindings[idx] = finding
                }
                state.tieredMemories.insert(mem, at: 0)
                let findings = state.patternFindings
                let tiered = state.tieredMemories
                return .merge(
                    .send(.delegate(.patternFindingsUpdated(findings))),
                    .send(.delegate(.tieredMemoriesUpdated(tiered)))
                )

            case let .storeOperationFailed(message):
                state.lastError = message
                return .none

            case .openSettingsTapped:
                return .send(.delegate(.openSettings))

            case .delegate:
                return .none
            }
        }
    }

    private func decideAnnotation(
        messageID: UUID, proposal: CoachWorkoutAnnotationProposal, decision: ActionAuditDecision, state: inout State
    ) -> Effect<Action> {
        guard !state.isResettingConversation,
              !state.confirmedAnnotationProposalMessageIDs.contains(messageID),
              !state.dismissedAnnotationProposalMessageIDs.contains(messageID),
              state.messages.first(where: { $0.id == messageID })?.annotationDecision == nil,
              state.pendingAnnotationDecisionMessageIDs.insert(messageID).inserted
        else { return .none }
        return .run { send in
            do {
                let action = try ActionProposal(
                    id: messageID, kind: .annotateWorkout, origin: .agent,
                    encodablePayload: AnnotateWorkoutPayload(
                        workoutUUID: proposal.workoutUUID, rawText: proposal.rawText,
                        parserVersion: proposal.proposal.parserVersion, muscleLoads: proposal.muscleLoads,
                        coachAnnotationDecision: decision,
                        expectedRecordState: proposal.recordState
                    )
                )
                let audit = try await bodySeekStoreClient.executeProposal(action)
                if audit.decision == .rejected {
                    await send(.annotationProposalRejected(messageID))
                } else {
                    await send(.annotationProposalCommitted(messageID: messageID, proposal: proposal))
                }
            } catch {
                await send(.annotationDecisionFailed(messageID, "保存训练复盘决定失败：\(error.localizedDescription)"))
            }
        }
    }

    private func enqueueQuestion(_ question: String, state: inout State) -> Effect<Action> {
        let userMsg = CoachMessage(id: uuid(), role: .user, text: question, timestamp: now)
        if state.isAtWelcome { state.messages = [] }
        state.messages.append(userMsg)
        state.isSending = true
        state.lastError = nil

        let context = AgentExecutionContext(
            snapshot: state.snapshot,
            sessions: state.sessions,
            templates: state.templates,
            memories: state.memories,
            tieredMemories: state.tieredMemories,
            storedWorkouts: state.storedWorkouts,
            deletedWorkoutUUIDs: state.deletedWorkoutUUIDs,
            annotationsByWorkoutUUID: state.annotationsByWorkoutUUID,
            muscleLoads: state.muscleLoads,
            patternFindings: state.patternFindings,
            todayNutritionLog: state.todayNutritionLog,
            nutritionTargetPlan: state.nutritionTargetPlan,
            nutritionLogs: state.nutritionLogs,
            checkIns: state.checkIns,
            dominantHand: state.dominantHand,
            sleepGoalMinutes: state.sleepGoalMinutes,
            asOf: userMsg.timestamp,
            conversationHistory: Array(state.messages.dropLast().suffix(6))
        )
        return .run { send in
            var storeError: String?
            do {
                try await fitnessStoreClient.appendMessage(userMsg)
            } catch {
                storeError = "本地对话持久化失败：\(error.localizedDescription)"
            }
            let reply = await coachAIClient.reply(question: question, context: context)
            if storeError == nil {
                do {
                    try await fitnessStoreClient.appendMessage(reply)
                } catch {
                    storeError = "本地对话持久化失败：\(error.localizedDescription)"
                }
            }
            await send(.aiReplyReceived(reply, storeError: storeError))
        }
    }
}
