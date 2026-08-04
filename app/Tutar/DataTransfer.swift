// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct TransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw DataTransferError.unreadableFile
        }
        self.data = data
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct DataTransferResult: Equatable {
    let imported: Int
    let skipped: Int
}

enum DataTransferError: Error, Equatable {
    case unreadableFile
    case fileTooLarge
    case invalidFormat
    case unsupportedVersion
    case missingRequiredColumn
    case invalidRow(Int)
}

struct CSVCodec {
    static func encode(_ rows: [[String]]) -> String {
        rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    static func decode(_ text: String) throws -> [[String]] {
        var rows = [[String]]()
        var row = [String]()
        var field = ""
        var insideQuotes = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)

            if character == "\"" {
                if insideQuotes, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                insideQuotes.toggle()
            } else if character == ",", !insideQuotes {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !insideQuotes {
                if character == "\r", next < text.endIndex, text[next] == "\n" {
                    index = next
                }
                row.append(field)
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }

        guard !insideQuotes else { throw DataTransferError.invalidFormat }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        }
        if rows.first?.first?.hasPrefix("\u{feff}") == true {
            rows[0][0].removeFirst()
        }
        return rows
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private struct TutarBackup: Codable {
    let format: String
    let version: Int
    let exportedAt: Date
    let categories: [CategoryRecord]
    let transactions: [TransactionRecord]
    let budgets: [BudgetRecord]
    let overallBudgets: [OverallBudgetRecord]
    let templates: [TemplateRecord]
}

private struct CategoryRecord: Codable {
    let id: UUID
    let systemKey: String?
    let name: String
    let emoji: String
    let colour: String
    let income: Bool
    let order: Int64
    let dateCreated: Date?
}

private struct TransactionRecord: Codable {
    let id: UUID
    let note: String
    let categoryID: UUID?
    let income: Bool
    let amountMinorUnits: Int64
    let date: Date
    let createdAt: Date?
    let recurringType: Int
    let recurringCoefficient: Int
    let installmentGroupID: UUID?
    let installmentIndex: Int
    let installmentCount: Int
    let installmentIntervalMonths: Int
    let installmentOriginalTotalMinorUnits: Int64
}

private struct BudgetRecord: Codable {
    let id: UUID
    let categoryID: UUID?
    let amountMinorUnits: Int64
    let type: Int
    let startDate: Date?
    let dateCreated: Date?
}

private struct OverallBudgetRecord: Codable {
    let amountMinorUnits: Int64
    let type: Int
    let startDate: Date?
    let dateCreated: Date?
}

private struct TemplateRecord: Codable {
    let id: UUID
    let categoryID: UUID?
    let note: String
    let income: Bool
    let amountMinorUnits: Int64
    let order: Int
    let recurringType: Int
    let recurringCoefficient: Int
}

extension DataController {
    func exportCSV(language: AppLanguage) throws -> Data {
        let request = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        let header = [
            "Date", "Note", "Amount", "Category", "Type", "ID", "CategoryID",
            "InstallmentGroupID", "InstallmentIndex", "InstallmentCount",
            "InstallmentIntervalMonths", "InstallmentOriginalTotalMinorUnits",
            "RecurringType", "RecurringCoefficient"
        ]

        let rows = try context.fetch(request).map { transaction in
            [
                Self.iso8601.string(from: transaction.wrappedDate),
                transaction.note ?? "",
                String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), transaction.amount),
                transaction.category?.displayName(language: language) ?? "",
                transaction.income ? "Income" : "Expense",
                transaction.id?.uuidString ?? "",
                transaction.category?.id?.uuidString ?? "",
                transaction.installmentGroupID?.uuidString ?? "",
                transaction.installmentIndex > 0 ? String(transaction.installmentIndex) : "",
                transaction.installmentCount > 0 ? String(transaction.installmentCount) : "",
                transaction.installmentIntervalMonths > 0 ? String(transaction.installmentIntervalMonths) : "",
                transaction.installmentOriginalTotalMinorUnits > 0
                    ? String(transaction.installmentOriginalTotalMinorUnits) : "",
                transaction.recurringType > 0 ? String(transaction.recurringType) : "",
                transaction.recurringCoefficient > 0 ? String(transaction.recurringCoefficient) : ""
            ]
        }
        guard let data = CSVCodec.encode([header] + rows).data(using: .utf8) else {
            throw DataTransferError.invalidFormat
        }
        return data
    }

