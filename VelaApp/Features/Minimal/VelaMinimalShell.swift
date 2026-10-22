import SwiftUI
import SwiftData
import UIKit

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
    @State private var askDraft = ""
    @StateObject private var dictation = CoachDictationController()
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
                showCoach = true
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
            withAnimation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion)) {
                keyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(VelaTheme.interfaceAnimation(reduceMotion: reduceMotion)) {
                keyboardVisible = false
            }
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
                onRefresh: {
                    await todayStore.send(.refresh(force: false))
                    await dashboardVM.refresh(modelContext: modelContext)
                },
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
        .safeAreaInset(edge: .top, spacing: 0) {
            segmentedHeader
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
            openCoachTabIfNeeded(selectedTab, previous: previous)
            mountedLegacyTabs = VelaLegacySurfaceMountPolicy.including(
                selectedTab: appState.selectedTab,
                in: mountedLegacyTabs
            )
        }
        .onChange(of: dictation.transcript) { _, transcript in
            if dictation.isRecording {
                askDraft = transcript
            }
        }
    }

    private func openCoachTabIfNeeded(_ selectedTab: Int, previous: Int) {
        guard selectedTab == VelaTab.coach.rawValue else { return }
        showCoach = true
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

    private var askContextTitle: String {
        switch appState.selectedTab {
        case VelaTab.trends.rawValue: return "带上趋势"
        case VelaTab.plan.rawValue: return "带上计划"
        default: return "带上今日数据"
        }
    }

    private var askSurface: CoachScreenSurface {
        switch appState.selectedTab {
        case VelaTab.trends.rawValue: return .trends
        case VelaTab.plan.rawValue: return .plan
        default: return .home
        }
    }

    private var askBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("问问你的身体…", text: $askDraft, axis: .vertical)
                .font(VelaTheme.callout())
                .foregroundStyle(VelaTheme.rhythmInk)
                .lineLimit(1...3)
                .onSubmit(sendAskDraft)
            HStack(spacing: 8) {
                Button { showPlusSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .frame(width: 44, height: 36)
                        .background(Capsule().fill(VelaTheme.rhythmCanvas))
                }
                .accessibilityLabel("记录")

                Text(askContextTitle)
                    .font(VelaTheme.caption1())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(Capsule().fill(VelaTheme.rhythmCanvas))

                Spacer(minLength: 8)

                Button(action: toggleSpeech) {
                    HStack(spacing: 6) {
                        Image(systemName: dictation.isRecording ? "stop.fill" : "waveform")
                        Text(dictation.isRecording ? "停止" : "说话")
                    }
                    .font(VelaTheme.subheadline().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmDeepOn)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Capsule().fill(VelaTheme.rhythmDeep))
                }
                .accessibilityLabel(dictation.isRecording ? "停止听写" : "说话")
                .accessibilityIdentifier("bodyseek-speak")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: VelaTheme.radiusInput, style: .continuous)
                .fill(VelaTheme.surfaceFloating)
        )
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusInput, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: 1)
        )
    }

    private func toggleSpeech() {
        if dictation.isRecording {
            dictation.stop()
            sendAskDraft()
            return
        }
        let pending = askDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pending.isEmpty {
            sendAskDraft()
            return
        }
        dictation.begin(existingText: "")
    }

    private func sendAskDraft() {
        let question = askDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        askDraft = ""
        dictation.transcript = ""
        appState.routeToQuickCoach(
            question: question.isEmpty ? nil : question,
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
