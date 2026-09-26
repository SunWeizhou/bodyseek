import SwiftUI

// MARK: - Today score dashboard

/// The score-led opening of Today. The hierarchy is deliberately stable:
/// Recovery / Sleep / Strain are always primary, while Stress / Energy are
/// always secondary. Baseline deviation adds emphasis without reordering.
struct TodaySignalGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: TodayExperienceModel
    let freshness: DataFreshness
    let deviatedScoreIDs: Set<String>
    let agentSentence: String
    let accentColor: (DailyPlanAccent) -> Color
    let onInspectGuidance: () -> Void
    var selectedDate: Date? = nil
    var dashboardSnapshot: DashboardSummary? = nil

    /// The Today contract has five independent metrics. Keep the descriptor
    /// list at the rendering boundary so a partial/legacy payload cannot make
    /// a metric disappear from the dashboard. Missing cards are represented by
    /// an explicit `--` value; no score or aggregate is fabricated.
    private struct SignalDescriptor {
        let id: String
        let title: String
        let accent: DailyPlanAccent
    }

    private static let requiredSignals = [
        SignalDescriptor(id: "recovery", title: "恢复", accent: .recovery),
        SignalDescriptor(id: "sleep", title: "睡眠", accent: .sleep),
        SignalDescriptor(id: "strain", title: "负荷", accent: .strain),
        SignalDescriptor(id: "stress", title: "压力", accent: .stress),
        SignalDescriptor(id: "energy", title: "能量", accent: .energy)
    ]

    private var primaryDescriptors: ArraySlice<SignalDescriptor> {
        Self.requiredSignals.prefix(3)
    }

    private var primaryCards: [TodayExperienceSignalCard] {
        primaryDescriptors.map(card(for:))
    }

    private var stressCard: TodayExperienceSignalCard {
        card(for: Self.requiredSignals[3])
    }

    private var energyCard: TodayExperienceSignalCard {
        card(for: Self.requiredSignals[4])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            primaryScores
            secondaryScores
            agentGuidance
        }
    }

    private var showsBaselineContext: Bool {
        switch model.baselineFormation.phase {
        case .waitingForEvidence, .learning:
            return true
        case .ready:
            return !deviatedScoreIDs.isEmpty
        }
    }

    @ViewBuilder
    private var baselineContext: some View {
        switch model.baselineFormation.phase {
        case .waitingForEvidence:
            baselineLearningRow(label: "初始基线 · 等待数据")
        case .learning:
            baselineLearningRow(
                label: "初始基线 · \(model.baselineFormation.observedDays)/\(model.baselineFormation.requiredDays) 天"
            )
        case .ready:
            if !deviatedScoreIDs.isEmpty {
                HStack(spacing: 8) {
                    Circle()
                        .fill(VelaTheme.stressColor)
                        .frame(width: 8, height: 8)
                    Text("\(deviatedScoreIDs.count) 项偏离个人基线")
                        .font(VelaTheme.subheadline())
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("发现 \(deviatedScoreIDs.count) 项个人基线偏离；这表示对你而言不寻常，不等同于医学异常")
            }
        }
    }

    private func baselineLearningRow(label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "hourglass")
                    .font(VelaTheme.subheadline())
                    .foregroundStyle(VelaTheme.rhythmDeep)
                Text(label)
                    .font(VelaTheme.subheadline())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                    ProgressView(value: model.baselineFormation.progress)
                        .tint(VelaTheme.rhythmDeep)
                        .frame(width: 60)
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                ProgressView(value: model.baselineFormation.progress)
                    .tint(VelaTheme.rhythmDeep)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("初始个人基线已记录 \(model.baselineFormation.observedDays) 个有效日，共需 \(model.baselineFormation.requiredDays) 天；每项分数仍按自己的有效数据独立启用")
    }

    private var primaryScores: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text("身体状态")
                    .font(VelaTheme.title1())
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                DataFreshnessIndicator(freshness: freshness, showText: false)
            }
            scoreCollection(primaryCards, ringSize: 92)
            if showsBaselineContext {
                baselineContext
            }
        }
        .padding(.vertical, 8)
    }

    private var shouldUseStackedSecondaryLayout: Bool {
        dynamicTypeSize.isAccessibilitySize || dynamicTypeSize >= .xxLarge
    }

    private var secondaryScores: some View {
        VStack(alignment: .leading, spacing: 12) {
            if shouldUseStackedSecondaryLayout {
                VStack(spacing: 12) {
                    stressPanel(stressCard)
                    energyPanel(energyCard)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    stressPanel(stressCard)
                    energyPanel(energyCard)
                }
            }
        }
    }

    private func stressPanel(_ card: TodayExperienceSignalCard) -> some View {
        NavigationLink {
            VelaMetricDetailView(
                metric: .stress,
                selectedDate: selectedDate,
                dashboardSnapshot: dashboardSnapshot,
                isPresentedInSheet: false
            )
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(card.title)
                        .font(VelaTheme.subheadline().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .lineLimit(1)
                    if deviatedScoreIDs.contains(card.id) {
                        Circle()
                            .fill(accentColor(card.accent))
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 2)
                    stressValue(card)
                    metricChevron
                }

                VStack(alignment: .leading, spacing: 4) {
                    TodayStressGauge(
                        value: Double(card.value),
                        color: accentColor(card.accent)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)

                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .contentShape(Rectangle())
            .todayDashboardCard(radius: VelaTheme.radiusCardStandard, depth: .standard)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-secondary-stress")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(secondaryAccessibilityLabel(card))
        .accessibilityHint("查看压力的时间变化和依据")
    }

    private func stressValue(_ card: TodayExperienceSignalCard) -> some View {
        Text(card.value)
            .font(VelaTheme.title2().monospacedDigit())
            .foregroundStyle(VelaTheme.rhythmInk)
            .lineLimit(1)
    }

    private func stressStateLabel(for state: MetricState) -> String {
        switch state {
        case .good: return "低"
        case .moderate: return "适中"
        case .poor: return "高"
        }
    }

    private func energyPanel(_ card: TodayExperienceSignalCard) -> some View {
        NavigationLink {
            VelaMetricDetailView(
                metric: .energy,
                selectedDate: selectedDate,
                dashboardSnapshot: dashboardSnapshot,
                isPresentedInSheet: false
            )
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(card.title)
                        .font(VelaTheme.subheadline().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .lineLimit(1)
                    if deviatedScoreIDs.contains(card.id) {
                        Circle()
                            .fill(accentColor(card.accent))
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 2)
                    energyValue(card)
                    metricChevron
                }

                VStack(alignment: .leading, spacing: 4) {
                    TodayEnergyGauge(
                        value: Double(card.value),
                        color: accentColor(card.accent)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 20)

                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .contentShape(Rectangle())
            .todayDashboardCard(radius: VelaTheme.radiusCardStandard, depth: .standard)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-secondary-energy")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(secondaryAccessibilityLabel(card))
        .accessibilityHint("查看能量的充入、消耗和时间变化")
    }

    private func energyValue(_ card: TodayExperienceSignalCard) -> some View {
        Text(card.value == "--" ? "--" : "\(card.value)%")
            .font(VelaTheme.title2().monospacedDigit())
            .foregroundStyle(VelaTheme.rhythmInk)
            .lineLimit(1)
    }

    private func energyStateLabel(for state: MetricState) -> String {
        switch state {
        case .good: return "充沛"
        case .moderate: return "适中"
        case .poor: return "偏低"
        }
    }

    private var metricChevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.bold))
            .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.55))
    }

    private func secondaryAccessibilityLabel(_ card: TodayExperienceSignalCard) -> String {
        let stateText: String
        if card.id == "stress" {
            stateText = card.value == "--" ? "待同步" : stressStateLabel(for: card.state)
        } else {
            stateText = card.value == "--" ? "待同步" : energyStateLabel(for: card.state)
        }
        let value = card.value == "--" ? "暂无数据" : "\(card.value)\(card.id == "energy" ? "%" : "分")"
        let deviation = deviatedScoreIDs.contains(card.id) ? "，偏离个人基线" : ""
        return "\(card.title)，\(value)，\(stateText)\(deviation)"
    }

    private var agentGuidance: some View {
        Button {
            VelaHaptic.selection()
            onInspectGuidance()
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(agentSentence)
                        .font(VelaTheme.body())
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-guidance")
        .accessibilityLabel("今日指导依据，\(agentSentence)")
        .accessibilityHint("查看判断依据并可追问教练")
    }

    @ViewBuilder
    private func scoreCollection(
        _ cards: [TodayExperienceSignalCard],
        ringSize: CGFloat
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                ForEach(cards) { card in
                    scoreLink(card, ringSize: 58, horizontal: true)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                ForEach(cards) { card in
                    scoreLink(card, ringSize: ringSize, horizontal: false)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func scoreLink(
        _ card: TodayExperienceSignalCard,
        ringSize: CGFloat,
        horizontal: Bool
    ) -> some View {
        if let metric = detailMetric(for: card.id) {
            NavigationLink {
                VelaMetricDetailView(
                    metric: metric,
                    selectedDate: selectedDate,
                    dashboardSnapshot: dashboardSnapshot,
                    isPresentedInSheet: false
                )
            } label: {
                scoreLabel(card, ringSize: ringSize, horizontal: horizontal)
            }
            .buttonStyle(.plain)
            .accessibilityHint("查看\(card.title)的依据和个人趋势")
            .accessibilityIdentifier("today-score-\(card.id)")
        } else {
            scoreLabel(card, ringSize: ringSize, horizontal: horizontal)
        }
    }

    @ViewBuilder
    private func scoreLabel(
        _ card: TodayExperienceSignalCard,
        ringSize: CGFloat,
        horizontal: Bool
    ) -> some View {
        let hasDeviation = deviatedScoreIDs.contains(card.id)
        let scoreDescription = card.value == "--" ? "暂无数据" : "\(card.value) 分"

        // A concrete container is intentional here. A `Group` can distribute
        // accessibility modifiers across its branches, which made the stable
        // score identifier disappear on the empty-data (non-ring) projection.
        VStack(spacing: 0) {
            if horizontal {
                HStack(spacing: 12) {
                    scoreRing(card, size: ringSize)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(card.title)
                                .font(VelaTheme.body().weight(.semibold))
                                .foregroundStyle(VelaTheme.rhythmInk)
                            if hasDeviation {
                                Circle()
                                    .fill(VelaTheme.stressColor)
                                    .frame(width: 6, height: 6)
                                    .accessibilityHidden(true)
                            }
                        }
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text(card.directionLabel)
                                .font(VelaTheme.caption1())
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.65))
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            } else {
                VStack(spacing: 8) {
                    scoreRing(card, size: ringSize)
                    HStack(spacing: 3) {
                        Text(card.title)
                            .font(VelaTheme.subheadline().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                            .lineLimit(1)
                        if hasDeviation {
                            Circle()
                                .fill(VelaTheme.stressColor)
                                .frame(width: 6, height: 6)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(card.title)，\(scoreDescription)，\(card.directionLabel)\(hasDeviation ? "，偏离个人基线" : "")"
        )
        .accessibilityIdentifier("today-score-\(card.id)")
    }

    private func scoreRing(
        _ card: TodayExperienceSignalCard,
        size: CGFloat
    ) -> some View {
        let accent = accentColor(card.accent)
        let score = Double(card.value)

        return VelaMetricScoreRing(
            score: score,
            label: card.title,
            domain: metricDomain(for: card.id),
            size: size,
            accent: accent,
            showsLabel: false,
            direction: card.directionLabel,
            dataState: deviatedScoreIDs.contains(card.id) ? "偏离个人基线" : nil
        )
    }

    private func card(for descriptor: SignalDescriptor) -> TodayExperienceSignalCard {
        model.signalCards.first(where: { $0.id == descriptor.id })
            ?? TodayExperienceSignalCard(
                id: descriptor.id,
                title: descriptor.title,
                value: "--",
                directionLabel: "待同步",
                confidenceLabel: "数据不足",
                coverageLabel: "未同步",
                subtitle: "等待健康数据",
                trend: [],
                accent: descriptor.accent,
                state: .moderate
            )
    }

    private func detailMetric(for cardID: String) -> VelaMetricDetailView.MetricType? {
        switch cardID {
        case "recovery": return .recovery
        case "sleep": return .sleep
        case "strain": return .strain
        case "stress": return .stress
        case "energy": return .energy
        default: return nil
        }
    }

    private func metricDomain(for cardID: String) -> VelaMetricDomain {
        switch cardID {
        case "recovery": return .recovery
        case "sleep": return .sleep
        case "strain": return .strain
        case "stress": return .stress
        case "energy": return .energy
        default: return .neutral
        }
    }

    private func glyphKind(for cardID: String) -> BodySeekMetricGlyphKind {
        switch cardID {
        case "recovery": return .recovery
        case "sleep": return .sleep
        case "strain": return .strain
        case "stress": return .stress
        case "energy": return .energy
        default: return .recovery
        }
    }
}

private struct TodayStressGauge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double?
    let color: Color

    private var progress: CGFloat {
        guard let value else { return 0 }
        return CGFloat(min(1, max(0, value / 100)))
    }

    private let segmentCount = 14

    private var filledSegments: Int {
        guard value != nil else { return 0 }
        return Int((progress * CGFloat(segmentCount)).rounded(.up))
    }

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 3
            let count = segmentCount
            let segmentWidth = (size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            let segmentHeight: CGFloat = 20
            let top = (size.height - segmentHeight) / 2
            for index in 0..<count {
                let rect = CGRect(
                    x: CGFloat(index) * (segmentWidth + spacing),
                    y: top,
                    width: segmentWidth,
                    height: segmentHeight
                )
                let path = Path(roundedRect: rect, cornerRadius: min(segmentWidth, segmentHeight) / 2)
                context.fill(
                    path,
                    with: .color(index < filledSegments ? color : VelaTheme.rhythmMist)
                )
            }
        }
        .animation(VelaTheme.dataAnimation(reduceMotion: reduceMotion), value: filledSegments)
        .accessibilityHidden(true)
    }
}

private struct TodayEnergyGauge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double?
    let color: Color

    private var progress: CGFloat {
        guard let value else { return 0 }
        return CGFloat(min(1, max(0, value / 100)))
    }

    private let segmentCount = 14

    private var filledSegments: Int {
        guard value != nil else { return 0 }
        return Int((progress * CGFloat(segmentCount)).rounded(.up))
    }

    var body: some View {
        // One Canvas node renders all segments to keep the SwiftUI layout tree small.
        Canvas { context, size in
            let spacing: CGFloat = 3
            let count = segmentCount
            let segmentWidth = (size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            let segmentHeight: CGFloat = 20
            let top = (size.height - segmentHeight) / 2
            for index in 0..<count {
                let rect = CGRect(
                    x: CGFloat(index) * (segmentWidth + spacing),
                    y: top,
                    width: segmentWidth,
                    height: segmentHeight
                )
                let path = Path(roundedRect: rect, cornerRadius: min(segmentWidth, segmentHeight) / 2)
                context.fill(
                    path,
                    with: .color(index < filledSegments ? color : VelaTheme.rhythmMist)
                )
            }
        }
        .animation(VelaTheme.dataAnimation(reduceMotion: reduceMotion), value: filledSegments)
        .accessibilityHidden(true)
    }
}

private enum TodayDashboardCardDepth: Equatable {
    case featured
    case standard
}

private struct TodayDashboardCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let radius: CGFloat
    let depth: TodayDashboardCardDepth

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // Perf: shadows on every card re-rasterize per frame while scrolling
        // (CA::Layer::commit cost dominates hitches). The soft elevation is
        // preserved through the stroke + raised fill; drop the blur shadow.
        let _ = depth

        content
            .background(VelaTheme.rhythmCanvasRaised)
            .compositingGroup()
            .clipShape(shape)
            .overlay {
                shape.stroke(
                    colorSchemeContrast == .increased
                        ? VelaTheme.rhythmInk
                        : VelaTheme.rhythmMist.opacity(0.82),
                    lineWidth: colorSchemeContrast == .increased ? 1 : 0.6
                )
            }
    }
}

private extension View {
    func todayDashboardCard(
        radius: CGFloat,
        depth: TodayDashboardCardDepth
    ) -> some View {
        modifier(TodayDashboardCardModifier(radius: radius, depth: depth))
    }
}

// MARK: - Today plan

/// The first downstream capability after the score and lived-state calibration.
/// A conservative local fallback keeps Today useful while the persisted plan is
/// still loading; the Training surface remains the place where users adjust it.
struct TodayDailyPlanCard: View {
    let model: TodayExperienceModel
    let payload: DailyOperatingPlanPayload?
    let onAction: (TodayExperienceAction) -> Void
    let onOpenPlan: () -> Void

    private var primaryAction: TodayExperienceAction? {
        if let payload, payload.hasCanonicalActionSequence {
            guard let action = payload.nextIncompleteAction else { return nil }
            return TodayExperienceAction(
                id: action.id, title: action.title, detail: action.detail,
                destination: action.destination, isPrimary: true, evidence: action.evidence
            )
        }
        return model.actions.first(where: \.isPrimary) ?? model.actions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(primaryAction == nil ? "今日安排" : "下一项")
                    .font(VelaTheme.subheadline())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                Spacer()
                Button("查看计划", action: onOpenPlan)
                    .font(VelaTheme.subheadline())
                    .foregroundStyle(VelaTheme.rhythmDeep)
                    .frame(minHeight: VelaTheme.minimumHitTarget)
            }
            if let action = primaryAction {
                Button {
                    VelaHaptic.selection()
                    onAction(action)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(action.title)
                                .font(VelaTheme.headline())
                                .foregroundStyle(VelaTheme.rhythmInk)
                            if !action.detail.isEmpty {
                                Text(action.detail)
                                    .font(VelaTheme.subheadline())
                                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(VelaTheme.subheadline())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                    .frame(minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today-next-action")
            } else {
                Text(payload?.allActionsCompleted == true ? "今天的安排已完成" : "今天没有待办安排")
                    .font(VelaTheme.headline())
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .accessibilityIdentifier("today-plan-finished")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Equatable Breakers
//
// The Today scroll container re-evaluates its body on every frame while
// scrolling (iOS 26 preference propagation). These `Equatable` conformances
// let SwiftUI skip re-building the heavy card subtrees when their inputs are
// unchanged — the dominant per-frame cost of the fixed five-score dashboard.
extension TodaySignalGrid: Equatable {
    nonisolated static func == (lhs: TodaySignalGrid, rhs: TodaySignalGrid) -> Bool {
        lhs.model.signalCards == rhs.model.signalCards
            && lhs.model.baselineFormation == rhs.model.baselineFormation
            && lhs.freshness == rhs.freshness
            && lhs.deviatedScoreIDs == rhs.deviatedScoreIDs
            && lhs.agentSentence == rhs.agentSentence
    }
}

extension TodayDailyPlanCard: Equatable {
    nonisolated static func == (lhs: TodayDailyPlanCard, rhs: TodayDailyPlanCard) -> Bool {
        lhs.model.actions == rhs.model.actions && lhs.payload == rhs.payload
    }
}
