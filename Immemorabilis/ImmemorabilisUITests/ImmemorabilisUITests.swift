import XCTest

final class ImmemorabilisUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if (testRun?.failureCount ?? 0) > 0 {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "Failure"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testOnboardingNavigatesFromWelcomeToAgenda() {
        let app = launch(startAtHome: false)
        let next = app.buttons["onboarding-next"]

        XCTAssertTrue(app.staticTexts["Immemorabilis"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(next.exists)

        next.tap()
        assertText(containing: "Your Reminders", in: app)

        app.buttons["onboarding-back"].tap()
        XCTAssertTrue(app.staticTexts["Immemorabilis"].firstMatch.waitForExistence(timeout: 2))

        next.tap()
        next.tap()
        assertText(containing: "Connect Apple Reminders", in: app)

        next.tap()
        assertText(containing: "Choose your lists", in: app)

        next.tap()
        assertText(containing: "Enable gentle follow-through", in: app)

        next.tap()
        assertText(containing: "Choose one notification voice", in: app)

        next.tap()
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Send revised methods section"].exists)
    }

    @MainActor
    func testDeniedRemindersAccessDoesNotTrapOnboarding() {
        let app = launch(startAtHome: false, remindersDenied: true)
        let next = app.buttons["onboarding-next"]

        next.tap()
        next.tap()
        assertText(containing: "Connect Apple Reminders", in: app)

        next.tap()
        assertText(containing: "Choose your lists", in: app)
        XCTAssertTrue(app.buttons["onboarding-back"].exists)
    }

    @MainActor
    func testCreatesTaskAndNavigatesEditorSections() {
        let app = launch(startAtHome: true)

        app.buttons["new-task-button"].tap()
        XCTAssertTrue(app.staticTexts["New Task"].waitForExistence(timeout: 3))

        let title = app.textFields["task-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.tap()
        title.typeText("Read chapter tomorrow")

        app.buttons["Date"].tap()
        XCTAssertTrue(app.navigationBars["Date"].waitForExistence(timeout: 2))
        app.buttons["Done"].tap()

        app.buttons["editor-notes"].tap()
        let notes = app.textViews.firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 2))
        notes.tap()
        notes.typeText("Compare the methods section with https://example.edu/paper")

        app.buttons["editor-location"].tap()
        XCTAssertTrue(app.textFields["Address or place"].waitForExistence(timeout: 2))

        app.buttons["editor-repeat"].tap()
        XCTAssertTrue(app.buttons["Repeat"].firstMatch.waitForExistence(timeout: 2))

        app.buttons["screen-save"].tap()
        XCTAssertTrue(app.staticTexts["Read chapter tomorrow"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["New Task"].exists)
    }

    @MainActor
    func testEditsSnoozesAndCompletesExistingTask() {
        let app = launch(startAtHome: true)
        let taskTitle = "Send revised methods section"

        app.staticTexts[taskTitle].tap()
        XCTAssertTrue(app.staticTexts["Edit Task"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["task-title"].value as? String, taskTitle)
        app.buttons["screen-cancel"].tap()

        let snooze = app.buttons["Re-remind me about \(taskTitle)"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 2))
        snooze.tap()
        XCTAssertTrue(app.buttons["15 minutes"].waitForExistence(timeout: 2))
        app.buttons["15 minutes"].tap()
        XCTAssertTrue(app.staticTexts[taskTitle].waitForExistence(timeout: 2))

        app.buttons["Complete \(taskTitle)"].tap()
        XCTAssertTrue(app.buttons["Mark incomplete"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSettingsAboutAndAccentNavigation() {
        let app = launch(startAtHome: true)

        app.buttons["settings-button"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Re-Remind After"].exists)

        let blue = app.buttons["Blue"]
        XCTAssertTrue(blue.waitForExistence(timeout: 2))
        blue.tap()
        XCTAssertTrue(app.staticTexts["Settings"].exists)

        let about = app.buttons["about-feedback-button"]
        XCTAssertTrue(about.waitForExistence(timeout: 2))
        var attempts = 0
        while !about.isHittable && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(about.isHittable)
        about.tap()
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Discuss on GitHub Issues"].exists)
        XCTAssertTrue(app.buttons["View Onboarding Again"].exists)

        app.buttons.matching(identifier: "screen-close").element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 2))
        app.buttons.matching(identifier: "screen-close").firstMatch.tap()
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func launch(startAtHome: Bool, remindersDenied: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", startAtHome ? "-uiTestStartHome" : "-uiTestStartOnboarding"]
        if remindersDenied { app.launchArguments.append("-uiTestRemindersDenied") }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        return app
    }

    @MainActor
    private func assertText(containing text: String, in app: XCUIApplication, timeout: TimeInterval = 3) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        XCTAssertTrue(app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: timeout))
    }
}
