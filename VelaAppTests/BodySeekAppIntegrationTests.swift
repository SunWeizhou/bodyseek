@testable import Vela
import XCTest

@MainActor
final class BodySeekAppIntegrationTests: XCTestCase {
    func testPreferencesClientLiveRoundTripAndReset() throws {
        try PreferencesClient.liveValue.reset()

        var prefs = AppPreferencesState()
        prefs.sleepGoalMinutes = 480
        prefs.subjectiveFeelingsByDay["2026-11-16"] = 8

        try PreferencesClient.liveValue.save(prefs)
        let loaded = try PreferencesClient.liveValue.load()
        XCTAssertEqual(loaded, prefs)

        try PreferencesClient.liveValue.reset()
        let cleared = try PreferencesClient.liveValue.load()
        XCTAssertEqual(cleared, AppPreferencesState())
    }

    func testSwiftDataFitnessStoreRoundTripAndReset() async throws {
        try await BodySeekSwiftDataBackend.shared.resetAll()

        let templates = try await BodySeekSwiftDataBackend.shared.loadTemplates()
        XCTAssertGreaterThanOrEqual(templates.count, 4)

        let memory = AthleteMemoryItem(category: .injury, content: "左肩盂唇轻微受限")
        try await BodySeekSwiftDataBackend.shared.saveMemory(memory)
        let loadedMemories = try await BodySeekSwiftDataBackend.shared.loadMemories()
        XCTAssertEqual(loadedMemories.first?.content, "左肩盂唇轻微受限")

        let session = LoggedWorkoutSession(
            title: "推力分化",
            startedAt: Date().addingTimeInterval(-1800),
            completedAt: Date(),
            exercises: [
                LoggedExerciseRecord(
                    exerciseID: "barbell-bench-press",
                    sets: [LoggedSetEntry(setIndex: 1, weightKg: 60, reps: 8, isCompleted: true)]
                ),
            ],
            rpe: 8,
            estimatedCalories: 240
        )
        try await BodySeekSwiftDataBackend.shared.saveSession(session)
        let loadedSessions = try await BodySeekSwiftDataBackend.shared.loadSessions()
        XCTAssertEqual(loadedSessions.first?.totalVolumeKg, 480)

        try await BodySeekSwiftDataBackend.shared.resetAll()
    }

    func testEmptyPreviewDashboardShowsMissingInsteadOfZero() {
        let state = AppFeature.State(arguments: ["-velaPreviewEmptyDashboard"])
        XCTAssertNil(state.snapshot.today.recovery.value)
        XCTAssertNil(state.snapshot.today.sleep.value)
        XCTAssertNil(state.snapshot.today.strain.value)
        XCTAssertFalse(state.snapshot.isAuthorized)
    }

    func testPreviewDashboardComputesAllFiveMetricsAndRespectsWorkoutInitialTab() {
        let state = AppFeature.State(arguments: ["-velaPreviewDashboard", "-velaInitialTab", "1"])
        XCTAssertEqual(state.selectedTab, .workout)
        XCTAssertNotNil(state.snapshot.today.recovery.value)
        XCTAssertNotNil(state.snapshot.today.sleep.value)
        XCTAssertNotNil(state.snapshot.today.strain.value)
        XCTAssertNotNil(state.snapshot.today.stress.value)
        XCTAssertNotNil(state.snapshot.today.energy.value)
        XCTAssertFalse(state.sessions.isEmpty)
        XCTAssertFalse(state.templates.isEmpty)
    }
}
