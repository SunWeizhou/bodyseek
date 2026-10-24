import SwiftUI
import SwiftData

struct BodyModelEditView: View {
    var onRefresh: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \OnboardingState.updatedAt, order: .reverse)
    private var onboardingStates: [OnboardingState]
    
    private var onboarding: OnboardingState? { onboardingStates.first }
    
    @State private var primaryGoal = "performance"
    @State private var trainingStyle = "strength"
    @State private var weeklyTrainingDays = 3
    @State private var sessionDurationMinutes = 45
    @State private var experienceLevel = "intermediate"
    @State private var nextRotationFocus = "back"
    @State private var coachStyle = "direct"
    @State private var hasGym = true
    @State private var hasHomeEquipment = true
    @State private var hasBodyweight = true
    @State private var saveError: String?
    
    var body: some View {
        Form {
            Section(header: Text("健身目标")) {
                Picker("主要目标", selection: $primaryGoal) {
                    Text(localizedOnboardingGoal("performance")).tag("performance")
                    Text(localizedOnboardingGoal("muscle_gain")).tag("muscle_gain")
                    Text(localizedOnboardingGoal("fat_loss")).tag("fat_loss")
                    Text(localizedOnboardingGoal("health")).tag("health")
                }
                .pickerStyle(.menu)
                
                Picker("体能经验", selection: $experienceLevel) {
                    Text(localizedOnboardingExperience("beginner")).tag("beginner")
                    Text(localizedOnboardingExperience("intermediate")).tag("intermediate")
                    Text(localizedOnboardingExperience("advanced")).tag("advanced")
                }
                .pickerStyle(.segmented)
            }
            
            Section(header: Text("训练偏好")) {
                Picker("训练风格", selection: $trainingStyle) {
                    // 选项集与 onboarding 一致（此前 mixed/cardio/yoga 与
                    // strength/hybrid/endurance 不互通，编辑即丢值）。
                    Text(localizedOnboardingTrainingStyle("strength")).tag("strength")
                    Text(localizedOnboardingTrainingStyle("hybrid")).tag("hybrid")
                    Text(localizedOnboardingTrainingStyle("endurance")).tag("endurance")
                }
                .pickerStyle(.menu)
                
                Stepper(value: $weeklyTrainingDays, in: 1...7) {
                    HStack {
                        Text("每周频次")
                        Spacer()
                        Text("\(weeklyTrainingDays) 次 / 周")
                            .font(.system(.body, design: .monospaced).bold())
                            .foregroundStyle(VelaTheme.accent)
                    }
                }
                
                Stepper(value: $sessionDurationMinutes, in: 20...120, step: 5) {
                    HStack {
                        Text("单次时长")
                        Spacer()
                        Text("\(sessionDurationMinutes) 分钟")
                            .font(.system(.body, design: .monospaced).bold())
                            .foregroundStyle(VelaTheme.accent)
                    }
                }
            }

            Section(header: Text("训练轮转")) {
                LabeledContent("轮转顺序", value: "背 · 胸 · 肩 · 腿 · 手臂核心")

                Picker("下一站", selection: $nextRotationFocus) {
                    ForEach(TrainingRotationResolver.defaultFocuses, id: \.self) { focus in
                        Text(TrainingRotationResolver.title(for: focus)).tag(focus)
                    }
                }
                .pickerStyle(.menu)
            }
            
            Section(header: Text("训练设备")) {
                Toggle(localizedOnboardingEquipment("gym"), isOn: $hasGym)
                    .tint(VelaTheme.accent)
                Toggle(localizedOnboardingEquipment("home_equipment"), isOn: $hasHomeEquipment)
                    .tint(VelaTheme.accent)
                Toggle(localizedOnboardingEquipment("bodyweight"), isOn: $hasBodyweight)
                    .tint(VelaTheme.accent)
            }
            
            Section(header: Text("教练指导")) {
                Picker("指导风格", selection: $coachStyle) {
                    Text(localizedOnboardingCoachStyle("direct")).tag("direct")
                    Text(localizedOnboardingCoachStyle("balanced")).tag("balanced")
                    Text(localizedOnboardingCoachStyle("explanatory")).tag("explanatory")
                }
                .pickerStyle(.segmented)
            }
        }
        .velaRhythmFormSurface()
        .navigationTitle("编辑身体模型")
        .velaRhythmDetailChrome()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    if saveEdits() {
                        dismiss()
                    }
                }
                .bold()
                .foregroundStyle(VelaTheme.rhythmDeep)
            }
        }
        .onAppear {
            loadOnboardingState()
        }
        .alert("身体模型未保存", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }
    
    private func loadOnboardingState() {
        let trainingResponses = (try? TrainingResponseRepository(modelContext: modelContext)
            .fetchAllSortedByDate()) ?? []
        guard let state = onboarding else { return }
        primaryGoal = state.goalProfile.primaryGoal
        experienceLevel = state.goalProfile.experienceLevel
        trainingStyle = state.trainingPreference.trainingStyle
        weeklyTrainingDays = state.trainingPreference.weeklyTrainingDays
        sessionDurationMinutes = state.trainingPreference.sessionDurationMinutes
        nextRotationFocus = TrainingRotationResolver.nextFocus(
            profile: state.trainingPreference,
            recentResponses: trainingResponses.map(\.dto)
        )
        
        let equip = state.equipmentProfile.equipment
        hasGym = equip.contains("gym")
        hasHomeEquipment = equip.contains("home_equipment")
        hasBodyweight = equip.contains("bodyweight")
        
        coachStyle = state.coachingPreference.style
    }
    
    private func saveEdits() -> Bool {
        let state = onboarding ?? OnboardingState()
        state.goalProfile = UserGoalProfile(
            primaryGoal: primaryGoal,
            secondaryGoals: state.goalProfile.secondaryGoals,
            experienceLevel: experienceLevel,
            bodyConcerns: state.goalProfile.bodyConcerns
        )
        state.trainingPreference = TrainingPreferenceProfile(
            trainingStyle: trainingStyle,
            weeklyTrainingDays: weeklyTrainingDays,
            sessionDurationMinutes: sessionDurationMinutes,
            preferredTrainingDays: state.trainingPreference.preferredTrainingDays,
            rotationFocuses: TrainingRotationResolver.defaultFocuses,
            nextRotationFocus: nextRotationFocus
        )
        
        var equip: [String] = []
        if hasGym { equip.append("gym") }
        if hasHomeEquipment { equip.append("home_equipment") }
        if hasBodyweight { equip.append("bodyweight") }
        
        state.equipmentProfile = EquipmentProfile(
            equipment: equip,
            scheduleNotes: "\(weeklyTrainingDays)x weekly, \(sessionDurationMinutes)m sessions"
        )
        state.coachingPreference = CoachingPreference(
            style: coachStyle,
            explanationDepth: coachStyle == "explanatory" ? "detailed" : "balanced",
            language: "zh-Hans"
        )
        state.currentStep = "completed"
        state.isCompleted = true
        state.completedAt = state.completedAt ?? Date()
        state.updatedAt = Date()
        
        if onboardingStates.isEmpty {
            modelContext.insert(state)
        }
        
        do {
            try modelContext.save()
            VelaAppState.shared.markLocalDataChanged()
            Task {
                if let onRefresh {
                    await onRefresh()
                }
            }
            return true
        } catch {
            modelContext.rollback()
            saveError = "本次修改未能写入本机资料，请重试。"
            return false
        }
    }
}

