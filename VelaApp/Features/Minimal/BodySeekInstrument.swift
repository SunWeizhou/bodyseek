import SwiftUI

// MARK: - Today Agent brief

/// One Today sentence: now → optional recent change → whether action is needed.
/// Facts come from `PersonalHealthBrief` (`evaluateAction` + morning-brief fields).
/// A single recovery score never implies the other vitals are fine.
enum TodayAgentBriefCopy {
    static func sentence(
        brief: PersonalHealthBrief?,
        formation: PersonalBaselineFormation
    ) -> String {
        guard let brief else {
            return fallback(for: formation)
        }

        var parts: [String] = []
        let now = nowClause(brief, formation: formation)
        if !now.isEmpty { parts.append(now) }

        if let change = changeClause(brief), !now.contains(change) {
            parts.append(change)
        }

        let action = actionClause(brief)
        if !action.isEmpty, !parts.contains(where: { $0.contains(action) }) {
            parts.append(action)
        }

        let joined = parts.joined(separator: "，")
        if joined.isEmpty { return fallback(for: formation) }
        return joined.hasSuffix("。") ? joined : joined + "。"
    }

    static func nowClause(_ brief: PersonalHealthBrief, formation: PersonalBaselineFormation) -> String {
        let raw = stripPeriod(brief.subheadline)
        if raw.isEmpty || looksLikeOverclaim(raw) {
            if let recovery = recoveryCitation(in: raw) {
                return "现在\(recovery)"
            }
            switch formation.phase {
            case .waitingForEvidence:
                return "连接 Apple 健康后开始形成个人基线"
            case .learning:
                return "现在先看今天的读数，个人基线还在建立"
            case .ready:
                return "现在先看五项各自的读数"
            }
        }
        if raw.hasPrefix("现在") { return raw }
        return "现在\(raw)"
    }

    static func changeClause(_ brief: PersonalHealthBrief) -> String? {
        guard let first = brief.notableChanges.first(where: \.isNotable)
                ?? brief.notableChanges.first else { return nil }
        let summary = stripPeriod(first.summary)
        if !summary.isEmpty { return summary }
        return "\(first.metric.shortTitle)出现短期波动"
    }

    static func actionClause(_ brief: PersonalHealthBrief) -> String {
        if brief.needsAction {
            if let headline = brief.actionHeadline?.trimmingCharacters(in: .whitespacesAndNewlines),
               !headline.isEmpty,
               !looksLikeOverclaim(headline) {
                return headline
            }
            return "今天可能需要调整安排"
        }
        return "今天不必改计划"
    }

    private static func fallback(for formation: PersonalBaselineFormation) -> String {
        switch formation.phase {
        case .waitingForEvidence:
            return "连接 Apple 健康后开始形成个人基线。"
        case .learning:
            return "继续正常佩戴，Vela 正在了解你的日常波动。"
        case .ready:
            return "今天的数据还没有同步，五项暂显示 --。"
        }
    }

    private static func stripPeriod(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。"))
    }

    /// Local brief / evaluateAction copy that treats one score as every vital.
    static func looksLikeOverclaim(_ text: String) -> Bool {
        let markers = ["各项", "都好", "都在", "机能充沛", "处于良好", "核心体征平稳", "节奏良好", "身体机能"]
        return markers.contains { text.contains($0) }
    }

    static func recoveryCitation(in text: String) -> String? {
        guard let range = text.range(of: #"恢复\s*\d+"#, options: .regularExpression) else {
            return nil
        }
        return text[range].replacingOccurrences(of: "  ", with: " ")
    }
}

// MARK: - Baseline gauge

/// A 0–100 track that places today's reading next to the person's own usual
/// value. It never draws a value or baseline that was not published: a
/// missing reading leaves an empty dashed track and a forming baseline omits
/// its tick. The span is a comparison, not a total or a status bar.
struct BaselineGauge: View {
    let value: Double?
    let baseline: Double?
    var isUnusual: Bool = false
    var height: CGFloat = 22

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let inset: CGFloat = 7
            let width = max(1, size.width - inset * 2)
            func x(_ v: Double) -> CGFloat {
                inset + CGFloat(min(100, max(0, v)) / 100) * width
            }

