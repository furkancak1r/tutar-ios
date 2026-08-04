// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import CoreData
import XCTest
@testable import Tutar

final class InstallmentPlannerTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testThreeThousandCreatesExactlyThreeMonthlyInstallments() throws {
        let first = utcCalendar.date(from: DateComponents(year: 2026, month: 8, day: 18))!
        let plan = try InstallmentPlanner.plan(
            totalMinorUnits: 300_000,
            count: 3,
            firstDate: first,
            intervalMonths: 1,
            calendar: utcCalendar
        )

        XCTAssertEqual(plan.count, 3)
        XCTAssertEqual(plan.map(\.amountMinorUnits), [100_000, 100_000, 100_000])
        XCTAssertEqual(plan.reduce(0) { $0 + $1.amountMinorUnits }, 300_000)
        XCTAssertEqual(plan.map { utcCalendar.component(.month, from: $0.date) }, [8, 9, 10])
        XCTAssertEqual(plan.map { utcCalendar.component(.day, from: $0.date) }, [18, 18, 18])
        XCTAssertEqual(plan.map(\.index), [1, 2, 3])
    }

    func testRemainderAlwaysGoesToLastInstallment() throws {
        let plan = try InstallmentPlanner.plan(
            totalMinorUnits: 10_000,
            count: 3,
            firstDate: .now,
            intervalMonths: 1
        )
        XCTAssertEqual(plan.map(\.amountMinorUnits), [3_333, 3_333, 3_334])
        XCTAssertEqual(plan.reduce(0) { $0 + $1.amountMinorUnits }, 10_000)
    }

    func testMonthEndClampsWithoutDriftingFollowingMonths() throws {
        let first = utcCalendar.date(from: DateComponents(year: 2025, month: 1, day: 31))!
        let plan = try InstallmentPlanner.plan(
            totalMinorUnits: 30_000,
            count: 3,
            firstDate: first,
            intervalMonths: 1,
            calendar: utcCalendar
        )
        XCTAssertEqual(plan.map { utcCalendar.component(.day, from: $0.date) }, [31, 28, 31])
    }

    func testLocalizedMoneyInputRejectsFractionsSmallerThanMinorUnit() {
        XCTAssertEqual(MoneyInput.minorUnits(from: "3.000,25", locale: Locale(identifier: "tr_TR")), 300_025)
        XCTAssertEqual(MoneyInput.minorUnits(from: "3,000.25", locale: Locale(identifier: "en_US")), 300_025)
        XCTAssertNil(MoneyInput.minorUnits(from: "10.001", locale: Locale(identifier: "en_US")))
        XCTAssertNil(MoneyInput.minorUnits(from: "0", locale: Locale(identifier: "tr_TR")))
    }
}

@MainActor
final class InstallmentPersistenceTests: XCTestCase {
    func testDuplicateGroupIsRejectedAndFollowingDeleteStopsAtSelection() async throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(controller)
        let category = try XCTUnwrap(try controller.context.fetch(Category.fetchRequest()).first)
        let groupID = UUID()

        let created = try controller.createInstallments(
            note: "Laptop",
            category: category,
            income: false,
            totalMinorUnits: 300_000,
            count: 3,
            firstDate: .now,
            intervalMonths: 1,
            groupID: groupID
        )
        XCTAssertEqual(created.count, 3)

        XCTAssertThrowsError(try controller.createInstallments(
            note: "Duplicate",
            category: category,
            income: false,
            totalMinorUnits: 300_000,
            count: 3,
            firstDate: .now,
            intervalMonths: 1,
            groupID: groupID
        )) { error in
            XCTAssertEqual(error as? InstallmentError, .duplicate)
        }

