import SwiftUI
import SwiftData

// MARK: - Plan presentation contract

enum PlanLoadPhase: Equatable, Sendable {
    case idle
    case loading(previous: Bool)
    case ready
    case empty
    case failed
}

enum PlanError: Equatable, Sendable, LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        }
    }
}

struct PlanCompletionProjection: Equatable, Sendable {
    let completed: Int
    let total: Int

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

/// Immutable plan read model used by the redesigned page. Persistence and
/// mutation remain behind the existing plan adapter until the full migration
/// is complete.
struct PlanViewState: Equatable, Sendable {
    var selectedDay: Date
    var activePlan: TodayPlanProjection?
    var pendingProposal: TodayPendingPlanProjection?
    var completion: PlanCompletionProjection
    var phase: PlanLoadPhase
    var error: PlanError?
}

enum PlanAction: Hashable, Sendable {
    case complete(actionID: String)
    case edit(actionID: String)
    case delete(actionID: String)
    case acceptProposal
    case rejectProposal
    case openTraining
    case askCoach
}

/// The user's daily operating plan. Training is one downstream action domain,
/// not the organizing principle of the primary workspace.
struct VelaPlanView: View {
    @EnvironmentObject private var dashboardVM: DashboardViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appState = VelaAppState.shared

    @State private var plan: DailyOperatingPlanRecord?
    @State private var editorDraft: PlanActionDraft?
    @State private var pendingDelete: DailyOperatingPlanAction?
    @State private var showTraining = false
    @State private var lastHandledTrainingRequest = 0
    @State private var planRevision = 0
    @State private var planError: PlanError?

    private var payload: DailyOperatingPlanPayload? {
        plan?.operatingPlanPayload
    }

    private var actions: [DailyOperatingPlanAction] {
        payload?.allActions ?? []
    }

    private var completedCount: Int {
        actions.filter { $0.completedAt != nil }.count
    }

    private var candidatePayload: DailyOperatingPlanPayload? {
        guard let plan, payload?.hasUserEdits == true,
              plan.bodyStateHash != dashboardVM.dashboard.bodyState.hash else {
            return nil
        }
        return DailyOperatingPlanBuilder.build(
            bodyState: dashboardVM.dashboard.bodyState,
            decision: currentDecision,
            brief: dashboardVM.dashboard.personalHealthBrief,
            language: AppLanguage.stored
        )
    }

    private var currentDecision: DailyTrainingDecision {
        dashboardVM.dailyTrainingDecision ?? TrainingDecisionKernel().decide(
            input: TrainingDecisionInput(
                bodyState: dashboardVM.dashboard.bodyState,
                personalHealthBrief: dashboardVM.dashboard.personalHealthBrief
            )
        )
    }

    private var dayIdentifier: String {
        DailyHealthSummaryRecord.dayIdentifier(for: dashboardVM.selectedDate)
    }

    private var planViewState: PlanViewState {
        let payload = plan?.operatingPlanPayload
        let currentActions = payload?.allActions ?? []
        let phase: PlanLoadPhase
        if planError != nil {
            phase = .failed
        } else if plan == nil {
            phase = .loading(previous: false)
        } else if payload == nil || currentActions.isEmpty {
            phase = .empty
        } else {
            phase = .ready
        }
        return PlanViewState(
            selectedDay: dashboardVM.selectedDate,
            activePlan: payload.map(TodayPlanProjection.init),
            pendingProposal: nil,
            completion: PlanCompletionProjection(
                completed: currentActions.filter { $0.completedAt != nil }.count,
                total: currentActions.count
            ),
            phase: phase,
            error: planError
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VelaSurfaceHeader(
                title: L10n.t("Plan", "计划"),
                subtitle: dateSubtitle
            ) {
                Button {
                    appState.routeToCoach(question: coachQuestion, surface: .plan)
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .frame(width: VelaTheme.circularControlSize, height: VelaTheme.circularControlSize)
                        .background(VelaTheme.rhythmCanvasRaised, in: Circle())
                }
                .buttonStyle(.cardPress)
                .accessibilityLabel("让 Vela 分析今天的计划")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: VelaTheme.sectionGap) {
                    if let error = planViewState.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error.localizedDescription)
                                .font(VelaTheme.footnote())
                            Button("重新读取计划") { loadOrCreatePlan() }
                        }
                        .foregroundStyle(VelaTheme.stressColor)
                        .accessibilityIdentifier("plan-save-error")
                    }
                        rhythmSummary

                    if let candidatePayload {
                        candidateCard(candidatePayload)
                    }

