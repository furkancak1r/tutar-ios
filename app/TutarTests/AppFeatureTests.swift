// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import CoreData
import XCTest
@testable import Tutar

final class MoneyEntryTests: XCTestCase {
    func testDefaultEntryStartsWithWholeCurrencyUnits() {
        var entry = MoneyEntry()
        [4, 2, 5].forEach { entry.append($0) }
        XCTAssertEqual(entry.minorUnits, 42_500)
    }

    func testAutomaticCentsEntryAndDeletion() {
        var entry = MoneyEntry(mode: .automaticCents)
        [3, 0, 0, 0, 0, 0].forEach { entry.append($0) }
        XCTAssertEqual(entry.minorUnits, 300_000)
        entry.deleteLast()
        XCTAssertEqual(entry.minorUnits, 30_000)
    }

    func testDecimalEntryStopsAfterTwoFractionDigits() {
        var entry = MoneyEntry(mode: .decimal)
        [3, 0, 0, 0].forEach { entry.append($0) }
        entry.insertDecimalSeparator()
        [2, 5, 9].forEach { entry.append($0) }
        XCTAssertEqual(entry.minorUnits, 300_025)
        entry.deleteLast()
        XCTAssertEqual(entry.minorUnits, 300_020)
    }

    func testAutomaticEntryCanSwitchToLocalizedDecimalInput() {
        var entry = MoneyEntry(mode: .automaticCents)
        [3, 0, 0].forEach { entry.append($0) }
        entry.insertDecimalSeparator()
        [2, 5].forEach { entry.append($0) }
        XCTAssertEqual(entry.minorUnits, 30_025)
    }
}

final class AppFormatTests: XCTestCase {
    func testCurrencySelectionOverridesLanguageDefault() {
        XCTAssertEqual(AppFormat.currencyCode(language: .turkish, preferred: "USD"), "USD")
        XCTAssertEqual(AppFormat.currencyCode(language: .turkish, preferred: ""), "TRY")
    }

    func testAllISOCurrenciesAreAvailable() {
        XCTAssertGreaterThan(AppFormat.currencyCodes.count, 100)
        XCTAssertTrue(["TRY", "USD", "EUR", "JPY"].allSatisfy(AppFormat.currencyCodes.contains))
    }

    func testNetTotalLabelIsLocalized() {
        XCTAssertEqual(AppFormat.localized("summary.netTotal", language: .turkish), "Net toplam")
        XCTAssertEqual(AppFormat.localized("summary.netTotal", language: .english), "Net total")
    }

    func testTransactionDateUsesDayAndAbbreviatedMonthWithoutYear() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 8
        components.day = 6
        let date = try XCTUnwrap(components.date)

        let turkish = AppFormat.date(date, language: .turkish)
        let english = AppFormat.date(date, language: .english)
        XCTAssertTrue(turkish.contains("6"))
        XCTAssertTrue(turkish.localizedCaseInsensitiveContains("Ağu"))
        XCTAssertFalse(turkish.contains("2026"))
        XCTAssertTrue(english.contains("6"))
        XCTAssertFalse(english.contains("2026"))
    }
}

final class SavingsQuoteTests: XCTestCase {
    func testGoldOunceConvertsToPureAnd995GramTRY() {
        let pure = SavingsQuoteMath.metalPriceTRY(
            ounceUSD: Decimal(string: "4000")!,
            usdTRY: Decimal(string: "48")!
        )
        let gold995 = SavingsQuoteMath.metalPriceTRY(
            ounceUSD: Decimal(string: "4000")!,
            usdTRY: Decimal(string: "48")!,
            purity: Decimal(string: "0.995")!
        )
        XCTAssertEqual(NSDecimalNumber(decimal: pure).doubleValue, 6_172.94334, accuracy: 0.00001)
        XCTAssertEqual(NSDecimalNumber(decimal: gold995).doubleValue, NSDecimalNumber(decimal: pure * Decimal(string: "0.995")!).doubleValue, accuracy: 0.0001)
    }

