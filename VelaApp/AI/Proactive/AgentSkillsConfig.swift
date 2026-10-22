import Foundation
import UserNotifications

/// Central configuration for automated agent skills.
/// Published state is main-actor only; background tasks read it on the main actor.
@MainActor
final class AutoAgentConfig: ObservableObject {
    static let shared = AutoAgentConfig()

    private let defaults: UserDefaults

    /// Explicit consent for automated tasks that can send health context to a network AI provider.
    /// Manual Coach requests are an intentional, separate action and are not governed by this flag.
    @Published var backgroundNetworkAIConsent: Bool {
        didSet { defaults.set(backgroundNetworkAIConsent, forKey: "agent_background_network_ai_consent") }
    }

    /// 后台联网 AI 的双重要件：后台自动化 consent + 手动出站类别 consent
    /// （CoachOutboundDataPolicy）。任一被撤销，后台任务都不得向网络 AI 发送健康数据。
    var canSendHealthContextToNetworkAI: Bool {
        backgroundNetworkAIConsent && CoachOutboundDataPolicy.hasExplicitConsent
    }

    // ── Skill Toggles ──
    @Published var autoEveningWikiSync: Bool {
        didSet { defaults.set(autoEveningWikiSync, forKey: "agent_auto_evening_wiki_sync") }
    }
    @Published var autoMorningBrief: Bool {
        didSet { defaults.set(autoMorningBrief, forKey: "agent_auto_morning_brief") }
    }
    @Published var proactiveInsights: Bool {
        didSet { defaults.set(proactiveInsights, forKey: "agent_proactive_insights") }
    }

    // ── Schedule Preferences ──
    @Published var eveningSyncHour: Int {
        didSet { defaults.set(eveningSyncHour, forKey: "agent_sync_hour") }
    }
    @Published var morningBriefHour: Int {
        didSet { defaults.set(morningBriefHour, forKey: "agent_brief_hour") }
    }

    // ── Notification Preferences ──
    @Published var abnormalMetricAlerts: Bool {
        didSet {
            defaults.set(abnormalMetricAlerts, forKey: "agent_abnormal_metric_alerts")
        }
    }
    @Published var morningBriefAlerts: Bool {
        didSet {
            defaults.set(morningBriefAlerts, forKey: "agent_morning_brief_alerts")
        }
    }
    @Published var bedtimeReminders: Bool {
        didSet {
            defaults.set(bedtimeReminders, forKey: "agent_bedtime_reminders")
        }
    }
    @Published var bedtimeHour: Int {
        didSet {
            defaults.set(bedtimeHour, forKey: "agent_bedtime_hour")
        }
    }
    @Published var bedtimeMinute: Int {
        didSet {
            defaults.set(bedtimeMinute, forKey: "agent_bedtime_minute")
        }
    }

