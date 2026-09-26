import SwiftUI
import SwiftData

struct VelaSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    // Settings toggles
    @AppStorage("vela_dark_mode") private var darkModeRaw = "system"
    @AppStorage("agent_abnormal_metric_alerts") private var abnormalMetricAlertsOn = true
    @AppStorage("agent_morning_brief_alerts") private var morningBriefOn = true
    @AppStorage("agent_bedtime_reminders") private var bedtimeRemindersOn = true
    
    @AppStorage("vela_app_language") private var languageRaw = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("vela_daily_calorie_target") private var dailyCalorieTarget = 2000
    @AppStorage(SleepTargetSettings.hoursKey) private var sleepTargetHours = SleepTargetSettings.defaultHours
    @AppStorage("vela_coach_personality") private var coachPersonalityRaw = CoachPersonality.guardian.rawValue
    
    private var currentCoachPersonalityName: String {
        CoachPersonality(rawValue: coachPersonalityRaw)?.displayName ?? CoachPersonality.guardian.displayName
    }

    private var outboundAgentStatus: String {
        CoachOutboundDataPolicy.hasExplicitConsent ? "已授权" : "未授权"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                profileCardRow

                settingsGroup(eyebrow: "", title: "我的档案") {
                    VStack(spacing: 0) {
                        NavigationLink(destination: AccountSettingsView()) {
                            settingsRow(icon: "person.crop.circle", title: "基本资料", value: "本机保存")
                        }
                        settingsDivider
                        NavigationLink(destination: UserWikiArchiveView()) {
                            settingsRow(icon: "doc.text", title: "健康档案", value: "长期记忆")
                        }
                        settingsDivider
                        NavigationLink(destination: CoachPersonalitySettingsView()) {
                            settingsRow(icon: "brain.head.profile", title: "沟通方式", value: currentCoachPersonalityName)
                        }
                        settingsDivider
                        NavigationLink(destination: AgentAutomationSettingsView()) {
                            settingsRow(icon: "sparkles", title: "主动智能", value: "已配置")
                        }
                    }
                }

                settingsGroup(eyebrow: "", title: "连接与数据") {
                    VStack(spacing: 0) {
                        NavigationLink(destination: DataSourceSettingsView()) {
                            settingsRow(icon: "applewatch", title: "数据来源", value: "Apple 健康")
                        }
                        settingsDivider
                        NavigationLink(destination: DataCoverageView()) {
                            settingsRow(icon: "waveform.path.ecg.rectangle", title: "数据覆盖", value: "证据完整度")
                        }
                        settingsDivider
                        NavigationLink(destination: TrustCenterView()) {
                            settingsRow(icon: "checkmark.shield", title: "信任中心", value: "数据与 Agent")
                        }
                        settingsDivider
                        NavigationLink(destination: AIModelSettingsView()) {
                            settingsRow(icon: "network", title: "联网 Agent", value: outboundAgentStatus)
                        }
                        settingsDivider
                        NavigationLink(destination: PrivacyDataControlsView()) {
                            settingsRow(icon: "lock.shield", title: "隐私与数据控制", value: "导出或删除")
                        }
                        settingsDivider
                        NavigationLink(destination: HealthDataResyncSettingsView()) {
                            settingsRow(icon: "arrow.clockwise.icloud", title: "健康数据重同步", value: "最近 90 天")
                        }
                        settingsDivider
                        NavigationLink(destination: HistoricalBackfillView()) {
                            settingsRow(icon: "icloud.and.arrow.down", title: "三年 Apple 健康回填", value: "长期基准")
                        }
                        settingsDivider
                        NavigationLink(destination: XunjiHistoryBackfillView()) {
                            settingsRow(icon: "dumbbell.fill", title: "训记训练历史回填", value: "力量负荷")
                        }
                    }
                }

                settingsGroup(eyebrow: "", title: "体验偏好") {
                    VStack(spacing: 0) {
                        NavigationLink(destination: CustomizationSettingsView()) {
                            settingsRow(icon: "scope", title: "健康目标", value: "\(dailyCalorieTarget) kcal · \(SleepTargetSettings.displayHours(sleepTargetHours))")
                        }
                        settingsDivider
                        NavigationLink(destination: NotificationSettingsView()) {
                            settingsRow(
                                icon: "bell",
                                title: "通知",
                                value: abnormalMetricAlertsOn || morningBriefOn || bedtimeRemindersOn ? "已配置" : "已关闭"
                            )
                        }
                        settingsDivider
                        NavigationLink(destination: AppearanceSettingsView()) {
                            settingsRow(icon: "circle.lefthalf.filled", title: "外观", value: darkModeRaw == "dark" ? "深色" : (darkModeRaw == "light" ? "浅色" : "跟随系统"))
                        }
                        settingsDivider
                        NavigationLink(destination: LanguageSettingsView()) {
                            settingsRow(
                                icon: "globe",
                                title: "语言",
                                value: AppLanguage(rawValue: languageRaw)?.displayName ?? AppLanguage.simplifiedChinese.displayName
                            )
                        }
                        settingsDivider
                        NavigationLink(destination: ShortcutsSettingsView()) {
                            settingsRow(icon: "command", title: "快捷指令", value: "已接入")
                        }
                    }
                }

                settingsGroup(eyebrow: "", title: "高级设置") {
                    VStack(spacing: 0) {
                        NavigationLink(destination: CGMSettingsView()) {
                            settingsRow(icon: "drop.degreesign", title: "连续血糖数据", value: "Apple 健康")
                        }
                        settingsDivider
                        NavigationLink(destination: ProductQualityDiagnosticsView()) {
                            settingsRow(icon: "chart.line.uptrend.xyaxis", title: "产品质量诊断", value: "28 天闭环")
                        }
                        settingsDivider
                        NavigationLink(destination: ExportDataSettingsView()) {
                            settingsRow(icon: "square.and.arrow.up", title: "数据导出", value: "本地资料")
                        }

                        if VelaCapabilityAvailability.cloudKitSyncEnabled {
                            settingsDivider
                            NavigationLink(destination: iCloudSyncSettingsView()) {
                                settingsRow(icon: "icloud", title: "iCloud 同步", value: "已接入")
                            }
                        }
                    }
                }

                settingsGroup(eyebrow: "", title: "关于 BodySeek") {
                    VStack(spacing: 0) {
                        NavigationLink(destination: WhatsNewSettingsView()) {
                            settingsRow(icon: "sparkles", title: "最新变化", value: VelaAppMetadata.marketingVersion)
                        }
                    }
                }
            }
            .padding(.horizontal, VelaTheme.pagePadding)
            .padding(.top, 18)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("个人空间")
        .accessibilityIdentifier("settings-surface")
        .velaRhythmDetailChrome()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") {
                    dismiss()
                }
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
            }
        }
    }

    private func settingsGroup<Content: View>(
        eyebrow: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VelaRhythmSectionHeader(
                eyebrow: eyebrow,
                title: title,
                actionTitle: nil,
                action: {}
            )

            content()
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(VelaTheme.rhythmMist.opacity(0.78), lineWidth: 0.75)
                )
        }
    }

    private var settingsDivider: some View {
        Divider()
            .overlay(VelaTheme.rhythmMist.opacity(0.72))
            .padding(.leading, 56)
    }
    
    private func settingsRow(icon: String, title: String, value: String?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(VelaTheme.rhythmMist.opacity(0.72))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
            }
            
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(.body, design: .default, weight: .medium))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if let value {
                        Text(value)
                            .font(.system(.subheadline, design: .default, weight: .regular))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(title)
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundStyle(VelaTheme.rhythmInk)

                Spacer()

                if let value {
                    Text(value)
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineLimit(1)
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.58))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 0)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }
    
    private var profileCardRow: some View {
        VStack(alignment: .leading, spacing: 16) {
            BodySeekPageIntro(
                eyebrow: "PERSONAL / YOUR FIELD NOTES",
                title: "关于你，\n持续了解中。",
                subtitle: "你的资料、偏好与健康记忆，都在这里。",
                artwork: .profile
            )
            HStack(spacing: 8) {
                settingsPill("本机保存", icon: "iphone")
                settingsPill("由你掌控", icon: "hand.raised")
            }
        }
    }

    private func settingsPill(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(.caption2, design: .default, weight: .semibold))
            .foregroundStyle(VelaTheme.rhythmInkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 9)
            .frame(minHeight: 30)
            .background(VelaTheme.rhythmMist.opacity(0.66), in: Capsule())
    }
}

