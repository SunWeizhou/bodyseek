import BodySeekDomain
import SwiftUI

// MARK: - Today score dashboard

/// The score-led opening of Today: byline + one decision line, one hero score,
/// a compact four-score support strip, one named recent change, two follow-up
/// chips, then a single-line next action. Nothing here derives a score or total.
struct TodaySignalGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        let heroID = Self.primaryReadingID(readings: readings, statement: agentSentence)
        return VStack(alignment: .leading, spacing: 0) {
            statement(readings)
                .padding(.bottom, 18)
            TodayScoreInstrument(
                readings: readings,
                heroID: heroID,
                selectedDate: selectedDate,
                dashboardSnapshot: dashboardSnapshot
            )
            recentChangeRow
                .padding(.top, 16)
            followUpChips(readings)
                .padding(.top, 14)
            TodayPlanSection(
                payload: planPayload,
                fallback: model.actions.first,
                selectedDate: selectedDate,
                hasPendingProposal: hasPendingProposal,
                onOpenPlan: onOpenPlan,
                onInspectGuidance: onInspectGuidance,
                onAsk: onAsk
            )
            .padding(.top, 14)
        }
    }

    /// The score the first fold leads with. It prefers the metric the Agent
    /// statement already names, then a notable deviation, then the first
    /// reading with data. Display-only: it never re-ranks or re-scores anything.
    static func primaryReadingID(readings: [ScoreInstrumentReading], statement: String) -> String {
        let present = readings.filter { $0.value != nil }
        guard !present.isEmpty else { return readings.first?.id ?? "recovery" }
        let named = present.filter { statement.contains($0.title) }
        let candidates = named.isEmpty ? present : named
        return (candidates.first(where: \.isUnusual) ?? candidates[0]).id
    }

    /// Presentation-only split of the generated statement: the leading clause
    /// and the decision clause stay on the fold; the baseline / median clauses
    /// drop to one supporting caption. Copy generation itself is untouched.
    static func statementParts(_ sentence: String) -> (lead: String, support: String?) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", nil) }
        let withoutPeriod = trimmed.hasSuffix("。") ? String(trimmed.dropLast()) : trimmed
        let clauses = withoutPeriod
            .split(separator: "，", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard clauses.count > 1 else { return (trimmed, nil) }

        let decisionMarkers = ["建议", "不必", "需要调整", "要调整", "优先恢复"]
        let decisionIndex = clauses.indices.reversed().first { index in
            index > 0 && decisionMarkers.contains { clauses[index].contains($0) }
        }
        let leadIndexes = decisionIndex.map { [0, $0] } ?? [0]
        let lead = leadIndexes.map { clauses[$0] }.joined(separator: "，") + "。"
        let support = clauses.enumerated()
            .filter { !leadIndexes.contains($0.offset) }
            .map(\.element)
        return (lead, support.isEmpty ? nil : support.joined(separator: "，") + "。")
    }

    /// One quiet caption under the decision line: the deferred statement clauses
    /// plus the baseline comparison, without a gray copy wall on the fold.
    static func supportingCaption(support: String?, comparison: String) -> String {
        func trimmed(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "。"))
        }
        var pieces: [String] = []
        if let support, !trimmed(support).isEmpty { pieces.append(trimmed(support)) }
        if !trimmed(comparison).isEmpty { pieces.append(trimmed(comparison)) }
        return pieces.isEmpty ? "" : pieces.joined(separator: " · ") + "。"
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
                // Presentation only: two primary questions stay on the fold; the
                // third is retained in the suggestion generator but not shown.
                CoachFollowUpChipsView(suggestions: Array(suggestions.prefix(2)), wraps: true) { question in
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
        let parts = Self.statementParts(agentSentence)
        let caption = readings.contains { $0.value != nil }
            ? Self.supportingCaption(
                support: parts.support,
                comparison: Self.comparisonLine(readings, formation: model.baselineFormation)
            )
            : "同步 Apple 健康后再查看读数；已保存的安排仍会保留。"
        return VStack(alignment: .leading, spacing: 8) {
            bylineRow
            Text(parts.lead)
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.rhythmInk)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
            if !caption.isEmpty {
                Text(caption)
                    .font(VelaTheme.caption1())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-guidance")
    }

    private var bylineRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(VelaTheme.rhythmInk)
                    .frame(width: 7, height: 7)
                Text(bylineText)
                    .font(VelaTheme.caption1())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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

    /// One quiet navigation row: the change headline is already on the fold, so
    /// this stays a caption-weight line instead of a second gray card.
    private var recentChangeRow: some View {
        Button(action: onOpenTrends) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: notableFinding == nil ? "waveform.path" : "arrow.up.and.down.text.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(notableFinding == nil ? VelaTheme.rhythmInkSecondary : VelaTheme.deviationInk)
                Text(recentChangeTitle)
                    .font(VelaTheme.caption1().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .fixedSize(horizontal: true, vertical: false)
                Text(recentChangeBody)
                    .font(VelaTheme.footnote())
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.55))
            }
            .frame(minHeight: VelaTheme.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(VelaTheme.hairline)
                .frame(height: VelaTheme.hairlineWidth)
            HStack(spacing: 10) {
                Button(action: onOpenPlan) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hasPendingProposal ? "待确认" : "下一件")
                                .font(VelaTheme.caption2().weight(.semibold))
                                .foregroundStyle(hasPendingProposal ? VelaTheme.deviationInk : VelaTheme.rhythmInkSecondary)
                                .accessibilityIdentifier(
                                    payload?.allActionsCompleted == true ? "today-plan-finished" : "today-plan-title"
                                )
                            Text(nextActionTitle)
                                .font(VelaTheme.callout().weight(.semibold))
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
                    .frame(minHeight: VelaTheme.minimumHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today-open-plan")
                .accessibilityHint("打开计划查看全部安排")

                Button(action: onInspectGuidance) {
                    Text("依据")
                        .font(VelaTheme.caption1().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .padding(.horizontal, 12)
                        .frame(minHeight: VelaTheme.minimumHitTarget)
                        .background(Capsule().stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today-advice-evidence")
                .accessibilityLabel("为什么这样安排")
            }
            .padding(.horizontal, 2)
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
