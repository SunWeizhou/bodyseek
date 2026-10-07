import SwiftUI

// MARK: - BodySeek brand primitives

/// The reusable vector form of the confirmed Open Orbit brand mark.
///
/// The center remains empty by design. Data points may appear in charts, but
/// they are not part of the logo geometry.
struct BodySeekOrbitMainShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.80, 0.24))
        path.addCurve(
            to: point(0.08, 0.55),
            control1: point(0.55, 0.08),
            control2: point(0.03, 0.22)
        )
        path.addCurve(
            to: point(0.71, 0.59),
            control1: point(0.15, 0.86),
            control2: point(0.48, 0.86)
        )
        return path
    }
}

struct BodySeekOrbitGapShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.82, 0.29))
        path.addCurve(
            to: point(0.80, 0.49),
            control1: point(0.88, 0.33),
            control2: point(0.88, 0.43)
        )
        return path
    }
}

struct BodySeekOrbitMark: View {
    var size: CGFloat = 28
    var color: Color = VelaTheme.rhythmInk
    var drawOn = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

    var body: some View {
        ZStack {
            BodySeekOrbitMainShape()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round, lineJoin: .round))

            BodySeekOrbitGapShape()
                .trim(from: 0, to: max(CGFloat.zero, (progress - 0.70) / 0.30))
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.105, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            guard drawOn else { return }
            progress = 0
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.72)) {
                progress = 1
            }
        }
    }
}

enum BodySeekMetricGlyphKind: String, CaseIterable, Sendable {
    case recovery
    case sleep
    case strain
    case stress
    case energy
}

/// Small semantic glyphs share the Open Orbit silhouette while keeping their
/// supporting marks distinct from the brand mark itself.
struct BodySeekMetricGlyph: View {
    let kind: BodySeekMetricGlyphKind
    var size: CGFloat = 28
    var tint: Color = VelaTheme.rhythmDeep
    var accent: Color? = nil

