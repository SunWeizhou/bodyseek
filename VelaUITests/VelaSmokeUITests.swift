import XCTest

@MainActor
final class VelaSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testThreePrimarySurfacesAndInlineCoachAreReachable() {
        let app = launchApp(initialTab: 0)

        assertSurface(0, in: app)
        selectTab(index: 1, label: "趋势", in: app)
        assertSurface(1, in: app)
        selectTab(index: 2, label: "计划", in: app)
        assertSurface(2, in: app)
        selectTab(index: 3, label: "Vela", in: app)
        assertSurface(3, in: app)
        XCTAssertTrue(
            app.buttons["收起对话"].waitForExistence(timeout: 8),
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
        let guidanceCard = app.buttons["today-advice-evidence"]
        if guidanceCard.waitForExistence(timeout: 3) {
            for _ in 0..<4 where !guidanceCard.isHittable { app.swipeUp() }
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

        let recovery = app.descendants(matching: .any)["trends-score-recovery"]
        for _ in 0..<3 where !recovery.isHittable { app.swipeDown() }
        recovery.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["metric-detail-recovery"].waitForExistence(timeout: 8),
            "Trends recovery score did not route to its metric detail"
        )
    }

    func testTrendsChartLayoutsAndHorizons() {
        let app = launchApp(initialTab: 1, extraArguments: ["-vela_dark_mode", "light"])
        let recovery = app.descendants(matching: .any)["trends-score-recovery"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 10))
        let picker = app.descendants(matching: .any)["trends-horizon-picker"]
        XCTAssertTrue(picker.isHittable, "The time range must remain below the header")
        captureTrends("trends-light-30d")

        for horizon in ["7d", "6m", "3y", "30d"] {
            let option = app.buttons["trends-horizon-\(horizon)"]
            XCTAssertTrue(option.isHittable)
            option.tap()
            XCTAssertTrue(option.isSelected)
            XCTAssertTrue(recovery.exists)
        }
        captureTrends("trends-light-return-30d")

