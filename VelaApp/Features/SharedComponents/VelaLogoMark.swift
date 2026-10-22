import SwiftUI

struct VelaLogoMark: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            VelaTheme.accent.opacity(0.12),
                            VelaTheme.rhythmInk.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(VelaTheme.accent.opacity(0.2), lineWidth: 1)
                )

            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                let left = CGPoint(x: w * 0.26, y: h * 0.28)
                let bottom = CGPoint(x: w * 0.48, y: h * 0.74)
                let right = CGPoint(x: w * 0.76, y: h * 0.22)
                let inner = CGPoint(x: w * 0.55, y: h * 0.53)

                var sail = Path()
                sail.move(to: left)
                sail.addLine(to: bottom)
                sail.addLine(to: right)
                sail.addLine(to: inner)
                sail.closeSubpath()

                context.fill(
                    sail,
                    with: .linearGradient(
                        Gradient(colors: [VelaTheme.accent, VelaTheme.rhythmInk]),
                        startPoint: left,
                        endPoint: right
                    )
                )

                var mast = Path()
                mast.move(to: left)
                mast.addLine(to: bottom)
                mast.addLine(to: CGPoint(x: w * 0.34, y: h * 0.62))
                context.stroke(mast, with: .color(VelaTheme.fg.opacity(0.88)), style: StrokeStyle(lineWidth: max(1.5, size * 0.045), lineCap: .round, lineJoin: .round))

                [left, bottom, right].forEach { point in
                    let rect = CGRect(x: point.x - size * 0.035, y: point.y - size * 0.035, width: size * 0.07, height: size * 0.07)
                    context.fill(Path(ellipseIn: rect), with: .color(VelaTheme.fg))
                }
            }
            .padding(size * 0.17)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Vela")
    }
}
