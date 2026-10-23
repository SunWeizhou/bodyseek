import BodySeekDomain
import SwiftData
import SwiftUI

// MARK: - Today score dashboard

/// The score-led opening of Today: one statement, the five independent scores
/// read against the person's own usual values, the canonical plan for today,
/// and one named recent change. Nothing here derives a score or a total.
struct TodaySignalGrid: View {
    let model: TodayExperienceModel
    let freshness: DataFreshness
    /// Score id → "低于平时" / "高于平时" / empty when notable without direction.
    let scoreDeviations: [String: String]
    let agentSentence: String
    var notableChangeText: String = ""
    var notableFinding: HealthTrendFinding? = nil
    let onInspectGuidance: () -> Void
    var onAsk: (String) -> Void = { _ in }
    var onOpenPlan: () -> Void = {}
    var onOpenTrends: () -> Void = {}
    let selectedDate: Date
    let dashboardSnapshot: DashboardSummary
    var planPayload: DailyOperatingPlanPayload? = nil
    var hasPendingProposal = false

    private var readings: [ScoreInstrumentReading] {
        ScoreInstrumentReading.make(
            cardValues: Dictionary(uniqueKeysWithValues: model.signalCards.map { ($0.id, $0.value) }),
            deviations: scoreDeviations,
            findings: dashboardSnapshot.healthTrends
        )
    }

    var body: some View {
        let readings = readings
        return VStack(alignment: .leading, spacing: 16) {
            statement(readings)
            TodayScoreInstrument(
                readings: readings,
                selectedDate: selectedDate,
                dashboardSnapshot: dashboardSnapshot
            )
            TodayPlanSection(
                payload: planPayload,
                fallback: model.actions.first,
                selectedDate: selectedDate,
                hasPendingProposal: hasPendingProposal,
                onOpenPlan: onOpenPlan,
                onInspectGuidance: onInspectGuidance,
                onAsk: onAsk
            )
            recentChangeCard
        }
    }

    // MARK: Statement

    private var stampText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        let day = formatter.string(from: selectedDate)
        let time = model.generatedAt.formatted(date: .omitted, time: .shortened)
        return "\(day) · \(time) 更新"
    }

    private func statement(_ readings: [ScoreInstrumentReading]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(stampText)
                    .font(VelaTheme.caption1())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                Spacer(minLength: 8)
                if dashboardSnapshot.source == .preview {
                    Text("示例数据")
                        .font(VelaTheme.caption2().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().stroke(VelaTheme.hairline, lineWidth: 1))
                } else if freshness == .missing || freshness == .stale {
                    Text(freshness == .missing ? "未同步" : "数据较旧")
                        .font(VelaTheme.caption2().weight(.semibold))
                        .foregroundStyle(VelaTheme.deviationInk)
                }
            }
            Text(agentSentence)
                .font(VelaTheme.statement())
                .foregroundStyle(VelaTheme.rhythmInk)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.comparisonLine(readings, formation: model.baselineFormation))
                .font(VelaTheme.subheadline())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-guidance")
    }

    /// Restates only the published deviation flags; it never ranks or totals.
    static func comparisonLine(
        _ readings: [ScoreInstrumentReading],
        formation: PersonalBaselineFormation
    ) -> String {
        let present = readings.filter { $0.value != nil }
        guard !present.isEmpty else { return "今天的数据还没有同步，五项暂显示 --。" }
        if !present.contains(where: { $0.baseline != nil || $0.isUnusual }) {
            switch formation.phase {
            case .learning:
                return "初始基线 \(formation.observedDays)/\(formation.requiredDays) 天，先看今天的读数。"
            case .waitingForEvidence, .ready:
                return "个人基线还在建立，先看今天的读数。"
            }
        }
        let unusual = present.filter(\.isUnusual)
        let comparable = present.filter { !$0.isUnusual && $0.baseline != nil }
        let forming = present.filter { !$0.isUnusual && $0.baseline == nil }
        var parts: [String] = []
        if !unusual.isEmpty {
            parts.append(unusual.map { reading in
                let label = reading.caption.split(separator: " ").first.map(String.init) ?? BaselineDeviationCopy.unusualFallback
                return "\(reading.title)\(label)"
            }.joined(separator: "、"))
        }
        if !comparable.isEmpty {
            if unusual.isEmpty && forming.isEmpty && comparable.count == readings.count {
                parts.append("五项都在你的平时范围内")
            } else if unusual.isEmpty {
                parts.append("\(comparable.map(\.title).joined(separator: "、"))接近平时")
            } else {
                parts.append("其余接近平时")
            }
        }
        if !forming.isEmpty {
            parts.append("\(forming.map(\.title).joined(separator: "、"))基线建立中")
        }
        if present.count < readings.count {
            let missing = readings.filter { $0.value == nil }.map(\.title).joined(separator: "、")
            parts.append("\(missing)暂无数据")
        }
        return parts.joined(separator: "，") + "。"
    }

    // MARK: Recent change

    private var recentChangeTitle: String {
        guard let finding = notableFinding else { return "最近变化" }
        return "最近变化 · \(finding.horizon.title)"
    }

    private var recentChangeBody: String {
        if !notableChangeText.isEmpty { return notableChangeText }
        let available = dashboardSnapshot.healthTrends.filter {
            $0.horizon == .thirtyDays && $0.metric.todayScoreRingID != nil && $0.isAvailable
        }
        if available.isEmpty {
            return "记录还不够判断长期变化，趋势页会显示每项的有效天数。"
        }
        return "近 30 天没有越过你常见范围的变化。"
    }

    private var recentChangeCard: some View {
        Button(action: onOpenTrends) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: notableFinding == nil ? "waveform.path" : "arrow.up.and.down.text.horizontal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(notableFinding == nil ? VelaTheme.rhythmInkSecondary : VelaTheme.deviationInk)
                    .frame(width: 32, height: 32)
                    .background(
                        (notableFinding == nil ? VelaTheme.rhythmMist.opacity(0.6) : VelaTheme.deviationWash),
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(recentChangeTitle)
                        .font(VelaTheme.caption1().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    Text(recentChangeBody)
                        .font(VelaTheme.subheadline())
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.55))
            }
            .padding(14)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                    .stroke(VelaTheme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.cardPress)
        .accessibilityIdentifier("today-recent-change")
        .accessibilityHint("打开趋势")
    }
}

