import SwiftUI
import SwiftData
import Combine

// MARK: - VelaTrainingView
// The phone decides and explains. Apple Watch records the training itself.

struct VelaTrainingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.velaSurfaceIsActive) private var isActiveSurface
    @Environment(\.colorScheme) private var cs
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dashboardVM: DashboardViewModel
    @EnvironmentObject private var services: VelaServices
    @ObservedObject private var appState = VelaAppState.shared

    @Query(sort: \OnboardingState.updatedAt, order: .reverse)
    private var onboardingStates: [OnboardingState]

    private static let lookbackDays = 90
    private var trainingLookbackStart: Date {
        Calendar.current.date(byAdding: .day, value: -Self.lookbackDays, to: dashboardVM.selectedDate) ?? dashboardVM.selectedDate
    }

    @State private var strengthWorkouts: [StrengthWorkoutRecord] = []
    /// 页面展示/合并用的近 90 天训练事件。
    @State private var localWorkoutEvents: [WorkoutEventRecord] = []
    /// 计划解析专用事件：覆盖活跃计划开始以来的全部完成记录。
    @State private var planResolutionEvents: [WorkoutEventRecord] = []
    @State private var workoutTemplates: [WorkoutTemplateRecord] = []
    @State private var trainingPlans: [TrainingPlanRecord] = []
    @State private var operatingPlans: [DailyOperatingPlanRecord] = []
    @State private var trainingResponses: [TrainingResponseRecord] = []
    /// 活跃计划未来训练日中待确认的调整提案（本机 BodyInterpreter / AI 练后边界共用）。
    @State private var pendingPlanAdaptations: [TrainingPlanAdaptationRecord] = []

    private var dashboard: DashboardSummary { dashboardVM.dashboard }
    private var activePlan: TrainingPlanRecord? {
        trainingPlans.first(where: { $0.isActive })
    }
    private var trainingPreference: TrainingPreferenceProfile? {
        onboardingStates.first?.trainingPreference
    }
    private var rotationFocus: String? {
        guard activePlan == nil else { return nil }
        return TrainingRotationResolver.nextFocus(
            profile: trainingPreference,
            recentResponses: trainingResponses.map(\.dto)
        )
    }
    private var todayPlan: DailyOperatingPlanRecord? {
        let identifier = DailyHealthSummaryRecord.dayIdentifier(for: dashboardVM.selectedDate)
        return operatingPlans.first(where: { $0.dayIdentifier == identifier })
    }
    private var todaySession: TrainingDay? {
        guard let activePlan else { return nil }
        return TrainingScheduleResolver.resolve(
            plan: activePlan.dto,
            on: dashboardVM.selectedDate,
            events: planResolutionEvents.map { $0.dto }
        )
    }
    private var todayDecision: DailyTrainingDecision? {
        dashboardVM.dailyTrainingDecision ?? todayPlan?.trainingDecision
    }

    @State private var previousMonthActiveTiers: [Int: Int] = [:]
    @State private var currentMonthActiveTiers: [Int: Int] = [:]

    // Dynamic states for statistics & trend graphs
    @State private var totalWorkoutDurationText = "--"
    @State private var summaryPeakStrainText = "--"
    @State private var summaryWorkPathPoints: [CGPoint] = []
    @State private var summaryWorkValues: [Double] = []
    @State private var summaryWorkDates: [Date] = []
    @State private var exertionValues: [Double] = []
    @State private var exertionDates: [Date] = []
    @State private var dynamicExertionWorkload: [Double] = []
    @State private var targetComparison: TrainingTargetComparison = .unavailable
    /// 训练节律热力图的每日快照记录（约 6 周窗口）。
    @State private var heatmapRecords: [DailyHealthSummaryRecord] = []
    /// 热力图周数据缓存：数据加载后计算一次，body 重渲染不再重复聚合。
    @State private var memoHeatmapWeeks: [TrainingHeatmapWeek] = []
    /// Coach 参与的未来三天规划（nil = 未请求，显示本地推荐）。
    @State private var aiFutureDays: [RotationDayRecommendation]?
    @State private var isPlanningWithAI = false
    @State private var recentWorkouts: [WorkoutSummary] = []
    /// 60 天训练摘要短时缓存：HealthKit 大窗口查询（含全量心率样本）很贵，
    /// 下拉刷新/换日期/本地数据变化连续触发时 60 秒内复用，避免重复秒级等待。
    @State private var cachedWorkoutSummaries: [WorkoutSummary] = []
    @State private var cachedWorkoutSummariesAt: Date?
    @State private var cachedWorkoutSummariesAnchor: Date?
    /// 随 loadDynamicData 一次性算好的近 7 天训练摘要、个人纪录与肌群逐日组数
    /// （此前每次 body 重渲染都 O(n²) 重算，刷新后主线程被拖住）。
    @State private var memoStrengthSummary: RecentTrainingSummary?
    @State private var memoPersonalRecords: [PersonalRecord] = []
    @State private var memoMuscleDailySets: [String: [Int]] = [:]
    @State private var memoCardioSnapshot: CardioTrainingSnapshot?
    /// 三年历史基线（回填后可用；给 AI 规划上下文的长线参照）。
    @State private var memoLongTermRHRMedian: Double?
    @State private var memoLongTermHRVMedian: Double?
    /// 长线基线按「浏览日 + 本地数据版本」懒加载，避免每次进入训练页都全表抓 1100 天快照。
    @State private var longTermMediansCacheKey: String?
    @State private var selectedAnalyticsTab = 0
    @State private var handledAdaptiveTrainingStartRequest = 0

    var body: some View {
        let strengthSummary = recentStrengthSummary
        let cardioSnapshot = memoCardioSnapshot ?? CardioTrainingAnalyzer.analyze(
            workouts: recentWorkouts,
            endingAt: dashboardVM.selectedDate
        )
        let hero = TrainingHeroSection(
            todaySession: todaySession,
            todayPlan: todayPlan,
            dailyDecision: todayDecision,
            activePlan: activePlan,
            rotationFocus: rotationFocus,
            preferredSessionMinutes: trainingPreference?.sessionDurationMinutes ?? 60,
            summary: strengthSummary,
            evidenceMetrics: trainingEvidenceMetrics,
            heatmapWeeks: heatmapWeeks,
            futureRecommendations: rotationFutureDays,
            aiFutureDays: aiFutureDays,
            isPlanningWithAI: isPlanningWithAI,
            personalInsight: dashboardVM.dashboard.bodyModelState?.insightLine(),
            onRequestAIPlan: { Task { await requestAIPlan() } },
            onDiscussWithCoach: {
                VelaAppState.shared.routeToCoach(question: trainingAnalysisQuestion, surface: .training)
            }
        )

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                hero

                VStack(alignment: .leading, spacing: 24) {
                    if let workout = postWorkoutPromptWorkout {
                        TrainingPostWorkoutPrompt(workout: workout) {
                            appState.routeToPostWorkoutCheckIn(
                                workoutID: strengthWorkout(for: workout)?.id ?? workout.id
                            )
                        }
                    }

                    hero.futureRecommendationStrip

                    syncedWorkoutsSection

                    TrainingMuscleLandscape(
                        summary: strengthSummary,
                        muscleDailySets: memoMuscleDailySets,
                        endingAt: dashboardVM.selectedDate
                    )

                    hero.rhythmDisclosure

                    if !pendingPlanAdaptations.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            VelaRhythmSectionHeader(
                                eyebrow: "",
                                title: "计划调整建议",
                                actionTitle: nil,
                                action: {}
                            )

                            NavigationLink {
                                VelaTrainingRotationView()
                            } label: {
                                TrainingProposalPortal(proposals: pendingPlanAdaptations)
                            }
                            .buttonStyle(.cardPress)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        VelaRhythmSectionHeader(
                            eyebrow: "",
                            title: "计划与轮转",
                            actionTitle: nil,
                            action: {}
                        )

                        NavigationLink {
                            VelaTrainingRotationView()
                        } label: {
                            TrainingPlanPortal(
                                planTitle: activePlan?.title,
                                nextFocus: todaySession?.title,
                                completedDays: activePlan?.days.filter(\.isCompleted).count ?? 0,
                                totalDays: activePlan?.days.count ?? 0,
                                days: activePlan?.days ?? [],
                                todayTitle: todaySession?.title,
                                pendingProposalCount: pendingPlanAdaptations.count
                            )
                        }
                        .buttonStyle(.cardPress)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        VelaRhythmSectionHeader(
                            eyebrow: "",
                            title: "趋势与记录",
                            actionTitle: nil,
                            action: {}
                        )

                        NavigationLink {
                            deepAnalysisDestination(strengthSummary: strengthSummary, cardioSnapshot: cardioSnapshot)
                        } label: {
                            TrainingAnalysisPortal(
                                sessions: strengthSummary.sessions,
                                totalDuration: totalWorkoutDurationText,
                                cardioStatus: cardioSnapshot.status?.title ?? (cardioSnapshot.acuteMinutes > 0 ? "已记录" : "待建立"),
                                sparkline: summaryWorkPathPoints,
                                prCount: personalRecords.count
                            )
                        }
                        .buttonStyle(.cardPress)
                    }
                }
                .padding(.horizontal, VelaTheme.pagePadding)
                .padding(.bottom, VelaFloatingNavigationMetrics.contentBottomPadding)
            }
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top) {
            fitnessHeader
                .padding(.horizontal, VelaTheme.pagePadding)
                .padding(.vertical, 10)
                .background(VelaTheme.rhythmCanvas.opacity(0.94))
        }
        .background(VelaTheme.rhythmCanvas)
        .task(id: isActiveSurface) {
            guard isActiveSurface else { return }
            loadRealFitnessData()
            consumeAdaptiveTrainingStartIfNeeded()
            await syncRealFitnessData()
        }
        .refreshable {
            await syncRealFitnessData(force: true)
        }
        .onChange(of: dashboardVM.selectedDate) { _, _ in
            guard isActiveSurface else { return }
            aiFutureDays = nil
            loadRealFitnessData()
            Task {
                await syncRealFitnessData()
            }
        }
        .onChange(of: appState.localDataRevision) { _, _ in
            guard isActiveSurface else { return }
            aiFutureDays = nil
            loadRealFitnessData()
            Task {
                await syncRealFitnessData()
            }
        }
        .onChange(of: appState.adaptiveTrainingStartRequest) { _, _ in
            consumeAdaptiveTrainingStartIfNeeded()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func deepAnalysisDestination(
        strengthSummary: RecentTrainingSummary,
        cardioSnapshot: CardioTrainingSnapshot
    ) -> some View {
        TrainingDeepAnalysisView(
            selectedAnalyticsTab: $selectedAnalyticsTab,
            targetComparison: targetComparison,
            dynamicExertionWorkload: dynamicExertionWorkload,
            exertionValues: exertionValues,
            exertionDates: exertionDates,
            totalWorkoutDurationText: totalWorkoutDurationText,
            summaryWorkPathPoints: summaryWorkPathPoints,
            summaryWorkValues: summaryWorkValues,
            summaryWorkDates: summaryWorkDates,
            summaryPeakStrainText: summaryPeakStrainText,
            selectedDate: dashboardVM.selectedDate,
            previousMonthActiveTiers: previousMonthActiveTiers,
            currentMonthActiveTiers: currentMonthActiveTiers,
            cardioSnapshot: cardioSnapshot,
            recentWorkouts: recentWorkouts,
            strengthSummary: strengthSummary,
            exerciseProgressLines: exerciseProgressLines,
            personalRecords: personalRecords,
            metricRecords: recentMetricRecords,
            strengthWorkout: { workout in self.strengthWorkout(for: workout) }
        )
    }

    // MARK: - Synced Workouts Section
    private var syncedWorkoutsSection: some View {
        let strengthSummary = recentStrengthSummary
        let cardioSnapshot = memoCardioSnapshot ?? CardioTrainingAnalyzer.analyze(
            workouts: recentWorkouts,
            endingAt: dashboardVM.selectedDate
        )
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("运动记录与复盘")
                    .font(VelaTheme.headline())
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                if !recentWorkouts.isEmpty {
                    NavigationLink {
                        deepAnalysisDestination(strengthSummary: strengthSummary, cardioSnapshot: cardioSnapshot)
                    } label: {
                        HStack(spacing: 2) {
                            Text("全部记录")
                            Image(systemName: "chevron.right")
                        }
                        .font(VelaTheme.caption1().weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if recentWorkouts.isEmpty {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(VelaTheme.rhythmDeep.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "applewatch")
                            .accessibilityHidden(true)
                            .font(.system(.title3, design: .default, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apple Watch 自动同步")
                            .font(.system(.footnote, design: .default, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Text("手表记录运动完成后，将在此自动生成生理负荷与心率区间复盘。")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(16)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(recentWorkouts.prefix(3))) { workout in
                        NavigationLink {
                            if let strength = strengthWorkout(for: workout) {
                                StrengthWorkoutDetailView(workout: strength)
                            } else {
                                WorkoutDetailView(workout: workout)
                            }
                        } label: {
                            workoutRow(workout)
                        }
                        .buttonStyle(.cardPress)
                    }
                }
            }
        }
    }

    private func workoutRow(_ workout: WorkoutSummary) -> some View {
        let durationMinutes = max(1, Int(workout.end.timeIntervalSince(workout.start) / 60))
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(VelaTheme.rhythmDeep.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: workoutIcon(for: workout.activityName))
                .accessibilityHidden(true)
                    .font(.system(.body, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(workout.activityName)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)

                Text(workoutTimeSubtitle(workout))
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(durationMinutes) 分钟")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                if let energy = workout.energyKilocalories, energy > 0 {
                    Text("\(Int(energy)) kcal")
                        .font(.system(.caption2, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
            }

            Image(systemName: "chevron.right")
                .accessibilityHidden(true)
                .font(.system(.caption2, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.5))
        }
        .padding(14)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        )
    }

    private func workoutIcon(for activity: String) -> String {
        if activity.contains("跑") || activity.lowercased().contains("run") {
            return "figure.run"
        } else if activity.contains("力量") || activity.contains("举重") || activity.lowercased().contains("strength") {
            return "figure.strengthtraining.traditional"
        } else if activity.contains("骑") || activity.lowercased().contains("cycl") {
            return "figure.outdoor.cycle"
        } else if activity.contains("游") || activity.lowercased().contains("swim") {
            return "figure.pool.swim"
        } else if activity.contains("高强度") || activity.lowercased().contains("hiit") {
            return "figure.highintensity.intervaltraining"
        } else if activity.contains("走") || activity.lowercased().contains("walk") {
            return "figure.walk"
        }
        return "figure.mixed.cardio"
    }

    private func workoutTimeSubtitle(_ workout: WorkoutSummary) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: workout.start)
    }

    // MARK: - Training Title Header
    private var fitnessHeader: some View {
        HStack {
            Text("训练")
                .font(.system(.title2, design: .default, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(VelaTheme.rhythmInk)

            Spacer()

            Button {
                VelaAppState.shared.routeToCoach(question: trainingAnalysisQuestion, surface: .training)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                    Text("问 Vela")
                        .font(.system(.footnote, design: .default, weight: .semibold))
                }
                .foregroundStyle(VelaTheme.rhythmDeep)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(VelaTheme.rhythmDeep.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("让 Coach 分析训练")
        }
    }

    private var postWorkoutPromptWorkout: WorkoutSummary? {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dashboardVM.selectedDate))
            ?? dashboardVM.selectedDate
        let start = end.addingTimeInterval(-36 * 60 * 60)
        let responseWorkoutIDs = Set(trainingResponses.map(\.workoutId))
        let annotatedWorkoutIDs = Set(localWorkoutEvents.compactMap { event -> UUID? in
            if responseWorkoutIDs.contains(event.id) { return event.id }
            if let strengthID = event.linkedStrengthWorkoutId,
               responseWorkoutIDs.contains(strengthID) {
                return event.id
            }
            return nil
        }).union(responseWorkoutIDs)
        return recentWorkouts.first {
            $0.start >= start && $0.start < end && !annotatedWorkoutIDs.contains($0.id)
        }
    }

    // MARK: - Double-Month Activity Heatmap Card
    // Combined into performanceAnalyticsCard

    // Individual Month Heatmap builder


    private var trainingAnalysisQuestion: String {
        let dashboard = dashboardVM.dashboard
        let recovery = dashboard.recovery.hasData ? "\(Int(dashboard.recovery.score.rounded()))" : "--"
        let strain = dashboard.strain.hasData ? "\(Int(dashboard.strain.score.rounded()))" : "--"
        let stress = dashboard.stress.hasData ? "\(Int(dashboard.stress.stressIndex.rounded()))" : "--"
        let decisionText = todayDecision.map {
            switch $0.decision {
            case .keep: "保持"
            case .reduce: "减量"
            case .swap: "换部位"
            case .rest: "恢复"
            }
        } ?? "待定"
        return "请结合过去 30 天训练记录、恢复 \(recovery)、负荷 \(strain)、压力 \(stress)、局部肌群疲劳、身体模型与健康档案，复核本机今日决策（\(decisionText)）并给出下一次训练建议。"
    }

    /// 剂量环「为什么」的证据指标（真实评分，缺失时不伪造）。
    /// 联通专项批次 1：证据锚点改为「恢复 + 负荷 + 动态第三槽」——
    /// 把触发的隐性门控（压力>75 / TSB≤-15 / 能量<30）抬进证据层，
    /// 与 kernel 门控同阈值同源（TrainingDecision.swift），最多 3 个锚点。
    private var trainingEvidenceMetrics: [String] {
        let dashboard = dashboardVM.dashboard
        var metrics: [String] = []
        if dashboard.recovery.hasData {
            metrics.append("恢复 \(Int(dashboard.recovery.score.rounded()))")
        }
        if dashboard.strain.hasData {
            let range = dashboard.strain.recommendedRange
            metrics.append("负荷 \(Int(dashboard.strain.score.rounded()))（目标 \(range.lowerBound)-\(range.upperBound)）")
        }
        if dashboard.stress.hasData, dashboard.stress.stressIndex > 75 {
            metrics.append("压力 \(Int(dashboard.stress.stressIndex.rounded()))（>75）")
        } else if let tsb = dashboard.energy.metrics["tsb"], tsb <= -15 {
            metrics.append("TSB \(String(format: "%+.0f", tsb))（深度为负）")
        } else if dashboard.energy.hasData, dashboard.energy.currentEnergy < 30 {
            metrics.append("能量 \(Int(dashboard.energy.currentEnergy.rounded()))（偏低）")
        } else if dashboard.sleepScore.hasData {
            metrics.append("睡眠 \(Int(dashboard.sleepScore.score.rounded()))")
        }
        return metrics
    }

    /// 训练节律日历热力图（最近 5 周，周一起始；力量肌群 + 有氧分钟 + 强度分档）。
    /// 训练类型数据源用 SwiftData 事件（同步即用，含 HealthKit 镜像）——
    /// 此前用异步 recentWorkouts，同步完成前点击格子恒显示「休息」。
    private var heatmapWeeks: [TrainingHeatmapWeek] {
        if !memoHeatmapWeeks.isEmpty { return memoHeatmapWeeks }
        return makeHeatmapWeeks()
    }

    private func makeHeatmapWeeks() -> [TrainingHeatmapWeek] {
        TrainingHeatmapData.weeks(
            endingAt: dashboardVM.selectedDate,
            weeks: 5,
            records: heatmapRecords,
            workouts: strengthWorkouts,
            summaries: localWorkoutEvents.map {
                WorkoutSummary(
                    id: $0.id,
                    start: $0.startedAt,
                    end: $0.endedAt,
                    activityName: $0.activityType,
                    energyKilocalories: $0.energyKilocalories,
                    averageHeartRate: $0.averageHeartRate,
                    source: $0.source,
                    rpe: $0.rpe
                )
            }
        )
    }

    /// 趋势卡使用的最近 30 天每日快照（恢复 / 负荷 / 压力同窗口、同源）。
    /// 热力图加载时已经取到 42 天窗口，这里只做内存过滤，不额外查询 SwiftData。
    private var recentMetricRecords: [DailyHealthSummaryRecord] {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dashboardVM.selectedDate))
            ?? dashboardVM.selectedDate
        let start = calendar.date(byAdding: .day, value: -30, to: end) ?? end
        return heatmapRecords
            .filter { $0.date >= start && $0.date < end }
            .sorted { $0.date < $1.date }
    }

    /// 未来 2 天最佳训练部位（肌群疲劳 + 恢复状态 + 轮转交替；今天卡由今日决策驱动）。
    private var rotationFutureDays: [RotationDayRecommendation] {
        TrainingRotationRecommender.upcomingDays(
            localFatigue: recentStrengthSummary.localFatigue,
            decision: todayPlan?.operatingPlanPayload?.decision ?? .keep,
            recoveryScore: dashboardVM.dashboard.recovery.hasData
                ? dashboardVM.dashboard.recovery.score
                : nil,
            rotationFocuses: TrainingRotationResolver.focuses(for: trainingPreference),
            currentFocus: rotationFocus,
            days: 2
        )
    }

    /// 过去 3 天每天练过的肌群（给 AI 上下文的最近训练摘要）。
    private var recentTrainedDays: [(date: Date, groups: [String])] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: dashboardVM.selectedDate)
        let start = calendar.date(byAdding: .day, value: -3, to: end) ?? end
        var groupsByDay: [Date: Set<String>] = [:]
        for workout in strengthWorkouts {
            let day = calendar.startOfDay(for: workout.startedAt)
            guard day >= start, day <= end else { continue }
            let analysis = TrainingAnalyticsService().summarizeWorkout(workout.dto)
            for key in analysis.muscleGroupSets.keys {
                groupsByDay[day, default: []].insert(key)
            }
        }
        var result: [(date: Date, groups: [String])] = []
        for offset in stride(from: 3, through: 1, by: -1) {
            let day = calendar.date(byAdding: .day, value: -offset, to: end) ?? end
            result.append((date: day, groups: groupsByDay[day].map { Array($0) } ?? []))
        }
        return result
    }

    /// 给 Coach 的未来两天规划上下文——联通专项批次 4：改走 AgentFactSnapshot
    /// 共享边界（ADR 0002），健康事实不再手工拼装。
    private var aiPlanContextText: String {
        // 规划上下文必须锚定训练页正在浏览的日期：历史日请求不能把
        // 真实今天之后的训练/手记/报告泄漏进 AI 上下文。
        let asOf = dashboardVM.selectedDate
        let input = AgentFactInputLoader().load(modelContext: modelContext, asOf: asOf)
        let dashboard = dashboardVM.dashboard
        let bodyState = input.bodyState(dashboard: dashboard)
        let snapshot = AIContextBuilder().buildFacts(
            dashboard: dashboard,
            journalEntries: input.journalContext,
            historicalReports: input.reportContext,
            userWiki: WikiFileService.loadPopulatedDictionary(),
            weeklyTrends: input.weeklyTrends,
            foodLogs: input.foodLogs,
            workoutEvents: input.workoutEvents,
            strengthWorkouts: input.strengthWorkouts,
            trainingResponses: input.trainingResponses,
            onboardingState: input.onboardingState,
            bodyModelState: dashboard.bodyModelState,
            bodyState: bodyState,
            trainingDecision: input.canonicalTrainingDecision(for: bodyState),
            dataCoverage: nil,
            scoringContext: dashboard.scoringContext,
            dailyOperatingPlan: AIContextBuilder.compactDailyOperatingPlan(input.dailyOperatingPlan),
            activePlan: input.activePlan?.dto,
            generatedAt: asOf
        ).snapshot
        let recentLines = recentTrainedDays.map { entry in
            let groups = entry.groups.isEmpty ? "休息" : entry.groups.joined(separator: "+")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "M/d"
            return "\(formatter.string(from: entry.date)): \(groups)"
        }
        let localPlan = rotationFutureDays.map {
            "第\($0.dayOffset)天: \($0.groups.isEmpty ? "休息" : $0.groups.joined(separator: "+")) (\($0.note))"
        }
        return AgentFactAdapters.trainingPlanningFacts(
            snapshot: snapshot,
            longTermRHRMedian: memoLongTermRHRMedian,
            longTermHRVMedian: memoLongTermHRVMedian,
            recentTrainedDays: recentLines,
            localPlanLines: localPlan
        )
    }

    /// 让 Coach（DeepSeek）结合数据复核并给出未来三天规划；失败回退本地建议。
    @MainActor
    private func requestAIPlan() async {
        guard AutoAgentConfig.shared.canSendHealthContextToNetworkAI else {
            aiFutureDays = nil
            return
        }
        isPlanningWithAI = true
        aiFutureDays = nil
        defer { isPlanningWithAI = false }
        loadLongTermMediansIfNeeded()
        let apiKey = try? KeychainService.shared.read(account: "deepseek_api_key")
        do {
            let plan = try await TrainingPlanAdvisor.suggestNextDays(
                contextText: aiPlanContextText,
                apiKey: apiKey
            )
            aiFutureDays = plan.isEmpty ? nil : plan
        } catch {
            // 失败保持本地建议，不打断页面。
            aiFutureDays = nil
        }
    }

    private var recentStrengthSummary: RecentTrainingSummary {
        if let memoStrengthSummary { return memoStrengthSummary }
        // Anchor to the browsed date, not real-world "today": otherwise browsing a
        // historical date on the Training page still shows real-today muscle volume,
        // PRs and fatigue.
        return makeStrengthSummary()
    }

    private func makeStrengthSummary() -> RecentTrainingSummary {
        TrainingAnalyticsService().buildRecentSummary(
            workouts: strengthWorkouts.map { $0.dto },
            days: 7,
            endingAt: dashboardVM.selectedDate
        )
    }

    /// 训练窗口内去重后的个人纪录（动作 × 类型保留最高值，附被打破前的值）。
    /// 数据加载时一次性算好（memoPersonalRecords），body 不重算。
    private var personalRecords: [PersonalRecord] {
        memoPersonalRecords
    }

    private func consumeAdaptiveTrainingStartIfNeeded() {
        let request = appState.adaptiveTrainingStartRequest
        guard request > handledAdaptiveTrainingStartRequest else { return }
        handledAdaptiveTrainingStartRequest = request
        loadDynamicData()
        // 训练数据来自 Apple 健康:从训练页/今日页发起的「开始训练」改为与 Coach 讨论。
        VelaAppState.shared.routeToCoach(question: trainingAnalysisQuestion, surface: .training)
    }

    // MARK: - SwiftData and HealthKit loader
    private func syncRealFitnessData(force: Bool = false) async {
        await services.syncCoordinator.run(source: .healthKit, force: force) {
            loadRealFitnessData()
            await dashboardVM.refresh(modelContext: modelContext, force: force)
            loadRealFitnessData()
            // 修复：此前 recentWorkouts(limit: 30) 用无谓词查询只取最新 30 条，
            // 5 周热力图/30 天趋势在训练频繁时会漏掉更早的记录。
            // 改为 60 天日期窗口查询，且锚定浏览日（与热力图/趋势窗口一致，
            // 此前锚定真实今天，浏览历史日期时有氧道/列表漂移）。
            // 60 天 HK 训练摘要（含心率样本聚合）是大查询：同锚定日 60 秒内复用缓存，
            // 下拉刷新/切回训练页不再重复等待秒级拉取。
            let anchorDay = Calendar.current.startOfDay(for: dashboardVM.selectedDate)
            let healthKit: [WorkoutSummary]
            if let cachedAt = cachedWorkoutSummariesAt,
               let cachedAnchor = cachedWorkoutSummariesAnchor,
               cachedAnchor == anchorDay,
               Date().timeIntervalSince(cachedAt) < 60 {
                healthKit = cachedWorkoutSummaries
            } else {
                let fetched = (try? await services.queryService.workoutSummaries(
                    in: DateRangeQuery.recentDays(60, endingAt: dashboardVM.selectedDate, calendar: Calendar.current)
                )) ?? []
                healthKit = fetched
                cachedWorkoutSummaries = fetched
                cachedWorkoutSummariesAt = Date()
                cachedWorkoutSummariesAnchor = anchorDay
            }
            let deletedRecords = (try? modelContext.fetch(FetchDescriptor<DeletedWorkoutRecord>())) ?? []
            let blacklistedIDs = Set(deletedRecords.map(\.id))
            let filteredHealthKit = healthKit.filter { !blacklistedIDs.contains($0.id.uuidString) }

            // P1-2 修复：本地镜像事件也必须按黑名单过滤，
            // 否则「本地已删、HK 仍在」的训练删除后仍显示/计数。
            let local = localWorkoutEvents
                .filter { event in
                    if blacklistedIDs.contains(event.id.uuidString) { return false }
                    if let hkId = event.linkedHealthKitWorkoutId,
                       blacklistedIDs.contains(hkId.uuidString) { return false }
                    return true
                }
                .map {
                    WorkoutSummary(
                        id: $0.id,
                        start: $0.startedAt,
                        end: $0.endedAt,
                        activityName: $0.activityType,
                        energyKilocalories: $0.energyKilocalories,
                        averageHeartRate: $0.averageHeartRate,
                        source: $0.source,
                        rpe: $0.rpe
                    )
                }
            let localIDs = Set(local.map(\.id))
            let representedEventHKIDs = Set(localWorkoutEvents
                .filter { !blacklistedIDs.contains($0.linkedHealthKitWorkoutId?.uuidString ?? "") }
                .compactMap(\.linkedHealthKitWorkoutId))
            recentWorkouts = (filteredHealthKit.filter { !localIDs.contains($0.id) && !representedEventHKIDs.contains($0.id) } + local)
                .sorted { $0.start > $1.start }
            memoCardioSnapshot = CardioTrainingAnalyzer.analyze(
                workouts: recentWorkouts,
                endingAt: dashboardVM.selectedDate
            )
        }
    }

    private func sourceLabel(for source: String?) -> String {
        switch source {
        case "healthKit+xunji":
            return "Apple + 训记"
        case "xunji":
            return "训记"
        case "strengthLog":
            return "力量"
        case "manual":
            return "手动"
        default:
            return "Apple"
        }
    }

    private func strengthWorkout(for workout: WorkoutSummary) -> StrengthWorkoutRecord? {
        if let event = localWorkoutEvents.first(where: { $0.id == workout.id || $0.linkedHealthKitWorkoutId == workout.id }),
           let strengthId = event.linkedStrengthWorkoutId {
            return strengthWorkouts.first(where: { $0.id == strengthId })
        }
        return strengthWorkouts.first(where: { $0.id == workout.id })
    }

    private var exerciseProgressLines: [String] {
        let exercises = strengthWorkouts
            .sorted { $0.startedAt > $1.startedAt }
            .flatMap { workout in workout.exercises.map { (workout.startedAt, $0) } }
        let grouped = Dictionary(grouping: exercises, by: { $0.1.name })
        return grouped.compactMap { name, entries in
            guard let latestDate = entries.map(\.0).max() else { return nil }
            let latest = peakEstimatedOneRepMax(entries.filter { $0.0 == latestDate }.map(\.1))
            let prior = peakEstimatedOneRepMax(entries.filter { $0.0 < latestDate }.map(\.1))
            guard latest > 0 else { return nil }
            if prior > 0 {
                return "\(name)：e1RM \(Int(latest.rounded())) kg（\(String(format: "%+.0f", latest - prior)) kg）"
            }
            return "\(name)：e1RM \(Int(latest.rounded())) kg（建立基线）"
        }.sorted()
    }

    private func peakEstimatedOneRepMax(_ exercises: [StrengthExerciseLog]) -> Double {
        exercises.flatMap(\.sets)
            .filter { !($0.isWarmup) && $0.weightKilograms > 0 && $0.repetitions >= 1 && $0.repetitions <= 12 }
            .map { $0.weightKilograms * (1 + Double($0.repetitions) / 30) }
            .max() ?? 0
    }

    private func loadRealFitnessData() {
        let calendar = Calendar.current
        let now = dashboardVM.selectedDate
        
        let currentMonthStart = monthStart(for: now)
        let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: currentMonthStart) ?? currentMonthStart
        let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: currentMonthStart) ?? now
        
        // 热力图需要 5 周（35 天）+ 余量，取 -42 天兜底（此前 -29 天会让最老一行缺数据）。
        let lowerBound = min(previousMonthStart, calendar.date(byAdding: .day, value: -42, to: now) ?? now)
        let upperBound = nextMonthStart
        let descriptor = FetchDescriptor<DailyHealthSummaryRecord>(
            predicate: #Predicate<DailyHealthSummaryRecord> { record in
                record.date >= lowerBound && record.date < upperBound
            },
            sortBy: [SortDescriptor(\DailyHealthSummaryRecord.date, order: .forward)]
        )
        
        do {
            let allRecords: [DailyHealthSummaryRecord] = try modelContext.fetch(descriptor)
            heatmapRecords = allRecords
            let records = allRecords.filter { $0.date >= previousMonthStart && $0.date < nextMonthStart }
            
            var apTiers: [Int: Int] = [:]
            var myTiers: [Int: Int] = [:]
            
            for record in records {
                let day = calendar.component(.day, from: record.date)
                
                let count = record.workoutCount ?? 0
                let calories = record.activeCalories ?? 0
                let duration = record.workoutDuration ?? 0
                
                var tier = 0
                if count >= 3 {
                    tier = 3
                } else if count == 2 {
                    tier = 2
                } else if count == 1 {
                    tier = 1
                } else if calories > 400 || duration > 45 {
                    tier = 2
                } else if calories > 150 || duration > 15 {
                    tier = 1
                }
                
                if calendar.isDate(record.date, equalTo: previousMonthStart, toGranularity: .month) {
                    apTiers[day] = tier
                } else if calendar.isDate(record.date, equalTo: currentMonthStart, toGranularity: .month) {
                    myTiers[day] = tier
                }
            }
            
            previousMonthActiveTiers = apTiers
            currentMonthActiveTiers = myTiers
            
            // 2. Fetch past 30 days of records for statistics
            let startDate30 = calendar.date(byAdding: .day, value: -29, to: now) ?? now
            let startOf30 = calendar.startOfDay(for: startDate30)
            let endOf30 = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
            
            let records30 = allRecords.filter { $0.date >= startOf30 && $0.date <= endOf30 }
            if !records30.isEmpty {
                // Calculate total duration in minutes
                let totalMin = records30.compactMap { $0.workoutDuration }.reduce(0, +)
                let hours = Int(totalMin) / 60
                let mins = Int(totalMin) % 60
                totalWorkoutDurationText = "\(hours)小时 \(mins)分钟"
                
                // Construct points for summaryWorkPath
                let strains = records30.compactMap(\.strainScore)
                // P2-4 修复：无 strain 时只重置趋势态，不能 return——
                // 否则 loadDynamicData() 被跳过，计划/力量/热力图肌群整页空白。
                guard !strains.isEmpty else {
                    summaryWorkPathPoints = []
                    summaryWorkValues = []
                    summaryWorkDates = []
                    dynamicExertionWorkload = []
                    exertionValues = []
                    exertionDates = []
                    targetComparison = .unavailable
                    summaryPeakStrainText = "--"
                    loadDynamicData()
                    return
                }
                let maxStrain = strains.max() ?? 10.0
                summaryPeakStrainText = "\(Int(maxStrain.rounded()))"
                let minStrain = strains.min() ?? 0.0
                let strainDiff = maxStrain - minStrain
                
                var pts: [CGPoint] = []
                var values: [Double] = []
                var dates: [Date] = []
                for idx in 0..<records30.count {
                    let x = Double(idx) / Double(max(records30.count - 1, 1))
                    let strain = records30[idx].strainScore ?? minStrain
                    let normalized = strainDiff > 0 ? (strain - minStrain) / strainDiff : 0.5
                    let y = 0.9 - (normalized * 0.78)
                    pts.append(CGPoint(x: x, y: y))
                    values.append(strain)
                    dates.append(records30[idx].date)
                }
                summaryWorkPathPoints = pts
                summaryWorkValues = values
                summaryWorkDates = dates
                
                // Exertion workload (recent 12 records)
                let recent12 = Array(records30.suffix(12))
                let strainRecent = recent12.compactMap(\.strainScore)
                let maxSR = strainRecent.max() ?? 10.0
                let minSR = strainRecent.min() ?? 0.0
                let srDiff = maxSR - minSR
                dynamicExertionWorkload = strainRecent.map { srDiff > 0 ? ($0 - minSR) / srDiff : 0.5 }
                // 与曲线同序的真实耗力分数与日期（标注/拖动交互显示）
                exertionValues = strainRecent
                exertionDates = recent12.compactMap { $0.strainScore != nil ? $0.date : nil }
                
                // Target exertion zone comparison
                targetComparison = TrainingTargetComparison.evaluate(
                    strainValues: strains,
                    target: dashboard.strain
                )
            } else {
                useEmptyFitnessDefaults()
            }
            
        } catch {
            useEmptyFitnessDefaults()
        }
        loadDynamicData()
    }

    private func loadDynamicData() {
        let calendar = Calendar.current
        let refDate = dashboardVM.selectedDate
        let startOfDayRef = calendar.startOfDay(for: refDate)
        
        let startLimit = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -Self.lookbackDays, to: startOfDayRef) ?? startOfDayRef)
        let endLimit = calendar.date(byAdding: .day, value: 1, to: startOfDayRef) ?? startOfDayRef
        
        let strengthDesc = FetchDescriptor<StrengthWorkoutRecord>(
            predicate: #Predicate<StrengthWorkoutRecord> { $0.startedAt >= startLimit && $0.startedAt <= endLimit },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        self.strengthWorkouts = (try? modelContext.fetch(strengthDesc)) ?? []

        let templatesDesc = FetchDescriptor<WorkoutTemplateRecord>(
            sortBy: [SortDescriptor(\.title, order: .forward)]
        )
        self.workoutTemplates = (try? modelContext.fetch(templatesDesc)) ?? []

        // P3-12 修复：直接按 isActive 谓词取活跃计划（此前 fetchLimit=10 会漏取
        // 更新较早的活跃计划，计划入口与 todaySession 消失）。
        let plansDesc = FetchDescriptor<TrainingPlanRecord>(
            predicate: #Predicate<TrainingPlanRecord> { $0.isActive },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        self.trainingPlans = (try? modelContext.fetch(plansDesc)) ?? []

        // 训练事件窗口覆盖完整活跃计划：TrainingScheduleResolver 需要看到
        // 计划开始以来的完成事件，否则长计划会被 90 天窗口截断。
        let eventStartLimit = min(
            startLimit,
            self.trainingPlans.first(where: { $0.isActive })?.startDate ?? startLimit
        )
        let eventsDesc = FetchDescriptor<WorkoutEventRecord>(
            predicate: #Predicate<WorkoutEventRecord> { $0.startedAt >= eventStartLimit && $0.startedAt <= endLimit },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let planEvents = (try? modelContext.fetch(eventsDesc)) ?? []
        self.planResolutionEvents = planEvents
        // 展示层继续使用近 90 天窗口，避免热力图/最近记录被长计划全量事件撑大。
        self.localWorkoutEvents = planEvents.filter {
            $0.startedAt >= startLimit && $0.startedAt <= endLimit
        }
        self.memoHeatmapWeeks = makeHeatmapWeeks()

        // 训练计划的建议入口：把「计划与轮转」门户接到真实提案表。
        // 同一提案区也承接练后 AI 边界建议；只有未来未完成训练日的 proposed 才计数。
        if let activePlan = self.trainingPlans.first(where: { $0.isActive }) {
            let upcomingDayIDs = Set(activePlan.days.filter { !$0.isCompleted }.map(\.id))
            let activePlanID = activePlan.id
            let proposedForPlan = (try? modelContext.fetch(FetchDescriptor<TrainingPlanAdaptationRecord>(
                predicate: #Predicate<TrainingPlanAdaptationRecord> {
                    $0.planId == activePlanID && $0.status == "proposed"
                },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            ))) ?? []
            self.pendingPlanAdaptations = proposedForPlan.filter {
                upcomingDayIDs.contains($0.dayId)
            }
        } else {
            self.pendingPlanAdaptations = []
        }

        let dayIdentifier = DailyHealthSummaryRecord.dayIdentifier(for: refDate, calendar: calendar)
        var opPlansDesc = FetchDescriptor<DailyOperatingPlanRecord>(
            predicate: #Predicate<DailyOperatingPlanRecord> { $0.dayIdentifier == dayIdentifier },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        )
        opPlansDesc.fetchLimit = 1
        self.operatingPlans = (try? modelContext.fetch(opPlansDesc)) ?? []

        let responseDesc = FetchDescriptor<TrainingResponseRecord>(
            predicate: #Predicate<TrainingResponseRecord> { $0.date >= startLimit && $0.date <= endLimit },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        self.trainingResponses = (try? modelContext.fetch(responseDesc)) ?? []

        // 性能：个人纪录（需逐次传入历史先例）与肌群 7 天逐日组数只在数据加载后
        // 算一次并缓存，body 重渲染不再重复 O(n²) 扫描。
        let service = TrainingAnalyticsService()
        self.memoStrengthSummary = service.buildRecentSummary(
            workouts: self.strengthWorkouts.map { $0.dto },
            days: 7,
            endingAt: refDate
        )

        // PR 计算改为递增先例：排序后维护一个逐渐增长的 history 数组，
        // 每个训练只与它之前的训练比较，整体从 O(n²) 降为 O(n)。
        // 按 startedAt 分组处理，保证同一时刻的训练彼此不进入先例集合，
        // 与旧实现的 `startedAt < current.startedAt` 语义逐位一致。
        let sortedStrength = self.strengthWorkouts.sorted { $0.startedAt < $1.startedAt }
        let groupedByStart = Dictionary(grouping: sortedStrength, by: { $0.startedAt })
        var priorDTOs: [StrengthWorkoutDTO] = []
        var allPRs: [PersonalRecord] = []
        for start in groupedByStart.keys.sorted() {
            let batch = groupedByStart[start] ?? []
            for workout in batch {
                allPRs.append(contentsOf: service.summarizeWorkout(workout.dto, history: priorDTOs).personalRecords)
            }
            priorDTOs.append(contentsOf: batch.map(\.dto))
        }
        self.memoPersonalRecords = PersonalRecord.bestRecords(from: allPRs)
        self.memoMuscleDailySets = TrainingAnalyticsService.dailySetsByMuscle(
            workouts: self.strengthWorkouts.map(\.dto),
            days: 7,
            endingAt: refDate,
            calendar: calendar
        )

    }

    /// 只在用户点击「Vela 规划」时计算三年长线中位数，并按浏览日缓存。
    private func loadLongTermMediansIfNeeded() {
        let refDate = dashboardVM.selectedDate
        let dayIdentifier = DailyHealthSummaryRecord.dayIdentifier(for: refDate)
        let cacheKey = "\(dayIdentifier)-\(VelaAppState.shared.localDataRevision)"
        guard longTermMediansCacheKey != cacheKey else { return }

        let allSummaries = (try? modelContext.fetch(FetchDescriptor<DailyHealthSummaryRecord>())) ?? []
        let longTermCutoff = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -90, to: refDate) ?? refDate
        )
        let oldRHR = allSummaries
            .filter { $0.date < longTermCutoff }
            .compactMap(\.restingHeartRate)
        let oldHRV = allSummaries
            .filter { $0.date < longTermCutoff }
            .compactMap(\.hrvAverage)
        self.memoLongTermRHRMedian = Self.median(of: oldRHR)
        self.memoLongTermHRVMedian = Self.median(of: oldHRV)
        self.longTermMediansCacheKey = cacheKey
    }

    private static func median(of values: [Double]) -> Double? {
        guard values.count >= 30 else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }
    
    private func useEmptyFitnessDefaults() {
        previousMonthActiveTiers = [:]
        currentMonthActiveTiers = [:]
        totalWorkoutDurationText = "--"
        summaryPeakStrainText = "--"
        summaryWorkPathPoints = []
        summaryWorkValues = []
        summaryWorkDates = []
        dynamicExertionWorkload = []
        exertionValues = []
        exertionDates = []
        targetComparison = .unavailable
    }
    
    private func monthStart(for date: Date) -> Date {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return Calendar.current.date(from: components) ?? date
    }
}

