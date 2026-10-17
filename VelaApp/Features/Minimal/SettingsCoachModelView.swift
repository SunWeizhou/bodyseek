import SwiftUI
import SwiftData
import Charts

struct AIModelSettingsView: View {
    @AppStorage("vela_coach_text_model") private var textModel = "DeepSeek V4 Pro"
    @AppStorage("vela_coach_vision_model") private var visionModel = "Kimi 2.6"
    @AppStorage(CoachReasoningMode.storageKey) private var reasoningMode = CoachReasoningMode.adaptive.rawValue
    @AppStorage(CoachOutboundDataPolicy.consentVersionKey) private var outboundConsentVersion = 0
    @AppStorage(CoachOutboundDataPolicy.healthKey) private var outboundHealth = false
    @AppStorage(CoachOutboundDataPolicy.trainingKey) private var outboundTraining = false
    @AppStorage(CoachOutboundDataPolicy.nutritionKey) private var outboundNutrition = false
    @AppStorage(CoachOutboundDataPolicy.journalKey) private var outboundJournal = false
    @AppStorage(CoachOutboundDataPolicy.wikiKey) private var outboundWiki = false
    @AppStorage(CoachOutboundDataPolicy.reportsKey) private var outboundReports = false
    @AppStorage(CoachOutboundDataPolicy.conversationHistoryKey) private var outboundConversationHistory = false
    @AppStorage(CoachOutboundDataPolicy.webSearchKey) private var outboundWebSearch = false
    @State private var deepseekKey = ""
    @State private var kimiKey = ""
    @State private var isTesting = false
    @State private var testResultText = ""
    @State private var showSaveSuccess = false
    
    let textModels = DeepSeekTextModel.allCases.map(\.rawValue)
    let visionModels = ["Kimi 2.6"]
    