    func exportBackup() throws -> Data {
        let categories = try context.fetch(Category.fetchRequest()).map { category in
            CategoryRecord(
                id: category.id ?? UUID(),
                systemKey: category.systemKey,
                name: category.name ?? "",
                emoji: category.emoji ?? "",
                colour: category.colour ?? "#5E5CE6",
                income: category.income,
                order: category.order,
                dateCreated: category.dateCreated
            )
        }
        let transactions = try context.fetch(Transaction.fetchRequest()).compactMap { transaction -> TransactionRecord? in
            guard let id = transaction.id, transaction.amountMinorUnits > 0, transaction.date != nil else { return nil }
            return TransactionRecord(
                id: id,
                note: transaction.note ?? "",
                categoryID: transaction.category?.id,
                income: transaction.income,
                amountMinorUnits: transaction.amountMinorUnits,
                date: transaction.wrappedDate,
                createdAt: transaction.createdAt,
                recurringType: Int(transaction.recurringType),
                recurringCoefficient: Int(transaction.recurringCoefficient),
                installmentGroupID: transaction.installmentGroupID,
                installmentIndex: Int(transaction.installmentIndex),
                installmentCount: Int(transaction.installmentCount),
                installmentIntervalMonths: Int(transaction.installmentIntervalMonths),
                installmentOriginalTotalMinorUnits: transaction.installmentOriginalTotalMinorUnits
            )
        }
        let budgets = try context.fetch(Budget.fetchRequest()).map { budget in
            BudgetRecord(
                id: budget.id ?? UUID(),
                categoryID: budget.category?.id,
                amountMinorUnits: Int64((budget.amount * 100).rounded()),
                type: Int(budget.type),
                startDate: budget.startDate,
                dateCreated: budget.dateCreated
            )
        }
        let overall = try context.fetch(MainBudget.fetchRequest()).map { budget in
            OverallBudgetRecord(
                amountMinorUnits: Int64((budget.amount * 100).rounded()),
                type: Int(budget.type),
                startDate: budget.startDate,
                dateCreated: budget.dateCreated
            )
        }
        let templates = try context.fetch(TemplateTransaction.fetchRequest()).compactMap { item -> TemplateRecord? in
            guard let id = item.id else { return nil }
            return TemplateRecord(
                id: id,
                categoryID: item.category?.id,
                note: item.note ?? "",
                income: item.income,
                amountMinorUnits: Int64((item.amount * 100).rounded()),
                order: Int(item.order),
                recurringType: Int(item.recurringType),
                recurringCoefficient: Int(item.recurringCoefficient)
            )
        }

        let backup = TutarBackup(
            format: "com.furkancakir.tutar.backup",
            version: 1,
            exportedAt: .now,
            categories: categories,
            transactions: transactions,
            budgets: budgets,
            overallBudgets: overall,
            templates: templates
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(backup)
    }

    func importData(_ data: Data, fileExtension: String, language: AppLanguage) throws -> DataTransferResult {
        do {
            if fileExtension.lowercased() == "json" || data.firstNonWhitespaceByte == UInt8(ascii: "{") {
                return try importBackup(data)
            }
            guard let text = String(data: data, encoding: .utf8) else {
                throw DataTransferError.unreadableFile
            }
            return try importCSV(text, language: language)
        } catch {
            context.rollback()
            throw error
        }
    }

    private func importBackup(_ data: Data) throws -> DataTransferResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(TutarBackup.self, from: data)
        guard backup.format == "com.furkancakir.tutar.backup" else { throw DataTransferError.invalidFormat }
        guard backup.version == 1 else { throw DataTransferError.unsupportedVersion }

        let existingCategories = try context.fetch(Category.fetchRequest())
        var categoriesByID = Dictionary(uniqueKeysWithValues: existingCategories.compactMap { category in
            category.id.map { ($0, category) }
        })
        var categoriesBySystemKey = Dictionary(uniqueKeysWithValues: existingCategories.compactMap { category in
            category.systemKey.map { ($0, category) }
        })
        var imported = 0
        var skipped = 0

        for record in backup.categories {
            if categoriesByID[record.id] != nil {
                skipped += 1
                continue
            }
            if let key = record.systemKey, let existing = categoriesBySystemKey[key] {
                categoriesByID[record.id] = existing
                skipped += 1
                continue
            }
            guard record.name.count <= 80, record.emoji.count <= 16, Self.validHex(record.colour) else {
                throw DataTransferError.invalidFormat
            }
            let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context) as! Category
            category.id = record.id
            category.systemKey = record.systemKey?.prefix(100).description
            category.name = record.name
            category.emoji = record.emoji
            category.colour = record.colour
            category.income = record.income
            category.order = record.order
            category.dateCreated = record.dateCreated ?? .now
            categoriesByID[record.id] = category
            if let key = category.systemKey { categoriesBySystemKey[key] = category }
            imported += 1
        }

