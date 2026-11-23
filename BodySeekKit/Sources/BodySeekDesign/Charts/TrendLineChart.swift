import BodySeekCore
import Charts
import SwiftUI

/// Native Swift Charts trend line for 7d / 30d horizons with adaptive Y scaling, baseline band, honest gaps, knownZero dots, and native `.chartXSelection`.
public struct TrendLineChart: View {
    public let snapshot: ChartSeriesSnapshot
    public let tint: Color
    public let unitLabel: String
    public let height: CGFloat
    public let showsHeader: Bool
    public let onSelectDate: (@MainActor (Date?) -> Void)?

    @State private var rawSelectedDate: Date?
    @State private var scrubbedPoint: ChartPointSnapshot?

    public init(
        snapshot: ChartSeriesSnapshot,
        tint: Color,
        unitLabel: String = "分",
        height: CGFloat = 208,
        showsHeader: Bool = true,
        onSelectDate: (@MainActor (Date?) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.tint = tint
        self.unitLabel = unitLabel
        self.height = height
        self.showsHeader = showsHeader
        self.onSelectDate = onSelectDate
    }

    public var body: some View {
        let segments = ChartAxisSupport.segmentedPoints(from: snapshot.dailyPoints)
        let excludedPoints = snapshot.dailyPoints.filter {
            if case .excluded = $0.availability { return true }
            return false
        }

        if segments.isEmpty {
            ChartEmptyPlaceholder(
                title: "\(snapshot.kind.title)在\(snapshot.horizon.title)内暂无有效样本",
                height: height
            )
        } else {
            let yDomain = ChartAxisSupport.smartYDomain(
                values: segments.map(\.numericValue),
                baseline: snapshot.baselineBand,
                clampRange: 0...100,
                minSpan: 20
            )
            let yTicks = ChartAxisSupport.yAxisTicks(for: yDomain, count: 3)
            let tickDates = ChartAxisSupport.explicitTickDates(from: snapshot.dailyPoints.map(\.date), maxTicks: 4)
            let header = headerStrings(segments: segments)

            VStack(alignment: .leading, spacing: BSSpace.s) {
                if showsHeader {
                    ChartLockedReadoutHeader(
                        primaryText: header.primary,
                        secondaryText: header.secondary,
                        tint: tint,
                        isLocked: scrubbedPoint != nil,
                        onClear: scrubbedPoint == nil ? nil : {
                            rawSelectedDate = nil
                            scrubbedPoint = nil
                            onSelectDate?(nil)
                        }
                    )
                }

                Chart {
                    rollingBandMarks(yDomain: yDomain)

                    ForEach(excludedPoints) { excluded in
                        RectangleMark(
                            xStart: .value("排除起", excluded.date.addingTimeInterval(-10 * 3600)),
                            xEnd: .value("排除止", excluded.date.addingTimeInterval(10 * 3600)),
                            yStart: .value("下", yDomain.lowerBound),
                            yEnd: .value("上", yDomain.upperBound)
                        )
                        .foregroundStyle(Color.secondary.opacity(BSOpacity.faint))
                    }

                    ForEach(segments) { item in
                        if snapshot.kind == .strain {
                            BarMark(
                                x: .value("日期", item.point.date),
                                yStart: .value("底", yDomain.lowerBound),
                                yEnd: .value(snapshot.kind.title, item.numericValue),
                                width: .fixed(barWidth)
                            )
                            .cornerRadius(BSChartStroke.data)
                            .foregroundStyle(tint)
                        } else {
                            LineMark(
                                x: .value("日期", item.point.date),
                                y: .value(snapshot.kind.title, item.numericValue),
                                series: .value("分段", item.segmentID)
                            )
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: BSChartStroke.data, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(tint)
                        }

                        if snapshot.kind != .strain, snapshot.horizon.dayCount <= Self.dotHorizonDays {
                            PointMark(
                                x: .value("日期", item.point.date),
                                y: .value(snapshot.kind.title, item.numericValue)
                            )
                            .symbolSize(Self.pointSymbolSize)
                            .foregroundStyle(tint)
                        }

                        if item.isKnownZero {
                            PointMark(
                                x: .value("日期", item.point.date),
                                y: .value(snapshot.kind.title, item.numericValue)
                            )
                            .symbol {
                                Circle()
                                    .fill(BSColor.surface)
                                    .overlay(Circle().strokeBorder(tint, lineWidth: BSChartStroke.data))
                                    .frame(width: BSSize.dot, height: BSSize.dot)
                            }
                        }
                    }

                    if let scrubbedPoint {
                        RuleMark(x: .value("选中日", scrubbedPoint.date))
                            .lineStyle(StrokeStyle(lineWidth: BSChartStroke.rule))
                            .foregroundStyle(BSColor.separator)

                        if let value = scrubbedPoint.value {
                            PointMark(
                                x: .value("选中日", scrubbedPoint.date),
                                y: .value("选中值", value)
                            )
                            .symbol {
                                Circle()
                                    .fill(tint)
                                    .overlay(Circle().strokeBorder(BSColor.surface, lineWidth: BSChartStroke.data))
                                    .frame(width: BSSize.dot, height: BSSize.dot)
                            }
                        }
                    } else if let latest = segments.last {
                        PointMark(
                            x: .value("最新", latest.point.date),
                            y: .value("最新值", latest.numericValue)
                        )
                        .symbol {
                            Circle()
                                .fill(tint)
                                .frame(width: BSSize.dot, height: BSSize.dot)
                        }
                    }
                }
                .chartYScale(domain: yDomain)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: yTicks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: BSChartStroke.grid))
                            .foregroundStyle(BSColor.separator)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(ChartAxisSupport.formatYAxisTick(v))
                                    .font(.caption2.monospacedDigit())
                                    .fontDesign(.rounded)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: tickDates) { value in
                        AxisValueLabel(centered: true) {
                            if let d = value.as(Date.self) {
                                Text(ChartAxisSupport.formatAxisDate(d, horizon: snapshot.horizon))
                                    .font(.caption2.monospacedDigit())
                                    .fontDesign(.rounded)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                        }
                    }
                }
                .bsChartScrub(selectedDate: $rawSelectedDate)
                .onChange(of: rawSelectedDate) { _, newValue in
                    handleSelectionChange(newValue)
                }
                .onChange(of: snapshot.kind) { _, _ in
                    rawSelectedDate = nil
                    scrubbedPoint = nil
                    onSelectDate?(nil)
                }
                .onChange(of: snapshot.horizon) { _, _ in
                    rawSelectedDate = nil
                    scrubbedPoint = nil
                    onSelectDate?(nil)
                }
                .frame(height: height)
                .bodyseekSelectionHaptic(trigger: scrubbedPoint?.id)
                .accessibilityChartDescriptor(
                    NumericSeriesAXDescriptor(
                        title: "\(snapshot.kind.title)\(snapshot.horizon.title)趋势",
                        summary: snapshot.statusSummary,
                        points: segments.map {
                            (ChartAxisSupport.formatAxisDate($0.point.date, horizon: snapshot.horizon), $0.numericValue)
                        },
                        yAxisTitle: unitLabel,
                        yRange: yDomain
                    )
                )
            }
        }
    }

    /// UI v4：逐日滚动的平时范围（前 28 天 P25–P75），中性灰填充；有效观测不足的点不画。
    @ChartContentBuilder
    private func rollingBandMarks(yDomain: ClosedRange<Double>) -> some ChartContent {
        ForEach(snapshot.dailyPoints) { point in
            if let band = point.rollingBand {
                let low = min(yDomain.upperBound, max(yDomain.lowerBound, band.lower))
                let high = max(low, min(yDomain.upperBound, band.upper))
                AreaMark(
                    x: .value("日期", point.date),
                    yStart: .value("平时下沿", low),
                    yEnd: .value("平时上沿", high),
                    series: .value("平时范围", "rolling")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.secondary.opacity(BSOpacity.faint))
            }
        }
    }

    /// 负荷用柱：7 天用宽柱，30 天用窄柱。
    private var barWidth: CGFloat {
        snapshot.horizon.dayCount <= Self.dotHorizonDays ? BSSpace.m : BSSize.dot
    }

    private static let dotHorizonDays = 7
    private static let pointSymbolSize: CGFloat = 36

    private func handleSelectionChange(_ date: Date?) {
        guard let date else {
            if !showsHeader, scrubbedPoint != nil {
                scrubbedPoint = nil
                onSelectDate?(nil)
            }
            return
        }
        guard let nearest = snapshot.dailyPoints.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }) else { return }

        if scrubbedPoint?.id != nearest.id {
            scrubbedPoint = nearest
            BodySeekSignposts.shared.emitEvent(.chartScrub, detail: snapshot.kind.rawValue)
            onSelectDate?(nearest.date)
        }
    }

    private func headerStrings(segments: [ChartAxisSupport.ContiguousPoint]) -> (primary: String, secondary: String) {
        if let point = scrubbedPoint {
            let dateStr = ChartAxisSupport.formatReadoutDate(point.date, horizon: snapshot.horizon)
            switch point.availability {
            case .available:
                let valStr = point.value.map { "\(Int($0.rounded())) \(unitLabel)" } ?? "--"
                return (valStr, "\(dateStr) · 选定")
            case let .knownZero(reason):
                return ("0 \(unitLabel)", "\(dateStr) · 已知零值（\(reason)）")
            case let .missing(reason):
                return ("--", "\(dateStr) · 缺失（\(reason)）")
            case let .excluded(reason):
                return ("已排除", "\(dateStr) · \(reason)")
            }
        }

        let latestText = segments.last.map { "\(Int($0.numericValue.rounded())) \(unitLabel)" } ?? "--"
        let medianText = snapshot.medianValue.map { "基线中位 \(Int($0.rounded()))" } ?? "基线积累中"
        return (latestText, "\(medianText) · 覆盖 \(snapshot.coveredDays)/\(snapshot.totalDays)天")
    }
}