    var body: some View {
        Canvas { context, canvasSize in
            let orbitRect = CGRect(
                x: canvasSize.width * 0.06,
                y: canvasSize.height * 0.06,
                width: canvasSize.width * 0.88,
                height: canvasSize.height * 0.88
            )
            let lineWidth = max(1.4, size * 0.075)
            let main = BodySeekOrbitMainShape().path(in: orbitRect)
            let gap = BodySeekOrbitGapShape().path(in: orbitRect)
            context.stroke(main, with: .color(tint), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            context.stroke(gap, with: .color(tint), style: StrokeStyle(lineWidth: lineWidth * 1.14, lineCap: .round))

            let supportingColor = (accent ?? tint).opacity(0.82)
            switch kind {
            case .recovery:
                var baseline = Path()
                baseline.move(to: CGPoint(x: canvasSize.width * 0.20, y: canvasSize.height * 0.78))
                baseline.addCurve(
                    to: CGPoint(x: canvasSize.width * 0.76, y: canvasSize.height * 0.70),
                    control1: CGPoint(x: canvasSize.width * 0.38, y: canvasSize.height * 0.72),
                    control2: CGPoint(x: canvasSize.width * 0.56, y: canvasSize.height * 0.84)
                )
                context.stroke(baseline, with: .color(supportingColor), style: StrokeStyle(lineWidth: lineWidth * 0.68, lineCap: .round))

            case .sleep:
                var quietArc = Path()
                quietArc.move(to: CGPoint(x: canvasSize.width * 0.28, y: canvasSize.height * 0.23))
                quietArc.addCurve(
                    to: CGPoint(x: canvasSize.width * 0.66, y: canvasSize.height * 0.20),
                    control1: CGPoint(x: canvasSize.width * 0.38, y: canvasSize.height * 0.10),
                    control2: CGPoint(x: canvasSize.width * 0.54, y: canvasSize.height * 0.12)
                )
                context.stroke(quietArc, with: .color(supportingColor), style: StrokeStyle(lineWidth: lineWidth * 0.70, lineCap: .round))

            case .strain:
                for index in 0..<3 {
                    let x = canvasSize.width * (0.38 + CGFloat(index) * 0.11)
                    let barHeight = canvasSize.height * CGFloat(0.14 + Double(index) * 0.07)
                    let bar = Path(roundedRect: CGRect(x: x, y: canvasSize.height * 0.72 - barHeight, width: lineWidth * 0.72, height: barHeight), cornerRadius: lineWidth * 0.36)
                    context.fill(bar, with: .color(supportingColor))
                }

            case .stress:
                for index in 0..<2 {
                    var signal = Path()
                    signal.addArc(
                        center: CGPoint(x: canvasSize.width * 0.58, y: canvasSize.height * 0.48),
                        radius: canvasSize.width * (0.14 + CGFloat(index) * 0.08),
                        startAngle: .degrees(-55),
                        endAngle: .degrees(55),
                        clockwise: false
                    )
                    context.stroke(signal, with: .color(supportingColor.opacity(0.82 - Double(index) * 0.18)), style: StrokeStyle(lineWidth: lineWidth * 0.62, lineCap: .round))
                }

            case .energy:
                let reservoir = RoundedRectangle(cornerRadius: lineWidth * 0.45, style: .continuous)
                    .path(in: CGRect(x: canvasSize.width * 0.26, y: canvasSize.height * 0.72, width: canvasSize.width * 0.46, height: lineWidth * 1.8))
                context.stroke(reservoir, with: .color(supportingColor), style: StrokeStyle(lineWidth: lineWidth * 0.65, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A compact, data-first progress rail for the daily operating plan.
/// The orbit is a brand primitive; the nodes remain plain so completion
/// cannot be confused with a health score.
struct BodySeekPlanProgressRail: View {
    let completed: Int
    let total: Int
    var tint: Color = VelaTheme.rhythmDeep

    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, max(0, CGFloat(completed) / CGFloat(total)))
    }

    var body: some View {
        ProgressView(value: Double(progress))
            .tint(tint)
            .frame(minHeight: 12)
            .accessibilityLabel(total == 0 ? "今日暂无计划行动" : "已完成 \(completed) 项，共 \(total) 项")
    }
}

struct BodySeekMetricAvailability: Identifiable, Sendable {
    let id: String
    let title: String
    let kind: BodySeekMetricGlyphKind
    let isAvailable: Bool
}

/// A small availability map for evidence surfaces. It intentionally reports
/// presence only; the score and its meaning remain in the adjacent metric UI.
struct BodySeekMetricAvailabilityStrip: View {
    let items: [BodySeekMetricAvailability]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(items) { item in
                VStack(spacing: 4) {
                    BodySeekMetricGlyph(
                        kind: item.kind,
                        size: 24,
                        tint: item.isAvailable ? VelaTheme.rhythmDeep : VelaTheme.rhythmInkSecondary.opacity(0.52)
                    )
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.isAvailable ? VelaTheme.rhythmInkSecondary : VelaTheme.rhythmInkSecondary.opacity(0.62))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    (item.isAvailable ? VelaTheme.rhythmDeep : VelaTheme.rhythmMist).opacity(item.isAvailable ? 0.08 : 0.32),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.title)，\(item.isAvailable ? "有数据" : "暂无数据")")
            }
        }
    }
}

/// The sail mark is the product's durable identity. Keep it separate from
/// health-state colours so data meaning never gets confused with branding.
/// A single-stroke B. The two open curves suggest a changing body profile;
/// the mark stays legible at navigation size without a decorative orbit.
struct BodySeekContour: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: point(0.27, 0.16))
        path.addLine(to: point(0.27, 0.84))
        path.addCurve(to: point(0.79, 0.67), control1: point(0.60, 0.88), control2: point(0.79, 0.83))
        path.addCurve(to: point(0.44, 0.49), control1: point(0.79, 0.52), control2: point(0.60, 0.48))
        path.addCurve(to: point(0.72, 0.32), control1: point(0.60, 0.49), control2: point(0.72, 0.44))
        path.addCurve(to: point(0.27, 0.16), control1: point(0.72, 0.17), control2: point(0.51, 0.13))
        return path
    }
}