struct BaselineRangeIndicator: View {
    let today: Double?
    let baseline: Double?
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let baseVal = baseline {
                    Text("基线: \(Int(baseVal))\(unit)")
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                } else {
                    Text("基线积累中")
                        .font(.system(.caption2, design: .default, weight: .medium))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                
                Spacer()
                
                if let todayVal = today {
                    Text("今日: \(Int(todayVal))\(unit)")
                        .font(.system(.caption2, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                } else {
                    Text("今日: --")
                        .font(.system(.caption2, design: .default, weight: .medium))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
            }
            
            if let base = baseline {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(VelaTheme.rhythmMist)
                            .frame(height: 6)

                        let width = geo.size.width
                        let startPct = 0.35
                        let endPct = 0.65
                        Capsule()
                            .fill(VelaTheme.rhythmDeep.opacity(0.18))
                            .frame(width: width * (endPct - startPct), height: 6)
                            .offset(x: width * startPct)
                        
                        Rectangle()
                            .fill(VelaTheme.rhythmInkSecondary)
                            .frame(width: 1.5, height: 10)
                            .offset(x: width * 0.5, y: -2)
                        
                        if let tod = today {
                            let pct = 0.5 + (tod - base) / (base * 0.4)
                            let clampedPct = min(max(pct, 0.05), 0.95)
                            Circle()
                                .fill(VelaTheme.rhythmDeep)
                                .frame(width: 10, height: 10)
                                .offset(x: width * clampedPct - 5, y: -2)
                        }
                    }
                }
                .frame(height: 10)
            }
        }
    }
}

