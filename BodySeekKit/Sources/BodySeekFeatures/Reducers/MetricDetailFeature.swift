import BodySeekCore
import ComposableArchitecture
import Foundation

@Reducer
public struct MetricDetailFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public let kind: MetricKind
        public var horizon: TrendHorizon {
            didSet {
                if oldValue != horizon {
                    refreshActiveChart()
                }
            }
        }
        public var selectedDate: Date?
        public var snapshot: BodySeekDashboardSnapshot
        public var sleepGoalMinutes: Int
        public var chartCache: [TrendHorizon: ChartSeriesSnapshot]
        public var activeChartSnapshot: ChartSeriesSnapshot
        public var isSheet: Bool

        public init(
            kind: MetricKind,
            snapshot: BodySeekDashboardSnapshot,
            horizon: TrendHorizon = .month,
            isSheet: Bool = false,
            sleepGoalMinutes: Int = 450,
            precomputedCache: [TrendHorizon: ChartSeriesSnapshot]? = nil
        ) {
            self.kind = kind
            self.horizon = horizon
            self.snapshot = snapshot
            self.isSheet = isSheet
            self.sleepGoalMinutes = sleepGoalMinutes

            let resolvedCache = precomputedCache ?? Self.buildCache(
                for: kind,
                days: snapshot.historyDays,
                referenceDate: snapshot.referenceDate
            )
            self.chartCache = resolvedCache
            self.activeChartSnapshot = resolvedCache[horizon] ?? BevelScoringEngine.buildChartSeriesSnapshot(
                for: kind,
                horizon: horizon,
                days: snapshot.historyDays,
                referenceDate: snapshot.referenceDate
            )
        }

        public var currentScore: MetricScore {
            snapshot.today.score(for: kind)
        }

        public mutating func updateSnapshot(
            _ newSnapshot: BodySeekDashboardSnapshot,
            precomputedCache: [TrendHorizon: ChartSeriesSnapshot]? = nil
        ) {
            self.snapshot = newSnapshot
            self.chartCache = precomputedCache ?? Self.buildCache(
                for: kind,
                days: newSnapshot.historyDays,
                referenceDate: newSnapshot.referenceDate
            )
            refreshActiveChart()
        }

        private mutating func refreshActiveChart() {
            self.activeChartSnapshot = chartCache[horizon] ?? BevelScoringEngine.buildChartSeriesSnapshot(
                for: kind,
                horizon: horizon,
                days: snapshot.historyDays,
                referenceDate: snapshot.referenceDate
            )
        }

        private static func buildCache(
            for kind: MetricKind,
            days: [DailyComputedDay],
            referenceDate: Date
        ) -> [TrendHorizon: ChartSeriesSnapshot] {
            var dict: [TrendHorizon: ChartSeriesSnapshot] = [:]
            for h in TrendHorizon.allCases {
                dict[h] = BevelScoringEngine.buildChartSeriesSnapshot(
                    for: kind,
                    horizon: h,
                    days: days,
                    referenceDate: referenceDate
                )
            }
            return dict
        }
    }

    public enum Action: Equatable, Sendable {
        case horizonChanged(TrendHorizon)
        case selectedDateChanged(Date?)
        case askCoachTapped
        case closeTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case askCoach(String)
            case dismissed
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

            case let .selectedDateChanged(date):
                state.selectedDate = date
                return .none

            case .askCoachTapped:
                let scoreText = state.currentScore.formattedScore
                let question = "结合我今天\(state.kind.title)（\(scoreText)）和近期变化，应该注意什么？"
                return .send(.delegate(.askCoach(question)))

            case .closeTapped:
                return .send(.delegate(.dismissed))

            case .delegate:
                return .none
            }
        }
    }
}