struct BodySeekBrandMark: View {
    var size: CGFloat = 28
    var showWordmark = false
    var monochrome = false

    var body: some View {
        HStack(spacing: 9) {
            BodySeekContour()
                .stroke(
                    monochrome ? VelaTheme.rhythmInk : VelaTheme.rhythmDeep,
                    style: StrokeStyle(lineWidth: size * 0.085, lineCap: .round, lineJoin: .round)
                )
                .frame(width: size, height: size)
                .accessibilityHidden(true)
            if showWordmark {
                Text("BodySeek")
                    .font(.system(size: size * 0.62, weight: .semibold, design: .default))
                    .tracking(-0.3)
                    .foregroundStyle(VelaTheme.rhythmInk)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("BodySeek")
    }
}

struct BodySeekTopBar: View {
    let title: String
    var subtitle: String? = nil
    var onProfile: (() -> Void)? = nil
    var onQuickAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            BodySeekBrandMark(size: 30, monochrome: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VelaTheme.title2())
                    .foregroundStyle(VelaTheme.rhythmInk)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(VelaTheme.subheadline())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
            }
            Spacer(minLength: 8)
            if let onQuickAction {
                Button(action: onQuickAction) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmDeepOn)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(VelaTheme.rhythmDeep))
                }
                .accessibilityLabel("记录或提问")
            }
            if let onProfile {
                Button(action: onProfile) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(VelaTheme.rhythmInk)
                }
                .accessibilityLabel("个人档案")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

// MARK: - Vela 3.0 Command System Components

struct CoachArtifactCard: View {
    let artifact: CoachArtifact
    var compact = false
    var onAction: ((CoachArtifactAction) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(artifact.title)
                        .font(compact ? VelaTheme.subheadline() : VelaTheme.headline())
                        .fontWeight(.semibold)
                        .foregroundStyle(VelaTheme.fg)
                        .lineLimit(2)

                    Text(artifact.type.displayTitle)
                        .font(VelaTheme.caption2())
                        .fontWeight(.semibold)
                        .foregroundStyle(VelaTheme.muted)
                }

                Spacer(minLength: 0)

