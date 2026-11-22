import BodySeekCore
import Charts
import SwiftUI

/// Native Apple Health-style percentile capsule chart for 7d (daily), 30d/6m (weekly), and 3y (monthly) horizons.
public struct RangeCapsuleChart: View {
    public let snapshot: ChartSeriesSnapshot
    public let tint: Color
    public let unitLabel: String
    public let height: CGFloat
    public let onSelectBucket: (@MainActor (RangeCapsuleBucket?) -> Void)?

    @State private var rawSelectedDate: Date?
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

            VStack(alignment: .leading, spacing: 10) {
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

                Chart {
                    if let band = snapshot.baselineBand {
                        let clampedLow = min(yDomain.upperBound, max(yDomain.lowerBound, band.lower))
                        let clampedHigh = max(clampedLow, min(yDomain.upperBound, band.upper))
                        RectangleMark(
                            yStart: .value("基线下界", clampedLow),
                            yEnd: .value("基线上界", clampedHigh)
                        )
                        .foregroundStyle(tint.opacity(0.08))
                    }

                    if let median = snapshot.medianValue {
                        RuleMark(y: .value("中位", median))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(BevelTheme.inkSecondary.opacity(0.45))
                    }

                    if let selectedBucket {
                        let selMid = midpointDate(for: selectedBucket)
                        let med = Int(selectedBucket.median.rounded())
                        let sub: String = selectedBucket.p25 == selectedBucket.p75
                            ? selectedBucket.label
                            : "\(selectedBucket.label) · P25–75 \(Int(selectedBucket.p25.rounded()))–\(Int(selectedBucket.p75.rounded()))"
                        RuleMark(x: .value("选中周期", selMid))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(tint.opacity(0.75))
                            .annotation(
                                position: .top,
                                spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                            ) {
                                ChartSelectionCallout(
                                    valueText: "\(med) \(unitLabel)",
                                    subtitleText: sub,
                                    tint: tint
                                )
                            }
                    }

                    ForEach(buckets) { bucket in
                        let mid = midpointDate(for: bucket)
                        let isSelected = selectedBucket?.id == bucket.id

                        if bucket.p25 == bucket.p75, bucket.sampleCount == 1 {
                            let bottom = min(bucket.median, yDomain.lowerBound)
                            BarMark(
                                x: .value("周期", mid),
                                yStart: .value("底", bottom),
                                yEnd: .value("值", bucket.median),
                                width: .fixed(capsuleWidth)
                            )
                            .cornerRadius(capsuleWidth / 2)
                            .foregroundStyle(tint.opacity(isSelected ? 0.90 : 0.34))

                            PointMark(
                                x: .value("周期", mid),
                                y: .value("中位", bucket.median)
                            )
                            .symbol {
                                Circle()
                                    .fill(isSelected ? BevelTheme.ink : tint)
                                    .overlay(Circle().strokeBorder(BevelTheme.card, lineWidth: 1.5))
                                    .frame(width: isSelected ? 8.5 : 6.5, height: isSelected ? 8.5 : 6.5)
                            }
                        } else {
                            RuleMark(
                                x: .value("周期", mid),
                                yStart: .value("极小", bucket.min),
                                yEnd: .value("极大", bucket.max)
                            )
                            .lineStyle(StrokeStyle(lineWidth: 1.3, lineCap: .round))
                            .foregroundStyle(tint.opacity(isSelected ? 0.65 : 0.28))

                            BarMark(
                                x: .value("周期", mid),
                                yStart: .value("P25", bucket.p25),
                                yEnd: .value("P75", bucket.p75),
                                width: .fixed(capsuleWidth)
                            )
                            .cornerRadius(capsuleWidth / 2)
                            .foregroundStyle(tint.opacity(isSelected ? 0.92 : 0.46))

                            PointMark(
                                x: .value("周期", mid),
                                y: .value("中位", bucket.median)
                            )
                            .symbol {
                                Circle()
                                    .fill(isSelected ? BevelTheme.ink : tint)
                                    .overlay(Circle().strokeBorder(BevelTheme.card, lineWidth: 1.5))
                                    .frame(width: isSelected ? 8.5 : 6.5, height: isSelected ? 8.5 : 6.5)
                            }
                        }
                    }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: yDomain)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: yTicks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(BevelTheme.hairline.opacity(0.7))
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

    private func handleSelectionChange(_ date: Date?, buckets: [RangeCapsuleBucket]) {
        guard let date else {
            if selectedBucket != nil {
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
            HStack(spacing: 0) {
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
            HStack(spacing: 0) {
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