    var body: some View {
        Form {
            Section(header: Text("模型连接配置")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DeepSeek 密钥")
                        .font(.system(.caption, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.muted)
                    SecureField("输入 DeepSeek 密钥...", text: $deepseekKey)
                        .font(.system(.footnote, design: .default))
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kimi 密钥（图片识别）")
                        .font(.system(.caption, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.muted)
                    SecureField("输入 Kimi 密钥...", text: $kimiKey)
                        .font(.system(.footnote, design: .default))
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("大语言模型选择")) {
                // 响应模式（CoachReasoningMode）当前无消费者，已隐藏：
                // 模型选择以「对话文本模型」Picker 为准。恢复推理模式时在此重新挂载。
                Picker("对话文本模型", selection: $textModel) {
                    ForEach(textModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                
                Picker("图像视觉模型", selection: $visionModel) {
                    ForEach(visionModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
            }

            Section(header: Text("数据如何流动")) {
                Label {
                    Text("只有当你主动发送 Coach 消息时，消息与回答所需的健康、训练上下文才会发送给 DeepSeek；餐食照片分析由第三方 Moonshot（Kimi Vision）处理，照片只会用于该次营养分析。")
                } icon: {
                    Image(systemName: "text.bubble.fill")
                        .foregroundStyle(VelaTheme.accent)
                }

                Label {
                    Text("餐食照片仅在你确认分析后发送给 Kimi。自动任务还需要在“联网 AI 授权”中单独开启。")
                } icon: {
                    Image(systemName: "photo.badge.checkmark.fill")
                        .foregroundStyle(VelaTheme.energyColor)
                }

                Label {
                    Text("API 密钥保存在系统钥匙串；模型选择保存在本机设置。Vela 不会把密钥写入聊天记录。")
                } icon: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(VelaTheme.recoveryColor)
                }
            }
            .font(.footnote)

            Section(header: Text("DeepSeek 数据授权")) {
                if outboundConsentVersion >= CoachOutboundDataPolicy.currentConsentVersion {
                    Toggle("健康指标与化验", isOn: $outboundHealth)
                    Toggle("训练记录与计划", isOn: $outboundTraining)
                    Toggle("营养记录", isOn: $outboundNutrition)
                    Toggle("日志与习惯", isOn: $outboundJournal)
                    Toggle("个人档案与长期记忆", isOn: $outboundWiki)
                    Toggle("历史 AI 报告", isOn: $outboundReports)
                    Toggle("当前对话历史", isOn: $outboundConversationHistory)
                    Toggle("Bing 联网搜索关键词", isOn: $outboundWebSearch)

                    Text("关闭的类别会在本机组装上下文时移除，同时禁用对应的 AI 读取工具。你的手动问题文本仍会发送。")
                        .font(.caption)
                        .foregroundStyle(VelaTheme.muted)

                    Button("撤销全部联网数据授权", role: .destructive) {
                        CoachOutboundDataPolicy.revoke()
                        outboundConsentVersion = 0
                    }
                } else {
                    Label("尚未授权。首次发送联网 Coach 消息时，Vela 会逐项询问。", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(VelaTheme.muted)
                }
            }
            
            Section(header: Text("连接测试与保存")) {
                Button {
                    Task {
                        await testConnection()
                    }
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView().padding(.trailing, 8)
                        }
                        Text(isTesting ? "正在测试连接..." : "测试模型连接")
                            .bold()
                            .foregroundStyle(VelaTheme.accent)
                    }
                }
                
                if !testResultText.isEmpty {
                    Text(testResultText)
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .foregroundStyle(testResultText.contains("成功") ? VelaTheme.systemGreen : VelaTheme.systemRed)
                }
                
                Button("保存配置") {
                    saveKeysToKeychain()
                }
                .bold()
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge).fill(VelaTheme.accent))
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            loadKeysFromKeychain()
        }
        .alert("保存成功", isPresented: $showSaveSuccess) {
            Button("好") {}
        } message: {
            Text("模型密钥已写入系统钥匙串，模型选择已保存在本机设置。")
        }
        .navigationTitle("AI 模型设置")
        .velaRhythmFormSurface()
        .velaRhythmDetailChrome()
    }
    
    private func loadKeysFromKeychain() {
        if let dsKey = try? KeychainService.shared.read(account: "deepseek_api_key") {
            deepseekKey = dsKey
        }
        if let kmKey = try? KeychainService.shared.read(account: FoodPhotoAnalyzer.keychainAccount) {
            kimiKey = kmKey
        }
    }
    
    private func saveKeysToKeychain() {
        do {
            let trimmedDeepSeekKey = deepseekKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedKimiKey = kimiKey.trimmingCharacters(in: .whitespacesAndNewlines)
 
            if trimmedDeepSeekKey.isEmpty {
                KeychainService.shared.delete(account: "deepseek_api_key")
            } else {
                try KeychainService.shared.save(trimmedDeepSeekKey, account: "deepseek_api_key")
            }
 
            if trimmedKimiKey.isEmpty {
                KeychainService.shared.delete(account: FoodPhotoAnalyzer.keychainAccount)
            } else {
                try KeychainService.shared.save(trimmedKimiKey, account: FoodPhotoAnalyzer.keychainAccount)
            }
            showSaveSuccess = true
        } catch {
            testResultText = "保存失败: \(error.localizedDescription)"
        }
    }
    
    @MainActor
    private func testConnection() async {
        let key = deepseekKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            testResultText = "测试失败：请先填写 DeepSeek 密钥。"
            return
        }
 
        isTesting = true
        testResultText = ""
        defer { isTesting = false }
 
        do {
            let startedAt = Date()
            _ = try await DeepSeekProvider(
                apiKey: key,
                model: DeepSeekTextModel(displayName: textModel).apiIdentifier
            ).complete(
                request: LLMRequest(
                    systemPrompt: "You are testing a private health app provider connection.",
                    userPrompt: "请用一句简短中文确认连接成功。",
                    contextJSON: "{}"
                )
            )
            let latencyMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
            testResultText = "连接测试成功。模型延时: \(latencyMilliseconds)ms"
        } catch {
            testResultText = "连接测试失败: \(error.localizedDescription)"
        }
    }
}

struct DataSourceSettingsView: View {
    let dashboard: DashboardSummary
    var onRefresh: (() async -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var isSyncing = false
    @State private var lastSync: Date?
    @State private var authErrorMessage: String?
    @State private var successTier: HealthPermissionTier?
 
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("连接 Apple 健康")
                    .font(.system(.callout, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.fg)
                    .padding(.leading, 16)
                    .padding(.top, 16)
 
                Text("按用途逐步授权。Vela 只读取你允许的数据，并用于生成恢复、训练负荷和长期趋势参考。")
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.muted)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
 
                VStack(spacing: 12) {
                    tierRequestCard(
                        tier: .core,
                        title: "基础健康信号",
                        desc: "睡眠、HRV、静息心率、日常心率、呼吸、步数和训练记录。",
                        impact: "用于判断今天是否适合训练，以及恢复分数是否可信。",
                        action: "授权基础数据",
                        color: VelaTheme.systemPink
                    )
 
                    tierRequestCard(
                        tier: .enhanced,
                        title: "体能与身体组成",
                        desc: "最大摄氧量、体重、体脂率、去脂体重、血氧和腕温。",
                        impact: "用于长期趋势、体能变化和恢复异常解释。",
                        action: "授权体能数据",
                        color: VelaTheme.tagPurple
                    )
 
                    tierRequestCard(
                        tier: .advanced,
                        title: "营养与进阶指标",
                        desc: "血糖、血压、水分、膳食摄入、步态稳定性、正念和睡眠呼吸事件。",
                        impact: "用于解释能量、压力、睡眠质量和训练波动来源。",
                        action: "授权进阶数据",
                        color: VelaTheme.infoBlue
                    )
                }
                .padding(.horizontal, 16)
 
                if let authErrorMessage {
                    Text(authErrorMessage)
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }
 
                if let successTier {
                    Text("已向系统请求\(authorizationTierTitle(successTier))。")
                        .font(.system(.footnote, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.systemGreen)
                        .padding(.horizontal, 16)
                }
 
                Text("已同步健康传感器")
                    .font(.system(.callout, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.fg)
                    .padding(.leading, 16)
                
                VStack(spacing: 0) {
                    sensorRow(
                        name: "Apple 健康",
                        status: appleHealthStatus,
                        count: appleHealthDetail
                    )
                }
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(VelaTheme.secondaryGroupedBackground))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(VelaTheme.separatorSoft, lineWidth: 0.5))
                .padding(.horizontal, 16)
 
                Button {
                    Task {
                        isSyncing = true
                        if let onRefresh {
                            await onRefresh()
                        }
                        lastSync = Date()
                        isSyncing = false
                    }
                } label: {
                    HStack {
                        if isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(isSyncing ? "正在同步..." : "立即同步 Apple 健康")
                    }
                    .font(.system(.footnote, design: .default, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VelaTheme.accent))
                }
                .buttonStyle(.plain)
                .disabled(isSyncing)
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("健康数据源")
        .velaRhythmDetailChrome()
    }
 
    private func tierRequestCard(
        tier: HealthPermissionTier,
        title: String,
        desc: String,
        impact: String,
        action: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(color.opacity(0.12)))
 
                Text(title)
                    .font(.system(.subheadline, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.fg)
 
                Spacer()
            }
 
            Text(desc)
                .font(.system(.caption, design: .default))
                .foregroundStyle(VelaTheme.muted)
                .lineSpacing(2)
 
            Text(impact)
                .font(.system(.caption, design: .default, weight: .medium))
                .foregroundStyle(VelaTheme.fg2)
                .lineSpacing(2)
 
            Button {
                Task {
                    do {
                        authErrorMessage = nil
                        successTier = nil
                        try await HealthAuthorizationService().requestAuthorization(tier: tier)
                        successTier = tier
                    } catch {
                        authErrorMessage = "权限授权失败：\(error.localizedDescription)"
                    }
                }
            } label: {
                Text(action)
                    .font(.system(.footnote, design: .default, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous).fill(color))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VelaTheme.secondaryGroupedBackground))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VelaTheme.separatorSoft, lineWidth: 0.5))
    }
 
    private var appleHealthStatus: String {
        if isSyncing { return "同步中" }
        switch dashboard.source {
        case .healthKit: return "已同步"
        case .cache: return "已读取缓存"
        case .empty: return "待同步"
        case .preview: return "模拟数据"
        }
    }
 
    private var appleHealthDetail: String {
        switch dashboard.source {
        case .healthKit:
            return lastSync.map { "最近同步：\($0.formatted(date: .omitted, time: .shortened))" }
                ?? "已读取 Apple 健康 data"
        case .cache:
            return "正在显示最近一次 Apple 健康快照"
        case .empty:
            return "未读取到可用健康数据"
        case .preview:
            return "当前为调试模拟数据"
        }
    }
 
    private func authorizationTierTitle(_ tier: HealthPermissionTier) -> String {
        switch tier {
        case .core:
            return "基础健康信号授权"
        case .enhanced:
            return "体能与身体组成授权"
        case .advanced:
            return "营养与进阶指标授权"
        }
    }
    
    private func sensorRow(name: String, status: String, count: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(.subheadline, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.fg)
                Text(count)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(VelaTheme.muted)
            }
            Spacer()
            Text(status)
                .font(.system(.footnote, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.systemGreen)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct HealthDataResyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var services: VelaServices
    @State private var isSyncing = false
    @State private var statusMessage = ""
 
    var body: some View {
        Form {
            Section {
                Text("重新读取并计算最近 90 天 Apple 健康数据。该操作会刷新已有缓存，适合补授权、换设备或发现旧数据未更新后使用。")
                    .font(.caption)
                    .foregroundStyle(VelaTheme.muted)
 
                Button {
                    resync()
                } label: {
                    if isSyncing {
                        ProgressView()
                    } else {
                        Label("重新同步最近 90 天", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isSyncing)
            }
 
            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("健康数据重同步")
        .velaRhythmFormSurface()
        .velaRhythmDetailChrome()
    }
 
    private func resync() {
        isSyncing = true
        statusMessage = "正在重新同步..."
        Task { @MainActor in
            let succeeded = await services.syncCoordinator.runReporting(source: .healthKit, force: true) {
                try await HealthKitSyncEngine(
                    queryService: services.queryService,
                    modelContext: modelContext
                ).syncPastDays(90, forceRefreshRecentDays: 90)
            }
            if succeeded {
                statusMessage = "最近 90 天健康数据已重新同步。"
            } else {
                let detail = services.syncCoordinator.sourceStatuses[.healthKit]?.lastErrorDescription ?? "未知错误"
                statusMessage = "重新同步失败：\(detail)"
            }
            isSyncing = false
        }
    }
}

struct CGMSettingsSummary {
    let readings: [BloodGlucoseReading]
 
    init(readings: [BloodGlucoseReading]) {
        self.readings = readings.sorted { $0.date < $1.date }
    }
 
    var latestReading: BloodGlucoseReading? { readings.last }
    var readingCount: Int { readings.count }
    var hasReadings: Bool { !readings.isEmpty }
}

struct CGMSettingsView: View {
    @State private var readings: [BloodGlucoseReading] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
 
    private var summary: CGMSettingsSummary {
        CGMSettingsSummary(readings: readings)
    }
 
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sourceCard
 
                if isLoading {
                    ProgressView("正在读取 Apple 健康血糖数据...")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if let errorMessage {
                    emptyCard(message: errorMessage)
                } else if summary.hasReadings {
                    latestReadingCard
                    trendCard
                } else {
                    emptyCard(message: "Apple 健康中暂未读取到血糖样本。授权高级健康数据后，如果你的 CGM 已将记录写入 Apple 健康，趋势会自动出现在这里。")
                }
 
                Button {
                    Task { await requestAccessAndReload() }
                } label: {
                    Label("请求权限并刷新", systemImage: "arrow.clockwise")
                        .font(.system(.footnote, design: .default, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(VelaTheme.infoBlue)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
            .padding(20)
        }
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("连续血糖监测 (CGM)")
        .velaRhythmDetailChrome()
        .task {
            await reload()
        }
    }
 
    private var sourceCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 30))
                .foregroundStyle(VelaTheme.infoBlue)
                .frame(width: 54, height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(VelaTheme.infoBlue.opacity(0.12))
                )
 
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple 健康 CGM 数据")
                    .font(.system(.body, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.fg)
                Text("读取已同步到 Apple 健康的血糖样本")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(VelaTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }
 
    private var latestReadingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最新血糖")
                .font(.system(.footnote, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.muted)
 
            if let latest = summary.latestReading {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(latest.milligramsPerDeciliter.formatted(.number.precision(.fractionLength(0))))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(VelaTheme.fg)
                    Text("mg/dL")
                        .font(.system(.footnote, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.muted)
                }
 
                Text("最近更新 \(latest.date.formatted(date: .abbreviated, time: .shortened)) · 近 14 天共 \(summary.readingCount) 条")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(VelaTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }
 
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("近 14 天趋势")
                .font(.system(.subheadline, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.fg)
 
            Chart(summary.readings) { reading in
                LineMark(
                    x: .value("时间", reading.date),
                    y: .value("血糖", reading.milligramsPerDeciliter)
                )
                .foregroundStyle(VelaTheme.infoBlue)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
 
                PointMark(
                    x: .value("时间", reading.date),
                    y: .value("血糖", reading.milligramsPerDeciliter)
                )
                .foregroundStyle(VelaTheme.infoBlue)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 190)
        }
        .padding(16)
        .background(cardBackground)
    }
 
    private func emptyCard(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "drop.triangle")
                .font(.system(size: 32))
                .foregroundStyle(VelaTheme.infoBlue)
            Text("等待血糖数据")
                .font(.system(.body, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.fg)
            Text(message)
                .font(.system(.footnote, design: .default))
                .multilineTextAlignment(.center)
                .foregroundStyle(VelaTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(cardBackground)
    }
 
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(VelaTheme.separatorSoft, lineWidth: 0.5)
            )
    }
 
    @MainActor
    private func requestAccessAndReload() async {
        isLoading = true
        do {
            try await HealthAuthorizationService().requestAuthorization(tier: .advanced)
            await reload()
        } catch {
            errorMessage = "无法读取 Apple 健康血糖数据：\(error.localizedDescription)"
            isLoading = false
        }
    }
 
    @MainActor
    private func reload() async {
        isLoading = true
        errorMessage = nil
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
 
        do {
            readings = try await HealthKitQueryService().bloodGlucoseSamples(
                in: DateRangeQuery(start: start, end: now)
            )
        } catch {
            errorMessage = "无法读取 Apple 健康血糖数据：\(error.localizedDescription)"
        }
        isLoading = false
    }
}

struct CoachPersonalitySettingsView: View {
    @AppStorage("vela_coach_personality") private var coachPersonalityRaw = CoachPersonality.guardian.rawValue
    @State private var selectedPersonality: CoachPersonality = .guardian
 
    var body: some View {
        Form {
            Section(header: Text("选择教练风格")) {
                ForEach(CoachPersonality.allCases) { personality in
                    Button {
                        selectedPersonality = personality
                        coachPersonalityRaw = personality.rawValue
                        CoachPersonality.current = personality
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: personality.icon)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(width: 28, height: 28)
                                .background(personality.tint)
                                .clipShape(Circle())
 
                            VStack(alignment: .leading, spacing: 4) {
                                Text(personality.displayName)
                                    .font(.system(.subheadline, design: .default, weight: .bold))
                                    .foregroundStyle(VelaTheme.fg)
                                Text(personality.description)
                                    .font(.system(.caption, design: .default))
                                    .foregroundStyle(VelaTheme.muted)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            if selectedPersonality == personality {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(VelaTheme.accent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("AI 教练风格")
        .velaRhythmDetailChrome()
        .onAppear {
            selectedPersonality = CoachPersonality(rawValue: coachPersonalityRaw) ?? .guardian
        }
    }
}

struct AgentAutomationSettingsView: View {
    @StateObject private var agentConfig = AutoAgentConfig.shared
    @AppStorage("vela_app_language") private var languageRaw = AppLanguage.simplifiedChinese.rawValue
    @State private var oneTimeCheckInDate = Date().addingTimeInterval(3600)
    @State private var oneTimeStatus = ""
    
    private var isChinese: Bool {
        AppLanguage(rawValue: languageRaw)?.isChinese ?? true
    }

    private var checkInSignature: String {
        [
            agentConfig.hourlyCheckins ? "1" : "0", "\(agentConfig.hourlyCheckinMinute)",
            agentConfig.progressCheckins ? "1" : "0", "\(agentConfig.progressCheckinHour)",
            agentConfig.weeklySummary ? "1" : "0", "\(agentConfig.weeklySummaryDay)", "\(agentConfig.weeklySummaryHour)",
            agentConfig.monthlySummary ? "1" : "0", "\(agentConfig.monthlySummaryDay)", "\(agentConfig.monthlySummaryHour)",
        ].joined(separator: ":")
    }
    
    var body: some View {
        Form {
            Section(header: Text(isChinese ? "联网 AI 授权" : "Network AI consent")) {
                Toggle(isChinese ? "允许后台自动任务使用联网 AI" : "Allow background tasks to use network AI", isOn: $agentConfig.backgroundNetworkAIConsent)
                    .tint(VelaTheme.accent)
                    .onChange(of: agentConfig.backgroundNetworkAIConsent) { _, enabled in
                        if enabled {
                            BackgroundTaskManager.schedule()
                        } else {
                            BackgroundTaskManager.cancelAll()
                        }
                    }

                Text(isChinese
                     ? "开启后，已启用的自动任务可能将必要的健康与训练上下文发送给你配置的 AI 服务商以生成报告。手动与 Coach 对话不受此开关影响。"
                     : "When enabled, active automated tasks may send necessary health and training context to your configured AI provider. Manual Coach conversations are unaffected.")
                    .font(.caption)
                    .foregroundStyle(VelaTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(header: Text("自动任务执行")) {
                ForEach(agentConfig.skillList(isChinese: isChinese)) { skill in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: skill.icon)
                                .font(.body)
                                .foregroundStyle(VelaTheme.accent)
                                .frame(width: 28)
 
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isChinese ? skill.name : skill.enName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(VelaTheme.fg)
                                Text(skill.schedule)
                                    .font(.caption2)
                                    .foregroundStyle(VelaTheme.muted)
                            }
 
                            Spacer()
 
                            Toggle("", isOn: Binding(
                                get: { skill.isEnabled },
                                set: { new in
                                    var config = agentConfig
                                    config[keyPath: skill.configKey] = new
                                    if agentConfig.canRunBackgroundNetworkAI {
                                        BackgroundTaskManager.schedule()
                                    } else {
                                        BackgroundTaskManager.cancelAll()
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(VelaTheme.accent)
                        }
 
                        Text(isChinese ? skill.description : skill.enDescription)
                            .font(.caption)
                            .foregroundStyle(VelaTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                }
            }

            Section(header: Text(isChinese ? "本机 Check-ins" : "On-device check-ins")) {
                Text(isChinese
                     ? "这些提醒完全由 iPhone 本机安排，不会发送健康数据，也不保证精确到分钟。小时提醒默认关闭。"
                     : "These reminders are scheduled on-device and send no health data. Delivery is not guaranteed to the exact minute. Hourly reminders default off.")
                    .font(.caption)
                    .foregroundStyle(VelaTheme.muted)

                DatePicker(isChinese ? "一次性" : "One-time", selection: $oneTimeCheckInDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                Button(isChinese ? "安排一次性 Check-in" : "Schedule one-time check-in") {
                    Task {
                        let success = await CoachCheckInScheduler.scheduleOneTime(at: oneTimeCheckInDate)
                        oneTimeStatus = success
                            ? (isChinese ? "已安排" : "Scheduled")
                            : (isChinese ? "未安排：请检查通知权限" : "Not scheduled: check notification permission")
                    }
                }
                if !oneTimeStatus.isEmpty {
                    Text(oneTimeStatus).font(.caption).foregroundStyle(VelaTheme.muted)
                }

                Toggle(isChinese ? "每小时提醒" : "Hourly", isOn: $agentConfig.hourlyCheckins)
                if agentConfig.hourlyCheckins {
                    Picker(isChinese ? "每小时的分钟" : "Minute of each hour", selection: $agentConfig.hourlyCheckinMinute) {
                        ForEach([0, 15, 30, 45], id: \.self) { Text(":\(String(format: "%02d", $0))").tag($0) }
                    }
                }

                Toggle(isChinese ? "每日回顾" : "Daily", isOn: $agentConfig.progressCheckins)
                if agentConfig.progressCheckins {
                    Picker(isChinese ? "每日时间" : "Daily time", selection: $agentConfig.progressCheckinHour) {
                        ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                    }
                }

                Toggle(isChinese ? "每周回顾" : "Weekly", isOn: $agentConfig.weeklySummary)
                if agentConfig.weeklySummary {
                    Picker(isChinese ? "星期" : "Weekday", selection: $agentConfig.weeklySummaryDay) {
                        ForEach(1...7, id: \.self) { Text(weekdayLabel($0)).tag($0) }
                    }
                    Picker(isChinese ? "时间" : "Time", selection: $agentConfig.weeklySummaryHour) {
                        ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                    }
                }

                Toggle(isChinese ? "每月回顾" : "Monthly", isOn: $agentConfig.monthlySummary)
                if agentConfig.monthlySummary {
                    Stepper(isChinese ? "每月第 \(agentConfig.monthlySummaryDay) 天" : "Day \(agentConfig.monthlySummaryDay)", value: $agentConfig.monthlySummaryDay, in: 1...28)
                    Picker(isChinese ? "时间" : "Time", selection: $agentConfig.monthlySummaryHour) {
                        ForEach(0..<24, id: \.self) { Text("\($0):00").tag($0) }
                    }
                }
            }
        }
        .navigationTitle("Agent 自动化技能")
        .velaRhythmFormSurface()
        .velaRhythmDetailChrome()
        .onChange(of: checkInSignature) { _, _ in
            Task { await CoachCheckInScheduler.reschedule(config: agentConfig) }
        }
    }

    private func weekdayLabel(_ value: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols.indices.contains(value - 1) ? symbols[value - 1] : "\(value)"
    }
}
