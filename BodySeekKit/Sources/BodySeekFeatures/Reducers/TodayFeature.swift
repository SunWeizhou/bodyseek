import BodySeekAgent
import BodySeekCore
import BodySeekStore
import ComposableArchitecture
import Foundation

@Reducer
public struct TodayFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var snapshot: BodySeekDashboardSnapshot
        public var briefingStatus: AIBriefingStatus = .idle
        /// 今天的每日简报（唯一的结论来源）；页面上的 AI 解读读它，不再自己生成。
        public var dailyBrief: DailyBrief?
        /// 用户对今天简报的反馈；一天只记一次。
        public var briefFeedback: BriefFeedbackRating?
        public var postWorkoutAdvice: String?
        public var isLoading: Bool = false
        public var showEvidenceBreakdown: Bool = false
        public var subjectiveFeeling: Int?
        public var todayCheckIn: DailyCheckIn?
        public var planItems: [PlanItemRecord] = []
        public var proactiveInsights: [ProactiveInsight] = []
        public var dismissedInsightIDs: Set<String> = []
        public var todayNutritionLog: DailyNutritionLog?
        public var nutritionTargetPlan: NutritionTargetPlan?
        public var nutritionRollingDeficit7d: Double?
        public var recentHRVSeries: [VitalSparkPoint]
        public var recentRHRSeries: [VitalSparkPoint]
        public var recentRespiratorySeries: [VitalSparkPoint]
        public var recentSpO2Series: [VitalSparkPoint]
        public var lastError: String?

        public init(
            snapshot: BodySeekDashboardSnapshot,
            briefingStatus: AIBriefingStatus = .idle,
            planItems: [PlanItemRecord] = []
        ) {
            self.snapshot = snapshot
            self.briefingStatus = briefingStatus
            self.planItems = planItems
            let recent = snapshot.historyDays.suffix(14)
            self.recentHRVSeries = recent.map { VitalSparkPoint(date: $0.date, value: $0.raw.hrvMs) }
            self.recentRHRSeries = recent.map { VitalSparkPoint(date: $0.date, value: $0.raw.restingHeartRateBpm) }
            self.recentRespiratorySeries = recent.map { VitalSparkPoint(date: $0.date, value: $0.raw.respiratoryRateBrpm) }
            self.recentSpO2Series = recent.map { VitalSparkPoint(date: $0.date, value: $0.raw.oxygenSaturationPct) }
        }

        public var today: DailyComputedDay { snapshot.today }

        public mutating func updateSnapshot(_ newSnapshot: BodySeekDashboardSnapshot) {
            self.snapshot = newSnapshot
            let recent = newSnapshot.historyDays.suffix(14)
            self.recentHRVSeries = recent.map { VitalSparkPoint(date: $0.date, value: $0.raw.hrvMs) }
            self.recentRHRSeries = recent.map { VitalSparkPoint(date: $0.date, value: $0.raw.restingHeartRateBpm) }
            self.recentRespiratorySeries = recent.map { VitalSparkPoint(date: $0.date, value: $0.raw.respiratoryRateBrpm) }
            self.recentSpO2Series = recent.map { VitalSparkPoint(date: $0.date, value: $0.raw.oxygenSaturationPct) }
        }
    }

    public enum Action: Equatable, Sendable {
        case refreshTapped
        case authorizationTapped
        case toggleEvidenceBreakdown
        case metricTapped(MetricKind)
        case askCoachTapped(String)
        case feelingSelected(Int)
        case adoptPlanItem(UUID)
        case dismissPlanItem(UUID)
        case openNutritionTapped
        case openWorkoutTapped
        case openSettingsTapped
        case openCheckInTapped
        case regenerateBriefingTapped
        case briefFeedbackTapped(BriefFeedbackRating)
        case proactiveInsightActionTapped(ProactiveInsight)
        case dismissProactiveInsightTapped(String)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case refreshRequested
            case authorizationRequested
            case openMetric(MetricKind)
            case askCoach(String)
            case saveSubjectiveFeeling(Int)
            case adoptPlanItem(PlanItemRecord)
            case dismissPlanItem(PlanItemRecord)
            case openNutrition
            case openSettings
            case openCheckIn
            case openWorkoutInbox
            case proactiveInsightDismissed(String)
            case regenerateBriefingRequested
            case briefFeedbackSubmitted(BriefFeedbackRating)
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

            case let .adoptPlanItem(id):
                guard let idx = state.planItems.firstIndex(where: { $0.id == id }) else { return .none }
                let updated = state.planItems[idx].updatingState(.adopted)
                state.planItems[idx] = updated
                return .send(.delegate(.adoptPlanItem(updated)))

            case let .dismissPlanItem(id):
                guard let idx = state.planItems.firstIndex(where: { $0.id == id }) else { return .none }
                let updated = state.planItems[idx].updatingState(.dismissed)
                state.planItems[idx] = updated
                return .send(.delegate(.dismissPlanItem(updated)))

            case .openNutritionTapped:
                return .send(.delegate(.openNutrition))

            case .openWorkoutTapped:
                return .send(.delegate(.openWorkoutInbox))

            case .openSettingsTapped:
                return .send(.delegate(.openSettings))

            case .openCheckInTapped:
                return .send(.delegate(.openCheckIn))

            case .regenerateBriefingTapped:
                return .send(.delegate(.regenerateBriefingRequested))

            case let .briefFeedbackTapped(rating):
                guard state.dailyBrief != nil, state.briefFeedback == nil else { return .none }
                state.briefFeedback = rating
                return .send(.delegate(.briefFeedbackSubmitted(rating)))

            case let .proactiveInsightActionTapped(insight):
                switch insight.route {
                case let .askCoach(prompt):
                    return .send(.delegate(.askCoach(prompt)))
                case .openWorkoutInbox:
                    return .send(.delegate(.openWorkoutInbox))
                }

            case let .dismissProactiveInsightTapped(id):
                state.dismissedInsightIDs.insert(id)
                state.proactiveInsights.removeAll { $0.id == id }
                return .send(.delegate(.proactiveInsightDismissed(id)))

            case .delegate:
                return .none
            }
        }
    }
}