        let existingTransactions = try context.fetch(Transaction.fetchRequest())
        let existingTransactionIDs = Set(existingTransactions.compactMap(\.id))
        var addedTransactionIDs = Set<UUID>()
        var groupPositions = Set(existingTransactions.compactMap { transaction -> String? in
            guard let groupID = transaction.installmentGroupID, transaction.installmentIndex > 0 else { return nil }
            return "\(groupID.uuidString):\(transaction.installmentIndex)"
        })
        var groupMetadata = [UUID: String]()
        for transaction in existingTransactions where transaction.isInstallment {
            guard let groupID = transaction.installmentGroupID else { continue }
            groupMetadata[groupID] = Self.groupMetadata(
                count: Int(transaction.installmentCount),
                interval: Int(transaction.installmentIntervalMonths),
                total: transaction.installmentOriginalTotalMinorUnits
            )
        }

        for (index, record) in backup.transactions.enumerated() {
            guard record.amountMinorUnits > 0, record.amountMinorUnits <= MoneyEntry.maximumMinorUnits,
                  record.note.count <= 500 else {
                throw DataTransferError.invalidRow(index + 1)
            }
            guard !existingTransactionIDs.contains(record.id), addedTransactionIDs.insert(record.id).inserted else {
                skipped += 1
                continue
            }

            if let groupID = record.installmentGroupID {
                guard (2 ... 120).contains(record.installmentCount),
                      (1 ... record.installmentCount).contains(record.installmentIndex),
                      (1 ... 24).contains(record.installmentIntervalMonths),
                      record.installmentOriginalTotalMinorUnits > 0,
                      record.installmentOriginalTotalMinorUnits <= MoneyEntry.maximumMinorUnits else {
                    throw DataTransferError.invalidRow(index + 1)
                }
                let metadata = Self.groupMetadata(
                    count: record.installmentCount,
                    interval: record.installmentIntervalMonths,
                    total: record.installmentOriginalTotalMinorUnits
                )
                guard groupMetadata[groupID].map({ $0 == metadata }) ?? true else {
                    throw DataTransferError.invalidRow(index + 1)
                }
                groupMetadata[groupID] = metadata
                let position = "\(groupID.uuidString):\(record.installmentIndex)"
                guard groupPositions.insert(position).inserted else {
                    skipped += 1
                    continue
                }
            }

            let transaction = NSEntityDescription.insertNewObject(forEntityName: "Transaction", into: context) as! Transaction
            configure(
                transaction,
                note: record.note,
                category: record.categoryID.flatMap { categoriesByID[$0] },
                income: record.income,
                amountMinorUnits: record.amountMinorUnits,
                date: record.date
            )
            transaction.id = record.id
            transaction.createdAt = record.createdAt ?? record.date
            if (1 ... 3).contains(record.recurringType), (1 ... 99).contains(record.recurringCoefficient) {
                transaction.onceRecurring = true
                transaction.recurringType = Int16(record.recurringType)
                transaction.recurringCoefficient = Int16(record.recurringCoefficient)
            }
            transaction.installmentGroupID = record.installmentGroupID
            transaction.installmentIndex = Int16(record.installmentIndex)
            transaction.installmentCount = Int16(record.installmentCount)
            transaction.installmentIntervalMonths = Int16(record.installmentIntervalMonths)
            transaction.installmentOriginalTotalMinorUnits = record.installmentOriginalTotalMinorUnits
            if record.installmentGroupID == nil {
                transaction.installmentIndex = 0
                transaction.installmentCount = 0
                transaction.installmentIntervalMonths = 0
                transaction.installmentOriginalTotalMinorUnits = 0
            }
            guard (record.recurringType == 0 && record.recurringCoefficient == 0)
                || ((1 ... 3).contains(record.recurringType) && (1 ... 99).contains(record.recurringCoefficient)) else {
                throw DataTransferError.invalidRow(index + 1)
            }
            imported += 1
        }