        // Every card remains reachable even though its chart now owns a full row.
        for metric in ["sleepScore", "strain", "stress", "energy"] {
            let row = app.descendants(matching: .any)["trends-score-\(metric)"]
            for _ in 0..<6 where !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.isHittable, "The \(metric) chart should remain reachable")
        }
        captureTrends("trends-light-lower-charts")
        app.terminate()

        let dark = launchApp(initialTab: 1, extraArguments: ["-vela_dark_mode", "dark"])
        XCTAssertTrue(dark.descendants(matching: .any)["trends-score-recovery"].waitForExistence(timeout: 10))
        captureTrends("trends-dark")
        dark.terminate()

        let large = launchApp(initialTab: 1, extraArguments: [
            "-vela_dark_mode", "light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        XCTAssertTrue(large.descendants(matching: .any)["trends-score-recovery"].waitForExistence(timeout: 10))
        captureTrends("trends-accessibility-top")
        let largeRecovery = large.descendants(matching: .any)["trends-score-recovery"]
        for _ in 0..<5 where !largeRecovery.isHittable { large.swipeUp() }
        large.swipeUp()
        captureTrends("trends-accessibility-chart")
    }

    func testDataRepairLayoutsAndLegacyProtocolRecovery() {
        var app = launchApp(initialTab: 1, extraArguments: ["-velaDisableNetworkAI", "-vela_dark_mode", "light"])
        let coverage = app.buttons["trends-history-coverage"]
        XCTAssertTrue(coverage.waitForExistence(timeout: 10))
        XCTAssertTrue(coverage.label.contains("含当天"))
        captureTrends("repair-trends-light")
        coverage.tap()
        XCTAssertTrue(app.descendants(matching: .any)["history-coverage-details"].waitForExistence(timeout: 4))
        captureTrends("repair-coverage-light")
        app.buttons["关闭"].tap()
        app.descendants(matching: .any)["trends-score-recovery"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["recovery-detail-chart"].waitForExistence(timeout: 5))
        captureTrends("repair-recovery-chart-light")
        app.terminate()
        app = launchApp(initialTab: 0, extraArguments: ["-velaDisableNetworkAI", "-velaCoachProtocolFixture", "-vela_dark_mode", "light"])
        XCTAssertTrue(app.descendants(matching: .any)["today-score-instrument"].waitForExistence(timeout: 10))
        captureTrends("repair-today-light")
        app.descendants(matching: .any)["bodyseek-ask-input"].tap()
        XCTAssertTrue(app.buttons["恢复问题"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "<tool_call>")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "未形成可用结论")).firstMatch.isHittable)
        captureTrends("repair-legacy-protocol")
        app.buttons["恢复问题"].tap()
        let field = app.descendants(matching: .any)["bodyseek-ask-input"]
        XCTAssertTrue((field.value as? String)?.contains("Explain this trend") == true)
        captureTrends("repair-restored-question")
        app.buttons["收起对话"].tap()
        app.terminate()
        app = launchApp(initialTab: 2, extraArguments: ["-velaDisableNetworkAI", "-velaPlanProposalFixture", "-vela_dark_mode", "light"])
        captureTrends("repair-plan-collapsed")
        let expand = app.buttons["plan-proposal-expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["采用建议"].exists)
        expand.tap()
        XCTAssertTrue(app.buttons["采用建议"].waitForExistence(timeout: 3))
        captureTrends("repair-plan-diff")
        app.terminate()
        app = launchApp(initialTab: 0, extraArguments: ["-velaDisableNetworkAI", "-vela_dark_mode", "dark"])
        XCTAssertTrue(app.descendants(matching: .any)["today-score-instrument"].waitForExistence(timeout: 10))
        captureTrends("repair-today-dark")
    }

    func testHistoryRepairEntryIsReachableWithoutStartingHealthQueries() {
        let app = launchApp(initialTab: 0, extraArguments: ["-velaDisableNetworkAI"])
        app.buttons["个人档案"].tap()
        let history = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "三年 Apple 健康回填")).firstMatch
        for _ in 0..<8 where !history.isHittable { app.swipeUp() }
        XCTAssertTrue(history.isHittable)
        history.tap()
        let repair = app.buttons["history-score-repair"]
        for _ in 0..<8 where !repair.isHittable { app.swipeUp() }
        XCTAssertTrue(repair.isHittable)
        captureTrends("repair-history-entry")
    }

    func testPeriodSummaryCoverageAndCompactComposer() {
        let app = launchApp(initialTab: 1, extraArguments: ["-velaDisableNetworkAI", "-vela_dark_mode", "light"])
        let summary = app.descendants(matching: .any)["trends-period-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "Each horizon needs its own evidence summary")
        let thirty = summary.label
        app.buttons["trends-horizon-7d"].tap()
        XCTAssertTrue(summary.label.contains("7天"))
        XCTAssertNotEqual(summary.label, thirty)
        let coverage = app.buttons["trends-history-coverage"]
        XCTAssertTrue(coverage.exists)
        coverage.tap()
        XCTAssertTrue(app.descendants(matching: .any)["history-coverage-details"].waitForExistence(timeout: 4))
        captureTrends("five-history-coverage")
        app.buttons["关闭"].tap()
        selectTab(index: 0, label: "今日", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["today-follow-up-chips"].exists)
        let composer = app.descendants(matching: .any)["bodyseek-ask-composer"]
        XCTAssertLessThan(composer.frame.height, 90, "Idle composer should leave room for health data")
        captureTrends("five-today-compact")
        app.buttons["bodyseek-context"].tap()
        XCTAssertTrue(app.staticTexts["本次提问的上下文"].waitForExistence(timeout: 3))
        captureTrends("five-question-context")
        app.buttons["关闭"].tap()
        let field = app.descendants(matching: .any)["bodyseek-ask-input"]
        field.tap()
        field.typeText("Explain these scores")
        captureTrends("five-inline-compact-draft")
        XCTAssertTrue(app.buttons["发送"].exists)
        XCTAssertTrue(app.buttons["coach-inline-question"].firstMatch.exists)
        app.buttons["收起对话"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["today-score-recovery"].isHittable)
    }

    func testAskBarOffersExplicitSendAndStaysOnCurrentPage() {
        let app = launchApp(initialTab: 0, extraArguments: ["-velaDisableNetworkAI"])
        let field = app.textViews.firstMatch.exists ? app.textViews.firstMatch : app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        let question = "Interaction \(UUID().uuidString.prefix(8))"
        field.typeText(question)
        let send = app.buttons["发送"]
        XCTAssertTrue(send.waitForExistence(timeout: 3), "Text input needs a real Send button, not a mislabeled speech action")
        XCTAssertTrue(app.descendants(matching: .any)["inline-coach-panel"].exists,
                      "Conversation should open in place above the composer")
        send.tap()
        let opened = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        opened.name = "inline-conversation-after-send"
        opened.lifetime = .keepAlways
        add(opened)
        let message = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", question, question)
        ).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["surface-0"].exists)
        app.buttons["收起对话"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["today-score-recovery"].isHittable)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "today-after-inline-conversation"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSpeechPermissionCallbackDoesNotTerminateApp() {
        let app = launchApp(initialTab: 0)
        let speak = app.buttons["bodyseek-speak"]
        XCTAssertTrue(speak.waitForExistence(timeout: 8))
        speak.tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = system.alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            let decline = alert.buttons.matching(NSPredicate(format: "label IN %@", ["不允许", "Don’t Allow", "Don't Allow"])).firstMatch
            if decline.exists { decline.tap() }
        }
        XCTAssertEqual(app.state, .runningForeground, "A speech permission result must not crash on a background callback queue")
    }

    func testPrimaryPageStateAndInlineConversationSnapshots() {
        let app = launchApp(initialTab: 0, extraArguments: ["-velaDisableNetworkAI", "-vela_dark_mode", "light"])
        let recovery = app.descendants(matching: .any)["today-score-recovery"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 10))
        let initialValue = recovery.label
        for _ in 0..<3 {
            selectTab(index: 1, label: "趋势", in: app)
            XCTAssertTrue(app.descendants(matching: .any)["trends-score-recovery"].waitForExistence(timeout: 5))
            selectTab(index: 2, label: "计划", in: app)
            XCTAssertTrue(app.descendants(matching: .any)["surface-2"].waitForExistence(timeout: 5))
            selectTab(index: 0, label: "今日", in: app)
            XCTAssertEqual(recovery.label, initialValue)
        }
        captureTrends("interaction-today-light")
        let evidence = app.descendants(matching: .any)["today-advice-evidence"]
        for _ in 0..<4 where !evidence.isHittable { app.swipeUp() }
        XCTAssertTrue(evidence.isHittable)
        evidence.tap()
        XCTAssertTrue(app.descendants(matching: .any)["today-evidence-sheet"].waitForExistence(timeout: 5))
        captureTrends("interaction-advice-evidence")
        let close = app.buttons["关闭"]
        if close.exists { close.tap() }

        selectTab(index: 2, label: "计划", in: app)
        captureTrends("interaction-plan-light")
        selectTab(index: 0, label: "今日", in: app)
        let field = app.descendants(matching: .any)["bodyseek-ask-input"]
        field.tap()
        field.typeText("How should I read today's scores?")
        captureTrends("interaction-inline-draft-light")
        XCTAssertTrue(app.buttons["发送"].exists)
        XCTAssertTrue(app.buttons["bodyseek-speak"].exists)
        app.buttons["发送"].tap()
        captureTrends("interaction-inline-answer-light")
        app.buttons["收起对话"].tap()
        XCTAssertTrue(app.buttons["继续对话"].exists)
        app.buttons["继续对话"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["inline-coach-panel"].exists)
        captureTrends("interaction-inline-resumed-light")
    }

    func testDraftSurvivesExpandedChatAndCancelledConsent() {
        let app = launchApp(initialTab: 0, extraArguments: ["-velaDisableNetworkAI", "-vela_dark_mode", "light"])
        let field = app.descendants(matching: .any)["bodyseek-ask-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        field.typeText("Keep this draft")
        app.buttons["展开完整对话"].tap()
        let fullInput = app.descendants(matching: .any)["coach-full-input"]
        XCTAssertTrue(fullInput.waitForExistence(timeout: 5))
        XCTAssertEqual(fullInput.value as? String, "Keep this draft")
        app.buttons["关闭"].tap()
        XCTAssertEqual(field.value as? String, "Keep this draft")
        app.terminate()

        let consent = launchApp(initialTab: 0, extraArguments: [
            "-velaCoachConsentFixture", "-vela_coach_outbound_consent_version", "0", "-vela_dark_mode", "light"
        ])
        let pending = consent.descendants(matching: .any)["bodyseek-ask-input"]
        XCTAssertTrue(pending.waitForExistence(timeout: 8))
        pending.tap()
        pending.typeText("Consent draft")
        consent.buttons["发送"].firstMatch.tap()
        XCTAssertTrue(consent.navigationBars["联网 AI 数据授权"].waitForExistence(timeout: 5))
        consent.buttons["取消"].tap()
        XCTAssertEqual(pending.value as? String, "Consent draft")
        captureTrends("interaction-consent-cancelled-draft")
    }

    private func captureTrends(_ name: String) {
        // Let the asynchronous Store load settle before recording visual evidence.
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
            let readyID = index == 0 ? "today-score-recovery" : index == 3 ? "inline-coach-panel" : "surface-\(index)"
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

    /// Next-wave evidence uses production navigation and synthetic dashboard inputs.
    func testVisualNextWaveSettingsSnapshots() {
        for (entry, title, slug) in [
            ("基本资料", "基本资料", "account"),
            ("数据来源", "健康数据源", "sources"),
            ("沟通方式", "AI 教练风格", "personality"),
            ("信任中心", "信任中心", "trust"),
            ("连续血糖数据", "连续血糖监测 (CGM)", "cgm")
        ] {
            let app = launchApp(extraArguments: ["-velaOpenSettings", "-velaDisableNetworkAI", "-vela_dark_mode", "dark"])
            XCTAssertTrue(app.descendants(matching: .any)["settings-surface"].waitForExistence(timeout: 10))
            let row = app.staticTexts[entry].firstMatch
            tapNextWaveSettingsRow(row, in: app)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 8), "Settings title: \(title)")
            captureTrends("next-" + slug + "-dark")
            app.swipeUp()
            captureTrends("next-" + slug + "-dark-scrolled")
            app.terminate()
        }
    }

    func testVisualNextWaveAccessibilitySnapshots() {
        for entry in ["基本资料"] {
            let app = launchApp(extraArguments: [
                "-velaOpenSettings", "-velaDisableNetworkAI", "-vela_dark_mode", "light",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
            ])
            XCTAssertTrue(app.descendants(matching: .any)["settings-surface"].waitForExistence(timeout: 10))
            captureTrends("next-settings-accessibility-" + entry)
            let row = app.staticTexts[entry].firstMatch
            tapNextWaveSettingsRow(row, in: app)
            XCTAssertTrue(app.navigationBars[entry == "基本资料" ? "基本资料" : "AI 模型设置"].waitForExistence(timeout: 8))
            captureTrends("next-" + entry + "-accessibility")
            app.swipeUp()
            captureTrends("next-" + entry + "-accessibility-scrolled")
            app.terminate()
        }
        for (name, route) in [("recovery", "-velaOpenRecoveryDetail"), ("strain", "-velaOpenStrainDetail"), ("stress", "-velaOpenStressDetail"), ("energy", "-velaOpenEnergyDetail")] {
            let app = launchApp(extraArguments: [route, "-vela_dark_mode", "dark",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
            XCTAssertTrue(app.descendants(matching: .any)["metric-detail-" + name].waitForExistence(timeout: 10))
            captureTrends("next-" + name + "-accessibility")
            app.swipeUp()
            captureTrends("next-" + name + "-accessibility-scrolled")
            if name == "recovery" {
                app.swipeUp()
                captureTrends("next-recovery-accessibility-observations")
            }
            app.terminate()
        }
    }

    func testVisualNextWavePlanEditorSnapshots() {
        // The preview dashboard is read-only; use the empty simulator's local plan.
        let app = XCUIApplication()
        app.launchArguments = ["-vela_onboarding_completed", "YES", "-vela_app_language", "simplifiedChinese",
            "-velaInitialTab", "2", "-velaDisableNetworkAI", "-vela_dark_mode", "dark"]
        app.launch()
        assertSurface(2, in: app)
        let menu = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "管理 ")).firstMatch
        for _ in 0..<5 where !menu.isHittable { app.swipeUp() }
        XCTAssertTrue(menu.isHittable)
        menu.tap()
        app.buttons["编辑"].tap()
        XCTAssertTrue(app.navigationBars["编辑行动"].waitForExistence(timeout: 5))
        captureTrends("next-plan-editor-dark")
        app.buttons["取消"].tap()
        assertSurface(2, in: app)
    }

    func testVisualNextWaveSheetsAndCoachSnapshots() {
        let app = launchApp(extraArguments: ["-velaDisableNetworkAI", "-vela_dark_mode", "dark"])
        assertSurface(0, in: app)
        let evidence = app.buttons["today-advice-evidence"]
        for _ in 0..<5 where !evidence.isHittable { app.swipeUp() }
        XCTAssertTrue(evidence.isHittable)
        evidence.tap()
        XCTAssertTrue(app.descendants(matching: .any)["today-evidence-sheet"].waitForExistence(timeout: 5))
        captureTrends("next-evidence-dark")
        app.buttons["关闭"].tap()
        app.buttons["记录"].tap()
        XCTAssertTrue(app.buttons["记录体重"].waitForExistence(timeout: 5))
        captureTrends("next-quick-actions-dark")
        app.buttons["记录体重"].tap()
        XCTAssertTrue(app.buttons["保存记录"].waitForExistence(timeout: 5))
        captureTrends("next-weight-dark")
        app.terminate()

        let coach = launchApp(extraArguments: ["-velaDisableNetworkAI", "-vela_dark_mode", "dark"])
        let field = coach.descendants(matching: .any)["bodyseek-ask-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        field.tap()
        coach.buttons["展开完整对话"].tap()
        XCTAssertTrue(coach.descendants(matching: .any)["coach-full-input"].waitForExistence(timeout: 5))
        captureTrends("next-coach-full-dark")
        coach.buttons["更多"].tap()
        coach.buttons["历史分析报告"].tap()
        XCTAssertTrue(coach.navigationBars["历史报告"].waitForExistence(timeout: 5))
        captureTrends("next-coach-reports-dark")
        XCTAssertTrue(coach.buttons["查看全部"].waitForExistence(timeout: 5))
        coach.buttons["查看全部"].tap()
        captureTrends("next-artifact-library-dark")
        coach.terminate()

        let large = launchApp(extraArguments: ["-vela_dark_mode", "light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        assertSurface(0, in: large)
        large.buttons["记录"].tap()
        XCTAssertTrue(large.buttons["记录体重"].waitForExistence(timeout: 5))
        captureTrends("next-quick-actions-accessibility")
        large.buttons["记录体重"].tap()
        XCTAssertTrue(large.navigationBars["记录体重体脂"].waitForExistence(timeout: 5))
        let weightField = large.textFields.firstMatch
        XCTAssertTrue(weightField.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(weightField.frame.minX, large.frame.minX)
        XCTAssertLessThanOrEqual(weightField.frame.maxX, large.frame.maxX)
        captureTrends("next-weight-accessibility")
        large.swipeUp()
        captureTrends("next-weight-accessibility-scrolled")
        large.terminate()
    }

    private func tapNextWaveSettingsRow(_ row: XCUIElement, in app: XCUIApplication) {
        // A partially visible oversized label may be "hittable" under the toolbar.
        // Keep the entire label in the visible content before tapping.
        for _ in 0..<30 {
            let exists = row.exists
            let frame = exists ? row.frame : CGRect.null
            if exists && row.isHittable && frame.minY > 110 && frame.maxY < app.frame.maxY - 20 {
                row.tap()
                return
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.72))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: exists && frame.minY < 110 && row.isHittable ? 0.89 : 0.55))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Settings row was not fully visible: " + row.label)
    }

    /// Actual SwiftUI evidence for the residual pass; uses existing debug routes only.
    func testVisualResidualSnapshots() {
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "residual-" + name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        for (name, route) in [
            ("recovery", "-velaOpenRecoveryDetail"),
            ("sleep", "-velaOpenSleepDetail"),
            ("strain", "-velaOpenStrainDetail"),
            ("stress", "-velaOpenStressDetail"),
            ("energy", "-velaOpenEnergyDetail")
        ] {
            let app = launchApp(extraArguments: [route, "-vela_dark_mode", "dark"])
            XCTAssertTrue(app.descendants(matching: .any)["metric-detail-" + name].waitForExistence(timeout: 10))
            capture(name + "-dark")
            app.terminate()
        }

        let large = launchApp(extraArguments: [
            "-velaOpenSleepDetail", "-vela_dark_mode", "light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        XCTAssertTrue(large.descendants(matching: .any)["metric-detail-sleep"].waitForExistence(timeout: 10))
        capture("sleep-light-accessibility")
        large.swipeUp()
        capture("sleep-light-accessibility-scrolled")
        large.terminate()

        for (name, route, title) in [
            ("body", "-velaForceOnboarding", "先看见身体，再决定今天。"),
            ("agent", "-velaOnboardingAgentControl", "Agent 解释，你做决定。"),
            ("health", "-velaOnboardingAppleHealth", "连接 Apple 健康")
        ] {
            let app = launchApp(extraArguments: ["-velaForceOnboarding", route, "-vela_dark_mode", "dark"])
            XCTAssertTrue(app.staticTexts[title].firstMatch.waitForExistence(timeout: 10))
            capture("onboarding-" + name + "-dark")
            app.terminate()
        }

        let journal = launchApp(extraArguments: ["-vela_dark_mode", "dark"])
        assertSurface(0, in: journal)
        journal.buttons["记录"].tap()
        XCTAssertTrue(journal.buttons["手记"].waitForExistence(timeout: 5))
        capture("quick-actions-dark")
        journal.buttons["手记"].tap()
        XCTAssertTrue(journal.staticTexts["习惯与记录"].waitForExistence(timeout: 10))
        capture("journal-dark")
    }

    func testRecoveryDetailDeepLaunch() {
        let app = launchApp(extraArguments: ["-velaOpenRecoveryDetail"])

        XCTAssertTrue(
            app.descendants(matching: .any)["metric-detail-recovery"].waitForExistence(timeout: 10),
            "Recovery detail did not open from its launch route"
        )
        XCTAssertTrue(app.staticTexts["恢复"].firstMatch.exists)

        let closeButton = app.buttons["关闭"].firstMatch
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
        XCTAssertTrue(
            app.buttons["返回"].exists,
            "Pushed metric detail should expose its custom back button"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["metric-detail-hero"].waitForExistence(timeout: 5),
            "Recovery detail hero section should be present"
        )

        let backButton = app.buttons["返回"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Metric custom back button should be present")
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
        let backButton = app.buttons["返回"]
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
        XCTAssertTrue(app.staticTexts["睡眠"].firstMatch.exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["sleep-timeline-card"].waitForExistence(timeout: 5),
            "Sleep timeline card should be present in sleep detail"
        )

        let closeButton = app.buttons["关闭"].firstMatch
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
        XCTAssertTrue(
            app.buttons["返回"].exists,
            "Pushed metric detail should expose its custom back button"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["sleep-timeline-card"].waitForExistence(timeout: 5),
            "Sleep timeline card should be present in sleep detail push"
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "sleep-detail-push"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let backButton = app.buttons["返回"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Metric custom back button should be present")
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
            let backButton = app.buttons["返回"]
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
        XCTAssertTrue(app.staticTexts["负荷"].firstMatch.waitForExistence(timeout: 5))
        let closeButton = app.buttons["关闭"].firstMatch
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
        XCTAssertTrue(app.staticTexts["压力"].firstMatch.waitForExistence(timeout: 5))
        let closeButton = app.buttons["关闭"].firstMatch
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
        XCTAssertTrue(app.staticTexts["能量"].firstMatch.waitForExistence(timeout: 5))
        let closeButton = app.buttons["关闭"].firstMatch
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
        ] + (extraArguments.contains("-UIPreferredContentSizeCategoryName") ? [] : [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ]) + extraArguments
        app.launch()
        return app
    }

    private func selectTab(
        index: Int,
        label: String,
        in app: XCUIApplication
    ) {
        if index == 3 {
            let ask = app.descendants(matching: .any)["bodyseek-ask-input"]
            XCTAssertTrue(ask.waitForExistence(timeout: 8), "Inline Coach entry should be reachable")
            ask.tap()
            return
        }
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
        if index == 3 {
            XCTAssertTrue(app.descendants(matching: .any)["inline-coach-panel"].waitForExistence(timeout: 10))
            return
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["surface-\(index)"].waitForExistence(timeout: 10),
            "Primary surface \(index) did not become visible"
        )
    }
}

/// Design review walkthrough on preview data. Runs only when
/// `TEST_RUNNER_BODYSEEK_WALKTHROUGH_DIR` is set, and writes one PNG per step
/// there so a reviewer can page through the daily flow.
@MainActor
final class BodySeekWalkthroughUITests: XCTestCase {
    // Initialization and capture both run on the main actor.
    private var outputDirectory: URL?
    private var step = 0

    func testDailyWalkthrough() throws {
        continueAfterFailure = true
        guard let path = ProcessInfo.processInfo.environment["BODYSEEK_WALKTHROUGH_DIR"], !path.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_BODYSEEK_WALKTHROUGH_DIR to record the walkthrough.")
        }
        outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory!, withIntermediateDirectories: true)

        let appearance = ProcessInfo.processInfo.environment["BODYSEEK_WALKTHROUGH_APPEARANCE"] ?? "light"
        let app = XCUIApplication()
        app.launchArguments = [
            "-vela_onboarding_completed", "YES",
            "-vela_app_language", "simplifiedChinese",
            "-velaPreviewDashboard", "-velaLegacyInterface", "-velaDisableNetworkAI",
            "-vela_dark_mode", appearance,
            "-velaInitialTab", "0",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ]
        app.launch()
        let any = app.descendants(matching: .any)
        XCTAssertTrue(any["today-score-recovery"].waitForExistence(timeout: 10))
        capture("today-top")

        app.swipeUp()
        capture("today-scrolled")
        app.swipeDown(); app.swipeDown()

        let evidence = any["today-advice-evidence"]
        if evidence.waitForExistence(timeout: 3) {
            for _ in 0..<3 where !evidence.isHittable { app.swipeUp() }
            evidence.tap()
            capture("today-evidence")
            if app.buttons["关闭"].exists { app.buttons["关闭"].tap() }
            app.swipeDown(); app.swipeDown()
        }

        let context = app.buttons["bodyseek-context"]
        if context.waitForExistence(timeout: 3) {
            context.tap()
            capture("ask-context-sheet")
            if app.buttons["关闭"].exists { app.buttons["关闭"].tap() }
        }

        let field = any["bodyseek-ask-input"]
        field.tap()
        capture("ask-focused")
        field.typeText("今天适合练腿吗")
        capture("ask-draft")
        if app.buttons["发送"].exists { app.buttons["发送"].tap() }
        capture("ask-inline-answer")
        if app.buttons["收起对话"].exists { app.buttons["收起对话"].tap() }
        capture("today-after-ask")

        any["today-score-recovery"].tap()
        capture("detail-recovery")
        app.swipeUp()
        capture("detail-recovery-scrolled")
        if app.buttons["metric-detail-close"].exists { app.buttons["metric-detail-close"].tap() }
        any["today-secondary-stress"].tap()
        capture("detail-stress")
        if app.buttons["metric-detail-close"].exists { app.buttons["metric-detail-close"].tap() }

        XCTAssertTrue(app.buttons["tab-1"].waitForExistence(timeout: 5))
        app.buttons["tab-1"].tap()
        XCTAssertTrue(any["trends-score-recovery"].waitForExistence(timeout: 8))
        capture("trends-30d")
        if app.buttons["trends-history-coverage"].exists {
            app.buttons["trends-history-coverage"].tap()
            capture("trends-coverage-sheet")
            if app.buttons["关闭"].exists { app.buttons["关闭"].tap() }
        }
        if app.buttons["trends-horizon-7d"].exists { app.buttons["trends-horizon-7d"].tap(); capture("trends-7d") }
        if app.buttons["trends-horizon-3y"].exists { app.buttons["trends-horizon-3y"].tap(); capture("trends-3y") }
        if app.buttons["trends-horizon-30d"].exists { app.buttons["trends-horizon-30d"].tap() }
        app.swipeUp()
        capture("trends-scrolled")
        app.swipeUp(); app.swipeUp()
        capture("trends-bottom")
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        if any["trends-score-sleepScore"].waitForExistence(timeout: 3) {
            any["trends-score-sleepScore"].tap()
            capture("detail-sleep")
            app.swipeUp()
            capture("detail-sleep-scrolled")
            if app.buttons["metric-detail-close"].exists { app.buttons["metric-detail-close"].tap() }
        }

        XCTAssertTrue(app.buttons["tab-2"].waitForExistence(timeout: 5))
        app.buttons["tab-2"].tap()
        capture("plan-top")
        app.swipeUp()
        capture("plan-scrolled")
        app.swipeDown()

        app.buttons["bodyseek-menu"].tap()
        capture("side-panel")
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 1.2)
        step += 1
        guard let outputDirectory else { return }
        let file = outputDirectory.appendingPathComponent(String(format: "%02d-%@.png", step, name))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: file)
    }
}