            var track = Path()
            track.move(to: CGPoint(x: inset, y: midY))
            track.addLine(to: CGPoint(x: inset + width, y: midY))
            context.stroke(
                track,
                with: .color(VelaTheme.scoreTrack),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: value == nil ? [2, 5] : [])
            )
            for mark in [0.0, 100.0] {
                var cap = Path()
                cap.move(to: CGPoint(x: x(mark), y: midY - 3.5))
                cap.addLine(to: CGPoint(x: x(mark), y: midY + 3.5))
                context.stroke(cap, with: .color(VelaTheme.rhythmMist), lineWidth: 1.5)
            }

            let ink = isUnusual ? VelaTheme.deviationInk : VelaTheme.rhythmInk
            if let value, let baseline {
                var span = Path()
                span.move(to: CGPoint(x: x(baseline), y: midY))
                span.addLine(to: CGPoint(x: x(value), y: midY))
                context.stroke(
                    span,
                    with: .color(ink.opacity(0.55)),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
            }
            if let baseline {
                let tick = CGRect(x: x(baseline) - 1, y: midY - 8, width: 2, height: 16)
                context.fill(
                    Path(roundedRect: tick, cornerRadius: 1),
                    with: .color(VelaTheme.rhythmInkSecondary)
                )
            }
            if let value {
                let dot = CGRect(x: x(value) - 6, y: midY - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: dot.insetBy(dx: -2.5, dy: -2.5)), with: .color(VelaTheme.rhythmCanvasRaised))
                if isUnusual {
                    context.stroke(
                        Path(ellipseIn: dot),
                        with: .color(ink),
                        style: StrokeStyle(lineWidth: 1.5)
                    )
                } else {
                    context.fill(Path(ellipseIn: dot), with: .color(ink))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Score reading

/// Display-only projection of one Scored Health Evidence result next to its
/// 30-day Personal Baseline. It reads published values and never derives a
/// score, a baseline, or a combined total.
struct ScoreInstrumentReading: Equatable, Identifiable {
    let id: String
    let title: String
    let value: Double?
    let baseline: Double?
    let isUnusual: Bool
    let caption: String

    var valueText: String {
        value.map { String(Int($0.rounded())) + (id == "energy" ? "%" : "") } ?? "--"
    }

    /// Short Today-strip caption. Unusual readings show the published direction
    /// ("低于平时") next to a hollow mark; usual or missing values stay blank.
    var stripDeviationLabel: String? {
        guard isUnusual, value != nil else { return nil }
        if let first = caption.split(separator: " ").first {
            let word = String(first)
            if word.contains("低") || word.contains("高") || word.contains("偏离") {
                return word
            }
        }
        return BaselineDeviationCopy.unusualFallback
    }

    var accessibilityText: String {
        let reading = value == nil ? "暂无数据" : id == "energy" ? "\(valueText) 可用余量" : "\(valueText) 分"
        return "\(title)，\(reading)，\(caption)"
    }

    static let scoreOrder: [(id: String, title: String, metric: CoreHealthMetric)] = [
        ("recovery", "恢复", .recovery),
        ("sleep", "睡眠", .sleepScore),
        ("strain", "负荷", .strain),
        ("stress", "压力", .stress),
        ("energy", "能量", .energy)
    ]

    /// - Parameters:
    ///   - cardValues: the value strings already shown on Today (`"--"` when missing).
    ///   - deviations: Today's baseline-deviation labels by score id. An empty
    ///     label means notable without a direction.
    static func make(
        cardValues: [String: String],
        deviations: [String: String],
        findings: [HealthTrendFinding],
        horizon: HealthTrendHorizon = .thirtyDays
    ) -> [ScoreInstrumentReading] {
        scoreOrder.map { entry in
            let raw = cardValues[entry.id]?.replacingOccurrences(of: "%", with: "")
            let value = raw.flatMap { $0 == "--" ? nil : Double($0) }
            let finding = findings.first { $0.metric == entry.metric && $0.horizon == horizon }
            let deviation = deviations[entry.id]
            let deviationFinding = findings.first {
                $0.metric == entry.metric && $0.isAvailable && $0.isNotable
                    && deviation != nil && (BaselineDeviationCopy.label(for: $0) ?? "") == deviation
            }
            let reference = deviationFinding ?? finding
            let baseline = reference?.isAvailable == true ? reference?.baselineValue : nil
            let isUnusual = value != nil && deviation != nil
            let caption: String
            if value == nil {
                caption = "暂无数据"
            } else if let deviation {
                let label = deviation.isEmpty ? BaselineDeviationCopy.unusualFallback : deviation
                caption = reference?.isAvailable == true ? "\(label) · \((reference?.horizon.title ?? horizon.title))" : label
            } else if let baseline {
                caption = "\(horizon.title)平时 \(Int(baseline.rounded()))"
            } else if let finding {
                caption = "历史 \(finding.sampleCount)/\(finding.requiredSampleCount) 天"
            } else {
                caption = "基线建立中"
            }
            return ScoreInstrumentReading(
                id: entry.id,
                title: entry.title,
                value: value,
                baseline: baseline,
                isUnusual: isUnusual,
                caption: caption
            )
        }
    }
}

// MARK: - Today instrument

/// Today leads with one reading, then keeps the other four as a quiet support
/// strip. The hero is the score the Agent statement already named (or the
/// notable / first reading); the remaining four no longer share its weight.
/// It reads published values only: no total, no derived score.
struct TodayScoreInstrument: View {
    let readings: [ScoreInstrumentReading]
    /// The reading this surface leads with. Falls back to the first reading.
    var heroID: String? = nil
    let selectedDate: Date
    let dashboardSnapshot: DashboardSummary

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hero: ScoreInstrumentReading? {
        guard readings.contains(where: { $0.value != nil }) else { return nil }
        if let heroID, let match = readings.first(where: { $0.id == heroID }) {
            return match
        }
        return readings.first
    }

    private var support: [ScoreInstrumentReading] {
        readings.filter { $0.id != hero?.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VelaTheme.space3) {
            if let hero {
                heroLink(hero)
            }
            supportStrip
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-score-instrument")
    }

    // MARK: Hero

    @ViewBuilder
    private func heroLink(_ reading: ScoreInstrumentReading) -> some View {
        if let metric = detailMetric(for: reading.id) {
            NavigationLink {
                VelaMetricDetailView(
                    metric: metric,
                    selectedDate: selectedDate,
                    dashboardSnapshot: dashboardSnapshot,
                    isPresentedInSheet: false
                )
            } label: {
                heroContent(reading)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading.accessibilityText)
            .accessibilityHint("查看\(reading.title)的依据和个人趋势")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier(for: reading.id))
        } else {
            heroContent(reading)
        }
    }

    private func heroContent(_ reading: ScoreInstrumentReading) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(reading.title)
                    .font(VelaTheme.caption1().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                if let label = reading.stripDeviationLabel {
                    BaselineDeviationMarker(directionLabel: label, showsLabel: true, diameter: 6)
                }
                Spacer(minLength: 8)
                Text(heroCaption(reading))
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(reading.valueText)
                    .font(VelaTheme.heroValue())
                    .foregroundStyle(reading.value == nil ? VelaTheme.rhythmInkSecondary : VelaTheme.rhythmInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.55))
            }

            BaselineGauge(
                value: reading.value,
                baseline: reading.baseline,
                isUnusual: reading.isUnusual,
                height: 12
            )
        }
        .padding(.horizontal, VelaTheme.cardPadding)
        .padding(.vertical, VelaTheme.compactCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        )
        .contentShape(Rectangle())
    }

    /// Top-right context for the hero: the published baseline number when it
    /// exists, otherwise the reading's own caption. The direction label already
    /// sits next to the title, so this never repeats it.
    private func heroCaption(_ reading: ScoreInstrumentReading) -> String {
        if let baseline = reading.baseline {
            return "基线 \(Int(baseline.rounded()))"
        }
        return reading.caption
    }

    // MARK: Support strip

    @ViewBuilder
    private var supportStrip: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: VelaTheme.space3),
                    GridItem(.flexible(), spacing: VelaTheme.space3)
                ],
                alignment: .leading,
                spacing: VelaTheme.space3
            ) {
                ForEach(support) { reading in
                    supportLink(reading)
                }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(Array(support.enumerated()), id: \.element.id) { index, reading in
                    if index > 0 {
                        Rectangle()
                            .fill(VelaTheme.hairline)
                            .frame(width: VelaTheme.hairlineWidth, height: 22)
                    }
                    supportLink(reading)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func supportLink(_ reading: ScoreInstrumentReading) -> some View {
        if let metric = detailMetric(for: reading.id) {
            NavigationLink {
                VelaMetricDetailView(
                    metric: metric,
                    selectedDate: selectedDate,
                    dashboardSnapshot: dashboardSnapshot,
                    isPresentedInSheet: false
                )
            } label: {
                supportContent(reading)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading.accessibilityText)
            .accessibilityHint("查看\(reading.title)的依据和个人趋势")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier(for: reading.id))
        } else {
            supportContent(reading)
        }
    }

    private func supportContent(_ reading: ScoreInstrumentReading) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(reading.valueText)
                    .font(VelaTheme.supportValue())
                    .foregroundStyle(reading.value == nil ? VelaTheme.rhythmInkSecondary : VelaTheme.rhythmInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if reading.isUnusual {
                    Circle()
                        .strokeBorder(VelaTheme.deviationInk, lineWidth: 1)
                        .frame(width: 5, height: 5)
                }
            }
            Text(reading.title)
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// Stable identifiers predate this layout and are used by UI tests.
    private func identifier(for id: String) -> String {
        switch id {
        case "stress": return "today-secondary-stress"
        case "energy": return "today-secondary-energy"
        default: return "today-score-\(id)"
        }
    }

    private func detailMetric(for id: String) -> VelaMetricDetailView.MetricType? {
        switch id {
        case "recovery": return .recovery
        case "sleep": return .sleep
        case "strain": return .strain
        case "stress": return .stress
        case "energy": return .energy
        default: return nil
        }
    }
}

