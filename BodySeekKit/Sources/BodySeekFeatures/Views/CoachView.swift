import BodySeekCore
import ComposableArchitecture
import SwiftUI

public struct CoachView: View {
    @Bindable var store: StoreOf<CoachFeature>
    @FocusState private var isComposerFocused: Bool

    public init(store: StoreOf<CoachFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            memoryStripBar

            if let err = store.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(BevelTheme.dangerColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(store.messages) { msg in
                            messageRow(msg)
                                .id(msg.id)
                        }

                        if store.isSending {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("智能体正在调用健康与训练工具…")
                                    .font(.caption)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                            .padding(.vertical, 6)
                        }

                        quickPromptBar
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: store.messages.count) { _, _ in
                    if let lastID = store.messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            Divider()

            composerBar
        }
        .background(BevelTheme.canvas.ignoresSafeArea())
        .navigationTitle("问身体")
        .toolbar {
            ToolbarItem(placement: .bodyseekLeading) {
                BodySeekBrandMark(size: 20)
            }
            ToolbarItemGroup(placement: .bodyseekTrailing) {
                Button {
                    store.send(.newConversationTapped)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新对话")

                Menu {
                    Button {
                        store.send(.memorySheetPresented(true))
                    } label: {
                        Label("长期记忆管理 (\(store.memories.count))", systemImage: "brain.head.profile")
                    }
                    Button {
                        store.send(.openSettingsTapped)
                    } label: {
                        Label("AI 接口与设置", systemImage: "gearshape")
                    }
                    Button {
                        store.send(.newConversationTapped)
                    } label: {
                        Label("清空会话", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多")
            }
        }
        .sheet(
            isPresented: Binding(
                get: { store.showMemorySheet },
                set: { store.send(.memorySheetPresented($0)) }
            )
        ) {
            memorySheet
        }
    }

    private var memoryStripBar: some View {
        Button {
            store.send(.memorySheetPresented(true))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BevelTheme.brand)
                if let first = store.memories.first {
                    Text("已记住 \(store.memories.count) 条：\(first.content)")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.ink)
                        .lineLimit(1)
                } else {
                    Text("尚无长期记忆 · 对话提及伤病或习惯将自动记忆")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(BevelTheme.inkSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(BevelTheme.card.opacity(0.85))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coach-memory-strip")
    }

    @ViewBuilder
    private func messageRow(_ msg: CoachMessage) -> some View {
        if msg.role == .user {
            HStack {
                Spacer(minLength: 48)
                Text(msg.text)
                    .font(.subheadline)
                    .foregroundStyle(BevelTheme.onBrand)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(BevelTheme.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    BodySeekBrandMark(size: 15)
                    Text("BodySeek Coach")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.inkSecondary)
                    if let engineLabel = msg.engineLabel {
                        Text(engineLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(BevelTheme.brandSoft, in: Capsule())
                            .foregroundStyle(BevelTheme.brand)
                    }
                }

                if let memoryNote = msg.memorySavedNote {
                    Label(memoryNote, systemImage: "brain.head.profile")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(BevelTheme.brandSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(BevelTheme.brand)
                }

                Text(msg.text)
                    .font(.subheadline)
                    .foregroundStyle(BevelTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let metric = msg.evidenceMetric {
                    evidenceSparklineCard(for: metric)
                }

                if let proposal = msg.workoutProposal, !store.dismissedProposalMessageIDs.contains(msg.id) {
                    workoutProposalCard(proposal, messageID: msg.id)
                }
            }
        }
    }

    private func evidenceSparklineCard(for kind: MetricKind) -> some View {
        let tint = BevelTheme.color(for: kind)
        let title = kind == .recovery ? "HRV · 近 14 天" : "\(kind.title) · 近 14 天"
        return BevelCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.inkSecondary)
                    Spacer()
                    Text("客观序列")
                        .font(.caption2)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }
                MetricSparklineChart(
                    points: store.state.sparklinePoints(for: kind),
                    tint: tint,
                    height: 44
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-evidence-card")
    }

    private func workoutProposalCard(_ proposal: WorkoutProposal, messageID: UUID) -> some View {
        BevelCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("结构化训练处方 · 需你确认", systemImage: "dumbbell.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    Spacer()
                    Text(proposal.template.focusTag)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(BevelTheme.surfaceElevated, in: Capsule())
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                Text(proposal.template.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BevelTheme.ink)

                Text(proposal.rationale)
                    .font(.caption)
                    .foregroundStyle(BevelTheme.inkSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(proposal.template.exercises) { item in
                        let name = ExerciseCatalog.find(id: item.exerciseID)?.name ?? item.exerciseID
                        HStack {
                            Text("• \(name)")
                                .font(.caption)
                                .foregroundStyle(BevelTheme.ink)
                            Spacer()
                            Text("\(item.targetSets) 组 × \(item.targetReps) 次 · \(Int(item.targetWeightKg))kg")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(BevelTheme.inkSecondary)
                        }
                    }
                }
                .padding(8)
                .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 8) {
                    Button {
                        store.send(.applyProposalTapped(messageID: messageID, proposal: proposal, startImmediately: false))
                    } label: {
                        Text("加入健身页")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(BevelTheme.surfaceElevated, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach-proposal-save")

                    Button {
                        store.send(.applyProposalTapped(messageID: messageID, proposal: proposal, startImmediately: true))
                    } label: {
                        Text("立即开练")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.onBrand)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(BevelTheme.brand, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach-proposal-start")

                    Button {
                        store.send(.dismissProposalTapped(messageID))
                    } label: {
                        Text("不用了")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BevelTheme.inkSecondary)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-workout-proposal")
    }

    private var quickPromptBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.quickPrompts, id: \.self) { prompt in
                    Button {
                        store.send(.quickPromptTapped(prompt))
                    } label: {
                        Text(prompt)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BevelTheme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(BevelTheme.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(BevelTheme.hairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 4)
    }

    private var composerBar: some View {
        HStack(spacing: 10) {
            TextField(
                "追问状态、告诉 Coach 伤病或排一份新课表…",
                text: Binding(
                    get: { store.draftText },
                    set: { store.send(.draftChanged($0)) }
                ),
                axis: .vertical
            )
            .lineLimit(1...4)
            .focused($isComposerFocused)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(BevelTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityIdentifier("coach-full-input")

            Button {
                isComposerFocused = false
                store.send(.sendTapped)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        store.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? BevelTheme.inkSecondary
                            : BevelTheme.brand
                    )
            }
            .disabled(store.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSending)
            .accessibilityLabel("发送")
            .accessibilityIdentifier("coach-send-button")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(BevelTheme.canvas)
    }

    private var memorySheet: some View {
        NavigationStack {
            List {
                if store.memories.isEmpty {
                    Text("尚无已存储的长期记忆。当你在对话中说明「左肩不适」「习惯清晨训练」等情况时，AI 会自动记录到这里。")
                        .font(.footnote)
                        .foregroundStyle(BevelTheme.inkSecondary)
                } else {
                    ForEach(store.memories) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.category.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BevelTheme.brand)
                            Text(item.content)
                                .font(.subheadline)
                                .foregroundStyle(BevelTheme.ink)
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                store.send(.deleteMemoryTapped(item.id))
                            }
                        }
                    }
                }
            }
            .navigationTitle("长期记忆")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button("完成") {
                        store.send(.memorySheetPresented(false))
                    }
                }
            }
        }
    }
}
