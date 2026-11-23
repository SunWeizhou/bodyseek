import BodySeekCore
import Charts
import SwiftUI

public enum ChartAxisSupport {
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans")
        f.dateFormat = "M/d"
        return f
    }()

    private static let yearMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans")
        f.dateFormat = "yy/M月"
        return f
    }()

    private static let monthOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans")
        f.dateFormat = "M月"
        return f
    }()

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let fullDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans")
        f.dateFormat = "M月d日"
        return f
    }()

    private static let fullYearDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    public static func formatAxisDate(_ date: Date, horizon: TrendHorizon) -> String {
        switch horizon {
        case .week, .month:
            monthDayFormatter.string(from: date)
        case .sixMonths:
            monthOnlyFormatter.string(from: date)
        case .threeYears:
            yearMonthFormatter.string(from: date)
        }
    }

    public static func formatReadoutDate(_ date: Date, horizon: TrendHorizon) -> String {
        switch horizon {
        case .week, .month:
            fullDayFormatter.string(from: date)
        case .sixMonths, .threeYears:
            fullYearDayFormatter.string(from: date)
        }
    }

    public static func formatHour(_ date: Date) -> String {
        hourFormatter.string(from: date)
    }

    /// Computes up to 4 evenly spaced explicit X-axis tick dates so ticks never collide or truncate.
    public static func explicitTickDates(from dates: [Date], maxTicks: Int = 4) -> [Date] {
        guard !dates.isEmpty else { return [] }
        let sorted = dates.sorted()
        guard let first = sorted.first, let last = sorted.last, first < last else {
            return [sorted[0]]
        }
        let clampedCount = max(2, min(maxTicks, 4))
        let totalSpan = last.timeIntervalSince(first)
        guard totalSpan > 0 else { return [first] }

        // Keep an inset near the trailing edge so the final tick never clips against trailing Y-axis labels.
        var ticks: [Date] = []
        ticks.reserveCapacity(clampedCount)
        let steps = clampedCount - 1
        for i in 0...steps {
            let fraction = Double(i) / Double(steps)
            let easedFraction = i == steps ? 0.88 : (i == 0 ? 0.06 : fraction * 0.94)
            ticks.append(first.addingTimeInterval(totalSpan * easedFraction))
        }
        return ticks
    }

    /// Splits a series of `ChartPointSnapshot` into contiguous non-missing segments for honest line breaks.
    public struct ContiguousPoint: Identifiable, Hashable {
        public let id: String
        public let segmentID: Int
        public let point: ChartPointSnapshot
        public let numericValue: Double
        public let isKnownZero: Bool

        public init(segmentID: Int, point: ChartPointSnapshot, numericValue: Double, isKnownZero: Bool) {
            self.id = "\(segmentID)-\(point.id)"
            self.segmentID = segmentID
            self.point = point
            self.numericValue = numericValue
            self.isKnownZero = isKnownZero
        }
    }

    public static func segmentedPoints(from points: [ChartPointSnapshot]) -> [ContiguousPoint] {
        var result: [ContiguousPoint] = []
        result.reserveCapacity(points.count)
        var currentSegment = 0
        var inSegment = false

        for pt in points {
            switch pt.availability {
            case .available:
                if let val = pt.value, val.isFinite {
                    if !inSegment {
                        currentSegment += 1
                        inSegment = true
                    }
                    result.append(ContiguousPoint(segmentID: currentSegment, point: pt, numericValue: val, isKnownZero: false))
                } else {
                    inSegment = false
                }
            case .knownZero:
                let val = pt.value ?? 0
                if !inSegment {
                    currentSegment += 1
                    inSegment = true
                }
                result.append(ContiguousPoint(segmentID: currentSegment, point: pt, numericValue: val, isKnownZero: true))
            case .missing, .excluded:
                inSegment = false
            }
        }
        return result
    }

    /// Computes an Apple Health-style adaptive Y-axis domain with breathing room and clean tick snapping.
    public static func smartYDomain(
        values: [Double],
        baseline: BaselineBand? = nil,
        clampRange: ClosedRange<Double>? = 0...100,
        minSpan: Double = 16
    ) -> ClosedRange<Double> {
        var finite = values.filter(\.isFinite)
        if let baseline, baseline.lower.isFinite, baseline.upper.isFinite {
            finite.append(baseline.lower)
            finite.append(baseline.upper)
        }
        guard var lo = finite.min(), var hi = finite.max() else {
            return clampRange ?? 0...100
        }

        let effectiveMinSpan = max(minSpan, 1e-3)
        if (hi - lo) < effectiveMinSpan {
            let mid = (lo + hi) * 0.5
            lo = mid - effectiveMinSpan * 0.5
            hi = mid + effectiveMinSpan * 0.5
        }

        let headroom = max((hi - lo) * 0.14, effectiveMinSpan * 0.08)
        lo -= headroom
        hi += headroom

        let rawSpan = hi - lo
        let step: Double = if rawSpan >= 40 {
            10
        } else if rawSpan >= 18 {
            5
        } else if rawSpan >= 7 {
            2
        } else if rawSpan >= 2.5 {
            1
        } else if rawSpan >= 0.8 {
            0.5
        } else {
            0.05
        }

        lo = floor(lo / step) * step
        hi = ceil(hi / step) * step

        if let clampRange {
            let cLo = clampRange.lowerBound
            let cHi = clampRange.upperBound
            lo = max(cLo, lo)
            hi = min(cHi, hi)
            if hi - lo < effectiveMinSpan {
                let targetSpan = min(effectiveMinSpan, cHi - cLo)
                if hi + (targetSpan - (hi - lo)) <= cHi {
                    hi = lo + targetSpan
                } else {
                    lo = max(cLo, hi - targetSpan)
                }
            }
            if hi <= lo {
                return clampRange
            }
        } else if hi <= lo {
            return lo...(lo + max(1.0, effectiveMinSpan))
        }

        return lo...hi
    }

    /// Returns evenly spaced Y-axis gridline values across an adaptive domain.
    public static func yAxisTicks(for domain: ClosedRange<Double>, count: Int = 3) -> [Double] {
        let clampedCount = max(2, count)
        let lo = domain.lowerBound
        let hi = domain.upperBound
        let span = hi - lo
        guard span > 1e-6 else { return [lo] }

        return (0..<clampedCount).map { idx in
            if idx == 0 { return lo }
            if idx == clampedCount - 1 { return hi }
            let raw = lo + span * Double(idx) / Double(clampedCount - 1)
            return span >= 6 ? raw.rounded() : (raw * 10).rounded() / 10
        }
    }

    public static func formatYAxisTick(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }
}

