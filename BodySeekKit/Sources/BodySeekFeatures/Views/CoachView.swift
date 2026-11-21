import BodySeekAgent
import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct CoachView: View {
    @Bindable var store: StoreOf<CoachFeature>
    @FocusState private var isComposerFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isNearLatest = true
    @State private var confirmNewConversation = false

    private enum ScrollTarget: Hashable {
        case welcome
        case latest
    }

    public init(store: StoreOf<CoachFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if store.isAtWelcome {
                        welcomePanel
                            .id(ScrollTarget.welcome)
                    } else {
                        ForEach(store.messages) { msg in
                            messageRow(msg)
                                .id(msg.id)
                        }
                        if store.isSending {
                            ProgressView("Coach 正在回复…")
                                .controlSize(.small)
                                .font(.footnote)
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .padding(.vertical, 8)
                        }
                    }
                    Color.clear.frame(height: 1)
                        .accessibilityHidden(true)
                        .id(ScrollTarget.latest)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(store.isAtWelcome ? .top : .bottom, for: .initialOffset)
            .scrollDismissesKeyboard(.interactively)
            .bodyseekScrollEdgeEffect()
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY < 100
            } action: { _, nearLatest in
                isNearLatest = nearLatest
            }
            .onChange(of: store.messages.last?.id) { _, _ in
                if store.isAtWelcome {
                    scroll(to: ScrollTarget.welcome, anchor: .top, using: proxy)
                } else if let last = store.messages.last, last.role == .user {
                    scroll(to: ScrollTarget.latest, anchor: .bottom, using: proxy)
                } else if let last = store.messages.last, isNearLatest {
                    scroll(to: last.id, anchor: .top, using: proxy)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !isNearLatest && !store.isAtWelcome {
                    Button("回到底部", systemImage: "arrow.down") {
                        scroll(to: ScrollTarget.latest, anchor: .bottom, using: proxy)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.trailing, 18)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("coach-jump-to-latest")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let err = store.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(BevelTheme.dangerColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(BevelTheme.canvas)
                    .accessibilityIdentifier("coach-error-banner")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerBar
        }
        .background(BevelTheme.canvas.ignoresSafeArea())
        .navigationTitle("Coach")
        .bodyseekNavigationBarInline()
        .toolbar {
            ToolbarItemGroup(placement: .bodyseekTrailing) {
                Button {
                    store.send(.memorySheetPresented(true))
                } label: {
                    Image(systemName: "brain.head.profile")
                }
                .accessibilityLabel("记忆")
                .accessibilityIdentifier("coach-memory-strip")

                Button {
                    confirmNewConversation = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新对话")
                .disabled(store.isAtWelcome || store.isSending || store.isResettingConversation)

                Menu {
                    Button {
                        store.send(.openSettingsTapped)
                    } label: {
                        Label("AI 连接与隐私", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多")
            }
        }
        .alert("开始新对话？", isPresented: $confirmNewConversation) {
            Button("清空并开始", role: .destructive) {
                store.send(.newConversationTapped)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会清空当前聊天记录。")
        }
        .sheet(
            isPresented: Binding(
                get: { store.showMemorySheet },
                set: { store.send(.memorySheetPresented($0)) }
            )
        ) {
            CoachMemorySheetView(store: store)
        }
    }

    private func scroll(to id: some Hashable, anchor: UnitPoint, using proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            proxy.scrollTo(id, anchor: anchor)
        }
    }

    @ViewBuilder
    private func messageRow(_ msg: CoachMessage) -> some View {
        if msg.role == .user {
            HStack {
                Spacer(minLength: 48)
                Text(msg.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .foregroundStyle(BevelTheme.onBrand)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(BevelTheme.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    if let engine = msg.engineLabel {
                        Menu {
                            Text(engine)
                        } label: {
                            Label("Coach", systemImage: "info.circle")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(BevelTheme.inkSecondary)
                        }
                        .accessibilityLabel("回复来源")
                    } else {
                        Label("Coach", systemImage: "bubble.left")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                    if !msg.unverifiedNumbers.isEmpty {
                        Text("含未核实数字")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(BevelTheme.dangerColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(BevelTheme.dangerColor)
                            .accessibilityIdentifier("coach-unverified-badge")
                    }
                }

                CoachMarkdownReply(source: msg.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let memProposal = msg.memoryProposal,
                   !store.dismissedMemoryProposalMessageIDs.contains(msg.id)
                {
                    memoryProposalCard(memProposal, messageID: msg.id)
                }

                if let annotationProposal = msg.workoutAnnotationProposal, msg.annotationDecision != .rejected,
                   !store.dismissedAnnotationProposalMessageIDs.contains(msg.id)
                {
                    workoutAnnotationProposalCard(annotationProposal, messageID: msg.id, applied: msg.annotationDecision == .applied)
                }

                if let metric = msg.evidenceMetric {
                    evidenceSparklineCard(for: metric)
                }

                if let proposal = msg.workoutProposal,
                   !store.dismissedProposalMessageIDs.contains(msg.id)
                {
                    workoutProposalCard(proposal, messageID: msg.id)
                }
            }
        }
    }

    private func memoryProposalCard(_ memory: TieredMemoryRecord, messageID: UUID) -> some View {
        let isCommitted = store.confirmedMemoryProposalMessageIDs.contains(messageID)
        return BevelCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("保存这条记忆？", systemImage: "brain.head.profile")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    Spacer()
                    Text(memory.tier.titleLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(BevelTheme.surfaceElevated, in: Capsule())
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                Text(memory.content)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BevelTheme.ink)

                if let exp = memory.expiresAt {
                    let days = max(1, Int((exp.timeIntervalSince(memory.confirmedAt ?? Date()) / 86_400).rounded()))
                    Text("\(days) 天后自动到期")
                        .font(.caption2)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                if isCommitted {
                    Label("已确认写入 \(memory.tier.titleLabel)", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.recoveryColor)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            store.send(.confirmMemoryProposalTapped(messageID: messageID, memory: memory))
                        } label: {
                            Text("保存记忆")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(BevelTheme.brand, in: Capsule())
                                .foregroundStyle(BevelTheme.onBrand)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("coach-memory-proposal-confirm")

                        Button {
                            store.send(.dismissMemoryProposalTapped(messageID))
                        } label: {
                            Text("暂不保存")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("coach-memory-proposal-dismiss")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-memory-proposal-card")
    }

    private func workoutAnnotationProposalCard(_ proposal: CoachWorkoutAnnotationProposal, messageID: UUID, applied: Bool) -> some View {
        let isCommitted = applied || store.confirmedAnnotationProposalMessageIDs.contains(messageID)
        return BevelCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label("保存这次训练复盘？", systemImage: "text.bubble.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BevelTheme.strainColor)

                Text("\(proposal.workoutTitle) ← “\(proposal.rawText)”")
                    .font(.caption)
                    .foregroundStyle(BevelTheme.ink)
                if let workout = store.storedWorkouts.first(where: { $0.hkUUID == proposal.workoutUUID }) {
                    Text(workout.start, format: .dateTime.month().day().hour().minute())
                        .font(.subheadline)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                Text("主肌群：\(proposal.proposal.primaryMuscles.map(\.title).joined(separator: "、"))" + (proposal.proposal.rpe.map { " · RPE \($0)" } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(BevelTheme.inkSecondary)

                if isCommitted {
                    Label("已保存训练复盘", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.recoveryColor)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            store.send(.confirmAnnotationProposalTapped(messageID: messageID, proposal: proposal))
                        } label: {
                            Text("保存到训练记录")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(BevelTheme.brand, in: Capsule())
                                .foregroundStyle(BevelTheme.onBrand)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("coach-annotation-proposal-confirm")

                        Button {
                            store.send(.dismissAnnotationProposalTapped(messageID))
                        } label: {
                            Text("忽略")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(BevelTheme.inkSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-annotation-proposal-card")
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

                }
                MiniSparkline(
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
                    Label("训练建议", systemImage: "dumbbell.fill")
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

    private var welcomePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("今天想了解什么？")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 8) {
                ForEach(store.quickPrompts, id: \.title) { prompt in
                    Button {
                        store.send(.quickPromptTapped(prompt.question))
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(prompt.title).font(.subheadline.weight(.semibold))
                                Text(prompt.question)
                                    .font(.footnote)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(BevelTheme.brand)
                                .accessibilityHidden(true)
                        }
                        .padding(12)
                        .background(BevelTheme.card, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(BevelTheme.hairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isResettingConversation)
                }
            }
        }
        .foregroundStyle(BevelTheme.ink)
        .padding(.vertical, 10)
        .accessibilityIdentifier("coach-welcome-panel")
    }

    private var composerBar: some View {
        let canSend = !store.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !store.isSending && !store.isResettingConversation
        return HStack(alignment: .bottom, spacing: 8) {
            TextField(
                "问 Coach…",
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
            .accessibilityIdentifier("coach-full-input")

            Button {
                isComposerFocused = false
                store.send(.sendTapped)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(
                        canSend ? BevelTheme.brand : BevelTheme.inkSecondary
                    )
            }
            .disabled(!canSend)
            .accessibilityLabel("发送")
            .accessibilityIdentifier("coach-send-button")
        }
        .padding(3)
        .background(BevelTheme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(BevelTheme.hairline, lineWidth: 0.5))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