                    actionSection
                    trainingPortal
                }
                .padding(.horizontal, VelaTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, VelaTheme.bottomContentClearance)
                .id(planRevision)
            }
            .scrollIndicators(.hidden)
        }
        .background(VelaTheme.rhythmCanvas)
        .task(id: dayIdentifier) {
            await dashboardVM.refresh(modelContext: modelContext)
            loadOrCreatePlan()
            openRequestedTrainingIfNeeded()
        }
        .onChange(of: appState.localDataRevision) { _, _ in
            loadOrCreatePlan()
        }
        .onChange(of: appState.adaptiveTrainingStartRequest) { _, _ in
            openRequestedTrainingIfNeeded()
        }
        .sheet(item: $editorDraft) { draft in
            PlanActionEditorSheet(draft: draft) { savedDraft in
                save(savedDraft)
            }
            .velaSheetSurface()
        }
        .confirmationDialog(
            "删除“\(pendingDelete?.title ?? "这项行动")”？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除行动", role: .destructive) {
                deletePendingAction()
            }
            Button("取消", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            Text("只会从今天的计划中移除，其他健康数据不会改变。")
        }
        .navigationDestination(isPresented: $showTraining) {
            VelaTrainingView()
        }
    }

    private var rhythmSummary: some View {
        let completion = planViewState.completion
        let total = completion.total
        let progress = completion.progress
        let completed = completion.completed
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(total == 0 ? "今天由你决定" : primaryRhythmTitle)
                        .font(.system(.title2, design: .default, weight: .semibold))
                        .tracking(-0.35)
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(total == 0 ? "添加一项真正有帮助的行动" : completed == total ? "今天的安排已完成" : "按自己的节奏，一项一项完成")
                        .font(.footnote)
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                Spacer(minLength: 16)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(completed)")
                        .font(.system(.largeTitle, design: .default, weight: .semibold).monospacedDigit())
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Text("/\(total)")
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("已完成 \(completed) 项，共 \(total) 项")
            }

            BodySeekPlanProgressRail(
                completed: completed,
                total: total,
                tint: VelaTheme.rhythmDeep
            )
            .animation(VelaTheme.dataAnimation(reduceMotion: reduceMotion), value: progress)
        }
        .padding(VelaTheme.cardPadding)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        }
        .shadow(color: VelaTheme.cardShadow(colorScheme), radius: 14, x: 0, y: 6)
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VelaRhythmSectionHeader(
                eyebrow: L10n.t("TODAY", "今天"),
                title: "今日行动",
                actionTitle: actions.count < 3 ? "添加" : nil,
                action: presentAddEditor
            )

            if actions.isEmpty {
                Button(action: presentAddEditor) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmDeepOn)
                            .frame(width: 34, height: 34)
                            .background(VelaTheme.rhythmDeep, in: Circle())
                        Text("添加今天的第一项行动")
                            .font(.system(.subheadline, design: .default, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Spacer()
                    }
                    .padding(VelaTheme.cardPadding)
                    .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.cardPress)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        PlanActionRow(
                            action: action,
                            isPrimary: index == 0,
                            onToggle: { toggle(action) },
                            onEdit: { presentEditor(for: action, mode: .edit) },
                            onReschedule: { presentEditor(for: action, mode: .reschedule) },
                            onReplace: { presentEditor(for: action, mode: .replace) },
                            onDelete: { pendingDelete = action }
                        )
                        if index < actions.count - 1 {
                            Divider()
                                .overlay(VelaTheme.rhythmMist)
                                .padding(.leading, 66)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                }
            }
        }
    }

    private func candidateCard(_ candidate: DailyOperatingPlanPayload) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(VelaTheme.rhythmDeep)
                Text("Vela 建议更新")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
            }

            Text(candidateSentence(candidate))
                .font(.system(.body, design: .default))
                .foregroundStyle(VelaTheme.rhythmInk)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(candidate.allActions) { action in
                    let style = PlanDomainStyle(action.domain)
                    HStack(spacing: 8) {
                        Image(systemName: style.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(style.color)
                            .frame(width: 20)
                        Text(action.title)
                            .font(.system(.caption, design: .default, weight: .medium))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .accessibilityElement(children: .contain)

            HStack(spacing: 10) {
                Button("采用新计划") {
                    accept(candidate)
                }
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmDeepOn)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(VelaTheme.rhythmDeep, in: Capsule())
                .buttonStyle(.cardPress)

                Button("保留我的安排") {
                    keepCurrentPlan()
                }
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .buttonStyle(.cardPress)
            }
        }
        .padding(VelaTheme.cardPadding)
        .background(VelaTheme.rhythmDeep.opacity(0.08), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(VelaTheme.rhythmDeep.opacity(0.20), lineWidth: 0.8)
        }
    }

    private var trainingPortal: some View {
        Button {
            showTraining = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "figure.run")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(VelaTheme.strainColor)
                    .frame(width: 42, height: 42)
                    .background(VelaTheme.strainColor.opacity(0.11), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("训练")
                        .font(.system(.headline, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Text("训练窗口、轮转与记录")
                        .font(.footnote)
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.caption, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .padding(VelaTheme.cardPadding)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
            }
        }
        .buttonStyle(.cardPress)
        .accessibilityHint("打开训练专项")
    }

    private var primaryRhythmTitle: String {
        payload?.primaryAction?.title ?? "今天的节奏"
    }

    private var dateSubtitle: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.stored.isChinese
            ? Locale(identifier: "zh_Hans_CN")
            : Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        let date = formatter.string(from: dashboardVM.selectedDate)
        return Calendar.current.isDateInToday(dashboardVM.selectedDate) ? "今天 · \(date)" : date
    }

    private var coachQuestion: String {
        "请结合我今天的身体状态和当前每日计划，分析这些安排是否合适；先说明最值得关注的一点，再回答我的追问。"
    }

    private func candidateSentence(_ candidate: DailyOperatingPlanPayload) -> String {
        guard let title = candidate.primaryAction?.title else {
            return "身体状态有了变化，我建议把今天留得更轻一些。"
        }
        return "身体状态有了变化，我建议把今天的重点调整为“\(title)”。"
    }

    private func loadOrCreatePlan() {
        if plan?.dayIdentifier != dayIdentifier { plan = nil }
        var descriptor = FetchDescriptor<DailyOperatingPlanRecord>(
            predicate: #Predicate<DailyOperatingPlanRecord> { $0.dayIdentifier == dayIdentifier },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        do {
            if let stored = try modelContext.fetch(descriptor).first {
                plan = stored
            } else {
                guard Calendar.current.isDate(dashboardVM.dashboard.bodyState.date, inSameDayAs: dashboardVM.selectedDate) else {
                    throw PlanError.unavailable("所选日期的身体状态仍在读取，请稍后重试。")
                }
                plan = try DailyOperatingPlanCoordinator.upsert(
                    bodyState: dashboardVM.dashboard.bodyState,
                    decision: currentDecision,
                    brief: dashboardVM.dashboard.personalHealthBrief,
                    modelContext: modelContext
                )
            }
            planError = nil
            planRevision += 1
        } catch {
            planError = .unavailable("计划未能读取或保存：\(error.localizedDescription)")
        }
    }

    private func mutate(_ mutation: DailyOperatingPlanMutation) throws {
        guard let plan, let payload else {
            throw PlanError.unavailable("计划尚未准备好，修改未保存。请稍后重试。")
        }
        let updated = DailyOperatingPlanEditor.applying(mutation, to: payload)
        try DailyOperatingPlanEditor.persist(updated, to: plan, modelContext: modelContext)
        planError = nil
        planRevision += 1
        appState.markLocalDataChanged()
    }

    private func toggle(_ action: DailyOperatingPlanAction) {
        let wasComplete = action.completedAt != nil
        do {
            try mutate(.toggleCompletion(actionID: action.id, at: Date()))
            if wasComplete {
                VelaHaptic.selection()
            } else {
                VelaHaptic.success()
            }
        } catch {
            planError = .unavailable("完成状态未保存：\(error.localizedDescription)")
        }
    }

    private func presentAddEditor() {
        guard actions.count < 3 else { return }
        editorDraft = PlanActionDraft.new(
            usedDomains: Set(actions.map(\.domain)),
            selectedDate: dashboardVM.selectedDate
        )
    }

    private func presentEditor(for action: DailyOperatingPlanAction, mode: PlanActionDraft.Mode) {
        editorDraft = PlanActionDraft.existing(
            action,
            mode: mode,
            usedDomains: Set(actions.filter { $0.id != action.id }.map(\.domain)),
            selectedDate: dashboardVM.selectedDate
        )
    }

    private func save(_ draft: PlanActionDraft) -> Result<Void, Error> {
        let action = draft.action
        do {
            if draft.originalActionID == nil {
                try mutate(.add(action: action, at: Date()))
            } else {
                try mutate(.update(action: action, at: Date()))
            }
            VelaHaptic.success()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func deletePendingAction() {
        guard let action = pendingDelete else { return }
        do {
            try mutate(.delete(actionID: action.id, at: Date()))
            pendingDelete = nil
            VelaHaptic.selection()
        } catch {
            planError = .unavailable("行动未删除：\(error.localizedDescription)")
        }
    }

    private func accept(_ candidate: DailyOperatingPlanPayload) {
        do {
            plan = try DailyOperatingPlanCoordinator.upsert(
                bodyState: dashboardVM.dashboard.bodyState,
                decision: currentDecision,
                brief: dashboardVM.dashboard.personalHealthBrief,
                modelContext: modelContext
            )
            planRevision += 1
            planError = nil
            appState.markLocalDataChanged()
            VelaHaptic.success()
        } catch {
            planError = .unavailable("新计划未保存，原计划仍保留：\(error.localizedDescription)")
        }
    }

    private func keepCurrentPlan() {
        guard let plan, let payload else { return }
        do {
            try DailyOperatingPlanEditor.acknowledgeCurrentPlan(
                payload,
                record: plan,
                bodyStateHash: dashboardVM.dashboard.bodyState.hash,
                modelContext: modelContext
            )
            planRevision += 1
            planError = nil
            appState.markLocalDataChanged()
            VelaHaptic.selection()
        } catch {
            planError = .unavailable("保留安排的确认未保存：\(error.localizedDescription)")
        }
    }

    private func openRequestedTrainingIfNeeded() {
        let request = appState.adaptiveTrainingStartRequest
        guard request > lastHandledTrainingRequest else { return }
        lastHandledTrainingRequest = request
        showTraining = true
    }
}

private struct PlanActionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let action: DailyOperatingPlanAction
    let isPrimary: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onReschedule: () -> Void
    let onReplace: () -> Void
    let onDelete: () -> Void

    private var style: PlanDomainStyle { PlanDomainStyle(action.domain) }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        completionButton
                        if isPrimary {
                            primaryBadge
                        }
                        Spacer(minLength: 8)
                        managementMenu
                    }
                    actionButton(showsPrimaryBadgeInline: false)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    completionButton
                    actionButton(showsPrimaryBadgeInline: true)
                    managementMenu
                }
            }
        }
        .padding(.vertical, 12)
    }

    private var completionButton: some View {
        Button(action: onToggle) {
            ZStack {
                Circle()
                    .stroke(action.completedAt == nil ? style.color.opacity(0.62) : style.color, lineWidth: 1.8)
                if action.completedAt != nil {
                    Circle().fill(style.color)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                } else {
                    Image(systemName: style.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(style.color)
                }
            }
            .frame(width: 40, height: 40)
            .contentShape(Circle())
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel(action.completedAt == nil ? "完成 \(action.title)" : "取消完成 \(action.title)")
    }

    private func actionButton(showsPrimaryBadgeInline: Bool) -> some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(action.title)
                        .font(.system(.subheadline, design: .default, weight: isPrimary ? .semibold : .medium))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .strikethrough(action.completedAt != nil, color: VelaTheme.rhythmInkSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    if isPrimary && showsPrimaryBadgeInline {
                        primaryBadge
                    }
                }
                if let scheduledAt = action.scheduledAt {
                    Label(scheduledAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                } else if !action.detail.isEmpty {
                    Text(action.detail)
                        .font(.caption)
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(action.completedAt == nil ? 1 : 0.62)
    }

    private var primaryBadge: some View {
        Text("重点")
            .font(.system(.caption2, design: .default, weight: .semibold))
            .foregroundStyle(VelaTheme.rhythmDeep)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(VelaTheme.rhythmDeep.opacity(0.10), in: Capsule())
    }

    private var managementMenu: some View {
        Menu {
            Button("编辑", systemImage: "pencil", action: onEdit)
            Button("改期", systemImage: "clock", action: onReschedule)
            Button("替换", systemImage: "arrow.triangle.2.circlepath", action: onReplace)
            Divider()
            Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("管理 \(action.title)")
    }
}

private struct PlanActionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlanActionDraft
    @State private var saveError: String?
    let onSave: (PlanActionDraft) -> Result<Void, Error>

    init(draft: PlanActionDraft, onSave: @escaping (PlanActionDraft) -> Result<Void, Error>) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section {
                        Text("未保存：\(saveError)")
                            .foregroundStyle(VelaTheme.stressColor)
                        Text("修改内容仍保留在这里，可以再次点击保存。")
                            .font(.footnote)
                    }
                    .accessibilityIdentifier("plan-editor-save-error")
                }
                Section("行动") {
                    Picker("类别", selection: $draft.domain) {
                        ForEach(draft.availableDomains, id: \.self) { domain in
                            Label(PlanDomainStyle(domain).title, systemImage: PlanDomainStyle(domain).icon)
                                .tag(domain)
                        }
                    }
                    TextField("准备做什么？", text: $draft.title, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("补充说明（可选）", text: $draft.detail, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section("安排") {
                    Toggle("设置时间", isOn: $draft.hasSchedule)
                    if draft.hasSchedule {
                        DatePicker(
                            "时间",
                            selection: $draft.scheduledAt,
                            displayedComponents: [.hourAndMinute]
                        )
                    }
                }
            }
            .velaRhythmFormSurface()
            .navigationTitle(draft.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        switch onSave(draft) {
                        case .success:
                            dismiss()
                        case .failure(let error):
                            saveError = error.localizedDescription
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct PlanActionDraft: Identifiable {
    enum Mode { case add, edit, reschedule, replace }

    let id = UUID()
    var originalActionID: String?
    var mode: Mode
    var domain: DailyOperatingPlanActionDomain
    var title: String
    var detail: String
    var hasSchedule: Bool
    var scheduledAt: Date
    var completedAt: Date?
    var evidence: String?
    var availableDomains: [DailyOperatingPlanActionDomain]

    var navigationTitle: String {
        switch mode {
        case .add: "添加行动"
        case .edit: "编辑行动"
        case .reschedule: "安排时间"
        case .replace: "替换行动"
        }
    }

    var action: DailyOperatingPlanAction {
        DailyOperatingPlanAction(
            id: originalActionID ?? "user_\(UUID().uuidString)",
            domain: domain,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: PlanDomainStyle(domain).destination,
            evidence: evidence ?? "用户安排",
            scheduledAt: hasSchedule ? scheduledAt : nil,
            completedAt: completedAt
        )
    }

    static func new(usedDomains: Set<DailyOperatingPlanActionDomain>, selectedDate: Date) -> Self {
        let domains = DailyOperatingPlanActionDomain.allCases.filter { !usedDomains.contains($0) }
        let defaultDomain = domains.first ?? .movement
        return Self(
            originalActionID: nil,
            mode: .add,
            domain: defaultDomain,
            title: "",
            detail: "",
            hasSchedule: false,
            scheduledAt: defaultSchedule(on: selectedDate),
            completedAt: nil,
            evidence: "用户安排",
            availableDomains: domains
        )
    }

    static func existing(
        _ action: DailyOperatingPlanAction,
        mode: Mode,
        usedDomains: Set<DailyOperatingPlanActionDomain>,
        selectedDate: Date
    ) -> Self {
        let domains = DailyOperatingPlanActionDomain.allCases.filter {
            $0 == action.domain || !usedDomains.contains($0)
        }
        return Self(
            originalActionID: action.id,
            mode: mode,
            domain: action.domain,
            title: mode == .replace ? "" : action.title,
            detail: mode == .replace ? "" : action.detail,
            hasSchedule: mode == .reschedule || action.scheduledAt != nil,
            scheduledAt: action.scheduledAt ?? defaultSchedule(on: selectedDate),
            completedAt: mode == .replace ? nil : action.completedAt,
            evidence: mode == .replace ? "用户替换" : action.evidence,
            availableDomains: domains
        )
    }

    private static func defaultSchedule(on date: Date) -> Date {
        Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
    }
}

private struct PlanDomainStyle {
    let domain: DailyOperatingPlanActionDomain
    init(_ domain: DailyOperatingPlanActionDomain) { self.domain = domain }

    var title: String {
        switch domain {
        case .training: "训练"
        case .movement: "活动"
        case .eatingRhythm: "饮食节奏"
        case .stressRecovery: "放松恢复"
        case .sleep: "睡眠"
        }
    }

    var icon: String {
        switch domain {
        case .training: "figure.run"
        case .movement: "figure.walk"
        case .eatingRhythm: "fork.knife"
        case .stressRecovery: "wind"
        case .sleep: "bed.double.fill"
        }
    }

    var color: Color {
        switch domain {
        case .training: VelaTheme.strainColor
        case .movement: VelaTheme.recoveryColor
        case .eatingRhythm: VelaTheme.energyColor
        case .stressRecovery: VelaTheme.stressColor
        case .sleep: VelaTheme.sleepColor
        }
    }

    var destination: String {
        switch domain {
        case .training: "training"
        case .movement: "movement"
        case .eatingRhythm: "nutrition"
        case .stressRecovery: "recovery"
        case .sleep: "sleep"
        }
    }
}

struct VelaTrainingRotationView: View {
    @Query(sort: \TrainingPlanRecord.updatedAt, order: .reverse)
    private var plans: [TrainingPlanRecord]
    @Query(sort: \WorkoutEventRecord.startedAt, order: .reverse)
    private var events: [WorkoutEventRecord]
    // 算法打通（批次 B）：BodyInterpreterEngine + AdaptiveTrainingEngine 产出的
    // 计划调整提案（TrainingPlanAdaptationRecord）此前写在库里但没有任何页面读取——
    // 旧日历页挂在死导航下。这里接上：今日提案展示 + 用户确认（ADR 0008）。
    @Query(
        filter: #Predicate<TrainingPlanAdaptationRecord> { $0.status == "proposed" },
        sort: \TrainingPlanAdaptationRecord.createdAt
    )
    private var pendingAdaptations: [TrainingPlanAdaptationRecord]
    @EnvironmentObject private var dashboardVM: DashboardViewModel
    @Environment(\.modelContext) private var modelContext

    /// 今天的正式运营计划（决策面板数据源；无则退回恢复信号说明）。
    @State private var todayOperatingPlan: DailyOperatingPlanRecord?

    private var activePlan: TrainingPlanRecord? {
        plans.first(where: \.isActive) ?? plans.first
    }

    /// 深度专项批次 4：提案区覆盖今日 + 未来未完成训练日——
    /// 本机提案（今日）与 AI 练后边界建议（下次训练日）都能被看到并确认。
    private var planAdaptations: [TrainingPlanAdaptationRecord] {
        guard let activePlan else { return [] }
        let upcomingDayIds = Set(activePlan.days.filter { !$0.isCompleted }.map(\.id))
        return pendingAdaptations.filter {
            $0.planId == activePlan.id && upcomingDayIds.contains($0.dayId)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                planHero

                VStack(alignment: .leading, spacing: 14) {
                    VelaRhythmSectionHeader(
                        eyebrow: "",
                        title: "训练轮转",
                        actionTitle: nil,
                        action: {}
                    )
                    planRows
                }

                todayDecisionSection
                if !planAdaptations.isEmpty {
                    adaptationProposalsSection
                }
                coachActions
            }
            .padding(.horizontal, VelaTheme.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("训练计划")
        .velaRhythmDetailChrome()
        .task {
            fetchTodayOperatingPlan()
        }
        .onChange(of: dashboardVM.selectedDate) {
            fetchTodayOperatingPlan()
        }
    }

    private func fetchTodayOperatingPlan() {
        let identifier = DailyHealthSummaryRecord.dayIdentifier(
            for: dashboardVM.selectedDate,
            calendar: .current
        )
        var descriptor = FetchDescriptor<DailyOperatingPlanRecord>(
            predicate: #Predicate<DailyOperatingPlanRecord> { $0.dayIdentifier == identifier },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        todayOperatingPlan = (try? modelContext.fetch(descriptor))?.first
    }

    private var planHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(activePlan?.title ?? "建立可调整的训练轮转")
                .font(.system(.title, design: .default, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(VelaTheme.rhythmInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(planSummary)
                .font(.system(.footnote, design: .default))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .lineSpacing(3)

            HStack(spacing: 0) {
                planMetric("已完成", activePlan.map { "\($0.days.filter(\.isCompleted).count)" } ?? "—")
                metricDivider
                planMetric("训练日", activePlan.map { "\($0.days.count)" } ?? "—")
                metricDivider
                planMetric("周期", activePlan.map { "\($0.weeksCount) 周" } ?? "—")
            }
        }
        .padding(.vertical, 10)
        .background(alignment: .topTrailing) {
            RadialGradient(
                colors: [VelaTheme.rhythmGlow.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 170
            )
            .frame(width: 220, height: 190)
            .offset(x: 30, y: -30)
        }
    }

    @ViewBuilder
    private var planRows: some View {
        if let activePlan, !activePlan.days.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(activePlan.days.enumerated()), id: \.element.id) { index, day in
                    PlanDayRow(day: day, events: events)
                    if index < activePlan.days.count - 1 {
                        Rectangle()
                            .fill(VelaTheme.rhythmMist)
                            .frame(height: 0.75)
                            .padding(.leading, 59)
                    }
                }
            }
            .padding(.horizontal, 15)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(VelaTheme.rhythmDeep)
                Text("目前没有活动计划。Vela 可以根据恢复、目标与最近训练建立第一版。")
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .padding(16)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    /// 今天如何调整：优先展示当天正式决策（容量/RPE 边界 + 理由），
    /// 没有运营计划时退回恢复信号说明——不再是一句通用文案。
    private var todayDecisionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今天如何调整")
                .font(.system(.title3, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInk)

            Text(metricContextLine)
                .font(.system(.caption2, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let todayOperatingPlan, let payload = todayOperatingPlan.operatingPlanPayload {
                HStack(spacing: 8) {
                    Text(decisionLabel(payload.decision))
                        .font(.system(.caption, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeepOn)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(VelaTheme.rhythmDeep, in: Capsule())
                    Text(boundaryText(payload))
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }

                if !payload.summary.isEmpty {
                    Text(payload.summary)
                        .font(.system(.footnote, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                let reasons = todayOperatingPlan.operatingPlanReasons
                if !reasons.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(reasons.prefix(3).enumerated()), id: \.offset) { _, reason in
                            HStack(alignment: .top, spacing: 7) {
                                Circle()
                                    .fill(VelaTheme.rhythmDeep.opacity(0.6))
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 5)
                                Text(reason)
                                    .font(.system(.caption, design: .default))
                                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            } else {
                Text(adaptationText)
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(17)
        .background(VelaTheme.rhythmMist.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func decisionLabel(_ decision: DailyTrainingDecisionType) -> String {
        switch decision {
        case .keep: return "保持计划"
        case .reduce: return "建议减量"
        case .swap: return "建议换部位"
        case .rest: return "恢复优先"
        }
    }

    private func boundaryText(_ payload: DailyOperatingPlanPayload) -> String {
        guard payload.decision != .rest else { return "优先恢复 · 轻活动" }
        return "容量 \(Int((payload.volumeMultiplier * 100).rounded()))% · RPE ≤ \(payload.intensityCap)"
    }

    /// 算法打通（批次 B）：今日的 Vela 调整提案（BodyInterpreterEngine 产出）。
    /// 采纳 → 应用到计划；拒绝 → 标记 rejected。ADR 0008：任何计划修改由用户确认。
    private var adaptationProposalsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(planAdaptations) { adaptation in
                PlanProposalDiffCard(
                    originalTitle: adaptation.originalDayTitle,
                    adjustment: adaptation.adjustment,
                    reason: adaptation.reason,
                    suggestedAlternative: adaptation.suggestedAlternative,
                    status: adaptation.status,
                    planTitle: activePlan?.title,
                    onAccept: { acceptAdaptation(adaptation) },
                    onReject: { rejectAdaptation(adaptation) }
                )
            }
            Text("采纳后计划即时更新，今日决策面板将在下次刷新时重算。")
                .font(.system(.caption2, design: .default))
                .foregroundStyle(VelaTheme.meta)
                .padding(.leading, 4)
        }
    }

    private func acceptAdaptation(_ adaptation: TrainingPlanAdaptationRecord) {
        guard let activePlan else { return }
        if AdaptiveTrainingManager().applyAdaptation(adaptation, to: activePlan) {
            adaptation.status = AdaptationStatus.accepted.rawValue
            adaptation.acceptedAt = Date()
            try? modelContext.save()
            VelaAppState.shared.markLocalDataChanged()
        }
    }

    private func rejectAdaptation(_ adaptation: TrainingPlanAdaptationRecord) {
        adaptation.status = AdaptationStatus.rejected.rawValue
        adaptation.rejectedAt = Date()
        try? modelContext.save()
    }

    private func adaptationLabel(_ adjustment: String) -> String {
        switch adjustment {
        case "keep": return "保持"
        case "reduce": return "减量"
        case "swap": return "替换"
        case "rest": return "休息"
        case "reschedule": return "改期"
        case "deloadWeek": return "减载周"
        default: return adjustment
        }
    }

    private var coachActions: some View {
        VStack(spacing: 10) {
            Button {
                VelaAppState.shared.routeToCoach(question: coachPlanQuestion, surface: .plan)
            } label: {
                Label("和 Vela 调整计划", systemImage: "sparkles")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmDeepOn)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(VelaTheme.rhythmDeep, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.cardPress)

            Text("Vela 只提出方案；任何影响后续安排的修改都由你确认。")
                .font(.system(.caption2, design: .default))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var planSummary: String {
        guard let activePlan else {
            return "计划不是日历任务，而是背、胸、肩、腿与小肌群之间可移动的下一站。"
        }
        if !activePlan.goalDescription.isEmpty { return activePlan.goalDescription }
        return "保留训练方向，同时允许恢复、科研压力与临时有氧改变当天落点。"
    }

    /// 计划页发给 Coach 的问题：显式带上三指标与身体模型，避免 Agent
    /// 只看到计划文本、脱离当前身体证据。
    private var coachPlanQuestion: String {
        let dashboard = dashboardVM.dashboard
        let recovery = dashboard.recovery.hasData ? "\(Int(dashboard.recovery.score.rounded()))" : "--"
        let strain = dashboard.strain.hasData ? "\(Int(dashboard.strain.score.rounded()))" : "--"
        let stress = dashboard.stress.hasData ? "\(Int(dashboard.stress.stressIndex.rounded()))" : "--"
        return "请根据我最新的恢复 \(recovery)、负荷 \(strain)、压力 \(stress)、局部疲劳、身体模型与健康档案，提出未来一周训练轮转的调整方案；修改前先让我确认。"
    }

    /// 计划页的统一指标依据：恢复、负荷、压力直接来自 DashboardSummary，
    /// 与训练页状态卡和 TrainingDecisionKernel 同源。
    private var metricContextLine: String {
        let dashboard = dashboardVM.dashboard
        var parts: [String] = []
        if dashboard.recovery.hasData {
            parts.append("恢复 \(Int(dashboard.recovery.score.rounded()))")
        }
        if dashboard.strain.hasData {
            let range = dashboard.strain.recommendedRange
            parts.append("负荷 \(Int(dashboard.strain.score.rounded()))（目标 \(range.lowerBound)-\(range.upperBound)）")
        }
        if dashboard.stress.hasData {
            parts.append("压力 \(Int(dashboard.stress.stressIndex.rounded()))")
        }
        return parts.isEmpty ? "恢复、负荷与压力信号尚未同步，先使用保守训练窗口。" : "依据：" + parts.joined(separator: " · ")
    }

    private var adaptationText: String {
        let dashboard = dashboardVM.dashboard
        guard dashboard.recovery.hasData else {
            return "恢复信号尚未同步，无法给出个性化计划调整。先同步 Apple 健康，同时按保守窗口执行。"
        }
        let recovery = dashboard.recovery.score
        let stress = dashboard.stress.hasData ? Int(dashboard.stress.stressIndex.rounded()) : nil
        let loadHigh = dashboard.strain.hasData
            && dashboard.strain.score > Double(dashboard.strain.recommendedRange.upperBound)
        if recovery >= 70, (stress ?? 0) < 75, !loadHigh {
            return "恢复、压力与负荷支持保留计划方向。训练时按 Apple Watch 记录，容量与强度仍以身体边界为准。"
        }
        return "当前恢复/压力/负荷至少有一项不支持满量执行。建议保留训练习惯但降低容量，或换到疲劳更低的部位；如精神压力明显，恢复也算完成计划。"
    }

    private func planMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.caption2, design: .default, weight: .medium))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            Text(value)
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(VelaTheme.rhythmMist)
            .frame(width: 1, height: 32)
            .padding(.horizontal, 12)
    }
}

// MARK: - Expandable plan day row

/// 计划日行：点开看计划动作、实际执行记录与依从度——计划与事实的闭环。
private struct PlanDayRow: View {
    let day: TrainingDay
    let events: [WorkoutEventRecord]

    @State private var isExpanded = false

    private var plannedExercises: [WorkoutTemplateExercise] {
        guard let data = day.plannedExercisesJSON.data(using: .utf8),
              let list = try? JSONDecoder().decode([WorkoutTemplateExercise].self, from: data) else {
            return []
        }
        return list
    }

    private var linkedEvents: [WorkoutEventRecord] {
        events.filter { $0.linkedTrainingPlanDayId == day.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 13) {
                    ZStack {
                        Circle()
                            .fill(day.isCompleted ? VelaTheme.rhythmDeep : VelaTheme.rhythmMist)
                        if day.isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(day.dayNumber)")
                                .font(.system(.caption, design: .default, weight: .semibold))
                                .foregroundStyle(VelaTheme.rhythmInk)
                        }
                    }
                    .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(day.title)
                                .font(.system(.footnote, design: .default, weight: .semibold))
                                .foregroundStyle(VelaTheme.rhythmInk)
                                .lineLimit(1)

                            if day.isCompleted {
                                Text("已完成")
                                    .font(.system(.caption2, design: .default, weight: .semibold))
                                    .foregroundStyle(VelaTheme.rhythmDeep)
                            } else if let adherence = day.adherenceScore {
                                Text("依从 \(Int((adherence * 100).rounded()))%")
                                    .font(.system(.caption2, design: .default, weight: .semibold))
                                    .foregroundStyle(VelaTheme.rhythmDeep)
                            }
                        }

                        Text(day.description.isEmpty ? "边界会在训练当天根据状态调整" : day.description)
                            .font(.system(.caption2, design: .default))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Text(day.focus == "rest" ? "恢复" : "\(day.durationMinutes)′")
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.7))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 14, height: 14)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(day.title)，点按查看计划动作与实际执行")

            if isExpanded {
                expandedPanel
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            if !plannedExercises.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("计划动作")
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    ForEach(Array(plannedExercises.prefix(6).enumerated()), id: \.element.id) { index, exercise in
                        Text("• \(exercise.name) — \(exercise.targetSets) 组 × \(exercise.targetReps)")
                            .font(.system(.caption, design: .default, weight: .medium))
                            .foregroundStyle(VelaTheme.rhythmInk)
                    }
                    if plannedExercises.count > 6 {
                        Text("另有 \(plannedExercises.count - 6) 个动作")
                            .font(.system(.caption2, design: .default))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
            }

            if !linkedEvents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("实际执行")
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    ForEach(Array(linkedEvents.prefix(3).enumerated()), id: \.element.id) { _, event in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(VelaTheme.rhythmDeep)
                                .frame(width: 5, height: 5)
                            Text(eventText(event))
                                .font(.system(.caption, design: .default))
                                .foregroundStyle(VelaTheme.rhythmInk)
                        }
                    }
                }
            } else if !day.isCompleted {
                Text("还没有关联的实际训练记录。")
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }

            if day.isCompleted, let completedAt = day.completedAt {
                Text("完成于 \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(.caption2, design: .default, weight: .medium))
                    .foregroundStyle(VelaTheme.rhythmDeep)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmMist.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.leading, 47)
    }

    private func eventText(_ event: WorkoutEventRecord) -> String {
        let date = event.startedAt.formatted(date: .abbreviated, time: .shortened)
        let name = event.activityType.isEmpty ? "训练" : event.activityType
        return "\(date) · \(name)"
    }
}
