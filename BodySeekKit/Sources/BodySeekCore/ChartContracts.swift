import Foundation

public struct BaselineBand: Hashable, Codable, Sendable {
    public let lower: Double
    public let upper: Double

    public init(lower: Double, upper: Double) {
        self.lower = min(lower, upper)
        self.upper = max(lower, upper)
    }

    public var range: ClosedRange<Double> {
        lower...upper
    }
}

public struct ChartPointSnapshot: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let dayKey: DayKey
    public let date: Date
    public let value: Double?
    public let baselineLow: Double?
    public let baselineHigh: Double?
    public let availability: MetricAvailability

    public init(
        id: String? = nil,
        dayKey: DayKey,
        date: Date,
        value: Double?,
        baselineLow: Double? = nil,
        baselineHigh: Double? = nil,
        availability: MetricAvailability
    ) {
        self.id = id ?? dayKey.isoString
        self.dayKey = dayKey
        self.date = date
        self.value = value
        self.baselineLow = baselineLow
        self.baselineHigh = baselineHigh
        self.availability = availability
    }
}

public struct RangeCapsuleBucket: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let label: String
    public let startDayKey: DayKey
    public let endDayKey: DayKey
    public let startDate: Date
    public let endDate: Date
    public let min: Double
    public let p25: Double
    public let median: Double
    public let p75: Double
    public let max: Double
    public let sampleCount: Int
    public let totalDays: Int

    public init(
        id: String,
        label: String,
        startDayKey: DayKey,
        endDayKey: DayKey,
        startDate: Date,
        endDate: Date,
        min: Double,
        p25: Double,
        median: Double,
        p75: Double,
        max: Double,
        sampleCount: Int,
        totalDays: Int
    ) {
        self.id = id
        self.label = label
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
        self.startDate = startDate
        self.endDate = endDate
        self.min = min
        self.p25 = p25
        self.median = median
        self.p75 = p75
        self.max = max
        self.sampleCount = sampleCount
        self.totalDays = totalDays
    }
}

public struct ChartSeriesSnapshot: Hashable, Codable, Sendable {
    public let kind: MetricKind
    public let horizon: TrendHorizon
    public let referenceDayKey: DayKey
    public let dailyPoints: [ChartPointSnapshot]
    public let capsules: [RangeCapsuleBucket]
    public let baselineBand: BaselineBand?
    public let medianValue: Double?
    public let halfDelta: Int?
    public let coveredDays: Int
    public let totalDays: Int
    public let statusSummary: String
    public let algorithmVersion: AlgorithmVersion

    public init(
        kind: MetricKind,
        horizon: TrendHorizon,
        referenceDayKey: DayKey,
        dailyPoints: [ChartPointSnapshot],
        capsules: [RangeCapsuleBucket],
        baselineBand: BaselineBand?,
        medianValue: Double?,
        halfDelta: Int?,
        coveredDays: Int,
        totalDays: Int,
        statusSummary: String,
        algorithmVersion: AlgorithmVersion = .scoreV2
    ) {
        self.kind = kind
        self.horizon = horizon
        self.referenceDayKey = referenceDayKey
        self.dailyPoints = dailyPoints
        self.capsules = capsules
        self.baselineBand = baselineBand
        self.medianValue = medianValue
        self.halfDelta = halfDelta
        self.coveredDays = coveredDays
        self.totalDays = totalDays
        self.statusSummary = statusSummary
        self.algorithmVersion = algorithmVersion
    }

    public func toLegacyTrendSeries() -> TrendSeries {
        let points = dailyPoints.map { point in
            TrendPoint(
                date: point.date,
                value: point.value.map { Int($0.rounded()) },
                availability: point.availability
            )
        }
        return TrendSeries(
            kind: kind,
            horizon: horizon,
            points: points,
            baselineRange: baselineBand?.range,
            coveredDays: coveredDays,
            totalDays: totalDays,
            median: medianValue.map { Int($0.rounded()) },
            deltaFromFirstHalf: halfDelta,
            statusSummary: statusSummary
        )
    }
}

public struct MetricDetailViewState: Hashable, Codable, Sendable {
    public let kind: MetricKind
    public let dayKey: DayKey
    public let score: MetricScore
    public let chart30d: ChartSeriesSnapshot
    public let contributors: [MetricContributor]
    public let baselineText: String?
    public let dataCoverage: Double
    public let sources: [SourceRef]
    public let algorithmVersion: AlgorithmVersion

    public init(
        kind: MetricKind,
        dayKey: DayKey,
        score: MetricScore,
        chart30d: ChartSeriesSnapshot,
        contributors: [MetricContributor],
        baselineText: String?,
        dataCoverage: Double,
        sources: [SourceRef],
        algorithmVersion: AlgorithmVersion = .scoreV2
    ) {
        self.kind = kind
        self.dayKey = dayKey
        self.score = score
        self.chart30d = chart30d
        self.contributors = contributors
        self.baselineText = baselineText
        self.dataCoverage = min(1.0, max(0.0, dataCoverage))
        self.sources = sources
        self.algorithmVersion = algorithmVersion
    }
}
