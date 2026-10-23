import SwiftUI
import SwiftData
import UIKit
import Observation

enum VelaNavigationVisibility {
    static func shouldShowBottomBar(keyboardVisible: Bool) -> Bool {
        !keyboardVisible
    }
}

enum VelaFloatingNavigationMetrics {
    static let barHeight: CGFloat = 58
    static let navBottomPadding: CGFloat = 14
    static let contentBottomPadding: CGFloat = 32
    static let coachComposerClearance: CGFloat = 116
}

enum VelaNavigationMotion {
    static let destinationFadeDuration = 0.16
}

// MARK: - BodySeek product navigation intent

/// UI-only intent types. These keep the product shell independent from
/// SwiftData, HealthKit and score computation. VelaAppState remains the
/// compatibility router at the composition root.
enum BodySeekDestination: Hashable, Sendable {
    case today
    case trends
    case plan
    case coach
    case profile
}

enum BodySeekQuickAction: Hashable, Sendable {
    case logLivedState
    case logWeight
    case logBlood
    case logWorkout
    case askCoach
}

enum BodySeekNavigationAction: Hashable, Sendable {
    case select(BodySeekDestination)
    case perform(BodySeekQuickAction)
    case presentProfile
}

extension EnvironmentValues {
    @Entry var velaSurfaceIsActive = true
}

@MainActor
private final class TodayLegacyRuntimeHolder: ObservableObject {
    var runtime: TodayLegacyRuntime?
}

// MARK: - VelaShell — Native iOS 26 Navigation with Legacy Fallback
//
// iOS 26 uses the system Liquid Glass tab bar and its native scroll minimization.
// Earlier releases keep the custom floating glass navigation.