    // ── Proactive Check-in Types (Bevel-inspired) ──
    @Published var progressCheckins: Bool {
        didSet { defaults.set(progressCheckins, forKey: "agent_progress_checkins") }
    }
    @Published var hourlyCheckins: Bool {
        didSet { defaults.set(hourlyCheckins, forKey: "agent_hourly_checkins") }
    }
    @Published var hourlyCheckinMinute: Int {
        didSet { defaults.set(hourlyCheckinMinute, forKey: "agent_hourly_checkin_minute") }
    }
    @Published var progressCheckinHour: Int {
        didSet { defaults.set(progressCheckinHour, forKey: "agent_progress_checkin_hour") }
    }
    @Published var weeklySummary: Bool {
        didSet { defaults.set(weeklySummary, forKey: "agent_weekly_summary") }
    }
    @Published var weeklySummaryDay: Int {  // 1=Sun, 2=Mon...
        didSet { defaults.set(weeklySummaryDay, forKey: "agent_weekly_summary_day") }
    }
    @Published var weeklySummaryHour: Int {
        didSet { defaults.set(weeklySummaryHour, forKey: "agent_weekly_summary_hour") }
    }
    @Published var monthlySummary: Bool {
        didSet { defaults.set(monthlySummary, forKey: "agent_monthly_summary") }
    }
    @Published var monthlySummaryDay: Int {
        didSet { defaults.set(monthlySummaryDay, forKey: "agent_monthly_summary_day") }
    }
    @Published var monthlySummaryHour: Int {
        didSet { defaults.set(monthlySummaryHour, forKey: "agent_monthly_summary_hour") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Automated network AI is strictly opt-in. Existing installations must opt in again
        // because earlier versions enabled these tasks by default.
        if defaults.object(forKey: "agent_background_network_ai_consent") == nil {
            defaults.set(false, forKey: "agent_background_network_ai_consent")
        }
        self.backgroundNetworkAIConsent = defaults.bool(forKey: "agent_background_network_ai_consent")

        // Background skills are also opt-in on a fresh install.
        if defaults.object(forKey: "agent_auto_evening_wiki_sync") == nil {
            defaults.set(false, forKey: "agent_auto_evening_wiki_sync")
        }
        if defaults.object(forKey: "agent_auto_morning_brief") == nil {
            defaults.set(false, forKey: "agent_auto_morning_brief")
        }
        if defaults.object(forKey: "agent_proactive_insights") == nil {
            defaults.set(false, forKey: "agent_proactive_insights")
        }
        self.autoEveningWikiSync = defaults.bool(forKey: "agent_auto_evening_wiki_sync")
        self.autoMorningBrief = defaults.bool(forKey: "agent_auto_morning_brief")
        self.proactiveInsights = defaults.bool(forKey: "agent_proactive_insights")

        self.eveningSyncHour = defaults.integer(forKey: "agent_sync_hour").nonZero ?? 23
        self.morningBriefHour = defaults.integer(forKey: "agent_brief_hour").nonZero ?? 7

        // Notification preferences — all enabled by default
        if defaults.object(forKey: "agent_abnormal_metric_alerts") == nil {
            defaults.set(true, forKey: "agent_abnormal_metric_alerts")
        }
        if defaults.object(forKey: "agent_morning_brief_alerts") == nil {
            defaults.set(true, forKey: "agent_morning_brief_alerts")
        }
        if defaults.object(forKey: "agent_bedtime_reminders") == nil {
            defaults.set(true, forKey: "agent_bedtime_reminders")
        }
        self.abnormalMetricAlerts = defaults.bool(forKey: "agent_abnormal_metric_alerts")
        self.morningBriefAlerts = defaults.bool(forKey: "agent_morning_brief_alerts")
        self.bedtimeReminders = defaults.bool(forKey: "agent_bedtime_reminders")

        self.bedtimeHour = defaults.integer(forKey: "agent_bedtime_hour").nonZero ?? 22
        self.bedtimeMinute = defaults.integer(forKey: "agent_bedtime_minute")

        // Proactive check-ins
        if defaults.object(forKey: "agent_progress_checkins") == nil { defaults.set(true, forKey: "agent_progress_checkins") }
        if defaults.object(forKey: "agent_weekly_summary") == nil { defaults.set(true, forKey: "agent_weekly_summary") }
        self.progressCheckins = defaults.bool(forKey: "agent_progress_checkins")
        self.progressCheckinHour = defaults.integer(forKey: "agent_progress_checkin_hour").nonZero ?? 12
        self.hourlyCheckins = defaults.bool(forKey: "agent_hourly_checkins")
        self.hourlyCheckinMinute = min(59, max(0, defaults.integer(forKey: "agent_hourly_checkin_minute")))
        self.weeklySummary = defaults.bool(forKey: "agent_weekly_summary")
        self.weeklySummaryDay = defaults.integer(forKey: "agent_weekly_summary_day").nonZero ?? 2
        self.weeklySummaryHour = defaults.integer(forKey: "agent_weekly_summary_hour").nonZero ?? 9
        self.monthlySummary = defaults.bool(forKey: "agent_monthly_summary")
        self.monthlySummaryDay = defaults.integer(forKey: "agent_monthly_summary_day").nonZero ?? 1
        self.monthlySummaryHour = defaults.integer(forKey: "agent_monthly_summary_hour").nonZero ?? 9
    }

    var canRunBackgroundNetworkAI: Bool {
        backgroundNetworkAIConsent && (autoEveningWikiSync || autoMorningBrief || proactiveInsights)
    }
}

enum CoachCheckInCadence: String, CaseIterable {
    case hourly
    case daily
    case weekly
    case monthly
}

enum CoachCheckInSchedule {
    static func components(
        cadence: CoachCheckInCadence,
        hour: Int,
        minute: Int = 0,
        weekday: Int = 2,
        day: Int = 1
    ) -> DateComponents {
        var components = DateComponents()
        components.calendar = .current
        components.timeZone = .current
        components.minute = min(59, max(0, minute))
        switch cadence {
        case .hourly:
            break
        case .daily:
            components.hour = min(23, max(0, hour))
        case .weekly:
            components.hour = min(23, max(0, hour))
            components.weekday = min(7, max(1, weekday))
        case .monthly:
            components.hour = min(23, max(0, hour))
            components.day = min(28, max(1, day))
        }
        return components
    }
}

enum CoachCheckInScheduler {
    private static let prefix = "vela.coach.checkin."

