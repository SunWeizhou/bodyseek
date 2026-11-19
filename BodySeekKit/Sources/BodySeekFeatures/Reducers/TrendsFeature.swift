import BodySeekCore
import ComposableArchitecture
import Foundation

@Reducer
public struct TrendsFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var horizon: TrendHorizon = .month {
            didSet {
                if oldValue != horizon {
                    refreshActiveSlices()
                }
            }
        }

        public var selectedKind: MetricKind = .recovery {
            didSet {
                if oldValue != selectedKind {
                    refreshActiveSlices()
                }
            }
        }

        public var selectedDate: Date?
        public var showCoverageSheet: Bool = false
        public var snapshot: BodySeekDashboardSnapshot
        public var chartCache: [TrendHorizon: [MetricKind: ChartSeriesSnapshot]]
        public var activeChartSnapshot: ChartSeriesSnapshot
        public var allMetricSnapshots: [ChartSeriesSnapshot]
        public var activeSeries: TrendSeries
        public var allMetricSeries: [TrendSeries]

        public init(
            snapshot: BodySeekDashboardSnapshot,
            precomputedCache: [TrendHorizon: [MetricKind: ChartSeriesSnapshot]]? = nil
        ) {
            let initialHorizon: TrendHorizon = .month
            let initialKind: MetricKind = .recovery
            let resolvedCache = precomputedCache ?? BevelScoringEngine.buildAllChartSnapshots(
                days: snapshot.historyDays,
                referenceDate: snapshot.referenceDate
            )
            let slices = Self.deriveSlices(
                cache: resolvedCache,
                horizon: initialHorizon,
                selectedKind: initialKind,
                snapshot: snapshot
            )
            self.snapshot = snapshot
            self.chartCache = resolvedCache
            self.activeChartSnapshot = slices.activeSnapshot
            self.allMetricSnapshots = slices.allSnapshots
            self.activeSeries = slices.activeSeries
            self.allMetricSeries = slices.allSeries
        }

        public mutating func updateSnapshot(
            _ newSnapshot: BodySeekDashboardSnapshot,
            precomputedCache: [TrendHorizon: [MetricKind: ChartSeriesSnapshot]]? = nil
        ) {
            self.snapshot = newSnapshot
            self.chartCache = precomputedCache ?? BevelScoringEngine.buildAllChartSnapshots(
                days: newSnapshot.historyDays,
                referenceDate: newSnapshot.referenceDate
            )
            refreshActiveSlices()
        }

        private mutating func refreshActiveSlices() {
            let slices = Self.deriveSlices(
                cache: chartCache,
                horizon: horizon,
                selectedKind: selectedKind,
                snapshot: snapshot
            )
            self.activeChartSnapshot = slices.activeSnapshot
            self.allMetricSnapshots = slices.allSnapshots
            self.activeSeries = slices.activeSeries
            self.allMetricSeries = slices.allSeries
        }

        private struct DerivedSlices {
            let activeSnapshot: ChartSeriesSnapshot
            let allSnapshots: [ChartSeriesSnapshot]
            let activeSeries: TrendSeries
            let allSeries: [TrendSeries]
        }

        private static func deriveSlices(
            cache: [TrendHorizon: [MetricKind: ChartSeriesSnapshot]],
            horizon: TrendHorizon,
            selectedKind: MetricKind,
            snapshot: BodySeekDashboardSnapshot
        ) -> DerivedSlices {
            let horizonMap = cache[horizon] ?? [:]
            let allSnapshots: [ChartSeriesSnapshot] = MetricKind.allCases.map { kind in
                horizonMap[kind] ?? BevelScoringEngine.buildChartSeriesSnapshot(
                    for: kind,
                    horizon: horizon,
                    days: snapshot.historyDays,
                    referenceDate: snapshot.referenceDate
                )
            }
            let activeSnapshot = horizonMap[selectedKind]
                ?? allSnapshots.first(where: { $0.kind == selectedKind })
                ?? allSnapshots[0]
            let allSeries = allSnapshots.map { $0.toLegacyTrendSeries() }
            let activeSeries = activeSnapshot.toLegacyTrendSeries()
            return DerivedSlices(
                activeSnapshot: activeSnapshot,
                allSnapshots: allSnapshots,
                activeSeries: activeSeries,
                allSeries: allSeries
            )
        }
    }

    public enum Action: Equatable, Sendable {
        case horizonChanged(TrendHorizon)
        case kindSelected(MetricKind)
        case selectedDateChanged(Date?)
        case coverageSheetPresented(Bool)
        case openMetricDetail(MetricKind)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case openMetric(MetricKind, TrendHorizon)
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .horizonChanged(horizon):
                state.horizon = horizon
                state.selectedDate = nil
                return .none

            case let .kindSelected(kind):
                state.selectedKind = kind
                state.selectedDate = nil
                return .none

            case let .selectedDateChanged(date):
                state.selectedDate = date
                return .none

            case let .coverageSheetPresented(presented):
                state.showCoverageSheet = presented
                return .none

            case let .openMetricDetail(kind):
                return .send(.delegate(.openMetric(kind, state.horizon)))

            case .delegate:
                return .none
            }
        }
    }
}