                ConfidenceBadge(score: artifact.confidence)
            }

            Text(artifact.summary)
                .font(VelaTheme.subheadline())
                .foregroundStyle(VelaTheme.fg2)
                .lineSpacing(3)
                .lineLimit(compact ? 3 : nil)

            if !compact, !artifact.reasons.isEmpty {
                VStack(spacing: 8) {
                    ForEach(Array(artifact.reasons.prefix(3).enumerated()), id: \.offset) { _, reason in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(accent)
                                .frame(width: 6, height: 6)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(reason.signal): \(reason.value)")
                                    .font(VelaTheme.caption1())
                                    .fontWeight(.semibold)
                                    .foregroundStyle(VelaTheme.fg)
                                Text(reason.explanation)
                                    .font(VelaTheme.caption1())
                                    .foregroundStyle(VelaTheme.muted)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            if !artifact.actions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(artifact.actions.prefix(compact ? 2 : 4)) { action in
                            ActionPill(
                                title: action.label,
                                systemImage: icon(for: action),
                                isPrimary: action.id == artifact.actions.first?.id
                            ) {
                                onAction?(action)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(16)
        .velaNativeCard(radius: 18)
    }

    private var iconName: String {
        switch artifact.type {
        case .morningBrief: return "sun.max.fill"
        case .workoutReadiness, .trainingAdjustment: return "figure.strengthtraining.traditional"
        case .postWorkoutReview: return "checkmark.seal.fill"
        case .eveningReview: return "moon.stars.fill"
        case .weeklyReview: return "calendar.badge.clock"
        case .wikiUpdateProposal: return "brain.head.profile"
        case .askCoachAnswer: return "sparkles"
        }
    }

    private var accent: Color {
        switch artifact.type {
        case .postWorkoutReview, .trainingAdjustment, .workoutReadiness: return VelaTheme.strainColor
        case .eveningReview: return VelaTheme.sleepColor
        case .wikiUpdateProposal: return Color(hex: "#FF9F0A")
        default: return VelaTheme.accent
        }
    }

    private func icon(for action: CoachArtifactAction) -> String {
        if action.type.contains("training") || action.type.contains("workout") { return "figure.run" }
        if action.type.contains("recovery") { return "heart.fill" }
        if action.type.contains("check") { return "square.and.pencil" }
        return "arrow.right"
    }
}

struct ActionPill: View {
    let title: String
    var systemImage: String
    var isPrimary = false
    var action: () -> Void

    var body: some View {
        Button {
            VelaHaptic.selection()
            VelaAppState.shared.logDebug("[ActionPill] Direct tap triggered: \(title)")
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(isPrimary ? VelaTheme.rhythmDeepOn : VelaTheme.rhythmInk)
            .padding(.horizontal, 12)
            .frame(minHeight: VelaTheme.minimumHitTarget)
            .background(
                Capsule(style: .continuous)
                    .fill(isPrimary ? VelaTheme.rhythmDeep : VelaTheme.rhythmMist.opacity(0.4))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isPrimary ? Color.clear : VelaTheme.rhythmMist, lineWidth: 0.75)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel(title)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            Text(title)
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.rhythmInk)
            Text(subtitle)
                .font(VelaTheme.subheadline())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .velaNativeCard(radius: 16)
    }
}

struct DataSourceBadge: View {
    let source: HealthDataSource

    var body: some View {
        Text(label)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(VelaTheme.muted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(VelaTheme.surface))
    }

    private var label: String {
        switch source {
        case .healthKit: return "Health"
        case .userProvided: return "Manual"
        case .aiEstimated: return "AI"
        case .wikiProfile: return "Wiki"
        case .biomarkerLab: return "Lab"
        case .computed: return "Calc"
        }
    }
}

struct ConfidenceBadge: View {
    var confidence: DataConfidence? = nil
    var score: Double? = nil

    var body: some View {
        Text(label)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.1)))
    }

    private var label: String {
        if let score {
            return "\(Int((score * 100).rounded()))%"
        }
        switch confidence {
        case .high: return "HIGH"
        case .medium: return "MED"
        case .low: return "LOW"
        case .unavailable: return "MISS"
        case nil: return "N/A"
        }
    }

    private var color: Color {
        if let score {
            if score >= 0.75 { return VelaTheme.success }
            if score >= 0.5 { return Color(hex: "#FF9F0A") }
            return Color(hex: "#FF3B30")
        }
        switch confidence {
        case .high: return VelaTheme.success
        case .medium: return Color(hex: "#FF9F0A")
        case .low, .unavailable: return Color(hex: "#FF3B30")
        case nil: return VelaTheme.meta
        }
    }
}

struct WorkoutSessionCard: View {
    let title: String
    let subtitle: String
    let metric: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(VelaTheme.strainColor)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(VelaTheme.strainColor.opacity(0.12)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(VelaTheme.subheadline())
                        .fontWeight(.semibold)
                        .foregroundStyle(VelaTheme.fg)
                    Text(subtitle)
                        .font(VelaTheme.caption1())
                        .foregroundStyle(VelaTheme.muted)
                }

                Spacer()

                Text(metric)
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .foregroundStyle(VelaTheme.fg)
            }
            .padding(14)
            .velaNativeCard(radius: 16)
        }
        .buttonStyle(.plain)
    }
}

