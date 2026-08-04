// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import Charts
import CoreData
import SwiftUI

private enum AppTab: Hashable {
    case overview
    case transactions
    case installments
    case analysis
    case settings
}

struct RootView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.appLanguage) private var language
    @State private var selectedTab = AppTab.overview
    @State private var showingEditor = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                NavigationStack { DashboardView(showingEditor: $showingEditor) }
                    .tabItem { Label("tab.overview", systemImage: "rectangle.3.group.fill") }
                    .tag(AppTab.overview)

                NavigationStack { TransactionsView() }
                    .tabItem { Label("tab.transactions", systemImage: "list.bullet.rectangle.portrait") }
                    .tag(AppTab.transactions)

                NavigationStack { InstallmentsView() }
                    .tabItem { Label("tab.installments", systemImage: "square.stack.3d.up.fill") }
                    .tag(AppTab.installments)

                NavigationStack { AnalysisView() }
                    .tabItem { Label("tab.analysis", systemImage: "chart.bar.xaxis") }
                    .tag(AppTab.analysis)

                NavigationStack { SettingsView() }
                    .tabItem { Label("tab.settings", systemImage: "gearshape.fill") }
                    .tag(AppTab.settings)
            }

            if selectedTab != .settings {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Color.tutarCoral, in: Circle())
                        .shadow(color: .tutarCoral.opacity(0.35), radius: 14, y: 8)
                }
                .accessibilityLabel(Text("action.addTransaction"))
                .accessibilityIdentifier("addTransactionButton")
                .padding(.trailing, 20)
                .padding(.bottom, 72)
            }
        }
        .fontDesign(.rounded)
        .sheet(isPresented: $showingEditor) {
            TransactionEditorView()
        }
        .alert("error.data.title", isPresented: loadErrorBinding) {
            Button("action.ok") { dataController.dismissLoadError() }
        } message: {
            Text("error.data.message")
        }
        .onOpenURL { url in
            if url.scheme == "tutar", url.host == "add" {
                showingEditor = true
            }
        }
    }

    private var loadErrorBinding: Binding<Bool> {
        Binding(
            get: { dataController.loadError != nil },
            set: { if !$0 { dataController.dismissLoadError() } }
        )
    }
}

