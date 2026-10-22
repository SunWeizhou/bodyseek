import Foundation

/// One dated sample for a personal baseline.
public struct BaselineSample: Hashable, Sendable {
    public var date: Date
    public var value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Robust personal baseline over a calendar window that ends yesterday.
public struct BaselineEstimate: Hashable, Sendable {
    public var median: Double
    /// Normal-consistent MAD (`1.4826 × MAD`). Nil when every sample is identical.
    public var robustScale: Double?
    public var sampleCount: Int
    /// Chronological values, one per calendar day, excluding `asOf`'s day.
    public var values: [Double]
    public var earliest: Date
    public var latest: Date

    public init(
        median: Double,
        robustScale: Double?,
        sampleCount: Int,
        values: [Double],
        earliest: Date,
        latest: Date
    ) {
        self.median = median
        self.robustScale = robustScale
        self.sampleCount = sampleCount
        self.values = values
        self.earliest = earliest
        self.latest = latest
    }
}

/// Shared baseline for scoring, trends, and AI context.
///
/// The window is calendar days and stops before `asOf`, so today is never part
/// of the baseline it is compared against. Each day contributes one sample.
/// Days without a sample are omitted; they are not zeros. The center is the
/// median and the scale is the MAD.
public enum BaselineEstimator {
    /// Inside this band the value is within the person's usual variation.
    public static let stableZ = 1.0
    /// Outside this band the value is a notable departure from that variation.
    public static let notableZ = 2.0

    /// Prior-day samples inside the window, one value per calendar day, oldest first.
    public static func samples(
        from samples: [BaselineSample],
        asOf: Date,
        windowDays: Int,
        calendar: Calendar
    ) -> [BaselineSample] {
        let dayCount = max(windowDays, 1)
        let end = calendar.startOfDay(for: asOf)
        let start = calendar.date(byAdding: .day, value: -dayCount, to: end) ?? end

        var byDay: [Date: BaselineSample] = [:]
        for sample in samples where sample.value.isFinite {
            let day = calendar.startOfDay(for: sample.date)
            guard day >= start, day < end else { continue }
            if let existing = byDay[day], sample.date < existing.date {
                continue
            }
            byDay[day] = BaselineSample(date: sample.date, value: sample.value)
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    public static func estimate(
        samples: [BaselineSample],
        asOf: Date,
        windowDays: Int,
        minimumSamples: Int,
        calendar: Calendar
    ) -> BaselineEstimate? {
        let window = self.samples(
            from: samples,
            asOf: asOf,
            windowDays: windowDays,
            calendar: calendar
        )
        guard window.count >= max(minimumSamples, 1),
              let median = ScoringMath.median(window.map(\.value)),
              let earliest = window.first?.date,
              let latest = window.last?.date else {
            return nil
        }
        return BaselineEstimate(
            median: median,
            robustScale: ScoringMath.robustStandardDeviation(window.map(\.value), around: median),
            sampleCount: window.count,
            values: window.map(\.value),
            earliest: earliest,
            latest: latest
        )
    }

    /// Robust z of `value` against a baseline. A flat history has no scale;
    /// any real difference is then outside every observed day.
    public static func zScore(value: Double, median: Double, robustScale: Double?) -> Double {
        guard value.isFinite, median.isFinite else { return 0 }
        if let scale = robustScale, scale > 0, scale.isFinite {
            return (value - median) / scale
        }
        if value == median { return 0 }
        return value > median ? notableZ * 2 : -notableZ * 2
    }
}
