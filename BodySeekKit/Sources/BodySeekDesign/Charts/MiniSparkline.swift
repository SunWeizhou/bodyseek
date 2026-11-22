import BodySeekCore
import Charts
import SwiftUI

/// Native Apple Swift Charts sparkline honoring `nil` gaps without linear bridging.
public struct MiniSparkline: View {
    public let points: [(date: Date, value: Double?)]
    public let tint: Color
    public let baselineRange: ClosedRange<Double>?
    public let height: CGFloat

    private struct SegmentPoint: Identifiable {
        let id: Int
        let segmentID: Int
        let date: Date
        let value: Double
    }

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

    public init(
        vitalPoints: [VitalSparkPoint],
        tint: Color,
        baselineRange: ClosedRange<Double>? = nil,
        height: CGFloat = 42
    ) {
        self.points = vitalPoints.map { ($0.date, $0.value) }
        self.tint = tint
        self.baselineRange = baselineRange
        self.height = height
    }

    public var body: some View {
        let prepared = buildSegments()

        if prepared.validValues.count < 2 {
            dashedPlaceholder
                .frame(height: height)
        } else {
            let minVal = prepared.validValues.min() ?? 0
            let maxVal = prepared.validValues.max() ?? 100
            let baseline = baselineRange.map { BaselineBand(lower: $0.lowerBound, upper: $0.upperBound) }
            let yDomain = ChartAxisSupport.smartYDomain(
                values: prepared.validValues,
                baseline: baseline,
                clampRange: nil,
                minSpan: max(2.0, (maxVal - minVal) * 0.22)
            )
            let multiRuns = prepared.runs.filter { $0.count >= 2 }.flatMap { $0 }
            let singleRuns = prepared.runs.filter { $0.count == 1 }.flatMap { $0 }
            let latestPoint = prepared.runs.last?.last

            Chart {
                if let band = baselineRange {
                    let clampedLow = min(yDomain.upperBound, max(yDomain.lowerBound, band.lowerBound))
                    let clampedHigh = max(clampedLow, min(yDomain.upperBound, band.upperBound))
                    RectangleMark(
                        yStart: .value("基线下", clampedLow),
                        yEnd: .value("基线上", clampedHigh)
                    )
                    .foregroundStyle(tint.opacity(0.09))
                }

                ForEach(multiRuns) { pt in
                    AreaMark(
                        x: .value("日期", pt.date),
                        yStart: .value("底", yDomain.lowerBound),
                        yEnd: .value("数值", pt.value),
                        series: .value("段", pt.segmentID)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.22), tint.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("日期", pt.date),
                        y: .value("数值", pt.value),
                        series: .value("段", pt.segmentID)
                    )
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(tint)
                }

                ForEach(singleRuns) { pt in
                    PointMark(
                        x: .value("日期", pt.date),
                        y: .value("数值", pt.value)
                    )
                    .symbolSize(16)
                    .foregroundStyle(tint)
                }

                if let latestPoint {
                    PointMark(
                        x: .value("最新", latestPoint.date),
                        y: .value("最新值", latestPoint.value)
                    )
                    .symbol {
                        ZStack {
                            Circle()
                                .fill(tint.opacity(0.22))
                                .frame(width: 10, height: 10)
                            Circle()
                                .fill(tint)
                                .overlay(
                                    Circle()
                                        .strokeBorder(BevelTheme.card, lineWidth: 1.2)
                                )
                                .frame(width: 5.5, height: 5.5)
                        }
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .chartXScale(domain: prepared.xDomain)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in
                plot.background(.clear)
            }
            .frame(height: height)
        }
    }

    private func buildSegments() -> (
        runs: [[SegmentPoint]],
        validValues: [Double],
        xDomain: ClosedRange<Date>
    ) {
        let sorted = points.sorted { $0.date < $1.date }
        let firstDate = sorted.first?.date ?? Date()
        let lastDate = sorted.last?.date ?? firstDate
        let needsSyntheticSpacing = sorted.count > 1 && lastDate <= firstDate

        var runs: [[SegmentPoint]] = []
        var currentRun: [SegmentPoint] = []
        var validValues: [Double] = []
        var segmentID = 0
        var nextID = 0

        for (index, item) in sorted.enumerated() {
            let xDate = needsSyntheticSpacing
                ? firstDate.addingTimeInterval(Double(index) * 3600)
                : item.date
            if let val = item.value, val.isFinite {
                if currentRun.isEmpty {
                    segmentID += 1
                }
                nextID += 1
                validValues.append(val)
                currentRun.append(SegmentPoint(id: nextID, segmentID: segmentID, date: xDate, value: val))
            } else if !currentRun.isEmpty {
                runs.append(currentRun)
                currentRun = []
            }
        }
        if !currentRun.isEmpty {
            runs.append(currentRun)
        }

        let xDomain: ClosedRange<Date>
        if let first = sorted.first?.date {
            let resolvedLast = needsSyntheticSpacing
                ? first.addingTimeInterval(Double(max(1, sorted.count - 1)) * 3600)
                : max(lastDate, first.addingTimeInterval(3600))
            xDomain = first...resolvedLast
        } else {
            let now = Date()
            xDomain = now.addingTimeInterval(-3600)...now
        }

        return (runs, validValues, xDomain)
    }

    private var dashedPlaceholder: some View {
        Rectangle()
            .fill(.clear)
            .overlay {
                Capsule()
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                    .foregroundStyle(BevelTheme.inkSecondary.opacity(0.4))
                    .frame(height: 1.5)
            }
    }
}
