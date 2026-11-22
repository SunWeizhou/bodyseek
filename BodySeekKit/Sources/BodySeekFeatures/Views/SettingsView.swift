import BodySeekAgent
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

                    Toggle(
                        "饮食识别启用 DeepSeek 联网搜索",
                        isOn: Binding(
                            get: { store.config.enableWebSearch },
                            set: { store.send(.webSearchToggled($0)) }
                        )
                    )
                    .accessibilityIdentifier("settings-web-search-toggle")

                    Toggle(
                        "主动洞察（每日最多 2 条）",
                        isOn: Binding(
                            get: { store.preferences.proactiveInsightsEnabled },
                            set: { store.send(.proactiveInsightsToggled($0)) }
                        )
                    )
                    .accessibilityIdentifier("settings-proactive-insights-toggle")

                    Button {
                        store.send(.privacyPayloadSheetPresented(true))
                    } label: {
                        Label("查看最近发往云端 AI 的数据", systemImage: "eye.trianglebadge.exclamationmark")
                    }
                    .foregroundStyle(BevelTheme.ink)
                    .accessibilityIdentifier("settings-privacy-payload-button")
                } header: {
                    Text("AI 智能体引擎（自研 OpenAI 兼容客户端 / Apple 智能）")
                } footer: {
                    Text("填入 DeepSeek 等 OpenAI 兼容接口后可启用云端四态工具调用；留空时，支持 Apple 智能的 iOS 26 设备将自动启用端侧 FoundationModels 智能体。云端 Coach 请求会附带当前对话最近最多 6 条消息及其中的训练提案摘要，可在隐私预览核对。")
                }

                Section("三层长期记忆 (\(store.tieredMemories.isEmpty ? store.memories.count : store.tieredMemories.filter { $0.isActive() }.count))") {
                    if store.tieredMemories.isEmpty && store.memories.isEmpty {
                        Text("暂无已保存的伤病或训练习惯记忆。")
                            .font(.footnote)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    } else if !store.tieredMemories.isEmpty {
                        ForEach(store.tieredMemories.filter { $0.isActive() }) { record in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(record.tier.titleLabel)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(BevelTheme.brand)
                                    if let exp = record.expiresAt {
                                        Text("· 截至 \(exp.formatted(.dateTime.month().day()))")
                                            .font(.caption2)
                                            .foregroundStyle(BevelTheme.inkSecondary)
                                    }
                                }
                                Text(record.content)
                                    .font(.footnote)
                            }
                            .swipeActions {
                                Button("删除", role: .destructive) {
                                    store.send(.deleteMemoryTapped(record.id))
                                }
                            }
                        }
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
            .sheet(
                isPresented: Binding(
                    get: { store.showPrivacyPayloadSheet },
                    set: { store.send(.privacyPayloadSheetPresented($0)) }
                )
            ) {
                privacyPayloadSheet
            }
        }
    }

    private var privacyPayloadSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("API Key 仅保留在 Keychain 与 HTTP Authorization 请求头，不会写入外发对话 JSON。以下为最近一次发往云端模型的完整请求脱敏快照：")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)

                    if let snap = store.lastOutboundPayload {
                        BevelCard(padding: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Endpoint: \(snap.endpointURL)")
                                    .font(.caption2.monospaced())
                                Text("Model: \(snap.modelName) · Messages: \(snap.messageCount)")
                                    .font(.caption2.monospaced())
                                Text("Tools: \(snap.toolNames.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundStyle(BevelTheme.brand)
                                Divider()
                                Text(snap.redactedRequestJSON)
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    } else {
                        BevelCard(padding: 14) {
                            Text("本次应用会话尚未向云端 AI 发送任何数据。预览模式或端侧 Apple Intelligence 模式下不会外发健康 JSON。")
                                .font(.footnote)
                                .foregroundStyle(BevelTheme.inkSecondary)
                        }
                    }
                }
                .padding(16)
            }
            .background(BevelTheme.canvas.ignoresSafeArea())
            .navigationTitle("外发云端 AI 数据预览")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button("关闭") {
                        store.send(.privacyPayloadSheetPresented(false))
                    }
                    .accessibilityIdentifier("settings-privacy-payload-close")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-privacy-payload-sheet")
    }
}