struct VelaShell: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var services: VelaServices

    @State private var showPlusSheet = false
    @State private var showCoach     = false
    @State private var showTodayEvidence = false
    @State private var keyboardVisible = false
    @State private var showSidePanel = false
    @State private var showCoverage = false
    @State private var showMemory = false
    @State private var showInlineConversation = false
    @State private var inlineHeightOverride: CGFloat?
    @GestureState private var inlineResizeTranslation: CGFloat = 0
    @State private var composerDraft = BodySeekComposerDraft()
    @State private var mountedLegacyTabs: Set<VelaTab> = [.today]
    @State private var lastPresentedAppSheet: VelaAppState.AppSheet?
    @StateObject private var todayLegacyRuntimeHolder: TodayLegacyRuntimeHolder
    /// Cross-surface Today effects are composed here, next to the runtime
    /// bridge. The Today root does not dispatch navigation through both the
    /// Store and the legacy app state.
    private let todayEffectRouter: TodayLegacyEffectRouter
    /// TodayStore is a shell-owned dependency.  Keeping its identity at this
    /// composition boundary prevents tab-surface reevaluation from creating a
    /// second reader/load coordinator.
    @StateObject private var todayStore: TodayStore
    private let todayReader: LegacyTodayReadingModule

    @ObservedObject private var appState = VelaAppState.shared
    @EnvironmentObject private var dashboardVM: DashboardViewModel
    @Namespace private var tabAnimation

    // MARK: - Tab Enum

    enum VelaTab: Int, CaseIterable, Hashable {
        case today = 0
        case trends = 1
        case plan = 2
        case coach = 3
    }

    /// Rhythm's four canonical surfaces (Today, Trends, Plan, Coach) define the navigation.
    init() {
        let reader = LegacyTodayReadingModule()
        self.todayReader = reader
        let effectRouter = TodayLegacyEffectRouter()
        self.todayEffectRouter = effectRouter
        _todayStore = StateObject(
            wrappedValue: TodayStore(
                reader: reader,
                clock: SystemAppClock(),
                calendar: .current,
                effects: effectRouter
            )
        )
        _todayLegacyRuntimeHolder = StateObject(
            wrappedValue: TodayLegacyRuntimeHolder()
        )
    }

    /// Today receives its legacy compatibility dependencies from the shell's
    /// composition boundary. The surface itself stays unaware of SwiftData,
    /// location/weather singletons, app-state routing, and DashboardViewModel.
    private var todayLegacyRuntime: TodayLegacyRuntime {
        if let runtime = todayLegacyRuntimeHolder.runtime {
            runtime.bind(reader: todayReader, dashboardVM: dashboardVM)
            return runtime
        }

        let runtime = TodayLegacyRuntime(
            modelContext: modelContext,
            useCase: services.dailySummaryUseCase,
            appState: appState,
            locationManager: LocationManager.shared,
            fetchWeather: { latitude, longitude in
                try await WeatherService.shared.fetchWeather(
                    latitude: latitude,
                    longitude: longitude
                )
            },
            loadWeatherLocation: {
                WeatherLocationStore.load()
            },
            saveWeatherLocation: { snapshot in
                WeatherLocationStore.save(snapshot)
            },
            readCalorieTarget: {
                let value = UserDefaults.standard.integer(forKey: "vela_daily_calorie_target")
                return value > 0 ? value : nil
            }
        )
        todayEffectRouter.bind(runtime: runtime)
        todayLegacyRuntimeHolder.runtime = runtime
        runtime.bind(reader: todayReader, dashboardVM: dashboardVM)
        return runtime
    }

    // MARK: - Body

    var body: some View {
        navigationSurface
        .onReceive(appState.$showCoachHub) { show in
            if show {
                showPlusSheet = false
                showInlineConversation = true
                appState.showCoachHub = false
            }
        }
        .onChange(of: appState.showSettings) { _, shouldShow in
            guard shouldShow else { return }
            appState.showSettings = false
            appState.present(.settings)
        }
        .onChange(of: appState.presentedSheet) { _, sheet in
            if let sheet {
                lastPresentedAppSheet = sheet
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onChange(of: scenePhase) { _, phase in
            services.coachChat.handleAppActiveChange(isActive: phase == .active)
            if phase == .active {
                let ctx = modelContext
                Task { @MainActor in
                    await ProactiveIntelligenceOrchestrator().runAsyncCheck(modelContext: ctx)
                }
            }
        }
        .sheet(isPresented: $showPlusSheet, onDismiss: appState.runDeferredQuickAction) {
            PlusActionSheet()
                .presentationDetents([.medium])
                .velaSheetSurface()
        }
        .overlay(alignment: .bottom) {
            if showTodayEvidence {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture { showTodayEvidence = false }
                    TodayEvidenceSheet(
                        state: todayStore.state.command
                            ?? TodayViewState.unavailableCommand(for: todayStore.state.selectedDay),
                        dashboard: todayStore.state.dashboard,
                        onAskCoach: { question in
                            showTodayEvidence = false
                            appState.routeToCoach(question: question, surface: .home)
                        },
                        onClose: { showTodayEvidence = false }
                    )
                    .frame(maxHeight: .infinity)
                    .velaSheetSurface()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .accessibilityIdentifier("today-evidence-sheet")
            }
        }
        .fullScreenCover(isPresented: $showCoach) {
            VelaCoachView(
                presentation: .quickCover,
                selectedDate: todayStore.state.selectedDay,
                dashboard: dashboardVM.dashboard,
                onRestoreDraft: { composerDraft.text = $0 },
                vm: services.coachChat
            )
        }
        .sheet(item: $appState.presentedSheet, onDismiss: handleAppSheetDismissal) { sheet in
            appSheetContent(sheet)
        }
        .tint(VelaTheme.accent)
    }

    private func handleAppSheetDismissal() {
        if lastPresentedAppSheet?.refreshesLocalDataOnDismiss == true {
            appState.markLocalDataChanged()
        }
        lastPresentedAppSheet = nil
    }

    @ViewBuilder
    private func appSheetContent(_ sheet: VelaAppState.AppSheet) -> some View {
        switch sheet {
        case .settings:
            NavigationStack {
                VelaSettingsView(
                    dashboard: dashboardVM.dashboard,
                    onRefresh: {
                        await todayStore.send(.refresh(force: true))
                        await dashboardVM.refresh(modelContext: modelContext, force: true)
                    }
                )
            }
                .velaSheetSurface()
        case .weightLog:
            WeightLogSheetView()
                .velaSheetSurface()
        case .bloodLog:
            BloodLogSheetView()
                .presentationDetents([.medium, .large])
                .velaSheetSurface()
        case .workoutLog:
            WorkoutLogSheetView {
                await todayStore.send(.refresh(force: true))
                await dashboardVM.refresh(modelContext: modelContext, force: true)
            }
                .presentationDetents([.medium, .large])
                .velaSheetSurface()
        case .journal:
            NavigationStack {
                VelaJournalView(
                    selectedDate: todayStore.state.selectedDay,
                    onSelectDate: { day in
                        Task {
                            await todayStore.send(.selectDay(day))
                            todayLegacyRuntime.mirrorSelectedDayToLegacySurface(day)
                        }
                    }
                )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") { appState.dismissPresentedSheet() }
                                .font(.system(.subheadline, design: .default, weight: .semibold))
                                .foregroundStyle(VelaTheme.rhythmDeep)
                        }
                    }
            }
            .presentationDetents([.large])
            .velaSheetSurface()
        case .livedState:
            LivedStateCheckInSheet(selectedDate: todayStore.state.selectedDay) {}
                .presentationDetents([.large])
                .velaSheetSurface()
        case .recoveryDetail:
            NavigationStack {
                VelaMetricDetailView(
                    metric: .recovery,
                    selectedDate: todayStore.state.selectedDay,
                    dashboardSnapshot: todayStore.state.dashboard,
                    isPresentedInSheet: true
                )
            }
                .presentationDetents([.large])
                .velaSheetSurface()
        case .sleepDetail:
            NavigationStack {
                VelaMetricDetailView(
                    metric: .sleep,
                    selectedDate: todayStore.state.selectedDay,
                    dashboardSnapshot: todayStore.state.dashboard,
                    isPresentedInSheet: true
                )
            }
                .presentationDetents([.large])
                .velaSheetSurface()
        case .strainDetail:
            NavigationStack {
                VelaMetricDetailView(
                    metric: .strain,
                    selectedDate: todayStore.state.selectedDay,
                    dashboardSnapshot: todayStore.state.dashboard,
                    isPresentedInSheet: true
                )
            }
                .presentationDetents([.large])
                .velaSheetSurface()
        case .stressDetail:
            NavigationStack {
                VelaMetricDetailView(
                    metric: .stress,
                    selectedDate: todayStore.state.selectedDay,
                    dashboardSnapshot: todayStore.state.dashboard,
                    isPresentedInSheet: true
                )
            }
                .presentationDetents([.large])
                .velaSheetSurface()
        case .energyDetail:
            NavigationStack {
                VelaMetricDetailView(
                    metric: .energy,
                    selectedDate: todayStore.state.selectedDay,
                    dashboardSnapshot: todayStore.state.dashboard,
                    isPresentedInSheet: true
                )
            }
                .presentationDetents([.large])
                .velaSheetSurface()
        case let .postWorkoutCheckIn(workoutID):
            NavigationStack { PostWorkoutCheckInSheet(workoutID: workoutID) }
                .presentationDetents([.medium, .large])
                .velaSheetSurface()
        case let .postWorkoutImpact(workoutID):
            NavigationStack { PostWorkoutImpactSheet(workoutID: workoutID) }
                .presentationDetents([.medium, .large])
                .velaSheetSurface()
        }
    }

    @ViewBuilder
    private var navigationSurface: some View {
        // BodySeek owns one navigation grammar on every supported iOS
        // release. The system TabView is intentionally kept below as a
        // reference implementation while the product Dock is validated.
        legacyFloatingNavigation
    }

    @available(iOS 26.0, *)
    private var nativeTabNavigation: some View {
        TabView(selection: $appState.selectedTab) {
            nativeTabSurface(.today) {
                VelaTodayView(
                    showCoach: $showCoach,
                    showSettings: $appState.showSettings,
                    showEvidence: $showTodayEvidence,
                    todayStore: todayStore
                )
                    .environment(\.todayLegacyRuntime, todayLegacyRuntime)
            }
            .tabItem {
                Label(label(for: .today), systemImage: iconName(for: .today))
            }
            .tag(0)

            nativeTabSurface(.trends) {
                VelaTrendsHost(
                    selectedDate: todayStore.state.selectedDay,
                    dashboard: dashboardVM.dashboard
                )
            }
            .tabItem {
                Label(label(for: .trends), systemImage: iconName(for: .trends))
            }
            .tag(1)

            nativeTabSurface(.plan) {
                VelaPlanView(
                    selectedDate: todayStore.state.selectedDay,
                    dashboard: dashboardVM.dashboard,
                    dailyTrainingDecision: dashboardVM.dailyTrainingDecision,
                    onRefresh: {
                        await todayStore.send(.refresh(force: false))
                        await dashboardVM.refresh(modelContext: modelContext)
                    }
                )
            }
            .tabItem {
                Label(label(for: .plan), systemImage: iconName(for: .plan))
            }
            .tag(2)

            nativeTabSurface(.coach) {
                VelaCoachView(
                    presentation: .embedded,
                    selectedDate: todayStore.state.selectedDay,
                    dashboard: dashboardVM.dashboard,
                    onRefresh: {
                        await todayStore.send(.refresh(force: false))
                        await dashboardVM.refresh(modelContext: modelContext)
                    },
                    vm: services.coachChat
                )
            }
            .tabItem {
                Label(label(for: .coach), systemImage: iconName(for: .coach))
            }
            .tag(3)
        }
        // Perf: `tabBarMinimizeBehavior(.onScrollDown)` makes the tab bar track
        // the scroll offset on every frame. On iOS 26 that invalidates the whole
        // tab hierarchy (all four mounted tab roots re-evaluate their bodies
        // per frame), which is the dominant hitch source in DEBUG builds.
        // Remove the minimize behavior; the tab bar stays visible instead.
        // .tabBarMinimizeBehavior(.onScrollDown)
        .toolbar(keyboardVisible ? .hidden : .visible, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BodySeekBrandMark(size: 26, monochrome: true)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showPlusSheet = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("记录或提问")
                Button { appState.present(.settings) } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("个人档案")
            }
        }
    }

    private var legacyFloatingNavigation: some View {
        ZStack {
            VelaTheme.rhythmCanvas.ignoresSafeArea()

            // Mount each legacy surface on first visit, then preserve its navigation
            // and scroll state. This avoids eagerly initializing four SwiftData trees
            // at launch while keeping normal tab-return behavior after the first visit.
            ZStack {
                if mountedLegacyTabs.contains(.today) {
                    tabSurface(.today) {
                        VelaTodayView(
                            showCoach: $showCoach,
                            showSettings: $appState.showSettings,
                            showEvidence: $showTodayEvidence,
                            todayStore: todayStore
                        )
                            .environment(\.todayLegacyRuntime, todayLegacyRuntime)
                    }
                }
                if mountedLegacyTabs.contains(.trends) {
                    tabSurface(.trends) {
                        VelaTrendsHost(
                            selectedDate: todayStore.state.selectedDay,
                            dashboard: dashboardVM.dashboard
                        )
                    }
                }
                if mountedLegacyTabs.contains(.plan) {
                    tabSurface(.plan) {
                        VelaPlanView(
                            selectedDate: todayStore.state.selectedDay,
                            dashboard: dashboardVM.dashboard,
                            dailyTrainingDecision: dashboardVM.dailyTrainingDecision,
                            onRefresh: {
                                await todayStore.send(.refresh(force: false))
                                await dashboardVM.refresh(modelContext: modelContext)
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            if showInlineConversation {
                GeometryReader { geometry in
                    let contentHeight: CGFloat = services.coachChat.messages.isEmpty ? 270 : 420
                    let limit = max(160, geometry.size.height * 0.9)
                    let base = min(limit, inlineHeightOverride ?? contentHeight)
                    let height = min(limit, max(160, base - inlineResizeTranslation))
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VelaCoachView(
                            presentation: .inline,
                            selectedDate: todayStore.state.selectedDay,
                            dashboard: dashboardVM.dashboard,
                            onClose: { showInlineConversation = false },
                            onExpand: {
                                services.coachChat.draft = composerDraft.text
                                composerDraft.text = ""
                                showInlineConversation = false
                                showCoach = true
                            },
                            onRestoreDraft: { composerDraft.text = $0 },
                            coverage: todayStore.state.coverage,
                            inlineSuggestions: askSuggestions,
                            vm: services.coachChat
                        )
                        .padding(.top, 10)
                        .frame(height: height)
                        .overlay(alignment: .top) {
                            Capsule().fill(VelaTheme.rhythmMist)
                                .frame(width: 34, height: 4)
                                .frame(width: 96, height: 16)
                                .contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 6)
                                    .updating($inlineResizeTranslation) { value, state, _ in state = value.translation.height }
                                    .onEnded { value in inlineHeightOverride = min(limit, max(160, base - value.translation.height)) })
                                .accessibilityLabel("调整对话高度")
                                .accessibilityAdjustableAction { direction in
                                    inlineHeightOverride = min(limit, max(160, base + (direction == .increment ? 80 : -80)))
                                }
                        }
                        .background(VelaTheme.rhythmCanvas)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(VelaTheme.hairline, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.10), radius: 18, y: -4)
                        .accessibilityIdentifier("inline-coach-panel")
                    }
                    .padding(.horizontal, VelaTheme.pagePadding)
                    .padding(.bottom, 4)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if appState.detailAskContext == nil {
                segmentedHeader
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            askBar
                .padding(.horizontal, VelaTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(VelaTheme.rhythmCanvas)
        }
        .overlay {
            if showSidePanel {
                sidePanel
            }
        }
        .sheet(isPresented: $showCoverage) {
            NavigationStack { DataCoverageView() }
                .velaSheetSurface()
        }
        .sheet(isPresented: $showMemory) {
            NavigationStack { WikiProfileView() }
                .velaSheetSurface()
        }
        .onAppear {
            openCoachTabIfNeeded(appState.selectedTab, previous: VelaTab.today.rawValue)
            mountedLegacyTabs = VelaLegacySurfaceMountPolicy.including(
                selectedTab: appState.selectedTab,
                in: mountedLegacyTabs
            )
        }
        .onChange(of: appState.selectedTab) { previous, selectedTab in
            if previous != VelaTab.coach.rawValue && selectedTab != VelaTab.coach.rawValue {
                showInlineConversation = false
            }
            openCoachTabIfNeeded(selectedTab, previous: previous)
            mountedLegacyTabs = VelaLegacySurfaceMountPolicy.including(
                selectedTab: appState.selectedTab,
                in: mountedLegacyTabs
            )
        }
    }

    private func openCoachTabIfNeeded(_ selectedTab: Int, previous: Int) {
        guard selectedTab == VelaTab.coach.rawValue else { return }
        showInlineConversation = true
        let fallback = previous == VelaTab.coach.rawValue ? VelaTab.today.rawValue : previous
        if appState.selectedTab != fallback {
            appState.selectedTab = fallback
        }
    }

    private var segmentedHeader: some View {
        HStack(spacing: 8) {
            Button {
                showSidePanel = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(VelaTheme.surfaceFloating))
            }
            .accessibilityLabel("菜单")
            .accessibilityIdentifier("bodyseek-menu")

            HStack(spacing: 0) {
                segmentButton(.today)
                segmentButton(.trends)
                segmentButton(.plan)
            }
            .padding(3)
            .background(Capsule().fill(VelaTheme.surfaceFloating))

            Button {
                appState.present(.settings)
            } label: {
                Image(systemName: "person")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(VelaTheme.surfaceFloating))
            }
            .accessibilityLabel("个人档案")
        }
        .padding(.horizontal, VelaTheme.pagePadding)
        .padding(.vertical, 6)
        .background(VelaTheme.rhythmCanvas)
    }

    private func segmentButton(_ tab: VelaTab) -> some View {
        let isActive = appState.selectedTab == tab.rawValue
        return Button {
            appState.selectedTab = tab.rawValue
        } label: {
            Text(label(for: tab))
                .font(VelaTheme.subheadline().weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? VelaTheme.rhythmInk : VelaTheme.rhythmInkSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    if isActive {
                        Capsule().fill(VelaTheme.segmentOn)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(label(for: tab))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier("tab-\(tab.rawValue)")
    }

    private var askContext: BodySeekAskContext {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        let day = formatter.string(from: todayStore.state.selectedDay)
        if let detail = appState.detailAskContext {
            return BodySeekAskContext(chip: "\(detail.title)详情", items: [
                "\(day)的\(detail.title)读数、依据与数据覆盖",
                "\(detail.title)的个人基线与近期变化",
                "今天的五项状态，用于联系其他信号"
            ])
        }
        switch appState.selectedTab {
        case VelaTab.trends.rawValue:
            let horizon = appState.visibleTrendHorizon
            return BodySeekAskContext(chip: "\(horizon.title)趋势", items: [
                "时间窗口：\(horizon.detailedTitle)（截至\(day)）",
                "五项分数在这个窗口的趋势结果与有效天数",
                "当前个人基线与偏离"
            ])
        case VelaTab.plan.rawValue:
            return BodySeekAskContext(chip: "今日计划", items: [
                "\(day)计划里的每一项、顺序与完成情况",
                "今天的五项状态与训练决定",
                "改动计划前会先给出候选，确认后才生效"
            ])
        default:
            return BodySeekAskContext(chip: "今日数据", items: [
                "日期：\(day)",
                "五项分数、个人基线与偏离",
                "今日计划与完成情况",
                "数据覆盖与新鲜度"
            ])
        }
    }

    private var askSuggestions: [String] {
        let dashboard = todayStore.state.dashboard
        var deviations: [String: String] = [:]
        for finding in dashboard.personalHealthBrief?.notableChanges ?? [] {
            guard finding.isNotable, let id = finding.metric.todayScoreRingID else { continue }
            deviations[id] = BaselineDeviationCopy.label(for: finding) ?? ""
        }
        let readings = ScoreInstrumentReading.make(
            cardValues: [
                "recovery": dashboard.recovery.formattedScore,
                "sleep": dashboard.sleepScore.formattedScore,
                "strain": dashboard.strain.formattedScore,
                "stress": dashboard.stress.formattedScore,
                "energy": dashboard.energy.formattedScore
            ],
            deviations: deviations,
            findings: dashboard.healthTrends
        )
        let nextAction = todayStore.state.operatingPlanPayload?.allActions
            .first(where: { $0.completedAt == nil })?.title
        return BodySeekAskSuggestions.make(
            surface: askSurface,
            horizonTitle: appState.visibleTrendHorizon.title,
            readings: readings,
            nextActionTitle: nextAction,
            hasPendingProposal: todayStore.state.pendingPlan != nil,
            detailTitle: appState.detailAskContext?.title
        )
    }

    private var askPlaceholder: String {
        if let detail = appState.detailAskContext?.askPlaceholder {
            return detail
        }
        if appState.selectedTab == VelaTab.plan.rawValue {
            return "调整今天的安排…"
        }
        return "问问你的身体…"
    }

    private var askSurface: CoachScreenSurface {
        if appState.detailAskContext != nil { return .metricDetail }
        switch appState.selectedTab {
        case VelaTab.trends.rawValue: return .trends
        case VelaTab.plan.rawValue: return .plan
        default: return .home
        }
    }

    private var askBar: some View {
        BodySeekAskComposer(
            placeholder: askPlaceholder,
            context: askContext,
            isExpanded: $showInlineConversation,
            draftState: composerDraft,
            vm: services.coachChat,
            onAdd: { showPlusSheet = true },
            onSend: sendAskDraft
        )
    }

    private func sendAskDraft(_ question: String) {
        appState.routeToQuickCoach(
            question: question,
            surface: askSurface
        )
    }

    private var sidePanel: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { showSidePanel = false }
            VStack(alignment: .leading, spacing: 8) {
                Text("BodySeek")
                    .font(VelaTheme.title2())
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .padding(.bottom, 12)
                sidePanelButton("新对话", systemImage: "bubble.left") {
                    showSidePanel = false
                    appState.routeToQuickCoach(question: nil, surface: askSurface)
                }
                sidePanelButton("记忆", systemImage: "brain") {
                    showSidePanel = false
                    showMemory = true
                }
                sidePanelButton("数据覆盖", systemImage: "checkmark.shield") {
                    showSidePanel = false
                    showCoverage = true
                }
                sidePanelButton("设置", systemImage: "gearshape") {
                    showSidePanel = false
                    appState.present(.settings)
                }
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 300, maxHeight: .infinity, alignment: .topLeading)
            .background(VelaTheme.rhythmCanvas)
            .overlay(alignment: .trailing) {
                Rectangle().fill(VelaTheme.hairline).frame(width: 1)
            }
        }
        .accessibilityIdentifier("bodyseek-side-panel")
    }

    private func sidePanelButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                Text(title)
                    .font(VelaTheme.body())
                Spacer()
            }
            .foregroundStyle(VelaTheme.rhythmInk)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Legacy Floating Glass Navigation
    
    private var bodySeekDock: some View {
        HStack(spacing: 5) {
            customTabButton(.today)
            customTabButton(.trends)
            Button { showPlusSheet = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmDeepOn)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(VelaTheme.rhythmDeep))
            }
            .accessibilityLabel("记录或提问")
            customTabButton(.plan)
            customTabButton(.coach)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            dockBackground
        }
        .padding(.horizontal, 14)
        // Navigation chrome has a fixed hit-target grid; reading content keeps
        // the user's full Dynamic Type size inside each destination.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    @ViewBuilder
    private var dockBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .overlay(
                shape
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.5),
                                Color.white.opacity(colorScheme == .dark ? 0.02 : 0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
    }

    // MARK: - Individual Tab Button with Premium Sliding Highlight

    private func tabSurface<Content: View>(
        _ tab: VelaTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isActive = VelaTabSelection.isActive(tab, selectedTab: appState.selectedTab)
        return NavigationStack {
            content()
        }
        .environment(\.velaSurfaceIsActive, isActive)
        .accessibilityIdentifier("surface-\(tab.rawValue)")
        .opacity(isActive ? 1 : 0)
        .allowsHitTesting(isActive)
        .accessibilityHidden(!isActive)
        .zIndex(isActive ? 1 : 0)
        .animation(
            .easeOut(duration: reduceMotion ? 0.12 : VelaNavigationMotion.destinationFadeDuration),
            value: isActive
        )
    }

    private func customTabButton(_ tab: VelaTab) -> some View {
        let isActive = appState.selectedTab == tab.rawValue
        return Button {
            guard !isActive else { return }
            withAnimation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion)) {
                appState.selectedTab = tab.rawValue
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: iconName(for: tab))
                    .font(.system(size: 17, weight: isActive ? .semibold : .regular))
                    .frame(height: 22)
                Text(label(for: tab))
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(isActive ? VelaTheme.fg : VelaTheme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                ZStack {
                    if isActive {
                        if reduceMotion {
                            Capsule(style: .continuous)
                                .fill(VelaTheme.accent.opacity(0.10))
                        } else {
                            Capsule(style: .continuous)
                                .fill(VelaTheme.accent.opacity(0.10))
                                .matchedGeometryEffect(id: "activeTabHighlight", in: tabAnimation)
                        }
                    }
                }
            )
        }
        .buttonStyle(.tabItem)
        .accessibilityLabel(label(for: tab))
        .accessibilityValue(isActive ? L10n.t("Selected", "已选中") : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityIdentifier("tab-\(tab.rawValue)")
    }

    private func iconName(for tab: VelaTab) -> String {
        switch tab {
        case .today:    "sun.max"
        case .trends:   "waveform.path.ecg"
        case .plan:     "checklist"
        case .coach:    "sparkles"
        }
    }

    private func label(for tab: VelaTab) -> String {
        switch tab {
        case .today:    L10n.t("Today", "今日")
        case .trends:   L10n.t("Trends", "趋势")
        case .plan:     L10n.t("Plan", "计划")
        case .coach:    L10n.t("Coach", "教练")
        }
    }

    private var bottomBarTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    @ViewBuilder
    private func nativeTabSurface<Content: View>(
        _ tab: VelaTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            content()
        }
        .environment(\.velaSurfaceIsActive, appState.selectedTab == tab.rawValue)
        .accessibilityIdentifier("surface-\(tab.rawValue)")
    }
}

