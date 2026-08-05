// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import CoreData
import SwiftUI

private enum BudgetEditorTarget: Identifiable {
    case new
    case category(Budget)
    case overall(MainBudget)

    var id: String {
        switch self {
        case .new: "new"
        case let .category(budget): budget.objectID.uriRepresentation().absoluteString
        case let .overall(budget): budget.objectID.uriRepresentation().absoluteString
        }
    }
}

private enum BudgetDeletion: Identifiable {
    case category(Budget)
    case overall(MainBudget)

    var id: String {
        switch self {
        case let .category(budget): budget.objectID.uriRepresentation().absoluteString
        case let .overall(budget): budget.objectID.uriRepresentation().absoluteString
        }
    }

    var object: NSManagedObject {
        switch self {
        case let .category(budget): budget
        case let .overall(budget): budget
        }
    }
}

struct BudgetsView: View {
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Budget.dateCreated, ascending: true)], animation: .default)
    private var budgets: FetchedResults<Budget>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \MainBudget.dateCreated, ascending: true)], animation: .default)
    private var overallBudgets: FetchedResults<MainBudget>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Transaction.date, ascending: true)], animation: .default)
    private var transactions: FetchedResults<Transaction>

    @EnvironmentObject private var dataController: DataController
    @Environment(\.appLanguage) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("currencyCode", store: .tutar) private var preferredCurrency = ""
    @State private var editorTarget: BudgetEditorTarget?
    @State private var deleting: BudgetDeletion?
    @State private var errorMessage = ""

    private var currency: String {
        AppFormat.currencyCode(language: language, preferred: preferredCurrency)
    }

    var body: some View {
        List {
            Section {
                Label("budgets.explanation", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("budgetExplanation")
            }

            if let overall = overallBudgets.first {
                Section("budgets.overall.section") {
                    row(
                        title: AppFormat.localized("budgets.overall", language: language),
                        emoji: "◎",
                        amount: overall.amount,
                        spent: spent(in: overall.activeInterval),
                        interval: overall.activeInterval,
                        type: Int(overall.type)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { editorTarget = .overall(overall) }
                    .tutarDeleteSwipeAction { deleting = .overall(overall) }
                    .confirmationDialog(
                        "budgets.delete.title",
                        isPresented: deleteBinding(for: .overall(overall)),
                        titleVisibility: .visible
                    ) {
                        Button("action.delete", role: .destructive, action: performDelete)
                        Button("action.cancel", role: .cancel) { deleting = nil }
                    } message: {
                        Text("budgets.delete.message")
                    }
                }
            }

            if !budgets.isEmpty {
                Section("budgets.categories.section") {
                    ForEach(budgets) { budget in
                        row(
                            title: budget.category?.displayName(language: language)
                                ?? AppFormat.localized("category.uncategorized", language: language),
                            emoji: budget.category?.wrappedEmoji ?? "•",
                            amount: budget.amount,
                            spent: spent(in: budget.activeInterval, category: budget.category),
                            interval: budget.activeInterval,
                            type: Int(budget.type)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { editorTarget = .category(budget) }
                        .tutarDeleteSwipeAction { deleting = .category(budget) }
                        .confirmationDialog(
                            "budgets.delete.title",
                            isPresented: deleteBinding(for: .category(budget)),
                            titleVisibility: .visible
                        ) {
                            Button("action.delete", role: .destructive, action: performDelete)
                            Button("action.cancel", role: .cancel) { deleting = nil }
                        } message: {
                            Text("budgets.delete.message")
                        }
                    }
                }
            }

            if budgets.isEmpty, overallBudgets.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("empty.budgets.title", systemImage: "gauge.with.dots.needle.50percent")
                    } description: {
                        Text("empty.budgets.message")
                    } actions: {
                        Button("budgets.add") { editorTarget = .new }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .accessibilityIdentifier("emptyBudgetAddButton")
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("budgets.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorTarget = .new
                } label: {
                    Label("budgets.add", systemImage: "plus")
                }
                .accessibilityIdentifier("addBudgetButton")
            }
        }
        .fullScreenCover(item: $editorTarget) { target in
            switch target {
            case .new:
                BudgetEditorView(hasOverallBudget: !overallBudgets.isEmpty)
            case let .category(budget):
                BudgetEditorView(budget: budget)
            case let .overall(budget):
                BudgetEditorView(overallBudget: budget)
            }
        }
        .alert("error.save.title", isPresented: errorBinding) {
            Button("action.ok") { errorMessage = "" }
        } message: {
            Text(verbatim: errorMessage)
        }
    }

    private func deleteBinding(for target: BudgetDeletion) -> Binding<Bool> {
        Binding(
            get: { deleting?.id == target.id },
            set: { if !$0, deleting?.id == target.id { deleting = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })
    }

    private func row(
        title: String,
        emoji: String,
        amount: Double,
        spent: Double,
        interval: DateInterval,
        type: Int
    ) -> some View {
        let progress = amount > 0 ? spent / amount : 0
        let details = VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(verbatim: emoji)
                    .font(.body)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(budgetPeriodLabel(type))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: "\(AppFormat.localized("budgets.target", language: language)) \(AppFormat.money(amount, language: language, currencyCode: currency))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: "\(AppFormat.localized("budgets.spent.label", language: language)) \(AppFormat.money(spent, language: language, currencyCode: currency))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: "\(AppFormat.localized("budgets.remaining", language: language)) \(AppFormat.money(amount - spent, language: language, currencyCode: currency))")
                .font(.caption)
                .foregroundStyle(spent > amount ? .red : .secondary)
        }

        let gauge = Gauge(value: min(max(progress, 0), 1), in: 0 ... 1) {
            Text("budgets.progress")
        } currentValueLabel: {
            Text(verbatim: "\(Int((progress * 100).rounded()))%")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(width: 48)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(progress > 1 ? .red : .primary)
        .frame(width: 64, height: 64)
        .accessibilityLabel(Text("budgets.progress"))
        .accessibilityValue(Text(verbatim: "\(Int((progress * 100).rounded()))%"))
        .accessibilityIdentifier("budgetGauge")

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    details
                    gauge.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 14) {
                    details
                    Spacer(minLength: 8)
                    gauge
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }

    private func budgetPeriodLabel(_ type: Int) -> LocalizedStringKey {
        switch type {
        case 1: "budget.period.daily"
        case 2: "budget.period.weekly"
        case 3: "budget.period.monthly"
        default: "budget.period.yearly"
        }
    }

    private func spent(in interval: DateInterval, category: Category? = nil) -> Double {
        transactions.filter {
            !$0.income
                && interval.contains($0.wrappedDate)
                && (category == nil || $0.category == category)
        }
        .reduce(0) { $0 + $1.amount }
    }

    private func performDelete() {
        guard let deleting else { return }
        self.deleting = nil
        do {
            try dataController.deleteBudget(deleting.object)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum BudgetKind: Int, CaseIterable, Identifiable {
    case overall
    case category

    var id: Int { rawValue }
}

private struct BudgetEditorView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.order, ascending: true)],
        predicate: NSPredicate(format: "income == NO"),
        animation: .default
    ) private var categories: FetchedResults<Category>
    @FetchRequest(sortDescriptors: []) private var existingBudgets: FetchedResults<Budget>

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @AppStorage("currencyCode", store: .tutar) private var preferredCurrency = ""

    let budget: Budget?
    let overallBudget: MainBudget?
    let hasOverallBudget: Bool

    @State private var kind: BudgetKind
    @State private var category: Category?
    @State private var amountEntry: MoneyEntry
    @State private var type: Int
    @State private var startDate: Date
    @State private var errorKey: String?

    private var isEditing: Bool { budget != nil || overallBudget != nil }

    private var availableCategories: [Category] {
        categories.filter { candidate in
            existingBudgets.allSatisfy { $0.category != candidate || $0 == budget }
        }
    }

    private var amountText: String {
        AppFormat.money(
            Double(amountEntry.minorUnits) / 100,
            language: language,
            currencyCode: AppFormat.currencyCode(language: language, preferred: preferredCurrency)
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 22) {
                        if !isEditing {
                            Picker("budgets.kind", selection: $kind) {
                                if !hasOverallBudget {
                                    Text("budgets.overall").tag(BudgetKind.overall)
                                }
                                Text("budgets.category").tag(BudgetKind.category)
                            }
                            .pickerStyle(.segmented)

                            Label("budgets.editorHint", systemImage: "info.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(spacing: 8) {
                            Text(amountText)
                                .font(.largeTitle.weight(.semibold).monospacedDigit())
                                .minimumScaleFactor(0.45)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel(Text("editor.amount"))
                                .accessibilityValue(Text(verbatim: amountText))
                                .accessibilityIdentifier("budgetAmountDisplay")
                            AmountDeleteButton(entry: $amountEntry)
                        }

                        VStack(spacing: 0) {
                            if kind == .category {
                                LabeledContent("editor.category") {
                                    Picker("editor.category", selection: $category) {
                                        ForEach(availableCategories) { item in
                                            Text(verbatim: "\(item.wrappedEmoji) \(item.displayName(language: language))")
                                                .tag(Optional(item))
                                        }
                                    }
                                    .labelsHidden()
                                }
                                .padding(.vertical, 10)
                                Divider()
                            }

                            LabeledContent("budgets.period") {
                                Picker("budgets.period", selection: $type) {
                                    Text("budget.period.daily").tag(1)
                                    Text("budget.period.weekly").tag(2)
                                    Text("budget.period.monthly").tag(3)
                                    Text("budget.period.yearly").tag(4)
                                }
                                .labelsHidden()
                            }
                            .padding(.vertical, 10)

                            Divider()

                            LabeledContent("budgets.startDate") {
                                AutoDismissDatePicker(selection: $startDate, title: "budgets.startDate", identifier: "budgetDatePicker")
                            }
                            .padding(.vertical, 10)
                        }
                        .padding(.horizontal, 14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        if kind == .category, availableCategories.isEmpty {
                            Label("budgets.error.noCategory", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let errorKey {
                            Label(AppFormat.localized(errorKey, language: language), systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity)
                }

                AmountKeypad(entry: $amountEntry, submit: save)
            }
            .background(Color(.systemBackground))
            .navigationTitle(isEditing ? "budgets.edit.title" : "budgets.new.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save", action: save)
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if category == nil { category = availableCategories.first }
        }
    }

    init(hasOverallBudget: Bool = false, budget: Budget? = nil, overallBudget: MainBudget? = nil) {
        self.hasOverallBudget = hasOverallBudget
        self.budget = budget
        self.overallBudget = overallBudget

        let rawMode = UserDefaults.tutar.object(forKey: "numberEntryType") as? Int ?? 1
        let mode = MoneyEntry.Mode(rawValue: rawMode) ?? .automaticCents
        let amount = budget?.amount ?? overallBudget?.amount ?? 0

        _kind = State(initialValue: budget != nil || (budget == nil && overallBudget == nil && hasOverallBudget) ? .category : .overall)
        _category = State(initialValue: budget?.category)
        _amountEntry = State(initialValue: MoneyEntry(minorUnits: Int64((amount * 100).rounded()), mode: mode))
        _type = State(initialValue: max(Int(budget?.type ?? overallBudget?.type ?? 3), 1))
        _startDate = State(initialValue: budget?.startDate ?? overallBudget?.startDate ?? .now)
    }

    private func save() {
        guard amountEntry.minorUnits > 0 else {
            errorKey = "editor.error.amount"
            return
        }

        do {
            if kind == .overall {
                try dataController.saveOverallBudget(
                    overallBudget,
                    amountMinorUnits: amountEntry.minorUnits,
                    type: type,
                    startDate: startDate
                )
            } else {
                guard let category else {
                    errorKey = "editor.error.category"
                    return
                }
                try dataController.saveCategoryBudget(
                    budget,
                    category: category,
                    amountMinorUnits: amountEntry.minorUnits,
                    type: type,
                    startDate: startDate
                )
            }
            dismiss()
        } catch BudgetError.duplicateCategory {
            errorKey = "budgets.error.duplicateCategory"
        } catch BudgetError.duplicateOverall {
            errorKey = "budgets.error.duplicateOverall"
        } catch {
            errorKey = "editor.error.save"
        }
    }
}

private extension Budget {
    var activeInterval: DateInterval {
        budgetInterval(start: startDate ?? .now, type: Int(type))
    }
}

private extension MainBudget {
    var activeInterval: DateInterval {
        budgetInterval(start: startDate ?? .now, type: Int(type))
    }
}

private func budgetInterval(start originalStart: Date, type: Int, reference: Date = .now) -> DateInterval {
    let calendar = Calendar.current
    let component: Calendar.Component
    let value: Int
    switch type {
    case 1: component = .day; value = 1
    case 2: component = .day; value = 7
    case 3: component = .month; value = 1
    default: component = .year; value = 1
    }

    var start = originalStart
    var end = calendar.date(byAdding: component, value: value, to: start) ?? start.addingTimeInterval(86_400)
    // ponytail: linear by elapsed budget periods; switch to calendar-component jumps if multi-decade budgets become common.
    while end <= reference {
        start = end
        end = calendar.date(byAdding: component, value: value, to: start) ?? start.addingTimeInterval(86_400)
    }
    return DateInterval(start: start, end: end)
}
