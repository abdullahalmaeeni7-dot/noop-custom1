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
        XCTAssertFalse(app.buttons["setupContinue"].isEnabled)
        let birthday = app.buttons["profileBirthDate"]
        reveal(birthday, in: app)
        birthday.tap()
        XCTAssertTrue(app.buttons["profileBirthDateDone"].waitForExistence(timeout: 5))
        app.buttons["profileBirthDateDone"].tap()
        let man = app.buttons["profileGender-man"]
        reveal(man, in: app); man.tap()
        let left = app.buttons["profileWrist-left"]
        reveal(left, in: app); left.tap()
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
        XCTAssertFalse(app.buttons["setupData-person.crop.circle"].exists)
        XCTAssertFalse(app.buttons["setupData-heart.fill"].exists)
        XCTAssertTrue(app.buttons["setupData-square.and.arrow.down"].exists)
        capture("03-sync-and-import", app)

        let export = app.buttons["setupData-square.and.arrow.up"]
        reveal(export, in: app)
        XCTAssertTrue(export.isHittable)
        export.tap()
        XCTAssertTrue(app.navigationBars["Export Data"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["exportConnectAccount"].exists)
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
        XCTAssertTrue(app.buttons["setupLanguage-ar"].exists)
        capture("07-arabic-welcome", app)
    }

    func testCCalendarAndLiveLayoutKeepHomeOnToday() {
        let app = XCUIApplication()
        app.launchArguments = ["-whoop.language.v1", "en", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["homeTracker"].waitForExistence(timeout: 15))
        app.buttons["openRecoveryCalendar"].tap()
        XCTAssertTrue(app.navigationBars["Recovery Calendar"].waitForExistence(timeout: 5))
        app.buttons["calendarToday"].tap()
        app.buttons["tab-menu"].tap()
        let live = app.buttons["openLiveCamera"]
        reveal(live, in: app); XCTAssertTrue(live.isHittable); live.tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 2) {
            for label in ["Allow", "OK"] where permission.buttons[label].exists { permission.buttons[label].tap(); break }
        }
        XCTAssertTrue(app.buttons["liveControls"].waitForExistence(timeout: 10))
        let recovery = app.buttons["liveMode-recovery"]
        if !recovery.isHittable { app.swipeLeft() }
        recovery.tap()
        app.buttons["liveControls"].tap()
        let size = app.sliders["liveLayoutSize"]
        reveal(size, in: app); XCTAssertTrue(size.exists)
        size.adjust(toNormalizedSliderPosition: 0.2)
        capture("11-live-size-controls", app)
        let adjust = app.buttons["liveAdjust"]
        reveal(adjust, in: app); adjust.tap()
        let overlay = app.descendants(matching: .any).matching(identifier: "liveOverlay-recovery").firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        let center = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 25, dy: -35)))
        capture("12-live-adjusted-recovery", app)
        app.buttons["liveSaveChanges"].tap()
        app.buttons["liveControls"].tap()
        let day = app.buttons["liveRecordedDay"]
        reveal(day, in: app); day.tap()
        XCTAssertTrue(app.navigationBars["Recovery Calendar"].waitForExistence(timeout: 5))
        let previous = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: Date())!
        displayedDay(previous, in: app).tap()
        app.navigationBars["Live Controls"].buttons["Done"].tap()
        app.buttons["closeLive"].tap()
        app.buttons["tab-home"].tap()
        XCTAssertTrue(app.buttons["openRecoveryCalendar"].label.contains("TODAY"), "Live's recorded date must not change Home's date.")
    }

    func testDConfirmSleepPersistsAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["-whoop.language.v1", "en", "-whoop.setup.completed.v1", "YES"]
        app.launch()
        let ring = app.buttons["scoreRing-sleep"]
        XCTAssertTrue(ring.waitForExistence(timeout: 15))
        ring.tap()
        let log = app.buttons["sleepReviewEntry"]
        reveal(log, in: app)
        XCTAssertTrue(log.isHittable)
        log.tap()
        let save = app.buttons["I was asleep · Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Your confirmed sleep"), object: log)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed)
        app.terminate()
        app.launch()
        XCTAssertTrue(ring.waitForExistence(timeout: 15))
        ring.tap()
        reveal(log, in: app)
        XCTAssertTrue(log.label.contains("Your confirmed sleep"))
        capture("19-confirmed-sleep", app)
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


