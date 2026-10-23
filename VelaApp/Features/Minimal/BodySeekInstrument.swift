import SwiftUI

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
                context.fill(Path(ellipseIn: dot), with: .color(ink))
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
        value.map { String(Int($0.rounded())) } ?? "--"
    }

    var accessibilityText: String {
        let reading = value == nil ? "暂无数据" : "\(valueText) 分"
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
            let baseline = finding?.isAvailable == true ? finding?.baselineValue : nil
            let deviation = deviations[entry.id]
            let isUnusual = value != nil && deviation != nil
            let caption: String
            if value == nil {
                caption = "暂无数据"
            } else if let deviation {
                let label = deviation.isEmpty ? BaselineDeviationCopy.unusualFallback : deviation
                caption = baseline.map { "\(label) \(Int($0.rounded()))" } ?? label
            } else if let baseline {
                caption = "平时 \(Int(baseline.rounded()))"
            } else if let finding {
                caption = "基线 \(min(finding.sampleCount, finding.requiredSampleCount))/\(finding.requiredSampleCount) 天"
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

/// Today's five independent scores, each read against the person's own usual
/// value. Recovery / Sleep / Strain stay primary; Stress / Energy secondary.
/// There is no total.
struct TodayScoreInstrument: View {
    let readings: [ScoreInstrumentReading]
    let selectedDate: Date
    let dashboardSnapshot: DashboardSummary

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                if index == 3 {
                    secondaryDivider
                } else if index > 0 {
                    Divider()
                        .overlay(VelaTheme.rhythmMist)
                        .padding(.leading, 16)
                }
                row(reading, primary: index < 3)
            }
            legend
        }
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-score-instrument")
    }

    private var secondaryDivider: some View {
        Rectangle()
            .fill(VelaTheme.rhythmMist)
            .frame(height: 6)
            .padding(.vertical, 2)
            .accessibilityHidden(true)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) {
                Circle().fill(VelaTheme.rhythmInk).frame(width: 7, height: 7)
                Text("今天")
            }
            HStack(spacing: 5) {
                Capsule().fill(VelaTheme.rhythmInkSecondary).frame(width: 2, height: 10)
                Text("近 30 天平时")
            }
            HStack(spacing: 5) {
                Circle().fill(VelaTheme.deviationInk).frame(width: 7, height: 7)
                Text("对你不常见")
            }
            Spacer(minLength: 0)
        }
        .font(VelaTheme.caption2())
        .foregroundStyle(VelaTheme.rhythmInkSecondary)
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("圆点是今天，竖线是你近 30 天的平时水平，琥珀色表示对你而言不常见，不代表好坏。")
    }

    @ViewBuilder
    private func row(_ reading: ScoreInstrumentReading, primary: Bool) -> some View {
        if let metric = detailMetric(for: reading.id) {
            NavigationLink {
                VelaMetricDetailView(
                    metric: metric,
                    selectedDate: selectedDate,
                    dashboardSnapshot: dashboardSnapshot,
                    isPresentedInSheet: false
                )
            } label: {
                rowContent(reading, primary: primary)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reading.accessibilityText)
            .accessibilityHint("查看\(reading.title)的依据和个人趋势")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier(for: reading.id))
        } else {
            rowContent(reading, primary: primary)
        }
    }

    private func rowContent(_ reading: ScoreInstrumentReading, primary: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.title)
                    .font(primary ? VelaTheme.subheadline().weight(.semibold) : VelaTheme.footnote().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(reading.caption)
                    .font(VelaTheme.caption2())
                    .foregroundStyle(reading.isUnusual ? VelaTheme.deviationInk : VelaTheme.rhythmInkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(width: 96, alignment: .leading)

            BaselineGauge(
                value: reading.value,
                baseline: reading.baseline,
                isUnusual: reading.isUnusual,
                height: primary ? 24 : 18
            )

            Text(reading.valueText)
                .font(VelaTheme.instrumentValue(primary: primary))
                .monospacedDigit()
                .foregroundStyle(reading.value == nil ? VelaTheme.rhythmInkSecondary : VelaTheme.rhythmInk)
                .frame(minWidth: primary ? 44 : 36, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.55))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, primary ? 10 : 7)
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
