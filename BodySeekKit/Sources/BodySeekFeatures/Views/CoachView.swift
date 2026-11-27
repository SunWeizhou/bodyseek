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
                LazyVStack(alignment: .leading, spacing: BSSpace.l) {
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
                                .padding(.vertical, BSSpace.xs)
                        }
                    }
                    Color.clear.frame(height: BSSize.dot)
                        .accessibilityHidden(true)
                        .id(ScrollTarget.latest)
                }
                .padding(.horizontal, BSSpace.m)
                .padding(.vertical, BSSpace.m)
                .frame(maxWidth: BSSize.chartDetail)
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
                    .padding(.trailing, BSSpace.m)
                    .padding(.bottom, BSSpace.xs)
                    .accessibilityIdentifier("coach-jump-to-latest")
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: BSSpace.none) {
            if let err = store.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(BevelTheme.dangerColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, BSSpace.m)
                    .padding(.vertical, BSSpace.xs)
                    .background(BevelTheme.canvas)
                    .accessibilityIdentifier("coach-error-banner")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: BSSpace.none) {
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
        withAnimation(BSMotion.animation(BSMotion.standard, reduceMotion: reduceMotion)) {
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
                    .padding(.horizontal, BSSpace.m)
                    .padding(.vertical, BSSpace.s)
                    .background(BevelTheme.brand, in: RoundedRectangle(cornerRadius: BSRadius.l, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                HStack(spacing: BSSpace.xs) {
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
                }

                CoachMarkdownReply(source: msg.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

                verificationFooter(msg)

                ForEach(msg.appliedActions) { receipt in
                    CoachReceiptCard(
                        receipt: receipt,
                        isUndone: store.undoneReceiptIDs.contains(receipt.id),
                        isPending: store.pendingReceiptUndoIDs.contains(receipt.id),
                        onUndo: { store.send(.undoReceiptTapped(messageID: msg.id, receiptID: receipt.id)) }
                    )
                }

                if let memProposal = msg.memoryProposal,
                   !store.dismissedMemoryProposalMessageIDs.contains(msg.id)
                {
                    memoryProposalCard(memProposal, messageID: msg.id)
                }

                if msg.annotationDecision == .undone || store.undoneAnnotationMessageIDs.contains(msg.id) {
                    annotationUndoneCard(msg)
                } else if let selected = store.annotationCandidateSelections[msg.id] {
                    workoutAnnotationProposalCard(
                        selected,
                        messageID: msg.id,
                        applied: msg.annotationDecision == .applied,
                        undone: false
                    )
                } else if msg.workoutAnnotationCandidates.count > 1, msg.workoutAnnotationProposal == nil,
                          msg.annotationDecision == nil,
                          !store.dismissedAnnotationProposalMessageIDs.contains(msg.id)
                {
                    annotationCandidateCard(msg.workoutAnnotationCandidates, messageID: msg.id)
                } else if let annotationProposal = msg.workoutAnnotationProposal, msg.annotationDecision != .rejected,
                          !store.dismissedAnnotationProposalMessageIDs.contains(msg.id)
                {
                    workoutAnnotationProposalCard(
                        annotationProposal,
                        messageID: msg.id,
                        applied: msg.annotationDecision == .applied || store.confirmedAnnotationProposalMessageIDs.contains(msg.id),
                        undone: msg.annotationDecision == .undone
                    )
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

    /// 回复底部一行核对汇总（UI v4 §6.1）：正文里不再逐个标"未核实"。
    @ViewBuilder
    private func verificationFooter(_ msg: CoachMessage) -> some View {
        if !msg.toolsInvoked.isEmpty {
            let count = msg.unverifiedNumbers.count
            let title = count == 0 ? "文中数字都已和本机数据核对 · 查看依据" : "有 \(count) 个数字未能核对 · 查看"
            DisclosureGroup {
                VStack(alignment: .leading, spacing: BSSpace.xxs) {
                    ForEach(msg.unverifiedNumbers, id: \.self) { token in
                        Text("未能核对：\(token)")
                            .bsText(.caption)
                    }
                    Text("本轮读取：" + msg.toolsInvoked.joined(separator: "、"))
                        .bsText(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, BSSpace.xxs)
            } label: {
                Text(title)
                    .bsText(.caption)
            }
            .accessibilityIdentifier("coach-verification-footer")
        }
    }

    private func memoryProposalCard(_ memory: TieredMemoryRecord, messageID: UUID) -> some View {
        let isCommitted = store.confirmedMemoryProposalMessageIDs.contains(messageID)
        return BSCard {
            VStack(alignment: .leading, spacing: BSSpace.xs) {
                HStack {
                    Label("保存这条记忆？", systemImage: "brain.head.profile")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    Spacer()
                    Text(memory.tier.titleLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, BSSpace.xs)
                        .padding(.vertical, BSSpace.xxs)
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
                    HStack(spacing: BSSpace.s) {
                        Button {
                            store.send(.confirmMemoryProposalTapped(messageID: messageID, memory: memory))
                        } label: {
                            Text("保存记忆")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, BSSpace.xs)
                                .background(BevelTheme.brand, in: Capsule())
                                .foregroundStyle(BevelTheme.onBrand)
                        }
                        .buttonStyle(.bsPressable)
                        .accessibilityIdentifier("coach-memory-proposal-confirm")

                        Button {
                            store.send(.dismissMemoryProposalTapped(messageID))
                        } label: {
                            Text("暂不保存")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .padding(.horizontal, BSSpace.s)
                        }
                        .buttonStyle(.bsPressable)
                        .accessibilityIdentifier("coach-memory-proposal-dismiss")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-memory-proposal-card")
    }

    private func annotationCandidateCard(
        _ candidates: [CoachWorkoutAnnotationCandidate],
        messageID: UUID
    ) -> some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.xs) {
                Label("选择要复盘的训练", systemImage: "list.bullet.rectangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BevelTheme.strainColor)
                Text("找到 \(candidates.count) 条 Watch 训练，请按开始时间和类型选择。")
                    .font(.caption2)
                    .foregroundStyle(BevelTheme.inkSecondary)
                ForEach(candidates) { candidate in
                    Button {
                        store.send(.selectAnnotationCandidate(messageID: messageID, candidate: candidate))
                    } label: {
                        HStack(spacing: BSSpace.s) {
                            VStack(alignment: .leading, spacing: BSSpace.xxs) {
                                Text(candidate.proposal.workoutTitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                Text(candidate.start, format: .dateTime.month().day().hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                            Spacer()
                            Text(candidate.reviewState == .unreviewed ? "待复盘" : "已记录")
                                .font(.caption2)
                                .foregroundStyle(BevelTheme.inkSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(BevelTheme.inkSecondary)
                        }
                        .padding(.vertical, BSSpace.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bsPressable)
                    .accessibilityIdentifier("coach-annotation-candidate-\(candidate.proposal.workoutUUID)")
                    if candidate.id != candidates.last?.id {
                        Divider().overlay(BevelTheme.hairline)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-annotation-candidate-card")
    }

    private func annotationUndoneCard(_ message: CoachMessage) -> some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.xs) {
                Label("这次训练标注已撤销", systemImage: "arrow.uturn.backward.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BevelTheme.inkSecondary)
                if let proposal = message.workoutAnnotationProposal {
                    Text("\(proposal.workoutTitle) ← “\(proposal.rawText)”")
                        .font(.caption2)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }
                Text("训练记录、肌群负荷和复盘状态已恢复到提交前。")
                    .font(.caption2)
                    .foregroundStyle(BevelTheme.inkSecondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-annotation-undone-card")
    }

    private func workoutAnnotationProposalCard(
        _ proposal: CoachWorkoutAnnotationProposal,
        messageID: UUID,
        applied: Bool,
        undone: Bool
    ) -> some View {
        let isCommitted = applied || store.confirmedAnnotationProposalMessageIDs.contains(messageID)
        let isUndone = undone || store.undoneAnnotationMessageIDs.contains(messageID)
        return BSCard {
            VStack(alignment: .leading, spacing: BSSpace.xs) {
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

                if isUndone {
                    Label("已撤销这次标注", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.inkSecondary)
                } else if isCommitted {
                    HStack {
                        Label("已保存训练复盘", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.recoveryColor)
                        Spacer()
                        Button {
                            store.send(.undoAnnotationTapped(messageID: messageID))
                        } label: {
                            Text("撤销")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BevelTheme.dangerColor)
                        }
                        .buttonStyle(.bsPressable)
                        .disabled(store.pendingAnnotationUndoMessageIDs.contains(messageID))
                        .accessibilityIdentifier("coach-annotation-undo")
                    }
                } else {
                    HStack(spacing: BSSpace.s) {
                        Button {
                            store.send(.confirmAnnotationProposalTapped(messageID: messageID, proposal: proposal))
                        } label: {
                            Text("保存到训练记录")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, BSSpace.xs)
                                .background(BevelTheme.brand, in: Capsule())
                                .foregroundStyle(BevelTheme.onBrand)
                        }
                        .buttonStyle(.bsPressable)
                        .accessibilityIdentifier("coach-annotation-proposal-confirm")

                        Button {
                            store.send(.dismissAnnotationProposalTapped(messageID))
                        } label: {
                            Text("忽略")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(BevelTheme.inkSecondary)
                        }
                        .buttonStyle(.bsPressable)
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
        return BSCard {
            VStack(alignment: .leading, spacing: BSSpace.xs) {
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
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                HStack {
                    Label("训练建议", systemImage: "dumbbell.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    Spacer()
                    Text(proposal.template.focusTag)
                        .font(.caption2)
                        .padding(.horizontal, BSSpace.xs)
                        .padding(.vertical, BSSpace.xxs)
                        .background(BevelTheme.surfaceElevated, in: Capsule())
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                Text(proposal.template.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BevelTheme.ink)

                Text(proposal.rationale)
                    .font(.caption)
                    .foregroundStyle(BevelTheme.inkSecondary)

                VStack(alignment: .leading, spacing: BSSpace.xxs) {
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
                .padding(BSSpace.xs)
                .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: BSRadius.s, style: .continuous))

                HStack(spacing: BSSpace.xs) {
                    Button {
                        store.send(.applyProposalTapped(messageID: messageID, proposal: proposal, startImmediately: false))
                    } label: {
                        Text("保存计划并查看")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.onBrand)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, BSSpace.xs)
                            .background(BevelTheme.brand, in: Capsule())
                    }
                    .buttonStyle(.bsPressable)
                    .accessibilityIdentifier("coach-proposal-save")

                    Button {
                        store.send(.dismissProposalTapped(messageID))
                    } label: {
                        Text("不用了")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BevelTheme.inkSecondary)
                            .padding(.horizontal, BSSpace.s)
                            .padding(.vertical, BSSpace.xs)
                    }
                    .buttonStyle(.bsPressable)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-workout-proposal")
    }

    private var welcomePanel: some View {
        VStack(alignment: .leading, spacing: BSSpace.m) {
            Text("今天想了解什么？")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: BSSpace.xs) {
                ForEach(store.quickPrompts, id: \.title) { prompt in
                    Button {
                        store.send(.quickPromptTapped(prompt.question))
                    } label: {
                        HStack(spacing: BSSpace.s) {
                            VStack(alignment: .leading, spacing: BSSpace.xxs) {
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
                        .padding(BSSpace.s)
                        .background(BevelTheme.card, in: RoundedRectangle(cornerRadius: BSRadius.m))
                        .overlay(RoundedRectangle(cornerRadius: BSRadius.m).strokeBorder(BevelTheme.hairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.bsPressable)
                    .disabled(store.isResettingConversation)
                }
            }
        }
        .foregroundStyle(BevelTheme.ink)
        .padding(.vertical, BSSpace.s)
        .accessibilityIdentifier("coach-welcome-panel")
    }

    private var composerBar: some View {
        let canSend = !store.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !store.isSending && !store.isResettingConversation
        return HStack(alignment: .bottom, spacing: BSSpace.xs) {
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
            .padding(.horizontal, BSSpace.m)
            .padding(.vertical, BSSpace.s)
            .accessibilityIdentifier("coach-full-input")

            Button {
                isComposerFocused = false
                store.send(.sendTapped)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .frame(width: BSSize.hitTarget, height: BSSize.hitTarget)
                    .foregroundStyle(
                        canSend ? BevelTheme.brand : BevelTheme.inkSecondary
                    )
            }
            .disabled(!canSend)
            .accessibilityLabel("发送")
            .accessibilityIdentifier("coach-send-button")
        }
        .padding(BSSpace.xxs)
        .background(BevelTheme.card, in: RoundedRectangle(cornerRadius: BSRadius.l))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.l).strokeBorder(BevelTheme.hairline, lineWidth: 0.5))
        .padding(.horizontal, BSSpace.m)
        .padding(.vertical, BSSpace.xs)
        .frame(maxWidth: BSSize.chartDetail)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}
