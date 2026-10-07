import SwiftUI
import SwiftData

enum VelaOnboardingStep: Int, CaseIterable {
    case bodyState
    case agentControl
    case appleHealth

    var primaryActionTitle: String {
        switch self {
        case .bodyState: "继续"
        case .agentControl: "连接身体数据"
        case .appleHealth: "连接 Apple 健康"
        }
    }
}

struct VelaOnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var dashboardVM: DashboardViewModel
    @AppStorage("vela_onboarding_completed") private var onboardingCompleted = false
    @State private var authError: String? = nil
    @State private var showingErrorAlert = false
    @State private var missingSignals: [HealthSignal] = []
    @State private var showingMissingAlert = false
    private let primaryGoal = "performance"
    private let trainingStyle = "strength"
    private let weeklyTrainingDays = 5
    private let sessionDurationMinutes = 60
    private let experienceLevel = "intermediate"
    private let coachStyle = "direct"
    @State private var currentStep = VelaOnboardingStep.bodyState
    @State private var isMovingForward = true

    @Query(sort: \OnboardingState.updatedAt, order: .reverse)
    private var onboardingStates: [OnboardingState]

    init(initialStep: VelaOnboardingStep = .bodyState) {
        _currentStep = State(initialValue: initialStep)
    }

    var body: some View {
        ZStack {
            VelaTheme.rhythmCanvas.ignoresSafeArea()

            VStack(spacing: 0) {
                onboardingHeader

                ScrollView {
                    Group {
                        switch currentStep {
                        case .bodyState: welcomeStep
                        case .agentControl: agentControlStep
                        case .appleHealth: healthStep
                        }
                    }
                    .id(currentStep.rawValue)
                    .transition(stepTransition)
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 150)
                }
                .scrollIndicators(.hidden)
            }
        }
        .safeAreaInset(edge: .bottom) {
            ctaButtons
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(.ultraThinMaterial)
        }
        .alert(isPresented: $showingErrorAlert) {
            Alert(
                title: Text(L10n.t("Unable to Authorize Apple Health", "无法授权 Apple 健康")),
                message: Text(authError ?? L10n.t("Vela requires Health permissions to analyze your wellness indices.", "Vela 需要健康权限来分析您的生理与运动数据。")),
                dismissButton: .default(Text(L10n.t("OK", "好的")))
            )
        }
        .alert(isPresented: $showingMissingAlert) {
            let names = missingSignals.map { $0.name }.joined(separator: ", ")
            return Alert(
                title: Text(L10n.t("Missing Core Permissions", "部分核心权限未开启")),
                message: Text(L10n.t(
                    "We noticed the following core permissions are missing: \(names).\n\nYou can enable them in iOS Settings > Health > Data Access & Devices > Vela to unlock full insights.",
                    "检测到以下核心权限未开启：\(names)。\n\n您可以在系统“设置 > 健康 > 数据与设备 > Vela”中开启它们，以获得完整的健康洞察。"
                )),
                primaryButton: .default(Text(L10n.t("Retry Check", "重新检查")), action: {
                    Task { await retryMissingSignalCheck() }
                }),
                secondaryButton: .cancel(Text(L10n.t("Proceed Anyway", "仍然继续")), action: {
                    finishOnboarding(missingSignals: missingSignals)
                })
            )
        }
    }

    private var onboardingHeader: some View {
        HStack(spacing: 10) {
            BodySeekBrandMark(
                size: 24,
                showWordmark: true,
                monochrome: true
            )

            Spacer()

            Text("\(currentStep.rawValue + 1) / \(VelaOnboardingStep.allCases.count)")
                .font(VelaTheme.caption1().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("See your body before judging your willpower.", "先看见身体，再决定今天。"))
                    .font(.system(.largeTitle, design: .default, weight: .semibold))
                    .tracking(-1.1)
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.t(
                    "Five independent scores place Apple Health signals against your personal baseline.",
                    "五项独立分数，把 Apple 健康信号放回你的个人基线中。"
                ))
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .lineSpacing(4)
            }

            scorePreviewCard
        }
    }

    private var agentControlStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Agent 解释，你做决定。")
                    .font(.system(.title, design: .default, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text("分数先在本机计算；联网 Agent 只接收你允许的类别。")
                    .font(VelaTheme.body())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineSpacing(3)
            }

            VStack(spacing: 0) {
                agentControlRow(
                    icon: "waveform.path.ecg",
                    title: "解释身体状态",
                    detail: "结合分数、趋势与相关身体数据回答追问"
                )
                Divider().padding(.leading, 58)
                agentControlRow(
                    icon: "calendar.badge.clock",
                    title: "提出计划调整",
                    detail: "默认有计划；Agent 的更改先交给你确认"
                )
                Divider().padding(.leading, 58)
                agentControlRow(
                    icon: "brain.head.profile",
                    title: "沉淀长期记忆",
                    detail: "观察可以被复核、修改或删除"
                )
            }
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(VelaTheme.rhythmMist.opacity(0.8), lineWidth: 0.75)
            }

            HStack(spacing: 10) {
                trustPill(icon: "iphone", title: "分数在本机")
                trustPill(icon: "hand.raised.fill", title: "写入先确认")
            }
        }
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("连接 Apple 健康")
                    .font(.system(.title, design: .default, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text("允许读取的信号会在本机形成五项分数和你的个人基线。")
                    .font(VelaTheme.body())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineSpacing(4)
            }

            VStack(spacing: 0) {
                permissionRow(icon: "bed.double.fill", title: "睡眠", detail: "睡眠时长、阶段与规律")
                Divider().padding(.leading, 52)
                permissionRow(icon: "heart.fill", title: "恢复与压力", detail: "HRV、静息心率与呼吸信号")
                Divider().padding(.leading, 52)
                permissionRow(icon: "figure.run", title: "负荷与能量", detail: "活动、训练与能量消耗")
            }
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(VelaTheme.rhythmMist.opacity(0.8), lineWidth: 0.75)
            )

            VStack(alignment: .leading, spacing: 10) {
                Label("只读 Apple 健康，不会写入或修改原始记录", systemImage: "eye.fill")
                Label("Apple 健康权限与联网 Agent 权限分开管理", systemImage: "slider.horizontal.3")
            }
            .font(VelaTheme.footnote().weight(.medium))
            .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
    }

    private var scorePreviewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("你的每日身体状态")
                    .font(VelaTheme.headline())
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Text("示例")
                    .font(VelaTheme.caption2().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(VelaTheme.rhythmMist.opacity(0.7), in: Capsule())
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    compactScoreRow(label: "恢复", score: 62, domain: .recovery)
                    compactScoreRow(label: "睡眠", score: 74, domain: .sleep)
                    compactScoreRow(label: "负荷", score: 41, domain: .strain)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    previewScore(label: "恢复", score: 62, domain: .recovery)
                    previewScore(label: "睡眠", score: 74, domain: .sleep)
                    previewScore(label: "负荷", score: 41, domain: .strain)
                }
            }

            HStack(spacing: 12) {
                previewBar(label: "压力", value: 37, domain: .stress)
                previewBar(label: "能量", value: 68, domain: .energy)
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
                Text("恢复低于近期基线，睡眠不足是主要影响。")
                    .font(VelaTheme.footnote())
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(VelaTheme.rhythmMist.opacity(0.8), lineWidth: 0.75)
        }
        .accessibilityElement(children: .contain)
    }

    private func previewScore(label: String, score: Double, domain: VelaMetricDomain) -> some View {
        VelaMetricScoreRing(score: score, label: label, domain: domain, size: 78)
            .frame(maxWidth: .infinity)
    }

    private func compactScoreRow(label: String, score: Double, domain: VelaMetricDomain) -> some View {
        HStack(spacing: 12) {
            VelaMetricScoreRing(score: score, label: "", domain: domain, size: 52, showsLabel: false)
            Text(label)
                .font(VelaTheme.body().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
            Spacer()
            Text("示例分数 \(Int(score))")
                .font(VelaTheme.caption1())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
    }

    private func previewBar(label: String, value: Double, domain: VelaMetricDomain) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(VelaTheme.caption1().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                Spacer()
                Text("\(Int(value))")
                    .font(VelaTheme.headline())
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(VelaTheme.rhythmMist)
                    Capsule()
                        .fill(domain.color)
                        .frame(width: proxy.size.width * CGFloat(value / 100))
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)，示例分数 \(Int(value))")
    }

    private func agentControlRow(icon: String, title: String, detail: String) -> some View {
        onboardingValueRow(icon: icon, title: title, detail: detail)
            .frame(minHeight: VelaTheme.minimumHitTarget)
    }

    private func trustPill(icon: String, title: String) -> some View {
        Label(title, systemImage: icon)
            .font(VelaTheme.caption1().weight(.semibold))
            .foregroundStyle(VelaTheme.rhythmInk)
            .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget)
            .background(VelaTheme.rhythmMist.opacity(0.56), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func onboardingValueRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .frame(width: 38, height: 38)
                .background(VelaTheme.rhythmMist.opacity(0.68), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(VelaTheme.headline()).foregroundStyle(VelaTheme.rhythmInk)
                Text(detail).font(VelaTheme.footnote()).foregroundStyle(VelaTheme.rhythmInkSecondary).lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func permissionRow(icon: String, title: String, detail: String) -> some View {
        onboardingValueRow(icon: icon, title: title, detail: detail)
    }

    private var ctaButtons: some View {
        VStack(spacing: 12) {
            Button(action: primaryOnboardingAction) {
                Text(primaryButtonTitle)
                    .font(VelaTheme.headline())
                    .foregroundStyle(VelaTheme.rhythmDeepOn)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VelaTheme.rhythmDeep))
            }
            .buttonStyle(.cardPress)

            if currentStep != .bodyState {
                Button {
                    if currentStep == .appleHealth {
                        Task { await finishOnboardingSkippingHealth() }
                    } else if let previousStep = VelaOnboardingStep(rawValue: currentStep.rawValue - 1) {
                        isMovingForward = false
                        withAnimation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion)) {
                            currentStep = previousStep
                        }
                    }
                } label: {
                    Text(currentStep == .appleHealth ? "稍后连接" : "返回")
                        .font(VelaTheme.subheadline().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.cardPress)
            }
        }
    }

    private var primaryButtonTitle: String {
        currentStep.primaryActionTitle
    }

    private func primaryOnboardingAction() {
        if currentStep != .appleHealth,
           let nextStep = VelaOnboardingStep(rawValue: currentStep.rawValue + 1) {
            isMovingForward = true
            withAnimation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion)) {
                currentStep = nextStep
            }
        } else {
            Task { await connectHealthAndFinish() }
        }
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertionEdge: Edge = isMovingForward ? .trailing : .leading
        let removalEdge: Edge = isMovingForward ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private func connectHealthAndFinish() async {
        do {
            try await HealthAuthorizationService().requestAuthorization(tier: .core)
            let coverageService = HealthSignalCoverageService()
            var missing: [HealthSignal] = []
            for signal in [HealthSignal.hrvSDNN, .restingHR, .sleepAnalysis, .workouts, .activeEnergy, .stepCount] {
                let cov = await coverageService.fetchCoverage(for: signal)
                if cov.authorizationState == .unavailable
                    || cov.authorizationState == .notRequested
                    || cov.authorizationState == .denied {
                    missing.append(signal)
                }
            }
            if missing.isEmpty {
                finishOnboarding(missingSignals: [])
            } else {
                _ = saveOnboardingState(missingSignals: missing, completed: false)
                missingSignals = missing
                showingMissingAlert = true
            }
        } catch {
            authError = error.localizedDescription
            showingErrorAlert = true
        }
    }

    private func retryMissingSignalCheck() async {
        let coverageService = HealthSignalCoverageService()
        var missing: [HealthSignal] = []
        for signal in [HealthSignal.hrvSDNN, .restingHR, .sleepAnalysis, .workouts, .activeEnergy, .stepCount] {
            let cov = await coverageService.fetchCoverage(for: signal)
            if cov.authorizationState == .unavailable
                || cov.authorizationState == .notRequested
                || cov.authorizationState == .denied {
                missing.append(signal)
            }
        }
        if missing.isEmpty {
            finishOnboarding(missingSignals: [])
        } else {
            _ = saveOnboardingState(missingSignals: missing, completed: false)
            missingSignals = missing
            showingMissingAlert = true
        }
    }

    /// 「稍后连接」：不请求授权，但真实记录缺失信号（此前 missingData=[]，
    /// Me 页「待补充健康指标」永不出现，且无重进 onboarding 的入口）。
    private func finishOnboardingSkippingHealth() async {
        let coverageService = HealthSignalCoverageService()
        var missing: [HealthSignal] = []
        for signal in [HealthSignal.hrvSDNN, .restingHR, .sleepAnalysis, .workouts, .activeEnergy, .stepCount] {
            let cov = await coverageService.fetchCoverage(for: signal)
            if cov.authorizationState == .unavailable
                || cov.authorizationState == .notRequested
                || cov.authorizationState == .denied {
                missing.append(signal)
            }
        }
        finishOnboarding(missingSignals: missing)
    }

    private func finishOnboarding(missingSignals: [HealthSignal]) {
        guard saveOnboardingState(missingSignals: missingSignals, completed: true) else { return }
        onboardingCompleted = true
        VelaAppState.shared.markLocalDataChanged()
        // 建档资料落盘 wiki：Coach 页健康档案不再显示空模板。
        WikiProfileMaterializer.materializeIfNeeded(modelContext: modelContext)
        Task {
            await dashboardVM.refresh(modelContext: modelContext, force: true)
        }
    }

    private func saveOnboardingState(missingSignals: [HealthSignal], completed: Bool) -> Bool {
        let state = onboardingStates.first ?? OnboardingState()
        state.currentStep = completed ? "completed" : "health_permissions"
        state.isCompleted = completed
        state.completedAt = completed ? Date() : nil
        state.goalProfile = UserGoalProfile(
            primaryGoal: primaryGoal,
            // 训练风格属于 trainingPreference，不应混入「次要目标」。
            secondaryGoals: [],
            experienceLevel: experienceLevel,
            bodyConcerns: []
        )
        state.trainingPreference = TrainingPreferenceProfile(
            trainingStyle: trainingStyle,
            weeklyTrainingDays: weeklyTrainingDays,
            sessionDurationMinutes: sessionDurationMinutes,
            preferredTrainingDays: [],
            rotationFocuses: TrainingRotationResolver.defaultFocuses,
            nextRotationFocus: TrainingRotationResolver.defaultFocuses.first
        )
        state.equipmentProfile = EquipmentProfile(
            equipment: selectedEquipment,
            scheduleNotes: "\(weeklyTrainingDays)x weekly, \(sessionDurationMinutes)m sessions"
        )
        state.coachingPreference = CoachingPreference(
            style: coachStyle,
            explanationDepth: coachStyle == "explanatory" ? "detailed" : "balanced",
            language: "zh-Hans"
        )
        state.initialBodySnapshot = InitialBodySnapshot(
            sleepScore: dashboardVM.dashboard.sleepScore.hasData ? dashboardVM.dashboard.sleepScore.score : nil,
            recoveryScore: dashboardVM.dashboard.recovery.hasData ? dashboardVM.dashboard.recovery.score : nil,
            strainScore: dashboardVM.dashboard.strain.hasData ? dashboardVM.dashboard.strain.score : nil,
            dataConfidence: dataConfidence(from: dashboardVM.dashboard.recovery.confidence),
            missingData: missingSignals.map(\.name)
        )
        state.missingData = missingSignals.map(\.name)
        state.firstBrief = localizedOnboardingFirstBrief(
            primaryGoal: primaryGoal,
            trainingStyle: trainingStyle,
            weeklyTrainingDays: weeklyTrainingDays
        )
        state.firstActionPlan = [
            "完成 Apple 健康授权并建立 HRV/睡眠/负荷基线。",
            "训练时继续使用 Apple Watch；结束后可选填主观感受，动作、重量与组数始终可跳过。",
            "在今日查看行动边界，在 Coach 解释或确认任何计划变化。"
        ]
        state.updatedAt = Date()
        if onboardingStates.isEmpty {
            modelContext.insert(state)
        }
        do {
            try modelContext.save()
            return true
        } catch {
            authError = "无法保存身体模型，请稍后重试。"
            showingErrorAlert = true
            return false
        }
    }

    private var selectedEquipment: [String] {
        ["gym", "home_equipment", "bodyweight"]
    }

    private func dataConfidence(from confidence: MetricConfidence) -> DataConfidence {
        switch confidence {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }

}
