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
        public var messages: [CoachMessage] = []
        public var draftText: String = ""
        public var isSending: Bool = false
        public var showMemorySheet: Bool = false
        public var dismissedProposalMessageIDs: Set<UUID> = []
        public var lastError: String?

        public init(
            snapshot: BodySeekDashboardSnapshot,
            sessions: [LoggedWorkoutSession] = [],
            templates: [WorkoutTemplate] = ExerciseCatalog.defaultTemplates,
            memories: [AthleteMemoryItem] = [],
            messages: [CoachMessage]? = nil
        ) {
            self.snapshot = snapshot
            self.sessions = sessions
            self.templates = templates
            self.memories = memories
            self.messages = messages ?? [Self.makeWelcomeMessage(snapshot: snapshot)]
        }

        public static func makeWelcomeMessage(snapshot: BodySeekDashboardSnapshot) -> CoachMessage {
            CoachMessage(
                role: .assistant,
                text: "已同步今日生理指标与训练基线（\(snapshot.today.factualSummary)）。你可以让我解读恢复状态、记住伤病与训练习惯，或直接帮你排出今天可开练的力量处方。",
                engineLabel: "BodySeek 智能体",
                evidenceMetric: .recovery
            )
        }

        public var quickPrompts: [String] {
            [
                "根据我的恢复和 ACWR，帮我排一份今天能练的减量上肢课表",
                "记住我右膝前侧轻微不适，最近两周减少大重量深蹲",
                "昨晚的睡眠分期和心率恢复说明了什么？",
            ]
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
        case aiReplyReceived(CoachMessage, savedMemories: [AthleteMemoryItem], storeError: String?)
        case newConversationTapped
        case applyProposalTapped(messageID: UUID, proposal: WorkoutProposal, startImmediately: Bool)
        case dismissProposalTapped(UUID)
        case memorySheetPresented(Bool)
        case deleteMemoryTapped(UUID)
        case storeOperationFailed(String)
        case openSettingsTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case applyWorkoutProposal(WorkoutProposal, startImmediately: Bool)
            case memoriesUpdated([AthleteMemoryItem])
            case openSettings
        }
    }

    @Dependency(\.coachAIClient) var coachAIClient
    @Dependency(\.fitnessStoreClient) var fitnessStoreClient
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
                guard !query.isEmpty, !state.isSending else { return .none }
                state.draftText = ""
                return enqueueQuestion(query, state: &state)

            case let .quickPromptTapped(prompt):
                guard !state.isSending else { return .none }
                return enqueueQuestion(prompt, state: &state)

            case let .externalPromptSubmitted(prompt):
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, !state.isSending else { return .none }
                return enqueueQuestion(trimmed, state: &state)

            case let .aiReplyReceived(reply, savedMemories, storeError):
                state.isSending = false
                state.lastError = storeError
                state.messages.append(reply)
                if !savedMemories.isEmpty {
                    for mem in savedMemories {
                        if let idx = state.memories.firstIndex(where: { $0.id == mem.id }) {
                            state.memories[idx] = mem
                        } else {
                            state.memories.insert(mem, at: 0)
                        }
                    }
                    return .send(.delegate(.memoriesUpdated(state.memories)))
                }
                return .none

            case .newConversationTapped:
                state.draftText = ""
                state.isSending = false
                state.lastError = nil
                state.dismissedProposalMessageIDs.removeAll()
                state.messages = [State.makeWelcomeMessage(snapshot: state.snapshot)]
                return .run { send in
                    do {
                        try await fitnessStoreClient.clearMessages()
                    } catch {
                        await send(.storeOperationFailed("清空对话历史失败：\(error.localizedDescription)"))
                    }
                }

            case let .applyProposalTapped(messageID, proposal, startImmediately):
                state.dismissedProposalMessageIDs.insert(messageID)
                return .send(.delegate(.applyWorkoutProposal(proposal, startImmediately: startImmediately)))

            case let .dismissProposalTapped(messageID):
                state.dismissedProposalMessageIDs.insert(messageID)
                return .none

            case let .memorySheetPresented(presented):
                state.showMemorySheet = presented
                return .none

            case let .deleteMemoryTapped(id):
                state.memories.removeAll { $0.id == id }
                let updated = state.memories
                return .merge(
                    .send(.delegate(.memoriesUpdated(updated))),
                    .run { send in
                        do {
                            try await fitnessStoreClient.deleteMemory(id)
                        } catch {
                            await send(.storeOperationFailed("删除长期记忆失败：\(error.localizedDescription)"))
                        }
                    }
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

    private func enqueueQuestion(_ question: String, state: inout State) -> Effect<Action> {
        let userMsg = CoachMessage(id: uuid(), role: .user, text: question, timestamp: now)
        state.messages.append(userMsg)
        state.isSending = true
        state.lastError = nil

        let context = AgentExecutionContext(
            snapshot: state.snapshot,
            sessions: state.sessions,
            templates: state.templates,
            memories: state.memories
        )
        return .run { send in
            let reply = await coachAIClient.reply(question: question, context: context)
            let savedMemories = await context.effects.savedMemories
            var storeError: String?
            do {
                try await fitnessStoreClient.appendMessage(userMsg)
                try await fitnessStoreClient.appendMessage(reply)
                for item in savedMemories {
                    try await fitnessStoreClient.saveMemory(item)
                }
            } catch {
                storeError = "本地对话或记忆持久化失败：\(error.localizedDescription)"
            }
            await send(.aiReplyReceived(reply, savedMemories: savedMemories, storeError: storeError))
        }
    }
}
