import XCTest

/// UI v4 验收截图：只有设置了环境变量 `UIV4_SHOT_SUFFIX`（light / dark）时才运行，
/// 否则跳过，不影响日常 UI 测试。截图写入 `docs/validation/ui-v4/`。
@MainActor
final class UIv4ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let suffix = ProcessInfo.processInfo.environment["UIV4_SHOT_SUFFIX"]
        try XCTSkipIf(suffix == nil || suffix?.isEmpty == true, "仅在截图流程中运行")
    }

    private var suffix: String {
        ProcessInfo.processInfo.environment["UIV4_SHOT_SUFFIX"] ?? "light"
    }

    private func launchApp(tab: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-velaPreviewDashboard", "-velaInitialTab", String(tab)]
        app.launch()
        return app
    }

    private func save(_ name: String, in app: XCUIApplication) throws {
        let home = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] ?? NSHomeDirectory()
        let directory = home + "/Developer/BodySeek/bodyseek-1/docs/validation/ui-v4"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let data = app.screenshot().pngRepresentation
        try data.write(to: URL(fileURLWithPath: "\(directory)/\(name)-\(suffix).png"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(name)-\(suffix)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testShotTodayAdviceSheet() throws {
        let app = launchApp(tab: 0)
        let entry = app.buttons["today-advice-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(app.buttons["today-advice-done"].waitForExistence(timeout: 5))
        sleep(1)
        try save("today-advice-sheet", in: app)
    }
}