struct ProductQualityDiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var snapshot = ProductQualitySnapshot(
        periodDays: 28,
        generatedPlans: 0,
        viewedDecisions: 0,
        startedActions: 0,
        completedFeedback: 0,
        adoptedDecisions: 0,
        accurateDecisions: 0,
        workoutLogs: 0,
        syncSuccesses: 0,
        syncFailures: 0
    )

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 7) {
                    Label("仅在本机计算", systemImage: "lock.fill")
                        .font(.headline)
                        .foregroundStyle(VelaTheme.accent)
                    Text("用于判断 Vela 是否真正帮助你完成“看见建议 → 开始行动 → 反馈结果 → 校准建议”的闭环，不会上传行为分析数据。")
                        .font(.footnote)
                        .foregroundStyle(VelaTheme.muted)
                }
                .padding(.vertical, 4)
            }

            Section("近 \(snapshot.periodDays) 天核心闭环") {
                qualityMetricRow("建议生成", count: snapshot.generatedPlans, rate: nil)
                qualityMetricRow("建议已查看", count: snapshot.viewedDecisions, rate: snapshot.viewRate)
                qualityMetricRow("行动已开始", count: snapshot.startedActions, rate: snapshot.actionRate)
                qualityMetricRow("反馈已完成", count: snapshot.completedFeedback, rate: snapshot.feedbackRate)
                qualityMetricRow("采纳或调整后采纳", count: snapshot.adoptedDecisions, rate: snapshot.adoptionRate)
                qualityMetricRow("准确或部分准确", count: snapshot.accurateDecisions, rate: snapshot.accuracyRate)
            }

            Section("可靠性") {
                qualityMetricRow("健康同步成功", count: snapshot.syncSuccesses, rate: snapshot.syncSuccessRate)
                qualityMetricRow("健康同步失败", count: snapshot.syncFailures, rate: nil)
                qualityMetricRow("训练记录完成", count: snapshot.workoutLogs, rate: nil)
                if snapshot.syncFailures > 0 && snapshot.syncSuccessRate < 0.9 {
                    Label("同步成功率偏低。建议前往“健康数据重同步”检查权限与数据源。", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(VelaTheme.warn)
                }
            }

            Section("如何解读") {
                Text("样本少于 7 天时只用于排查流程，不评价产品效果。建议至少连续使用 28 天，再观察采纳率、准确率与次日恢复是否共同改善。")
                    .font(.footnote)
                    .foregroundStyle(VelaTheme.muted)
            }
        }
        .navigationTitle("产品质量诊断")
        .velaRhythmFormSurface()
        .velaRhythmDetailChrome()
        .task { reload() }
        .refreshable { reload() }
    }

    @ViewBuilder
    private func qualityMetricRow(_ title: String, count: Int, rate: Double?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)")
                .foregroundStyle(VelaTheme.muted)
                .monospacedDigit()
            if let rate {
                Text(rate.formatted(.percent.precision(.fractionLength(0))))
                    .fontWeight(.semibold)
                    .foregroundStyle(rate >= 0.7 ? VelaTheme.success : (rate >= 0.4 ? VelaTheme.warn : VelaTheme.muted))
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    private func reload() {
        snapshot = DailyDecisionFeedbackService().qualitySnapshot(modelContext: modelContext)
    }
}