// MARK: - Today plan

/// Today renders the same persisted Daily Operating Plan as Plan. Checking an
/// action here writes through `DailyOperatingPlanEditor`, exactly like Plan.
/// Without a stored plan yet, the local recommendation is shown as a preview
/// of what Plan will create.
struct TodayPlanSection: View {
    let payload: DailyOperatingPlanPayload?
    let fallback: TodayExperienceAction?
    let selectedDate: Date
    var hasPendingProposal = false
    let onOpenPlan: () -> Void
    let onInspectGuidance: () -> Void
    let onAsk: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var localPayload: DailyOperatingPlanPayload?
    @State private var saveError: String?
    @State private var showAllActions = false

    private var shownPayload: DailyOperatingPlanPayload? { localPayload ?? payload }
    private var actions: [DailyOperatingPlanAction] { shownPayload?.allActions ?? [] }
    private var completed: Int { actions.filter { $0.completedAt != nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)

            if hasPendingProposal {
                Button(action: onOpenPlan) {
                    HStack(spacing: 8) {
                        Circle().fill(VelaTheme.deviationInk).frame(width: 7, height: 7)
                        Text("状态有变化，有一份调整建议待你确认")
                            .font(VelaTheme.footnote().weight(.semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(VelaTheme.deviationInk)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(VelaTheme.deviationWash, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .accessibilityIdentifier("today-plan-proposal")
            }

            if !actions.isEmpty {
                let visibleActions = showAllActions ? actions : Array(actions.filter { $0.completedAt == nil }.prefix(1))
                ForEach(Array(visibleActions.enumerated()), id: \.element.id) { index, action in
                    if index > 0 {
                        Divider().overlay(VelaTheme.rhythmMist).padding(.leading, 56)
                    }
                    actionRow(action, isPrimary: action.id == actions.first?.id)
                }
                if actions.count > 1 || completed > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { showAllActions.toggle() }
                    } label: {
                        HStack {
                            Text(showAllActions ? "收起安排" : completed == actions.count ? "查看已完成的 \(completed) 项安排" : "查看全部 \(actions.count) 项 · 已完成 \(completed) 项")
                            Spacer()
                            Image(systemName: showAllActions ? "chevron.up" : "chevron.down")
                        }
                        .font(VelaTheme.footnote()).frame(minHeight: 44)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today-plan-disclosure")
                }
            } else if let fallback {
                fallbackRow(fallback)
            } else {
                Text("今天还没有安排，打开计划添加一项真正有帮助的行动。")
                    .font(VelaTheme.subheadline())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }

            if let saveError {
                Text(saveError)
                    .font(VelaTheme.caption1())
                    .foregroundStyle(VelaTheme.deviationInk)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .accessibilityIdentifier("today-plan-save-error")
            }

            Divider().overlay(VelaTheme.rhythmMist).padding(.top, 4)
            footer
        }
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: 1)
        }
        .onChange(of: payload) { _, _ in localPayload = nil }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-advice-panel")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(shownPayload?.allActionsCompleted == true ? "今天的安排已完成" : "今天的安排")
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.rhythmInk)
                .accessibilityIdentifier(shownPayload?.allActionsCompleted == true ? "today-plan-finished" : "today-plan-title")
            Spacer(minLength: 8)
            if !actions.isEmpty {
                Text("\(completed)/\(actions.count)")
                    .font(VelaTheme.subheadline().monospacedDigit())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .accessibilityLabel("已完成 \(completed) 项，共 \(actions.count) 项")
                    .padding(.trailing, 6)
            }
            Button(action: onOpenPlan) {
                HStack(spacing: 3) {
                    Text(actions.isEmpty ? "打开计划" : "编辑")
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                }
                .font(VelaTheme.subheadline().weight(.medium))
                .foregroundStyle(VelaTheme.rhythmInk)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today-open-plan")
        }
    }

