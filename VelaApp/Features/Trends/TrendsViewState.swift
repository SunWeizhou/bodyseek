import Foundation

/// A chart point is value-only.  A missing day is represented by a point with
/// a nil value so renderers can preserve the temporal gap instead of drawing a
/// misleading zero or connecting across days without evidence.
struct TrendsChartPoint: Equatable, Hashable, Identifiable, Sendable {
    let date: Date
    let value: Double?
    let provenance: TrendsPointProvenance?

    var id: Date { date }
}

enum TrendsDataSource: String, Codable, Equatable, Hashable, Sendable {
    case healthKit
    case userInput
    case derived
    case mixed
    case unavailable
}

/// Provenance is supplied by the history adapter.  The Store and chart only
/// transport it; they never infer a source from a value or silently promote a
/// missing reading to a derived zero.
struct TrendsPointProvenance: Codable, Equatable, Hashable, Sendable {
    let source: TrendsDataSource
    let sourceLabel: String
    let detail: String?

    init(
        source: TrendsDataSource,
        sourceLabel: String? = nil,
        detail: String? = nil
    ) {
        self.source = source
        self.sourceLabel = sourceLabel ?? source.rawValue
        self.detail = detail
    }
}

struct TrendsHistoryPayload: Sendable {
    let snapshots: [DailyHealthSnapshot]
    let finding: HealthTrendFinding?
    let baselineBand: ClosedRange<Double>?
    let provenanceByDay: [Date: TrendsPointProvenance]

    init(
        snapshots: [DailyHealthSnapshot] = [],
        finding: HealthTrendFinding? = nil,
        baselineBand: ClosedRange<Double>? = nil,
        provenanceByDay: [Date: TrendsPointProvenance] = [:]
    ) {
        self.snapshots = snapshots
        self.finding = finding
        self.baselineBand = baselineBand
        self.provenanceByDay = provenanceByDay
    }
}

struct TrendsMetricSeries: Equatable, Sendable {
    let metric: CoreHealthMetric
    let horizon: HealthTrendHorizon
    let selectedDay: Date
    let points: [TrendsChartPoint]
    let baselineBand: ClosedRange<Double>?
    let finding: HealthTrendFinding?

    /// Non-missing runs are the only values a line chart may connect.  This
    /// keeps a missing day as a visible gap while still allowing each run to
    /// render as a smooth Swift Charts line/area segment.
    var nonMissingSegments: [[TrendsChartPoint]] {
        var segments: [[TrendsChartPoint]] = []
        var current: [TrendsChartPoint] = []
        for point in points {
            guard point.value != nil else {
                if !current.isEmpty {
                    segments.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }
            current.append(point)
        }
        if !current.isEmpty {
            segments.append(current)
        }
        return segments
    }

    var hasValue: Bool { points.contains { $0.value != nil } }
}

enum TrendsLoadPhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case empty
    case failed
}

struct TrendsPresentationState: Equatable, Sendable {
    let selectedDay: Date
    let horizon: HealthTrendHorizon
    let metric: CoreHealthMetric
    let phase: TrendsLoadPhase
    let finding: HealthTrendFinding?
    let baselineBand: ClosedRange<Double>?
    let observedPointCount: Int
}

struct TrendsViewState: Equatable, Sendable {
    var selectedDay: Date
    var horizon: HealthTrendHorizon
    var metric: CoreHealthMetric
    var phase: TrendsLoadPhase
    var series: TrendsMetricSeries?
    var selectedPoint: TrendsChartPoint?
    var errorMessage: String?

    var bodySeekPresentation: TrendsPresentationState {
        TrendsPresentationState(
            selectedDay: selectedDay,
            horizon: horizon,
            metric: metric,
            phase: phase,
            finding: series?.finding,
            baselineBand: series?.baselineBand,
            observedPointCount: series?.points.compactMap(\.value).count ?? 0
        )
    }

    static func initial(
        selectedDay: Date,
        horizon: HealthTrendHorizon = .thirtyDays,
        metric: CoreHealthMetric = .recovery
    ) -> TrendsViewState {
        TrendsViewState(
            selectedDay: selectedDay,
            horizon: horizon,
            metric: metric,
            phase: .idle,
            series: nil,
            selectedPoint: nil,
            errorMessage: nil
        )
    }
}
