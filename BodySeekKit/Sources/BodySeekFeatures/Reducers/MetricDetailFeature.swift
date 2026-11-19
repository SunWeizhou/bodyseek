import BodySeekCore
import ComposableArchitecture
import Foundation

@Reducer
public struct MetricDetailFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public let kind: MetricKind
        public var horizon: TrendHorizon = .month
        public var selectedDate: Date?
        public var snapshot: BodySeekDashboardSnapshot
        public var isSheet: Bool

        public init(
            kind: MetricKind,
            snapshot: BodySeekDashboardSnapshot,
            horizon: TrendHorizon = .month,
            isSheet: Bool = false
        ) {
            self.kind = kind
            self.snapshot = snapshot
            self.horizon = horizon
            self.isSheet = isSheet
        }

        public var currentScore: MetricScore {
            snapshot.today.score(for: kind)
        }

        public var series: TrendSeries {
            BevelScoringEngine.trendSeries(
                for: kind,
                horizon: horizon,
                days: snapshot.historyDays,
                referenceDate: snapshot.referenceDate
            )
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
