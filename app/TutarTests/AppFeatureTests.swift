// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import CoreData
import XCTest
@testable import Tutar

final class MoneyEntryTests: XCTestCase {
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

    func testResultWhileInactiveIsAppliedOnceWhenActive() async {
        let probe = AuthenticationProbe()
        let controller = makeController(probe)
        controller.start(enabled: true, reason: "Test", scenePhase: .active)
        await waitUntil { probe.callCount == 1 }

        controller.scenePhaseChanged(to: .inactive, lockEnabled: true, reason: "Test")
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
        controller.start(enabled: true, reason: "Test", scenePhase: .active)
        await waitUntil { probe.callCount == 1 }

        probe.complete(false)
        await waitUntil { controller.state == .locked }
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

    func testCompleteBackupRestoresInstallmentsAndBudget() async throws {
        let source = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(source)
        let category = try XCTUnwrap(try source.context.fetch(Category.fetchRequest()).first { !$0.income })
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

    func testDeletingCategoryKeepsTransactions() async throws {
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

        try controller.deleteCategory(category)
        XCTAssertFalse(transaction.isDeleted)
        XCTAssertNil(transaction.category)
        XCTAssertEqual(try controller.context.count(for: Transaction.fetchRequest()), 1)
    }

    private func waitUntilLoaded(_ controller: DataController) async throws {
        for _ in 0 ..< 100 where !controller.isStoreLoaded && controller.loadError == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        if let error = controller.loadError { throw error }
        XCTAssertTrue(controller.isStoreLoaded)
    }
}