        var existingBudgetIDs = Set(try context.fetch(Budget.fetchRequest()).compactMap(\.id))
        for record in backup.budgets {
            guard record.amountMinorUnits > 0, record.amountMinorUnits <= MoneyEntry.maximumMinorUnits,
                  (1 ... 4).contains(record.type), existingBudgetIDs.insert(record.id).inserted,
                  let categoryID = record.categoryID, let category = categoriesByID[categoryID], category.budget == nil else {
                skipped += 1
                continue
            }
            let budget = NSEntityDescription.insertNewObject(forEntityName: "Budget", into: context) as! Budget
            budget.id = record.id
            budget.amount = Double(record.amountMinorUnits) / 100
            budget.type = Int16(record.type)
            budget.startDate = record.startDate ?? .now
            budget.dateCreated = record.dateCreated ?? .now
            budget.category = category
            imported += 1
        }

        if try context.count(for: MainBudget.fetchRequest()) == 0, let record = backup.overallBudgets.first,
           record.amountMinorUnits > 0, (1 ... 4).contains(record.type) {
            let budget = NSEntityDescription.insertNewObject(forEntityName: "MainBudget", into: context) as! MainBudget
            budget.amount = Double(record.amountMinorUnits) / 100
            budget.type = Int16(record.type)
            budget.startDate = record.startDate ?? .now
            budget.dateCreated = record.dateCreated ?? .now
            imported += 1
        } else {
            skipped += backup.overallBudgets.count
        }

        var existingTemplateIDs = Set(try context.fetch(TemplateTransaction.fetchRequest()).compactMap(\.id))
        for record in backup.templates {
            guard existingTemplateIDs.insert(record.id).inserted else {
                skipped += 1
                continue
            }
            guard record.amountMinorUnits > 0, record.amountMinorUnits <= MoneyEntry.maximumMinorUnits,
                  record.note.count <= 500, (0 ... 3).contains(record.recurringType),
                  (0 ... 99).contains(record.recurringCoefficient) else {
                throw DataTransferError.invalidFormat
            }
            let item = NSEntityDescription.insertNewObject(forEntityName: "TemplateTransaction", into: context) as! TemplateTransaction
            item.id = record.id
            item.category = record.categoryID.flatMap { categoriesByID[$0] }
            item.note = record.note
            item.income = record.income
            item.amount = Double(record.amountMinorUnits) / 100
            item.order = Int16(clamping: record.order)
            item.recurringType = Int16(clamping: record.recurringType)
            item.recurringCoefficient = Int16(clamping: record.recurringCoefficient)
            imported += 1
        }

