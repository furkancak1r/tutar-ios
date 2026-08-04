// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import AppIntents
import XCTest

final class TutarUITests: XCTestCase {
    @MainActor
    func testTurkishInstallmentsAtLargestText() throws {
        let app = launch(language: "tr", locale: "tr_TR")

        let installmentsTab = app.buttons["Taksitler"].firstMatch
        XCTAssertTrue(installmentsTab.waitForExistence(timeout: 8))
        installmentsTab.tap()
        XCTAssertTrue(app.staticTexts["1/3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2/3"].exists)
        let finalInstallment = app.staticTexts["3/3"]
        if finalInstallment.exists == false { app.swipeUp() }
        XCTAssertTrue(finalInstallment.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["4/3"].exists)
        try app.performAccessibilityAudit(for: [.dynamicType, .sufficientElementDescription]) { issue in
            // ponytail: iPadOS 26 reports its five floating TabView UILabels as nil-element
            // Dynamic Type failures; keep auditing every issue associated with app content.
            issue.auditType == .dynamicType && issue.element == nil
        }
    }

    @MainActor
    func testEnglishAddInstallmentFlow() {
        let app = launch(language: "en", locale: "en_US", seed: false)

        let add = app.buttons["addTransactionButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()

        let amount = app.textFields["amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("3000")

        let note = app.textFields["noteField"]
        note.tap()
        note.typeText("Laptop")
        let done = app.buttons["keyboardDoneButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()

        let installment = app.switches["installmentToggle"]
        XCTAssertTrue(installment.exists)
        XCTAssertTrue(installment.isEnabled, installment.debugDescription)
        installment.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(installment.value as? String, "1")
        app.buttons["saveTransactionButton"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 5))

        let installmentsTab = app.buttons["Installments"].firstMatch
        XCTAssertTrue(installmentsTab.waitForExistence(timeout: 5))
        installmentsTab.tap()
        XCTAssertTrue(app.staticTexts["1/3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["3/3"].exists)
    }

    @MainActor
    private func launch(
        language: String,
        locale: String,
        seed: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-appLanguage", language,
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        if seed { app.launchArguments.append("-seed-installments") }
        app.launch()
        return app
    }
}