struct SetInputRow: View {
    let index: Int
    let reps: String
    let weight: String
    var completed: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(VelaTheme.caption1())
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(completed ? VelaTheme.success : VelaTheme.meta))

            Text(reps)
                .font(VelaTheme.subheadline())
                .foregroundStyle(VelaTheme.fg)
            Spacer()
            Text(weight)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(VelaTheme.fg2)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(VelaTheme.surface))
    }
}

// MARK: - Button Styles

extension ButtonStyle where Self == CardPressStyle {
    static var cardPress: CardPressStyle { CardPressStyle() }
}

struct CardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
            .animation(
                reduceMotion
                    ? .easeOut(duration: VelaTheme.reducedMotionDuration)
                    : VelaTheme.press,
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == TabItemStyle {
    static var tabItem: TabItemStyle { TabItemStyle() }
}

struct TabItemStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.68 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.16) : VelaTheme.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    VelaHaptic.selection()
                }
            }
    }
}

extension ButtonStyle where Self == PlusButtonStyle {
    static var plusButton: PlusButtonStyle { PlusButtonStyle() }
}

struct PlusButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.16) : VelaTheme.press, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    VelaHaptic.medium()
                }
            }
    }
}

// MARK: - View Modifiers

struct AmbientGlowModifier: ViewModifier {
    let color: Color
    let intensity: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                    .fill(color.opacity(intensity))
            )
    }
}

struct VelaThemeBackground: View {
    var body: some View {
        LinearGradient(
            colors: [VelaTheme.accent.opacity(0.055), VelaTheme.bg, VelaTheme.bg],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct VelaNativeCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(VelaTheme.rhythmCanvasRaised)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        colorSchemeContrast == .increased
                            ? VelaTheme.rhythmInk
                            : VelaTheme.rhythmMist,
                        lineWidth: colorSchemeContrast == .increased ? 1 : 0.75
                    )
            )
    }
}

struct VelaGlassSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let needsSolidSurface = reduceTransparency || colorSchemeContrast == .increased

        content
            .background {
                if needsSolidSurface {
                    shape.fill(VelaTheme.cardBg)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            .clipShape(shape)
            .overlay(
                shape.stroke(
                    colorSchemeContrast == .increased
                        ? VelaTheme.border
                        : VelaTheme.borderSoft.opacity(0.55),
                    lineWidth: colorSchemeContrast == .increased ? 1 : 0.5
                )
            )
    }
}

struct AppleIntelligenceGlowModifier: ViewModifier {
    let isHighlighted: Bool
    let radius: CGFloat
    func body(content: Content) -> some View {
        if isHighlighted {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(hex: "#9C5FF2"),
                                    Color(hex: "#00A2FF"),
                                    Color(hex: "#9C5FF2")
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        } else {
            content
        }
    }
}

extension View {
    func appleIntelligenceGlow(isHighlighted: Bool = true, radius: CGFloat = 18) -> some View {
        self.modifier(AppleIntelligenceGlowModifier(isHighlighted: isHighlighted, radius: radius))
    }

    func ambientGlow(color: Color, intensity: CGFloat = 0.05) -> some View {
        self.modifier(AmbientGlowModifier(color: color, intensity: intensity))
    }

    func velaNativeCard(radius: CGFloat = 16) -> some View {
        self.modifier(VelaNativeCardModifier(radius: radius))
    }

    func cardSurface(padding: CGFloat = VelaTheme.space4, radius: CGFloat = VelaTheme.radiusCardLarge) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(radius: radius)
    }

    func heroCardSurface(accent: Color = VelaTheme.accent, padding: CGFloat = VelaTheme.space4) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VelaTheme.radiusFeature, style: .continuous)
                    .fill(accent.opacity(0.06))
            )
            .glassEffect(radius: VelaTheme.radiusFeature)
            .overlay(
                RoundedRectangle(cornerRadius: VelaTheme.radiusFeature, style: .continuous)
                    .stroke(accent.opacity(0.25), lineWidth: 0.8)
            )
    }

    func glassEffect(radius: CGFloat = VelaTheme.radiusCardLarge) -> some View {
        self.modifier(VelaGlassSurfaceModifier(radius: radius))
    }

    func sectionSpacing() -> some View {
        self.padding(.bottom, VelaTheme.space8)
    }

    func velaSheetSurface() -> some View {
        self
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(VelaTheme.radiusSheet)
            .presentationBackground(VelaTheme.rhythmCanvas)
    }
}

