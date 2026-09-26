import XCTest

@MainActor
final class VelaSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFourPrimarySurfacesAreReachable() {
        let app = launchApp(initialTab: 0)

        assertSurface(0, in: app)
        selectTab(index: 1, label: "趋势", in: app)
        assertSurface(1, in: app)
        selectTab(index: 2, label: "计划", in: app)
        assertSurface(2, in: app)
        selectTab(index: 3, label: "Vela", in: app)
        assertSurface(3, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["coach-surface-header"].waitForExistence(timeout: 8),
            "Coach surface did not become visible"
        )
    }

    func testTodayScoreContentAndMetricRouting() {
        let app = launchApp(initialTab: 0)

        XCTAssertTrue(
            app.descendants(matching: .any)["surface-0"].waitForExistence(timeout: 10),
            "Today surface did not become visible"
        )
        for metric in ["recovery", "sleep", "strain"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["today-score-\(metric)"].waitForExistence(timeout: 3),
                "Today score \(metric) did not expose its stable identifier"
            )
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["today-secondary-stress"].waitForExistence(timeout: 3),
            "Today secondary stress card did not expose its stable identifier"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["today-secondary-energy"].waitForExistence(timeout: 3),
            "Today secondary energy card did not expose its stable identifier"
        )
        let guidanceCard = app.descendants(matching: .any)["today-guidance"]
        if guidanceCard.waitForExistence(timeout: 3) {
            guidanceCard.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["today-evidence-sheet"].waitForExistence(timeout: 8),
                "Tapping today guidance should open local evidence sheet"
            )
            let closeButton = app.buttons["关闭"]
            if closeButton.waitForExistence(timeout: 3) {
                closeButton.tap()
            }
        }
        let recoveryScore = app.descendants(matching: .any)["today-score-recovery"]
        if recoveryScore.waitForExistence(timeout: 3) {
            // Preview fixtures expose the score card as a stable, tappable
            // route. A real no-data launch may intentionally omit that card
            // while retaining the conservative state projection below.
            recoveryScore.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["metric-detail-recovery"].waitForExistence(timeout: 8),
                "Today recovery score did not route to its metric detail"
            )
        } else {
            XCTAssertTrue(
                app.descendants(matching: .any)["today-data-state"].waitForExistence(timeout: 5),
                "No-data Today launch should expose its conservative data state"
            )
        }
    }

    func testTrendsScoreContentAndMetricRouting() {
        let app = launchApp(initialTab: 1)

        XCTAssertTrue(
            app.descendants(matching: .any)["trends-content"].waitForExistence(timeout: 10),
            "Trends surface did not become visible"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["trends-horizon-picker"].waitForExistence(timeout: 8),
            "Trends horizon picker did not expose its stable identifier"
        )
        for metric in ["recovery", "sleepScore", "strain", "stress", "energy"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["trends-score-\(metric)"].waitForExistence(timeout: 8),
                "Trends score \(metric) did not expose its stable identifier"
            )
        }

        let chart = app.descendants(matching: .any)["trends-recovery-store-chart"]
        for _ in 0..<3 where !chart.exists { app.swipeUp() }
        XCTAssertTrue(chart.waitForExistence(timeout: 8), "Preview history should reach the real Store-owned chart")

        let recovery = app.descendants(matching: .any)["trends-score-recovery"]
        for _ in 0..<3 where !recovery.isHittable { app.swipeDown() }
        recovery.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["metric-detail-recovery"].waitForExistence(timeout: 8),
            "Trends recovery score did not route to its metric detail"
        )
    }

    func testSettingsDeepLaunch() {
        let app = launchApp(extraArguments: ["-velaOpenSettings"])

        XCTAssertTrue(
            app.descendants(matching: .any)["settings-surface"].waitForExistence(timeout: 10),
            "Settings sheet did not open from its launch route"
        )
        XCTAssertTrue(app.navigationBars["个人空间"].exists)
    }

    /// Read-only preview evidence for this redesign; kept separately from old captures.
    func testUpgradeSurfaceSnapshots() {
        for (index, name) in [(0, "today"), (1, "trends"), (2, "plan"), (3, "coach")] {
            let app = launchApp(initialTab: index, extraArguments: ["-vela_dark_mode", "light"])
            assertSurface(index, in: app)
            let readyID = index == 0 ? "today-score-recovery" : index == 3 ? "coach-current-context" : "surface-\(index)"
            XCTAssertTrue(app.descendants(matching: .any)[readyID].waitForExistence(timeout: 8))
            // Allow the existing score-ring entrance animation to finish.
            Thread.sleep(forTimeInterval: 1)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "upgrade-\(name)-light"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
        let dark = launchApp(extraArguments: ["-vela_dark_mode", "dark"])
        assertSurface(0, in: dark)
        XCTAssertTrue(dark.descendants(matching: .any)["today-secondary-energy"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "upgrade-today-dark"
        attachment.lifetime = .keepAlways
        add(attachment)
        dark.terminate()

        let large = launchApp(extraArguments: ["-vela_dark_mode", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        assertSurface(0, in: large)
        XCTAssertTrue(large.descendants(matching: .any)["today-score-recovery"].waitForExistence(timeout: 8))
        let largeAttachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        largeAttachment.name = "upgrade-today-accessibility"
        largeAttachment.lifetime = .keepAlways
        add(largeAttachment)
    }

    func testRecoveryDetailDeepLaunch() {
        let app = launchApp(extraArguments: ["-velaOpenRecoveryDetail"])

        XCTAssertTrue(
            app.descendants(matching: .any)["metric-detail-recovery"].waitForExistence(timeout: 10),
            "Recovery detail did not open from its launch route"
        )
        XCTAssertTrue(app.navigationBars["恢复"].exists)

        let closeButton = app.buttons["metric-detail-close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "Sheet should show close button")
        closeButton.tap()
        XCTAssertFalse(
            app.descendants(matching: .any)["metric-detail-recovery"].waitForExistence(timeout: 3),
            "Recovery detail sheet should dismiss after tapping close"
        )
    }

    func testRecoveryDetailPushNavigationAndReturn() {
        let app = launchApp(initialTab: 0)

        XCTAssertTrue(
            app.descendants(matching: .any)["surface-0"].waitForExistence(timeout: 10),
            "Today surface did not become visible"
        )
        let recoveryScore = app.descendants(matching: .any)["today-score-recovery"]
        guard recoveryScore.waitForExistence(timeout: 5) else {
            return
        }
        recoveryScore.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["metric-detail-recovery"].waitForExistence(timeout: 8),
            "Recovery detail did not open from Today push"
        )
        XCTAssertFalse(
            app.buttons["metric-detail-close"].exists,
            "Push navigation should not display custom sheet close button"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["metric-detail-hero"].waitForExistence(timeout: 5),
            "Recovery detail hero section should be present"
        )

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "System back button should be present")
        backButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["surface-0"].waitForExistence(timeout: 8),
            "Should return to Today surface after tapping back button"
        )
    }

    func testRecoveryDetailHistoricalDateNavigation() {
        let app = launchApp(initialTab: 0)

        XCTAssertTrue(
            app.descendants(matching: .any)["surface-0"].waitForExistence(timeout: 10),
            "Today surface did not become visible"
        )
        let calendarButton = app.buttons["today-calendar-button"]
        guard calendarButton.waitForExistence(timeout: 5) else {
            return
        }
        calendarButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["calendar-overview-sheet"].waitForExistence(timeout: 8),
            "Calendar sheet should open"
        )
        let dayButton = app.buttons["calendar-day-1"]
        if dayButton.waitForExistence(timeout: 5) && dayButton.isHittable {
            dayButton.tap()
        } else {
            let todayButton = app.buttons["今天"]
            if todayButton.waitForExistence(timeout: 3) {
                todayButton.tap()
            }
        }

        let recoveryScore = app.descendants(matching: .any)["today-score-recovery"]
        guard recoveryScore.waitForExistence(timeout: 5) else {
            return
        }
        recoveryScore.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["metric-detail-recovery"].waitForExistence(timeout: 8),
            "Recovery detail should open for historical date"
        )
        let screenshot = XCUIScreen.main.screenshot()
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/recovery-detail-historical.png"))
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 5) {
            backButton.tap()
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["surface-0"].waitForExistence(timeout: 8),
            "Should return to Today surface"
        )
    }

    func testLivedStateCheckInDeepLaunch() {
        let app = launchApp(extraArguments: ["-velaOpenLivedStateCheckIn"])

        XCTAssertTrue(
            app.descendants(matching: .any)["lived-state-check-in"].waitForExistence(timeout: 10),
            "Lived State check-in did not open from its launch route"
        )
        XCTAssertTrue(app.navigationBars["校准今日状态"].exists)
    }

    func testSleepDetailDeepLaunch() {
        let app = launchApp(extraArguments: ["-velaOpenSleepDetail"])

        XCTAssertTrue(
            app.descendants(matching: .any)["metric-detail-sleep"].waitForExistence(timeout: 10),
            "Sleep detail did not open from its launch route"
        )
        XCTAssertTrue(app.navigationBars["睡眠"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["sleep-timeline-card"].waitForExistence(timeout: 5),
            "Sleep timeline card should be present in sleep detail"
        )

        let closeButton = app.buttons["metric-detail-close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "Sheet should show close button")
        closeButton.tap()
        XCTAssertFalse(
            app.descendants(matching: .any)["metric-detail-sleep"].waitForExistence(timeout: 3),
            "Sleep detail sheet should dismiss after tapping close"
        )
    }

    func testSleepDetailPushNavigationAndReturn() {
        let app = launchApp(initialTab: 0)

        XCTAssertTrue(
            app.descendants(matching: .any)["surface-0"].waitForExistence(timeout: 10),
            "Today surface did not become visible"
        )
        let sleepScore = app.descendants(matching: .any)["today-score-sleep"]
        guard sleepScore.waitForExistence(timeout: 5) else {
            return
        }
        sleepScore.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["metric-detail-sleep"].waitForExistence(timeout: 8),
            "Sleep detail did not open from Today push"
        )
        XCTAssertFalse(
            app.buttons["metric-detail-close"].exists,
            "Push navigation should not display custom sheet close button"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["sleep-timeline-card"].waitForExistence(timeout: 5),
            "Sleep timeline card should be present in sleep detail push"
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "sleep-detail-push"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "System back button should be present")
        backButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["surface-0"].waitForExistence(timeout: 8),
            "Should return to Today surface after tapping back button"
        )
    }

    func testComprehensiveFullInteractionFlow() {
        let app = launchApp(initialTab: 0)
        XCTAssertTrue(app.descendants(matching: .any)["surface-0"].waitForExistence(timeout: 10))

        // 1. Switch to historical date
        let calendarButton = app.buttons["today-calendar-button"]
        if calendarButton.waitForExistence(timeout: 5) {
            calendarButton.tap()
            XCTAssertTrue(app.descendants(matching: .any)["calendar-overview-sheet"].waitForExistence(timeout: 8))
            let dayButton = app.buttons["calendar-day-1"]
            if dayButton.waitForExistence(timeout: 5) && dayButton.isHittable {
                dayButton.tap()
            } else {
                let todayButton = app.buttons["今天"]
                if todayButton.waitForExistence(timeout: 3) {
                    todayButton.tap()
                }
            }
        }

        // 2. Open detail (e.g. sleep)
        let sleepScore = app.descendants(matching: .any)["today-score-sleep"]
        if sleepScore.waitForExistence(timeout: 5) {
            sleepScore.tap()
            XCTAssertTrue(app.descendants(matching: .any)["metric-detail-sleep"].waitForExistence(timeout: 8))
            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            if backButton.waitForExistence(timeout: 5) {
                backButton.tap()
            }
            XCTAssertTrue(app.descendants(matching: .any)["surface-0"].waitForExistence(timeout: 8))
        }

        // 3. Switch to Trends tab
        selectTab(index: 1, label: "趋势", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["surface-1"].waitForExistence(timeout: 8))

        // 4. Switch back to Today tab
        selectTab(index: 0, label: "今日", in: app)
        XCTAssertTrue(app.descendants(matching: .any)["surface-0"].waitForExistence(timeout: 8))

        // 5. Background and foreground app
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)
        app.activate()
        XCTAssertTrue(app.descendants(matching: .any)["surface-0"].waitForExistence(timeout: 8))
    }

    func testStrainDetailDeepLaunch() {
        let app = launchApp(extraArguments: ["-velaOpenStrainDetail"])
        XCTAssertTrue(
            app.descendants(matching: .any)["metric-detail-strain"].waitForExistence(timeout: 10),
            "Strain detail did not open from its launch route"
        )
        XCTAssertTrue(app.navigationBars["耗力"].waitForExistence(timeout: 5))
        let closeButton = app.buttons["metric-detail-close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "Strain sheet should show close button")
        closeButton.tap()
        XCTAssertFalse(
            app.descendants(matching: .any)["metric-detail-strain"].waitForExistence(timeout: 3),
            "Strain detail sheet should dismiss after tapping close"
        )
    }

    func testStressDetailDeepLaunch() {
        let app = launchApp(extraArguments: ["-velaOpenStressDetail"])
        XCTAssertTrue(
            app.descendants(matching: .any)["metric-detail-stress"].waitForExistence(timeout: 10),
            "Stress detail did not open from its launch route"
        )
        XCTAssertTrue(app.navigationBars["压力"].waitForExistence(timeout: 5))
        let closeButton = app.buttons["metric-detail-close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "Stress sheet should show close button")
        closeButton.tap()
        XCTAssertFalse(
            app.descendants(matching: .any)["metric-detail-stress"].waitForExistence(timeout: 3),
            "Stress detail sheet should dismiss after tapping close"
        )
    }

    func testEnergyDetailDeepLaunch() {
        let app = launchApp(extraArguments: ["-velaOpenEnergyDetail"])
        XCTAssertTrue(
            app.descendants(matching: .any)["metric-detail-energy"].waitForExistence(timeout: 10),
            "Energy detail did not open from its launch route"
        )
        XCTAssertTrue(app.navigationBars["能量"].waitForExistence(timeout: 5))
        let closeButton = app.buttons["metric-detail-close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "Energy sheet should show close button")
        closeButton.tap()
        XCTAssertFalse(
            app.descendants(matching: .any)["metric-detail-energy"].waitForExistence(timeout: 3),
            "Energy detail sheet should dismiss after tapping close"
        )
    }

    private func launchApp(
        initialTab: Int = 0,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-vela_onboarding_completed", "YES",
            "-vela_app_language", "simplifiedChinese",
            "-velaPreviewDashboard",
            "-velaLegacyInterface",
            "-velaInitialTab", String(initialTab),
        ] + extraArguments
        app.launch()
        return app
    }

    private func selectTab(
        index: Int,
        label: String,
        in app: XCUIApplication
    ) {
        let customButton = app.buttons["tab-\(index)"]
        if customButton.exists {
            customButton.tap()
            return
        }

        let nativeButton = app.tabBars.buttons[label]
        XCTAssertTrue(
            nativeButton.waitForExistence(timeout: 8),
            "Tab \(label) was not reachable"
        )
        nativeButton.tap()
    }

    private func assertSurface(_ index: Int, in app: XCUIApplication) {
        XCTAssertTrue(
            app.descendants(matching: .any)["surface-\(index)"].waitForExistence(timeout: 10),
            "Primary surface \(index) did not become visible"
        )
    }
}
