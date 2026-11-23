import XCTest

/// Runs against the real app in an empty simulator. No device or score mocks.
final class SetupFlowTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAFirstLaunchPairsThenOffersImportAndExport() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-whoop.language.v1", "en", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["setupGetStarted"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["setupTrackerFirst"].exists)
        XCTAssertFalse(app.buttons["setupImportFirst"].exists)
        capture("01-welcome", app)
        app.buttons["setupGetStarted"].tap()
        let name = app.textFields["Your name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Alex Avery")
        app.buttons["setupContinue"].tap()
        XCTAssertTrue(app.buttons["setupSearchTracker"].waitForExistence(timeout: 5))
        capture("02-pairing", app)

        // Setup progress and the saved profile survive a normal app restart.
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["setupSearchTracker"].waitForExistence(timeout: 10))
        app.buttons["setupSearchTracker"].tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 2), permission.buttons["Allow"].exists { permission.buttons["Allow"].tap() }
        XCTAssertFalse(app.staticTexts["RECEIVING DATA"].exists, "A simulator must not pretend to receive tracker measurements.")
        app.buttons["setupContinue"].tap() // Hardware is absent, so connect later.
        XCTAssertTrue(app.staticTexts["Sync your data."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["setupSearchTracker"].exists)
        capture("03-sync-and-import", app)

        let export = app.buttons["setupData-square.and.arrow.up"]
        reveal(export, in: app)
        XCTAssertTrue(export.isHittable)
        export.tap()
        XCTAssertTrue(app.navigationBars["Export Data"].waitForExistence(timeout: 5))
        let json = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "SAVE JSON")).firstMatch
        reveal(json, in: app)
        XCTAssertTrue(json.exists && json.isEnabled, "The profile saved before pairing must be exportable in this same setup.")
        capture("04-export", app)
        app.buttons["exportDone"].tap()
        app.buttons["setupContinue"].tap()
        XCTAssertTrue(app.buttons["homeTracker"].waitForExistence(timeout: 10))
        capture("05-personal-home", app)
        app.buttons["homeTracker"].tap()
        XCTAssertTrue(app.navigationBars["DEVICE SETTINGS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["setupSearchTracker"].exists)
        XCTAssertFalse(app.staticTexts["CONNECTION DETAILS"].exists)
        capture("06-device-status", app)
        app.buttons["ADVANCED"].tap()
        XCTAssertTrue(app.staticTexts["CONNECTION DETAILS"].waitForExistence(timeout: 5))
    }

    func testBArabicWelcomeHasTheSameSingleEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["-whoop.language.v1", "ar", "-AppleLanguages", "(ar)",
                               "-whoop.setup.completed.v1", "NO", "-whoop.setup.step.v2", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["setupGetStarted"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["setupImportFirst"].exists)
        capture("07-arabic-welcome", app)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.swipeUp()
        }
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 1) // Let the app's 0.7-second ring transition settle before capture.
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
