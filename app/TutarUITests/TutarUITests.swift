// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import XCTest

final class TutarUITests: XCTestCase {
    @MainActor
    func testTurkishInstallmentsStayInRecordsAtLargestText() throws {
        let app = launch(language: "tr", locale: "tr_TR", largestText: true)

        XCTAssertTrue(app.navigationBars["Kayıtlar"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.tabBars.buttons["Taksitler"].exists)
        revealInstallment("1/3", in: app)

        goToNextMonth(in: app)
        revealInstallment("2/3", in: app)
        goToNextMonth(in: app)
        revealInstallment("3/3", in: app)
        XCTAssertFalse(app.staticTexts["4/3"].exists)

        try app.performAccessibilityAudit(for: [.sufficientElementDescription]) { issue in
            // XCTest audits the visual currency glyph although the row exposes a localized label/value.
            return issue.element == nil || issue.element?.label.hasPrefix("-₺") == true
        }
    }

    @MainActor
    func testDynamicTypeAuditAtSystemTextSize() throws {
        let app = launch(language: "tr", locale: "tr_TR")
        XCTAssertTrue(app.navigationBars["Kayıtlar"].waitForExistence(timeout: 8))
        let title = app.descendants(matching: .any).matching(identifier: "transactionTitle").firstMatch
        let metadata = app.descendants(matching: .any).matching(identifier: "transactionMetadata").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(metadata.waitForExistence(timeout: 5))
        let standardTitleHeight = title.frame.height
        let standardMetadataHeight = metadata.frame.height

        try app.performAccessibilityAudit(for: [.dynamicType]) { issue in
            // ponytail: iOS 26.2–26.5 misreports semantic SwiftUI text; compare real sizes below.
            let falsePositives = ["transactionCategoryIcon", "transactionTitle", "transactionMetadata"]
            return issue.element == nil || falsePositives.contains(issue.element?.identifier ?? "")
        }

        app.terminate()
        let largeApp = launch(language: "tr", locale: "tr_TR", largestText: true)
        XCTAssertTrue(largeApp.navigationBars["Kayıtlar"].waitForExistence(timeout: 8))
        largeApp.swipeUp()
        let largeTitle = largeApp.descendants(matching: .any).matching(identifier: "transactionTitle").firstMatch
        let largeMetadata = largeApp.descendants(matching: .any).matching(identifier: "transactionMetadata").firstMatch
        XCTAssertTrue(largeTitle.waitForExistence(timeout: 8))
        XCTAssertTrue(largeMetadata.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(largeTitle.frame.height, standardTitleHeight)
        XCTAssertGreaterThan(largeMetadata.frame.height, standardMetadataHeight)
    }

    @MainActor
    func testEnglishAutomaticKeypadAndInstallmentSchedule() {
        let app = launch(language: "en", locale: "en_US", seed: false)

        let add = app.buttons["addTransactionButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()

        XCTAssertTrue(app.otherElements["amountKeypad"].waitForExistence(timeout: 5))
        app.buttons["keypad3"].tap()
        for _ in 0 ..< 5 { app.buttons["keypad0"].tap() }

        let note = app.textFields["noteField"]
        note.tap()
        note.typeText("Laptop")
        app.buttons["keyboardDoneButton"].tap()

        app.buttons["scheduleButton"].tap()
        XCTAssertTrue(app.buttons["Installments"].waitForExistence(timeout: 5))
        app.buttons["Installments"].tap()
        app.buttons["Done"].tap()

        app.buttons["keypadSubmit"].tap()
        XCTAssertTrue(app.navigationBars["Records"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1/3"].waitForExistence(timeout: 5))
        app.buttons["nextMonthButton"].tap()
        XCTAssertTrue(app.staticTexts["2/3"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEnglishEditorKeepsKeypadUsableAtLargestText() {
        let app = launch(language: "en", locale: "en_US", seed: false, largestText: true)
        let add = app.buttons["addTransactionButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()

        XCTAssertTrue(app.otherElements["amountKeypad"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["amountDisplay"].exists)
        XCTAssertTrue(app.buttons["keypad0"].isHittable)
        XCTAssertTrue(app.buttons["keypadSubmit"].isHittable)
    }

    @MainActor
    func testSettingsExposeDimeStyleDataTools() {
        let app = launch(language: "en", locale: "en_US")
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.staticTexts["Number entry"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(app.buttons["Import data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Export transactions as CSV"].exists)
        XCTAssertTrue(app.buttons["Export complete backup"].exists)
        XCTAssertFalse(app.staticTexts["Tip Jar"].exists)
        XCTAssertFalse(app.staticTexts["Subscription"].exists)
    }

    @MainActor
    func testCategoryEmojiFieldOpensEmojiKeyboard() {
        let app = launch(language: "en", locale: "en_US", seed: false)
        app.tabBars.buttons["Settings"].tap()
        for _ in 0 ..< 4 where !app.buttons["Categories"].exists { app.swipeUp() }
        app.buttons["Categories"].tap()
        app.buttons["Add category"].tap()

        let emoji = app.textFields["categoryEmojiField"]
        XCTAssertTrue(emoji.waitForExistence(timeout: 5))
        emoji.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.keys["😀"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func launch(
        language: String,
        locale: String,
        seed: Bool = true,
        largestText: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-appLanguage", language,
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ]
        if largestText {
            app.launchArguments.append("-ui-test-largest-text")
        }
        if seed { app.launchArguments.append("-seed-installments") }
        app.launch()
        return app
    }

    @MainActor
    private func revealInstallment(_ label: String, in app: XCUIApplication) {
        let installment = app.staticTexts[label]
        for _ in 0 ..< 5 where !installment.exists { app.swipeUp() }
        XCTAssertTrue(installment.waitForExistence(timeout: 3))
    }

    @MainActor
    private func goToNextMonth(in app: XCUIApplication) {
        let button = app.buttons["nextMonthButton"]
        for _ in 0 ..< 5 where !button.isHittable { app.swipeDown() }
        XCTAssertTrue(button.isHittable)
        button.tap()
    }
}
