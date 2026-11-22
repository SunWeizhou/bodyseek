import BodySeekCore
import SwiftUI

public extension BSColor {
    /// 五项领域色：按 `MetricKind` 取对应的 `BSColor`。
    static func domain(_ kind: MetricKind) -> Color {
        switch kind {
        case .recovery: recovery
        case .sleep: sleep
        case .strain: strain
        case .stress: stress
        case .energy: energy
        }
    }
}

extension View {
    /// 有动作时包上 `Button` 并使用 `BSPressableStyle`，没有动作时原样返回。
    @ViewBuilder
    func bsTappable(_ action: (() -> Void)?) -> some View {
        if let action {
            Button(action: action) { self }
                .buttonStyle(BSPressableStyle())
        } else {
            self
        }
    }
}

/// 格式化数字，固定小数位。
func bsFormat(_ value: Double, digits: Int = 0) -> String {
    value.formatted(.number.precision(.fractionLength(digits)))
}

/// 迷你折线：1.5pt 线 + 末端点。供指标格和走向行使用，不可交互。
struct BSMiniLine: View {
    let points: [Double]
    let color: Color
    let endDotColor: Color

    private static let dotDiameter: CGFloat = 6
    private static let flatRatio: Double = 0.5

    var body: some View {
        GeometryReader { proxy in
            let pts = normalized(in: proxy.size)
            ZStack {
                Path { path in
                    guard let first = pts.first else { return }
                    path.move(to: first)
                    for point in pts.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: BSChartStroke.micro, lineCap: .round, lineJoin: .round)
                )
                if let last = pts.last {
                    Circle()
                        .fill(endDotColor)
                        .frame(width: Self.dotDiameter, height: Self.dotDiameter)
                        .position(last)
                }
            }
        }
        .padding(.horizontal, BSSpace.xxs)
        .accessibilityHidden(true)
    }

    private func normalized(in size: CGSize) -> [CGPoint] {
        guard points.count >= 2, let low = points.min(), let high = points.max() else { return [] }
        let step = size.width / CGFloat(points.count - 1)
        return points.enumerated().map { index, value in
            let ratio = high > low ? (value - low) / (high - low) : Self.flatRatio
            return CGPoint(x: step * CGFloat(index), y: size.height * (1 - CGFloat(ratio)))
        }
    }
}
