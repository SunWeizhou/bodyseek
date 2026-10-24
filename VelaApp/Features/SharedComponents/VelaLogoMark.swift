import SwiftUI

/// Legacy sail mark. Design D surfaces use `BodySeekBrandMark(monochrome: true)`;
/// this component stays flattened to solid ink on `surfaceFloating` + hairline so
/// no decorative gradient can leak back into a D surface.
struct VelaLogoMark: View {
    var size: CGFloat = 44

    private var cornerRadius: CGFloat { VelaTheme.radiusSm }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(VelaTheme.surfaceFloating)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
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

                context.fill(sail, with: .color(VelaTheme.rhythmInk))

                var mast = Path()
                mast.move(to: left)
                mast.addLine(to: bottom)
                mast.addLine(to: CGPoint(x: w * 0.34, y: h * 0.62))
                context.stroke(mast, with: .color(VelaTheme.rhythmInk), style: StrokeStyle(lineWidth: max(1.5, size * 0.045), lineCap: .round, lineJoin: .round))

                [left, bottom, right].forEach { point in
                    let rect = CGRect(x: point.x - size * 0.035, y: point.y - size * 0.035, width: size * 0.07, height: size * 0.07)
                    context.fill(Path(ellipseIn: rect), with: .color(VelaTheme.rhythmInk))
                }
            }
            .padding(size * 0.17)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("BodySeek")
    }
}