struct BodyModelDetailView: View {
    let selectedDate: Date
    let dashboard: DashboardSummary
    var onRefresh: (() async -> Void)?

    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \OnboardingState.updatedAt, order: .reverse)
    private var onboardingStates: [OnboardingState]
    @State private var journalEntries: [JournalEntryRecord] = []
    @State private var dailySummaries: [DailyHealthSummaryRecord] = []
    @State private var strengthWorkouts: [StrengthWorkoutRecord] = []
    @State private var trainingResponses: [TrainingResponseRecord] = []
    
    private var onboarding: OnboardingState? { onboardingStates.first }
    private var hasCompletedProfile: Bool { onboarding?.isCompleted == true }
    private var staticGoalText: String {
        hasCompletedProfile ? displayGoal(onboarding?.goalProfile.primaryGoal ?? "unknown") : "尚未设置"
    }
    private var staticExperienceText: String {
        hasCompletedProfile ? displayExperience(onboarding?.goalProfile.experienceLevel ?? "unknown") : "待补充"
    }
    private var staticFrequencyText: String {
        guard hasCompletedProfile else { return "待设置" }
        return "\(onboarding?.trainingPreference.weeklyTrainingDays ?? 0)次/周 · \(onboarding?.trainingPreference.sessionDurationMinutes ?? 0)分钟/次"
    }
    private var staticCoachStyleText: String {
        hasCompletedProfile ? displayCoachingStyle(onboarding?.coachingPreference.style ?? "unknown") : "待设置"
    }
    private var healthProfileSummary: String {
        var values: [String] = []
        let age = UserProfileSettings.age() ?? dashboard.extendedMetrics.age ?? WikiFileService.getAgeFromWiki()
        let weight = UserProfileSettings.weightKilograms() ?? dashboard.bodyMetrics.weightKilograms
        let height = UserProfileSettings.heightCentimeters() ?? dashboard.extendedMetrics.heightCm
        let sex = UserProfileSettings.biologicalSex() ?? dashboard.extendedMetrics.biologicalSex
        if let age, (10...100).contains(age) { values.append("\(age) 岁") }
        if let weight, (25...350).contains(weight) { values.append(String(format: "%.1f kg", weight)) }
        if let height, (100...250).contains(height) { values.append(String(format: "%.0f cm", height)) }
        if let sex = ["male": "男性", "female": "女性", "other": "其他"][sex ?? ""] { values.append(sex) }
        return values.isEmpty ? "等待 Apple 健康或手动填写" : values.joined(separator: " · ")
    }
    /// 记忆化（审计 H2）：bodyModelState 是 O(n) 组装（含 28 天训练摘要），
    /// 每帧 body 求值重跑会浪费主线程；数据变化时 loadModelData 里置空缓存。
    @State private var memoizedBodyModelState: BodyModelState?
    private var bodyModelState: BodyModelState {
        if let cached = memoizedBodyModelState { return cached }
        let state = BodyModelBuilder().build(
            onboarding: onboarding,
            dailySummaries: dailySummaries,
            journalEntries: journalEntries,
            strengthWorkouts: strengthWorkouts,
            trainingResponses: trainingResponses,
            longTermBaselines: longTermReport,
            asOf: dashboard.date
        )
        memoizedBodyModelState = state
        return state
    }

    /// 详情页自给自足：用自己拉取的三年记录计算长线基准（不依赖 dashboard 缓存状态）。
    @State private var longTermReport: LongTermBaselineReport? = nil
    
    @State private var healthSnapshots: [DailyHealthSnapshot] = []
    @State private var insights: [HabitCorrelationInsight] = []

    private var maturityTitle: String {
        switch bodyModelState.maturity.overall {
        case .seed: "种子期"
        case .learning: "学习期"
        case .stable: "稳定期"
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerCalibrationCard
                staticParametersSection
                physiologicalSection
                behavioralDynamicsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("身体模型")
        .velaRhythmDetailChrome()
        .task(id: selectedDate) {
            await loadModelData()
        }
    }
    
    private var headerCalibrationCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: VelaTheme.radiusSm).fill(VelaTheme.rhythmMist))
            VStack(alignment: .leading, spacing: 5) {
                Text("身体模型校准状态")
                    .font(.system(.callout, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(maturityTitle)
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
        .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous).stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
    }
    
    private var staticParametersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("静态约束与倾向")
                    .font(.system(.footnote, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                Spacer()
                NavigationLink(destination: BodyModelEditView(onRefresh: onRefresh)) {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                        Text("修改设定")
                    }
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
                }
                .buttonStyle(.plain)
            }
            
            VStack(spacing: 0) {
                detailRow(title: "生理特征", value: healthProfileSummary)
                Divider().padding(.leading, 16)
                detailRow(title: "主要健身目标", value: staticGoalText)
                Divider().padding(.leading, 16)
                detailRow(title: "体能训练经验", value: staticExperienceText)
                Divider().padding(.leading, 16)
                detailRow(title: "频次及单次时长", value: staticFrequencyText)
                Divider().padding(.leading, 16)
                detailRow(title: "教练指导风格", value: staticCoachStyleText)
            }
            .background(RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
            .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous).stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
        }
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(.footnote, design: .default))
                .foregroundStyle(VelaTheme.rhythmInk)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private var physiologicalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("生理稳态系统标定 (28天生理基线)")
                .font(.system(.footnote, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("自主神经张力基线 (HRV / 心率变异性)")
                        .font(.system(.footnote, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    BaselineRangeIndicator(
                        today: dashboard.recoveryMetrics.hrvMilliseconds,
                        baseline: dashboard.recoveryBaseline.hrvMilliseconds,
                        unit: " ms"
                    )
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("心脏负荷恢复基线 (RHR / 静息心率)")
                        .font(.system(.footnote, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    BaselineRangeIndicator(
                        today: dashboard.recoveryMetrics.restingHeartRate,
                        baseline: dashboard.recoveryBaseline.restingHeartRate,
                        unit: " bpm"
                    )
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("自主神经呼吸恢复 (Respiratory Rate / 呼吸频率)")
                        .font(.system(.footnote, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    BaselineRangeIndicator(
                        today: dashboard.recoveryMetrics.respiratoryRate,
                        baseline: dashboard.recoveryBaseline.respiratoryRate,
                        unit: " 次/分"
                    )
                }
                
                Divider()
                
                HStack {
                    Text("最大摄氧量标定 (VO2 Max)")
                        .font(.system(.footnote, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Spacer()
                    if let vo2Max = dashboard.bodyMetrics.vo2Max {
                        Text("\(String(format: "%.1f", vo2Max)) mL/kg/min")
                            .font(.system(.footnote, design: .default, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                    } else {
                        Text("暂无数据 (Apple Watch 户外跑/步行校准)")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
            .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous).stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
        }
    }
    
    private var behavioralDynamicsSection: some View {
        JournalCorrelationSection(bodyModelState: bodyModelState, insights: insights)
    }
    
    private func loadModelData() async {
        memoizedBodyModelState = nil
        // Fetches stay on the model context. The three-year aggregate does not.
        self.dailySummaries = (try? SwiftDataDailyHealthSummaryRepository(modelContext: modelContext)
            .fetchAllSortedByDate(newestFirst: true)) ?? []

        self.journalEntries = (try? SwiftDataJournalRepository(modelContext: modelContext)
            .fetchAllSortedByCreatedAt(newestFirst: true)) ?? []
        self.strengthWorkouts = (try? WorkoutHistoryRepository(modelContext: modelContext)
            .fetchStrengthWorkoutsSortedByStart(newestFirst: true)) ?? []

        self.trainingResponses = (try? TrainingResponseRepository(modelContext: modelContext)
            .fetchAllSortedByDate()) ?? []

        let repo = HealthSnapshotRepository(modelContext: modelContext)
        if let snaps = try? repo.fetchSnapshots(days: 1100, endingAt: dashboard.date) {
            self.healthSnapshots = snaps
            let journalsThroughDate = self.journalEntries.filter { $0.createdAt <= dashboard.date }
            let engine = JournalCorrelationEngine()
            let journalInsights = engine.calculateInsights(
                journalEntries: journalsThroughDate,
                snapshots: snaps
            )
            let physiologicalInsights = engine.physiologicalInsights(snapshots: snaps)
            self.insights = journalInsights + physiologicalInsights
        }
        let points = self.dailySummaries.map(\.longTermBaselinePoint)
        let today = dashboard.date
        self.longTermReport = await Task.detached {
            LongTermBaselineEngine.compute(points: points, today: today)
        }.value
    }
    
    private func confidenceColor(_ conf: MetricConfidence) -> Color {
        switch conf {
        case .high: return VelaTheme.success
        case .medium: return VelaTheme.accent
        case .low: return VelaTheme.systemOrange
        }
    }
 
    private func confidenceColor(_ conf: DataConfidence) -> Color {
        switch conf {
        case .high: return VelaTheme.success
        case .medium: return VelaTheme.accent
        case .low: return VelaTheme.systemOrange
        case .unavailable: return VelaTheme.muted
        }
    }
    
    private func displayConfidence(_ conf: String) -> String {
        switch conf.lowercased() {
        case "high": return L10n.t("High", "高")
        case "medium": return L10n.t("Medium", "中")
        case "low": return L10n.t("Low", "低")
        case "unavailable": return L10n.t("Unavailable", "不可用")
        default: return conf
        }
    }
    
    private func displayGoal(_ goal: String) -> String {
        localizedOnboardingGoal(goal)
    }
 
    private func displayExperience(_ level: String) -> String {
        localizedOnboardingExperience(level)
    }
 
    private func displayCoachingStyle(_ style: String) -> String {
        localizedOnboardingCoachStyle(style)
    }
}
