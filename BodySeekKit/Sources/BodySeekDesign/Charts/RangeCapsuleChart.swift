import BodySeekCore
import Charts
import SwiftUI

/// Native Apple Health-style percentile capsule chart for 7d (daily), 30d/6m (weekly), and 3y (monthly) horizons.
public struct RangeCapsuleChart: View {
    public let snapshot: ChartSeriesSnapshot
    public let tint: Color
    public let unitLabel: String
    public let height: CGFloat
    public let showsHeader: Bool
    public let onSelectBucket: (@MainActor (RangeCapsuleBucket?) -> Void)?

    @State private var rawSelectedDate: Date?
    @State private var selectedBucket: RangeCapsuleBucket?

    public init(
        snapshot: ChartSeriesSnapshot,
        tint: Color,
        unitLabel: String = "分",
        height: CGFloat = 208,
        showsHeader: Bool = true,
        onSelectBucket: (@MainActor (RangeCapsuleBucket?) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.tint = tint
        self.unitLabel = unitLabel
        self.height = height
        self.showsHeader = showsHeader
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
            let yValues = buckets.flatMap { [$0.min, $0.p25, $0.median, $0.p75, $0.max] }
            let yDomain = ChartAxisSupport.smartYDomain(
                values: yValues,
                baseline: snapshot.baselineBand,
                clampRange: 0...100,
                minSpan: 20
            )
            let yTicks = ChartAxisSupport.yAxisTicks(for: yDomain, count: 3)
            let capsuleWidth = max(4.5, min(11.0, 210.0 / CGFloat(max(1, buckets.count))))
            let header = headerStrings(buckets: buckets)

            VStack(alignment: .leading, spacing: BSSpace.s) {
                if showsHeader {
                    ChartLockedReadoutHeader(
                        primaryText: header.primary,
                        secondaryText: header.secondary,
                        tint: tint,
                        isLocked: selectedBucket != nil,
                        onClear: selectedBucket == nil ? nil : {
                            rawSelectedDate = nil
                            selectedBucket = nil
                            onSelectBucket?(nil)
                        }
                    )
                    .accessibilityIdentifier("trends-capsule-chart-readout")
                }

                Chart {
                    rollingBandMarks(buckets: buckets, yDomain: yDomain)

                    ForEach(buckets) { bucket in
                        capsuleMarks(bucket, capsuleWidth: capsuleWidth)
                    }
                }
                .chartXScale(domain: domain)
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
                .chartXAxis(.hidden)
                .chartXSelection(value: $rawSelectedDate)
                .onChange(of: rawSelectedDate) { _, newValue in
                    handleSelectionChange(newValue, buckets: buckets)
                }
                .onChange(of: snapshot.kind) { _, _ in
                    rawSelectedDate = nil
                    selectedBucket = nil
                    onSelectBucket?(nil)
                }
                .onChange(of: snapshot.horizon) { _, _ in
                    rawSelectedDate = nil
                    selectedBucket = nil
                    onSelectBucket?(nil)
                }
                .frame(height: height)
                .bodyseekSelectionHaptic(trigger: selectedBucket?.id)
                .accessibilityChartDescriptor(
                    NumericSeriesAXDescriptor(
                        title: "\(snapshot.kind.title)\(snapshot.horizon.title)区间胶囊",
                        summary: snapshot.statusSummary,
                        points: buckets.map { ($0.label, $0.median) },
                        yAxisTitle: unitLabel,
                        yRange: yDomain
                    )
                )

                axisFooter(domain: domain)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("trends-capsule-chart")
        }
    }

    /// UI v4：按每个桶最后一天的滚动分位画平时范围（中性灰），不足 7 天有效观测的桶不画。
    @ChartContentBuilder
    private func rollingBandMarks(buckets: [RangeCapsuleBucket], yDomain: ClosedRange<Double>) -> some ChartContent {
        ForEach(buckets) { bucket in
            if let band = bucket.rollingBand {
                let low = min(yDomain.upperBound, max(yDomain.lowerBound, band.lower))
                let high = max(low, min(yDomain.upperBound, band.upper))
                AreaMark(
                    x: .value("周期", midpointDate(for: bucket)),
                    yStart: .value("平时下沿", low),
                    yEnd: .value("平时上沿", high),
                    series: .value("平时范围", "rolling")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.secondary.opacity(BSOpacity.faint))
            }
        }
    }

    /// 一个胶囊：P25–P75 的圆角柱 + 嵌在里面的中位白点；选中后其余胶囊变成 `dimmed`。没有极值须线。
    @ChartContentBuilder
    private func capsuleMarks(_ bucket: RangeCapsuleBucket, capsuleWidth: CGFloat) -> some ChartContent {
        let mid = midpointDate(for: bucket)
        let isDimmed = selectedBucket != nil && selectedBucket?.id != bucket.id
        let color = isDimmed ? BSColor.dimmed : tint
        if bucket.p25 == bucket.p75, bucket.sampleCount == 1 {
            PointMark(x: .value("周期", mid), y: .value("中位", bucket.median))
                .foregroundStyle(color)
        } else {
            BarMark(
                x: .value("周期", mid),
                yStart: .value("P25", bucket.p25),
                yEnd: .value("P75", bucket.p75),
                width: .fixed(capsuleWidth)
            )
            .cornerRadius(capsuleWidth / 2)
            .foregroundStyle(color)

            PointMark(x: .value("周期", mid), y: .value("中位", bucket.median))
                .symbol {
                    Circle()
                        .fill(BSColor.surface)
                        .frame(width: max(BSChartStroke.data, capsuleWidth - BSChartStroke.data))
                }
        }
    }

    private func handleSelectionChange(_ date: Date?, buckets: [RangeCapsuleBucket]) {
        guard let date else {
            if !showsHeader, selectedBucket != nil {
                selectedBucket = nil
                onSelectBucket?(nil)
            }
            return
        }
        guard let nearest = buckets.min(by: {
            abs(midpointDate(for: $0).timeIntervalSince(date))
                < abs(midpointDate(for: $1).timeIntervalSince(date))
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
    @ViewBuilder
    private func axisFooter(domain: ClosedRange<Date>) -> some View {
        if snapshot.horizon.bucketUnit == .day {
            HStack(spacing: BSSpace.none) {
                ForEach(snapshot.dailyPoints) { pt in
                    Text(dayLabel(for: pt.date))
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.caption2.monospacedDigit())
            .fontDesign(.rounded)
            .foregroundStyle(BevelTheme.inkSecondary)
            .accessibilityHidden(true)
        } else {
            let middle = domain.lowerBound.addingTimeInterval(
                domain.upperBound.timeIntervalSince(domain.lowerBound) / 2.0
            )
            HStack(spacing: BSSpace.none) {
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
    }

    private static let localCalendar = Calendar.current

    private func dayLabel(for date: Date) -> String {
        let calendar = Self.localCalendar
        return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
    }

    private var bucketUnitTitle: String {
        switch snapshot.horizon.bucketUnit {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        }
    }

    private func headerStrings(buckets: [RangeCapsuleBucket]) -> (primary: String, secondary: String) {
        if let b = selectedBucket {
            let med = Int(b.median.rounded())
            let spanText: String
            if b.p25 == b.p75 {
                spanText = "单日样本"
            } else {
                spanText = "P25–P75 \(Int(b.p25.rounded()))–\(Int(b.p75.rounded()))"
            }
            return (
                "\(b.label) · 中位 \(med)\(unitLabel)",
                "\(spanText) · 覆盖 \(b.sampleCount)/\(b.totalDays)天"
            )
        }
        let medText = snapshot.medianValue.map { "中位 \(Int($0.rounded())) \(unitLabel)" } ?? "--"
        return (
            medText,
            "\(buckets.count) 个\(bucketUnitTitle)胶囊 · \(snapshot.coveredDays)/\(snapshot.totalDays)天"
        )
    }
}