    func testTCMBParserRespectsCurrencyUnitAndHourlyGoldCodes() throws {
        let xml = """
        <Tarih_Date Tarih="05.08.2026">
          <Currency CurrencyCode="JPY"><Unit>100</Unit><ForexBuying>32.5000</ForexBuying></Currency>
          <doviz_kur_liste gecerlilik_tarihi="2026-8-5">
            <kur><doviz_cinsi>XAU</doviz_cinsi><birim>1</birim><alis>6367,96</alis></kur>
            <kur><doviz_cinsi>XAS</doviz_cinsi><birim>1</birim><alis>6399,96</alis></kur>
          </doviz_kur_liste>
        </Tarih_Date>
        """
        let quotes = try TCMBQuoteParser.parse(Data(xml.utf8))
        XCTAssertEqual(quotes["JPY"]?.priceTRY, Decimal(string: "0.325"))
        XCTAssertEqual(quotes["XAU995"]?.priceTRY, Decimal(string: "6367.96"))
        XCTAssertEqual(quotes["XAU1000"]?.priceTRY, Decimal(string: "6399.96"))
    }
}

@MainActor
final class SavingsDataTests: XCTestCase {
    func testHoldingRoundTripsThroughVersionTwoBackup() throws {
        let source = DataController(inMemory: true, cloudEnabled: false)
        let holding = try source.saveHolding(
            institution: "Enpara",
            asset: .XAU995,
            quantity: Decimal(string: "12.5")!,
            quoteMode: 1,
            manualPrice: Decimal(string: "6400")!
        )
        XCTAssertEqual(holding.wrappedQuantity, Decimal(string: "12.5"))

        let destination = DataController(inMemory: true, cloudEnabled: false)
        let result = try destination.importData(source.exportBackup(), fileExtension: "json", language: .turkish)
        let restored = try XCTUnwrap(destination.context.fetch(SavingsHolding.fetchRequest()).first)
        XCTAssertGreaterThan(result.imported, 0)
        XCTAssertEqual(restored.wrappedInstitution, "Enpara")
        XCTAssertEqual(restored.wrappedAsset, .XAU995)
        XCTAssertEqual(restored.wrappedQuantity, Decimal(string: "12.5"))
        XCTAssertEqual(restored.wrappedManualPrice, Decimal(string: "6400"))
    }

    func testHoldingDoesNotCreateTransactionsOrBudgets() throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try controller.saveHolding(
            institution: "Cash",
            asset: .USD,
            quantity: 100,
            quoteMode: 0,
            manualPrice: 0
        )
        XCTAssertEqual(try controller.context.count(for: Transaction.fetchRequest()), 0)
        XCTAssertEqual(try controller.context.count(for: Budget.fetchRequest()), 0)
        XCTAssertEqual(try controller.context.count(for: MainBudget.fetchRequest()), 0)
    }

    func testHoldingRoundTripsThroughCSVWithoutBecomingATransaction() throws {
        let source = DataController(inMemory: true, cloudEnabled: false)
        try source.saveHolding(
            institution: "Physical",
            asset: .XAG,
            quantity: Decimal(string: "125.75")!,
            quoteMode: 0,
            manualPrice: 0
        )
        let destination = DataController(inMemory: true, cloudEnabled: false)
        _ = try destination.importData(source.exportCSV(language: .english), fileExtension: "csv", language: .english)
        let restored = try XCTUnwrap(destination.context.fetch(SavingsHolding.fetchRequest()).first)
        XCTAssertEqual(restored.wrappedAsset, .XAG)
        XCTAssertEqual(restored.wrappedQuantity, Decimal(string: "125.75"))
        XCTAssertEqual(try destination.context.count(for: Transaction.fetchRequest()), 0)
    }
}

@MainActor
private final class AuthenticationProbe {
    private(set) var callCount = 0
    private var continuations: [CheckedContinuation<Bool, Never>] = []

    func authenticate(_: String) async -> Bool {
        callCount += 1
        return await withCheckedContinuation { continuations.append($0) }
    }

    func complete(_ result: Bool, at index: Int = 0) {
        continuations.remove(at: index).resume(returning: result)
    }
}

@MainActor
final class AppLockControllerTests: XCTestCase {
    func testStartupAndButtonRequestsUseOneAuthentication() async {
        let probe = AuthenticationProbe()
        let controller = makeController(probe)

        controller.requestAuthentication(reason: "Test")
        controller.start(enabled: true, reason: "Test", scenePhase: .active)

        await waitUntil { probe.callCount == 1 }
        probe.complete(true)
        await waitUntil { controller.state == .unlocked }
    }

