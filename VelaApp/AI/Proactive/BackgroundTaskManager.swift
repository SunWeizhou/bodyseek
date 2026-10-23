import Foundation
import BackgroundTasks
import SwiftData
import os.log
import HealthKit

/// Manages registration and scheduling of BGAppRefreshTask for Vela's background agents.
@MainActor
enum BackgroundTaskManager {
    static let refreshTaskIdentifier = "com.sunweizhou.Vela.refresh"

    private static let logger = Logger(subsystem: "com.sunweizhou.Vela", category: "BackgroundTask")

    /// Call once on app launch to register task handlers with BGTaskScheduler.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                logger.error("Received unexpected background task type for \(self.refreshTaskIdentifier).")
                task.setTaskCompleted(success: false)
                return
            }
            handleRefreshTask(task: refreshTask)
        }
        logger.info("BGTask registered: \(self.refreshTaskIdentifier)")
    }

    /// Schedule the next background refresh targeting the nearest agent time window.
    /// iOS determines the actual fire time based on app usage patterns and system conditions.
    static func schedule() {
        let config = AutoAgentConfig.shared
        guard config.canRunBackgroundNetworkAI,
              AgentOutboundConsentPolicy.current.canSendNetworkAI else {
            cancelAll()
            logger.info("Background network AI or category consent is absent; no refresh scheduled.")
            return
        }

        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = nextTargetTime(config: config)

        do {
            try BGTaskScheduler.shared.submit(request)
            if let target = request.earliestBeginDate {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                logger.info("Background refresh scheduled, targeting ~\(formatter.string(from: target)).")
            }
        } catch {
            logger.error("Failed to schedule background refresh: \(error.localizedDescription)")
        }
    }

    /// Calculates the next target time for background refresh.
    /// Targets enabled evening/morning skills, whichever comes next.
    private static func nextTargetTime(config: AutoAgentConfig) -> Date {
        let now = Date()
        let cal = Calendar.current

        let enabledHours = [
            config.autoEveningWikiSync ? config.eveningSyncHour : nil,
            config.autoMorningBrief ? config.morningBriefHour : nil
        ].compactMap { $0 }
        let candidateHours = enabledHours.isEmpty ? [config.morningBriefHour] : enabledHours
        let candidates = candidateHours.map { hour -> Date in
            let today = cal.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
            return today > now ? today : (cal.date(byAdding: .day, value: 1, to: today) ?? today)
        }

        return candidates.min() ?? now.addingTimeInterval(3600)
    }

    /// Cancel all pending background tasks (e.g. when user disables the feature).
    static func cancelAll() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskIdentifier)
        logger.info("Pending background refresh cancelled.")
    }

    // MARK: - Handler

    private static func handleRefreshTask(task: BGAppRefreshTask) {
        logger.info("Background refresh task fired.")

        guard AutoAgentConfig.shared.canRunBackgroundNetworkAI,
              AgentOutboundConsentPolicy.current.canSendNetworkAI else {
            logger.info("Background network AI or category consent is absent; refresh skipped.")
            task.setTaskCompleted(success: true)
            return
        }

        // Schedule the next refresh immediately while this one runs.
        schedule()

        let handle = Task { @MainActor in
            // Always signal completion exactly once, even if the async work is
            // cancelled (expirationHandler cancels this task). Failing to call
            // setTaskCompleted lets the OS mark the app as failing background work
            // and throttle future BGAppRefreshTask grants.
            var succeeded = false
            defer { task.setTaskCompleted(success: succeeded) }
            do {
                let config = AutoAgentConfig.shared
                let hour = Calendar.current.component(.hour, from: Date())

                // 优先复用 App 容器（审计 H3）：BG 预算内省去 store 打开/迁移检查；
                // App 未在内存（被系统杀掉）时才重建。
                let modelContainer: ModelContainer
                if let active = VelaModelContainer.activeContainer {
                    modelContainer = active
                } else {
                    modelContainer = try VelaModelContainer.make()
                }
                let modelContext = ModelContext(modelContainer)
                let bgRun = AgentRunRecord(
                    agentName: "background_refresh",
                    startedAt: Date(),
                    status: .running,
                    reason: "BGAppRefreshTask",
                    outputSummary: "Background refresh started."
                )
                modelContext.insert(bgRun)
                modelContext.saveOrRecordFailure("modelContext.save")

                // Build DashboardSummary from HealthKit. Gate the expensive 7-day
                // HealthKit sync behind the last-successful-sync cursor: if data was
                // synced recently (within a few hours), skip the scan and recompute
                // from the persisted cache instead. This saves battery on every
                // background grant when HealthKit data hasn't changed.
                let queryService = HealthKitQueryService()
                VelaResolver.shared.register(HealthQueryService.self) { queryService }
                let services = VelaServices()

                let lastSync = HealthSyncCursorStore().load().lastSuccessfulSyncAt
                let freshEnough = lastSync.map { Date().timeIntervalSince($0) < 4 * 3600 } ?? false
                // F5 修复：即便 4 小时 TTL 内刚同步过，只要有后台投递标记
                // （HKObserverQuery 收到新样本），也必须重新摄入——
                // 否则晨间新到的 HRV/睡眠数据会被 TTL 挡掉，晨报用旧数据。
                let pendingDelivery = UserDefaults.standard.bool(
                    forKey: HealthKitBackgroundDelivery.pendingDeliveryKey
                )
                // Only run the expensive HealthKit sync when the cache is stale (or on
                // first launch) or new background data actually arrived; otherwise
                // recompute from persisted data.
                let shouldSyncData = !freshEnough || pendingDelivery

                // 深度专项批次 5：统一调度层收口后台触发源。
                let dashboard = try await VelaDailyOrchestrator.refresh(
                    for: Date(),
                    modelContext: modelContext,
                    queryService: queryService,
                    syncDays: shouldSyncData ? 7 : 0,
                    shouldSyncHealthData: shouldSyncData
                )
                if pendingDelivery {
                    UserDefaults.standard.set(false, forKey: HealthKitBackgroundDelivery.pendingDeliveryKey)
                }
                try? DailyLogService.refresh(dashboard: dashboard)

                if config.autoEveningWikiSync, (hour >= 21 || hour < 4) {
                    logger.info("Running daily profile sync in background.")
                    await EveningWikiSyncAgent.shared.runIfNeeded(
                        modelContext: modelContext,
                        dashboard: dashboard,
                        services: services
                    )
                } else if config.autoMorningBrief, hour >= 6, hour <= 11 {
                    logger.info("Running morning brief in background.")
                    await MorningBriefScheduler.shared.runIfNeeded(
                        modelContext: modelContext,
                        dashboard: dashboard,
                        services: services
                    )
                } else {
                    logger.info("No agent scheduled for current hour (\(hour)).")
                }

                bgRun.status = AgentRunStatus.success.rawValue
                bgRun.endedAt = Date()
                bgRun.outputSummary = "Background refresh completed. HealthKit sync window: 7 days."
                modelContext.saveOrRecordFailure("modelContext.save")
                succeeded = true
            } catch {
                logger.error("Background task failed: \(error.localizedDescription)")
                if let modelContainer = try? VelaModelContainer.make() {
                    let modelContext = ModelContext(modelContainer)
                    modelContext.insert(AgentRunRecord(
                        agentName: "background_refresh",
                        startedAt: Date(),
                        endedAt: Date(),
                        status: .failed,
                        reason: "BGAppRefreshTask",
                        outputSummary: "Background refresh failed.",
                        errorMessage: error.localizedDescription
                    ))
                    modelContext.saveOrRecordFailure("modelContext.save")
                }
            }
        }

        task.expirationHandler = {
            logger.warning("Background refresh task expired.")
            handle.cancel()
        }
    }
}

