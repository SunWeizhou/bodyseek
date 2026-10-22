import SwiftUI
import SwiftData
import BackgroundTasks
import AppIntents
import UserNotifications
import os.log


private let logger = Logger(subsystem: "com.sunweizhou.Vela", category: "App")
@MainActor
final class VelaAppState: ObservableObject {
    static let todayTabIndex = 0
    static let trendsTabIndex = 1
    static let planTabIndex = 2
    static let coachTabIndex = 3
    /// Compatibility alias for older deep links. Training now lives inside Plan.
    static let trainingTabIndex = planTabIndex
    static let meTabIndex = 3
    nonisolated private static let validTabIndices = 0...3

    enum CoachRouteDestination {
        case embedded
        case quickCover
    }

    struct DetailAskContext: Equatable {
        var title: String
        var askPlaceholder: String
        var contextTitle: String
    }

    enum DeferredQuickAction: Equatable {
        case coach(String?)
        case foodScanner(String)
        case foodSearch
        case workoutLog
        case weightLog
        case bloodLog
        case journal
    }

    enum AppSheet: Identifiable, Equatable {
        case settings
        case weightLog
        case bloodLog
        case workoutLog
        case journal
        case livedState
        case recoveryDetail
        case sleepDetail
        case strainDetail
        case stressDetail
        case energyDetail
        case postWorkoutCheckIn(UUID?)
        case postWorkoutImpact(UUID?)

        var id: String {
            switch self {
            case .settings: "settings"
            case .weightLog: "weight-log"
            case .bloodLog: "blood-log"
            case .workoutLog: "workout-log"
            case .journal: "journal"
            case .livedState: "lived-state"
            case .recoveryDetail: "recovery-detail"
            case .sleepDetail: "sleep-detail"
            case .strainDetail: "strain-detail"
            case .stressDetail: "stress-detail"
            case .energyDetail: "energy-detail"
            case let .postWorkoutCheckIn(id): "post-workout-check-in-\(id?.uuidString ?? "latest")"
            case let .postWorkoutImpact(id): "post-workout-impact-\(id?.uuidString ?? "latest")"
            }
        }

        var refreshesLocalDataOnDismiss: Bool {
            switch self {
            case .weightLog, .bloodLog, .workoutLog, .journal, .livedState, .postWorkoutCheckIn:
                true
            case .settings, .recoveryDetail, .sleepDetail, .strainDetail, .stressDetail, .energyDetail, .postWorkoutImpact:
                false
            }
        }
    }

    @Published var isFallbackStore = false
    @Published var isReadOnlySafetyMode = false
    @Published var selectedTab = VelaAppState.todayTabIndex
    @Published var showCoachHub = false
    /// Compatibility binding used by existing Today subviews. VelaShell consumes it
    /// into `presentedSheet` immediately so only one app sheet can be active.
    @Published var showSettings = false
    @Published var presentedSheet: AppSheet?
    /// Set while a metric detail is on screen so the shell keeps the ask bar
    /// and drops the 今日 / 趋势 / 计划 header.
    @Published var detailAskContext: DetailAskContext?
    @Published var prefilledCoachQuestion: String? = nil
    @Published var homeNavigationStackId = UUID()
    
    // Quick Actions Triggers
    @Published var triggerFoodCamera = false
    @Published var triggerFoodLibrary = false
    @Published var triggerFoodSearch = false
    @Published var triggerFoodScanner = false
    @Published var scannerType = "camera"
    @Published var forceNewCoachSession = false
    @Published private(set) var coachRouteDestination: CoachRouteDestination?
    @Published private(set) var coachRouteSurface: CoachScreenSurface = .coach
    @Published private(set) var coachRouteRevision = 0
    @Published private(set) var localDataRevision = 0
    @Published private(set) var adaptiveTrainingStartRequest = 0
    @Published private(set) var deferredQuickAction: DeferredQuickAction?
    