/// This class runs separately against the disposable workflow's explicit fixture.
final class ReferenceFeatureTests: XCTestCase {
    func testRecoveryCalendarSleepStagesAndHealthMeasurements() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-whoop.language.v1", "en", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["scoreRing-sleep"].waitForExistence(timeout: 15))
        app.buttons["openRecoveryCalendar"].tap()
        XCTAssertTrue(app.navigationBars["Recovery Calendar"].waitForExistence(timeout: 5))
        let calendar = Calendar(identifier: .gregorian)
        for (offset, score) in [(-2, 82), (-5, 29)] {
            let day = calendar.date(byAdding: .day, value: offset, to: Date())!
            XCTAssertTrue(displayedDay(day, in: app).label.contains("\(score)%"))
        }
        capture("08-colored-recovery-calendar", app)
        app.buttons["calendarToday"].tap()
        app.buttons["scoreRing-sleep"].tap()
        XCTAssertTrue(app.staticTexts["SLEEP STAGES"].waitForExistence(timeout: 5))
        capture("09-sleep-stages", app)
        let period = app.segmentedControls["metricTrendPeriod"]
        for _ in 0..<4 { if period.isHittable { break }; app.swipeUp() }
        period.buttons["30 DAYS"].tap()
        app.buttons["Back"].tap()
        let monitor = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "HEALTH MONITOR")).firstMatch
        for _ in 0..<5 { if monitor.isHittable { break }; app.swipeDown() }
        monitor.tap()
        XCTAssertTrue(app.staticTexts["98"].waitForExistence(timeout: 5))
        capture("10-health-measurements", app)
    }
    func testSavedPhotoOverlaysAndPrimaryTabs() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-whoop.language.v1", "en", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["scoreRing-sleep"].waitForExistence(timeout: 15))

        for (tabID, captureName) in [("health", "15-health"), ("community", "16-community"), ("menu", "17-more")] {
            let tab = app.buttons["tab-" + tabID]
            tab.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: tab)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 4), .completed)
            capture(captureName, app)
        }

        let live = app.buttons["openLiveCamera"]
        for _ in 0..<6 where !live.isHittable { app.swipeUp() }
        live.tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 2) {
            for label in ["Allow", "OK"] where permission.buttons[label].exists {
                permission.buttons[label].tap()
                break
            }
        }

        let gallery = app.buttons["Choose a saved photo"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 10))
        gallery.tap()
        try selectImportedPhoto(in: app)
        let shutter = app.buttons["Capture photo with stats"]
        let shutterReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true AND hittable == true"),
            object: shutter
        )
        XCTAssertEqual(XCTWaiter.wait(for: [shutterReady], timeout: 12), .completed)
        app.buttons["liveMode-overview"].tap()
        let overlay = app.descendants(matching: .any).matching(identifier: "liveMetrics").firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        for value in ["15.8", "38%", "3:44"] { XCTAssertTrue(overlay.label.contains(value), overlay.label) }
        capture("13-live-overview-photo", app)

        let recovery = app.buttons["liveMode-recovery"]
        if !recovery.isHittable { app.swipeLeft() }
        recovery.tap()
        XCTAssertTrue(overlay.label.contains("38%"))
        app.buttons["liveControls"].tap()
        let slider = app.sliders["liveLayoutSize"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let previous = try XCTUnwrap(slider.value as? String)
        slider.adjust(toNormalizedSliderPosition: 0.16)
        XCTAssertNotEqual(slider.value as? String, previous)
        app.navigationBars["Live Controls"].buttons["Done"].tap()
        capture("14-live-resized-recovery-photo", app)
    }

    /// PhotosUI can present its first-use sheet or expose the thumbnail grid
    /// through an out-of-process accessibility tree on different iOS releases.
    private func selectImportedPhoto(in app: XCUIApplication) throws {
        let picker = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow.photospicker")
        let photoLabel = NSPredicate(format: "label BEGINSWITH[c] %@ OR label CONTAINS[c] %@", "Photo,", "review-photo")
        let deadline = Date().addingTimeInterval(25)
        repeat {
            var hosts = [app]
            if picker.state == .runningForeground { hosts.append(picker) }
            for host in hosts {
                let welcome = host.buttons["Continue"]
                if welcome.exists && welcome.isHittable {
                    welcome.tap()
                    continue
                }
                let queries = [
                    host.descendants(matching: .any).matching(photoLabel),
                    host.collectionViews.cells,
                    host.scrollViews.images,
                    host.scrollViews.buttons,
                    host.images
                ]
                for query in queries {
                    for tile in query.allElementsBoundByIndex {
                        let bounds = tile.frame
                        // Square thumbnails occupy a grid column. Header icons,
                        // controls and the underlying full-screen preview do not.
                        guard bounds.width >= 65, bounds.width <= app.frame.width * 0.54,
                              bounds.height >= 65, abs(bounds.width - bounds.height) <= 12,
                              tile.isEnabled, tile.isHittable else { continue }
                        tile.tap()
                        return
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        } while Date() < deadline
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "18-system-photo-picker-failure"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "photo-picker-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        throw NSError(domain: "ReferenceFeatureTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Photos did not expose a selectable imported thumbnail. See the picker screenshot and hierarchy."
        ])
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}


/// Call newest to oldest. A seven-day review can cross into the preceding month.
private func displayedDay(_ date: Date, in app: XCUIApplication) -> XCUIElement {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd"
    let day = app.buttons["calendarDay-" + formatter.string(from: date)]
    if !day.exists {
        app.buttons["Previous month"].tap()
        XCTAssertTrue(day.waitForExistence(timeout: 3))
    }
    return day
}
