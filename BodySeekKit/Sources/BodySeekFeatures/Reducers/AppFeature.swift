import BodySeekAgent
import BodySeekCore
import BodySeekHealth
import BodySeekStore
import ComposableArchitecture
import Foundation

@Reducer
public struct AppFeature: Sendable {
    public enum AppTab: Int, Equatable, Hashable, Sendable, CaseIterable {
        case today = 0
        case workout = 1
        case nutrition = 2
        case trends = 3
        case coach = 4
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var hasCompletedOnboarding: Bool
        public var selectedTab: AppTab = .today
        public var snapshot: BodySeekDashboardSnapshot
        var lastAppliedCachedDigest: String?
        public var preferences: AppPreferencesState
        public var templates: [WorkoutTemplate]
        public var sessions: [LoggedWorkoutSession]
        public var memories: [AthleteMemoryItem]
        public var tieredMemories: [TieredMemoryRecord]
        public var today: TodayFeature.State
        public var workout: WorkoutFeature.State
        public var trends: TrendsFeature.State
        public var coach: CoachFeature.State
        public var todayPath = StackState<MetricDetailFeature.State>()
        public var trendsPath = StackState<MetricDetailFeature.State>()
        @Presents public var settings: SettingsFeature.State?
        public var nutrition: NutritionFeature.State
        public var isCheckInPresented: Bool = false

        public init(
            hasCompletedOnboarding: Bool = false,
            snapshot: BodySeekDashboardSnapshot? = nil,
            preferences: AppPreferencesState = AppPreferencesState(),
            templates: [WorkoutTemplate] = ExerciseCatalog.defaultTemplates,
            sessions: [LoggedWorkoutSession] = [],
            memories: [AthleteMemoryItem] = [],
            arguments: [String] = ProcessInfo.processInfo.arguments
        ) {
            let isPreview = arguments.contains("-velaPreviewDashboard")
            let resolvedSessions = sessions.isEmpty && isPreview ? PreviewSeedFactory.makeSampleLoggedWorkouts() : sessions
            let initialSnapshot = snapshot ?? BevelScoringEngine.computeWindow(
                rawDays: isPreview
                    ? PreviewSeedFactory.makeRawWindow()
                    : PreviewSeedFactory.makeEmptyRawWindow(),
                sleepGoalMinutes: preferences.sleepGoalMinutes,
                referenceDate: Date(),
                sourceLabel: isPreview ? "示例数据" : "Apple 健康",
                isAuthorized: isPreview
            )

            self.hasCompletedOnboarding = hasCompletedOnboarding
                || isPreview
                || arguments.contains("-velaPreviewEmptyDashboard")
                || arguments.contains("-velaSkipOnboarding")
            self.snapshot = initialSnapshot
            self.preferences = preferences
            self.templates = templates
            self.sessions = resolvedSessions
            self.memories = memories
            let bridgedMemories = MemoryContextSelector.bridgeFromLegacy(memories)
            self.tieredMemories = bridgedMemories
            var initialToday = TodayFeature.State(
                snapshot: initialSnapshot,
                planItems: TodayActionGenerator.generateDefaultPlanItems(
                    for: initialSnapshot,
                    dayKey: initialSnapshot.referenceDate.physiologicalDayKey()
                )
            )
            let initialWorkout = WorkoutFeature.State(
                snapshot: initialSnapshot,
                templates: templates,
                sessions: resolvedSessions,
                dominantHand: preferences.dominantHand,
                sleepGoalMinutes: preferences.sleepGoalMinutes
            )
            initialToday.proactiveInsights = ProactiveInsightEngine.generate(
                snapshot: initialSnapshot,
                storedWorkouts: initialWorkout.storedWorkouts,
                enabled: preferences.proactiveInsightsEnabled
            )
            self.today = initialToday
            self.workout = initialWorkout
            self.trends = TrendsFeature.State(snapshot: initialSnapshot)
            self.nutrition = NutritionFeature.State(snapshot: initialSnapshot)
            var initialCoach = CoachFeature.State(
                snapshot: initialSnapshot,
                sessions: resolvedSessions,
                templates: templates,
                memories: memories,
                tieredMemories: bridgedMemories
            )
            initialCoach.storedWorkouts = initialWorkout.storedWorkouts
            initialCoach.dominantHand = preferences.dominantHand
            initialCoach.sleepGoalMinutes = preferences.sleepGoalMinutes
            self.coach = initialCoach

            if let idx = arguments.firstIndex(of: "-velaInitialTab"),
               arguments.indices.contains(idx + 1),
               let rawTab = Int(arguments[idx + 1]),
               let tab = AppTab(rawValue: rawTab) {
                self.selectedTab = tab
            }
        }
    }