    static let shared = VelaAppState()

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if DEBUG
        selectedTab = Self.initialTab(from: arguments)
        if arguments.contains("-velaOpenCoach") {
            showCoachHub = true
        } else if arguments.contains("-velaOpenRecoveryDetail") {
            presentedSheet = .recoveryDetail
        } else if arguments.contains("-velaOpenSleepDetail") {
            presentedSheet = .sleepDetail
        } else if arguments.contains("-velaOpenStrainDetail") {
            presentedSheet = .strainDetail
        } else if arguments.contains("-velaOpenStressDetail") {
            presentedSheet = .stressDetail
        } else if arguments.contains("-velaOpenEnergyDetail") {
            presentedSheet = .energyDetail
        } else if arguments.contains("-velaOpenSettings") {
            presentedSheet = .settings
        } else if arguments.contains("-velaOpenLivedStateCheckIn") {
            presentedSheet = .livedState
        }
        #endif
    }

    nonisolated static func initialTab(from arguments: [String]) -> Int {
        guard let flagIndex = arguments.firstIndex(of: "-velaInitialTab"),
              arguments.indices.contains(arguments.index(after: flagIndex)),
              let tab = Int(arguments[arguments.index(after: flagIndex)]),
              validTabIndices.contains(tab) else {
            return 0
        }
        return tab
    }

    func routeToCoach(
        question: String?,
        surface: CoachScreenSurface = .coach
    ) {
        prepareCoachRoute(question: question, surface: surface)
        coachRouteDestination = .embedded
        showCoachHub = false
        selectedTab = Self.coachTabIndex
        coachRouteRevision += 1
    }

    func routeToQuickCoach(
        question: String?,
        surface: CoachScreenSurface = .coach
    ) {
        prepareCoachRoute(question: question, surface: surface)
        coachRouteDestination = .quickCover
        coachRouteRevision += 1
        showCoachHub = true
    }

    private func prepareCoachRoute(
        question: String?,
        surface: CoachScreenSurface
    ) {
        coachRouteSurface = surface
        if let question = question {
            prefilledCoachQuestion = question
            forceNewCoachSession = false
        } else {
            prefilledCoachQuestion = nil
            forceNewCoachSession = true
        }
    }

    func logDebug(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    func routeToTab(_ tab: Int) {
        guard Self.validTabIndices.contains(tab) else {
            logDebug("[VelaAppState] ignored invalid tab route \(tab)")
            return
        }
        selectedTab = tab
    }

    func routeToToday() {
        routeToTab(Self.todayTabIndex)
    }

    func routeToTrends() {
        routeToTab(Self.trendsTabIndex)
    }

    func routeToPlan() {
        routeToTab(Self.planTabIndex)
    }

    func routeToTraining() {
        routeToPlan()
    }

    func routeToMe() {
        present(.settings)
    }

    func routeToAdaptiveTrainingStart() {
        resetQuickActionSheetTriggers()
        selectedTab = Self.planTabIndex
        adaptiveTrainingStartRequest += 1
    }

    func routeToFoodScanner(type: String) {
        resetQuickActionSheetTriggers()
        scannerType = type
        triggerFoodScanner = true
    }

    func routeToRecoveryDetail() {
        present(.recoveryDetail)
    }

    func routeToPostWorkoutCheckIn(workoutID: UUID?) {
        present(.postWorkoutCheckIn(workoutID))
    }

    func routeToPostWorkoutImpact(workoutID: UUID?) {
        present(.postWorkoutImpact(workoutID))
    }

    func deferQuickActionUntilSheetDismisses(_ action: DeferredQuickAction) {
        deferredQuickAction = action
    }

    func runDeferredQuickAction() {
        guard let deferredQuickAction else { return }
        self.deferredQuickAction = nil
        resetQuickActionSheetTriggers()

        switch deferredQuickAction {
        case let .coach(question):
            routeToQuickCoach(question: question)
        case let .foodScanner(type):
            routeToFoodScanner(type: type)
        case .foodSearch:
            triggerFoodSearch = true
        case .workoutLog:
            present(.workoutLog)
        case .weightLog:
            present(.weightLog)
        case .bloodLog:
            present(.bloodLog)
        case .journal:
            present(.journal)
        }
    }

    private func resetQuickActionSheetTriggers() {
        triggerFoodSearch = false
        triggerFoodScanner = false
    }

    func present(_ sheet: AppSheet) {
        resetQuickActionSheetTriggers()
        presentedSheet = sheet
    }

    func dismissPresentedSheet() {
        presentedSheet = nil
    }

    func markLocalDataChanged() {
        localDataRevision += 1
    }
}