// MARK: - Secondary analysis

private struct TrainingDeepAnalysisView: View {
    @Binding var selectedAnalyticsTab: Int
    let targetComparison: TrainingTargetComparison
    let dynamicExertionWorkload: [Double]
    let exertionValues: [Double]
    let exertionDates: [Date]
    let totalWorkoutDurationText: String
    let summaryWorkPathPoints: [CGPoint]
    let summaryWorkValues: [Double]
    let summaryWorkDates: [Date]
    let summaryPeakStrainText: String
    let selectedDate: Date
    let previousMonthActiveTiers: [Int: Int]
    let currentMonthActiveTiers: [Int: Int]
    let cardioSnapshot: CardioTrainingSnapshot
    let recentWorkouts: [WorkoutSummary]
    let strengthSummary: RecentTrainingSummary
    let exerciseProgressLines: [String]
    let personalRecords: [PersonalRecord]
    /// 最近 30 天每日快照：恢复 / 负荷 / 压力趋势共用同一窗口与同一数据源。
    let metricRecords: [DailyHealthSummaryRecord]
    let strengthWorkout: (WorkoutSummary) -> StrengthWorkoutRecord?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("训练事实，而不是评分")
                        .font(.system(.title, design: .default, weight: .semibold))
                        .tracking(-0.65)
                        .foregroundStyle(VelaTheme.rhythmInk)
                }
                .padding(.bottom, 6)

                TrainingStatsSection(
                    selectedAnalyticsTab: $selectedAnalyticsTab,
                    targetComparison: targetComparison,
                    dynamicExertionWorkload: dynamicExertionWorkload,
                    exertionValues: exertionValues,
                    exertionDates: exertionDates,
                    totalWorkoutDurationText: totalWorkoutDurationText,
                    summaryWorkPathPoints: summaryWorkPathPoints,
                    summaryWorkValues: summaryWorkValues,
                    summaryWorkDates: summaryWorkDates,
                    summaryPeakStrainText: summaryPeakStrainText,
                    selectedDate: selectedDate,
                    previousMonthActiveTiers: previousMonthActiveTiers,
                    currentMonthActiveTiers: currentMonthActiveTiers
                )

                RecoveryLoadStressTrendsCard(records: metricRecords)

                CardioStatusCard(snapshot: cardioSnapshot)

                YearlyTrainingCard()

                PersonalRecordsCard(records: personalRecords)

                MuscleVolumeCard(
                    summary: strengthSummary,
                    exerciseProgressLines: exerciseProgressLines
                )

                RecentWorkoutsSection(
                    recentWorkouts: recentWorkouts,
                    strengthWorkout: strengthWorkout
                )
            }
            .padding(.horizontal, VelaTheme.pagePadding)
            .padding(.top, 18)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("深入分析")
        .velaRhythmDetailChrome()
    }
}

// MARK: - Safe-zone workload chart helpers



// MARK: - Preview
#Preview {
    VelaTrainingView()
        .environmentObject(DashboardViewModel())
}