    func testSuccessWhileInactiveUnlocksBeforeActive() async {
        let probe = AuthenticationProbe()
        let controller = makeController(probe)
        controller.start(enabled: true, reason: "Test", scenePhase: .active)
        await waitUntil { probe.callCount == 1 }

        controller.scenePhaseChanged(to: .inactive, lockEnabled: true, reason: "Test")
        probe.complete(true)
        await waitUntil { controller.state == .unlocked }

        controller.scenePhaseChanged(to: .active, lockEnabled: true, reason: "Test")
        XCTAssertEqual(controller.state, .unlocked)
        XCTAssertEqual(probe.callCount, 1)
    }

    func testSuccessWhileBackgroundWaitsUntilActive() async {
        let probe = AuthenticationProbe()
        let controller = makeController(probe)
        controller.start(enabled: true, reason: "Test", scenePhase: .active)
        await waitUntil { probe.callCount == 1 }

        controller.scenePhaseChanged(to: .background, lockEnabled: true, reason: "Test")
        probe.complete(true)
        await Task.yield()
        XCTAssertEqual(controller.state, .authenticating)

        controller.scenePhaseChanged(to: .active, lockEnabled: true, reason: "Test")
        XCTAssertEqual(controller.state, .unlocked)
        XCTAssertEqual(probe.callCount, 1)
    }

    func testActiveBeforeResultAlsoUnlocks() async {
        let probe = AuthenticationProbe()
        let controller = makeController(probe)
        controller.start(enabled: true, reason: "Test", scenePhase: .active)
        await waitUntil { probe.callCount == 1 }

        controller.scenePhaseChanged(to: .inactive, lockEnabled: true, reason: "Test")
        controller.scenePhaseChanged(to: .active, lockEnabled: true, reason: "Test")
        probe.complete(true)

        await waitUntil { controller.state == .unlocked }
        XCTAssertEqual(probe.callCount, 1)
    }

    func testFailureStaysLockedWithoutAutomaticRetry() async {
        let probe = AuthenticationProbe()
        let controller = makeController(probe)
        XCTAssertFalse(controller.canRetryAuthentication)
        controller.start(enabled: true, reason: "Test", scenePhase: .active)
        await waitUntil { probe.callCount == 1 }
        XCTAssertFalse(controller.canRetryAuthentication)

        probe.complete(false)
        await waitUntil { controller.state == .locked }
        XCTAssertTrue(controller.canRetryAuthentication)
        controller.scenePhaseChanged(to: .active, lockEnabled: true, reason: "Test")
        controller.scenePhaseChanged(to: .active, lockEnabled: true, reason: "Test")
        await Task.yield()

        XCTAssertEqual(probe.callCount, 1)
    }

    func testRealBackgroundStartsOneNewAuthentication() async {
        let probe = AuthenticationProbe()
        let controller = makeController(probe)
        controller.start(enabled: true, reason: "Test", scenePhase: .active)
        await waitUntil { probe.callCount == 1 }
        probe.complete(true)
        await waitUntil { controller.state == .unlocked }

        controller.scenePhaseChanged(to: .background, lockEnabled: true, reason: "Test")
        XCTAssertEqual(controller.state, .locked)
        XCTAssertFalse(controller.canRetryAuthentication)
        controller.scenePhaseChanged(to: .active, lockEnabled: true, reason: "Test")
        controller.scenePhaseChanged(to: .active, lockEnabled: true, reason: "Test")

        await waitUntil { probe.callCount == 2 }
        XCTAssertEqual(controller.state, .authenticating)
    }

    func testStaleResultCannotChangeReenabledLock() async {
        let probe = AuthenticationProbe()
        let controller = makeController(probe)
        controller.start(enabled: true, reason: "Test", scenePhase: .active)
        await waitUntil { probe.callCount == 1 }

        controller.setEnabled(false, reason: "Test", scenePhase: .active)
        controller.setEnabled(true, reason: "Test", scenePhase: .active)
        await waitUntil { probe.callCount == 2 }

        probe.complete(true)
        await Task.yield()
        XCTAssertEqual(controller.state, .authenticating)
        probe.complete(false)
        await waitUntil { controller.state == .locked }
    }

    private func makeController(_ probe: AuthenticationProbe) -> AppLockController {
        AppLockController(authenticate: probe.authenticate)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0 ..< 100 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not met", file: file, line: line)
    }
}

final class CSVCodecTests: XCTestCase {
    func testQuotedCSVValuesRoundTrip() throws {
        let rows = [
            ["Date", "Note", "Amount"],
            ["2026-08-04", "Coffee, beans\nand milk", "42.50"],
            ["2026-08-05", "He said \"hello\"", "10.00"]
        ]
        XCTAssertEqual(try CSVCodec.decode(CSVCodec.encode(rows)), rows)
    }

