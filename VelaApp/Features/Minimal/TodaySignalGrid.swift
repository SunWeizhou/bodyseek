import BodySeekDomain
import SwiftUI

// MARK: - Today score dashboard

/// The score-led opening of Today. The hierarchy is deliberately stable:
/// Recovery / Sleep / Strain are always primary, while Stress / Energy are
/// always secondary. Baseline deviation adds emphasis without reordering.
struct TodaySignalGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let model: TodayExperienceModel
    let freshness: DataFreshness
    /// Score ring id → "低于平时" / "高于平时" / empty when notable without direction.
    let scoreDeviations: [String: String]
    let agentSentence: String
    var briefDetail: String = ""
    var notableChangeText: String = ""
    let accentColor: (DailyPlanAccent) -> Color
    let onInspectGuidance: () -> Void
    var onAsk: (String) -> Void = { _ in }
    let selectedDate: Date
    let dashboardSnapshot: DashboardSummary

    /// Five scores stay separate on screen and are not combined into one health
    /// score. They still share sleep and HRV inputs, so a change in one can
    /// move another. Keep the descriptor list at the rendering boundary so a
    /// partial/legacy payload cannot make a metric disappear. Missing cards
    /// use `--`; no score is fabricated.
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
        let _ = dynamicTypeSize
        return VStack(alignment: .leading, spacing: 22) {
            agentBrief
            fiveScoreStrip
            recentChangeCard
            followUpChips
        }
    }

    private var briefStamp: String {
        let hour = Calendar.current.component(.hour, from: model.generatedAt)
        let dayPart = hour < 12 ? "早上" : (hour < 18 ? "下午" : "晚上")
        let time = model.generatedAt.formatted(date: .omitted, time: .shortened)
        return "BodySeek · \(dayPart) \(time)"
    }

    private var agentBrief: some View {
        let _ = accentColor(.recovery)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "circle.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(briefStamp)
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
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
            }
            Text(agentSentence)
                .font(VelaTheme.briefBody().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
            if !briefDetail.isEmpty, briefDetail != agentSentence {
                Text(briefDetail)
                    .font(VelaTheme.briefBody())
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action = model.actions.first,
               !action.detail.isEmpty,
               action.detail != agentSentence,
               action.detail != briefDetail {
                Text(action.detail)
                    .font(VelaTheme.briefBody())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("today-guidance")
    }

    private var fiveScoreStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.requiredSignals.enumerated()), id: \.element.id) { index, descriptor in
                if index > 0 {
                    Rectangle()
                        .fill(VelaTheme.hairline)
                        .frame(width: 1)
                        .padding(.vertical, 10)
                }
                scoreColumnLink(card(for: descriptor))
            }
        }
        .padding(.vertical, 8)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: 1)
        )
    }

    private func scoreColumnLink(_ card: TodayExperienceSignalCard) -> some View {
        let column = scoreColumn(card)
        return Group {
            if let metric = detailMetric(for: card.id) {
                NavigationLink {
                    VelaMetricDetailView(
                        metric: metric,
                        selectedDate: selectedDate,
                        dashboardSnapshot: dashboardSnapshot,
                        isPresentedInSheet: false
                    )
                } label: {
                    column
                }
                .buttonStyle(.plain)
            } else {
                column
            }
        }
        .accessibilityIdentifier("today-score-\(card.id)")
    }

    private func scoreColumn(_ card: TodayExperienceSignalCard) -> some View {
        let deviationLabel = scoreDeviations[card.id]
        return VStack(spacing: 4) {
            Text(scoreText(card))
                .font(VelaTheme.cardValue())
                .foregroundStyle(card.value == "--" ? VelaTheme.rhythmInkSecondary : VelaTheme.rhythmInk)
                .monospacedDigit()
            Text(card.title)
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .lineLimit(1)
            if let deviationLabel, !deviationLabel.isEmpty {
                HStack(spacing: 3) {
                    BaselineDeviationMarker(showsLabel: false, diameter: 6)
                    Text(deviationLabel)
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.deviationInk)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.title)，\(card.value == "--" ? "暂无数据" : "\(card.value) 分")\(accessibilityDeviation(for: card.id))")
    }

    private var recentTrend: [Double] {
        let series = model.signalCards.filter { $0.trend.count > 1 }
        if let matched = series.first(where: { notableChangeText.contains($0.title) }) {
            return matched.trend
        }
        return series.max(by: { $0.trend.count < $1.trend.count })?.trend ?? []
    }

    private func scoreText(_ card: TodayExperienceSignalCard) -> String {
        guard card.id == "energy", card.value != "--", !card.value.hasSuffix("%") else { return card.value }
        return "\(card.value)%"
    }

    private var recentBand: ClosedRange<Double>? {
        let trend = recentTrend
        guard trend.count >= 5 else { return nil }
        let now = Date()
        let samples = trend.enumerated().map { index, value in
            BaselineSample(
                date: now.addingTimeInterval(TimeInterval((index - trend.count) * 86_400)),
                value: value
            )
        }
        guard let estimate = BaselineEstimator.estimate(
            samples: samples,
            asOf: now,
            windowDays: max(trend.count, 7),
            minimumSamples: 5,
            calendar: .current
        ), let scale = estimate.robustScale, scale > 0 else {
            return nil
        }
        let half = scale * BaselineEstimator.stableZ
        return (estimate.median - half)...(estimate.median + half)
    }

    private var recentChangeCard: some View {
        let trend = recentTrend
        return HStack(spacing: 12) {
            if trend.count > 1 {
                DateAwareSparkline(
                    points: trend.enumerated().map { index, value in
                        TrendsChartPoint(
                            date: Date().addingTimeInterval(TimeInterval((index - trend.count) * 86_400)),
                            value: value,
                            provenance: nil
                        )
                    },
                    color: VelaTheme.rhythmInk,
                    height: 28,
                    width: 72,
                    band: recentBand,
                    marksLatestPoint: true
                )
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(trend.count > 1 ? "最近变化 · \(trend.count) 天" : "最近变化")
                    .font(VelaTheme.caption1().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                Text(notableChangeText.isEmpty ? "最近没有越过个人常见范围的变化。" : notableChangeText)
                    .font(VelaTheme.subheadline())
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
        .padding(14)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onInspectGuidance)
    }

    private var followUpQuestions: [String] {
        var recoveryQuestion = "今天的恢复怎么样？"
        if scoreDeviations["recovery"] == BaselineDeviationCopy.belowUsual {
            recoveryQuestion = "为什么恢复偏低？"
        } else if scoreDeviations["recovery"] == BaselineDeviationCopy.aboveUsual {
            recoveryQuestion = "为什么恢复偏高？"
        }
        return [recoveryQuestion, "今天能跑步吗？", "今晚怎么睡更好？"]
    }

    private var followUpChips: some View {
        FlowChips(questions: followUpQuestions) { question in
            onAsk(question)
        }
    }

    private var showsBaselineContext: Bool {
        switch model.baselineFormation.phase {
        case .waitingForEvidence, .learning:
            return true
        case .ready:
            return !scoreDeviations.isEmpty
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
            if !scoreDeviations.isEmpty {
                HStack(spacing: 8) {
                    BaselineDeviationMarker(showsLabel: false, diameter: 8)
                    Text(notableChangeText.isEmpty
                         ? "\(scoreDeviations.count) 项偏离个人基线"
                         : notableChangeText)
                        .font(VelaTheme.subheadline())
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("发现 \(scoreDeviations.count) 项个人基线偏离；这表示对你而言不寻常，不等同于医学异常")
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
                    if let direction = scoreDeviations[card.id] {
                        BaselineDeviationMarker(
                            directionLabel: direction,
                            showsLabel: true,
                            diameter: 6
                        )
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
                    if let direction = scoreDeviations[card.id] {
                        BaselineDeviationMarker(
                            directionLabel: direction,
                            showsLabel: true,
                            diameter: 6
                        )
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
        Text(card.value)
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
        let value = card.value == "--" ? "暂无数据" : "\(card.value) 分"
        return "\(card.title)，\(value)，\(stateText)\(accessibilityDeviation(for: card.id))"
    }

    private func accessibilityDeviation(for scoreID: String) -> String {
        guard let label = scoreDeviations[scoreID] else { return "" }
        let spoken = label.isEmpty ? BaselineDeviationCopy.unusualFallback : label
        return "，\(spoken)"
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
        let deviationLabel = scoreDeviations[card.id]
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
                            if let deviationLabel {
                                BaselineDeviationMarker(
                                    directionLabel: deviationLabel,
                                    showsLabel: true,
                                    diameter: 6
                                )
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
                        if let deviationLabel {
                            BaselineDeviationMarker(
                                directionLabel: deviationLabel,
                                showsLabel: true,
                                diameter: 6
                            )
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                .contentShape(Rectangle())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(card.title)，\(scoreDescription)，\(card.directionLabel)\(accessibilityDeviation(for: card.id))"
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
            dataState: scoreDeviations[card.id].map { $0.isEmpty ? BaselineDeviationCopy.unusualFallback : $0 }
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

private struct FlowChips: View {
    let questions: [String]
    let onAsk: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if questions.indices.contains(0) { chip(questions[0]) }
                if questions.indices.contains(1) { chip(questions[1]) }
            }
            if questions.indices.contains(2) {
                chip(questions[2])
            }
        }
    }

    private func chip(_ question: String) -> some View {
        Button {
            onAsk(question)
        } label: {
            Text(question)
                .font(VelaTheme.subheadline())
                .foregroundStyle(VelaTheme.rhythmInk)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().stroke(VelaTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
    let radius: CGFloat
    let depth: TodayDashboardCardDepth

    func body(content: Content) -> some View {
        // One card implementation. Depth stays in the call sites so featured
        // and standard rows can diverge later without a second modifier.
        let _ = depth
        content.velaNativeCard(radius: radius)
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
        .todayDashboardCard(radius: VelaTheme.radiusCard, depth: .standard)
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
            && lhs.scoreDeviations == rhs.scoreDeviations
            && lhs.agentSentence == rhs.agentSentence
            && lhs.notableChangeText == rhs.notableChangeText
    }
}

extension TodayDailyPlanCard: Equatable {
    nonisolated static func == (lhs: TodayDailyPlanCard, rhs: TodayDailyPlanCard) -> Bool {
        lhs.model.actions == rhs.model.actions && lhs.payload == rhs.payload
    }
}
