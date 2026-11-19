import SwiftUI

/// Direction-1 "Precision Dual-Arc B" brand emblem shared across Toolbars, Coach, and Onboarding.
public struct BodySeekBrandMark: View {
    public let size: CGFloat

    public init(size: CGFloat = 24) {
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let strokeWidth = max(1.4, min(w, h) * 0.13)

            var stem = Path()
            stem.move(to: CGPoint(x: w * 0.28, y: h * 0.16))
            stem.addLine(to: CGPoint(x: w * 0.28, y: h * 0.84))

            var upperArc = Path()
            upperArc.move(to: CGPoint(x: w * 0.28, y: h * 0.18))
            upperArc.addCurve(
                to: CGPoint(x: w * 0.28, y: h * 0.50),
                control1: CGPoint(x: w * 0.78, y: h * 0.15),
                control2: CGPoint(x: w * 0.78, y: h * 0.50)
            )

            var lowerArc = Path()
            lowerArc.move(to: CGPoint(x: w * 0.28, y: h * 0.50))
            lowerArc.addCurve(
                to: CGPoint(x: w * 0.28, y: h * 0.82),
                control1: CGPoint(x: w * 0.86, y: h * 0.48),
                control2: CGPoint(x: w * 0.86, y: h * 0.85)
            )

            context.stroke(
                stem,
                with: .color(BevelTheme.ink),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )
            context.stroke(
                upperArc,
                with: .color(BevelTheme.brand),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )
            context.stroke(
                lowerArc,
                with: .color(BevelTheme.ink),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )
        }
        .frame(width: size, height: size)
        .accessibilityLabel("BodySeek")
    }
}
