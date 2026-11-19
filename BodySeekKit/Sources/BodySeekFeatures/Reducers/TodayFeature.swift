import BodySeekCore
import ComposableArchitecture
import Foundation

@Reducer
public struct TodayFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var snapshot: BodySeekDashboardSnapshot
        public var briefingStatus: AIBriefingStatus = .idle
        public var isLoading: Bool = false
        public var showEvidenceBreakdown: Bool = false
        public var subjectiveFeeling: Int?
        public var todayCheckIn: DailyCheckIn?
        public var lastError: String?

        public init(
            snapshot: BodySeekDashboardSnapshot,
            briefingStatus: AIBriefingStatus = .idle
        ) {
            self.snapshot = snapshot
            self.briefingStatus = briefingStatus
        }

        public var today: DailyComputedDay { snapshot.today }

        public var recentHRVSeries: [(date: Date, value: Double?)] {
            snapshot.historyDays.suffix(14).map { ($0.date, $0.raw.hrvMs) }
        }

        public var recentRHRSeries: [(date: Date, value: Double?)] {
            snapshot.historyDays.suffix(14).map { ($0.date, $0.raw.restingHeartRateBpm) }
        }

        public var recentRespiratorySeries: [(date: Date, value: Double?)] {
            snapshot.historyDays.suffix(14).map { ($0.date, $0.raw.respiratoryRateBrpm) }
        }

        public var recentSpO2Series: [(date: Date, value: Double?)] {
            snapshot.historyDays.suffix(14).map { ($0.date, $0.raw.oxygenSaturationPct) }
        }
    }

    public enum Action: Equatable, Sendable {
        case refreshTapped
        case authorizationTapped
        case toggleEvidenceBreakdown
        case metricTapped(MetricKind)
        case askCoachTapped(String)
        case feelingSelected(Int)
        case openSettingsTapped
        case openCheckInTapped
        case regenerateBriefingTapped
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case refreshRequested
            case authorizationRequested
            case openMetric(MetricKind)
            case askCoach(String)
            case saveSubjectiveFeeling(Int)
            case openSettings
            case openCheckIn
            case regenerateBriefingRequested
        }
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .refreshTapped:
                return .send(.delegate(.refreshRequested))

            case .authorizationTapped:
                return .send(.delegate(.authorizationRequested))

            case .toggleEvidenceBreakdown:
                state.showEvidenceBreakdown.toggle()
                return .none

            case let .metricTapped(kind):
                return .send(.delegate(.openMetric(kind)))

            case let .askCoachTapped(question):
                return .send(.delegate(.askCoach(question)))

            case let .feelingSelected(score):
                state.subjectiveFeeling = score
                return .send(.delegate(.saveSubjectiveFeeling(score)))

            case .openSettingsTapped:
                return .send(.delegate(.openSettings))

            case .openCheckInTapped:
                return .send(.delegate(.openCheckIn))

            case .regenerateBriefingTapped:
                return .send(.delegate(.regenerateBriefingRequested))

            case .delegate:
                return .none
            }
        }
    }
}