struct OpenVelaTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "查看 Vela 今日状态"
    static let description = IntentDescription("打开 Vela 首页查看今日健康状态。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        VelaAppState.shared.routeToTab(VelaAppState.todayTabIndex)
        return .result()
    }
}

struct OpenVelaReadinessIntent: AppIntent {
    static let title: LocalizedStringResource = "询问 Vela 就绪状态"
    static let description = IntentDescription("打开 Vela Coach 并分析今天的就绪状态。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        VelaAppState.shared.routeToCoach(
            question: "请根据我今天的恢复、睡眠和训练负荷，解释当前身体状态，并给出一个最重要的行动建议。",
            surface: .home
        )
        return .result()
    }
}

struct OpenVelaFoodScannerIntent: AppIntent {
    static let title: LocalizedStringResource = "用 Vela 扫描餐食"
    static let description = IntentDescription("打开 Vela 的餐食拍照分析入口。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // 营养功能开关关闭时给出明确反馈，而非静默无响应。
        let dialog: IntentDialog? = VelaFeatureFlags.nutritionEnabled
            ? nil
            : IntentDialog("餐食扫描功能当前未开启。")
        if VelaFeatureFlags.nutritionEnabled {
            VelaAppState.shared.routeToFoodScanner(type: "camera")
        }
        return .result(dialog: dialog ?? IntentDialog("已打开 Vela。"))
    }
}

struct VelaShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenVelaTodayIntent(),
            phrases: ["查看 \(.applicationName) 今日状态"],
            shortTitle: "今日状态",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: OpenVelaReadinessIntent(),
            phrases: ["询问 \(.applicationName) 就绪状态"],
            shortTitle: "就绪状态",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: OpenVelaFoodScannerIntent(),
            phrases: ["用 \(.applicationName) 扫描餐食"],
            shortTitle: "扫描餐食",
            systemImageName: "camera.fill"
        )
    }
}

@main
struct VelaApp: App {
    private let modelContainer: ModelContainer

    init() {
        // 诊断用：未捕获 NSException（如 JSONSerialization 的 __SwiftValue 崩溃）
        // 记录完整符号化调用栈——NSLog 会进控制台（devicectl --console 可捕获），
        // 同时落盘到 Application Support/Vela/crash_diagnostic.log 便于事后分析。
        NSSetUncaughtExceptionHandler { exception in
            let symbols = Thread.callStackSymbols.joined(separator: "\n")
            let message = "VELA_UNCAUGHT_EXCEPTION reason=\(exception.reason ?? "nil")\n\(symbols)"
            NSLog("%@", message)
            // 落盘为时间戳日志并轮转保留最近 3 份（审计 H4：覆盖式单文件会被冲掉）。
            _ = CrashLogStore.record(message)
        }

        // 前台收到本地通知时也要展示（此前无 delegate，前台通知被系统静默抑制）。
        UNUserNotificationCenter.current().delegate = VelaNotificationDelegate.shared

        do {
            modelContainer = try VelaModelContainer.make()
        } catch {
            VelaAppState.shared.isReadOnlySafetyMode = true
            PersistenceWriteGate.shared.setReadOnly(true)
            VelaAppState.shared.isFallbackStore = true
            if let memoryContainer = try? VelaModelContainer.make(inMemory: true) {
                modelContainer = memoryContainer
            } else {
                preconditionFailure("Vela: Could not create ModelContainer in any configuration.")
            }
        }
        VelaModelContainer.activeContainer = modelContainer

        // 崩溃上报：DSN 未配置时完全 no-op，不上传任何数据。
        SentryService.configureOnLaunch()

        // Register background task handler
        BackgroundTaskManager.register()

        // Register notification categories
        NotificationService.shared.registerNotificationCategories()

        // Keep the paired Apple Watch session warm so the latest decision can be delivered in the background.
        WristSnapshotBridge.shared.activate()

    }

    var body: some Scene {
        WindowGroup {
            AppCoordinator()
        }
        .modelContainer(modelContainer)
    }
}

/// 前台通知展示委托：无此 delegate 时，立即投递的本地通知在前台被系统默认抑制。
final class VelaNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = VelaNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
