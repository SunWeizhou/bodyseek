import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct SettingsView: View {
    @Bindable var store: StoreOf<SettingsFeature>

    public init(store: StoreOf<SettingsFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("数据源与权限") {
                    LabeledContent("当前数据源", value: store.snapshot.sourceLabel)
                    LabeledContent("健康授权状态", value: store.snapshot.isAuthorized ? "已请求授权" : "未授权")

                    Button("重新请求 Apple 健康授权") {
                        store.send(.authorizeHealthTapped)
                    }
                    .foregroundStyle(BevelTheme.brand)
                }

                Section("睡眠与运动习惯") {
                    Stepper(
                        value: Binding(
                            get: { store.preferences.sleepGoalMinutes },
                            set: { store.send(.sleepGoalChanged($0)) }
                        ),
                        in: 360...600,
                        step: 15
                    ) {
                        let hours = Double(store.preferences.sleepGoalMinutes) / 60.0
                        LabeledContent("每日睡眠目标", value: String(format: "%.2f 小时", hours))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("持拍手 / 惯用手（羽毛球等单侧归因）")
                            .font(.subheadline)
                        Picker(
                            "持拍手",
                            selection: Binding(
                                get: { store.preferences.dominantHand },
                                set: { store.send(.dominantHandChanged($0)) }
                            )
                        ) {
                            Text("右手").tag(DominantHand.right)
                            Text("左手").tag(DominantHand.left)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settings-dominant-hand-picker")
                    }
                }

                Section {
                    TextField(
                        "API Endpoint",
                        text: Binding(
                            get: { store.config.endpointURL },
                            set: { store.send(.endpointChanged($0)) }
                        )
                    )
                    .bodyseekNoAutocapitalization()

                    TextField(
                        "模型名称",
                        text: Binding(
                            get: { store.config.modelName },
                            set: { store.send(.modelNameChanged($0)) }
                        )
                    )
                    .bodyseekNoAutocapitalization()

                    SecureField(
                        "DeepSeek / OpenAI API Key",
                        text: Binding(
                            get: { store.apiKey },
                            set: { store.send(.apiKeyChanged($0)) }
                        )
                    )
                    .bodyseekNoAutocapitalization()

                    Button {
                        store.send(.saveAIConfigTapped)
                    } label: {
                        HStack {
                            Text(store.isTestingConnection ? "正在测试连接..." : "保存并测试连接")
                            if store.isTestingConnection {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(store.isTestingConnection)
                    .foregroundStyle(BevelTheme.brand)
                } header: {
                    Text("AI 智能体引擎（SpeziLLM / Apple Intelligence）")
                } footer: {
                    Text("填入 DeepSeek 等 OpenAI 兼容接口后可启用云端工具调用；留空时，支持 Apple 智能的 iOS 26 设备将自动启用端侧 FoundationModels 智能体。")
                }

                Section("智能体长期记忆 (\(store.memories.count))") {
                    if store.memories.isEmpty {
                        Text("暂无已保存的伤病或训练习惯记忆。")
                            .font(.footnote)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    } else {
                        ForEach(store.memories) { mem in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mem.category.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BevelTheme.brand)
                                Text(mem.content)
                                    .font(.footnote)
                            }
                            .swipeActions {
                                Button("删除", role: .destructive) {
                                    store.send(.deleteMemoryTapped(mem.id))
                                }
                            }
                        }
                    }
                }

                Section("开源底座与存储重置") {
                    Button("重置训练日志、记忆与设置", role: .destructive) {
                        store.send(.resetAllDataTapped)
                    }
                    Text("开源生态：SpeziHealthKit · TCA · GRDB.swift · Swift Charts · MuscleMap · free-exercise-db。")
                        .font(.footnote)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                if let msg = store.statusMessage {
                    Section {
                        Text(msg)
                            .font(.footnote)
                            .foregroundStyle(BevelTheme.brand)
                    }
                }
            }
            .navigationTitle("设置")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button("完成") {
                        store.send(.closeTapped)
                    }
                    .accessibilityIdentifier("settings-done-button")
                }
            }
            .onAppear {
                store.send(.onAppear)
            }
        }
    }
}
