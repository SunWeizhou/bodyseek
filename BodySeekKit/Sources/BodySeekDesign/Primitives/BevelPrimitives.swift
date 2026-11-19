import BodySeekCore
import SwiftUI

public struct BevelCard<Content: View>: View {
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let content: Content

    public init(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content.bodySeekSurface(cornerRadius: cornerRadius, padding: padding)
    }
}

/// Calm atmospheric `MeshGradient` extending behind navigation bar and header without permanent loop animation.
public struct BevelAmbientAura: View {
    public let recoveryScore: Int?
    @Environment(\.colorScheme) private var colorScheme

    public init(recoveryScore: Int?) {
        self.recoveryScore = recoveryScore
    }

    public var body: some View {
        let baseAlpha = colorScheme == .dark ? 0.16 : 0.10
        let tint: Color = switch recoveryScore {
        case .some(75...): BevelTheme.recoveryColor
        case .some(50..<75): BevelTheme.brand
        case .some: BevelTheme.strainColor
        case .none: BevelTheme.sleepColor
        }

        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.45], [0.5, 0.42], [1.0, 0.45],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
            ],
            colors: [
                tint.opacity(baseAlpha), tint.opacity(baseAlpha * 0.65), BevelTheme.canvas,
                tint.opacity(baseAlpha * 0.35), BevelTheme.sleepColor.opacity(baseAlpha * 0.25), BevelTheme.canvas,
                BevelTheme.canvas, BevelTheme.canvas, BevelTheme.canvas,
            ]
        )
        .frame(height: 340)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

public struct MetricRingView: View {
    public let score: MetricScore
    public let diameter: CGFloat
    public let lineWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(score: MetricScore, diameter: CGFloat = 88, lineWidth: CGFloat = 9) {
        self.score = score
        self.diameter = diameter
        self.lineWidth = lineWidth
    }

    public var body: some View {
        let tint = BevelTheme.color(for: score.kind)
        let progress = Double(score.value ?? 0) / 100.0

        ZStack {
            Circle()
                .stroke(BevelTheme.scoreTrack, lineWidth: lineWidth)
            if case .knownZero = score.availability {
                Circle()
                    .stroke(tint.opacity(0.45), style: StrokeStyle(lineWidth: lineWidth * 0.45))
            } else if score.value == nil {
                Circle()
                    .stroke(BevelTheme.inkSecondary.opacity(0.28), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
            }
            Circle()
                .trim(from: 0, to: score.value == nil ? 0 : progress)
                .stroke(
                    tint.gradient,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : BodySeekMotion.standard, value: score.value)
            Text(score.formattedScore)
                .font(.system(size: diameter * 0.30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(score.value == nil ? BevelTheme.inkSecondary : BevelTheme.ink)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Custom vector organic illustration shown when HealthKit is unauthorized or empty.
public struct ReadinessEmptyIllustration: View {
    public init() {}

    public var body: some View {
        ZStack {
            Circle()
                .stroke(BevelTheme.brand.opacity(0.14), lineWidth: 12)
                .frame(width: 96, height: 96)
            Circle()
                .trim(from: 0.1, to: 0.72)
                .stroke(BevelTheme.sleepColor.opacity(0.35), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 72, height: 72)
                .rotationEffect(.degrees(-25))
            BodySeekBrandMark(size: 30)
        }
    }
}
