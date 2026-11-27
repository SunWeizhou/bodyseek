import Charts
import SwiftUI

#if os(iOS)
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// 横向锁定的拖动识别器（UI v4 §5.3）：手指横向位移超过 `lockDistance` 且大于纵向位移才锁定，
/// 纵向先超过则放弃，把手势让给外层滚动，避免和页面滚动冲突。
final class BSHorizontalLockRecognizer: UIGestureRecognizer {
    private static let lockDistance: CGFloat = 8

    private var startPoint: CGPoint = .zero
    private(set) var currentLocation: CGPoint = .zero

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else {
            state = .failed
            return
        }
        startPoint = touch.location(in: view)
        currentLocation = startPoint
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view else { return }
        currentLocation = touch.location(in: view)
        if state == .possible {
            let dx = abs(currentLocation.x - startPoint.x)
            let dy = abs(currentLocation.y - startPoint.y)
            if dx > Self.lockDistance, dx > dy {
                state = .began
            } else if dy > Self.lockDistance {
                state = .failed
            }
        } else {
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .cancelled
    }
}

private struct BSHorizontalScrub: UIGestureRecognizerRepresentable {
    let onScrub: (CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> BSHorizontalLockRecognizer {
        BSHorizontalLockRecognizer()
    }

    func handleUIGestureRecognizerAction(_ recognizer: BSHorizontalLockRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onScrub(recognizer.currentLocation.x)
        default:
            break
        }
    }
}
#endif

/// 图表上的选点交互：轻点选点；横向拖动先判断方向，锁定为横向后才逐点选择，松手后选中保留。
///
/// 替代原生 `chartXSelection`，避免在页面纵向滚动时误触发选点。macOS 上退化为普通拖动。
struct BSChartScrubOverlay: View {
    let proxy: ChartProxy
    @Binding var selectedDate: Date?

    var body: some View {
        GeometryReader { geometry in
            let origin = proxy.plotFrame.map { geometry[$0].origin } ?? .zero
            Color.clear
                .contentShape(.rect)
                .modifier(BSScrubGestures { x in
                    if let date = proxy.value(atX: x - origin.x, as: Date.self) {
                        selectedDate = date
                    }
                })
        }
    }
}

private struct BSScrubGestures: ViewModifier {
    let onLocation: (CGFloat) -> Void

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .gesture(BSHorizontalScrub(onScrub: onLocation))
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    onLocation(value.location.x)
                }
            )
        #else
        content
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    onLocation(value.location.x)
                }
            )
        #endif
    }
}

extension View {
    /// 给 Swift Charts 图表加横向锁定的选点交互，选中的日期写入 `selectedDate`。
    func bsChartScrub(selectedDate: Binding<Date?>) -> some View {
        chartOverlay { proxy in
            BSChartScrubOverlay(proxy: proxy, selectedDate: selectedDate)
        }
    }
}
