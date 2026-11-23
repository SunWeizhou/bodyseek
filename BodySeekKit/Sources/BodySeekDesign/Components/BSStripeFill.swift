import SwiftUI

/// AI 估算的斜纹填充：45° 领域色细线 + 透明间隔（UI v4 §1.3）。
///
/// 已记录部分用实色，估算部分用本组件。使用时由外层裁剪形状，例如
/// `BSStripeFill(color: tint).clipShape(Capsule())`。
public struct BSStripeFill: View {
    private let color: Color

    /// 创建斜纹填充。
    /// - Parameter color: 斜纹线条颜色，通常取领域色。
    public init(color: Color) {
        self.color = color
    }

    public var body: some View {
        Canvas { context, size in
            var path = Path()
            let pitch = BSSpace.xs
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: .zero))
                x += pitch
            }
            context.stroke(path, with: .color(color), lineWidth: BSChartStroke.micro)
        }
        .accessibilityHidden(true)
    }
}