// MARK: - Contextual questions

/// Suggested questions from the page the person is already looking at.
/// They never invent a score, a plan, or a missing deviation.
enum BodySeekAskSuggestions {
    static func make(
        surface: CoachScreenSurface,
        horizonTitle: String? = nil,
        readings: [ScoreInstrumentReading] = [],
        nextActionTitle: String? = nil,
        hasPendingProposal: Bool = false,
        detailTitle: String? = nil
    ) -> [String] {
        if let detailTitle, !detailTitle.isEmpty {
            return [
                "\(detailTitle)今天为什么是这个分数？",
                "\(detailTitle)和平时比怎么样？",
                "结合其他四项，\(detailTitle)意味着什么？"
            ]
        }

        switch surface {
        case .trends:
            let window = horizonTitle ?? "这段时间"
            return [
                "\(window)里最值得注意的变化是什么？",
                "睡眠和恢复有没有一起动？",
                "负荷和压力最近怎么配合？"
            ]
        case .plan:
            var questions: [String] = []
            if hasPendingProposal {
                questions.append("这份调整建议值得采用吗？为什么？")
            }
            if let title = nextActionTitle, !title.isEmpty {
                questions.append("今天继续「\(title)」还合适吗？")
            }
            questions.append("如果下午很累，安排怎么改？")
            questions.append("今晚睡眠怎么配合今天的训练？")
            return Array(questions.prefix(3))
        default:
            var questions: [String] = []
            for reading in readings where reading.isUnusual {
                questions.append("为什么\(reading.title)\(Self.deviationPhrase(reading.caption))？")
            }
            if hasPendingProposal {
                questions.append("状态有变化，今天的安排要不要改？")
            }
            if let title = nextActionTitle, !title.isEmpty {
                questions.append("今天「\(title)」和五项分数对得上吗？")
            }
            if questions.isEmpty {
                questions.append("今天的状态适合按计划训练吗？")
            }
            questions.append("今晚怎么睡更好？")
            return Array(questions.prefix(3))
        }
    }

    /// Uses the published caption ("低于平时 61") without re-deriving direction.
    static func deviationPhrase(_ caption: String) -> String {
        let words = caption.split(separator: " ")
        if let first = words.first, first.contains("低") || first.contains("高") || first.contains("偏离") {
            return String(first)
        }
        return "偏离平时"
    }
}
