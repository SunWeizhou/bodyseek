import SwiftUI

struct ArcProgressView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let score: Double
    let tint: Color
    let recommendedRange: ClosedRange<Int>
    var size: CGFloat = 200
    var lineWidth: CGFloat = 14

    @State private var animatedProgress: Double = 0

    private let startAngle: Double = 225 // 左下 (225 degrees)
    private let endAngle: Double = 315   // 右下 (315 degrees)
    // Total arc = 270 degrees from startAngle to endAngle

    private var progress: Double {
        min(max(score / 100, 0), 1)
    }

    private var scoreColor: Color {
        switch score {
        case ..<40: return VelaTheme.rhythmInk
        case ..<70: return VelaTheme.rhythmInk
        default: return tint
        }
    }

    var body: some View {
        ZStack {
            // Background track (270 degree arc)
            ArcShape(from: 0, to: 1)
                .stroke(
                    Color.black.opacity(0.06),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-135)) // align to start at 225°

            // Recommended range highlight
            if recommendedRange.upperBound > recommendedRange.lowerBound {
                let rangeStart = Double(recommendedRange.lowerBound) / 100
                let rangeEnd = Double(recommendedRange.upperBound) / 100

                ArcShape(from: rangeStart, to: rangeEnd)
                    .stroke(
                        tint.opacity(0.2),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-135))
            }

            // Animated progress arc with glowing gradient stroke
            ArcShape(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [scoreColor.opacity(0.6), scoreColor]),
                        center: .center,
                        startAngle: .degrees(225),
                        endAngle: .degrees(225 + animatedProgress * 270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-135))

            // End dot indicator with premium glowing neon instrumentation styling
            if animatedProgress > 0.01 {
                let dotAngle = Angle.degrees(startAngle + animatedProgress * 270)
                Circle()
                    .fill(scoreColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: scoreColor, radius: 4)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                    )
                    .offset(
                        x: cos(CGFloat(dotAngle.radians)) * (size / 2 - lineWidth / 2),
                        y: sin(CGFloat(dotAngle.radians)) * (size / 2 - lineWidth / 2)
                    )
            }

            // Center text
            VStack(spacing: 1) {
                Text(score.formatted(.number.precision(.fractionLength(0))))
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                    .foregroundStyle(VelaTheme.fg)
                    .monospacedDigit()

                Text(bandText)
                    .font(.system(size: max(8, size * 0.055), weight: .bold))
                    .foregroundStyle(scoreColor)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(VelaTheme.dataAnimation(reduceMotion: reduceMotion)) {
                animatedProgress = progress
            }
        }
        .onChange(of: score) { _, newValue in
            withAnimation(VelaTheme.dataAnimation(reduceMotion: reduceMotion)) {
                animatedProgress = min(max(newValue / 100, 0), 1)
            }
        }
    }

    private var bandText: String {
        let s = Int(score)
        if recommendedRange.contains(s) {
            return L10n.t("Within Target", "在目标范围内")
        } else if s < recommendedRange.lowerBound {
            return L10n.t("Below Target", "低于目标")
        } else {
            return L10n.t("Above Target", "高于目标")
        }
    }
}

// MARK: - Arc Shape Helper

private struct ArcShape: Shape {
    let from: Double // 0 to 1
    let to: Double   // 0 to 1

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let startDegrees = 225 + from * 270
        let endDegrees = 225 + to * 270

        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDegrees),
            endAngle: .degrees(endDegrees),
            clockwise: false
        )
        return path
    }
}

#if DEBUG
struct ArcProgressPreview: View {
    var body: some View {
        VStack(spacing: 24) {
            ArcProgressView(
                score: 65,
                tint: VelaTheme.rhythmInk,
                recommendedRange: 40...70
            )

            ArcProgressView(
                score: 30,
                tint: VelaTheme.rhythmInk,
                recommendedRange: 40...70
            )

            ArcProgressView(
                score: 85,
                tint: VelaTheme.rhythmInk,
                recommendedRange: 60...80
            )
        }
        .padding()
        .background(VelaTheme.bg)
        .previewLayout(.sizeThatFits)
    }
}

#Preview {
    ArcProgressPreview()
}
#endif