        try controller.delete(created[1], scope: .thisAndFollowing)
        let survivors = try controller.installments(groupID: groupID)
        XCTAssertEqual(survivors.map(\.installmentIndex), [1])
    }

    func testFollowingEditRedistributesNewRemainingTotal() async throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(controller)
        let category = try XCTUnwrap(try controller.context.fetch(Category.fetchRequest()).first)
        let groupID = UUID()
        let created = try controller.createInstallments(
            note: "Phone",
            category: category,
            income: false,
            totalMinorUnits: 300_000,
            count: 3,
            firstDate: .now,
            intervalMonths: 1,
            groupID: groupID
        )

        try controller.update(
            created[1],
            note: "Phone updated",
            category: category,
            income: false,
            amountMinorUnits: 210_001,
            date: created[1].wrappedDate,
            intervalMonths: 1,
            scope: .thisAndFollowing
        )

        let group = try controller.installments(groupID: groupID)
        XCTAssertEqual(group.map(\.amountMinorUnits), [100_000, 105_000, 105_001])
        XCTAssertEqual(group.reduce(0) { $0 + $1.amountMinorUnits }, 310_001)
        XCTAssertEqual(Set(group.map(\.installmentOriginalTotalMinorUnits)), [310_001])
    }

    func testFollowingEditOnFinalInstallmentUpdatesThatInstallment() async throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(controller)
        let category = try XCTUnwrap(try controller.context.fetch(Category.fetchRequest()).first)
        let groupID = UUID()
        let created = try controller.createInstallments(
            note: "Tablet",
            category: category,
            income: false,
            totalMinorUnits: 300_000,
            count: 3,
            firstDate: .now,
            intervalMonths: 1,
            groupID: groupID
        )

        try controller.update(
            created[2],
            note: "Tablet updated",
            category: category,
            income: false,
            amountMinorUnits: 120_001,
            date: created[2].wrappedDate,
            intervalMonths: 2,
            scope: .thisAndFollowing
        )

        let group = try controller.installments(groupID: groupID)
        XCTAssertEqual(group.map(\.amountMinorUnits), [100_000, 100_000, 120_001])
        XCTAssertEqual(group.last?.note, "Tablet updated")
        XCTAssertEqual(group.last?.installmentIntervalMonths, 2)
        XCTAssertEqual(Set(group.map(\.installmentOriginalTotalMinorUnits)), [320_001])
    }

    func testVersionTwoStoreMigratesWithoutChangingExistingTransaction() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TutarMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Main.sqlite")

        let modelDirectory = try XCTUnwrap(Bundle.main.url(forResource: "MainModel", withExtension: "momd"))
        let oldModelURL = modelDirectory.appendingPathComponent("MainModel 2.mom")
        let oldModel = try XCTUnwrap(NSManagedObjectModel(contentsOf: oldModelURL))
        let oldContainer = NSPersistentContainer(name: "MainModel", managedObjectModel: oldModel)
        let oldDescription = NSPersistentStoreDescription(url: storeURL)
        oldContainer.persistentStoreDescriptions = [oldDescription]

        let loaded = expectation(description: "v2 store loaded")
        var oldLoadError: Error?
        oldContainer.loadPersistentStores { _, error in
            oldLoadError = error
            loaded.fulfill()
        }
        await fulfillment(of: [loaded], timeout: 5)
        XCTAssertNil(oldLoadError)

        let oldTransaction = NSEntityDescription.insertNewObject(forEntityName: "Transaction", into: oldContainer.viewContext)
        oldTransaction.setValue(UUID(), forKey: "id")
        oldTransaction.setValue("Legacy transaction", forKey: "note")
        oldTransaction.setValue(42.75, forKey: "amount")
        oldTransaction.setValue(Date(timeIntervalSince1970: 1_700_000_000), forKey: "date")
        try oldContainer.viewContext.save()
        oldContainer.persistentStoreCoordinator.persistentStores.forEach {
            try? oldContainer.persistentStoreCoordinator.remove($0)
        }

        let migrated = DataController(storeURL: storeURL, cloudEnabled: false)
        try await waitUntilLoaded(migrated)
        let transactions = try migrated.context.fetch(Transaction.fetchRequest())
        let preserved = try XCTUnwrap(transactions.first { $0.note == "Legacy transaction" })
        XCTAssertEqual(preserved.amount, 42.75, accuracy: 0.001)
        XCTAssertNil(preserved.installmentGroupID)
        XCTAssertEqual(preserved.installmentIndex, 0)
    }

    private func waitUntilLoaded(_ controller: DataController) async throws {
        for _ in 0 ..< 100 where !controller.isStoreLoaded && controller.loadError == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        if let error = controller.loadError { throw error }
        XCTAssertTrue(controller.isStoreLoaded)
    }
}

final class LocalizationTests: XCTestCase {
    func testEnglishAndTurkishPluralRules() {
        XCTAssertEqual(AppFormat.plural("installments.remaining", count: 1, language: .english), "1 installment remaining")
        XCTAssertEqual(AppFormat.plural("installments.remaining", count: 2, language: .english), "2 installments remaining")
        XCTAssertEqual(AppFormat.plural("installments.remaining", count: 2, language: .turkish), "2 taksit kaldı")
    }
}