    private func actionRow(_ action: DailyOperatingPlanAction, isPrimary: Bool) -> some View {
        let done = action.completedAt != nil
        return HStack(alignment: .top, spacing: 12) {
            Button {
                toggle(action)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(done ? Color.clear : VelaTheme.rhythmInk.opacity(0.55), lineWidth: 1.5)
                        .background(Circle().fill(done ? VelaTheme.rhythmInk : Color.clear))
                        .frame(width: 26, height: 26)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmCanvas)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(shownPayload == nil || payload == nil)
            .accessibilityLabel(done ? "标记“\(action.title)”为未完成" : "完成“\(action.title)”")
            .accessibilityIdentifier("today-plan-toggle-\(action.domain.rawValue)")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(action.title)
                        .font(VelaTheme.subheadline().weight(.semibold))
                        .foregroundStyle(done ? VelaTheme.rhythmInkSecondary : VelaTheme.rhythmInk)
                        .strikethrough(done, color: VelaTheme.rhythmInkSecondary)
                    if isPrimary && !done {
                        Text("重点")
                            .font(VelaTheme.caption2().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().stroke(VelaTheme.hairline, lineWidth: 1))
                    }
                }
                if !done, !action.detail.isEmpty {
                    Text(action.detail)
                        .font(VelaTheme.footnote())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 6)
        .padding(.trailing, 16)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isPrimary ? "today-next-action" : "today-plan-action")
    }

    private func fallbackRow(_ action: TodayExperienceAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(action.title)
                .font(VelaTheme.subheadline().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
            if !action.detail.isEmpty {
                Text(action.detail)
                    .font(VelaTheme.footnote())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("打开计划后会保存为今天的安排，你可以随时修改。")
                .font(VelaTheme.caption1())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityIdentifier("today-next-action")
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button(action: onInspectGuidance) {
                Label("为什么这样安排", systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("today-advice-evidence")
            Rectangle().fill(VelaTheme.rhythmMist).frame(width: 1, height: 20)
            Button {
                onAsk("结合我今天的五项状态，帮我看看今天的安排是否合适，需要怎样调整。")
            } label: {
                Label("和 BodySeek 商量", systemImage: "bubble.left")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("today-plan-ask")
        }
        .font(VelaTheme.footnote().weight(.medium))
        .foregroundStyle(VelaTheme.rhythmInk)
        .buttonStyle(.plain)
        .labelStyle(.titleAndIcon)
    }

    private func toggle(_ action: DailyOperatingPlanAction) {
        guard let current = shownPayload else { return }
        let dayIdentifier = DailyHealthSummaryRecord.dayIdentifier(for: selectedDate)
        do {
            guard let record = try DailyOperatingPlanRepository(modelContext: modelContext)
                .fetchLatest(dayIdentifier: dayIdentifier) else {
                saveError = "今天的计划还没有保存，请先打开计划。"
                return
            }
            let updated = DailyOperatingPlanEditor.applying(
                .toggleCompletion(actionID: action.id, at: Date()),
                to: record.operatingPlanPayload ?? current
            )
            try DailyOperatingPlanEditor.persist(updated, to: record, modelContext: modelContext)
            localPayload = updated
            saveError = nil
            if action.completedAt == nil { VelaHaptic.success() } else { VelaHaptic.selection() }
            VelaAppState.shared.markLocalDataChanged()
        } catch {
            saveError = "完成状态未保存：\(error.localizedDescription)"
        }
    }
}

// MARK: - Equatable Breakers
//
// The Today scroll container re-evaluates its body on every frame while
// scrolling. These conformances let SwiftUI skip rebuilding the card subtree
// when its inputs are unchanged.
extension TodaySignalGrid: Equatable {
    nonisolated static func == (lhs: TodaySignalGrid, rhs: TodaySignalGrid) -> Bool {
        lhs.model.signalCards == rhs.model.signalCards
            && lhs.model.baselineFormation == rhs.model.baselineFormation
            && lhs.model.actions == rhs.model.actions
            && lhs.freshness == rhs.freshness
            && lhs.scoreDeviations == rhs.scoreDeviations
            && lhs.agentSentence == rhs.agentSentence
            && lhs.notableChangeText == rhs.notableChangeText
            && lhs.dashboardSnapshot.healthTrends == rhs.dashboardSnapshot.healthTrends
            && lhs.dashboardSnapshot.source == rhs.dashboardSnapshot.source
            && lhs.planPayload == rhs.planPayload
            && lhs.hasPendingProposal == rhs.hasPendingProposal
            && lhs.selectedDate == rhs.selectedDate
    }
}
