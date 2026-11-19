import BodySeekCore
import ComposableArchitecture
import Foundation

@Reducer
public struct TrendsFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var horizon: TrendHorizon = .month
        public var selectedKind: MetricKind = .recovery
        public var selectedDate: Date?
        public var showCoverageSheet: Bool = false
        public var snapshot: BodySeekDashboardSnapshot

        public init(snapshot: BodySeekDashboardSnapshot) {
            self.snapshot = snapshot
        }

        public var activeSeries: TrendSeries {
            BevelScoringEngine.trendSeries(
                for: selectedKind,
                horizon: horizon,
                days: snapshot.historyDays,
                referenceDate: snapshot.referenceDate
            )
        }

        public var allMetricSeries: [TrendSeries] {
            MetricKind.allCases.map {
                BevelScoringEngine.trendSeries(
                    for: $0,
                    horizon: horizon,
                    days: snapshot.historyDays,
                    referenceDate: snapshot.referenceDate
                )
            }
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