    public enum Action: Sendable {
        case onAppear
        case tabSelected(AppTab)
        case onboardingAuthorizeTapped
        case onboardingSkipTapped
        case refreshRequested
        case authorizationFinished(Bool)
        case cachedDashboardLoaded(CachedDashboardState)
        case snapshotLoaded(BodySeekDashboardSnapshot)
        case persistenceFailed(String)
        case backgroundSyncCompleted(String?, workoutsDeleted: Bool = false)
        case supplementalContextLoaded(
            planItems: [PlanItemRecord],
            experimentPlanItems: [PlanItemRecord],
            patterns: [PatternFindingRecord],
            todayNutritionLog: DailyNutritionLog?,
            nutritionTargetPlan: NutritionTargetPlan?,
            nutritionLogs: [DailyNutritionLog],
            checkIns: [DailyCheckIn],
            rollingDeficit7d: Double?,
            error: String?
        )
        case fitnessStoreLoaded(
            templates: [WorkoutTemplate],
            sessions: [LoggedWorkoutSession],
            memories: [AthleteMemoryItem],
            tieredMemories: [TieredMemoryRecord],
            messages: [CoachMessage],
            error: String?
        )
        case briefingGenerated(AIBriefingStatus)
        case healthUpdateTick
        case clearMetricDetailPaths
        case today(TodayFeature.Action)
        case workout(WorkoutFeature.Action)
        case trends(TrendsFeature.Action)
        case coach(CoachFeature.Action)
        case todayPath(StackActionOf<MetricDetailFeature>)
        case trendsPath(StackActionOf<MetricDetailFeature>)
        case settings(PresentationAction<SettingsFeature.Action>)
        case nutrition(NutritionFeature.Action)
        case checkInPresented(Bool)
        case checkInFeelingSelected(Int)
        case checkInSaved(DailyCheckIn)
    }

    private enum CancelID {
        case healthUpdates
        case dashboardObservation
        case loadSnapshot
        case briefing
    }