    func testUnclosedQuoteIsRejected() {
        XCTAssertThrowsError(try CSVCodec.decode("Date,Note\n2026-08-04,\"broken"))
    }
}

@MainActor
final class DataFeatureTests: XCTestCase {
    func testDimeCSVImportsAndDuplicateImportIsSkipped() async throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(controller)
        let csv = """
        Date,Note,Amount,Category,Type
        2026-08-18,"Laptop, work",3000.00,Shopping,Expense
        """
        let data = try XCTUnwrap(csv.data(using: .utf8))

        let first = try controller.importData(data, fileExtension: "csv", language: .english)
        let second = try controller.importData(data, fileExtension: "csv", language: .english)
        XCTAssertEqual(first, DataTransferResult(imported: 1, skipped: 0))
        XCTAssertEqual(second, DataTransferResult(imported: 0, skipped: 1))

        let item = try XCTUnwrap(try controller.context.fetch(Transaction.fetchRequest()).first)
        XCTAssertEqual(item.note, "Laptop, work")
        XCTAssertEqual(item.amountMinorUnits, 300_000)
        XCTAssertEqual(item.category?.systemKey, "category.shopping")
    }

    func testCSVRejectsAmountOutsideSupportedRange() async throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(controller)
        let csv = "Date,Note,Amount,Category,Type\n2026-08-18,Invalid,999999999999999999999,Shopping,Expense\n"
        let data = try XCTUnwrap(csv.data(using: .utf8))

        XCTAssertThrowsError(try controller.importData(data, fileExtension: "csv", language: .english))
        XCTAssertEqual(try controller.context.count(for: Transaction.fetchRequest()), 0)
    }

    func testCSVRestoresCategoryEmoji() async throws {
        let source = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(source)
        let category = try source.saveCategory(
            name: "Bookshelf",
            emoji: "📚",
            colour: "#232326",
            income: false
        )
        _ = try source.createTransaction(
            note: "Novel",
            category: category,
            income: false,
            amountMinorUnits: 2_500,
            date: .now
        )

        let destination = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(destination)
        _ = try destination.importData(
            source.exportCSV(language: .english),
            fileExtension: "csv",
            language: .english
        )

        let transaction = try XCTUnwrap(
            try destination.context.fetch(Transaction.fetchRequest()).first { $0.note == "Novel" }
        )
        XCTAssertEqual(transaction.category?.emoji, "📚")
    }

    func testCompleteBackupRestoresInstallmentsAndBudget() async throws {
        let source = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(source)
        let category = try XCTUnwrap(
            try source.context.fetch(Category.fetchRequest()).first { $0.systemKey == "category.market" }
        )
        _ = try source.saveCategory(
            category,
            name: category.displayName(language: .english),
            emoji: "🧺",
            colour: category.colour ?? "#232326",
            income: false
        )
        try source.createInstallments(
            note: "Computer",
            category: category,
            income: false,
            totalMinorUnits: 300_001,
            count: 3,
            firstDate: .now,
            intervalMonths: 1
        )
        try source.saveCategoryBudget(
            category: category,
            amountMinorUnits: 500_000,
            type: 3,
            startDate: .now
        )
        let backup = try source.exportBackup()

        let destination = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(destination)
        _ = try destination.importData(backup, fileExtension: "json", language: .english)
        _ = try destination.importData(backup, fileExtension: "json", language: .english)

        let transactions = try destination.context.fetch(Transaction.fetchRequest())
            .filter { $0.note == "Computer" }
            .sorted { $0.installmentIndex < $1.installmentIndex }
        XCTAssertEqual(transactions.map(\.amountMinorUnits), [100_000, 100_000, 100_001])
        XCTAssertEqual(transactions.map(\.installmentIndex), [1, 2, 3])
        XCTAssertEqual(try destination.context.count(for: Budget.fetchRequest()), 1)
        XCTAssertEqual(
            try destination.context.fetch(Category.fetchRequest()).filter { $0.systemKey == "category.market" }.count,
            1
        )
        XCTAssertEqual(
            try destination.context.fetch(Category.fetchRequest()).first { $0.systemKey == "category.market" }?.emoji,
            "🧺"
        )
    }

    func testRecurringEntryMaterializesOncePerDueDate() async throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(controller)
        let category = try XCTUnwrap(try controller.context.fetch(Category.fetchRequest()).first { !$0.income })
        let start = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -2, to: Calendar.current.startOfDay(for: .now)))

        try controller.createTransaction(
            note: "Coffee",
            category: category,
            income: false,
            amountMinorUnits: 1_000,
            date: start,
            recurringType: 1,
            recurringCoefficient: 1
        )
        try controller.materializeRecurringTransactions()

        let items = try controller.context.fetch(Transaction.fetchRequest()).filter { $0.note == "Coffee" }
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.filter { $0.recurringType > 0 }.count, 1)
    }

    func testDeletingUsedCategoryIsRejectedWithoutChangingTransactions() async throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(controller)
        let category = try controller.saveCategory(
            name: "Books",
            emoji: "📚",
            colour: "#007AFF",
            income: false
        )
        let transaction = try controller.createTransaction(
            note: "Novel",
            category: category,
            income: false,
            amountMinorUnits: 2_500,
            date: .now
        )

        XCTAssertThrowsError(try controller.deleteCategory(category)) { error in
            XCTAssertEqual(error as? CategoryError, .inUse)
        }
        XCTAssertFalse(transaction.isDeleted)
        XCTAssertEqual(transaction.category, category)
        XCTAssertEqual(try controller.context.count(for: Transaction.fetchRequest()), 1)
    }

    func testCategoryRequiresOneRealEmoji() async throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(controller)

        for valid in ["🛒", "👨‍👩‍👧‍👦", "👩🏽‍💻", "🇹🇷", "1️⃣"] {
            XCTAssertTrue(CategoryEmoji.isValid(valid), valid)
        }
        for invalid in ["", "A", "1", "TL", "+", "circle.fill", "🛒📚"] {
            XCTAssertFalse(CategoryEmoji.isValid(invalid), invalid)
        }
        XCTAssertThrowsError(try controller.saveCategory(
            name: "Text symbol",
            emoji: "+",
            colour: "#232326",
            income: false
        )) { error in
            XCTAssertEqual(error as? CategoryError, .invalidEmoji)
        }
    }

    func testCSVWithoutCategoriesUsesTypeSpecificOtherCategories() async throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(controller)
        let csv = "Date,Note,Amount,Category,Type\n2026-08-18,Coffee,10.00,,Expense\n2026-08-18,Gift,20.00,,Income\n"
        let data = try XCTUnwrap(csv.data(using: .utf8))

        XCTAssertEqual(
            try controller.importData(data, fileExtension: "csv", language: .english),
            DataTransferResult(imported: 2, skipped: 0)
        )
        let imported = try controller.context.fetch(Transaction.fetchRequest())
            .filter { ["Coffee", "Gift"].contains($0.note ?? "") }
        XCTAssertEqual(imported.first { !$0.income }?.category?.systemKey, "category.other")
        XCTAssertEqual(imported.first { $0.income }?.category?.systemKey, "category.otherIncome")
    }

    func testSuggestedCategoryKeepsLocalizationAndCannotBeAddedTwice() async throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(controller)

        let category = try controller.saveCategory(
            name: "category.housing",
            emoji: "🏠",
            colour: "#6B6258",
            income: false,
            systemKey: "category.housing"
        )

        XCTAssertEqual(category.displayName(language: .turkish), "Konut")
        XCTAssertEqual(category.displayName(language: .english), "Housing")
        XCTAssertThrowsError(try controller.saveCategory(
            name: "category.housing",
            emoji: "🏠",
            colour: "#6B6258",
            income: false,
            systemKey: "category.housing"
        )) { error in
            XCTAssertEqual(error as? CategoryError, .duplicate)
        }
    }

    func testCategoryEmojiMustBeUnique() async throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(controller)
        let category = try controller.saveCategory(
            name: "Books",
            emoji: "📚",
            colour: "#232326",
            income: false
        )

        _ = try controller.saveCategory(
            category,
            name: "Reading",
            emoji: "📚",
            colour: "#232326",
            income: false
        )
        XCTAssertThrowsError(try controller.saveCategory(
            name: "Library",
            emoji: "📚",
            colour: "#232326",
            income: true
        )) { error in
            XCTAssertEqual(error as? CategoryError, .duplicateEmoji)
        }
    }

    private func waitUntilLoaded(_ controller: DataController) async throws {
        for _ in 0 ..< 100 where !controller.isStoreLoaded && controller.loadError == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        if let error = controller.loadError { throw error }
        XCTAssertTrue(controller.isStoreLoaded)
    }
}
