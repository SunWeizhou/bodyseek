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
    @EnvironmentObject private var services: VelaServices

    @State private var showPlusSheet = false
    @State private var showCoach     = false
    @State private var showTodayEvidence = false
    @State private var keyboardVisible = false
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
    /// composition boundary.  The surface itself stays unaware of SwiftData,
    /// location/weather singletons, and app-state routing objects.
    private var todayLegacyRuntime: TodayLegacyRuntime {
        if let runtime = todayLegacyRuntimeHolder.runtime {
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
            VelaCoachView(presentation: .quickCover, vm: services.coachChat)
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
            NavigationStack { VelaSettingsView() }
                .velaSheetSurface()
        case .weightLog:
            WeightLogSheetView()
                .velaSheetSurface()
        case .bloodLog:
            BloodLogSheetView()
                .presentationDetents([.medium, .large])
                .velaSheetSurface()
        case .workoutLog:
            WorkoutLogSheetView()
                .presentationDetents([.medium, .large])
                .velaSheetSurface()
        case .journal:
            NavigationStack {
                VelaJournalView()
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
                    todayStore: todayStore,
                    todayReader: todayReader
                )
                    .environment(\.todayLegacyRuntime, todayLegacyRuntime)
            }
            .tabItem {
                Label(label(for: .today), systemImage: iconName(for: .today))
            }
            .tag(0)

            nativeTabSurface(.trends) {
                VelaTrendsView()
            }
            .tabItem {
                Label(label(for: .trends), systemImage: iconName(for: .trends))
            }
            .tag(1)

            nativeTabSurface(.plan) {
                VelaPlanView()
            }
            .tabItem {
                Label(label(for: .plan), systemImage: iconName(for: .plan))
            }
            .tag(2)

            nativeTabSurface(.coach) {
                VelaCoachView(presentation: .embedded, vm: services.coachChat)
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
                            todayStore: todayStore,
                            todayReader: todayReader
                        )
                            .environment(\.todayLegacyRuntime, todayLegacyRuntime)
                    }
                }
                if mountedLegacyTabs.contains(.trends) {
                    tabSurface(.trends) {
                        VelaTrendsView()
                    }
                }
                if mountedLegacyTabs.contains(.plan) {
                    tabSurface(.plan) {
                        VelaPlanView()
                    }
                }
                if mountedLegacyTabs.contains(.coach) {
                    tabSurface(.coach) {
                        VelaCoachView(
                            presentation: .embedded,
                            usesOverlayNavigation: true,
                            vm: services.coachChat
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if VelaNavigationVisibility.shouldShowBottomBar(keyboardVisible: keyboardVisible) {
                bodySeekDock
                    .padding(.top, 6)
                    .padding(.bottom, VelaFloatingNavigationMetrics.navBottomPadding)
                    .transition(bottomBarTransition)
            }
        }
        .onAppear {
            mountedLegacyTabs = VelaLegacySurfaceMountPolicy.including(
                selectedTab: appState.selectedTab,
                in: mountedLegacyTabs
            )
        }
        .onChange(of: appState.selectedTab) { _, selectedTab in
            mountedLegacyTabs = VelaLegacySurfaceMountPolicy.including(
                selectedTab: selectedTab,
                in: mountedLegacyTabs
            )
        }
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
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(VelaTheme.cardBg.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(VelaTheme.rhythmMist.opacity(0.7), lineWidth: 0.7)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 8)
        .padding(.horizontal, 14)
        // Navigation chrome has a fixed hit-target grid; reading content keeps
        // the user's full Dynamic Type size inside each destination.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
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
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(VelaTheme.accent.opacity(0.08))
                        } else {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(VelaTheme.accent.opacity(0.08))
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