    @Dependency(\.healthKitClient) var healthKitClient
    @Dependency(\.preferencesClient) var preferencesClient
    @Dependency(\.fitnessStoreClient) var fitnessStoreClient
    @Dependency(\.bodySeekStoreClient) var bodySeekStoreClient
    @Dependency(\.coachAIClient) var coachAIClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.today, action: \.today) {
            TodayFeature()
        }
        Scope(state: \.workout, action: \.workout) {
            WorkoutFeature()
        }
        Scope(state: \.trends, action: \.trends) {
            TrendsFeature()
        }
        Scope(state: \.coach, action: \.coach) {
            CoachFeature()
        }

        Scope(state: \.nutrition, action: \.nutrition) {
            NutritionFeature()
        }

        Reduce { state, action in
            switch action {
            case .onAppear:
                BodySeekSignposts.shared.beginColdStartIfNeeded()
                do {
                    let loaded = try preferencesClient.load()
                    state.preferences = loaded
                    state.workout.dominantHand = loaded.dominantHand
                    state.workout.sleepGoalMinutes = loaded.sleepGoalMinutes
                    state.workout.recomputeRecoverySnapshot(asOf: now)
                    syncCheckInFromPreferences(into: &state)
                } catch {
                    state.today.lastError = "读取偏好设置失败：\(error.localizedDescription)"
                }
                return .merge(
                    loadSnapshotEffect(goalMinutes: state.preferences.sleepGoalMinutes, referenceDate: now),
                    loadFitnessStoreEffect(),
                    loadSupplementalContextEffect(dayKey: state.snapshot.referenceDate.physiologicalDayKey(), referenceDate: now),
                    .send(.workout(.onAppear)),
                    observeHealthUpdatesEffect(),
                    observeStoredDashboardEffect(goalMinutes: state.preferences.sleepGoalMinutes)
                )

            case let .tabSelected(tab):
                BodySeekSignposts.shared.emitEvent(.tabSwitch, detail: "\(tab.rawValue)")
                state.selectedTab = tab
                return .none

            case .onboardingAuthorizeTapped:
                state.hasCompletedOnboarding = true
                return .run { send in
                    let granted = await healthKitClient.requestAuthorization()
                    await send(.authorizationFinished(granted))
                }

            case .onboardingSkipTapped:
                state.hasCompletedOnboarding = true
                return .none

            case .refreshRequested:
                state.today.isLoading = true
                return loadSnapshotEffect(goalMinutes: state.preferences.sleepGoalMinutes, referenceDate: now)

            case .authorizationFinished:
                return loadSnapshotEffect(goalMinutes: state.preferences.sleepGoalMinutes, referenceDate: now)

            case let .cachedDashboardLoaded(cached):
                guard cached.contentDigest != state.lastAppliedCachedDigest else { return .none }
                if state.snapshot.historyDays.isEmpty
                    || !state.snapshot.isAuthorized
                    || cached.snapshot.historyDays.count >= state.snapshot.historyDays.count
                {
                    state.lastAppliedCachedDigest = cached.contentDigest
                    apply(snapshot: cached.snapshot, precomputedCache: cached.chartCache, to: &state)
                    BodySeekSignposts.shared.endColdStartIfActive()
                }
                return .none

            case let .snapshotLoaded(snapshot):
                let mergedSnapshot: BodySeekDashboardSnapshot
                if snapshot.isAuthorized,
                   state.snapshot.isAuthorized,
                   state.snapshot.historyDays.count > snapshot.historyDays.count
                {
                    let newerKeys = Set(snapshot.historyDays.map(\.dayKey))
                    let preservedOlder = state.snapshot.historyDays.filter { !newerKeys.contains($0.dayKey) }
                    let combinedHistory = (preservedOlder + snapshot.historyDays).sorted { $0.date < $1.date }
                    mergedSnapshot = BodySeekDashboardSnapshot(
                        referenceDate: snapshot.referenceDate,
                        today: snapshot.today,
                        historyDays: combinedHistory,
                        trainingLoad: snapshot.trainingLoad,
                        sourceLabel: snapshot.sourceLabel,
                        lastUpdatedAt: snapshot.lastUpdatedAt,
                        isAuthorized: snapshot.isAuthorized,
                        scoreAlgorithmVersion: snapshot.scoreAlgorithmVersion
                    )
                } else {
                    mergedSnapshot = snapshot
                }
                apply(snapshot: mergedSnapshot, precomputedCache: nil, to: &state)
                BodySeekSignposts.shared.endColdStartIfActive()
                guard mergedSnapshot.isAuthorized else {
                    state.today.briefingStatus = .unconfigured(reason: "连接 Apple 健康并配置 AI 模型后生成生理简报")
                    return .cancel(id: CancelID.briefing)
                }
                let briefing = requestBriefing(state: &state)
                return .merge(
                    briefing,
                    triggerBackgroundBackfillEffect(goalMinutes: state.preferences.sleepGoalMinutes, referenceDate: now),
                    .send(.workout(.syncWatchWorkouts))
                )

            case let .persistenceFailed(message):
                state.today.lastError = message
                return .none

            case let .backgroundSyncCompleted(error, workoutsDeleted):
                if let error {
                    state.today.lastError = error
                }
                return workoutsDeleted ? .send(.workout(.syncWatchWorkouts)) : .none

            case let .supplementalContextLoaded(planItems, experimentPlanItems, patterns, nutritionLog, nutritionPlan, nutritionLogs, checkIns, rollingDeficit7d, error):
                let currentItems = planItems.filter { $0.dayKey == now.physiologicalDayKey() }
                if !currentItems.isEmpty {
                    state.today.planItems = currentItems
                }
                let eatingDays = Set(
                    nutritionLogs
                        .filter { $0.dietDayComplete == true || !$0.entries.isEmpty }
                        .map(\.dayKey)
                )
                state.trends.patternFindings = patterns
                state.trends.experimentPlanItems = experimentPlanItems
                state.trends.eatingAvailableDayKeys = eatingDays
                state.trends.refreshPersonalForecast()
                state.today.todayNutritionLog = nutritionLog
                state.today.nutritionTargetPlan = nutritionPlan
                state.today.nutritionRollingDeficit7d = rollingDeficit7d
                state.coach.patternFindings = patterns
                state.coach.todayNutritionLog = nutritionLog
                state.coach.nutritionTargetPlan = nutritionPlan
                state.coach.nutritionLogs = nutritionLogs
                state.coach.checkIns = checkIns
                if let error {
                    state.today.lastError = error
                }
                return .none

            case let .fitnessStoreLoaded(templates, sessions, memories, tieredMemories, messages, error):
                state.templates = templates
                state.sessions = sessions
                state.memories = memories
                let resolvedTiered = tieredMemories.isEmpty && !memories.isEmpty
                    ? MemoryContextSelector.bridgeFromLegacy(memories)
                    : tieredMemories
                state.tieredMemories = resolvedTiered
                state.workout.templates = templates
                state.workout.sessions = sessions
                state.workout.recomputeRecoverySnapshot(asOf: now)
                state.coach.templates = templates
                state.coach.sessions = sessions
                state.coach.memories = memories
                state.coach.tieredMemories = resolvedTiered
                if !messages.isEmpty, state.coach.isAtWelcome, !state.coach.isResettingConversation {
                    state.coach.messages = messages
                }
                if let error {
                    state.workout.lastError = error
                }
                refreshTrainingAdvice(&state)
                return state.today.postWorkoutAdvice == nil ? .none : .cancel(id: CancelID.briefing)

            case let .briefingGenerated(status):
                guard state.today.postWorkoutAdvice == nil else { return .none }
                state.today.briefingStatus = status
                return .none

            case .healthUpdateTick:
                return loadSnapshotEffect(goalMinutes: state.preferences.sleepGoalMinutes, referenceDate: now)

            case .clearMetricDetailPaths:
                state.todayPath.removeAll()
                state.trendsPath.removeAll()
                return .none

            // MARK: - Today Delegates

            case let .today(.delegate(delegate)):
                switch delegate {
                case .refreshRequested:
                    state.today.isLoading = true
                    return loadSnapshotEffect(goalMinutes: state.preferences.sleepGoalMinutes, referenceDate: now)

                case .authorizationRequested:
                    return .run { send in
                        let granted = await healthKitClient.requestAuthorization()
                        await send(.authorizationFinished(granted))
                    }

                case let .openMetric(kind):
                    state.todayPath.append(
                        MetricDetailFeature.State(
                            kind: kind,
                            snapshot: state.snapshot,
                            sleepGoalMinutes: state.preferences.sleepGoalMinutes,
                            precomputedCache: state.trends.cache(for: kind)
                        )
                    )
                    return .none

                case let .askCoach(question):
                    return routeToCoach(question: question, state: &state)

                case let .saveSubjectiveFeeling(score):
                    state.preferences.subjectiveFeelingsByDay[state.snapshot.referenceDate.dayKey()] = score
                    do {
                        try preferencesClient.save(state.preferences)
                    } catch {
                        state.today.lastError = "保存主观状态失败：\(error.localizedDescription)"
                    }
                    return .none

                case let .adoptPlanItem(item), let .dismissPlanItem(item):
                    return .run { send in
                        do {
                            let proposal = try ActionProposal(
                                kind: .adjustPlan,
                                origin: .user,
                                encodablePayload: AdjustPlanPayload(item: item),
                                rationale: item.state == .adopted ? "用户采纳今日行动建议" : "用户跳过今日行动建议"
                            )
                            _ = try await bodySeekStoreClient.executeProposal(proposal)
                        } catch {
                            await send(.persistenceFailed("保存行动计划状态失败：\(error.localizedDescription)"))
                        }
                    }

                case .openNutrition:
                    state.selectedTab = .nutrition
                    state.nutrition.showToday()
                    return .none

                case .openSettings:
                    state.settings = SettingsFeature.State(
                        snapshot: state.snapshot,
                        preferences: state.preferences,
                        memories: state.memories,
                        tieredMemories: state.tieredMemories
                    )
                    return .none

                case .openCheckIn:
                    state.isCheckInPresented = true
                    return .none

                case .openWorkoutInbox:
                    state.selectedTab = .workout
                    return .none

                case .proactiveInsightDismissed:
                    return .none

                case .regenerateBriefingRequested:
                    return requestBriefing(state: &state)
                }

            // MARK: - Workout Delegates

            case .workout(.watchWorkoutsLoaded), .workout(.reviewPersisted):
                syncWorkoutContextToCoachAndInsights(&state)
                refreshTrainingAdvice(&state)
                return state.today.postWorkoutAdvice == nil ? .none : .cancel(id: CancelID.briefing)

            case let .workout(.delegate(delegate)):
                switch delegate {
                case .refreshRequested:
                    return loadSnapshotEffect(goalMinutes: state.preferences.sleepGoalMinutes, referenceDate: now)

                case let .sessionSaved(session):
                    if let index = state.sessions.firstIndex(where: { $0.id == session.id }) {
                        state.sessions[index] = session
                    } else {
                        state.sessions.insert(session, at: 0)
                    }
                    state.coach.sessions = state.sessions
                    state.workout.recomputeRecoverySnapshot(asOf: now)
                    refreshTrainingAdvice(&state)
                    let cancelBriefing: Effect<Action> = state.today.postWorkoutAdvice == nil ? .none : .cancel(id: CancelID.briefing)
                    if session.syncedHealthKitUUID != nil {
                        return .merge(cancelBriefing, loadSnapshotEffect(goalMinutes: state.preferences.sleepGoalMinutes, referenceDate: now))
                    }
                    return cancelBriefing

                case let .templateSaved(template):
                    if let idx = state.templates.firstIndex(where: { $0.id == template.id }) {
                        state.templates[idx] = template
                    } else {
                        state.templates.insert(template, at: 0)
                    }
                    state.coach.templates = state.templates
                    return .none

                case let .memoryCommitted(item):
                    state.memories.insert(item, at: 0)
                    let bridged = MemoryContextSelector.bridgeFromLegacy([item])
                    state.tieredMemories.insert(contentsOf: bridged, at: 0)
                    let updatedMemories = state.memories
                    let updatedTiered = state.tieredMemories
                    state.coach.memories = updatedMemories
                    state.coach.tieredMemories = updatedTiered
                    state.settings?.memories = updatedMemories
                    state.settings?.tieredMemories = updatedTiered
                    return .none

                case let .askCoach(question):
                    return routeToCoach(question: question, state: &state)

                case .openTrends:
                    state.selectedTab = .trends
                    return .none
                }

            // MARK: - Trends & MetricDetail Delegates

            case let .trends(.delegate(.openMetric(kind, horizon))):
                state.trendsPath.append(
                    MetricDetailFeature.State(
                        kind: kind,
                        snapshot: state.snapshot,
                        horizon: horizon,
                        sleepGoalMinutes: state.preferences.sleepGoalMinutes,
                        precomputedCache: state.trends.cache(for: kind)
                    )
                )
                return .none

            case let .trends(.delegate(.patternFindingsUpdated(findings))):
                state.coach.patternFindings = findings
                return .none

            case let .trends(.delegate(.tieredMemoryAdded(memory))):
                if !state.tieredMemories.contains(where: { $0.id == memory.id }) {
                    state.tieredMemories.insert(memory, at: 0)
                    let updated = state.tieredMemories
                    state.coach.tieredMemories = updated
                    state.settings?.tieredMemories = updated
                }
                return .none

            case let .todayPath(.element(id: _, action: .delegate(.askCoach(question)))),
                 let .trendsPath(.element(id: _, action: .delegate(.askCoach(question)))):
                return routeToCoach(question: question, state: &state, deferPathReset: true)

            // MARK: - Coach Delegates

            case let .coach(.delegate(delegate)):
                switch delegate {
                case let .applyWorkoutProposal(proposal, startImmediately):
                    state.selectedTab = .workout
                    return .send(.workout(.acceptProposalTapped(proposal, startImmediately: startImmediately)))

                case let .memoriesUpdated(memories):
                    state.memories = memories
                    state.settings?.memories = memories
                    return .none

                case let .tieredMemoriesUpdated(tiered):
                    state.tieredMemories = tiered
                    state.settings?.tieredMemories = tiered
                    return .none

                case let .patternFindingsUpdated(findings):
                    state.trends.patternFindings = findings
                    return .none

                case .workoutAnnotationCommitted:
                    return .send(.workout(.onAppear))

                case .openSettings:
                    state.settings = SettingsFeature.State(
                        snapshot: state.snapshot,
                        preferences: state.preferences,
                        memories: state.memories,
                        tieredMemories: state.tieredMemories
                    )
                    return .none
                }

            // MARK: - Settings Delegates

            case let .settings(.presented(.delegate(delegate))):
                switch delegate {
                case .authorizationRequested:
                    return .run { send in
                        let granted = await healthKitClient.requestAuthorization()
                        await send(.authorizationFinished(granted))
                    }

                case let .preferencesUpdated(updated):
                    let handChanged = state.preferences.dominantHand != updated.dominantHand
                    state.preferences = updated
                    state.workout.dominantHand = updated.dominantHand
                    state.workout.sleepGoalMinutes = updated.sleepGoalMinutes
                    state.coach.dominantHand = updated.dominantHand
                    state.coach.sleepGoalMinutes = updated.sleepGoalMinutes
                    syncWorkoutContextToCoachAndInsights(&state)
                    if handChanged {
                        return .merge(
                            loadSnapshotEffect(goalMinutes: updated.sleepGoalMinutes, referenceDate: now),
                            .send(.workout(.syncWatchWorkouts))
                        )
                    }
                    return loadSnapshotEffect(goalMinutes: updated.sleepGoalMinutes, referenceDate: now)

                case let .memoriesUpdated(memories):
                    state.memories = memories
                    let activeIDs = Set(memories.map(\.id))
                    let pruned = state.tieredMemories.filter { $0.tier == .verifiedPattern || activeIDs.contains($0.id) }
                    state.tieredMemories = pruned
                    state.coach.memories = memories
                    state.coach.tieredMemories = pruned
                    state.settings?.tieredMemories = pruned
                    return .none

                case .allDataReset:
                    state.preferences = AppPreferencesState()
                    state.memories = []
                    state.tieredMemories = []
                    state.sessions = []
                    state.templates = ExerciseCatalog.defaultTemplates
                    state.workout.sessions = []
                    state.workout.templates = ExerciseCatalog.defaultTemplates
                    state.workout.storedWorkouts = []
                    state.workout.deletedWorkoutUUIDs = []
                    state.workout.annotationsByWorkoutUUID = [:]
                    state.workout.muscleLoads = []
                    state.workout.reviewDraft = nil
                    state.workout.inspectedMuscleForRecovery = nil
                    state.workout.inspectedWorkoutDetail = nil
                    state.workout.dominantHand = .right
                    state.workout.sleepGoalMinutes = state.preferences.sleepGoalMinutes
                    state.workout.recomputeRecoverySnapshot(asOf: now)
                    state.coach.memories = []
                    state.coach.tieredMemories = []
                    state.coach.sessions = []
                    state.coach.templates = ExerciseCatalog.defaultTemplates
                    state.coach.patternFindings = []
                    state.coach.nutritionLogs = []
                    state.coach.todayNutritionLog = nil
                    state.coach.checkIns = []
                    state.today.dismissedInsightIDs = []
                    state.today.subjectiveFeeling = nil
                    state.today.todayCheckIn = nil
                    state.today.planItems = []
                    state.today.todayNutritionLog = nil
                    state.today.nutritionTargetPlan = nil
                    state.today.nutritionRollingDeficit7d = nil
                    state.trends.patternFindings = []
                    let emptySnapshot = BevelScoringEngine.computeWindow(
                        rawDays: PreviewSeedFactory.makeEmptyRawWindow(endingAt: now),
                        sleepGoalMinutes: state.preferences.sleepGoalMinutes,
                        referenceDate: now,
                        sourceLabel: "已重置",
                        isAuthorized: false
                    )
                    state.lastAppliedCachedDigest = nil
                    state.nutrition = NutritionFeature.State(snapshot: emptySnapshot)
                    apply(snapshot: emptySnapshot, precomputedCache: nil, to: &state)
                    return loadSnapshotEffect(goalMinutes: state.preferences.sleepGoalMinutes, referenceDate: now)

                case .dismissed:
                    state.settings = nil
                    if state.snapshot.isAuthorized {
                        return requestBriefing(state: &state)
                    }
                    return .none
                }

            case let .checkInPresented(presented):
                state.isCheckInPresented = presented
                return .none

            case let .checkInFeelingSelected(score):
                let dayKey = state.snapshot.referenceDate.physiologicalDayKey()
                let entry = DailyCheckIn(
                    id: state.today.todayCheckIn?.id ?? UUID(),
                    dayKey: dayKey,
                    recordedAt: now,
                    energy: score,
                    mood: state.today.todayCheckIn?.mood ?? 3,
                    stress: state.today.todayCheckIn?.stress ?? 3,
                    soreness: state.today.todayCheckIn?.soreness ?? [:],
                    note: state.today.todayCheckIn?.note
                )
                return .send(.checkInSaved(entry))

            case let .checkInSaved(entry):
                let physKey = entry.dayKey.isoString
                let calKey = state.snapshot.referenceDate.dayKey()
                state.preferences.checkInsByDay[physKey] = entry
                state.preferences.subjectiveFeelingsByDay[physKey] = entry.energy
                state.preferences.subjectiveFeelingsByDay[calKey] = entry.energy
                state.today.todayCheckIn = entry
                state.today.subjectiveFeeling = entry.energy
                do {
                    try preferencesClient.save(state.preferences)
                } catch {
                    state.today.lastError = "保存每日体感打卡失败：\(error.localizedDescription)"
                }
                state.isCheckInPresented = false
                return .run { send in
                    do {
                        let proposal = try ActionProposal(
                            kind: .recordCheckIn,
                            origin: .user,
                            encodablePayload: RecordCheckInPayload(checkIn: entry)
                        )
                        _ = try await bodySeekStoreClient.executeProposal(proposal)
                    } catch {
                        await send(.persistenceFailed("同步每日体感打卡至数据库失败：\(error.localizedDescription)"))
                    }
                }

            case let .nutrition(.delegate(.nutritionDataChanged(todayLog, plan, rollingDeficit7d))):
                state.today.todayNutritionLog = todayLog
                state.today.nutritionTargetPlan = plan
                state.today.nutritionRollingDeficit7d = rollingDeficit7d
                state.coach.todayNutritionLog = todayLog
                state.coach.nutritionTargetPlan = plan
                state.coach.nutritionLogs = state.nutrition.logs
                state.trends.eatingAvailableDayKeys = Set(state.nutrition.logs
                    .filter { $0.dietDayComplete == true || !$0.entries.isEmpty }
                    .map(\.dayKey))
                state.trends.refreshPersonalForecast()
                return .none

            case .today, .workout, .trends, .coach, .todayPath, .trendsPath, .settings, .nutrition:
                return .none
            }
        }
        .forEach(\.todayPath, action: \.todayPath) {
            MetricDetailFeature()
        }
        .forEach(\.trendsPath, action: \.trendsPath) {
            MetricDetailFeature()
        }
        .ifLet(\.$settings, action: \.settings) {
            SettingsFeature()
        }
    }

    private func loadSnapshotEffect(goalMinutes: Int, referenceDate: Date) -> Effect<Action> {
        .run { send in
            let snapshot = await healthKitClient.loadDashboardWindow(
                days: 60,
                sleepGoalMinutes: goalMinutes,
                referenceDate: referenceDate
            )
            try Task.checkCancellation()
            await send(.snapshotLoaded(snapshot))
            if snapshot.isAuthorized {
                do {
                    try await bodySeekStoreClient.persistDashboardSnapshot(snapshot)
                } catch {
                    await send(.persistenceFailed("保存生理快照到数据库失败：\(error.localizedDescription)"))
                }
            }
        }
        .cancellable(id: CancelID.loadSnapshot, cancelInFlight: true)
    }

    private func observeStoredDashboardEffect(goalMinutes: Int) -> Effect<Action> {
        .run { send in
            do {
                let stream = await bodySeekStoreClient.observeDashboard(goalMinutes)
                for try await cached in stream {
                    await send(.cachedDashboardLoaded(cached))
                }
            } catch {
                await send(.persistenceFailed("监听数据库快照更新失败：\(error.localizedDescription)"))
            }
        }
        .cancellable(id: CancelID.dashboardObservation, cancelInFlight: true)
    }

    private func triggerBackgroundBackfillEffect(goalMinutes: Int, referenceDate: Date) -> Effect<Action> {
        .run { send in
            do {
                let recent = try await bodySeekStoreClient.syncRecentWindow(goalMinutes, referenceDate)
                if let recent, !recent.deletedWorkoutUUIDs.isEmpty {
                    await send(.backgroundSyncCompleted(nil, workoutsDeleted: true))
                }
                _ = try await bodySeekStoreClient.runBackgroundBackfill(goalMinutes, referenceDate)
                await send(.backgroundSyncCompleted(nil))
            } catch {
                await send(.backgroundSyncCompleted("后台同步历史健康数据失败：\(error.localizedDescription)"))
            }
        }
    }

    private func loadSupplementalContextEffect(dayKey: DayKey, referenceDate: Date) -> Effect<Action> {
        let isPreview = ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
        let isEmptyPreview = ProcessInfo.processInfo.arguments.contains("-velaPreviewEmptyDashboard")
        return .run { send in
            do {
                let storedPlan = try await bodySeekStoreClient.loadPlanItems(dayKey)
                let experimentItems = try await bodySeekStoreClient.loadExperimentPlanItems()
                var findings = try await bodySeekStoreClient.loadPatternFindings(nil)
                if findings.isEmpty && !isEmptyPreview {
                    let seeds = M4APersonalPatternSeeds.defaultCandidates()
                    for seed in seeds {
                        try await bodySeekStoreClient.savePatternFinding(seed)
                    }
                    findings = seeds
                }

                var profile = try await bodySeekStoreClient.loadNutritionProfile()
                var plan = try await bodySeekStoreClient.loadNutritionTargetPlan()
                var logs = try await bodySeekStoreClient.loadNutritionLogs(nil, nil)

                if isPreview && profile == nil && logs.isEmpty {
                    let seedProfile = NutritionPlanFactory.makePreviewProfile()
                    let seedPlan = NutritionPlanFactory.makeDefaultDRIsPlan(for: seedProfile, effectiveFrom: dayKey)
                    let seedLogs = NutritionPlanFactory.makePreviewLogs(endingAt: dayKey, bmrKcal: seedProfile.bmrKcalReference ?? 1640)
                    let profProp = try ActionProposal(kind: .upsertNutritionProfile, origin: .system, encodablePayload: UpsertNutritionProfilePayload(profile: seedProfile))
                    _ = try await bodySeekStoreClient.executeProposal(profProp)
                    let planProp = try ActionProposal(kind: .commitNutritionTargets, origin: .system, encodablePayload: CommitNutritionTargetsPayload(plan: seedPlan))
                    _ = try await bodySeekStoreClient.executeProposal(planProp)
                    for log in seedLogs {
                        for entry in log.entries {
                            let mealProp = try ActionProposal(kind: .logNutritionMeal, origin: .system, encodablePayload: LogNutritionMealPayload(dayKey: log.dayKey, entry: entry, partialFields: log.dietPartialFields))
                            _ = try await bodySeekStoreClient.executeProposal(mealProp)
                        }
                        if log.dietDayComplete == true {
                            let closeProp = try ActionProposal(
                                kind: .closeNutritionDay,
                                origin: .system,
                                encodablePayload: CloseNutritionDayPayload(
                                    dayKey: log.dayKey,
                                    markComplete: true,
                                    sportHours: log.sportHours,
                                    sportKcal: log.sportKcal,
                                    steps: log.steps,
                                    bmrKcalUsed: log.bmrKcalUsed,
                                    reviewSummary: log.reviewSummary
                                )
                            )
                            _ = try await bodySeekStoreClient.executeProposal(closeProp)
                        }
                    }
                    profile = seedProfile
                    plan = try await bodySeekStoreClient.loadNutritionTargetPlan()
                    logs = try await bodySeekStoreClient.loadNutritionLogs(nil, nil)
                }

                let bounds = NutritionFeature.State.dateBounds(mode: .week, anchor: dayKey)
                let summary = NutritionBoardAggregator.summarizePeriod(
                    logs: logs,
                    targetPlan: plan,
                    startDayKey: bounds.start,
                    endDayKey: bounds.end,
                    todayKey: dayKey
                )
                let todayLog = logs.first(where: { $0.dayKey == dayKey })
                let checkIns = try await bodySeekStoreClient.loadCheckIns()

                await send(.supplementalContextLoaded(
                    planItems: storedPlan,
                    experimentPlanItems: experimentItems,
                    patterns: findings,
                    todayNutritionLog: todayLog,
                    nutritionTargetPlan: plan,
                    nutritionLogs: logs,
                    checkIns: checkIns,
                    rollingDeficit7d: summary.rollingDeficit7dKcal,
                    error: nil
                ))
            } catch {
                await send(.supplementalContextLoaded(
                    planItems: [],
                    experimentPlanItems: [],
                    patterns: [],
                    todayNutritionLog: nil,
                    nutritionTargetPlan: nil,
                    nutritionLogs: [],
                    checkIns: [],
                    rollingDeficit7d: nil,
                    error: "读取计划与营养上下文失败：\(error.localizedDescription)"
                ))
            }
        }
    }

    private func loadFitnessStoreEffect() -> Effect<Action> {
        .run { send in
            do {
                let templates = try await fitnessStoreClient.loadTemplates()
                let sessions = try await fitnessStoreClient.loadSessions()
                let memories = try await fitnessStoreClient.loadMemories()
                let tieredMemories = try await bodySeekStoreClient.loadTieredMemories(false)
                let messages = try await fitnessStoreClient.loadMessages()
                await send(.fitnessStoreLoaded(
                    templates: templates,
                    sessions: sessions,
                    memories: memories,
                    tieredMemories: tieredMemories,
                    messages: messages,
                    error: nil
                ))
            } catch {
                await send(.fitnessStoreLoaded(
                    templates: ExerciseCatalog.defaultTemplates,
                    sessions: [],
                    memories: [],
                    tieredMemories: [],
                    messages: [],
                    error: "读取本地训练仓库失败：\(error.localizedDescription)"
                ))
            }
        }
    }

    private func requestBriefing(state: inout State) -> Effect<Action> {
        refreshTrainingAdvice(&state)
        guard state.today.postWorkoutAdvice == nil else { return .cancel(id: CancelID.briefing) }
        state.today.briefingStatus = .loading
        let context = AgentExecutionContext(
            snapshot: state.snapshot,
            sessions: state.sessions,
            templates: state.templates,
            memories: state.memories,
            tieredMemories: state.tieredMemories,
            storedWorkouts: state.workout.storedWorkouts,
            deletedWorkoutUUIDs: state.workout.deletedWorkoutUUIDs,
            annotationsByWorkoutUUID: state.workout.annotationsByWorkoutUUID,
            muscleLoads: state.workout.muscleLoads,
            patternFindings: state.trends.patternFindings,
            todayNutritionLog: state.today.todayNutritionLog,
            nutritionTargetPlan: state.today.nutritionTargetPlan,
            nutritionLogs: state.coach.nutritionLogs,
            checkIns: state.coach.checkIns,
            dominantHand: state.preferences.dominantHand,
            sleepGoalMinutes: state.preferences.sleepGoalMinutes,
            asOf: now
        )
        return .run { send in
            let status = await coachAIClient.generateBriefing(context)
            await send(.briefingGenerated(status))
        }
        .cancellable(id: CancelID.briefing, cancelInFlight: true)
    }

    private func observeHealthUpdatesEffect() -> Effect<Action> {
        .run { send in
            let stream = await healthKitClient.observeUpdates()
            for await _ in stream {
                await send(.healthUpdateTick)
            }
        }
        .cancellable(id: CancelID.healthUpdates, cancelInFlight: true)
    }

    private func apply(
        snapshot: BodySeekDashboardSnapshot,
        precomputedCache: [TrendHorizon: [MetricKind: ChartSeriesSnapshot]]?,
        to state: inout State
    ) {
        state.snapshot = snapshot
        state.today.isLoading = false
        state.today.updateSnapshot(snapshot)
        state.today.planItems.removeAll { $0.dayKey != snapshot.referenceDate.physiologicalDayKey() }
        let hasPersistedUserDecisions = state.today.planItems.contains { $0.state != .suggested || $0.origin != .system }
        if !hasPersistedUserDecisions {
            state.today.planItems = TodayActionGenerator.generateDefaultPlanItems(
                for: snapshot,
                dayKey: snapshot.referenceDate.physiologicalDayKey()
            )
        }
        syncCheckInFromPreferences(into: &state)
        state.workout.snapshot = snapshot
        state.workout.dominantHand = state.preferences.dominantHand
        state.workout.sleepGoalMinutes = state.preferences.sleepGoalMinutes
        state.workout.includeSnapshotWorkouts()
        state.workout.recomputeRecoverySnapshot(asOf: now)
        state.trends.updateSnapshot(snapshot, precomputedCache: precomputedCache)
        state.coach.snapshot = snapshot
        syncWorkoutContextToCoachAndInsights(&state)
        refreshTrainingAdvice(&state)
        state.settings?.snapshot = snapshot
        state.nutrition.snapshot = snapshot
        let nutritionDay = snapshot.referenceDate.physiologicalDayKey()
        if state.nutrition.todayKey != nutritionDay {
            let wasShowingToday = state.nutrition.selectedDayKey == state.nutrition.todayKey
            state.nutrition.todayKey = nutritionDay
            if wasShowingToday {
                state.nutrition.showToday()
            } else {
                state.nutrition.recomputeSummary()
            }
        }
        let sleepGoal = state.preferences.sleepGoalMinutes
        for id in state.todayPath.ids {
            if let kind = state.todayPath[id: id]?.kind {
                let kindCache = state.trends.cache(for: kind)
                state.todayPath[id: id]?.sleepGoalMinutes = sleepGoal
                state.todayPath[id: id]?.updateSnapshot(snapshot, precomputedCache: kindCache)
            }
        }
        for id in state.trendsPath.ids {
            if let kind = state.trendsPath[id: id]?.kind {
                let kindCache = state.trends.cache(for: kind)
                state.trendsPath[id: id]?.sleepGoalMinutes = sleepGoal
                state.trendsPath[id: id]?.updateSnapshot(snapshot, precomputedCache: kindCache)
            }
        }
    }

    private func refreshTrainingAdvice(_ state: inout State) {
        let reference = now
        let day = reference.physiologicalDayKey()
        let workouts = state.workout.storedWorkouts
            + WorkoutFeature.State.storedRecords(from: Array(state.snapshot.historyDays.suffix(3)))
        let completedIDs = Set(workouts.filter {
            $0.start.physiologicalDayKey() == day && $0.end <= reference
                && !state.workout.deletedWorkoutUUIDs.contains($0.hkUUID.lowercased())
        }.map { $0.hkUUID.lowercased() })
        let manual = state.workout.sessions.filter {
            $0.startedAt.physiologicalDayKey() == day && $0.completedAt <= reference
        }
        guard !completedIDs.isEmpty || !manual.isEmpty else {
            state.today.postWorkoutAdvice = nil
            return
        }

        let primaryMuscles = state.workout.muscleLoads.filter {
            $0.role == .primary && $0.load > 0 && completedIDs.contains($0.workoutUUID.lowercased())
        }.map(\.muscle)
        let manualMuscles = manual.flatMap { $0.muscleLoadIntensities.filter { $0.value >= 0.4 }.keys }
        let recordedMuscles = Set(primaryMuscles + manualMuscles)
        let names = BodyRegionMuscle.allCases.filter { recordedMuscles.contains($0) }.map(\.title)
        let focus = names.isEmpty ? "" : "已记录\(names.joined(separator: "、"))训练。"
        state.today.postWorkoutAdvice = focus + "接下来留时间恢复。"
        state.today.briefingStatus = .idle
    }

    private func syncWorkoutContextToCoachAndInsights(_ state: inout State) {
        let workouts = state.workout.storedWorkouts
        let annotations = state.workout.annotationsByWorkoutUUID
        let loads = state.workout.muscleLoads
        state.coach.storedWorkouts = workouts
        state.coach.deletedWorkoutUUIDs = state.workout.deletedWorkoutUUIDs
        state.coach.annotationsByWorkoutUUID = annotations
        state.coach.muscleLoads = loads
        state.coach.dominantHand = state.preferences.dominantHand
        state.coach.sleepGoalMinutes = state.preferences.sleepGoalMinutes
        state.today.proactiveInsights = ProactiveInsightEngine.generate(
            snapshot: state.snapshot,
            storedWorkouts: workouts,
            enabled: state.preferences.proactiveInsightsEnabled,
            dismissedIDs: state.today.dismissedInsightIDs
        )
    }

    private func syncCheckInFromPreferences(into state: inout State) {
        let physKey = state.snapshot.referenceDate.physiologicalDayKey().isoString
        let calKey = state.snapshot.referenceDate.dayKey()
        let checkIn = state.preferences.checkInsByDay[physKey] ?? state.preferences.checkInsByDay[calKey]
        state.today.todayCheckIn = checkIn
        state.today.subjectiveFeeling = checkIn?.energy
            ?? state.preferences.subjectiveFeelingsByDay[physKey]
            ?? state.preferences.subjectiveFeelingsByDay[calKey]
    }

    private func routeToCoach(
        question: String,
        state: inout State,
        deferPathReset: Bool = false
    ) -> Effect<Action> {
        state.selectedTab = .coach
        return .merge(
            .send(.coach(.externalPromptSubmitted(question))),
            .run { send in
                if deferPathReset {
                    do {
                        try await clock.sleep(for: .milliseconds(350))
                    } catch {
                        return
                    }
                    await send(.clearMetricDetailPaths)
                }
            }
        )
    }
}
