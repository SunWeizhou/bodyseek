import XCTest

@MainActor
final class BodySeekUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp(extraArguments: [String] = ["-velaPreviewDashboard"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = extraArguments
        app.launch()
        return app
    }

    func testFullV3WorkoutCoachTrendsAndRecoveryFlows() {
        let app = launchApp()

        // 1. Today tab hero and 5 metrics
        XCTAssertTrue(app.otherElements["today-score-instrument"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["today-score-recovery"].exists)
        XCTAssertTrue(app.buttons["today-score-sleep"].exists)
        XCTAssertTrue(app.buttons["today-score-strain"].exists)
        XCTAssertTrue(app.buttons["today-card-stress"].exists)
        XCTAssertTrue(app.buttons["today-card-energy"].exists)

        // 2. Push Recovery detail -> Ask Coach
        app.buttons["today-score-recovery"].tap()
        XCTAssertTrue(app.buttons["detail-ask-coach"].waitForExistence(timeout: 5))
        app.buttons["detail-ask-coach"].tap()

        // 3. Coach tab receives prompt, shows evidence sparkline & sends Tool-Calling request
        XCTAssertTrue(app.textFields["coach-full-input"].waitForExistence(timeout: 5)
            || app.textViews["coach-full-input"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["coach-evidence-card"].waitForExistence(timeout: 5))

        let input = app.textViews["coach-full-input"].exists
            ? app.textViews["coach-full-input"]
            : app.textFields["coach-full-input"]
        input.tap()
        input.typeText("记住我右膝不适，帮我排一份减量课表")
        app.buttons["coach-send-button"].tap()

        let applyWorkoutBtn = app.buttons["coach-proposal-save"].firstMatch
        XCTAssertTrue(applyWorkoutBtn.waitForExistence(timeout: 6))
        applyWorkoutBtn.tap()

        // 4. Proposal routes to Workout tab & toggles MuscleMap + launches active workout logger
        XCTAssertTrue(app.staticTexts["急慢性负荷比 (ACWR)"].waitForExistence(timeout: 6))
        if app.segmentedControls["workout.bodySidePicker"].exists {
            app.segmentedControls["workout.bodySidePicker"].buttons["背面"].tap()
        }

        let startTemplateBtn = app.buttons["workout.startTemplate.11111111-1111-1111-1111-111111111101"]
        if startTemplateBtn.waitForExistence(timeout: 4) {
            startTemplateBtn.tap()
            XCTAssertTrue(app.buttons["workout.finishSession"].waitForExistence(timeout: 5))
            if app.buttons["workout.completeSet.0.0"].exists {
                app.buttons["workout.completeSet.0.0"].tap()
            }
            app.buttons["workout.finishSession"].tap()
            XCTAssertTrue(app.staticTexts["急慢性负荷比 (ACWR)"].waitForExistence(timeout: 5))
        }

        // 5. Trends tab horizon & coverage sheet + DualAxis
        app.tabBars.buttons["趋势"].tap()
        XCTAssertTrue(app.buttons["trends-horizon-week"].waitForExistence(timeout: 5))
        app.buttons["trends-horizon-week"].tap()
        app.buttons["trends-history-coverage"].tap()
        XCTAssertTrue(app.buttons["关闭"].waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
    }

    func testEmptyStateHonestPlaceholdersWithoutAuthorization() {
        let app = launchApp(extraArguments: ["-velaPreviewEmptyDashboard"])
        XCTAssertTrue(app.buttons["today-authorize-button"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["--"].exists)
    }

    func testDailyCheckInSheetFlow() {
        let app = launchApp()
        let card = app.buttons["today-checkin-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        card.tap()

        XCTAssertTrue(app.buttons["checkin-energy-4"].waitForExistence(timeout: 5))
        app.buttons["checkin-energy-4"].tap()
        app.buttons["checkin-mood-5"].tap()
        app.buttons["checkin-stress-2"].tap()

        let saveButton = app.buttons["checkin-save-button"]
        if !saveButton.isHittable {
            app.swipeUp()
        }
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["今日体感已记录"].waitForExistence(timeout: 6))
    }

    func testCaptureLightAndDarkScreenshotsWhenRequested() throws {
        let env = ProcessInfo.processInfo.environment
        guard let outputDir = env["BODYSEEK_WALKTHROUGH_DIR"], !outputDir.isEmpty else {
            throw XCTSkip("Screenshot capture only runs when BODYSEEK_WALKTHROUGH_DIR is set.")
        }

        let dirURL = URL(fileURLWithPath: outputDir, isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        func snap(_ name: String) throws {
            let data = XCUIScreen.main.screenshot().pngRepresentation
            try data.write(to: dirURL.appendingPathComponent("\(name).png"))
        }

        let app = launchApp()
        XCTAssertTrue(app.otherElements["today-score-instrument"].waitForExistence(timeout: 8))
        try snap("01-today-top")

        app.swipeUp()
        try snap("02-today-vitals")
        app.swipeDown()

        app.buttons["today-score-recovery"].tap()
        XCTAssertTrue(app.buttons["detail-ask-coach"].waitForExistence(timeout: 5))
        try snap("03-recovery-detail")
        app.buttons["detail-ask-coach"].tap()
        XCTAssertTrue(app.otherElements["coach-evidence-card"].waitForExistence(timeout: 5))

        let input = app.textViews["coach-full-input"].exists
            ? app.textViews["coach-full-input"]
            : app.textFields["coach-full-input"]
        input.tap()
        input.typeText("记住我右膝微痛，安排上肢减量课表")
        app.buttons["coach-send-button"].tap()
        _ = app.buttons["coach-proposal-save"].waitForExistence(timeout: 5)
        try snap("04-coach")

        app.tabBars.buttons["健身"].tap()
        XCTAssertTrue(app.staticTexts["全身肌群热图（近72h负荷）"].waitForExistence(timeout: 5))
        try snap("05-workout-musclemap")

        app.swipeUp()
        app.swipeUp()
        try snap("06-workout-zones")
        app.swipeDown()
        app.swipeDown()

        app.tabBars.buttons["趋势"].tap()
        XCTAssertTrue(app.buttons["trends-horizon-month"].waitForExistence(timeout: 5))
        try snap("07-trends")
    }
}
