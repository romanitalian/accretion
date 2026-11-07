import XCTest

/// App Store screenshots. `make screenshots` runs these on an iPhone and an iPad simulator and pulls
/// the attachments out of the .xcresult. Each test opens one of the Debug demo scenes via launch arguments.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Launches with `-Key YES` flags (read by GameScene in Debug builds), waits for the scene to settle.
    private func launch(_ flags: [String] = [], settle: TimeInterval = 3) {
        app.launchArguments = flags.flatMap { ["-\($0)", "YES"] } + ["-AppleLanguages", "(ru)"]
        app.launch()
        Thread.sleep(forTimeInterval: settle)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test01_Showcase() {
        launch(["AccretionShowcase"], settle: 4)
        shot("01_showcase")
    }

    func test02_BlackHole() {
        launch(["AccretionBlackHoleDemo"], settle: 4)
        shot("02_black_hole")
    }

    func test03_Supernova() {
        // The supernova goes off 2 s after start; catch the blast wave.
        launch(["AccretionSupernovaDemo"], settle: 2.4)
        shot("03_supernova")
    }

    func test04_Astronaut() {
        launch(["AccretionAstronautDemo"])
        shot("04_astronaut")
    }

    func test05_FirstLevel() {
        launch()
        shot("05_first_level")
    }

    func test06_Menu() {
        launch()
        let menu = app.buttons["menuButton"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("06_menu")
    }
}
