// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import XCTest

final class TutarUITests: XCTestCase {
    @MainActor
    func testAppLockSuccessStaysUnlockedAfterForegroundReturn() {
        let app = launch(
            language: "tr",
            locale: "tr_TR",
            lockAuthenticationSucceeds: true
        )

        XCTAssertTrue(app.navigationBars["Kayıtlar"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(app.navigationBars["Kayıtlar"].exists)
        XCTAssertFalse(app.buttons["unlockButton"].exists)

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.navigationBars["Kayıtlar"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(app.navigationBars["Kayıtlar"].exists)
        XCTAssertFalse(app.buttons["unlockButton"].exists)
    }

    @MainActor
    func testFailedAppLockDoesNotRetryAndIsLocalized() {
        let turkish = launch(
            language: "tr",
            locale: "tr_TR",
            lockAuthenticationSucceeds: false
        )
        XCTAssertTrue(turkish.staticTexts["Uygulama kilitli"].waitForExistence(timeout: 8))
        XCTAssertTrue(turkish.buttons["Kilidi aç"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(turkish.buttons["Kilidi aç"].exists)
        XCTAssertFalse(turkish.navigationBars["Kayıtlar"].exists)
        turkish.terminate()

        let english = launch(
            language: "en",
            locale: "en_US",
            lockAuthenticationSucceeds: false
        )
        XCTAssertTrue(english.staticTexts["App locked"].waitForExistence(timeout: 8))
        XCTAssertTrue(english.buttons["Unlock"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(english.buttons["Unlock"].exists)
        XCTAssertFalse(english.navigationBars["Records"].exists)
    }

    @MainActor
    func testLockAndEmptyStateControlsPassContrastAudit() throws {
        for appearance in ["Light", "Dark"] {
            let locked = launch(
                language: "en",
                locale: "en_US",
                appearance: appearance,
                lockAuthenticationSucceeds: false
            )
            XCTAssertTrue(locked.buttons["unlockButton"].waitForExistence(timeout: 8))
            try locked.performAccessibilityAudit(for: [.contrast]) { self.contrastFalsePositive($0) }
            locked.terminate()

            let app = launch(
                language: "en",
                locale: "en_US",
                seed: false,
                appearance: appearance
            )
            XCTAssertTrue(app.buttons["emptyTransactionAddButton"].waitForExistence(timeout: 8))
            try app.performAccessibilityAudit(for: [.contrast]) { self.contrastFalsePositive($0) }

            app.buttons["emptyTransactionAddButton"].tap()
            XCTAssertTrue(app.buttons["keypadSubmit"].waitForExistence(timeout: 5))
            try app.performAccessibilityAudit(for: [.contrast]) { self.contrastFalsePositive($0) }
            app.terminate()

            let budgets = launch(
                language: "en",
                locale: "en_US",
                seed: false,
                appearance: appearance
            )
            openTab("Budgets", in: budgets)
            XCTAssertTrue(budgets.buttons["emptyBudgetAddButton"].waitForExistence(timeout: 5))
            try budgets.performAccessibilityAudit(for: [.contrast]) { self.contrastFalsePositive($0) }
            budgets.terminate()
        }
    }

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
            // ponytail: iOS 26 audits the rendered TRY glyph even though the combined row has a full VoiceOver label.
            return issue.element == nil || issue.element?.label.contains("₺") == true
        }
    }

    @MainActor
    func testDynamicTypeAuditAtSystemTextSize() throws {
        let app = launch(language: "tr", locale: "tr_TR")
        XCTAssertTrue(app.navigationBars["Kayıtlar"].waitForExistence(timeout: 8))
        let row = app.descendants(matching: .any).matching(identifier: "transactionRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let standardRowHeight = row.frame.height

        try app.performAccessibilityAudit(for: [.dynamicType]) { issue in
            // ponytail: iOS 26.2–26.5 misreports semantic SwiftUI text; compare real sizes below.
            let falsePositives = ["transactionCategoryIcon", "transactionTitle", "transactionRow"]
            return issue.element == nil || falsePositives.contains(issue.element?.identifier ?? "")
        }

        app.terminate()
        let largeApp = launch(language: "tr", locale: "tr_TR", largestText: true)
        XCTAssertTrue(largeApp.navigationBars["Kayıtlar"].waitForExistence(timeout: 8))
        largeApp.swipeUp()
        let largeRow = largeApp.descendants(matching: .any).matching(identifier: "transactionRow").firstMatch
        XCTAssertTrue(largeRow.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(largeRow.frame.height, standardRowHeight)
        XCTAssertLessThan(largeRow.frame.height, 70, "Transaction row wrapped instead of staying on one line")
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
        let monthSummary = app.otherElements["monthSummary"]
        XCTAssertTrue(monthSummary.waitForExistence(timeout: 5))
        monthSummary.swipeLeft()
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
        openTab("Settings", in: app)

        XCTAssertTrue(app.staticTexts["Number entry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["App Lock"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "currencyPicker").firstMatch.exists)
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
        openTab("Settings", in: app)
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
    func testTurkishCurrencyCanBeChangedFromTRY() {
        let app = launch(language: "tr", locale: "tr_TR", seed: false)
        openTab("Ayarlar", in: app)

        let picker = app.descendants(matching: .any).matching(identifier: "currencyPicker").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()

        let search = app.searchFields["Para birimi veya kod ara"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("USD")

        let usd = app.descendants(matching: .any).matching(identifier: "currencyOption-USD").firstMatch
        XCTAssertTrue(usd.waitForExistence(timeout: 5))
        usd.tap()

        let selectedPicker = app.descendants(matching: .any).matching(identifier: "currencyPicker").firstMatch
        XCTAssertTrue(selectedPicker.waitForExistence(timeout: 5))
        let selectedDescription = "\(selectedPicker.label) \(String(describing: selectedPicker.value))"
        XCTAssertTrue(selectedDescription.contains("USD"), selectedDescription)
    }

    @MainActor
    private func launch(
        language: String,
        locale: String,
        seed: Bool = true,
        largestText: Bool = false,
        appearance: String? = nil,
        lockAuthenticationSucceeds: Bool? = nil
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
        if let appearance {
            app.launchArguments += ["-AppleInterfaceStyle", appearance]
        }
        if let lockAuthenticationSucceeds {
            app.launchArguments.append("-ui-test-app-lock")
            if !lockAuthenticationSucceeds {
                app.launchArguments.append("-ui-test-authentication-fails")
            }
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

    @MainActor
    private func openTab(_ label: String, in app: XCUIApplication) {
        let tab = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    private func contrastFalsePositive(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        // ponytail: this regression targets controls; iOS 26 flags native secondary text and color emoji pixels on iPad.
        [.staticText, .searchField].contains(issue.element?.elementType) || issue.element?.label == "🛒"
    }
}
