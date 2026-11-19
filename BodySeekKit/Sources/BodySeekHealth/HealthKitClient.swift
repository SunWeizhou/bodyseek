import BodySeekCore
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct HealthKitClient: Sendable {
    public var requestAuthorization: @Sendable () async -> Bool = { false }
    public var isAuthorizedPrompted: @Sendable () async -> Bool = { false }
    public var loadDashboardWindow: @Sendable (_ days: Int, _ sleepGoalMinutes: Int, _ referenceDate: Date) async -> BodySeekDashboardSnapshot = { days, goal, date in
        BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: date, days: days),
            sleepGoalMinutes: goal,
            referenceDate: date,
            sourceLabel: "示例数据",
            isAuthorized: true
        )
    }
    public var saveWorkout: @Sendable (_ session: LoggedWorkoutSession) async throws -> String = { $0.id.uuidString }
    public var observeUpdates: @Sendable () async -> AsyncStream<Void> = {
        AsyncStream { $0.finish() }
    }
}

extension HealthKitClient: DependencyKey {
    public static let liveValue: HealthKitClient = {
        #if os(iOS)
        return HealthKitClient(
            requestAuthorization: {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-velaPreviewDashboard") || args.contains("-velaPreviewEmptyDashboard") {
                    return true
                }
                guard let hk = await MainActor.run(body: { BodySeekHealthBridgeModule.shared.currentHealthKit }) else {
                    return false
                }
                return await SpeziHealthKitFetcher.requestAuthorization(using: hk)
            },
            isAuthorizedPrompted: {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-velaPreviewDashboard") { return true }
                if args.contains("-velaPreviewEmptyDashboard") { return false }
                return await MainActor.run {
                    guard let hk = BodySeekHealthBridgeModule.shared.currentHealthKit else { return false }
                    return SpeziHealthKitFetcher.isAuthorizedPrompted(using: hk)
                }
            },
            loadDashboardWindow: { days, sleepGoalMinutes, referenceDate in
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-velaPreviewEmptyDashboard") {
                    return BevelScoringEngine.computeWindow(
                        rawDays: PreviewSeedFactory.makeEmptyRawWindow(endingAt: referenceDate),
                        sleepGoalMinutes: sleepGoalMinutes,
                        referenceDate: referenceDate,
                        sourceLabel: "未连接样本",
                        isAuthorized: false
                    )
                }
                if args.contains("-velaPreviewDashboard") {
                    return BevelScoringEngine.computeWindow(
                        rawDays: PreviewSeedFactory.makeRawWindow(endingAt: referenceDate, days: days),
                        sleepGoalMinutes: sleepGoalMinutes,
                        referenceDate: referenceDate,
                        sourceLabel: "示例数据",
                        isAuthorized: true
                    )
                }
                guard let hk = await MainActor.run(body: { BodySeekHealthBridgeModule.shared.currentHealthKit }) else {
                    return BevelScoringEngine.computeWindow(
                        rawDays: PreviewSeedFactory.makeEmptyRawWindow(endingAt: referenceDate),
                        sleepGoalMinutes: sleepGoalMinutes,
                        referenceDate: referenceDate,
                        sourceLabel: "Apple 健康初始化中",
                        isAuthorized: false
                    )
                }
                return await SpeziHealthKitFetcher.fetchWindow(
                    using: hk,
                    days: days,
                    sleepGoalMinutes: sleepGoalMinutes,
                    referenceDate: referenceDate
                )
            },
            saveWorkout: { session in
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-velaPreviewDashboard") || args.contains("-velaPreviewEmptyDashboard") {
                    return "preview-hk-\(session.id.uuidString)"
                }
                guard let hk = await MainActor.run(body: { BodySeekHealthBridgeModule.shared.currentHealthKit }) else {
                    throw NSError(
                        domain: "BodySeekHealth",
                        code: 1002,
                        userInfo: [NSLocalizedDescriptionKey: "HealthKit 模块尚未就绪"]
                    )
                }
                return try await SpeziHealthKitFetcher.saveStrengthWorkout(session, using: hk)
            },
            observeUpdates: {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-velaPreviewDashboard") || args.contains("-velaPreviewEmptyDashboard") {
                    return AsyncStream { $0.finish() }
                }
                return await BodySeekHealthBridgeModule.shared.updateStream()
            }
        )
        #else
        return previewValue
        #endif
    }()

    public static let previewValue = HealthKitClient(
        requestAuthorization: { true },
        isAuthorizedPrompted: { true },
        loadDashboardWindow: { days, sleepGoalMinutes, referenceDate in
            BevelScoringEngine.computeWindow(
                rawDays: PreviewSeedFactory.makeRawWindow(endingAt: referenceDate, days: days),
                sleepGoalMinutes: sleepGoalMinutes,
                referenceDate: referenceDate,
                sourceLabel: "示例数据",
                isAuthorized: true
            )
        },
        saveWorkout: { session in session.id.uuidString },
        observeUpdates: { AsyncStream { $0.finish() } }
    )
}

public extension DependencyValues {
    var healthKitClient: HealthKitClient {
        get { self[HealthKitClient.self] }
        set { self[HealthKitClient.self] = newValue }
    }
}
