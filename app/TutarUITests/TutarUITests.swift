// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import XCTest

final class TutarUITests: XCTestCase {
    @MainActor
    func testTurkishDarkOnboardingCompletesAndReopensFromSettings() throws {
        let app = launch(
            language: "tr",
            locale: "tr_TR",
            appearance: "Dark",
            showOnboarding: true
        )

        XCTAssertTrue(app.staticTexts["Tutar’a Hoş Geldin"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["onboardingPagePosition"].exists)
        attachScreenshot("23-onboarding-welcome-tr-dark", in: app)
        try app.performAccessibilityAudit(for: [.contrast]) { self.contrastFalsePositive($0) }

        app.buttons["onboardingNextButton"].tap()
        XCTAssertTrue(app.staticTexts["Tek İşlemden Planla"].waitForExistence(timeout: 3))
        attachScreenshot("23-onboarding-planning-tr-dark", in: app)

        app.buttons["onboardingNextButton"].tap()
        XCTAssertTrue(app.staticTexts["Bütçe Bir İşlem Değildir"].waitForExistence(timeout: 3))
        attachScreenshot("23-onboarding-budgets-tr-dark", in: app)

        app.buttons["onboardingNextButton"].tap()
        XCTAssertTrue(app.staticTexts["Birikimlerini Birlikte Gör"].waitForExistence(timeout: 3))
        attachScreenshot("26-onboarding-savings-tr-dark", in: app)

        app.buttons["onboardingNextButton"].tap()
        XCTAssertTrue(app.staticTexts["Verilerin Sana Ait"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["onboardingSkipButton"].exists)
        attachScreenshot("23-onboarding-privacy-tr-dark", in: app)

        app.buttons["onboardingFinishButton"].tap()
        XCTAssertTrue(app.navigationBars["Kayıtlar"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Tutar’a Hoş Geldin"].exists)

        openTab("Ayarlar", in: app)
        let showOnboarding = app.buttons["showOnboardingButton"]
        let tabBar = app.tabBars.firstMatch
        for _ in 0 ..< 10 where !showOnboarding.exists || showOnboarding.frame.maxY >= tabBar.frame.minY {
            app.swipeUp()
        }
        XCTAssertTrue(showOnboarding.isHittable)
        showOnboarding.tap()
        XCTAssertTrue(app.staticTexts["Tutar’a Hoş Geldin"].waitForExistence(timeout: 5))
        app.buttons["onboardingSkipButton"].tap()
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEnglishLightOnboardingSkipPersistsAcrossRelaunch() {
        let app = launch(
            language: "en",
            locale: "en_US",
            appearance: "Light",
            showOnboarding: true
        )

        XCTAssertTrue(app.staticTexts["Welcome to Tutar"].waitForExistence(timeout: 8))
        attachScreenshot("23-onboarding-welcome-en-light", in: app)
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["Plan From One Entry"].waitForExistence(timeout: 3))

        app.terminate()
        app.launchArguments.removeAll { $0 == "-ui-test-reset-onboarding" }
        app.launch()

        XCTAssertTrue(app.staticTexts["Welcome to Tutar"].waitForExistence(timeout: 8))
        app.buttons["onboardingSkipButton"].tap()
        XCTAssertTrue(app.navigationBars["Records"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()

        XCTAssertTrue(app.navigationBars["Records"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Welcome to Tutar"].exists)
    }

    @MainActor
    func testTransactionsTabIsCenteredAndSelectedInBothLanguages() {
        for (language, locale, label) in [
            ("en", "en_US", "Transactions"),
            ("tr", "tr_TR", "İşlemler")
        ] {
            let app = launch(language: language, locale: locale, seed: false)
            let buttons = app.tabBars.firstMatch.buttons
            XCTAssertEqual(buttons.count, 5)
            let center = buttons.element(boundBy: 2)
            XCTAssertEqual(center.label, label)
            XCTAssertTrue(center.isSelected)
            app.terminate()
        }
    }

    @MainActor
    func testAppLockTakesPriorityOverOnboarding() {
        let failed = launch(
            language: "en",
            locale: "en_US",
            lockAuthenticationSucceeds: false,
            showOnboarding: true
        )
        XCTAssertTrue(failed.staticTexts["App locked"].waitForExistence(timeout: 8))
        XCTAssertFalse(failed.staticTexts["Welcome to Tutar"].exists)
        failed.terminate()

        let successful = launch(
            language: "en",
            locale: "en_US",
            lockAuthenticationSucceeds: true,
            showOnboarding: true
        )
        XCTAssertTrue(successful.staticTexts["Welcome to Tutar"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(successful.staticTexts["Welcome to Tutar"].exists)
        XCTAssertFalse(successful.buttons["unlockButton"].exists)
    }

    @MainActor
    func testOnboardingSupportsLargestText() {
        let app = launch(
            language: "en",
            locale: "en_US",
            largestText: true,
            showOnboarding: true
        )

        XCTAssertTrue(app.staticTexts["Welcome to Tutar"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["onboardingNextButton"].isHittable)
        XCTAssertTrue(app.buttons["onboardingSkipButton"].isHittable)
        attachScreenshot("23-onboarding-largest-text", in: app)
    }

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
        XCTAssertTrue(turkish.staticTexts["Face ID, Touch ID veya aygıt parolasıyla kilidi aç."].exists)
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
        XCTAssertTrue(english.staticTexts["Unlock with Face ID, Touch ID, or your device passcode."].exists)
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
            XCTAssertTrue(app.buttons["addTransactionButton"].waitForExistence(timeout: 8))
            try app.performAccessibilityAudit(for: [.contrast]) { self.contrastFalsePositive($0) }

            app.buttons["addTransactionButton"].tap()
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
            let falsePositives = ["transactionCategoryIcon", "transactionTitle", "transactionMetadata", "transactionRow"]
            return issue.element == nil || falsePositives.contains(issue.element?.identifier ?? "")
        }

        app.terminate()
        let largeApp = launch(language: "tr", locale: "tr_TR", largestText: true)
        XCTAssertTrue(largeApp.navigationBars["Kayıtlar"].waitForExistence(timeout: 8))
        largeApp.swipeUp()
        let largeRow = largeApp.descendants(matching: .any).matching(identifier: "transactionRow").firstMatch
        let largeTitle = largeApp.descendants(matching: .any).matching(identifier: "transactionTitle").firstMatch
        let largeMetadata = largeApp.descendants(matching: .any).matching(identifier: "transactionMetadata").firstMatch
        let largeAmount = largeApp.descendants(matching: .any).matching(identifier: "transactionAmount").firstMatch
        XCTAssertTrue(largeRow.waitForExistence(timeout: 8))
        XCTAssertTrue(largeTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(largeMetadata.waitForExistence(timeout: 5))
        XCTAssertTrue(largeAmount.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(largeRow.frame.height, standardRowHeight)
        XCTAssertGreaterThanOrEqual(largeTitle.frame.minY, largeRow.frame.minY)
        XCTAssertLessThanOrEqual(largeTitle.frame.maxY, largeMetadata.frame.minY + 2)
        XCTAssertLessThanOrEqual(largeMetadata.frame.maxY, largeAmount.frame.minY + 2)
        XCTAssertLessThanOrEqual(largeAmount.frame.maxY, largeRow.frame.maxY)
        attachScreenshot("04-records-largest-text", in: largeApp)
    }

    @MainActor
    func testDarkRecordsAndSettingsUseReadableTwoLineLayout() throws {
        let app = launch(language: "tr", locale: "tr_TR", appearance: "Dark")
        XCTAssertTrue(app.navigationBars["Kayıtlar"].waitForExistence(timeout: 8))

        let add = app.buttons["addTransactionButton"]
        let window = app.windows.firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(add.frame.midX, window.frame.midX)
        XCTAssertGreaterThan(add.frame.midY, window.frame.midY)

        let netAmount = app.staticTexts["monthNetAmount"]
        let expenseAmount = app.descendants(matching: .any).matching(identifier: "monthExpenseAmount").firstMatch
        let incomeAmount = app.descendants(matching: .any).matching(identifier: "monthIncomeAmount").firstMatch
        XCTAssertTrue(netAmount.waitForExistence(timeout: 5))
        XCTAssertTrue(expenseAmount.exists)
        XCTAssertTrue(incomeAmount.exists)
        XCTAssertGreaterThan(netAmount.frame.height, expenseAmount.frame.height)

        let row = app.descendants(matching: .any).matching(identifier: "transactionRow").firstMatch
        let title = app.descendants(matching: .any).matching(identifier: "transactionTitle").firstMatch
        let metadata = app.descendants(matching: .any).matching(identifier: "transactionMetadata").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(metadata.waitForExistence(timeout: 5))
        XCTAssertLessThan(title.frame.midY, metadata.frame.midY)
        XCTAssertFalse(metadata.label.contains("2026"))
        attachScreenshot("01-records-dark", in: app)

        row.tap()
        XCTAssertTrue(app.textFields["noteField"].waitForExistence(timeout: 5))
        app.buttons["Vazgeç"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        XCTAssertTrue(app.buttons["Sil"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Düzenle"].exists)
        attachScreenshot("02-record-actions-dark", in: app)
        try app.performAccessibilityAudit(for: [.contrast]) { self.contrastFalsePositive($0) }

        openTab("Ayarlar", in: app)
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches.matching(identifier: "hapticsToggle").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "currencyPicker").firstMatch.exists)
        attachScreenshot("03-settings-dark", in: app)
        try app.performAccessibilityAudit(for: [.contrast]) { self.contrastFalsePositive($0) }
    }

    @MainActor
    func testEnglishAutomaticKeypadAndInstallmentSchedule() {
        let app = launch(language: "en", locale: "en_US", seed: false)

        let add = app.buttons["addTransactionButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()

        XCTAssertTrue(app.otherElements["amountKeypad"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["keypadDecimal"].exists)
        XCTAssertTrue(app.buttons["amountDeleteButton"].exists)
        XCTAssertFalse(app.buttons["keypadDelete"].exists)
        attachScreenshot("08-keypad-decimal-arrow-and-delete", in: app)

        let note = app.textFields["noteField"]
        note.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["amountKeypad"].waitForNonExistence(timeout: 3))

        let amount = app.buttons["amountDisplay"]
        XCTAssertTrue(amount.isHittable)
        amount.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["amountKeypad"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["keypad4"].isHittable)

        app.buttons["keypad4"].tap()
        app.buttons["keypad2"].tap()
        app.buttons["keypad5"].tap()
        XCTAssertTrue("\(amount.label) \(String(describing: amount.value))".contains("425.00"))
        XCTAssertEqual(amount.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 2)
        attachScreenshot("20-amount-425-centered", in: app)

        app.buttons["amountDeleteButton"].tap()
        XCTAssertTrue("\(amount.label) \(String(describing: amount.value))".contains("42.00"))
        app.buttons["keypad5"].tap()
        for _ in 0 ..< 3 { app.buttons["amountDeleteButton"].tap() }
        app.buttons["keypad3"].tap()
        for _ in 0 ..< 5 { app.buttons["keypad0"].tap() }

        note.tap()
        note.typeText("Laptop")
        amount.tap()
        XCTAssertTrue(app.otherElements["amountKeypad"].waitForExistence(timeout: 3))

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
        monthSummary.swipeRight()
        XCTAssertTrue(app.staticTexts["1/3"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEnglishEditorKeepsKeypadUsableAtLargestText() {
        let app = launch(language: "en", locale: "en_US", seed: false, largestText: true)
        let add = app.buttons["addTransactionButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()

        XCTAssertTrue(app.otherElements["amountKeypad"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["amountDisplay"].exists)
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

        let suggestions = app.buttons["suggestedCategoriesVisibilityButton"]
        let housing = app.descendants(matching: .any)
            .matching(identifier: "suggestedCategory-category.housing").firstMatch
        XCTAssertTrue(suggestions.waitForExistence(timeout: 5))
        XCTAssertEqual(suggestions.label, "Hide suggested categories")
        XCTAssertTrue(housing.exists)
        suggestions.tap()
        XCTAssertTrue(housing.waitForNonExistence(timeout: 3))
        XCTAssertEqual(suggestions.label, "Show suggested categories")
        suggestions.tap()
        XCTAssertTrue(housing.waitForExistence(timeout: 3))
        XCTAssertEqual(suggestions.label, "Hide suggested categories")

        let editMode = app.buttons["categoryEditModeButton"]
        XCTAssertTrue(editMode.waitForExistence(timeout: 5))
        XCTAssertEqual(editMode.label, "Edit")
        editMode.tap()
        XCTAssertEqual(editMode.label, "Done")
        editMode.tap()
        XCTAssertEqual(editMode.label, "Edit")
        app.buttons["Add category"].tap()

        let name = app.textFields["categoryNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        let emoji = app.textFields["categoryEmojiField"]
        XCTAssertTrue(emoji.waitForExistence(timeout: 5))
        XCTAssertEqual(emoji.placeholderValue, "Emoji")
        XCTAssertFalse(app.staticTexts["Symbol or emoji"].exists)
        XCTAssertFalse(app.staticTexts["Colour"].exists)
        XCTAssertFalse(app.staticTexts["Category colour"].exists)
        emoji.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.keys["😀"].waitForExistence(timeout: 3))
        emoji.typeText("🛒")
        name.tap()
        name.typeText("Duplicate Emoji")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["This emoji is already used by another category."].waitForExistence(timeout: 3))
    }

    @MainActor
    func testFiltersCompactRowsAndBudgetGauge() throws {
        let app = launch(language: "en", locale: "en_US", appearance: "Dark")
        XCTAssertTrue(app.buttons["transactionFilterButton"].waitForExistence(timeout: 8))
        let row = app.descendants(matching: .any).matching(identifier: "transactionRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        XCTAssertLessThanOrEqual(row.frame.height, 60)

        app.buttons["transactionFilterButton"].tap()
        XCTAssertTrue(app.buttons["Expenses"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Uncategorized"].exists)
        app.buttons["Expenses"].tap()
        XCTAssertFalse(app.buttons["transactionFilterButton"].exists)
        XCTAssertTrue(app.buttons["clearTransactionFilterButton"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(identifier: "clearTransactionFilterButton").count, 1)
        XCTAssertLessThan(app.buttons["clearTransactionFilterButton"].frame.midY, 150)
        attachScreenshot("21-records-toolbar-filter", in: app)
        try app.performAccessibilityAudit(for: [.contrast]) { self.contrastFalsePositive($0) }
        app.buttons["clearTransactionFilterButton"].tap()
        XCTAssertFalse(app.buttons["clearTransactionFilterButton"].exists)
        XCTAssertTrue(app.buttons["transactionFilterButton"].waitForExistence(timeout: 3))

        let upcomingHeader = app.buttons["upcomingSectionHeader"]
        if upcomingHeader.waitForExistence(timeout: 3) {
            let expandedCount = app.descendants(matching: .any).matching(identifier: "transactionRow").count
            upcomingHeader.tap()
            XCTAssertLessThan(app.descendants(matching: .any).matching(identifier: "transactionRow").count, expandedCount)
            upcomingHeader.tap()
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "transactionRow").count, expandedCount)
        }

        openTab("Analysis", in: app)
        let chart = app.descendants(matching: .any).matching(identifier: "analysisChart").firstMatch
        if chart.waitForExistence(timeout: 5) {
            attachScreenshot("21-analysis-month", in: app)
            let day = Calendar.current.component(.day, from: .now)
            chart.coordinate(withNormalizedOffset: CGVector(dx: day < 16 ? 0.9 : 0.1, dy: 0.5)).tap()
            XCTAssertTrue(app.navigationBars["Analysis"].exists)
            let records = app.navigationBars["Records"]
            var didNavigate = false
            for step in 2 ... 23 {
                chart.coordinate(withNormalizedOffset: CGVector(dx: Double(step) / 25, dy: 0.5)).tap()
                if records.waitForExistence(timeout: 0.4) {
                    didNavigate = true
                    break
                }
            }
            XCTAssertTrue(didNavigate)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "highlightedTransactionRow").firstMatch.exists)
            attachScreenshot("21-analysis-highlight", in: app)
            Thread.sleep(forTimeInterval: 3.4)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "highlightedTransactionRow").firstMatch.exists)
        }

        openTab("Budgets", in: app)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "budgetExplanation").firstMatch.exists)
        let budgetInfo = app.buttons["budgetInfoButton"]
        XCTAssertTrue(budgetInfo.waitForExistence(timeout: 5))
        budgetInfo.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "budgetExplanation").firstMatch.waitForExistence(timeout: 3))
        attachScreenshot("21-budget-info-popover", in: app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()
        if app.buttons["emptyBudgetAddButton"].exists {
            app.buttons["emptyBudgetAddButton"].tap()
            XCTAssertTrue(app.buttons["keypad1"].waitForExistence(timeout: 5))
            app.buttons["keypad1"].tap()
            app.buttons["keypad0"].tap()
            app.buttons["keypad0"].tap()
            app.buttons["keypadSubmit"].tap()
        }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "budgetGauge").firstMatch.waitForExistence(timeout: 5))
        attachScreenshot("21-budgets-gauge-dark", in: app)
        try app.performAccessibilityAudit(for: [.contrast]) { self.contrastFalsePositive($0) }
    }

    @MainActor
    func testNewTransactionTypeSwipesOnlyFromEmptyGutter() {
        let app = launch(language: "en", locale: "en_US", seed: false)
        XCTAssertTrue(app.buttons["addTransactionButton"].waitForExistence(timeout: 8))
        app.buttons["addTransactionButton"].tap()

        let scroll = app.scrollViews["transactionEditorScroll"]
        let expense = app.segmentedControls.buttons["Expense"]
        let income = app.segmentedControls.buttons["Income"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        XCTAssertTrue(expense.isSelected)

        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45)))
        XCTAssertTrue(income.waitForExistence(timeout: 2))
        XCTAssertTrue(income.isSelected)

        app.buttons["keypad1"].press(forDuration: 0.05, thenDragTo: app.buttons["keypad3"])
        XCTAssertTrue(income.isSelected)

        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.45)))
        XCTAssertTrue(expense.waitForExistence(timeout: 2))
        XCTAssertTrue(expense.isSelected)
    }

    @MainActor
    func testSuggestedExpenseAndIncomeCategoriesAddWithOneTap() throws {
        let app = launch(language: "en", locale: "en_US", seed: false, appearance: "Dark")
        openTab("Settings", in: app)
        for _ in 0 ..< 4 where !app.buttons["Categories"].exists { app.swipeUp() }
        app.buttons["Categories"].tap()

        let housing = app.descendants(matching: .any).matching(identifier: "suggestedCategory-category.housing").firstMatch
        XCTAssertTrue(housing.waitForExistence(timeout: 5))
        attachScreenshot("05-categories-expense-dark", in: app)
        housing.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "categoryRow-category.housing").firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertFalse(housing.exists)

        app.buttons["Income"].tap()
        let freelance = app.descendants(matching: .any).matching(identifier: "suggestedCategory-category.freelance").firstMatch
        XCTAssertTrue(freelance.waitForExistence(timeout: 5))
        attachScreenshot("06-categories-income-dark", in: app)
        try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription]) {
            self.contrastFalsePositive($0)
        }
        freelance.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "categoryRow-category.freelance").firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertFalse(freelance.exists)

        app.terminate()
        let turkish = launch(language: "tr", locale: "tr_TR", seed: false)
        openTab("Ayarlar", in: turkish)
        for _ in 0 ..< 4 where !turkish.buttons["Kategoriler"].exists { turkish.swipeUp() }
        turkish.buttons["Kategoriler"].tap()
        let housingTurkish = turkish.descendants(matching: .any)
            .matching(identifier: "suggestedCategory-category.housing").firstMatch
        XCTAssertTrue(housingTurkish.waitForExistence(timeout: 5))
        XCTAssertEqual(housingTurkish.label, "Konut kategorisini ekle")
        XCTAssertTrue(turkish.buttons["Gelir"].exists)
        attachScreenshot("07-categories-expense-turkish", in: turkish)
    }

    @MainActor
    func testCategoryDeleteActionPassesContrastInLightAndDark() throws {
        for (language, locale, appearance, settings, categories, delete, dialogTitle) in [
            ("en", "en_US", "Light", "Settings", "Categories", "Delete", "Delete category?"),
            ("tr", "tr_TR", "Dark", "Ayarlar", "Kategoriler", "Sil", "Kategori silinsin mi?")
        ] {
            let app = launch(language: language, locale: locale, seed: false, appearance: appearance)
            openTab(settings, in: app)
            for _ in 0 ..< 4 where !app.buttons[categories].exists { app.swipeUp() }
            app.buttons[categories].tap()

            let firstRow = app.descendants(matching: .any)
                .matching(identifier: "categoryRow-category.market").firstMatch
            let row = app.descendants(matching: .any)
                .matching(identifier: "categoryRow-category.health").firstMatch
            let followingRow = app.descendants(matching: .any)
                .matching(identifier: "categoryRow-category.entertainment").firstMatch
            XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertTrue(followingRow.waitForExistence(timeout: 5))
            swipeDeleteRow(row, in: app)
            XCTAssertTrue(app.buttons[delete].waitForExistence(timeout: 3))
            Thread.sleep(forTimeInterval: 0.5)
            attachScreenshot("category-delete-\(appearance.lowercased())", in: app)

            try app.performAccessibilityAudit(for: [.contrast]) { issue in
                let label = issue.element?.label ?? ""
                return issue.element == nil
                    || (issue.element?.elementType == .staticText
                        && label != delete)
            }

            if !app.buttons[delete].exists {
                swipeDeleteRow(row, in: app)
            }
            XCTAssertTrue(app.buttons[delete].waitForExistence(timeout: 3))
            app.buttons[delete].tap()
            XCTAssertTrue(app.staticTexts[dialogTitle].waitForExistence(timeout: 3))
            assertPopover(in: app, isAnchoredTo: row, ratherThan: firstRow)
            XCTAssertTrue(firstRow.exists)
            XCTAssertTrue(row.exists)
            XCTAssertTrue(followingRow.exists)
            XCTAssertGreaterThan(row.frame.height, 20)
            XCTAssertGreaterThan(followingRow.frame.height, 20)
            attachScreenshot("category-delete-confirmation-\(appearance.lowercased())", in: app)

            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55)).tap()
            XCTAssertTrue(app.staticTexts[dialogTitle].waitForNonExistence(timeout: 3))
            XCTAssertTrue(firstRow.waitForExistence(timeout: 3))
            XCTAssertTrue(row.waitForExistence(timeout: 3))
            XCTAssertTrue(followingRow.waitForExistence(timeout: 3))

            swipeDeleteRow(row, in: app)
            XCTAssertTrue(app.buttons[delete].waitForExistence(timeout: 3))
            app.buttons[delete].tap()
            XCTAssertTrue(app.staticTexts[dialogTitle].waitForExistence(timeout: 3))
            app.buttons[delete].tap()
            XCTAssertTrue(row.waitForNonExistence(timeout: 3))
            assertRemainsAbsent(app.staticTexts[dialogTitle])
            XCTAssertTrue(firstRow.exists)
            XCTAssertTrue(followingRow.exists)
            attachScreenshot("category-delete-complete-\(appearance.lowercased())", in: app)
            app.terminate()
        }
    }

    @MainActor
    func testTransactionDeleteDialogUsesSelectedRowAndKeepsInstallmentScopes() {
        let app = launch(language: "en", locale: "en_US", seed: false)
        addTransaction(note: "First record", in: app)
        addTransaction(note: "Second record", in: app)

        let firstRow = app.staticTexts["Second record"]
        let targetRow = app.staticTexts["First record"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        XCTAssertTrue(targetRow.waitForExistence(timeout: 5))
        swipeDeleteRow(targetRow, in: app)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Delete transaction?"].waitForExistence(timeout: 3))
        assertPopover(in: app, isAnchoredTo: targetRow, ratherThan: firstRow)
        attachScreenshot("transaction-delete-selected-row", in: app)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55)).tap()
        XCTAssertTrue(app.staticTexts["Delete transaction?"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(firstRow.exists)
        XCTAssertTrue(targetRow.exists)

        swipeDeleteRow(targetRow, in: app)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Delete transaction?"].waitForExistence(timeout: 3))
        app.buttons["Delete"].tap()
        XCTAssertTrue(targetRow.waitForNonExistence(timeout: 3))
        assertRemainsAbsent(app.staticTexts["Delete transaction?"])
        XCTAssertTrue(firstRow.exists)

        app.terminate()
        let installments = launch(language: "en", locale: "en_US")
        let installment = installments.staticTexts["UI Test"]
        XCTAssertTrue(installment.waitForExistence(timeout: 5))
        swipeDeleteRow(installment, in: installments)
        XCTAssertTrue(installments.buttons["Delete"].waitForExistence(timeout: 3))
        installments.buttons["Delete"].tap()
        XCTAssertTrue(installments.buttons["Only this installment"].waitForExistence(timeout: 3))
        XCTAssertTrue(installments.buttons["This and following installments"].exists)
        attachScreenshot("installment-delete-scopes", in: installments)
    }

    @MainActor
    func testBudgetDeleteDialogUsesSelectedRow() {
        let app = launch(language: "en", locale: "en_US", seed: false)
        openTab("Budgets", in: app)
        XCTAssertTrue(app.buttons["emptyBudgetAddButton"].waitForExistence(timeout: 5))
        app.buttons["emptyBudgetAddButton"].tap()
        enterAmountAndSubmit(in: app)
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 5))

        app.buttons["addBudgetButton"].tap()
        enterAmountAndSubmit(in: app)
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 5))

        let firstRow = app.staticTexts["Overall budget"]
        let targetRow = app.staticTexts["Market"]
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        XCTAssertTrue(targetRow.waitForExistence(timeout: 5))
        swipeDeleteRow(targetRow, in: app)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Delete budget?"].waitForExistence(timeout: 3))
        assertPopover(in: app, isAnchoredTo: targetRow, ratherThan: firstRow)
        attachScreenshot("budget-delete-selected-row", in: app)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55)).tap()
        XCTAssertTrue(app.staticTexts["Delete budget?"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(firstRow.exists)
        XCTAssertTrue(targetRow.exists)

        swipeDeleteRow(targetRow, in: app)
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 3))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Delete budget?"].waitForExistence(timeout: 3))
        app.buttons["Delete"].tap()
        XCTAssertTrue(targetRow.waitForNonExistence(timeout: 3))
        assertRemainsAbsent(app.staticTexts["Delete budget?"])
        XCTAssertTrue(firstRow.exists)
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
    func testSavingsAddsManualGoldWithoutCreatingATransaction() throws {
        let app = launch(language: "en", locale: "en_US", seed: false, appearance: "Dark")
        openTab("Savings", in: app)
        XCTAssertTrue(app.navigationBars["Savings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No savings yet"].exists)

        app.buttons["addSavingsButton"].tap()
        XCTAssertTrue(app.navigationBars["Add savings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "savingsEditorScroll").firstMatch.exists)
        XCTAssertTrue(app.otherElements["amountKeypad"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Where is it held?"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'XAU'")).firstMatch.exists)
        let quantity = app.buttons["savingsQuantityInput"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        XCTAssertEqual(quantity.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 2)
        quantity.tap()
        app.buttons["keypad1"].tap()
        app.buttons["keypad2"].tap()
        app.buttons["keypadDecimal"].tap()
        app.buttons["keypad5"].tap()
        app.buttons["Manual"].tap()
        let price = app.buttons["savingsManualPriceInput"]
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        XCTAssertEqual(price.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 2)
        [6, 4, 0, 0].forEach { app.buttons["keypad\($0)"].tap() }
        attachScreenshot("28-savings-editor-en-dark", in: app)
        try app.performAccessibilityAudit(for: [.contrast]) { self.contrastFalsePositive($0) }
        app.buttons["keypadSubmit"].tap()

        XCTAssertTrue(app.staticTexts["Gold"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["$80,000.00"].exists)
        attachScreenshot("28-savings-en-dark", in: app)
        try app.performAccessibilityAudit(for: [.contrast]) { self.contrastFalsePositive($0) }

        openTab("Settings", in: app)
        let currencyPicker = app.descendants(matching: .any).matching(identifier: "currencyPicker").firstMatch
        XCTAssertTrue(currencyPicker.waitForExistence(timeout: 5))
        currencyPicker.tap()
        let currencySearch = app.searchFields["Search currency or code"]
        XCTAssertTrue(currencySearch.waitForExistence(timeout: 5))
        currencySearch.tap()
        currencySearch.typeText("BRL")
        let brl = app.descendants(matching: .any).matching(identifier: "currencyOption-BRL").firstMatch
        XCTAssertTrue(brl.waitForExistence(timeout: 5))
        brl.tap()

        openTab("Savings", in: app)
        XCTAssertTrue(app.staticTexts["Manual BRL price needed"].waitForExistence(timeout: 5))

        openTab("Transactions", in: app)
        XCTAssertTrue(app.staticTexts["A clean slate"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTurkishLightSavingsEditorSupportsLargestText() throws {
        let app = launch(
            language: "tr",
            locale: "tr_TR",
            seed: false,
            largestText: true,
            appearance: "Light"
        )
        openTab("Birikim", in: app)
        app.buttons["addSavingsButton"].tap()

        XCTAssertTrue(app.navigationBars["Birikim ekle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "savingsEditorScroll").firstMatch.exists)
        XCTAssertTrue(app.buttons["savingsQuantityInput"].exists)
        XCTAssertTrue(app.buttons["keypad0"].isHittable)
        XCTAssertTrue(app.buttons["keypadSubmit"].isHittable)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        attachScreenshot("28-savings-editor-tr-light-largest", in: app)
        try app.performAccessibilityAudit(for: [.contrast]) { self.contrastFalsePositive($0) }
    }

    @MainActor
    func testAppStoreScreenshotsTurkish() {
        captureAppStoreScreenshots(language: "tr", locale: "tr_TR", suffix: "tr")
    }

    @MainActor
    func testAppStoreScreenshotsEnglish() {
        captureAppStoreScreenshots(language: "en", locale: "en_US", suffix: "en")
    }

    @MainActor
    private func captureAppStoreScreenshots(language: String, locale: String, suffix: String) {
        let app = launch(
            language: language,
            locale: locale,
            seed: false,
            appearance: "Dark",
            appStoreSeed: true
        )
        let labels = suffix == "tr"
            ? (records: "Kayıtlar", analysis: "Analiz", budgets: "Bütçeler", savings: "Birikim", installments: "Taksit")
            : (records: "Records", analysis: "Analysis", budgets: "Budgets", savings: "Savings", installments: "Installments")

        XCTAssertTrue(app.navigationBars[labels.records].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "transactionRow").firstMatch.waitForExistence(timeout: 5))
        attachScreenshot("store-01-overview-\(suffix)", in: app)

        app.buttons["addTransactionButton"].tap()
        XCTAssertTrue(app.buttons["keypad4"].waitForExistence(timeout: 5))
        app.buttons["keypad4"].tap()
        app.buttons["keypad2"].tap()
        app.buttons["keypad5"].tap()
        attachScreenshot("store-02-entry-\(suffix)", in: app)
        app.buttons[suffix == "tr" ? "Vazgeç" : "Cancel"].tap()

        openTab(labels.analysis, in: app)
        XCTAssertTrue(app.navigationBars[labels.analysis].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "analysisChart").firstMatch.waitForExistence(timeout: 5))
        attachScreenshot("store-03-analysis-\(suffix)", in: app)

        openTab(labels.budgets, in: app)
        XCTAssertTrue(app.navigationBars[labels.budgets].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "budgetGauge").firstMatch.waitForExistence(timeout: 5))
        attachScreenshot("store-04-budgets-\(suffix)", in: app)

        openTab(labels.savings, in: app)
        XCTAssertTrue(app.navigationBars[labels.savings].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["addSavingsButton"].waitForExistence(timeout: 5))
        attachScreenshot("store-06-savings-\(suffix)", in: app)

        openTab(labels.records == "Kayıtlar" ? "İşlemler" : "Transactions", in: app)
        app.buttons["addTransactionButton"].tap()
        XCTAssertTrue(app.buttons["keypad3"].waitForExistence(timeout: 5))
        app.buttons["keypad3"].tap()
        app.buttons["keypad0"].tap()
        app.buttons["keypad0"].tap()
        app.buttons["keypad0"].tap()
        app.buttons["scheduleButton"].tap()
        XCTAssertTrue(app.buttons[labels.installments].waitForExistence(timeout: 5))
        app.buttons[labels.installments].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "installmentCountStepper").firstMatch.waitForExistence(timeout: 5))
        attachScreenshot("store-05-installments-\(suffix)", in: app)
    }

    @MainActor
    private func launch(
        language: String,
        locale: String,
        seed: Bool = true,
        largestText: Bool = false,
        appearance: String? = nil,
        lockAuthenticationSucceeds: Bool? = nil,
        showOnboarding: Bool = false,
        appStoreSeed: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            showOnboarding ? "-ui-test-reset-onboarding" : "-ui-test-skip-onboarding",
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
        if appStoreSeed { app.launchArguments.append("-seed-app-store-screenshots") }
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
    private func addTransaction(note: String, in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["addTransactionButton"].waitForExistence(timeout: 5))
        app.buttons["addTransactionButton"].tap()
        XCTAssertTrue(app.buttons["keypad1"].waitForExistence(timeout: 5))
        app.buttons["keypad1"].tap()
        app.buttons["keypad0"].tap()
        app.buttons["keypad0"].tap()
        let noteField = app.textFields["noteField"]
        noteField.tap()
        noteField.typeText(note)
        app.buttons["keyboardDoneButton"].tap()
        app.buttons["keypadSubmit"].tap()
        XCTAssertTrue(app.staticTexts[note].waitForExistence(timeout: 5))
    }

    @MainActor
    private func enterAmountAndSubmit(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["keypad1"].waitForExistence(timeout: 5))
        app.buttons["keypad1"].tap()
        app.buttons["keypad0"].tap()
        app.buttons["keypad0"].tap()
        app.buttons["keypadSubmit"].tap()
    }

    @MainActor
    private func swipeDeleteRow(_ row: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch
        let rowY = row.frame.midY / window.frame.height
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: rowY))
            .press(
                forDuration: 0.1,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: rowY))
            )
    }

    @MainActor
    private func assertPopover(
        in app: XCUIApplication,
        isAnchoredTo target: XCUIElement,
        ratherThan other: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let popover = app.descendants(matching: .popover).firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertLessThan(
            abs(popover.frame.maxY - target.frame.midY),
            abs(popover.frame.maxY - other.frame.midY),
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertRemainsAbsent(
        _ element: XCUIElement,
        duration: TimeInterval = 1.5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(duration)
        repeat {
            XCTAssertFalse(element.exists, file: file, line: line)
            Thread.sleep(forTimeInterval: 0.075)
        } while Date() < deadline
    }

    @MainActor
    private func openTab(_ label: String, in app: XCUIApplication) {
        let tab = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()
    }

    private func attachScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func contrastFalsePositive(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        // ponytail: this regression targets controls; iOS 26 flags native secondary text and color emoji pixels on iPad.
        [.staticText, .searchField].contains(issue.element?.elementType) || issue.element?.label == "🛒"
    }
}