        try save()
        return DataTransferResult(imported: imported, skipped: skipped)
    }

    private func importCSV(_ text: String, language: AppLanguage) throws -> DataTransferResult {
        var rows = try CSVCodec.decode(text)
        guard !rows.isEmpty else { throw DataTransferError.invalidFormat }

        let first = rows[0].map(Self.normalizedHeader)
        let hasHeader = first.contains("date") && first.contains("amount")
        let headers: [String]
        if hasHeader {
            headers = first
            rows.removeFirst()
        } else {
            headers = ["date", "note", "amount", "category", "type"]
        }

        guard let dateColumn = headers.firstIndex(of: "date"),
              let amountColumn = headers.firstIndex(of: "amount") else {
            throw DataTransferError.missingRequiredColumn
        }
        let noteColumn = headers.firstIndex(of: "note")
        let categoryColumn = headers.firstIndex(of: "category")
        let typeColumn = headers.firstIndex(of: "type")
        let idColumn = headers.firstIndex(of: "id")
        let categoryIDColumn = headers.firstIndex(of: "categoryid")
        let groupColumn = headers.firstIndex(of: "installmentgroupid")
        let indexColumn = headers.firstIndex(of: "installmentindex")
        let countColumn = headers.firstIndex(of: "installmentcount")
        let intervalColumn = headers.firstIndex(of: "installmentintervalmonths")
        let totalColumn = headers.firstIndex(of: "installmentoriginaltotalminorunits")
        let recurringTypeColumn = headers.firstIndex(of: "recurringtype")
        let recurringCoefficientColumn = headers.firstIndex(of: "recurringcoefficient")

        let existingTransactions = try context.fetch(Transaction.fetchRequest())
        var existingIDs = Set(existingTransactions.compactMap(\.id))
        var signatures = Set(existingTransactions.map(Self.signature))
        var groupPositions = Set(existingTransactions.compactMap { transaction -> String? in
            guard let group = transaction.installmentGroupID, transaction.installmentIndex > 0 else { return nil }
            return "\(group.uuidString):\(transaction.installmentIndex)"
        })
        var groupMetadata = [UUID: String]()
        for transaction in existingTransactions where transaction.isInstallment {
            guard let groupID = transaction.installmentGroupID else { continue }
            groupMetadata[groupID] = Self.groupMetadata(
                count: Int(transaction.installmentCount),
                interval: Int(transaction.installmentIntervalMonths),
                total: transaction.installmentOriginalTotalMinorUnits
            )
        }
        var categories = try context.fetch(Category.fetchRequest())
        var imported = 0
        var skipped = 0

        for (rowIndex, row) in rows.enumerated() {
            guard row.indices.contains(dateColumn), row.indices.contains(amountColumn),
                  let date = Self.parseDate(row[dateColumn]),
                  let amountMinorUnits = Self.parseAmount(row[amountColumn]),
                  amountMinorUnits > 0,
                  amountMinorUnits <= MoneyEntry.maximumMinorUnits else {
                throw DataTransferError.invalidRow(rowIndex + (hasHeader ? 2 : 1))
            }

            let note = noteColumn.flatMap { row[safe: $0] } ?? ""
            guard note.count <= 500 else {
                throw DataTransferError.invalidRow(rowIndex + (hasHeader ? 2 : 1))
            }
            let typeValue = typeColumn.flatMap { row[safe: $0] }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? "expense"
            let income = ["income", "gelir", "true", "1", "+"].contains(typeValue)
            let id = idColumn.flatMap { row[safe: $0] }.flatMap(UUID.init(uuidString:)) ?? UUID()
            let signature = Self.signature(date: date, note: note, amount: amountMinorUnits, income: income)
            guard existingIDs.insert(id).inserted, signatures.insert(signature).inserted else {
                skipped += 1
                continue
            }

            let groupID = groupColumn.flatMap { row[safe: $0] }.flatMap(UUID.init(uuidString:))
            let installmentIndex = indexColumn.flatMap { row[safe: $0] }.flatMap(Int.init) ?? 0
            let installmentCount = countColumn.flatMap { row[safe: $0] }.flatMap(Int.init) ?? 0
            let installmentInterval = intervalColumn.flatMap { row[safe: $0] }.flatMap(Int.init) ?? 0
            let installmentTotal = totalColumn.flatMap { row[safe: $0] }.flatMap(Int64.init) ?? 0
            if let groupID {
                guard (2 ... 120).contains(installmentCount),
                      (1 ... installmentCount).contains(installmentIndex),
                      (1 ... 24).contains(installmentInterval),
                      installmentTotal > 0, installmentTotal <= MoneyEntry.maximumMinorUnits else {
                    throw DataTransferError.invalidRow(rowIndex + (hasHeader ? 2 : 1))
                }
                let metadata = Self.groupMetadata(
                    count: installmentCount,
                    interval: installmentInterval,
                    total: installmentTotal
                )
                guard groupMetadata[groupID].map({ $0 == metadata }) ?? true else {
                    throw DataTransferError.invalidRow(rowIndex + (hasHeader ? 2 : 1))
                }
                groupMetadata[groupID] = metadata
                let position = "\(groupID.uuidString):\(installmentIndex)"
                guard groupPositions.insert(position).inserted else {
                    skipped += 1
                    continue
                }
            }

            let categoryName = categoryColumn.flatMap { row[safe: $0] }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let categoryID = categoryIDColumn.flatMap { row[safe: $0] }.flatMap(UUID.init(uuidString:))
            let category = try categoryForImport(
                id: categoryID,
                name: categoryName,
                income: income,
                language: language,
                categories: &categories
            )

            let transaction = NSEntityDescription.insertNewObject(forEntityName: "Transaction", into: context) as! Transaction
            configure(
                transaction,
                note: note,
                category: category,
                income: income,
                amountMinorUnits: amountMinorUnits,
                date: date
            )
            transaction.id = id
            transaction.installmentGroupID = groupID
            transaction.installmentIndex = groupID == nil ? 0 : Int16(installmentIndex)
            transaction.installmentCount = groupID == nil ? 0 : Int16(installmentCount)
            transaction.installmentIntervalMonths = groupID == nil ? 0 : Int16(installmentInterval)
            transaction.installmentOriginalTotalMinorUnits = groupID == nil ? 0 : installmentTotal
            let recurringType = recurringTypeColumn.flatMap { row[safe: $0] }.flatMap(Int.init) ?? 0
            let recurringCoefficient = recurringCoefficientColumn.flatMap { row[safe: $0] }.flatMap(Int.init) ?? 0
            guard (recurringType == 0 && recurringCoefficient == 0)
                || ((1 ... 3).contains(recurringType) && (1 ... 99).contains(recurringCoefficient)) else {
                throw DataTransferError.invalidRow(rowIndex + (hasHeader ? 2 : 1))
            }
            if (1 ... 3).contains(recurringType), (1 ... 99).contains(recurringCoefficient) {
                transaction.onceRecurring = true
                transaction.recurringType = Int16(recurringType)
                transaction.recurringCoefficient = Int16(recurringCoefficient)
            }
            imported += 1
        }

        guard imported > 0 || skipped > 0 else { throw DataTransferError.invalidFormat }
        try save()
        return DataTransferResult(imported: imported, skipped: skipped)
    }

    private func categoryForImport(
        id: UUID?,
        name: String,
        income: Bool,
        language: AppLanguage,
        categories: inout [Category]
    ) throws -> Category? {
        if let id, let match = categories.first(where: { $0.id == id }) { return match }
        guard !name.isEmpty else { return nil }
        guard name.count <= 80 else { throw DataTransferError.invalidFormat }
        if let match = categories.first(where: {
            $0.income == income
                && ($0.name?.localizedCaseInsensitiveCompare(name) == .orderedSame
                    || $0.displayName(language: language).localizedCaseInsensitiveCompare(name) == .orderedSame)
        }) {
            return match
        }

        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context) as! Category
        category.id = id ?? UUID()
        category.name = name
        category.emoji = "🗂️"
        category.colour = "#5E5CE6"
        category.income = income
        category.order = (categories.filter { $0.income == income }.map(\.order).max() ?? -1) + 1
        category.dateCreated = .now
        categories.append(category)
        return category
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func parseDate(_ value: String) -> Date? {
        if let date = iso8601.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in [
            "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd",
            "dd-MM-yyyy", "MM-dd-yyyy", "yyyy/MM/dd", "dd/MM/yyyy", "MM/dd/yyyy",
            "yyyyMMdd", "ddMMyyyy", "MMddyyyy", "dd/MM/yyyy HH:mm:ss"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func parseAmount(_ value: String) -> Int64? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decimal = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var absolute = decimal < 0 ? -decimal : decimal
        absolute *= 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &absolute, 0, .plain)
        guard rounded == absolute else { return nil }
        let number = NSDecimalNumber(decimal: rounded)
        guard number != .notANumber,
              number.compare(NSDecimalNumber(value: MoneyEntry.maximumMinorUnits)) != .orderedDescending else {
            return nil
        }
        return number.int64Value
    }

    private static func signature(_ transaction: Transaction) -> String {
        signature(
            date: transaction.wrappedDate,
            note: transaction.note ?? "",
            amount: transaction.amountMinorUnits,
            income: transaction.income
        )
    }

    private static func signature(date: Date, note: String, amount: Int64, income: Bool) -> String {
        "\(Int64(date.timeIntervalSince1970.rounded()))|\(note.lowercased())|\(amount)|\(income)"
    }

    private static func normalizedHeader(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func validHex(_ value: String) -> Bool {
        value.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil
    }

    private static func groupMetadata(count: Int, interval: Int, total: Int64) -> String {
        "\(count):\(interval):\(total)"
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Data {
    var firstNonWhitespaceByte: UInt8? {
        first { ![9, 10, 13, 32].contains($0) }
    }
}
