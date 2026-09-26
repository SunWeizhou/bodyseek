import Foundation

/// User intent sent to TodayStore.  This is deliberately distinct from the
/// existing `TodayAction`, which is a rendered command value in
/// TodayCommandState.swift.
enum TodayStoreAction: Sendable {
    case appear
    case selectDay(Date)
    case refresh(force: Bool)
    case retry
    case openCalendar
    case openMetric(TodayMetricID)
    case openEvidence
    case openPlan
    case openSettings
    case askCoach(String)
    case startTraining
    case openTrends
    case openQuickCoach
    case requestWeather
    case weatherLocationChanged
    case refreshCoverage
    case trackDailyDecisionViewed(bodyStateHash: String)
    case trackDailyDecisionAction(bodyStateHash: String, destination: String)
    case setLivedStateAlignment(LivedStateAlignment)
    case saveLivedState(LivedStateCheckIn)
    case submitFeedback(DailyDecisionFeedbackValues)
}

@MainActor
protocol TodayEffectRouter: AnyObject {
    func openCalendar() async
    func openMetric(_ metric: TodayMetricID) async
    func openEvidence() async
    func openPlan() async
    func openSettings() async
    func askCoach(_ question: String) async
    func startTraining() async
    func openTrends() async
    func openQuickCoach() async
    func requestWeather() async -> TodayWeatherProjection?
    func refreshWeatherFromKnownLocation() async -> TodayWeatherProjection?
    func requestCoverage() async -> DataCoverageSummaryModel?
    func trackDailyDecisionViewed(bodyStateHash: String) async
    func trackDailyDecisionAction(bodyStateHash: String, destination: String) async
    func saveLivedStateAlignment(_ alignment: LivedStateAlignment) async
    func saveLivedState(_ checkIn: LivedStateCheckIn) async
    func submitFeedback(_ values: DailyDecisionFeedbackValues) async
}

/// Safe default for previews and composition-root wiring before each feature
/// effect has an adapter.  It intentionally has no persistence or navigation
/// dependencies.
@MainActor
final class NoOpTodayEffectRouter: TodayEffectRouter {
    init() {}
    func openCalendar() async {}
    func openMetric(_ metric: TodayMetricID) async {}
    func openEvidence() async {}
    func openPlan() async {}
    func openSettings() async {}
    func askCoach(_ question: String) async {}
    func startTraining() async {}
    func openTrends() async {}
    func openQuickCoach() async {}
    func requestWeather() async -> TodayWeatherProjection? { nil }
    func refreshWeatherFromKnownLocation() async -> TodayWeatherProjection? { nil }
    func requestCoverage() async -> DataCoverageSummaryModel? { nil }
    func trackDailyDecisionViewed(bodyStateHash: String) async {}
    func trackDailyDecisionAction(bodyStateHash: String, destination: String) async {}
    func saveLivedStateAlignment(_ alignment: LivedStateAlignment) async {}
    func saveLivedState(_ checkIn: LivedStateCheckIn) async {}
    func submitFeedback(_ values: DailyDecisionFeedbackValues) async {}
}
