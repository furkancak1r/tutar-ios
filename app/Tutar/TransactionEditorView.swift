// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import CoreData
import SwiftUI

private enum TransactionSchedule: Int, CaseIterable, Identifiable {
    case once
    case recurring
    case installments

    var id: Int { rawValue }
}

struct TransactionEditorView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.order, ascending: true)],
        animation: .default
    ) private var categories: FetchedResults<Category>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)]
    ) private var transactions: FetchedResults<Transaction>

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @AppStorage("currencyCode", store: .tutar) private var preferredCurrency = ""
    @AppStorage("showSuggestions", store: .tutar) private var showSuggestions = true

    let transaction: Transaction?

    @State private var note: String
    @State private var amountEntry: MoneyEntry
    @State private var date: Date
    @State private var income: Bool
    @State private var category: Category?
    @State private var schedule: TransactionSchedule
    @State private var recurringType: Int
    @State private var recurringCoefficient: Int
    @State private var installmentCount: Int
    @State private var intervalMonths: Int
    @State private var editScope = EditScope.one
    @State private var showingSchedule = false
    @State private var errorKey: String?
    @FocusState private var noteFocused: Bool

    private var matchingCategories: [Category] {
        categories.filter { $0.income == income }
    }

    private var isEditingInstallment: Bool { transaction?.isInstallment == true }

    private var currency: String {
        AppFormat.currencyCode(language: language, preferred: preferredCurrency)
    }

    private var amountText: String {
        AppFormat.money(
            Double(amountEntry.minorUnits) / 100,
            language: language,
            currencyCode: currency
        )
    }

    private var suggestions: [Transaction] {
        let query = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard showSuggestions, !query.isEmpty, transaction == nil else { return [] }

        var seen = Set<String>()
        return transactions.filter {
            $0.income == income
                && (category == nil || $0.category == category)
                && $0.displayNote(language: language).localizedCaseInsensitiveContains(query)
                && seen.insert($0.displayNote(language: language).lowercased()).inserted
        }
        .prefix(5)
        .map { $0 }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        Picker("editor.type.label", selection: $income) {
                            Text("editor.expense").tag(false)
                            Text("editor.income").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("transactionTypePicker")
                        .disabled(isEditingInstallment)
                        .onChange(of: income) { _, newValue in
                            if newValue, schedule == .installments { schedule = .once }
                            category = categories.first { $0.income == newValue }
                        }

                        HStack(alignment: .center, spacing: 8) {
                            Text(amountText)
                                .font(.largeTitle.weight(.semibold).monospacedDigit())
                                .minimumScaleFactor(0.45)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .contentTransition(.numericText())
                                .accessibilityLabel(Text("editor.amount"))
                                .accessibilityValue(Text(verbatim: amountText))
                                .accessibilityIdentifier("amountDisplay")

                        }
                        .padding(.vertical, 8)

                        TextField("editor.note", text: $note)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .focused($noteFocused)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .accessibilityIdentifier("noteField")

                        if !suggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(suggestions) { suggestion in
                                        Button {
                                            note = suggestion.note ?? ""
                                            category = suggestion.category
                                            if amountEntry.isEmpty {
                                                amountEntry = MoneyEntry(
                                                    minorUnits: suggestion.amountMinorUnits,
                                                    mode: amountEntry.mode
                                                )
                                            }
                                            noteFocused = false
                                        } label: {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(verbatim: suggestion.displayNote(language: language))
                                                    .lineLimit(1)
                                                Text(AppFormat.money(
                                                    suggestion.amount,
                                                    language: language,
                                                    currencyCode: currency
                                                ))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            .accessibilityLabel(Text("editor.suggestions"))
                        }

                        VStack(spacing: 0) {
                            LabeledContent("editor.category") {
                                Menu {
                                    ForEach(matchingCategories) { item in
                                        Button {
                                            category = item
                                        } label: {
                                            Text(verbatim: "\(item.wrappedEmoji) \(item.displayName(language: language))")
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(verbatim: category?.wrappedEmoji ?? "•")
                                        Text(verbatim: category?.displayName(language: language) ?? AppFormat.localized("editor.category.choose", language: language))
                                            .lineLimit(1)
                                    }
                                }
                                .accessibilityIdentifier("categoryPicker")
                            }
                            .padding(.vertical, 13)

                            Divider()

                            LabeledContent("editor.date") {
                                DatePicker(
                                    "editor.date",
                                    selection: $date,
                                    displayedComponents: .date
                                )
                                .labelsHidden()
                                .accessibilityIdentifier("datePicker")
                            }
                            .padding(.vertical, 10)

                            Divider()

                            LabeledContent("editor.schedule") {
                                Button {
                                    showingSchedule = true
                                } label: {
                                    Label(scheduleSummary, systemImage: scheduleIcon)
                                        .lineLimit(1)
                                }
                                .accessibilityIdentifier("scheduleButton")
                            }
                            .padding(.vertical, 13)
                        }
                        .padding(.horizontal, 14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        if isEditingInstallment {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("editor.apply.section")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Picker("editor.apply.label", selection: $editScope) {
                                    Text("editor.apply.one").tag(EditScope.one)
                                    Text("editor.apply.following").tag(EditScope.thisAndFollowing)
                                }
                                .pickerStyle(.segmented)
                                .accessibilityIdentifier("editScopePicker")
                                .onChange(of: editScope) { _, scope in
                                    if scope == .thisAndFollowing {
                                        loadRemainingTotal()
                                    } else if let transaction {
                                        amountEntry = MoneyEntry(minorUnits: transaction.amountMinorUnits, mode: amountEntry.mode)
                                    }
                                }

                                if editScope == .thisAndFollowing {
                                    Text("editor.apply.totalHint")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if let errorKey {
                            Label(AppFormat.localized(errorKey, language: language), systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("editorError")
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)

                if !noteFocused {
                    AmountKeypad(entry: $amountEntry, submit: save)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(transaction == nil ? "editor.new.title" : "editor.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save", action: save)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("saveTransactionButton")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("action.done") { noteFocused = false }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("keyboardDoneButton")
                }
            }
            .sheet(isPresented: $showingSchedule) {
                SchedulePickerView(
                    schedule: $schedule,
                    recurringType: $recurringType,
                    recurringCoefficient: $recurringCoefficient,
                    installmentCount: $installmentCount,
                    intervalMonths: $intervalMonths,
                    allowsInstallments: !income && (transaction == nil || isEditingInstallment),
                    locksScheduleKind: isEditingInstallment
                )
            }
        }
        .interactiveDismissDisabled(false)
        .onAppear {
            if category == nil { category = matchingCategories.first }
        }
    }

    init(transaction: Transaction? = nil) {
        self.transaction = transaction
        let rawMode = UserDefaults.tutar.object(forKey: "numberEntryType") as? Int ?? 1
        let mode = MoneyEntry.Mode(rawValue: rawMode) ?? .automaticCents

        _note = State(initialValue: transaction?.note ?? "")
        _amountEntry = State(initialValue: MoneyEntry(minorUnits: transaction?.amountMinorUnits ?? 0, mode: mode))
        _date = State(initialValue: transaction?.wrappedDate ?? .now)
        _income = State(initialValue: transaction?.income ?? false)
        _category = State(initialValue: transaction?.category)
        _recurringType = State(initialValue: max(Int(transaction?.recurringType ?? 0), 1))
        _recurringCoefficient = State(initialValue: max(Int(transaction?.recurringCoefficient ?? 1), 1))
        _installmentCount = State(initialValue: max(Int(transaction?.installmentCount ?? 3), 2))
        _intervalMonths = State(initialValue: max(Int(transaction?.installmentIntervalMonths ?? 1), 1))

        if transaction?.isInstallment == true {
            _schedule = State(initialValue: .installments)
        } else if (transaction?.recurringType ?? 0) > 0 {
            _schedule = State(initialValue: .recurring)
        } else {
            _schedule = State(initialValue: .once)
        }
    }

    private var scheduleIcon: String {
        switch schedule {
        case .once: "calendar"
        case .recurring: "repeat"
        case .installments: "calendar.badge.clock"
        }
    }

    private var scheduleSummary: String {
        switch schedule {
        case .once:
            AppFormat.localized("schedule.once", language: language)
        case .recurring:
            AppFormat.plural(recurringSummaryKey, count: recurringCoefficient, language: language)
        case .installments:
            AppFormat.plural("schedule.installment.summary", count: installmentCount, language: language)
        }
    }

    private var recurringSummaryKey: String {
        switch recurringType {
        case 1: "schedule.every.days"
        case 2: "schedule.every.weeks"
        default: "schedule.every.months"
        }
    }

    private func save() {
        let amount = amountEntry.minorUnits
        guard amount > 0 else {
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
                    recurringType: schedule == .recurring ? recurringType : 0,
                    recurringCoefficient: recurringCoefficient,
                    scope: editScope
                )
            } else if schedule == .installments {
                try dataController.createInstallments(
                    note: note,
                    category: category,
                    income: income,
                    totalMinorUnits: amount,
                    count: installmentCount,
                    firstDate: date,
                    intervalMonths: intervalMonths
                )
            } else {
                try dataController.createTransaction(
                    note: note,
                    category: category,
                    income: income,
                    amountMinorUnits: amount,
                    date: date,
                    recurringType: schedule == .recurring ? recurringType : 0,
                    recurringCoefficient: recurringCoefficient
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
            .reduce(Int64(0)) { $0 + $1.amountMinorUnits }
        amountEntry = MoneyEntry(minorUnits: total, mode: amountEntry.mode)
    }
}

private struct SchedulePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    @Binding var schedule: TransactionSchedule
    @Binding var recurringType: Int
    @Binding var recurringCoefficient: Int
    @Binding var installmentCount: Int
    @Binding var intervalMonths: Int

    let allowsInstallments: Bool
    let locksScheduleKind: Bool

    private var availableSchedules: [TransactionSchedule] {
        TransactionSchedule.allCases.filter { allowsInstallments || $0 != .installments }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("schedule.type.section") {
                    Picker("editor.schedule", selection: $schedule) {
                        ForEach(availableSchedules) { option in
                            Text(titleKey(option)).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(locksScheduleKind)
                }

                if schedule == .recurring {
                    Section {
                        Stepper(value: $recurringCoefficient, in: 1 ... 99) {
                            LabeledContent("schedule.every", value: "\(recurringCoefficient)")
                        }

                        Picker("schedule.unit", selection: $recurringType) {
                            Text("schedule.unit.day").tag(1)
                            Text("schedule.unit.week").tag(2)
                            Text("schedule.unit.month").tag(3)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("schedule.recurring.section")
                    } footer: {
                        Text("schedule.recurring.footer")
                    }
                }

                if schedule == .installments {
                    Section {
                        if !locksScheduleKind {
                            Stepper(value: $installmentCount, in: 2 ... 120) {
                                LabeledContent("editor.installment.count", value: "\(installmentCount)")
                            }
                            .accessibilityIdentifier("installmentCountStepper")
                        }

                        Stepper(value: $intervalMonths, in: 1 ... 24) {
                            LabeledContent(
                                "editor.installment.interval",
                                value: AppFormat.plural("months.count", count: intervalMonths, language: language)
                            )
                        }
                        .accessibilityIdentifier("installmentIntervalStepper")
                    } header: {
                        Text("editor.installment.section")
                    } footer: {
                        Text("editor.installment.remainderNote")
                    }
                }
            }
            .navigationTitle("editor.schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func titleKey(_ schedule: TransactionSchedule) -> LocalizedStringKey {
        switch schedule {
        case .once: "schedule.once"
        case .recurring: "schedule.recurring"
        case .installments: "schedule.installments"
        }
    }
}
