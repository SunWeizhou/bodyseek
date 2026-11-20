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

    private func tapTab(_ title: String, in app: XCUIApplication) {
        if !app.tabBars.buttons[title].waitForExistence(timeout: 1.5) {
            let collapsedPill = app.tabBars.buttons
                .matching(NSPredicate(format: "value == '已折叠' OR value == 'collapsed'"))
                .firstMatch
            if collapsedPill.exists {
                collapsedPill.tap()
            } else if app.tabBars.buttons.firstMatch.exists {
                app.tabBars.buttons.firstMatch.tap()
            }
            if !app.tabBars.buttons[title].waitForExistence(timeout: 2.0) {
                app.swipeDown()
                if !app.tabBars.buttons[title].exists {
                    app.swipeDown()
                }
            }
        }
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Tab '\(title)' should exist")
        tab.tap()
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
        if !card.waitForExistence(timeout: 6) || !card.isHittable {
            app.swipeUp()
        }
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

    func testM1UIActionCardBespokeDetailsTrends3YAndNutritionBoard() {
        let app = launchApp()

        // 1. Today Action Card adopt flow
        let actionCard = app.otherElements["today-action-card"]
        if !actionCard.waitForExistence(timeout: 6) || !actionCard.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(actionCard.waitForExistence(timeout: 6))
        let adoptBtn = actionCard.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'today-action-adopt-'")).firstMatch
        XCTAssertTrue(adoptBtn.waitForExistence(timeout: 4))
        while !adoptBtn.isHittable {
            app.swipeUp()
        }
        let adoptIdentifier = adoptBtn.identifier
        adoptBtn.tap()
        XCTAssertEqual(app.buttons[adoptIdentifier].label, "已采纳")

        // 2. Bespoke Sleep & Stress detail views
        while !app.buttons["today-score-sleep"].isHittable {
            app.swipeDown()
        }
        app.buttons["today-score-sleep"].tap()
        XCTAssertTrue(app.staticTexts["阶段构成占比"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        while !app.buttons["today-card-stress"].isHittable {
            app.swipeUp()
        }
        app.buttons["today-card-stress"].tap()
        XCTAssertTrue(app.staticTexts["高压时段 vs 恢复时段"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 3. Nutrition board sheet + meal logging flow
        let nutritionCard = app.buttons["today-nutrition-card"]
        while !nutritionCard.isHittable {
            app.swipeUp()
        }
        nutritionCard.tap()
        XCTAssertTrue(app.otherElements["nutrition-macro-matrix"].waitForExistence(timeout: 6))
        app.buttons["nutrition-log-meal-button"].tap()

        let foodPick = app.buttons["nutrition-food-pick-rice_cooked"]
        XCTAssertTrue(foodPick.waitForExistence(timeout: 5))
        foodPick.tap()
        app.buttons["nutrition-meal-save-button"].tap()

        XCTAssertTrue(app.otherElements["nutrition-selected-day-card"].waitForExistence(timeout: 5))
        app.buttons["nutrition-done-button"].tap()

        // 4. Trends 3Y capsule switch & Patterns card
        tapTab("趋势", in: app)
        let threeYBtn = app.buttons["trends-horizon-threeYears"]
        XCTAssertTrue(threeYBtn.waitForExistence(timeout: 5))
        threeYBtn.tap()
        XCTAssertTrue(app.otherElements["trends-patterns-card"].waitForExistence(timeout: 5))
    }

    func testM2WatchFirstReviewInboxMuscleRecoveryAndArchive() {
        let app = launchApp(extraArguments: ["-velaPreviewDashboard", "-velaInitialTab", "1"])

        // 1. Inbox shows yesterday's unreviewed Watch strength workout
        let inbox = app.otherElements["workout-review-inbox"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 8))
        let reviewBtn = app.buttons["workout-inbox-review-00000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(reviewBtn.waitForExistence(timeout: 5))
        reviewBtn.tap()

        // 2. Tap quick review phrase chip & confirm card -> writes annotation + 14d constraint memory
        let chip0 = app.buttons["workout-review-chip-0"]
        XCTAssertTrue(chip0.waitForExistence(timeout: 5))
        chip0.tap()

        XCTAssertTrue(app.staticTexts["身体信号 → 自动创建 14 天约束记忆"].waitForExistence(timeout: 5))
        let confirmBtn = app.buttons["workout-review-confirm"]
        if !confirmBtn.isHittable {
            app.swipeUp()
        }
        confirmBtn.tap()

        // 3. MuscleMap ranked recovery row opens MuscleRecoveryDetailSheet ("启发式估计")
        let chestRow = app.buttons["workout-muscle-rank-chest"]
        XCTAssertTrue(chestRow.waitForExistence(timeout: 6))
        chestRow.tap()

        XCTAssertTrue(app.staticTexts["muscle-recovery-eta-text"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["muscle-recovery-heuristic-badge"].exists)
        app.buttons["muscle-recovery-done"].tap()

        // 4. Watch archive row opens WorkoutDetailSheetView with annotated state & separated efforts
        let archiveRow = app.buttons["workout-archive-row-00000000-0000-4000-8000-000000000001"]
        while !archiveRow.exists || !archiveRow.isHittable {
            app.swipeUp()
        }
        archiveRow.tap()
        XCTAssertTrue(app.staticTexts["用户主观用力 (EffortUser)"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Apple 系统估算 (Estimated)"].exists)
        XCTAssertTrue(app.staticTexts["已复盘"].exists)
        app.buttons["workout-detail-done"].tap()
    }

    func testM3CoachProposalsTieredMemoryProactiveInsightsAndPrivacyViewer() {
        let app = launchApp()

        // 1. Today shows bounded Proactive Insights card (<= 2/day)
        let insightsContainer = app.otherElements["today-proactive-insights"]
        XCTAssertTrue(insightsContainer.waitForExistence(timeout: 8))

        // 2. Navigate to Coach, send injury + workout query -> confirm memory proposal -> verify 3-tier memory sheet
        tapTab("问身体", in: app)
        let input = app.textViews["coach-full-input"].exists
            ? app.textViews["coach-full-input"]
            : app.textFields["coach-full-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("记住我右肩前束微痛，帮我排一份减量上肢课表")
        app.buttons["coach-send-button"].tap()

        // Confirm-to-write memory proposal card must appear before strip turns active
        let confirmMemBtn = app.buttons["coach-memory-proposal-confirm"].firstMatch
        XCTAssertTrue(confirmMemBtn.waitForExistence(timeout: 6))
        confirmMemBtn.tap()

        XCTAssertTrue(app.staticTexts["已确认写入 短期约束"].waitForExistence(timeout: 5))

        let memoryStrip = app.buttons["coach-memory-strip"]
        XCTAssertTrue(memoryStrip.waitForExistence(timeout: 5))
        memoryStrip.tap()

        XCTAssertTrue(app.staticTexts["三层长期记忆管理"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["短期约束"].exists)
        app.buttons["coach-memory-sheet-done"].tap()

        // 3. Settings proactive insights toggle & privacy outbound payload viewer sheet
        tapTab("今日", in: app)
        let settingsBtn = app.buttons["settings-button"]
        XCTAssertTrue(settingsBtn.waitForExistence(timeout: 5))
        settingsBtn.tap()

        let proactiveSwitch = app.switches["settings-proactive-insights-toggle"]
        while !proactiveSwitch.exists || !proactiveSwitch.isHittable {
            app.swipeUp()
        }
        proactiveSwitch.tap()

        let privacyBtn = app.buttons["settings-privacy-payload-button"]
        if !privacyBtn.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(privacyBtn.waitForExistence(timeout: 5))
        privacyBtn.tap()

        XCTAssertTrue(app.otherElements["settings-privacy-payload-sheet"].waitForExistence(timeout: 5))
        app.buttons["settings-privacy-payload-close"].tap()
        app.buttons["settings-done-button"].tap()
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

        let nutritionCard = app.buttons["today-nutrition-card"]
        if !nutritionCard.isHittable {
            app.swipeDown()
        }
        while !nutritionCard.isHittable {
            app.swipeUp()
        }
        nutritionCard.tap()
        XCTAssertTrue(app.otherElements["nutrition-macro-matrix"].waitForExistence(timeout: 6))
        try snap("06-nutrition-board")
        app.buttons["nutrition-done-button"].tap()

        while !app.buttons["today-score-recovery"].isHittable {
            app.swipeDown()
        }

        app.buttons["today-score-recovery"].tap()
        XCTAssertTrue(app.buttons["detail-ask-coach"].waitForExistence(timeout: 5))
        try snap("03-recovery-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["today-score-sleep"].tap()
        XCTAssertTrue(app.staticTexts["阶段构成占比"].waitForExistence(timeout: 5))
        try snap("04-sleep-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        while !app.buttons["today-card-stress"].isHittable {
            app.swipeUp()
        }
        app.buttons["today-card-stress"].tap()
        XCTAssertTrue(app.staticTexts["高压时段 vs 恢复时段"].waitForExistence(timeout: 5))
        try snap("05-stress-detail")
        app.buttons["detail-ask-coach"].tap()

        XCTAssertTrue(app.otherElements["coach-evidence-card"].waitForExistence(timeout: 5))
        let input = app.textViews["coach-full-input"].exists
            ? app.textViews["coach-full-input"]
            : app.textFields["coach-full-input"]
        input.tap()
        input.typeText("记住我右膝微痛，安排上肢减量课表")
        app.buttons["coach-send-button"].tap()
        _ = app.buttons["coach-proposal-save"].waitForExistence(timeout: 5)
        try snap("10-coach")

        tapTab("趋势", in: app)
        XCTAssertTrue(app.buttons["trends-horizon-month"].waitForExistence(timeout: 5))
        try snap("07-trends-month")

        app.buttons["trends-horizon-threeYears"].tap()
        try snap("08-trends-3y-capsules")

        tapTab("健身", in: app)
        XCTAssertTrue(app.staticTexts["全身肌群恢复热图"].waitForExistence(timeout: 5))
        try snap("09-workout-musclemap")
    }
}