// MARK: - HealthKit 后台投递

/// 注册 HKObserverQuery 与后台投递：健康数据在后台更新时（如早晨手表同步
/// 睡眠段），重排后台刷新——此前只有前台刷新 + 机会性 BGAppRefreshTask，
/// 晨报可能基于过期的当夜睡眠数据生成。
enum HealthKitBackgroundDelivery {
    /// 后台投递脏标记：HKObserverQuery 收到新样本时置 true，
    /// BG 任务据此越过 4 小时 TTL 强制同步，成功后清除（见 handleRefreshTask）。
    static let pendingDeliveryKey = "vela_hk_pending_background_delivery"

    static func registerObservers() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()

        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .heartRate,
            .stepCount,
            .activeEnergyBurned,
        ]
        for identifier in quantityIdentifiers {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            register(store: store, sampleType: type)
        }
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            register(store: store, sampleType: sleepType)
        }
        register(store: store, sampleType: HKObjectType.workoutType())
    }

    private static func register(store: HKHealthStore, sampleType: HKSampleType) {
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            Task { @MainActor in
                UserDefaults.standard.set(true, forKey: HealthKitBackgroundDelivery.pendingDeliveryKey)
                // 训练/健康数据晚到（>3 天）的历史日此前永不重算（markDirty 生产零调用）：
                // 把最近 7 天标脏，planner 会纳入 rawRefresh 并重新评分。
                let cursorStore = HealthSyncCursorStore()
                let calendar = Calendar.current
                for offset in 0..<7 {
                    if let day = calendar.date(byAdding: .day, value: -offset, to: Date()) {
                        cursorStore.markDirty(day, calendar: calendar)
                    }
                }
                BackgroundTaskManager.schedule()
            }
            completionHandler()
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: sampleType, frequency: .hourly) { _, _ in }
    }
}
