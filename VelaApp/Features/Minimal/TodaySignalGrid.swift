import BodySeekDomain
import SwiftUI

// MARK: - Today score dashboard

/// The score-led opening of Today: Agent body, equal-width five-score strip,
/// one named recent change, follow-up chips, then a one-line next action.
/// Nothing here derives a score or a total.
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
            recentChangeCard
            followUpChips(readings)
            TodayPlanSection(
                payload: planPayload,
                fallback: model.actions.first,
                selectedDate: selectedDate,
                hasPendingProposal: hasPendingProposal,
                onOpenPlan: onOpenPlan,
                onInspectGuidance: onInspectGuidance,
                onAsk: onAsk
            )
        }
    }

    private func followUpChips(_ readings: [ScoreInstrumentReading]) -> some View {
        let suggestions = BodySeekAskSuggestions.make(
            surface: .home,
            readings: readings,
            nextActionTitle: planPayload?.allActions.first(where: { $0.completedAt == nil })?.title
                ?? model.actions.first?.title,
            hasPendingProposal: hasPendingProposal
        )
        return Group {
            if !suggestions.isEmpty {
                CoachFollowUpChipsView(suggestions: suggestions, wraps: true) { question in
                    onAsk(question)
                }
                .accessibilityIdentifier("today-follow-up-chips")
            }
        }
    }

    // MARK: Statement

    private var bylineText: String {
        let time = model.generatedAt.formatted(date: .omitted, time: .shortened)
        return "BodySeek · \(time)"
    }

    private func statement(_ readings: [ScoreInstrumentReading]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(VelaTheme.rhythmInk)
                        .frame(width: 7, height: 7)
                    Text(bylineText)
                        .font(VelaTheme.caption1())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                .accessibilityIdentifier("today-agent-byline")
                Spacer(minLength: 8)
                if dashboardSnapshot.source == .preview {
                    Text("示例数据")
                        .font(VelaTheme.caption2().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                } else if freshness == .missing || freshness == .stale {
                    Text(freshness == .missing ? "未同步" : "数据较旧")
                        .font(VelaTheme.caption2().weight(.semibold))
                        .foregroundStyle(VelaTheme.deviationInk)
                }
            }
            Text(agentSentence)
                .font(VelaTheme.briefBody())
                .foregroundStyle(VelaTheme.rhythmInk)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.comparisonLine(readings, formation: model.baselineFormation))
                .font(VelaTheme.footnote())
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
                    .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.cardPress)
        .accessibilityIdentifier("today-recent-change")
        .accessibilityHint("打开趋势")
    }
}

// MARK: - Today plan

/// Today only shows the next action. Completing, editing, and the full list
/// live on Plan so the first screen stays Agent → five scores → chips.
struct TodayPlanSection: View {
    let payload: DailyOperatingPlanPayload?
    let fallback: TodayExperienceAction?
    let selectedDate: Date
    var hasPendingProposal = false
    let onOpenPlan: () -> Void
    let onInspectGuidance: () -> Void
    let onAsk: (String) -> Void

    private var actions: [DailyOperatingPlanAction] { payload?.allActions ?? [] }
    private var nextActionTitle: String {
        if let next = actions.first(where: { $0.completedAt == nil })?.title {
            return next
        }
        if payload?.allActionsCompleted == true, !actions.isEmpty {
            return "今天的安排已完成"
        }
        return fallback?.title ?? "打开计划添加一项安排"
    }

    var body: some View {
        let _ = (selectedDate, onAsk)
        HStack(spacing: 8) {
            Button(action: onOpenPlan) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hasPendingProposal ? "今天的安排 · 待确认" : "今天的安排 · 下一件")
                            .font(VelaTheme.caption1().weight(.semibold))
                            .foregroundStyle(hasPendingProposal ? VelaTheme.deviationInk : VelaTheme.rhythmInkSecondary)
                            .accessibilityIdentifier(
                                payload?.allActionsCompleted == true ? "today-plan-finished" : "today-plan-title"
                            )
                        Text(nextActionTitle)
                            .font(VelaTheme.subheadline().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .accessibilityIdentifier("today-next-action")
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.55))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today-open-plan")
            .accessibilityHint("打开计划查看全部安排")

            Button(action: onInspectGuidance) {
                Text("依据")
                    .font(VelaTheme.footnote().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(Capsule().stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today-advice-evidence")
            .accessibilityLabel("为什么这样安排")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-advice-panel")
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
