import SwiftUI

// MARK: - TodayReadinessDial

// MARK: - ProactiveGuidanceCard

// MARK: - View Scroll Extensions
extension View {
    @ViewBuilder
    func velaTrackScrollOffsetY(offset: Binding<CGFloat>) -> some View {
        if #available(iOS 18, *) {
            self.onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { oldValue, newValue in
                offset.wrappedValue = newValue
            }
        } else {
            self // fallback
        }
    }
}

// MARK: - VelaHealthSyncNote(训练数据来源说明)

// MARK: - G1 重设计 · 今日页展示组件
// 统一品牌绿 + 状态色 + SF Rounded 大数字。全部为无副作用纯展示组件,数据由调用方传入。

// MARK: TodayStateRingsStrip(五指标状态色环)

// MARK: TodayReadinessHero(就绪度大数字 + 趋势线)

// MARK: TodayHeroSparkline(迷你趋势线,无数据画虚线)
struct TodayHeroSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height * 0.5))
                p.addLine(to: CGPoint(x: size.width, y: size.height * 0.5))
                context.stroke(
                    p,
                    with: .color(color.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4])
                )
                return
            }
            let minV = values.min() ?? 0
            let maxV = values.max() ?? 100
            let span = max(maxV - minV, 1)
            let stepX = size.width / CGFloat(values.count - 1)

            func point(_ i: Int, _ v: Double) -> CGPoint {
                let y = size.height * 0.15 + size.height * 0.7 * (1 - CGFloat((v - minV) / span))
                return CGPoint(x: CGFloat(i) * stepX, y: y)
            }

            var path = Path()
            for (i, v) in values.enumerated() {
                let pt = point(i, v)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }

            // Subtle area gradient beneath the line
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: CGFloat(values.count - 1) * stepX, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()
            context.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.18), color.opacity(0.01)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
            )
            if let last = values.last {
                let pt = point(values.count - 1, last)
                // Endpoint glow
                context.fill(
                    Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)),
                    with: .color(color.opacity(0.35))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)),
                    with: .color(color)
                )
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: TodayGuidanceCard(今日指导:洞察 + Coach 入口,无「开始训练」)

// MARK: TodayVitalsGrid(体征 2×2 大卡 + 迷你可视化)
enum TodayVitalKind: String, CaseIterable, Identifiable {
    case hrv, rhr, spo2, sleep
    var id: String { rawValue }
}

enum TodayVitalAssessment: String, Equatable, Sendable {
    case favorable
    case neutral
    case unfavorable
    case unknown

    var stateColor: Color {
        switch self {
        case .favorable:
            return VelaTheme.textColor(for: .good)
        case .neutral:
            return VelaTheme.rhythmInkSecondary
        case .unfavorable:
            return VelaTheme.textColor(for: .moderate)
        case .unknown:
            return VelaTheme.meta
        }
    }
}

struct TodayVitalCardModel: Identifiable, Equatable {
    let kind: TodayVitalKind
    let label: String
    let value: String          // "68" / "--"
    let unit: String           // "ms" / "bpm" / "%" / "时"
    let status: String
    let assessment: TodayVitalAssessment
    let trend: [Double]
    var id: String { kind.rawValue }

    var isGood: Bool { assessment == .favorable }

    init(
        kind: TodayVitalKind,
        label: String,
        value: String,
        unit: String,
        status: String,
        assessment: TodayVitalAssessment,
        trend: [Double]
    ) {
        self.kind = kind
        self.label = label
        self.value = value
        self.unit = unit
        self.status = status
        self.assessment = assessment
        self.trend = trend
    }

    init(
        kind: TodayVitalKind,
        label: String,
        value: String,
        unit: String,
        status: String,
        isGood: Bool,
        trend: [Double]
    ) {
        self.kind = kind
        self.label = label
        self.value = value
        self.unit = unit
        self.status = status
        self.assessment = isGood ? .favorable : .unfavorable
        self.trend = trend
    }
}

struct TodayVitalsGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let cards: [TodayVitalCardModel]
    let onTap: (TodayVitalKind) -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    ForEach(cards) { card in
                        vitalButton(card)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        if cards.indices.contains(0) { vitalButton(cards[0]) }
                        if cards.indices.contains(1) { vitalButton(cards[1]) }
                    }
                    HStack(spacing: 10) {
                        if cards.indices.contains(2) { vitalButton(cards[2]) }
                        if cards.indices.contains(3) { vitalButton(cards[3]) }
                    }
                }
            }
        }
    }

    private func vitalButton(_ card: TodayVitalCardModel) -> some View {
        Button { onTap(card.kind) } label: {
            TodayVitalCard(card: card)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(card.label) \(card.value)\(card.unit),\(card.status)")
        .accessibilityHint("查看\(card.label)详情")
    }
}

struct TodayVitalCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    let card: TodayVitalCardModel

    private var iconName: String {
        switch card.kind {
        case .hrv:   return "heart.fill"
        case .rhr:   return "waveform.path.ecg"
        case .spo2:  return "lungs.fill"
        case .sleep: return "bed.double.fill"
        }
    }

    private var accentColor: Color {
        switch card.kind {
        case .hrv:   return VelaTheme.rhythmInk
        case .rhr:   return VelaTheme.rhythmDeep
        case .spo2:  return VelaTheme.accent
        case .sleep: return VelaTheme.rhythmInk
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Icon + Title + Chevron
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous)
                        .fill(accentColor.opacity(0.12))
                    Image(systemName: iconName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accentColor)
                }
                .frame(width: 20, height: 20)

                Text(card.label)
                    .font(VelaTheme.caption1().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.4))
            }

            // Row 2: Large monospaced value + unit
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(card.value)
                    .font(VelaTheme.title3().weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(card.unit)
                    .font(VelaTheme.caption1().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }

            // Row 3: Status text & Sparkline
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        statusText
                        sparkline
                    }
                } else {
                    HStack(alignment: .top) {
                        statusText
                        Spacer(minLength: 4)
                        sparkline
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .fill(VelaTheme.rhythmCanvasRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(
                    VelaTheme.hairline,
                    lineWidth: VelaTheme.hairlineWidth
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
    }

    private var statusText: some View {
        Text(card.status)
            .font(VelaTheme.caption2().weight(.bold))
            .foregroundStyle(card.assessment.stateColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sparkline: some View {
        TodayHeroSparkline(values: card.trend, color: accentColor)
            .frame(width: 48, height: 18)
    }
}

// MARK: TodayWeeklyLoadCard(本周负荷柱状)

// Perf: breaks the per-frame cascade from the Today scroll container (iOS 26
// preference propagation re-evaluates the parent body every scroll frame).
// The grid body re-runs SwiftData-driven derivations and per-card layouts, so
// skipping unchanged rebuilds removes ~90ms/frame on device.
extension TodayVitalsGrid: Equatable {
    nonisolated static func == (lhs: TodayVitalsGrid, rhs: TodayVitalsGrid) -> Bool {
        lhs.cards == rhs.cards
    }
}