enum VelaCapabilityAvailability {
    static let cloudKitSyncEnabled = false
}

struct AppearanceSettingsView: View {
    @AppStorage("vela_dark_mode") private var darkModeRaw = "system"
    
    var body: some View {
        Form {
            Section(header: Text("主题选择")) {
                ForEach(["system", "light", "dark"], id: \.self) { mode in
                    Button {
                        darkModeRaw = mode
                    } label: {
                        HStack {
                            Text(mode == "dark" ? "深色" : (mode == "light" ? "浅色" : "跟随系统"))
                                .foregroundStyle(VelaTheme.fg)
                            Spacer()
                            if darkModeRaw == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(VelaTheme.accent)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("外观主题")
        .velaRhythmFormSurface()
        .velaRhythmDetailChrome()
    }
}

struct NotificationSettingsView: View {
    @AppStorage("agent_abnormal_metric_alerts") private var abnormalMetricAlertsOn = true
    @AppStorage("agent_morning_brief_alerts") private var morningBriefOn = true
    @AppStorage("agent_bedtime_reminders") private var bedtimeRemindersOn = true
    @AppStorage("agent_bedtime_hour") private var bedtimeHour = 22
    @AppStorage("agent_bedtime_minute") private var bedtimeMinute = 0
    @State private var authorizationMessage = ""
    
    var body: some View {
        Form {
            Section(header: Text("通知通道")) {
                Toggle("异常指标提醒", isOn: $abnormalMetricAlertsOn)
                    .onChange(of: abnormalMetricAlertsOn) { _, newValue in
                        NotificationService.shared.abnormalMetricAlertsEnabled = newValue
                        requestAuthorizationIfNeeded(enabled: newValue)
                    }
                Toggle("晨间健康简报", isOn: $morningBriefOn)
                    .onChange(of: morningBriefOn) { _, newValue in
                        NotificationService.shared.morningBriefAlertsEnabled = newValue
                        requestAuthorizationIfNeeded(enabled: newValue)
                    }
                Toggle("睡前提醒", isOn: $bedtimeRemindersOn)
                    .onChange(of: bedtimeRemindersOn) { _, newValue in
                        NotificationService.shared.bedtimeRemindersEnabled = newValue
                        requestAuthorizationIfNeeded(enabled: newValue)
                    }
            }

            Section(header: Text("睡前提醒时间")) {
                Picker("小时", selection: $bedtimeHour) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d", hour)).tag(hour)
                    }
                }
                Picker("分钟", selection: $bedtimeMinute) {
                    ForEach([0, 15, 30, 45], id: \.self) { minute in
                        Text(String(format: "%02d", minute)).tag(minute)
                    }
                }
                .onChange(of: bedtimeHour) { _, _ in
                    NotificationService.shared.scheduleBedtimeReminder()
                }
                .onChange(of: bedtimeMinute) { _, _ in
                    NotificationService.shared.scheduleBedtimeReminder()
                }
            }

            if !authorizationMessage.isEmpty {
                Section {
                    Text(authorizationMessage)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("通知")
        .velaRhythmFormSurface()
        .velaRhythmDetailChrome()
    }

    private func requestAuthorizationIfNeeded(enabled: Bool) {
        guard enabled else { return }
        Task {
            let granted = await NotificationService.shared.requestAuthorization()
            authorizationMessage = granted ? "系统通知权限已开启。" : "系统通知权限未开启，请在系统设置中允许 Vela 通知。"
        }
    }
}

struct CustomizationSettingsView: View {
    @AppStorage("vela_daily_calorie_target") private var dailyCalorieTarget = 2000
    @AppStorage(SleepTargetSettings.hoursKey) private var sleepTargetHours = SleepTargetSettings.defaultHours
    @State private var tempTarget = 2000
    
    var body: some View {
        Form {
            Section(header: Text("今日热量基准")) {
                Stepper("每日目标卡路里: \(tempTarget) kcal", value: $tempTarget, in: 1200...4000, step: 50)
                Button("保存更改") {
                    dailyCalorieTarget = tempTarget
                }
                .tint(VelaTheme.accent)
            }

            Section(header: Text("睡眠目标")) {
                Picker("每晚目标时长", selection: $sleepTargetHours) {
                    ForEach(SleepTargetSettings.availableHours, id: \.self) { hours in
                        Text(SleepTargetSettings.displayHours(hours)).tag(hours)
                    }
                }

                Text("该目标会用于睡眠评分和睡眠详情展示。")
                    .font(.caption)
                    .foregroundStyle(VelaTheme.muted)
            }
        }
        .onAppear {
            tempTarget = dailyCalorieTarget
        }
        .navigationTitle("自定义健康基准")
        .velaRhythmFormSurface()
        .velaRhythmDetailChrome()
    }
}

struct ShortcutsSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Siri 快捷指令与语音集成")
                    .font(.system(.title3, design: .default, weight: .bold))
                
                Text("以下快捷指令已通过 App Intents 接入，可在快捷指令 App 或 Siri 中使用：")
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.muted)
                
                VStack(alignment: .leading, spacing: 14) {
                    shortcutGuideRow(command: "查看 Vela 今日状态", desc: "打开首页查看今日恢复、睡眠和训练负荷。")
                    shortcutGuideRow(command: "询问 Vela 就绪状态", desc: "打开 Coach 并分析今天最重要的行动建议。")
                    shortcutGuideRow(command: "用 Vela 扫描餐食", desc: "打开餐食拍照分析入口。")
                }
                
                Spacer()
            }
            .padding(20)
        }
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("快捷指令")
        .velaRhythmDetailChrome()
    }
    
    private func shortcutGuideRow(command: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(command)
                .font(.system(.subheadline, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.accent)
            Text(desc)
                .font(.system(.caption, design: .default))
                .foregroundStyle(VelaTheme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(VelaTheme.secondaryGroupedBackground))
    }
}

struct LanguageSettingsView: View {
    @AppStorage("vela_app_language") private var languageRaw = AppLanguage.simplifiedChinese.rawValue
    
    var body: some View {
        Form {
            Section {
                Button { languageRaw = AppLanguage.simplifiedChinese.rawValue } label: {
                    HStack {
                        Text("简体中文")
                            .foregroundStyle(VelaTheme.fg)
                        Spacer()
                        if languageRaw == AppLanguage.simplifiedChinese.rawValue { Image(systemName: "checkmark").foregroundStyle(VelaTheme.accent) }
                    }
                }
                
                Button { languageRaw = AppLanguage.english.rawValue } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("English")
                                .foregroundStyle(VelaTheme.fg)
                            Text("Beta · 部分页面仍为中文")
                                .font(.caption)
                                .foregroundStyle(VelaTheme.muted)
                        }
                        Spacer()
                        if languageRaw == AppLanguage.english.rawValue { Image(systemName: "checkmark").foregroundStyle(VelaTheme.accent) }
                    }
                }
            } header: {
                Text("多语言选择")
            } footer: {
                Text("切换后重新打开 Vela 生效。English 正在持续完善，核心健康与训练页面目前以简体中文体验最佳。")
            }
        }
        .navigationTitle("应用语言")
        .velaRhythmFormSurface()
        .velaRhythmDetailChrome()
    }
}