struct DashboardView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)],
        animation: .default
    ) private var transactions: FetchedResults<Transaction>
    @Environment(\.appLanguage) private var language
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("currencyCode", store: .tutar) private var preferredCurrency = ""
    @Binding var showingEditor: Bool

    private var currency: String {
        AppFormat.currencyCode(language: language, preferred: preferredCurrency)
    }

    private var monthTransactions: [Transaction] {
        let calendar = Calendar.current
        guard
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date.now)),
            let end = calendar.date(byAdding: .month, value: 1, to: start)
        else { return [] }
        return transactions.filter { $0.wrappedDate >= start && $0.wrappedDate < end }
    }

    private var expenses: Double {
        monthTransactions.filter { !$0.income }.reduce(0) { $0 + $1.amount }
    }

    private var income: Double {
        monthTransactions.filter(\.income).reduce(0) { $0 + $1.amount }
    }

    private var upcoming: [Transaction] {
        transactions
            .filter { $0.isInstallment && $0.wrappedDate > Date.now }
            .sorted { $0.wrappedDate < $1.wrappedDate }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("dashboard.monthEyebrow")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text(AppFormat.month(.now, language: language))
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(AppFormat.money(expenses, language: language, currencyCode: currency))
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(.white)
                        .accessibilityLabel(Text("dashboard.monthExpense"))
                        .accessibilityValue(Text(verbatim: AppFormat.money(expenses, language: language, currencyCode: currency)))

                    HStack(spacing: 18) {
                        Label {
                            Text(AppFormat.money(income, language: language, currencyCode: currency))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        } icon: {
                            Image(systemName: "arrow.down.left")
                        }
                        Label {
                            Text(AppFormat.money(max(income - expenses, 0), language: language, currencyCode: currency))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        } icon: {
                            Image(systemName: "equal")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .background(
                    LinearGradient(
                        colors: [.tutarNavy, .tutarNavy.opacity(0.86), .tutarCoral.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous)
                )

                if let next = upcoming.first {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("dashboard.nextInstallment", systemImage: "calendar.badge.clock")
                            .font(.headline)
                            .foregroundStyle(colorScheme == .dark ? Color.tutarMint : Color.tutarNavy)
                        TransactionRow(transaction: next)
                    }
                    .padding(18)
                    .background(colorScheme == .dark ? Color.tutarNavy : Color.tutarCream, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityElement(children: .contain)
                }

                HStack {
                    Text("dashboard.recent")
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if transactions.isEmpty == false {
                        Text(AppFormat.localized("dashboard.currentMonthOnly", language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if monthTransactions.isEmpty {
                    ContentUnavailableView {
                        Label("empty.transactions.title", systemImage: "tray")
                    } description: {
                        Text("empty.transactions.message")
                    } actions: {
                        Button("action.addTransaction") { showingEditor = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ForEach(Array(monthTransactions.prefix(5))) { transaction in
                        TransactionRow(transaction: transaction)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("dashboard.title")
    }
}

struct TransactionsView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)],
        animation: .default
    ) private var transactions: FetchedResults<Transaction>
    @EnvironmentObject private var dataController: DataController
    @State private var editing: Transaction?
    @State private var deleting: Transaction?
    @State private var errorMessage = ""

    private var posted: [Transaction] {
        transactions.filter { !$0.isInstallment || $0.wrappedDate <= Date.now }
    }

    private var future: [Transaction] {
        transactions
            .filter { $0.isInstallment && $0.wrappedDate > Date.now }
            .sorted { $0.wrappedDate < $1.wrappedDate }
    }

    var body: some View {
        List {
            if future.isEmpty == false {
                Section("transactions.futureInstallments") {
                    ForEach(future) { transaction in row(transaction) }
                }
            }

            Section("transactions.history") {
                if posted.isEmpty {
                    Text("empty.transactions.message")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(posted) { transaction in row(transaction) }
                }
            }
        }
        .navigationTitle("transactions.title")
        .sheet(item: $editing) { TransactionEditorView(transaction: $0) }
        .confirmationDialog("delete.title", isPresented: deleteDialogBinding, titleVisibility: .visible) {
            if deleting?.isInstallment == true {
                Button("delete.one", role: .destructive) { performDelete(.one) }
                Button("delete.following", role: .destructive) { performDelete(.thisAndFollowing) }
            } else {
                Button("action.delete", role: .destructive) { performDelete(.one) }
            }
            Button("action.cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("delete.message")
        }
        .alert("error.save.title", isPresented: .constant(errorMessage.isEmpty == false)) {
            Button("action.ok") { errorMessage = "" }
        } message: {
            Text(verbatim: errorMessage)
        }
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private func row(_ transaction: Transaction) -> some View {
        TransactionRow(transaction: transaction)
            .contentShape(Rectangle())
            .onTapGesture { editing = transaction }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { deleting = transaction } label: {
                    Label("action.delete", systemImage: "trash")
                }
                Button { editing = transaction } label: {
                    Label("action.edit", systemImage: "pencil")
                }
                .tint(.tutarMint)
            }
            .accessibilityAction(named: Text("action.edit")) { editing = transaction }
            .accessibilityAction(named: Text("action.delete")) { deleting = transaction }
    }

    private func performDelete(_ scope: EditScope) {
        guard let deleting else { return }
        do {
            try dataController.delete(deleting, scope: scope)
        } catch {
            errorMessage = error.localizedDescription
        }
        self.deleting = nil
    }
}

struct TransactionRow: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("currencyCode", store: .tutar) private var preferredCurrency = ""
    let transaction: Transaction

    private var formattedAmount: String {
        AppFormat.money(
            transaction.income ? transaction.amount : -transaction.amount,
            language: language,
            currencyCode: AppFormat.currencyCode(language: language, preferred: preferredCurrency)
        )
    }

    var body: some View {
        HStack(spacing: 13) {
            Text(verbatim: transaction.category?.wrappedEmoji ?? "•")
                .font(.title3)
                .frame(width: 42, height: 42)
                .background(Color.tutarMint.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: transaction.displayNote(language: language))
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    if let label = transaction.installmentLabel {
                        Text(verbatim: label)
                            .font(.caption2.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .foregroundStyle(colorScheme == .dark ? Color.tutarMint : Color.tutarNavy)
                            .background(Color.tutarMint.opacity(colorScheme == .dark ? 0.14 : 0.25), in: Capsule())
                            .accessibilityLabel(Text("installment.position"))
                            .accessibilityValue(Text(verbatim: label))
                    }
                }
                Text(verbatim: "\(transaction.category?.displayName(language: language) ?? AppFormat.localized("category.uncategorized", language: language)) · \(AppFormat.date(transaction.wrappedDate, language: language))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(formattedAmount)
            .font(.subheadline.monospacedDigit().weight(.bold))
            .foregroundStyle(transaction.income ? Color.tutarMint : .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .accessibilityLabel(Text(transaction.income ? "accessibility.incomeAmount" : "accessibility.expenseAmount"))
            .accessibilityValue(Text(verbatim: formattedAmount))
        }
        .padding(.vertical, 5)
    }
}

struct AnalysisView: View {
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Transaction.date, ascending: true)])
    private var transactions: FetchedResults<Transaction>
    @Environment(\.appLanguage) private var language
    @AppStorage("currencyCode", store: .tutar) private var preferredCurrency = ""

    private var monthlyData: [(date: Date, amount: Double)] {
        let calendar = Calendar.current
        guard let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date.now)) else {
            return []
        }
        return (-5 ... 0).compactMap { offset in
            guard
                let start = calendar.date(byAdding: .month, value: offset, to: currentMonth),
                let end = calendar.date(byAdding: .month, value: 1, to: start)
            else { return nil }
            let total = transactions
                .filter { !$0.income && $0.wrappedDate >= start && $0.wrappedDate < end }
                .reduce(0) { $0 + $1.amount }
            return (start, total)
        }
    }

    private var categoryData: [(name: String, amount: Double)] {
        let calendar = Calendar.current
        guard
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date.now)),
            let end = calendar.date(byAdding: .month, value: 1, to: start)
        else { return [] }

        let grouped = Dictionary(grouping: transactions.filter {
            !$0.income && $0.wrappedDate >= start && $0.wrappedDate < end
        }) { $0.category?.objectID }

        return grouped.map { _, items in
            (items.first?.category?.displayName(language: language) ?? AppFormat.localized("category.uncategorized", language: language), items.reduce(0) { $0 + $1.amount })
        }.sorted { $0.amount > $1.amount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("analysis.sixMonths")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Chart(monthlyData, id: \.date) { point in
                    BarMark(
                        x: .value(AppFormat.localized("analysis.monthAxis", language: language), point.date, unit: .month),
                        y: .value(AppFormat.localized("analysis.amountAxis", language: language), point.amount)
                    )
                    .foregroundStyle(Color.tutarCoral.gradient)
                    .cornerRadius(6)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                    }
                }
                .frame(height: 220)
                .accessibilityLabel(Text("analysis.sixMonths"))

                Text("analysis.categories")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                if categoryData.isEmpty {
                    ContentUnavailableView("empty.analysis.title", systemImage: "chart.bar", description: Text("empty.analysis.message"))
                } else {
                    ForEach(categoryData, id: \.name) { item in
                        HStack {
                            Text(verbatim: item.name)
                            Spacer()
                            Text(AppFormat.money(
                                item.amount,
                                language: language,
                                currencyCode: AppFormat.currencyCode(language: language, preferred: preferredCurrency)
                            ))
                            .monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("analysis.title")
    }
}
