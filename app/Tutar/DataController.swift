// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import CoreData
import Foundation
import WidgetKit

enum EditScope: Equatable {
    case one
    case thisAndFollowing
}

enum BudgetError: Error, Equatable {
    case invalidAmount
    case invalidType
    case missingCategory
    case duplicateCategory
    case duplicateOverall
}

enum CategoryError: Error, Equatable {
    case invalidName
    case invalidEmoji
    case invalidColour
    case duplicate
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
                    try self.materializeRecurringTransactions()
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
        date: Date,
        recurringType: Int = 0,
        recurringCoefficient: Int = 1
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
        configureRecurrence(
            transaction,
            type: recurringType,
            coefficient: recurringCoefficient
        )
        try materializeRecurringTransaction(transaction)
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
        recurringType: Int = 0,
        recurringCoefficient: Int = 1,
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
            configureRecurrence(
                transaction,
                type: recurringType,
                coefficient: recurringCoefficient
            )
            try materializeRecurringTransaction(transaction)
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

    func materializeRecurringTransactions() throws {
        let request = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "recurringType > 0")
        for transaction in try context.fetch(request) {
            try materializeRecurringTransaction(transaction)
        }
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

    @discardableResult
    func saveCategoryBudget(
        _ budget: Budget? = nil,
        category: Category,
        amountMinorUnits: Int64,
        type: Int,
        startDate: Date
    ) throws -> Budget {
        guard amountMinorUnits > 0 else { throw BudgetError.invalidAmount }
        guard (1 ... 4).contains(type) else { throw BudgetError.invalidType }

        let request = Budget.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "category == %@", category)
        if let existing = try context.fetch(request).first, existing != budget {
            throw BudgetError.duplicateCategory
        }

