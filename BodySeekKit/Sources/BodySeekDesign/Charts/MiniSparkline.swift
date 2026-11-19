import BodySeekCore
import SwiftUI

/// Lightweight high-framerate Canvas sparkline honoring `nil` gaps without linear bridging.
public struct MiniSparkline: View {
    public let points: [(date: Date, value: Double?)]
    public let tint: Color
    public let baselineRange: ClosedRange<Double>?
    public let height: CGFloat

    public init(
        points: [(date: Date, value: Double?)],
        tint: Color,
        baselineRange: ClosedRange<Double>? = nil,
        height: CGFloat = 42
    ) {
        self.points = points
        self.tint = tint
        self.baselineRange = baselineRange
        self.height = height
    }

    public var body: some View {
        let sorted = points.sorted { $0.date < $1.date }
        let validValues = sorted.compactMap { pt -> Double? in
            guard let v = pt.value, v.isFinite else { return nil }
            return v
        }

        if validValues.count < 2 {
            dashedPlaceholder
                .frame(height: height)
        } else {
            Canvas { context, size in
                let paddingTop: CGFloat = 5
                let paddingBottom: CGFloat = 4
                let paddingHorizontal: CGFloat = 3
                let plotW = max(1, size.width - paddingHorizontal * 2)
                let plotH = max(1, size.height - paddingTop - paddingBottom)

                var minV = validValues.min() ?? 0
                var maxV = validValues.max() ?? 100
                if let band = baselineRange {
                    minV = min(minV, band.lowerBound)
                    maxV = max(maxV, band.upperBound)
                }
                let rawSpan = maxV - minV
                let paddedMin = minV - max(rawSpan * 0.14, 1.0)
                let paddedMax = maxV + max(rawSpan * 0.14, 1.0)
                let vSpan = max(1e-6, paddedMax - paddedMin)

                let firstTime = sorted.first?.date.timeIntervalSince1970 ?? 0
                let lastTime = sorted.last?.date.timeIntervalSince1970 ?? (firstTime + 1)
                let tSpan = max(1.0, lastTime - firstTime)

                func xPos(_ date: Date, index: Int) -> CGFloat {
                    if lastTime > firstTime {
                        let frac = (date.timeIntervalSince1970 - firstTime) / tSpan
                        return paddingHorizontal + CGFloat(frac) * plotW
                    }
                    let frac = Double(index) / Double(max(1, sorted.count - 1))
                    return paddingHorizontal + CGFloat(frac) * plotW
                }

                func yPos(_ val: Double) -> CGFloat {
                    let frac = (val - paddedMin) / vSpan
                    return paddingTop + plotH * (1.0 - CGFloat(frac))
                }

                if let band = baselineRange {
                    let yHigh = yPos(band.upperBound)
                    let yLow = yPos(band.lowerBound)
                    let bandRect = CGRect(
                        x: paddingHorizontal,
                        y: min(yHigh, yLow),
                        width: plotW,
                        height: max(1, abs(yLow - yHigh))
                    )
                    context.fill(Path(bandRect), with: .color(tint.opacity(0.09)))
                }

                // Split into contiguous valid runs so missing days create genuine gaps
                var runs: [[CGPoint]] = []
                var currentRun: [CGPoint] = []
                for (index, item) in sorted.enumerated() {
                    if let val = item.value, val.isFinite {
                        currentRun.append(CGPoint(x: xPos(item.date, index: index), y: yPos(val)))
                    } else if !currentRun.isEmpty {
                        runs.append(currentRun)
                        currentRun = []
                    }
                }
                if !currentRun.isEmpty {
                    runs.append(currentRun)
                }

                let bottomY = paddingTop + plotH
                for run in runs where run.count >= 2 {
                    var line = Path()
                    line.move(to: run[0])
                    for idx in 1..<run.count {
                        let prev = run[idx - 1]
                        let curr = run[idx]
                        let midX = (prev.x + curr.x) / 2
                        line.addCurve(
                            to: curr,
                            control1: CGPoint(x: midX, y: prev.y),
                            control2: CGPoint(x: midX, y: curr.y)
                        )
                    }

                    var area = line
                    if let lastPt = run.last, let firstPt = run.first {
                        area.addLine(to: CGPoint(x: lastPt.x, y: bottomY))
                        area.addLine(to: CGPoint(x: firstPt.x, y: bottomY))
                        area.closeSubpath()
                        context.fill(
                            area,
                            with: .linearGradient(
                                Gradient(colors: [tint.opacity(0.22), tint.opacity(0.0)]),
                                startPoint: CGPoint(x: 0, y: paddingTop),
                                endPoint: CGPoint(x: 0, y: bottomY)
                            )
                        )
                    }

                    context.stroke(
                        line,
                        with: .color(tint),
                        style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                    )
                }

                for run in runs where run.count == 1 {
                    let pt = run[0]
                    let dot = Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4))
                    context.fill(dot, with: .color(tint))
                }

                if let lastRun = runs.last, let endpoint = lastRun.last {
                    let halo = Path(ellipseIn: CGRect(x: endpoint.x - 4.5, y: endpoint.y - 4.5, width: 9, height: 9))
                    context.fill(halo, with: .color(tint.opacity(0.22)))
                    let dot = Path(ellipseIn: CGRect(x: endpoint.x - 2.6, y: endpoint.y - 2.6, width: 5.2, height: 5.2))
                    context.fill(dot, with: .color(tint))
                }
            }
            .frame(height: height)
        }
    }

    private var dashedPlaceholder: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
            .foregroundStyle(BevelTheme.inkSecondary.opacity(0.4))
        }
    }
}