// MARK: - Screen Wrapper

/// Shared chrome for the four canonical primary surfaces. It owns title
/// hierarchy, Dynamic Type reflow, spacing, and optional trailing actions.
struct VelaSurfaceHeader<Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                labels
                Spacer(minLength: 12)
                trailing()
            }

            VStack(alignment: .leading, spacing: 8) {
                labels
                HStack {
                    Spacer(minLength: 0)
                    trailing()
                }
            }
        }
        .padding(.horizontal, VelaTheme.pagePadding)
        .padding(.vertical, 8)
        // The header is persistent navigation chrome. Cap only this compact
        // region so accessibility text does not leave too little room for the
        // scrollable content; body content keeps the user's full type size.
        .dynamicTypeSize(
            dynamicTypeSize.isAccessibilitySize ? .accessibility1 : dynamicTypeSize
        )
    }

    private var labels: some View {
        HStack(alignment: .center, spacing: 10) {
            BodySeekBrandMark(size: 22, monochrome: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .tracking(-0.35)
                    .foregroundStyle(VelaTheme.rhythmInk)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension VelaSurfaceHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Section Header

struct VelaMinimalSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VelaTheme.meta)
                .textCase(.uppercase)
                .tracking(1.0)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.muted)
            }
        }
        .padding(.top, VelaTheme.space2)
        .padding(.bottom, VelaTheme.space2)
    }
}

// MARK: - ImagePicker wrapper (for CoachChatPanel compat)

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image
            }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

enum VelaMinimalTab: CaseIterable {
    case today, training, insights, settings
}

struct VelaMakeHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        subtitle: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.system(.footnote, design: .rounded, weight: .regular))
                    .foregroundStyle(VelaTheme.fg2)
                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(VelaTheme.fg)
            }
            Spacer(minLength: 8)
            trailing()
                .frame(minWidth: 32, minHeight: 32)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}

extension VelaMakeHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct VelaMakeCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VelaTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct VelaMakeSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.footnote, design: .rounded, weight: .regular))
            .foregroundStyle(VelaTheme.fg2)
            .padding(.horizontal, 4)
    }
}

struct VelaMakeIconTile: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}

struct VelaMakeRing: View {
    let value: Double
    let color: Color
    var size: CGFloat = 108
    var lineWidth: CGFloat = 8
    var valueText: String? = nil

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value / 100, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(valueText ?? "\(Int(value.rounded()))")
                .font(.system(size: size * 0.28, weight: .bold))
                .foregroundStyle(VelaTheme.fg)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
    }
}

struct VelaMinimalNavBar: View {
    let title: String
    var body: some View {
        Text(title)
            .font(VelaTheme.title1())
            .foregroundStyle(VelaTheme.fg)
            .padding(.top, 8)
    }
}

// MARK: - Premium Shimmer & Skeleton View Modifiers

struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0.0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let width = geo.size.width

                    if reduceMotion {
                        Color.white.opacity(0.08)
                    } else {
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.12),
                                .white.opacity(0.35),
                                .white.opacity(0.12),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .rotationEffect(.degrees(15))
                        .scaleEffect(1.5)
                        .offset(x: -width + (phase * width * 2.5))
                    }
                }
            )
            .mask(content)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
            .onChange(of: reduceMotion) { _, shouldReduceMotion in
                phase = 0
                guard !shouldReduceMotion else { return }
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
    }
}

struct SkeletonModifier<S: Shape>: ViewModifier {
    var show: Bool
    var shape: S
    
