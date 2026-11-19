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
        case trends = 2
        case coach = 3
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var hasCompletedOnboarding: Bool
        public var selectedTab: AppTab = .today
        public var snapshot: BodySeekDashboardSnapshot
        public var preferences: AppPreferencesState
        public var templates: [WorkoutTemplate]
        public var sessions: [LoggedWorkoutSession]
        public var memories: [AthleteMemoryItem]
        public var today: TodayFeature.State
        public var workout: WorkoutFeature.State
        public var trends: TrendsFeature.State
        public var coach: CoachFeature.State
        public var todayPath = StackState<MetricDetailFeature.State>()
        public var trendsPath = StackState<MetricDetailFeature.State>()
        @Presents public var settings: SettingsFeature.State?
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
            self.today = TodayFeature.State(snapshot: initialSnapshot)
            self.workout = WorkoutFeature.State(
                snapshot: initialSnapshot,
                templates: templates,
                sessions: resolvedSessions
            )
            self.trends = TrendsFeature.State(snapshot: initialSnapshot)
            self.coach = CoachFeature.State(
                snapshot: initialSnapshot,
                sessions: resolvedSessions,
                templates: templates,
                memories: memories
            )

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
        case backgroundSyncCompleted(String?)
        case fitnessStoreLoaded(
            templates: [WorkoutTemplate],
            sessions: [LoggedWorkoutSession],
            memories: [AthleteMemoryItem],
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
        case checkInPresented(Bool)
        case checkInFeelingSelected(Int)
        case checkInSaved(DailyCheckIn)
    }

    private enum CancelID {
        case healthUpdates
        case dashboardObservation
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

        Reduce { state, action in
            switch action {
            case .onAppear:
                BodySeekSignposts.shared.beginColdStartIfNeeded()
                do {
                    let loaded = try preferencesClient.load()
                    state.preferences = loaded
                    syncCheckInFromPreferences(into: &state)
                } catch {
                    state.today.lastError = "读取偏好设置失败：\(error.localizedDescription)"
                }
                return .merge(
                    loadCachedDashboardEffect(goalMinutes: state.preferences.sleepGoalMinutes, referenceDate: now),
                    loadSnapshotEffect(goalMinutes: state.preferences.sleepGoalMinutes, referenceDate: now),
                    loadFitnessStoreEffect(),
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
                if state.snapshot.historyDays.isEmpty
                    || !state.snapshot.isAuthorized
                    || cached.snapshot.historyDays.count >= state.snapshot.historyDays.count
                {
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
                    return .none
                }
                state.today.briefingStatus = .loading
                return .merge(
                    generateBriefingEffect(state: state),
                    triggerBackgroundBackfillEffect(goalMinutes: state.preferences.sleepGoalMinutes, referenceDate: now)
                )

            case let .persistenceFailed(message):
                state.today.lastError = message
                return .none

            case let .backgroundSyncCompleted(error):
                if let error {
                    state.today.lastError = error
                }
                return .none

            case let .fitnessStoreLoaded(templates, sessions, memories, messages, error):
                state.templates = templates
                state.sessions = sessions
                state.memories = memories
                state.workout.templates = templates
                state.workout.sessions = sessions
                state.coach.templates = templates
                state.coach.sessions = sessions
                state.coach.memories = memories
                if !messages.isEmpty {
                    state.coach.messages = messages
                }
                if let error {
                    state.workout.lastError = error
                }
                return .none

            case let .briefingGenerated(status):
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
                    state.todayPath.append(MetricDetailFeature.State(kind: kind, snapshot: state.snapshot))
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

                case .openSettings:
                    state.settings = SettingsFeature.State(
                        snapshot: state.snapshot,
                        preferences: state.preferences,
                        memories: state.memories
                    )
                    return .none

                case .openCheckIn:
                    state.isCheckInPresented = true
                    return .none

                case .regenerateBriefingRequested:
                    state.today.briefingStatus = .loading
                    return generateBriefingEffect(state: state)
                }

            // MARK: - Workout Delegates

            case let .workout(.delegate(delegate)):
                switch delegate {
                case let .sessionSaved(session):
                    state.sessions.insert(session, at: 0)
                    state.coach.sessions = state.sessions
                    if session.syncedHealthKitUUID != nil {
                        return loadSnapshotEffect(goalMinutes: state.preferences.sleepGoalMinutes, referenceDate: now)
                    }
                    return .none

                case let .templateSaved(template):
                    if let idx = state.templates.firstIndex(where: { $0.id == template.id }) {
                        state.templates[idx] = template
                    } else {
                        state.templates.insert(template, at: 0)
                    }
                    state.coach.templates = state.templates
                    return .none

                case let .askCoach(question):
                    return routeToCoach(question: question, state: &state)

                case .openTrends:
                    state.selectedTab = .trends
                    return .none
                }

            // MARK: - Trends & MetricDetail Delegates

            case let .trends(.delegate(.openMetric(kind, horizon))):
                state.trendsPath.append(MetricDetailFeature.State(kind: kind, snapshot: state.snapshot, horizon: horizon))
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
                    if state.settings != nil {
                        state.settings?.memories = memories
                    }
                    return .none

                case .openSettings:
                    state.settings = SettingsFeature.State(
                        snapshot: state.snapshot,
                        preferences: state.preferences,
                        memories: state.memories
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
                    state.preferences = updated
                    return loadSnapshotEffect(goalMinutes: updated.sleepGoalMinutes, referenceDate: now)

                case let .memoriesUpdated(memories):
                    state.memories = memories
                    state.coach.memories = memories
                    return .none

                case .allDataReset:
                    state.preferences = AppPreferencesState()
                    state.memories = []
                    state.sessions = []
                    state.templates = ExerciseCatalog.defaultTemplates
                    state.workout.sessions = []
                    state.workout.templates = ExerciseCatalog.defaultTemplates
                    state.coach.memories = []
                    state.coach.sessions = []
                    state.coach.templates = ExerciseCatalog.defaultTemplates
                    state.today.subjectiveFeeling = nil
                    state.today.todayCheckIn = nil
                    let emptySnapshot = BevelScoringEngine.computeWindow(
                        rawDays: PreviewSeedFactory.makeEmptyRawWindow(endingAt: now),
                        sleepGoalMinutes: state.preferences.sleepGoalMinutes,
                        referenceDate: now,
                        sourceLabel: "已重置",
                        isAuthorized: false
                    )
                    apply(snapshot: emptySnapshot, precomputedCache: nil, to: &state)
                    return loadSnapshotEffect(goalMinutes: state.preferences.sleepGoalMinutes, referenceDate: now)

                case .dismissed:
                    state.settings = nil
                    if state.snapshot.isAuthorized {
                        state.today.briefingStatus = .loading
                        return generateBriefingEffect(state: state)
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

            case .today, .workout, .trends, .coach, .todayPath, .trendsPath, .settings:
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

    private func loadCachedDashboardEffect(goalMinutes: Int, referenceDate: Date) -> Effect<Action> {
        .run { send in
            do {
                if let cached = try await bodySeekStoreClient.loadCachedDashboard(goalMinutes, referenceDate) {
                    await send(.cachedDashboardLoaded(cached))
                }
            } catch {
                await send(.persistenceFailed("读取离线生理缓存失败：\(error.localizedDescription)"))
            }
        }
    }

    private func loadSnapshotEffect(goalMinutes: Int, referenceDate: Date) -> Effect<Action> {
        .run { send in
            let snapshot = await healthKitClient.loadDashboardWindow(
                days: 60,
                sleepGoalMinutes: goalMinutes,
                referenceDate: referenceDate
            )
            await send(.snapshotLoaded(snapshot))
            if snapshot.isAuthorized {
                do {
                    try await bodySeekStoreClient.persistDashboardSnapshot(snapshot)
                } catch {
                    await send(.persistenceFailed("保存生理快照到数据库失败：\(error.localizedDescription)"))
                }
            }
        }
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
                _ = try await bodySeekStoreClient.syncRecentWindow(goalMinutes, referenceDate)
                _ = try await bodySeekStoreClient.runBackgroundBackfill(goalMinutes, referenceDate)
                await send(.backgroundSyncCompleted(nil))
            } catch {
                await send(.backgroundSyncCompleted("后台同步历史健康数据失败：\(error.localizedDescription)"))
            }
        }
    }

    private func loadFitnessStoreEffect() -> Effect<Action> {
        .run { send in
            do {
                let templates = try await fitnessStoreClient.loadTemplates()
                let sessions = try await fitnessStoreClient.loadSessions()
                let memories = try await fitnessStoreClient.loadMemories()
                let messages = try await fitnessStoreClient.loadMessages()
                await send(.fitnessStoreLoaded(
                    templates: templates,
                    sessions: sessions,
                    memories: memories,
                    messages: messages,
                    error: nil
                ))
            } catch {
                await send(.fitnessStoreLoaded(
                    templates: ExerciseCatalog.defaultTemplates,
                    sessions: [],
                    memories: [],
                    messages: [],
                    error: "读取本地训练仓库失败：\(error.localizedDescription)"
                ))
            }
        }
    }

    private func generateBriefingEffect(state: State) -> Effect<Action> {
        let context = AgentExecutionContext(
            snapshot: state.snapshot,
            sessions: state.sessions,
            templates: state.templates,
            memories: state.memories
        )
        return .run { send in
            let status = await coachAIClient.generateBriefing(context)
            await send(.briefingGenerated(status))
        }
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
        state.today.snapshot = snapshot
        syncCheckInFromPreferences(into: &state)
        state.workout.snapshot = snapshot
        state.trends.updateSnapshot(snapshot, precomputedCache: precomputedCache)
        state.coach.snapshot = snapshot
        if state.settings != nil {
            state.settings?.snapshot = snapshot
        }
        for id in state.todayPath.ids {
            state.todayPath[id: id]?.snapshot = snapshot
        }
        for id in state.trendsPath.ids {
            state.trendsPath[id: id]?.snapshot = snapshot
        }
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