    @MainActor
    static func reschedule(config: AutoAgentConfig? = nil) async {
        let config = config ?? .shared
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        if settings.authorizationStatus == .denied {
            // 通知被拒时排程静默失败，给可见反馈。
            NSLog("Vela CoachCheckIn: notification permission denied; check-ins will not be scheduled.")
        }
        center.removePendingNotificationRequests(withIdentifiers: CoachCheckInCadence.allCases.map { prefix + $0.rawValue })

        let plans: [(CoachCheckInCadence, Bool, DateComponents, String, String)] = [
            (.hourly, config.hourlyCheckins, CoachCheckInSchedule.components(cadence: .hourly, hour: 0, minute: config.hourlyCheckinMinute), "小时 Check-in", "快速记录一下此刻的精力、压力或正在做的事。"),
            (.daily, config.progressCheckins, CoachCheckInSchedule.components(cadence: .daily, hour: config.progressCheckinHour), "今日 Check-in", "回顾今天的执行、体感和需要调整的下一步。"),
            (.weekly, config.weeklySummary, CoachCheckInSchedule.components(cadence: .weekly, hour: config.weeklySummaryHour, weekday: config.weeklySummaryDay), "本周回顾", "打开 Vela 查看本周趋势，并确认下周最重要的一项行动。"),
            (.monthly, config.monthlySummary, CoachCheckInSchedule.components(cadence: .monthly, hour: config.monthlySummaryHour, day: config.monthlySummaryDay), "月度回顾", "查看本月健康、训练与习惯趋势；缺失数据会明确标注。"),
        ]
        for (cadence, enabled, components, title, body) in plans where enabled {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["coachRoute": "checkin", "cadence": cadence.rawValue]
            let request = UNNotificationRequest(
                identifier: prefix + cadence.rawValue,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
            try? await center.add(request)
        }
    }

    static func scheduleOneTime(at date: Date) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        } else if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional {
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = "Vela Check-in"
        content.body = "你安排的回顾时间到了。打开 Vela 记录当前状态。"
        content.sound = .default
        content.userInfo = ["coachRoute": "checkin", "cadence": "one_time"]
        let request = UNNotificationRequest(
            identifier: prefix + "one_time." + UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        )
        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}

/// Display model for the skills config UI
struct AgentSkillInfo: Identifiable {
    let id: String
    let name: String          // e.g. "夜间 Wiki 同步"
    let enName: String
    let icon: String
    let description: String
    let enDescription: String
    let schedule: String      // e.g. "每晚 23:00"
    var isEnabled: Bool
    let configKey: WritableKeyPath<AutoAgentConfig, Bool>
}

extension AutoAgentConfig {
    func skillList(isChinese: Bool) -> [AgentSkillInfo] {
        [
            AgentSkillInfo(
                id: "evening_wiki_sync",
                name: "夜间 Wiki 同步",
                enName: "Nightly Wiki Sync",
                icon: "moon.stars.fill",
                description: "每晚自动总结当日健康数据和对话，更新 Wiki 档案",
                enDescription: "Auto-summarize daily health & chat into your Wiki each night",
                schedule: isChinese ? "每晚 \(eveningSyncHour):00" : "Nightly at \(eveningSyncHour):00",
                isEnabled: autoEveningWikiSync,
                configKey: \.autoEveningWikiSync
            ),
            AgentSkillInfo(
                id: "morning_brief",
                name: "晨间简报",
                enName: "Morning Brief",
                icon: "sunrise.fill",
                description: "早晨自动生成当日的健康状态简报",
                enDescription: "Auto-generate your morning health brief at wake time",
                schedule: isChinese ? "每天早上 \(morningBriefHour):00 发送" : "Every morning at \(morningBriefHour):00",
                isEnabled: autoMorningBrief,
                configKey: \.autoMorningBrief
            ),
            AgentSkillInfo(
                id: "proactive_insights",
                name: "主动洞察",
                enName: "Proactive Insights",
                icon: "sparkle.magnifyingglass",
                description: "根据异常数据自动推送健康提醒和建议",
                enDescription: "Auto-push health alerts based on abnormal physiological data",
                schedule: isChinese ? "持续监测" : "Continuous",
                isEnabled: proactiveInsights,
                configKey: \.proactiveInsights
            )
        ]
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