    func body(content: Content) -> some View {
        if show {
            shape
                .fill(VelaTheme.borderSoft)
                .shimmer()
        } else {
            content
        }
    }
}

extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
    
    func skeleton<S: Shape>(show: Bool, shape: S) -> some View {
        self.modifier(SkeletonModifier(show: show, shape: shape))
    }
}

// MARK: - VelaBackground — simple full-screen background
struct VelaBackground: View {
    var body: some View {
        VelaTheme.bg.ignoresSafeArea()
    }
}

// MARK: - BodySeek Field Notes

/// Decorative, deterministic vector artwork. These contours never encode a
/// health measurement; charts continue to use their observed data series.
enum BodySeekArtworkKind: Int {
    case day, trends, plan, coach, profile, sleep, recovery, strain, stress, energy
}

struct BodySeekArtwork: View {
    var kind: BodySeekArtworkKind = .day
    var tint: Color = VelaTheme.rhythmDeep

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let center = CGPoint(x: w * 0.54, y: h * 0.47)
            let radius = min(w, h) * 0.3
            // A small sun and topographic contours form one consistent family.
            context.fill(
                Path(ellipseIn: CGRect(x: w * 0.69, y: h * 0.1, width: w * 0.16, height: w * 0.16)),
                with: .color(tint.opacity(0.25))
            )
            for index in 0..<9 {
                let offset = CGFloat(index) * min(w, h) * 0.029
                var contour = Path()
                let phase = Double(kind.rawValue) * 0.45
                for step in 0...100 {
                    let angle = Double(step) / 100 * .pi * 2
                    let ripple = 1 + 0.12 * sin(angle * 3 + phase) + 0.07 * cos(angle * 2 - phase)
                    let r = (radius + offset) * ripple
                    let progress = Double(step) / 100
                    let point: CGPoint
                    switch kind {
                    case .trends, .stress:
                        point = CGPoint(
                            x: w * (0.06 + progress * 0.88),
                            y: h * (0.36 + Double(index) * 0.04)
                                + sin(progress * .pi * 2.2 + phase) * h * 0.13
                        )
                    case .plan, .strain:
                        point = CGPoint(
                            x: center.x + cos(angle) * r * 0.72,
                            y: center.y + sin(angle) * r * 0.5 - cos(angle) * h * 0.19
                        )
                    case .coach:
                        point = CGPoint(
                            x: center.x + cos(angle) * r * 0.7,
                            y: center.y + sin(angle * 2) * r * 0.72
                        )
                    case .sleep:
                        point = CGPoint(
                            x: center.x + cos(angle * 0.78) * r * 0.78,
                            y: center.y + sin(angle * 0.78) * r * 0.95
                        )
                    default:
                        point = CGPoint(
                            x: center.x + cos(angle) * r * 0.78,
                            y: center.y + sin(angle) * r * 0.95
                        )
                    }
                    if step == 0 { contour.move(to: point) }
                    else { contour.addLine(to: point) }
                }
                if kind != .trends && kind != .stress && kind != .sleep {
                    contour.closeSubpath()
                }
                context.stroke(contour, with: .color(tint.opacity(0.18 + Double(index) * 0.025)), lineWidth: 0.85)
            }
            var axis = Path()
            axis.move(to: CGPoint(x: w * 0.18, y: h * 0.8))
            axis.addCurve(
                to: CGPoint(x: w * 0.82, y: h * 0.26),
                control1: CGPoint(x: w * 0.65, y: h * 0.9),
                control2: CGPoint(x: w * 0.3, y: h * 0.12)
            )
            context.stroke(axis, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

struct BodySeekPageIntro: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let eyebrow: String
    let title: String
    let subtitle: String
    var artwork: BodySeekArtworkKind = .day
    var tint: Color = VelaTheme.rhythmDeep

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(.title, design: .serif, weight: .medium))
                    .tracking(-0.6)
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize {
                BodySeekArtwork(kind: artwork, tint: tint)
                    .frame(width: 82, height: 108)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
