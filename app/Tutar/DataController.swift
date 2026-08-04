// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import CoreData
import Foundation
import WidgetKit

enum EditScope: Equatable {
    case one
    case thisAndFollowing
}

@MainActor
final class DataController: ObservableObject {
    private static let isTesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil

    static let shared = DataController(
        inMemory: isTesting,
        cloudEnabled: !isTesting
    )

    let container: NSPersistentCloudKitContainer
    @Published private(set) var loadError: Error?
    @Published private(set) var isStoreLoaded = false

    var context: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false, storeURL: URL? = nil, cloudEnabled: Bool? = nil) {
        container = NSPersistentCloudKitContainer(name: "MainModel")

        let description = NSPersistentStoreDescription()
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            description.url = storeURL ?? Self.defaultStoreURL
            let enabled = cloudEnabled ?? UserDefaults.tutar.object(forKey: "icloudSync") as? Bool ?? true
            if enabled {
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: AppConstants.cloudContainer
                )
            }
        }

        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.loadError = error
                    return
                }
                do {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-initialize-cloudkit-schema") {
                        try self.container.initializeCloudKitSchema(options: [])
                    }
                    #endif
                    try self.finishMigrationAndSeed()
                    if ProcessInfo.processInfo.arguments.contains("-seed-installments") {
                        try self.seedUITestInstallmentsIfNeeded()
                    }
                    self.isStoreLoaded = true
                } catch {
                    self.loadError = error
                }
            }
        }

        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private static var defaultStoreURL: URL {
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroup
        ) {
            return groupURL.appendingPathComponent("Main.sqlite")
        }

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("Main.sqlite")
    }

    @discardableResult
    func createTransaction(
        note: String,
        category: Category?,
        income: Bool,
        amountMinorUnits: Int64,
        date: Date
    ) throws -> Transaction {
        guard amountMinorUnits > 0 else { throw InstallmentError.invalidAmount }
        let transaction = NSEntityDescription.insertNewObject(
            forEntityName: "Transaction",
            into: context
        ) as! Transaction
        configure(
            transaction,
            note: note,
            category: category,
            income: income,
            amountMinorUnits: amountMinorUnits,
            date: date
        )
        try save()
        return transaction
    }

    @discardableResult
    func createInstallments(
        note: String,
        category: Category?,
        income: Bool,
        totalMinorUnits: Int64,
        count: Int,
        firstDate: Date,
        intervalMonths: Int,
        groupID: UUID = UUID(),
        calendar: Calendar = .current
    ) throws -> [Transaction] {
        guard (2 ... 120).contains(count) else { throw InstallmentError.invalidCount }
        let duplicateRequest = Transaction.fetchRequest()
        duplicateRequest.fetchLimit = 1
        duplicateRequest.predicate = NSPredicate(format: "installmentGroupID == %@", groupID as CVarArg)
        guard try context.count(for: duplicateRequest) == 0 else { throw InstallmentError.duplicate }

        let plan = try InstallmentPlanner.plan(
            totalMinorUnits: totalMinorUnits,
            count: count,
            firstDate: firstDate,
            intervalMonths: intervalMonths,
            calendar: calendar
        )

        let transactions = plan.map { slice in
            let transaction = NSEntityDescription.insertNewObject(
                forEntityName: "Transaction",
                into: context
            ) as! Transaction
            configure(
                transaction,
                note: note,
                category: category,
                income: income,
                amountMinorUnits: slice.amountMinorUnits,
                date: slice.date
            )
            transaction.installmentGroupID = groupID
            transaction.installmentIndex = Int16(slice.index)
            transaction.installmentCount = Int16(slice.count)
            transaction.installmentIntervalMonths = Int16(intervalMonths)
            transaction.installmentOriginalTotalMinorUnits = totalMinorUnits
            return transaction
        }

        try save()
        return transactions
    }

    func update(
        _ transaction: Transaction,
        note: String,
        category: Category?,
        income: Bool,
        amountMinorUnits: Int64,
        date: Date,
        intervalMonths: Int,
        scope: EditScope
    ) throws {
        guard amountMinorUnits > 0 else { throw InstallmentError.invalidAmount }

        guard
            scope == .thisAndFollowing,
            let groupID = transaction.installmentGroupID,
            transaction.installmentIndex > 0
        else {
            configure(
                transaction,
                note: note,
                category: category,
                income: income,
                amountMinorUnits: amountMinorUnits,
                date: date
            )
            try save()
            return
        }

        let request = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "installmentIndex", ascending: true)]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "installmentGroupID == %@", groupID as CVarArg),
            NSPredicate(format: "installmentIndex >= %d", transaction.installmentIndex)
        ])
        let remaining = try context.fetch(request)
        guard !remaining.isEmpty else { throw InstallmentError.missingGroup }

        let plan = try InstallmentPlanner.plan(
            totalMinorUnits: amountMinorUnits,
            count: remaining.count,
            firstDate: date,
            intervalMonths: intervalMonths
        )
        let priorTotal = try totalMinorUnits(
            groupID: groupID,
            beforeIndex: Int(transaction.installmentIndex)
        )
        let newGroupTotal = priorTotal + amountMinorUnits

        for (item, slice) in zip(remaining, plan) {
            configure(
                item,
                note: note,
                category: category,
                income: income,
                amountMinorUnits: slice.amountMinorUnits,
                date: slice.date
            )
            item.installmentIntervalMonths = Int16(intervalMonths)
        }

        let allInGroup = try installments(groupID: groupID)
        allInGroup.forEach { $0.installmentOriginalTotalMinorUnits = newGroupTotal }
        try save()
    }

    func delete(_ transaction: Transaction, scope: EditScope) throws {
        if
            scope == .thisAndFollowing,
            let groupID = transaction.installmentGroupID,
            transaction.installmentIndex > 0
        {
            let request = Transaction.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "installmentGroupID == %@", groupID as CVarArg),
                NSPredicate(format: "installmentIndex >= %d", transaction.installmentIndex)
            ])
            try context.fetch(request).forEach(context.delete)
        } else {
            context.delete(transaction)
        }
        try save()
    }

    func deleteAll() throws {
        for entityName in ["Transaction", "Category", "Budget", "MainBudget", "TemplateTransaction"] {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            deleteRequest.resultType = .resultTypeObjectIDs
            if let result = try context.execute(deleteRequest) as? NSBatchDeleteResult,
               let objectIDs = result.result as? [NSManagedObjectID]
            {
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                    into: [context]
                )
            }
        }
        try finishMigrationAndSeed()
    }

    func installments(groupID: UUID) throws -> [Transaction] {
        let request = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "installmentIndex", ascending: true)]
        request.predicate = NSPredicate(format: "installmentGroupID == %@", groupID as CVarArg)
        return try context.fetch(request)
    }

    func save() throws {
        guard context.hasChanges else { return }
        do {
            try context.save()
            updateWidgetSnapshot()
        } catch {
            context.rollback()
            throw error
        }
    }

    func dismissLoadError() {
        loadError = nil
    }

    private func configure(
        _ transaction: Transaction,
        note: String,
        category: Category?,
        income: Bool,
        amountMinorUnits: Int64,
        date: Date
    ) {
        let calendar = Calendar.current
        transaction.id = transaction.id ?? UUID()
        transaction.createdAt = transaction.createdAt ?? Date.now
        transaction.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.category = category
        transaction.income = income
        transaction.amount = Double(amountMinorUnits) / 100
        transaction.date = date
        transaction.day = calendar.startOfDay(for: date)
        transaction.month = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }

    private func totalMinorUnits(groupID: UUID, beforeIndex: Int) throws -> Int64 {
        let request = Transaction.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "installmentGroupID == %@", groupID as CVarArg),
            NSPredicate(format: "installmentIndex < %d", beforeIndex)
        ])
        return try context.fetch(request).reduce(0) { $0 + $1.amountMinorUnits }
    }

    private func finishMigrationAndSeed() throws {
        let transactionRequest = Transaction.fetchRequest()
        let transactions = try context.fetch(transactionRequest)
        transactions.forEach {
            $0.id = $0.id ?? UUID()
            $0.createdAt = $0.createdAt ?? $0.date ?? Date.now
        }

        try localizeKnownLegacyCategories()
        try deduplicateInstallments()

        let categoryRequest = Category.fetchRequest()
        if try context.count(for: categoryRequest) == 0 {
            let defaults: [(String, String, String, Bool)] = [
                ("category.market", "🛒", "#FF6B5E", false),
                ("category.food", "🍽️", "#FF9F43", false),
                ("category.transport", "🚇", "#37D6C0", false),
                ("category.bills", "🧾", "#5B8DEF", false),
                ("category.shopping", "🛍️", "#A66CFF", false),
                ("category.health", "🩺", "#EF5DA8", false),
                ("category.entertainment", "🎟️", "#F5C451", false),
                ("category.salary", "💼", "#20B26B", true)
            ]

            for (index, item) in defaults.enumerated() {
                let category = NSEntityDescription.insertNewObject(
                    forEntityName: "Category",
                    into: context
                ) as! Category
                category.id = UUID()
                category.systemKey = item.0
                category.name = item.0
                category.emoji = item.1
                category.colour = item.2
                category.income = item.3
                category.order = Int64(index)
                category.dateCreated = Date.now
            }
        }

        try save()
    }

    private func localizeKnownLegacyCategories() throws {
        let mapping = [
            "groceries": "category.market",
            "food": "category.food",
            "transport": "category.transport",
            "bills": "category.bills",
            "shopping": "category.shopping",
            "health": "category.health",
            "entertainment": "category.entertainment",
            "salary": "category.salary"
        ]
        let request = Category.fetchRequest()
        request.predicate = NSPredicate(format: "systemKey == nil")
        try context.fetch(request).forEach { category in
            if let name = category.name?.lowercased(), let key = mapping[name] {
                category.systemKey = key
            }
        }
    }

    private func deduplicateInstallments() throws {
        let request = Transaction.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "installmentGroupID", ascending: true),
            NSSortDescriptor(key: "installmentIndex", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ]
        request.predicate = NSPredicate(format: "installmentGroupID != nil AND installmentIndex > 0")

        var seen = Set<String>()
        for transaction in try context.fetch(request) {
            guard let groupID = transaction.installmentGroupID else { continue }
            let key = "\(groupID.uuidString):\(transaction.installmentIndex)"
            if seen.insert(key).inserted == false {
                context.delete(transaction)
            }
        }
    }

    private func seedUITestInstallmentsIfNeeded() throws {
        let request = Transaction.fetchRequest()
        guard try context.count(for: request) == 0 else { return }
        let categoryRequest = Category.fetchRequest()
        categoryRequest.fetchLimit = 1
        let category = try context.fetch(categoryRequest).first
        try createInstallments(
            note: "UI Test",
            category: category,
            income: false,
            totalMinorUnits: 300_000,
            count: 3,
            firstDate: Date.now,
            intervalMonths: 1
        )
    }

    private func updateWidgetSnapshot() {
        let calendar = Calendar.current
        guard
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date.now)),
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)
        else { return }

        let monthlyRequest = Transaction.fetchRequest()
        monthlyRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "date >= %@ AND date < %@", monthStart as CVarArg, nextMonth as CVarArg),
            NSPredicate(format: "income == NO")
        ])
        let total = (try? context.fetch(monthlyRequest))?.reduce(0) { $0 + $1.amount } ?? 0
        UserDefaults.tutar.set(total, forKey: "widget.monthExpense")

        let nextRequest = Transaction.fetchRequest()
        nextRequest.fetchLimit = 1
        nextRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        nextRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "date > %@", Date.now as CVarArg),
            NSPredicate(format: "installmentGroupID != nil")
        ])

        if let next = try? context.fetch(nextRequest).first {
            UserDefaults.tutar.set(next.note, forKey: "widget.nextNote")
            UserDefaults.tutar.set(next.category?.systemKey, forKey: "widget.nextCategoryKey")
            UserDefaults.tutar.set(next.category?.name, forKey: "widget.nextCategoryName")
            UserDefaults.tutar.set(next.date, forKey: "widget.nextDate")
            UserDefaults.tutar.set(Int(next.installmentIndex), forKey: "widget.nextIndex")
            UserDefaults.tutar.set(Int(next.installmentCount), forKey: "widget.nextCount")
        } else {
            [
                "widget.nextNote", "widget.nextCategoryKey", "widget.nextCategoryName",
                "widget.nextDate", "widget.nextIndex", "widget.nextCount"
            ].forEach {
                UserDefaults.tutar.removeObject(forKey: $0)
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension Transaction {
    var wrappedDate: Date { date ?? .distantPast }
    func displayNote(language: AppLanguage) -> String {
        note?.isEmpty == false
            ? note!
            : category?.displayName(language: language) ?? AppFormat.localized("category.uncategorized", language: language)
    }
    var amountMinorUnits: Int64 { Int64((amount * 100).rounded()) }
    var isInstallment: Bool { installmentGroupID != nil && installmentIndex > 0 }
    var installmentLabel: String? {
        isInstallment ? "\(installmentIndex)/\(installmentCount)" : nil
    }
}

extension Category {
    func displayName(language: AppLanguage) -> String {
        guard let systemKey, !systemKey.isEmpty else { return name ?? "" }
        return AppFormat.localized(systemKey, language: language)
    }

    var wrappedEmoji: String { emoji ?? "•" }
}
