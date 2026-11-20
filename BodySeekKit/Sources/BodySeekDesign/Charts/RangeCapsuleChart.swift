import BodySeekCore
import Charts
import SwiftUI

/// Native Apple Health-style percentile capsule chart for 6m (weekly) & 3y (monthly) horizons.
public struct RangeCapsuleChart: View {
    public let snapshot: ChartSeriesSnapshot
    public let tint: Color
    public let unitLabel: String
    public let height: CGFloat
    public let onSelectBucket: (@MainActor (RangeCapsuleBucket?) -> Void)?

    @State private var selectedBucket: RangeCapsuleBucket?

    public init(
        snapshot: ChartSeriesSnapshot,
        tint: Color,
        unitLabel: String = "分",
        height: CGFloat = 208,
        onSelectBucket: (@MainActor (RangeCapsuleBucket?) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.tint = tint
        self.unitLabel = unitLabel
        self.height = height
        self.onSelectBucket = onSelectBucket
    }

    private func midpointDate(for bucket: RangeCapsuleBucket) -> Date {
        Date(timeIntervalSince1970: (bucket.startDate.timeIntervalSince1970 + bucket.endDate.timeIntervalSince1970) / 2.0)
    }

    public var body: some View {
        let buckets = snapshot.capsules
        if buckets.isEmpty {
            ChartEmptyPlaceholder(
                title: "\(snapshot.horizon.title)窗口暂无足够周期胶囊数据",
                height: height
            )
        } else {
            let domain = xDomain(buckets: buckets)
            let capsuleWidth = max(4.0, min(11.0, 210.0 / CGFloat(max(1, buckets.count))))
            let header = headerStrings(buckets: buckets)

            VStack(alignment: .leading, spacing: 10) {
                ChartLockedReadoutHeader(
                    primaryText: header.primary,
                    secondaryText: header.secondary,
                    tint: tint,
                    isLocked: selectedBucket != nil,
                    onClear: selectedBucket == nil ? nil : {
                        selectedBucket = nil
                        onSelectBucket?(nil)
                    }
                )

                Chart {
                    if let band = snapshot.baselineBand {
                        RectangleMark(
                            yStart: .value("基线下界", max(0, band.lower)),
                            yEnd: .value("基线上界", min(100, band.upper))
                        )
                        .foregroundStyle(tint.opacity(0.08))
                    }

                    if let median = snapshot.medianValue {
                        RuleMark(y: .value("中位", median))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(BevelTheme.inkSecondary.opacity(0.45))
                    }

                    ForEach(buckets) { bucket in
                        let mid = midpointDate(for: bucket)
                        let isSelected = selectedBucket?.id == bucket.id

                        RuleMark(
                            x: .value("周期", mid),
                            yStart: .value("极小", bucket.min),
                            yEnd: .value("极大", bucket.max)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 1.3, lineCap: .round))
                        .foregroundStyle(tint.opacity(isSelected ? 0.6 : 0.28))

                        BarMark(
                            x: .value("周期", mid),
                            yStart: .value("P25", bucket.p25),
                            yEnd: .value("P75", bucket.p75),
                            width: .fixed(capsuleWidth)
                        )
                        .cornerRadius(capsuleWidth / 2)
                        .foregroundStyle(tint.opacity(isSelected ? 0.95 : 0.48))

                        PointMark(
                            x: .value("周期", mid),
                            y: .value("中位", bucket.median)
                        )
                        .symbolSize(isSelected ? 46 : 22)
                        .foregroundStyle(isSelected ? BevelTheme.ink : tint)
                    }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(BevelTheme.hairline.opacity(0.7))
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)")
                                    .font(.caption2.monospacedDigit())
                                    .fontDesign(.rounded)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 8)
                                    .onChanged { value in
                                        selectNearestBucket(at: value.location, buckets: buckets, proxy: proxy, geometry: geometry)
                                    }
                            )
                            .simultaneousGesture(
                                SpatialTapGesture()
                                    .onEnded { value in
                                        selectNearestBucket(at: value.location, buckets: buckets, proxy: proxy, geometry: geometry)
                                    }
                            )
                    }
                }
                .frame(height: height)
                .bodyseekSelectionHaptic(trigger: selectedBucket?.id)
                .accessibilityChartDescriptor(
                    NumericSeriesAXDescriptor(
                        title: "\(snapshot.kind.title)\(snapshot.horizon.title)区间胶囊",
                        summary: snapshot.statusSummary,
                        points: buckets.map { ($0.label, $0.median) },
                        yAxisTitle: unitLabel,
                        yRange: 0...100
                    )
                )

                axisFooter(domain: domain)
            }
        }
    }

    private func selectNearestBucket(
        at location: CGPoint,
        buckets: [RangeCapsuleBucket],
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotFrame = proxy.plotFrame else { return }
        let frame = geometry[plotFrame]
        let xInPlot = location.x - frame.origin.x
        guard xInPlot >= 0, xInPlot <= frame.size.width else { return }
        guard let tappedDate: Date = proxy.value(atX: xInPlot) else { return }

        guard let nearest = buckets.min(by: {
            abs(midpointDate(for: $0).timeIntervalSince(tappedDate))
                < abs(midpointDate(for: $1).timeIntervalSince(tappedDate))
        }) else { return }

        if selectedBucket?.id != nearest.id {
            selectedBucket = nearest
            BodySeekSignposts.shared.emitEvent(.chartScrub, detail: "\(snapshot.kind.rawValue)-capsule")
            onSelectBucket?(nearest)
        }
    }

    /// Keep the horizon's full time axis even when only part of it has data.
    /// Without this, Swift Charts shrinks the axis to the buckets that exist.
    private func xDomain(buckets: [RangeCapsuleBucket]) -> ClosedRange<Date> {
        if let first = snapshot.dailyPoints.first?.date,
           let last = snapshot.dailyPoints.last?.date,
           first < last {
            return first...last
        }
        let dates = buckets.flatMap { [$0.startDate, $0.endDate] }
        guard let first = dates.min(), let last = dates.max(), first < last else {
            let now = Date()
            return now.addingTimeInterval(-86_400)...now
        }
        return first...last
    }

    /// Swift Charts drops trailing axis labels when the domain is much wider than the
    /// data, so render the horizon's start / middle / end labels ourselves.
    private func axisFooter(domain: ClosedRange<Date>) -> some View {
        let middle = domain.lowerBound.addingTimeInterval(
            domain.upperBound.timeIntervalSince(domain.lowerBound) / 2.0
        )
        return HStack(spacing: 0) {
            Text(ChartAxisSupport.formatAxisDate(domain.lowerBound, horizon: snapshot.horizon))
            Spacer(minLength: 8)
            Text(ChartAxisSupport.formatAxisDate(middle, horizon: snapshot.horizon))
            Spacer(minLength: 8)
            Text(ChartAxisSupport.formatAxisDate(domain.upperBound, horizon: snapshot.horizon))
        }
        .font(.caption2.monospacedDigit())
        .fontDesign(.rounded)
        .foregroundStyle(BevelTheme.inkSecondary)
        .accessibilityHidden(true)
    }

    private func headerStrings(buckets: [RangeCapsuleBucket]) -> (primary: String, secondary: String) {
        if let b = selectedBucket {
            let med = Int(b.median.rounded())
            let p25 = Int(b.p25.rounded())
            let p75 = Int(b.p75.rounded())
            return (
                "\(b.label) · 中位 \(med)\(unitLabel)",
                "P25–P75 \(p25)–\(p75) · 覆盖 \(b.sampleCount)/\(b.totalDays)天"
            )
        }
        let medText = snapshot.medianValue.map { "中位 \(Int($0.rounded())) \(unitLabel)" } ?? "--"
        return (
            medText,
            "\(buckets.count) 个\(snapshot.horizon == .sixMonths ? "周" : "月")胶囊 · \(snapshot.coveredDays)/\(snapshot.totalDays)天"
        )
    }
}
