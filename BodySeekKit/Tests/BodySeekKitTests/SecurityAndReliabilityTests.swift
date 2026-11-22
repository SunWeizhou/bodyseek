import BodySeekAgent
import BodySeekCore
import BodySeekFeatures
import BodySeekHealth
import ComposableArchitecture
import Foundation
import XCTest

@MainActor
final class SecurityAndReliabilityTests: XCTestCase {
    private struct StubError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private final class LockedConfig: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: CoachAIConfig?

        var value: CoachAIConfig? {
            get { lock.lock(); defer { lock.unlock() }; return storage }
            set { lock.lock(); defer { lock.unlock() }; storage = newValue }
        }
    }

    func testKeychainMigratesLegacyUserDefaultsKeyAndPurgesIt() throws {
        let suiteName = "bodyseek.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("  sk-legacy-deepseek-key  ", forKey: KeychainCredentialStore.legacyUserDefaultsAPIKey)
        let memoryStorage = InMemoryKeychainStorage()
        let store = KeychainCredentialStore(storage: memoryStorage, userDefaults: defaults)

        let loaded = try store.loadAPIKey()
        XCTAssertEqual(loaded, "sk-legacy-deepseek-key")
        XCTAssertEqual(try memoryStorage.read(account: KeychainCredentialStore.apiKeyAccount), "sk-legacy-deepseek-key")
        XCTAssertNil(defaults.string(forKey: KeychainCredentialStore.legacyUserDefaultsAPIKey))

        try store.saveAPIKey("sk-new-rotated-key")
        XCTAssertEqual(try store.loadAPIKey(), "sk-new-rotated-key")
        XCTAssertNil(defaults.string(forKey: KeychainCredentialStore.legacyUserDefaultsAPIKey))

        try store.saveAPIKey("   ")
        XCTAssertEqual(try store.loadAPIKey(), "")
        XCTAssertNil(try memoryStorage.read(account: KeychainCredentialStore.apiKeyAccount))
    }

    func testSettingsFeatureSurfacesKeychainAndDeleteMemoryFailures() async {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 10),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Test",
            isAuthorized: true
        )
        let memory = AthleteMemoryItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000077")!,
            category: .injury,
            content: "右肩紧绷",
            updatedAt: now
        )

        let store = TestStore(
            initialState: SettingsFeature.State(
                snapshot: snapshot,
                preferences: AppPreferencesState(),
                memories: [memory]
            )
        ) {
            SettingsFeature()
        } withDependencies: {
            $0.coachAIClient.loadAPIKey = { throw StubError(message: "Keychain locked") }
            $0.coachAIClient.saveAPIKey = { _ in throw StubError(message: "Keychain write denied") }
            $0.coachAIClient.loadConfig = { CoachAIConfig() }
            $0.coachAIClient.saveConfig = { _ in }
            $0.fitnessStoreClient.deleteMemory = { _ in throw StubError(message: "Disk read-only") }
            $0.preferencesClient = .previewValue
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        XCTAssertTrue(store.state.statusMessage?.contains("读取 Keychain 凭据失败") == true)

        await store.send(.apiKeyChanged("sk-test"))
        await store.send(.saveAIConfigTapped)
        XCTAssertTrue(store.state.statusMessage?.contains("保存 API Key 到 Keychain 失败") == true)

        await store.send(.deleteMemoryTapped(memory.id))
        await store.receive(\.memoryDeleteFailed)
        XCTAssertTrue(store.state.statusMessage?.contains("删除记忆失败") == true)
    }

    func testWebSearchToggleDoesNotPersistUnsavedConnectionDraft() async {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 5),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Test",
            isAuthorized: true
        )
        let recorder = LockedConfig()
        let stored = CoachAIConfig(
            endpointURL: "https://stored.example/v1",
            modelName: "stored-model",
            enableWebSearch: true
        )
        let store = TestStore(
            initialState: SettingsFeature.State(
                snapshot: snapshot,
                preferences: AppPreferencesState()
            )
        ) {
            SettingsFeature()
        } withDependencies: {
            $0.coachAIClient.loadConfig = { stored }
            $0.coachAIClient.saveConfig = { recorder.value = $0 }
            $0.coachAIClient.loadAPIKey = { "" }
            $0.preferencesClient = .previewValue
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.send(.modelNameChanged("unsaved-draft-model"))
        await store.send(.webSearchToggled(false))

        XCTAssertEqual(store.state.config.modelName, "unsaved-draft-model")
        XCTAssertEqual(recorder.value?.modelName, "stored-model")
        XCTAssertEqual(recorder.value?.enableWebSearch, false)
    }

    func testCoachWorkoutAndAppSurfaceStoreErrorsInsteadOfSwallowing() async {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 10),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Test",
            isAuthorized: true
        )
        let mem = AthleteMemoryItem(category: .goal, content: "半马破 140")

        let coachStore = TestStore(
            initialState: CoachFeature.State(snapshot: snapshot, memories: [mem])
        ) {
            CoachFeature()
        } withDependencies: {
            $0.coachAIClient = .previewValue
            $0.fitnessStoreClient.clearMessages = { throw StubError(message: "clear failed") }
            $0.fitnessStoreClient.deleteMemory = { _ in throw StubError(message: "delete failed") }
            $0.uuid = .incrementing
            $0.date.now = now
        }
        coachStore.exhaustivity = .off

        await coachStore.send(.newConversationTapped)
        await coachStore.receive(\.conversationResetFinished)
        XCTAssertTrue(coachStore.state.lastError?.contains("清空对话历史失败") == true)

        await coachStore.send(.deleteMemoryTapped(mem.id))
        await coachStore.receive(\.storeOperationFailed)
        XCTAssertTrue(coachStore.state.lastError?.contains("删除长期记忆失败") == true)

        let proposal = WorkoutProposal(
            template: ExerciseCatalog.defaultTemplates[0],
            rationale: "测试失败传播"
        )
        let workoutStore = TestStore(
            initialState: WorkoutFeature.State(snapshot: snapshot)
        ) {
            WorkoutFeature()
        } withDependencies: {
            $0.fitnessStoreClient.saveTemplate = { _ in throw StubError(message: "template db error") }
            $0.healthKitClient = .previewValue
            $0.restTimerClient = .previewValue
            $0.uuid = .incrementing
            $0.date.now = now
        }
        workoutStore.exhaustivity = .off

        await workoutStore.send(.acceptProposalTapped(proposal, startImmediately: false))
        await workoutStore.receive(\.templatePersistFailed)
        XCTAssertTrue(workoutStore.state.lastError?.contains("保存训练模板失败") == true)

        var badPrefsClient = PreferencesClient.previewValue
        badPrefsClient.load = { throw StubError(message: "corrupt json") }
        let appStore = TestStore(
            initialState: AppFeature.State(hasCompletedOnboarding: true, snapshot: snapshot)
        ) {
            AppFeature()
        } withDependencies: {
            $0.preferencesClient = badPrefsClient
            $0.healthKitClient = .previewValue
            $0.fitnessStoreClient = .previewValue
            $0.coachAIClient = .previewValue
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
            $0.date.now = now
        }
        appStore.exhaustivity = .off

        await appStore.send(.onAppear)
        XCTAssertTrue(appStore.state.today.lastError?.contains("读取偏好设置失败") == true)
    }
}
