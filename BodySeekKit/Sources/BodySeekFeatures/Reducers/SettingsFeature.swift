import BodySeekAgent
import BodySeekCore
import BodySeekHealth
import ComposableArchitecture
import Foundation

@Reducer
public struct SettingsFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var snapshot: BodySeekDashboardSnapshot
        public var preferences: AppPreferencesState
        public var memories: [AthleteMemoryItem]
        public var apiKey: String = ""
        public var config: CoachAIConfig = CoachAIConfig()
        public var isTestingConnection: Bool = false
        public var statusMessage: String?

        public init(
            snapshot: BodySeekDashboardSnapshot,
            preferences: AppPreferencesState,
            memories: [AthleteMemoryItem] = []
        ) {
            self.snapshot = snapshot
            self.preferences = preferences
            self.memories = memories
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case sleepGoalChanged(Int)
        case dominantHandChanged(DominantHand)
        case apiKeyChanged(String)
        case endpointChanged(String)
        case modelNameChanged(String)
        case saveAIConfigTapped
        case testConnectionFinished(String?)
        case authorizeHealthTapped
        case deleteMemoryTapped(UUID)
        case memoryDeleteFailed(String)
        case resetAllDataTapped
        case resetFinished
        case resetFailed(String)
        case closeTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case authorizationRequested
            case preferencesUpdated(AppPreferencesState)
            case memoriesUpdated([AthleteMemoryItem])
            case allDataReset
            case dismissed
        }
    }

    @Dependency(\.preferencesClient) var preferencesClient
    @Dependency(\.fitnessStoreClient) var fitnessStoreClient
    @Dependency(\.coachAIClient) var coachAIClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                do {
                    state.apiKey = try coachAIClient.loadAPIKey()
                } catch {
                    state.apiKey = ""
                    state.statusMessage = "读取 Keychain 凭据失败：\(error.localizedDescription)"
                }
                state.config = coachAIClient.loadConfig()
                return .none

            case let .sleepGoalChanged(minutes):
                state.preferences.sleepGoalMinutes = min(600, max(360, minutes))
                do {
                    try preferencesClient.save(state.preferences)
                    return .send(.delegate(.preferencesUpdated(state.preferences)))
                } catch {
                    state.statusMessage = "保存睡眠目标失败：\(error.localizedDescription)"
                    return .none
                }

            case let .dominantHandChanged(hand):
                state.preferences.dominantHand = hand
                do {
                    try preferencesClient.save(state.preferences)
                    return .send(.delegate(.preferencesUpdated(state.preferences)))
                } catch {
                    state.statusMessage = "保存持拍手设置失败：\(error.localizedDescription)"
                    return .none
                }

            case let .apiKeyChanged(key):
                state.apiKey = key
                return .none

            case let .endpointChanged(url):
                state.config.endpointURL = url
                return .none

            case let .modelNameChanged(model):
                state.config.modelName = model
                return .none

            case .saveAIConfigTapped:
                let normalizedConfig = CoachAIConfig(
                    endpointURL: state.config.endpointURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    modelName: state.config.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                state.config = normalizedConfig
                do {
                    try coachAIClient.saveAPIKey(state.apiKey)
                } catch {
                    state.statusMessage = "保存 API Key 到 Keychain 失败：\(error.localizedDescription)"
                    return .none
                }
                coachAIClient.saveConfig(normalizedConfig)
                if state.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    state.statusMessage = "已清空 Keychain 中的云端 Key，将优先尝试设备端侧 Apple 智能"
                    return .none
                }
                state.isTestingConnection = true
                state.statusMessage = "正在测试连接 \(normalizedConfig.modelName)..."
                let key = state.apiKey
                return .run { send in
                    let errorText = await coachAIClient.testConnection(key, normalizedConfig)
                    await send(.testConnectionFinished(errorText))
                }

            case let .testConnectionFinished(errorText):
                state.isTestingConnection = false
                if let errorText {
                    state.statusMessage = "已保存但连接失败：\(errorText)"
                } else {
                    state.statusMessage = "连接成功！已启用 \(state.config.modelName)"
                }
                return .none

            case .authorizeHealthTapped:
                return .send(.delegate(.authorizationRequested))

            case let .deleteMemoryTapped(id):
                state.memories.removeAll { $0.id == id }
                let updated = state.memories
                return .merge(
                    .send(.delegate(.memoriesUpdated(updated))),
                    .run { send in
                        do {
                            try await fitnessStoreClient.deleteMemory(id)
                        } catch {
                            await send(.memoryDeleteFailed(error.localizedDescription))
                        }
                    }
                )

            case let .memoryDeleteFailed(reason):
                state.statusMessage = "删除记忆失败：\(reason)"
                return .none

            case .resetAllDataTapped:
                return .run { send in
                    do {
                        try preferencesClient.reset()
                        try await fitnessStoreClient.resetAll()
                        await send(.resetFinished)
                    } catch {
                        await send(.resetFailed(error.localizedDescription))
                    }
                }

            case .resetFinished:
                state.preferences = AppPreferencesState()
                state.memories = []
                state.statusMessage = "已重置训练记录、AI 长期记忆与偏好设置"
                return .send(.delegate(.allDataReset))

            case let .resetFailed(reason):
                state.statusMessage = "重置失败：\(reason)"
                return .none

            case .closeTapped:
                return .send(.delegate(.dismissed))

            case .delegate:
                return .none
            }
        }
    }
}