/// Compact Apple Health-style floating callout rendered over selected Chart rules.
public struct ChartSelectionCallout: View {
    public let valueText: String
    public let subtitleText: String
    public let tint: Color

    public init(valueText: String, subtitleText: String, tint: Color) {
        self.valueText = valueText
        self.subtitleText = subtitleText
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .center, spacing: BSSpace.none) {
            Text(valueText)
                .font(.caption.weight(.bold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(tint)
            Text(subtitleText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(BevelTheme.inkSecondary)
        }
        .padding(.horizontal, BSSpace.xs)
        .padding(.vertical, BSSpace.xxs)
        .background(BSColor.surface, in: RoundedRectangle(cornerRadius: BSRadius.s, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.s, style: .continuous)
                .strokeBorder(BevelTheme.hairline, lineWidth: BSChartStroke.rule)
        )
    }
}

/// Subtle diagonal hatch view rendered behind excluded periods (e.g., workout hours or invalid artifacts).
public struct DiagonalHatchView: View {
    public let tint: Color
    public let spacing: CGFloat

    public init(tint: Color = BevelTheme.inkSecondary, spacing: CGFloat = 6) {
        self.tint = tint
        self.spacing = spacing
    }

    public var body: some View {
        Canvas { context, size in
            var path = Path()
            let total = size.width + size.height
            var x: CGFloat = -size.height
            while x < total {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(tint.opacity(BSOpacity.muted)), lineWidth: BSChartStroke.rule)
        }
        .clipped()
    }
}

/// Top locked readout bar replacing floating overlay tooltips to avoid thumb occlusion.
public struct ChartLockedReadoutHeader: View {
    public let primaryText: String
    public let secondaryText: String
    public let tint: Color
    public let isLocked: Bool
    public let onClear: (() -> Void)?

    public init(
        primaryText: String,
        secondaryText: String,
        tint: Color,
        isLocked: Bool,
        onClear: (() -> Void)? = nil
    ) {
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.tint = tint
        self.isLocked = isLocked
        self.onClear = onClear
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: BSSpace.xs) {
                primaryLabel
                Spacer(minLength: 6)
                trailingControls
            }

            VStack(alignment: .leading, spacing: BSSpace.xxs) {
                primaryLabel
                trailingControls
            }
        }
    }

    private var primaryLabel: some View {
        Text(primaryText)
            .font(.title3.weight(.bold).monospacedDigit())
            .fontDesign(.rounded)
            .contentTransition(.numericText())
            .foregroundStyle(isLocked ? tint : BevelTheme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var trailingControls: some View {
        HStack(spacing: BSSpace.xs) {
            Text(secondaryText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(BevelTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if isLocked, let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }
                .buttonStyle(.bsPressable)
                .accessibilityLabel("清除选点")
            }
        }
    }
}

public struct ChartEmptyPlaceholder: View {
    public let title: String
    public let systemImage: String
    public let height: CGFloat

    public init(
        title: String = "当前时间窗口内暂无可绘制数据",
        systemImage: String = "chart.xyaxis.line",
        height: CGFloat = 196
    ) {
        self.title = title
        self.systemImage = systemImage
        self.height = height
    }

    public var body: some View {
        VStack(spacing: BSSpace.xs) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(BevelTheme.inkSecondary)
            Text(title)
                .font(.footnote)
                .foregroundStyle(BevelTheme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

public struct NumericSeriesAXDescriptor: AXChartDescriptorRepresentable {
    public let title: String
    public let summary: String
    public let points: [(label: String, value: Double)]
    public let yAxisTitle: String
    public let yRange: ClosedRange<Double>

    public init(
        title: String,
        summary: String,
        points: [(label: String, value: Double)],
        yAxisTitle: String = "数值",
        yRange: ClosedRange<Double> = 0...100
    ) {
        self.title = title
        self.summary = summary
        self.points = points
        self.yAxisTitle = yAxisTitle
        self.yRange = yRange
    }

    public func makeChartDescriptor() -> AXChartDescriptor {
        let categories = points.map(\.label)
        let xAxis = AXCategoricalDataAxisDescriptor(
            title: "日期",
            categoryOrder: categories
        )
        let yAxis = AXNumericDataAxisDescriptor(
            title: yAxisTitle,
            range: yRange,
            gridlinePositions: []
        ) { value in
            "\(Int(value.rounded()))"
        }
        let dataPoints = points.map { item in
            AXDataPoint(x: item.label, y: item.value)
        }
        let series = AXDataSeriesDescriptor(
            name: title,
            isContinuous: true,
            dataPoints: dataPoints
        )
        return AXChartDescriptor(
            title: title,
            summary: summary,
            xAxis: xAxis,
            yAxis: yAxis,
            series: [series]
        )
    }
}