        let item = budget ?? (NSEntityDescription.insertNewObject(
            forEntityName: "Budget",
            into: context
        ) as! Budget)
        item.id = item.id ?? UUID()
        item.dateCreated = item.dateCreated ?? .now
        item.amount = Double(amountMinorUnits) / 100
        item.type = Int16(type)
        item.startDate = startDate
        item.category = category
        try save()
        return item
    }

    @discardableResult
    func saveOverallBudget(
        _ budget: MainBudget? = nil,
        amountMinorUnits: Int64,
        type: Int,
        startDate: Date
    ) throws -> MainBudget {
        guard amountMinorUnits > 0 else { throw BudgetError.invalidAmount }
        guard (1 ... 4).contains(type) else { throw BudgetError.invalidType }

        if budget == nil {
            let request = MainBudget.fetchRequest()
            request.fetchLimit = 1
            guard try context.count(for: request) == 0 else { throw BudgetError.duplicateOverall }
        }

        let item = budget ?? (NSEntityDescription.insertNewObject(
            forEntityName: "MainBudget",
            into: context
        ) as! MainBudget)
        item.dateCreated = item.dateCreated ?? .now
        item.amount = Double(amountMinorUnits) / 100
        item.type = Int16(type)
        item.startDate = startDate
        try save()
        return item
    }

    func deleteBudget(_ budget: NSManagedObject) throws {
        context.delete(budget)
        try save()
    }

    @discardableResult
    func saveCategory(
        _ category: Category? = nil,
        name: String,
        emoji: String,
        colour: String,
        income: Bool,
        replacesSystemName: Bool = false
    ) throws -> Category {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty, cleanedName.count <= 80 else { throw CategoryError.invalidName }
        guard !cleanedEmoji.isEmpty, cleanedEmoji.count <= 16 else { throw CategoryError.invalidEmoji }
        guard colour.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else {
            throw CategoryError.invalidColour
        }

        let request = Category.fetchRequest()
        request.predicate = NSPredicate(format: "income == %@", NSNumber(value: income))
        let duplicate = try context.fetch(request).contains {
            $0 != category && $0.name?.localizedCaseInsensitiveCompare(cleanedName) == .orderedSame
        }
        guard !duplicate else { throw CategoryError.duplicate }

        let item = category ?? (NSEntityDescription.insertNewObject(
            forEntityName: "Category",
            into: context
        ) as! Category)
        item.id = item.id ?? UUID()
        item.dateCreated = item.dateCreated ?? .now
        item.name = cleanedName
        item.emoji = cleanedEmoji
        item.colour = colour
        item.income = income
        if category == nil {
            item.order = (try context.fetch(request).map(\.order).max() ?? -1) + 1
        } else if replacesSystemName {
            item.systemKey = nil
        }
        try save()
        return item
    }

    func deleteCategory(_ category: Category) throws {
        let transactions = Transaction.fetchRequest()
        transactions.predicate = NSPredicate(format: "category == %@", category)
        try context.fetch(transactions).forEach { $0.category = nil }

        let templates = TemplateTransaction.fetchRequest()
        templates.predicate = NSPredicate(format: "category == %@", category)
        try context.fetch(templates).forEach { $0.category = nil }

        if let budget = category.budget { context.delete(budget) }
        context.delete(category)
        try save()
    }

    func reorderCategories(_ categories: [Category]) throws {
        for (index, category) in categories.enumerated() {
            category.order = Int64(index)
        }
        try save()
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

    func configure(
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

    private func configureRecurrence(_ transaction: Transaction, type: Int, coefficient: Int) {
        guard (1 ... 3).contains(type), (1 ... 99).contains(coefficient), !transaction.isInstallment else {
            transaction.onceRecurring = false
            transaction.recurringType = 0
            transaction.recurringCoefficient = 0
            return
        }
        transaction.onceRecurring = true
        transaction.recurringType = Int16(type)
        transaction.recurringCoefficient = Int16(coefficient)
    }

    private func materializeRecurringTransaction(_ transaction: Transaction, through date: Date = .now) throws {
        let type = Int(transaction.recurringType)
        let coefficient = Int(transaction.recurringCoefficient)
        guard (1 ... 3).contains(type), (1 ... 99).contains(coefficient) else { return }

        let calendar = Calendar.current
        let limit = calendar.startOfDay(for: date)
        var marker = transaction

        while let nextDate = nextRecurringDate(
            after: marker.wrappedDate,
            type: type,
            coefficient: coefficient,
            calendar: calendar
        ), calendar.startOfDay(for: nextDate) <= limit {
            marker.recurringType = 0
            marker.recurringCoefficient = 0

            let next = NSEntityDescription.insertNewObject(
                forEntityName: "Transaction",
                into: context
            ) as! Transaction
            configure(
                next,
                note: marker.note ?? "",
                category: marker.category,
                income: marker.income,
                amountMinorUnits: marker.amountMinorUnits,
                date: nextDate
            )
            next.onceRecurring = true
            next.recurringType = Int16(type)
            next.recurringCoefficient = Int16(coefficient)
            marker = next
        }
    }

    private func nextRecurringDate(
        after date: Date,
        type: Int,
        coefficient: Int,
        calendar: Calendar
    ) -> Date? {
        switch type {
        case 1:
            calendar.date(byAdding: .day, value: coefficient, to: date)
        case 2:
            calendar.date(byAdding: .day, value: coefficient * 7, to: date)
        case 3:
            calendar.date(byAdding: .month, value: coefficient, to: date)
        default:
            nil
        }
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

        let categoryRequest = Category.fetchRequest()
        try context.fetch(categoryRequest).forEach { $0.id = $0.id ?? UUID() }

        let budgetRequest = Budget.fetchRequest()
        try context.fetch(budgetRequest).forEach { $0.id = $0.id ?? UUID() }

        try localizeKnownLegacyCategories()
        try deduplicateInstallments()

        if try context.count(for: categoryRequest) == 0 {
            let defaults: [(String, String, String, Bool)] = [
                ("category.market", "🛒", "#9B554D", false),
                ("category.food", "🍽️", "#9A7B4F", false),
                ("category.transport", "🚇", "#5F6B5C", false),
                ("category.bills", "🧾", "#5C5A57", false),
                ("category.shopping", "🛍️", "#7A6068", false),
                ("category.health", "🩺", "#87504D", false),
                ("category.entertainment", "🎟️", "#736A62", false),
                ("category.salary", "💼", "#4F705F", true)
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
        categoryRequest.predicate = NSPredicate(format: "income == NO")
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