enum VelaTabSelection {
    struct Result {
        var selectedTab: VelaShell.VelaTab
        var shouldPresentQuickActions: Bool
    }

    static let contentTabs: [VelaShell.VelaTab] = [.today, .trends, .plan, .coach]

    static func isActive(_ tab: VelaShell.VelaTab, selectedTab: Int) -> Bool {
        tab.rawValue == selectedTab
    }

    static func resolve(
        candidate: VelaShell.VelaTab,
        current: VelaShell.VelaTab
    ) -> Result {
        Result(selectedTab: candidate, shouldPresentQuickActions: false)
    }

}

enum VelaLegacySurfaceMountPolicy {
    static func including(
        selectedTab: Int,
        in mountedTabs: Set<VelaShell.VelaTab>
    ) -> Set<VelaShell.VelaTab> {
        guard let selected = VelaShell.VelaTab(rawValue: selectedTab) else {
            return mountedTabs
        }
        return mountedTabs.union([selected])
    }
}

/// Keystrokes and speech partials invalidate this small composer, rather than
/// rebuilding the shell and every mounted health page on each character.
@Observable @MainActor
private final class BodySeekComposerDraft {
    var text = ""
}

/// What the next question carries, stated before anything is sent.
struct BodySeekAskContext: Equatable {
    let chip: String
    let items: [String]
}

