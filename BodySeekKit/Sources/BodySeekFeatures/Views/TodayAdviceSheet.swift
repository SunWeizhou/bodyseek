import BodySeekAgent
import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

/// 今日建议 sheet（UI v4 §2.2）：建议标题与一段话、行动框（加入计划 / 撤销）、查看依据、最近的变化、简报反馈。
struct TodayAdviceSheet: View {
    @Bindable var store: StoreOf<TodayFeature>
    @Environment(\.dismiss) private var dismiss

    /// 行动框里的行动条数，用于入口标签。
    @MainActor
    static func actionCount(store: StoreOf<TodayFeature>) -> Int {
        if store.postWorkoutAdvice != nil { return 0 }
        let plan = store.planItems.filter { $0.state != .dismissed }.count
        if plan > 0 { return Swift.min(plan, Self.maxActions) }
        return Swift.min(store.dailyBrief?.actions.count ?? 0, Self.maxActions)
    }

    private static let maxActions = 3

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSSpace.l) {
                    headlineBlock
                    actionBlock
                    evidenceBlock
                    changesBlock
                    feedbackBlock
                }
                .padding(BSSpace.m)
            }
            .background(BSColor.canvas)
            .navigationTitle("今日建议")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("today-advice-done")
                }
            }
        }
    }

    // MARK: - 标题与一段话

    private var headlineBlock: some View {
        BSCoachNote(
            noteText,
            engine: noteEngine,
            evidence: [],
            onAsk: askCoach,
            askIdentifier: "today-ask-coach-button"
        )
    }

    private var askCoach: () -> Void {
        {
            dismiss()
            store.send(.askCoachTapped("结合我今天的恢复、睡眠、训练负荷和近期饮食，给一个具体安排"))
        }
    }

    private var noteText: String {
        if let brief = store.dailyBrief { return brief.headline }
        if !store.snapshot.isAuthorized { return "授权 Apple 健康后即可生成今日结论。" }
        if let advice = store.postWorkoutAdvice { return advice }
        let summary = store.today.factualSummary
        return summary.isEmpty ? "同步 HRV、静息心率与睡眠样本后将给出今日结论。" : summary
    }

    private var noteEngine: BSBriefEngine {
        switch store.dailyBrief?.engine {
        case .cloud: .cloud
        case .onDevice: .onDevice
        case .localTemplate, .none: .localTemplate
        }
    }

    // MARK: - 行动框

    private var actionBlock: some View {
        BSSection("今天要不要行动") {
            VStack(spacing: BSSpace.s) {
                actionRows
                checkInRow
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today-action-card")
        }
    }

    @ViewBuilder
    private var actionRows: some View {
        if let advice = store.postWorkoutAdvice {
            postWorkoutCard(advice)
        } else if !visiblePlanItems.isEmpty {
            ForEach(visiblePlanItems) { record in
                planRow(record)
            }
        } else {
            ForEach(briefActions) { action in
                briefActionRow(action)
            }
        }
    }

    private var visiblePlanItems: [PlanItemRecord] {
        let items = store.planItems.filter { $0.state != .dismissed }
        let focus = items.filter { $0.kind == .trainingFocus }
        let rest = items.filter { $0.kind != .trainingFocus }
        return Array((focus + rest).prefix(Self.maxActions))
    }

    private var briefActions: [BriefAction] {
        Array((store.dailyBrief?.actions ?? []).prefix(Self.maxActions))
    }

    private func postWorkoutCard(_ advice: String) -> some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.xxs) {
                Label("今天已完成训练", systemImage: "checkmark.circle")
                    .bsText(.cardTitle)
                Text(advice)
                    .bsText(.label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func planRow(_ record: PlanItemRecord) -> some View {
        let item = record.decodedActionItem()
        let identifier = record.id.uuidString
        return BSActionRow(
            title: item?.title ?? "行动建议",
            basis: [item?.detail, item?.metricBasis].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n"),
            status: record.state == .suggested ? .idle : .done,
            actionTitle: "加入计划",
            onExecute: { store.send(.adoptPlanItem(record.id)) },
            dismissTitle: "跳过",
            onDismiss: { store.send(.dismissPlanItem(record.id)) },
            executeIdentifier: "today-action-adopt-\(identifier)",
            statusIdentifier: "today-action-status-\(identifier)",
            dismissIdentifier: "today-action-dismiss-\(identifier)"
        )
    }

    private func briefActionRow(_ action: BriefAction) -> some View {
        BSActionRow(
            title: action.title,
            basis: action.basis,
            actionTitle: "问 Coach",
            onExecute: {
                dismiss()
                store.send(.askCoachTapped(action.coachPrompt))
            }
        )
    }

    private var checkInRow: some View {
        let recorded = store.todayCheckIn != nil
        return BSActionRow(
            title: recorded ? "今日体感已记录" : "记录今日体感",
            basis: checkInBasis,
            actionTitle: recorded ? "修改" : "打卡",
            onExecute: {
                dismiss()
                store.send(.openCheckInTapped)
            },
            executeIdentifier: "today-checkin-card"
        )
    }

    private var checkInBasis: String {
        guard let checkIn = store.todayCheckIn else {
            return "10 秒量化主观精力、情绪、压力与酸痛，持续校准个人身体模型"
        }
        let soreness = checkIn.soreness.isEmpty ? "" : " · 酸痛 \(checkIn.soreness.count) 处"
        return "精力 \(checkIn.energy)/5 · 情绪 \(checkIn.mood)/5 · 压力 \(checkIn.stress)/5\(soreness)"
    }

    // MARK: - 依据与变化

    @ViewBuilder
    private var evidenceBlock: some View {
        if let brief = store.dailyBrief, !brief.evidence.isEmpty {
            BSCard {
                DisclosureGroup("查看依据") {
                    VStack(alignment: .leading, spacing: BSSpace.xs) {
                        Text("数据日期 \(brief.dayKey.isoString)")
                            .bsText(.caption)
                        ForEach(brief.evidence, id: \.identifier) { item in
                            Text(item.summary)
                                .bsText(.label)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, BSSpace.xs)
                }
                .accessibilityIdentifier("today-advice-evidence")
            }
        }
    }

    @ViewBuilder
    private var changesBlock: some View {
        if let brief = store.dailyBrief, !brief.changes.isEmpty {
            BSSection("最近的变化") {
                BSCard {
                    VStack(alignment: .leading, spacing: BSSpace.s) {
                        ForEach(brief.changes) { change in
                            VStack(alignment: .leading, spacing: BSSpace.xxs) {
                                Text(change.title)
                                    .bsText(.cardTitle)
                                Text(change.detail)
                                    .bsText(.label)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackBlock: some View {
        if store.dailyBrief != nil {
            BriefFeedbackBar(selected: store.briefFeedback) { rating in
                store.send(.briefFeedbackTapped(rating))
            }
        }
    }
}
