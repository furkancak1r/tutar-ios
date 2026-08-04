// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import CoreData
import SwiftUI

struct TransactionEditorView: View {
    private enum Field: Hashable {
        case note
        case amount
    }

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.order, ascending: true)],
        animation: .default
    ) private var categories: FetchedResults<Category>
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    let transaction: Transaction?

    @State private var note: String
    @State private var amountText: String
    @State private var date: Date
    @State private var income: Bool
    @State private var category: Category?
    @State private var isInstallment: Bool
    @State private var count: Int
    @State private var intervalMonths: Int
    @State private var editScope = EditScope.one
    @State private var errorKey: String?
    @FocusState private var focusedField: Field?

    private var matchingCategories: [Category] {
        categories.filter { $0.income == income }
    }

    private var isEditingInstallment: Bool { transaction?.isInstallment == true }

    var body: some View {
        NavigationStack {
            Form {
                Section("editor.type.section") {
                    Picker("editor.type.label", selection: $income) {
                        Text("editor.expense").tag(false)
                        Text("editor.income").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("transactionTypePicker")
                    .onChange(of: income) { _, newValue in
                        if newValue { isInstallment = false }
                        category = matchingCategories.first
                    }
                }

                Section("editor.details.section") {
                    TextField("editor.note", text: $note)
                        .textInputAutocapitalization(.sentences)
                        .focused($focusedField, equals: .note)
                        .accessibilityIdentifier("noteField")

                    TextField("editor.amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .amount)
                        .accessibilityIdentifier("amountField")

                    Picker("editor.category", selection: $category) {
                        ForEach(matchingCategories) { item in
                            Text(verbatim: "\(item.wrappedEmoji) \(item.displayName(language: language))")
                                .tag(Optional(item))
                        }
                    }
                    .accessibilityIdentifier("categoryPicker")

                    DatePicker("editor.date", selection: $date, displayedComponents: .date)
                        .accessibilityIdentifier("datePicker")
                }

                if transaction == nil {
                    Section {
                        Toggle("editor.installment.toggle", isOn: $isInstallment)
                            .disabled(income)
                            .accessibilityIdentifier("installmentToggle")

                        if isInstallment {
                            Stepper(value: $count, in: 2 ... 120) {
                                LabeledContent("editor.installment.count", value: "\(count)")
                            }
                            .accessibilityIdentifier("installmentCountStepper")

                            Stepper(value: $intervalMonths, in: 1 ... 24) {
                                LabeledContent(
                                    "editor.installment.interval",
                                    value: AppFormat.plural("months.count", count: intervalMonths, language: language)
                                )
                            }
                            .accessibilityIdentifier("installmentIntervalStepper")

                            Text("editor.installment.remainderNote")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("editor.installment.section")
                    } footer: {
                        if isInstallment {
                            Text("editor.installment.futureNote")
                        }
                    }
                } else if isEditingInstallment {
                    Section("editor.apply.section") {
                        Picker("editor.apply.label", selection: $editScope) {
                            Text("editor.apply.one").tag(EditScope.one)
                            Text("editor.apply.following").tag(EditScope.thisAndFollowing)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: editScope) { _, scope in
                            if scope == .thisAndFollowing { loadRemainingTotal() }
                            else if let transaction { amountText = decimalText(transaction.amount) }
                        }

                        if editScope == .thisAndFollowing {
                            Stepper(value: $intervalMonths, in: 1 ... 24) {
                                LabeledContent(
                                    "editor.installment.interval",
                                    value: AppFormat.plural("months.count", count: intervalMonths, language: language)
                                )
                            }
                            Text("editor.apply.totalHint")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorKey {
                    Section {
                        Label(AppFormat.localized(errorKey, language: language), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("editorError")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(transaction == nil ? "editor.new.title" : "editor.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                        .fontWeight(.bold)
                        .accessibilityIdentifier("saveTransactionButton")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("action.done") { focusedField = nil }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("keyboardDoneButton")
                }
            }
        }
        .interactiveDismissDisabled(false)
        .onAppear {
            if category == nil { category = matchingCategories.first }
        }
        .onChange(of: matchingCategories.count) { _, _ in
            if category == nil { category = matchingCategories.first }
        }
    }

    init(transaction: Transaction? = nil) {
        self.transaction = transaction
        _note = State(initialValue: transaction?.note ?? "")
        _amountText = State(initialValue: transaction.map { Self.decimalText($0.amount, locale: .autoupdatingCurrent) } ?? "")
        _date = State(initialValue: transaction?.wrappedDate ?? .now)
        _income = State(initialValue: transaction?.income ?? false)
        _category = State(initialValue: transaction?.category)
        _isInstallment = State(initialValue: false)
        _count = State(initialValue: 3)
        _intervalMonths = State(initialValue: max(Int(transaction?.installmentIntervalMonths ?? 1), 1))
    }

    private func save() {
        guard let amount = MoneyInput.minorUnits(from: amountText, locale: language.locale) else {
            errorKey = "editor.error.amount"
            return
        }
        guard let category = category ?? matchingCategories.first else {
            errorKey = "editor.error.category"
            return
        }

        do {
            if let transaction {
                try dataController.update(
                    transaction,
                    note: note,
                    category: category,
                    income: income,
                    amountMinorUnits: amount,
                    date: date,
                    intervalMonths: intervalMonths,
                    scope: editScope
                )
            } else if isInstallment {
                try dataController.createInstallments(
                    note: note,
                    category: category,
                    income: income,
                    totalMinorUnits: amount,
                    count: count,
                    firstDate: date,
                    intervalMonths: intervalMonths
                )
            } else {
                try dataController.createTransaction(
                    note: note,
                    category: category,
                    income: income,
                    amountMinorUnits: amount,
                    date: date
                )
            }
            dismiss()
        } catch InstallmentError.invalidAmount {
            errorKey = "editor.error.installmentAmount"
        } catch InstallmentError.duplicate {
            errorKey = "editor.error.duplicate"
        } catch {
            errorKey = "editor.error.save"
        }
    }

    private func loadRemainingTotal() {
        guard
            let transaction,
            let groupID = transaction.installmentGroupID,
            let group = try? dataController.installments(groupID: groupID)
        else { return }
        let total = group
            .filter { $0.installmentIndex >= transaction.installmentIndex }
            .reduce(0) { $0 + $1.amount }
        amountText = decimalText(total)
    }

    private func decimalText(_ amount: Double) -> String {
        Self.decimalText(amount, locale: language.locale)
    }

    private static func decimalText(_ amount: Double, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }
}