private struct BodySeekAskComposer: View {
    let placeholder: String
    let context: BodySeekAskContext
    @Binding var isExpanded: Bool
    @Bindable var draftState: BodySeekComposerDraft
    @ObservedObject var vm: CoachChatVM
    let onAdd: () -> Void
    let onSend: (String) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lastDictationApplied: String?
    @State private var showContext = false
    @StateObject private var dictation = CoachDictationController()
    @FocusState private var isFocused: Bool

    private var draft: String {
        get { draftState.text }
        nonmutating set { draftState.text = newValue }
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// One quiet line while idle; two lines once there is something to send,
    /// to stop, or to dictate into.
    private var isCompact: Bool {
        !isFocused && draft.isEmpty && !dictation.isRecording && !dictation.isStarting && !vm.isStreaming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 6) {
                if isCompact {
                    if vm.messages.isEmpty { addButton } else { resumeButton }
                }
                // The field keeps one position in the tree so focus survives
                // the compact → expanded switch.
                TextField(placeholder, text: $draftState.text, axis: .vertical)
                    .font(VelaTheme.callout())
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .lineLimit(isCompact ? 1...1 : 1...5)
                    .frame(minHeight: isCompact ? 40 : 28)
                    .padding(.horizontal, isCompact ? 2 : 4)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .accessibilityIdentifier("bodyseek-ask-input")
                if isCompact {
                    contextChip
                    micButton
                }
            }

            if !isCompact {
                HStack(spacing: 6) {
                    addButton
                    contextChip
                    Spacer(minLength: 0)
                    micButton
                    trailingAction
                }
            }

            if dictation.isRecording {
                Label("正在听写 · 停止后可编辑，再点发送", systemImage: "waveform")
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .padding(.leading, 4)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, isCompact ? 6 : 10)
        .background(VelaTheme.surfaceFloating, in: RoundedRectangle(cornerRadius: VelaTheme.radiusInput, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusInput, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: 1)
        }
        .animation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion), value: isCompact)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bodyseek-ask-composer")
        .sheet(isPresented: $showContext) {
            BodySeekAskContextSheet(context: context)
                .presentationDetents([.medium])
                .velaSheetSurface()
        }
        .onChange(of: isFocused) { _, focused in
            if focused { isExpanded = true }
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { isFocused = false; dictation.stop() }
        }
        .onChange(of: dictation.transcript) { _, transcript in
            if lastDictationApplied == nil || draft == lastDictationApplied {
                draft = transcript
                lastDictationApplied = transcript
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || (phase != .active && dictation.isRecording) { dictation.stop() }
        }
        .onDisappear { dictation.stop() }
        .alert("听写不可用", isPresented: Binding(
            get: { dictation.errorMessage != nil },
            set: { if !$0 { dictation.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { dictation.errorMessage = nil }
        } message: {
            Text(dictation.errorMessage ?? "")
        }
    }

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !vm.isStreaming else { return }
        dictation.stop()
        draft = ""
        lastDictationApplied = nil
        isFocused = false
        isExpanded = true
        onSend(question)
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(VelaTheme.rhythmInk)
                .frame(width: 40, height: 40)
                .background(VelaTheme.rhythmCanvas, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("记录")
    }

    private var contextChip: some View {
        Button { showContext = true } label: {
            HStack(spacing: 3) {
                Text(context.chip)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .font(VelaTheme.caption1().weight(.medium))
            .foregroundStyle(VelaTheme.rhythmInkSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(VelaTheme.rhythmCanvas, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .fixedSize()
        }
        .accessibilityLabel("本次提问带上：\(context.chip)")
        .accessibilityHint("查看这次提问会使用哪些数据")
        .accessibilityIdentifier("bodyseek-context")
    }

    private var resumeButton: some View {
        Button { isExpanded = true } label: {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(VelaTheme.rhythmInk)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("继续对话")
    }

    private var micButton: some View {
        Button {
            if dictation.isRecording || dictation.isStarting {
                dictation.stop()
            } else {
                lastDictationApplied = draft
                dictation.begin(existingText: draft)
            }
        } label: {
            Group {
                if dictation.isStarting { ProgressView().controlSize(.small) }
                else { Image(systemName: dictation.isRecording ? "stop.fill" : "mic") }
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(dictation.isRecording ? VelaTheme.rhythmDeepOn : VelaTheme.rhythmInk)
            .frame(width: 40, height: 40)
            .background(dictation.isRecording ? VelaTheme.rhythmDeep : VelaTheme.rhythmCanvas, in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(dictation.isRecording ? "停止听写" : dictation.isStarting ? "取消听写" : "说话")
        .accessibilityIdentifier("bodyseek-speak")
    }

    @ViewBuilder
    private var trailingAction: some View {
        if vm.isStreaming {
            Button { vm.cancelActiveResponse() } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(VelaTheme.rhythmDeepOn)
                    .background(VelaTheme.rhythmDeep, in: Circle())
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("停止回复")
        } else if canSend {
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(VelaTheme.rhythmDeepOn)
                    .background(VelaTheme.rhythmDeep, in: Circle())
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("发送")
            .accessibilityIdentifier("bodyseek-send")
        } else if !isExpanded, !vm.messages.isEmpty {
            resumeButton
        }
    }
}

private struct BodySeekAskContextSheet: View {
    let context: BodySeekAskContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("本次提问的上下文")
                    .font(VelaTheme.headline())
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Button("关闭") { dismiss() }
                    .font(VelaTheme.subheadline().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .frame(minHeight: 44)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(context.items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Text(item)
                            .font(VelaTheme.subheadline())
                            .foregroundStyle(VelaTheme.rhythmInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("分数在本机计算。联网 AI 需要你先授权，只接收裁剪后的结构化摘要，不上传原始 Apple 健康样本。")
                .font(VelaTheme.footnote())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(24)
        .accessibilityIdentifier("bodyseek-context-sheet")
    }
}
