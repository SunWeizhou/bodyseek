import Dependencies
import DependenciesMacros
import Foundation
import UserNotifications

@DependencyClient
public struct RestTimerClient: Sendable {
    public var scheduleRestCompletion: @Sendable (_ seconds: Int, _ exerciseName: String) async -> Void = { _, _ in }
    public var cancelPending: @Sendable () async -> Void = {}
}

extension RestTimerClient: DependencyKey {
    private static let notificationID = "bodyseek.workout.rest.complete"

    public static let liveValue = RestTimerClient(
        scheduleRestCompletion: { seconds, exerciseName in
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-velaPreviewDashboard") || args.contains("-velaPreviewEmptyDashboard") {
                return
            }
            #if os(iOS)
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted, seconds > 0 else { return }

            center.removePendingNotificationRequests(withIdentifiers: [notificationID])
            let content = UNMutableNotificationContent()
            content.title = "组间休息结束"
            content.body = "\(exerciseName) 休息时间到，可以开始下一组。"
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
            let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
            try? await center.add(request)
            #endif
        },
        cancelPending: {
            #if os(iOS)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
            #endif
        }
    )

    public static let previewValue = RestTimerClient(
        scheduleRestCompletion: { _, _ in },
        cancelPending: {}
    )
}

public extension DependencyValues {
    var restTimerClient: RestTimerClient {
        get { self[RestTimerClient.self] }
        set { self[RestTimerClient.self] = newValue }
    }
}
