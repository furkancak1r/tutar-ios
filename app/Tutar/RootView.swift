// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import Charts
import CoreData
import SwiftUI

private enum AppTab: Hashable {
    case log
    case analysis
    case budgets
    case settings
}

@MainActor
final class AppLockController: ObservableObject {
    enum State: Equatable {
        case locked
        case authenticating
        case unlocked
    }

    typealias Authenticator = (String) async -> Bool

    @Published private(set) var state: State = .locked

    private let authenticate: Authenticator
    private var scenePhase = ScenePhase.active
    private var didHandleStartup = false
    private var shouldAuthenticateWhenActive = false
    private var requestSequence = 0
    private var activeRequestID: Int?
    private var pendingResult: Bool?

    init(authenticate: @escaping Authenticator = DeviceAuthentication.authenticate) {
        self.authenticate = authenticate
    }

    var isUnlocked: Bool { state == .unlocked }
    var canRetryAuthentication: Bool {
        state == .locked && didHandleStartup && !shouldAuthenticateWhenActive
    }

    func start(enabled: Bool, reason: String, scenePhase: ScenePhase) {
        self.scenePhase = scenePhase
        guard !didHandleStartup else { return }
        didHandleStartup = true

        guard enabled else {
            disable()
            return
        }
        if scenePhase == .active {
            requestAuthentication(reason: reason)
        } else {
            shouldAuthenticateWhenActive = true
        }
    }

    func setEnabled(_ enabled: Bool, reason: String, scenePhase: ScenePhase) {
        self.scenePhase = scenePhase
        guard enabled else {
            disable()
            return
        }

        invalidateRequest()
        state = .locked
        if scenePhase == .active {
            requestAuthentication(reason: reason)
        } else {
            shouldAuthenticateWhenActive = true
        }
    }

    func requestAuthentication(reason: String) {
        guard state == .locked else { return }
        guard scenePhase == .active else {
            shouldAuthenticateWhenActive = true
            return
        }

        requestSequence &+= 1
        let requestID = requestSequence
        activeRequestID = requestID
        pendingResult = nil
        shouldAuthenticateWhenActive = false
        state = .authenticating

        Task { [weak self, authenticate] in
            let success = await authenticate(reason)
            self?.authenticationFinished(success, requestID: requestID)
        }
    }

    func scenePhaseChanged(
        to phase: ScenePhase,
        lockEnabled: Bool,
        reason: String
    ) {
        scenePhase = phase
        guard lockEnabled else {
            if state != .unlocked || activeRequestID != nil { disable() }
            return
        }

        switch phase {
        case .active:
            if let pendingResult {
                apply(pendingResult)
            } else if shouldAuthenticateWhenActive, state == .locked {
                shouldAuthenticateWhenActive = false
                requestAuthentication(reason: reason)
            }
        case .background:
            guard state != .authenticating else { return }
            invalidateRequest()
            state = .locked
            shouldAuthenticateWhenActive = true
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func disable() {
        invalidateRequest()
        shouldAuthenticateWhenActive = false
        state = .unlocked
    }

    private func authenticationFinished(_ success: Bool, requestID: Int) {
        guard activeRequestID == requestID, state == .authenticating else { return }
        if scenePhase == .active {
            apply(success)
        } else {
            pendingResult = success
        }
    }

    private func apply(_ success: Bool) {
        activeRequestID = nil
        pendingResult = nil
        shouldAuthenticateWhenActive = false
        state = success ? .unlocked : .locked
    }

    private func invalidateRequest() {
        requestSequence &+= 1
        activeRequestID = nil
        pendingResult = nil
    }
}

struct RootView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appLockController: AppLockController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appLanguage) private var language
    @AppStorage("biometricLock", store: .tutar) private var biometricLock = false
    @State private var selectedTab = AppTab.log
    @State private var showingEditor = false

    var body: some View {
        ZStack {
            if lockEnabled, !appLockController.isUnlocked {
                LockedView(
                    canRetry: appLockController.canRetryAuthentication,
                    authenticate: requestAuthentication
                )
            } else {
                appContent
            }
        }
        .alert("error.data.title", isPresented: loadErrorBinding) {
            Button("action.ok") { dataController.dismissLoadError() }
        } message: {
            Text("error.data.message")
        }
        .onOpenURL { url in
            if url.scheme == "tutar", url.host == "add", !lockEnabled || appLockController.isUnlocked {
                showingEditor = true
            }
        }
        .task {
            appLockController.start(
                enabled: lockEnabled,
                reason: authenticationReason,
                scenePhase: scenePhase
            )
        }
        .onChange(of: biometricLock) { _, enabled in
            if enabled { showingEditor = false }
            appLockController.setEnabled(
                enabled && lockAllowedInCurrentProcess,
                reason: authenticationReason,
                scenePhase: scenePhase
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                try? dataController.materializeRecurringTransactions()
            }
            if phase == .background, lockEnabled { showingEditor = false }
            appLockController.scenePhaseChanged(
                to: phase,
                lockEnabled: lockEnabled,
                reason: authenticationReason
            )
        }
    }

    private var appContent: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TransactionsView(showingEditor: $showingEditor)
            }
            .tabItem { Label("tab.transactions", systemImage: "list.bullet") }
            .tag(AppTab.log)

            NavigationStack {
                AnalysisView()
            }
            .tabItem { Label("tab.analysis", systemImage: "chart.bar.xaxis") }
            .tag(AppTab.analysis)

            NavigationStack {
                BudgetsView()
            }
            .tabItem { Label("tab.budgets", systemImage: "gauge.with.dots.needle.50percent") }
            .tag(AppTab.budgets)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("tab.settings", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .fullScreenCover(isPresented: $showingEditor) {
            TransactionEditorView()
        }
    }

    private var lockEnabled: Bool {
        biometricLock && lockAllowedInCurrentProcess
    }

    private var lockAllowedInCurrentProcess: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return !arguments.contains("-ui-testing") || arguments.contains("-ui-test-app-lock")
    }

    private var authenticationReason: String {
        AppFormat.localized("settings.lock.reason", language: language)
    }

    private func requestAuthentication() {
        appLockController.requestAuthentication(reason: authenticationReason)
    }

    private var loadErrorBinding: Binding<Bool> {
        Binding(
            get: { dataController.loadError != nil },
            set: { if !$0 { dataController.dismissLoadError() } }
        )
    }
}

private struct LockedView: View {
    let canRetry: Bool
    let authenticate: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 32, weight: .semibold))
                .frame(width: 72, height: 72)
                .background(Color.primary.opacity(0.08), in: Circle())
                .accessibilityHidden(true)

            Text("settings.lock.title")
                .font(.title2.bold())
            Text("settings.lock.message")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Group {
                if canRetry {
                    Button(action: authenticate) {
                        Label("settings.lock.retry", systemImage: "lock.open")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("unlockButton")
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: 280)
            .frame(height: 50)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .contain)
    }
}

struct TransactionsView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Transaction.date, ascending: false)],
        animation: .default
    ) private var transactions: FetchedResults<Transaction>

    @EnvironmentObject private var dataController: DataController
    @Environment(\.appLanguage) private var language
    @AppStorage("currencyCode", store: .tutar) private var preferredCurrency = ""
    @AppStorage("showUpcoming", store: .tutar) private var showUpcoming = true
    @Binding var showingEditor: Bool

    @State private var selectedMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: .now)
    ) ?? .now
    @State private var searchText = ""
    @State private var editing: Transaction?
    @State private var deleting: Transaction?
    @State private var errorMessage = ""

    private var currency: String {
        AppFormat.currencyCode(language: language, preferred: preferredCurrency)
    }

    private var monthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: selectedMonth)
            ?? DateInterval(start: selectedMonth, duration: 2_592_000)
    }

    private var monthTransactions: [Transaction] {
        transactions.filter {
            monthInterval.contains($0.wrappedDate) && matchesSearch($0)
        }
    }

    private var history: [Transaction] {
        monthTransactions.filter { $0.wrappedDate <= Date.now }
    }

    private var upcoming: [Transaction] {
        guard showUpcoming else { return [] }
        return monthTransactions
            .filter { $0.wrappedDate > Date.now }
            .sorted { $0.wrappedDate < $1.wrappedDate }
    }

    private var groupedHistory: [(date: Date, items: [Transaction])] {
        Dictionary(grouping: history) { Calendar.current.startOfDay(for: $0.wrappedDate) }
            .map { ($0.key, $0.value.sorted { $0.wrappedDate > $1.wrappedDate }) }
            .sorted { $0.date > $1.date }
    }

    private var expenses: Double {
        monthTransactions.filter { !$0.income }.reduce(0) { $0 + $1.amount }
    }

    private var income: Double {
        monthTransactions.filter(\.income).reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        List {
            Section {
                MonthSummaryView(
                    month: selectedMonth,
                    expense: expenses,
                    income: income,
                    currency: currency,
                    previous: { moveMonth(-1) },
                    next: { moveMonth(1) }
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if !upcoming.isEmpty {
                Section("transactions.upcoming") {
                    ForEach(upcoming) { transaction in
                        row(transaction)
                    }
                }
            }

            if groupedHistory.isEmpty, upcoming.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("empty.transactions.title", systemImage: "tray")
                    } description: {
                        Text(searchText.isEmpty ? "empty.transactions.message" : "empty.search.message")
                    } actions: {
                        if searchText.isEmpty {
                            Button("action.addTransaction") { showingEditor = true }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .accessibilityIdentifier("emptyTransactionAddButton")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(groupedHistory, id: \.date) { group in
                    Section {
                        ForEach(group.items) { transaction in
                            row(transaction)
                        }
                    } header: {
                        Text(AppFormat.dayHeader(group.date, language: language))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("transactions.title")
        .searchable(text: $searchText, prompt: "transactions.search")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingEditor = true
                } label: {
                    Label("action.addTransaction", systemImage: "plus")
                }
                .accessibilityIdentifier("addTransactionButton")
            }
        }
        .fullScreenCover(item: $editing) {
            TransactionEditorView(transaction: $0)
        }
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
        .alert("error.save.title", isPresented: errorBinding) {
            Button("action.ok") { errorMessage = "" }
        } message: {
            Text(verbatim: errorMessage)
        }
        .refreshable {
            try? dataController.materializeRecurringTransactions()
        }
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })
    }

    private func matchesSearch(_ transaction: Transaction) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return transaction.displayNote(language: language).localizedCaseInsensitiveContains(query)
            || (transaction.category?.displayName(language: language).localizedCaseInsensitiveContains(query) ?? false)
    }

    private func moveMonth(_ value: Int) {
        selectedMonth = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) ?? selectedMonth
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
                .tint(.accentColor)
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

private struct MonthSummaryView: View {
    @Environment(\.appLanguage) private var language
    let month: Date
    let expense: Double
    let income: Double
    let currency: String
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: previous) {
                    Label("month.previous", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("month.previous"))
                .accessibilityIdentifier("previousMonthButton")
                .buttonStyle(.plain)

                Spacer()
                Text(AppFormat.month(month, language: language))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()

                Button(action: next) {
                    Label("month.next", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("month.next"))
                .accessibilityIdentifier("nextMonthButton")
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) { summaryItems }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > 60, abs(horizontal) > abs(vertical) * 1.25 else { return }
                    horizontal < 0 ? next() : previous()
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monthSummary")
        .accessibilityHint(Text("month.swipeHint"))
    }

    @ViewBuilder
    private var summaryItems: some View {
        metric("summary.expense", value: expense, color: .primary)
        metric("summary.income", value: income, color: .green)
        metric("summary.net", value: income - expense, color: income >= expense ? .green : .red)
    }

    private func metric(_ key: LocalizedStringKey, value: Double, color: Color) -> some View {
        let formattedValue = AppFormat.money(value, language: language, currencyCode: currency)
        return LabeledContent {
            Text(formattedValue)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
        } label: {
            Text(key)
                .foregroundStyle(.secondary)
        }
    }
}

struct TransactionRow: View {
    @Environment(\.appLanguage) private var language
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
        HStack(spacing: 10) {
            categoryIcon
            details
            Spacer(minLength: 4)
            amountLabel
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("transactionRow")
        .accessibilityElement(children: .contain)
    }

    private var categoryIcon: some View {
        Text(transaction.category?.wrappedEmoji ?? "•")
            .font(.body)
            .frame(width: 34, height: 34)
            .background(Color(.tertiarySystemFill), in: Circle())
            .accessibilityIdentifier("transactionCategoryIcon")
            .accessibilityHidden(true)
    }

    private var details: some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(transaction.displayNote(language: language)) · \(transaction.category?.displayName(language: language) ?? AppFormat.localized("category.uncategorized", language: language)) · \(AppFormat.date(transaction.wrappedDate, language: language))")
                .font(.body.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
                .accessibilityIdentifier("transactionTitle")
            scheduleIndicator
        }
        .lineLimit(1)
        .layoutPriority(1)
    }

    @ViewBuilder
    private var scheduleIndicator: some View {
        if let label = transaction.installmentLabel {
            badge(label, accessibilityKey: "installment.position")
        } else if transaction.recurringType > 0 {
            Image(systemName: "repeat")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("schedule.recurring"))
        }
    }

    private var amountLabel: some View {
        Text(formattedAmount)
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .foregroundStyle(transaction.income ? Color.green : .primary)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .allowsTightening(true)
            .layoutPriority(2)
            .accessibilityIdentifier("transactionAmount")
            .accessibilityLabel(Text(verbatim: "\(AppFormat.localized(transaction.income ? "accessibility.incomeAmount" : "accessibility.expenseAmount", language: language)): \(formattedAmount)"))
    }

    private func badge(_ text: String, accessibilityKey: LocalizedStringKey) -> some View {
        Text(verbatim: text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .accessibilityLabel(Text(accessibilityKey))
            .accessibilityValue(Text(verbatim: text))
    }
}

private enum AnalysisPeriod: Int, CaseIterable, Identifiable {
    case week
    case month
    case year

    var id: Int { rawValue }
}

private enum AnalysisKind: Int, CaseIterable, Identifiable {
    case expense
    case income

    var id: Int { rawValue }
}

struct AnalysisView: View {
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Transaction.date, ascending: true)])
    private var transactions: FetchedResults<Transaction>
    @Environment(\.appLanguage) private var language
    @AppStorage("currencyCode", store: .tutar) private var preferredCurrency = ""
    @State private var period = AnalysisPeriod.month
    @State private var kind = AnalysisKind.expense

    private var currency: String {
        AppFormat.currencyCode(language: language, preferred: preferredCurrency)
    }

    private var interval: DateInterval {
        let component: Calendar.Component
        switch period {
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        return Calendar.current.dateInterval(of: component, for: .now)
            ?? DateInterval(start: .now, duration: 86_400)
    }

    private var periodTransactions: [Transaction] {
        transactions.filter { interval.contains($0.wrappedDate) }
    }

    private var selectedTransactions: [Transaction] {
        periodTransactions.filter { $0.income == (kind == .income) }
    }

    private var expense: Double {
        periodTransactions.filter { !$0.income }.reduce(0) { $0 + $1.amount }
    }

    private var income: Double {
        periodTransactions.filter(\.income).reduce(0) { $0 + $1.amount }
    }

    private var chartData: [(date: Date, amount: Double)] {
        let component: Calendar.Component = period == .year ? .month : .day
        return Dictionary(grouping: selectedTransactions) {
            Calendar.current.dateInterval(of: component, for: $0.wrappedDate)?.start ?? $0.wrappedDate
        }
        .map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }
        .sorted { $0.date < $1.date }
    }

    private var categoryData: [(name: String, amount: Double)] {
        Dictionary(grouping: selectedTransactions) { $0.category?.objectID }
            .map { _, items in
                (
                    items.first?.category?.displayName(language: language)
                        ?? AppFormat.localized("category.uncategorized", language: language),
                    items.reduce(0) { $0 + $1.amount }
                )
            }
            .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        List {
            Section {
                Picker("analysis.period", selection: $period) {
                    Text("analysis.period.week").tag(AnalysisPeriod.week)
                    Text("analysis.period.month").tag(AnalysisPeriod.month)
                    Text("analysis.period.year").tag(AnalysisPeriod.year)
                }
                .pickerStyle(.segmented)

                LabeledContent("summary.expense", value: AppFormat.money(expense, language: language, currencyCode: currency))
                LabeledContent("summary.income", value: AppFormat.money(income, language: language, currencyCode: currency))
                LabeledContent("summary.net", value: AppFormat.money(income - expense, language: language, currencyCode: currency))
            }

            Section {
                Picker("analysis.kind", selection: $kind) {
                    Text("editor.expense").tag(AnalysisKind.expense)
                    Text("editor.income").tag(AnalysisKind.income)
                }
                .pickerStyle(.segmented)

                if chartData.isEmpty {
                    ContentUnavailableView("empty.analysis.title", systemImage: "chart.bar", description: Text("empty.analysis.message"))
                        .frame(maxWidth: .infinity)
                } else {
                    Chart(chartData, id: \.date) { point in
                        BarMark(
                            x: .value(AppFormat.localized("analysis.dateAxis", language: language), point.date, unit: period == .year ? .month : .day),
                            y: .value(AppFormat.localized("analysis.amountAxis", language: language), point.amount)
                        )
                        .foregroundStyle(kind == .income ? Color.green : Color.accentColor)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: period == .year ? 6 : 7)) { value in
                            AxisValueLabel(format: period == .year ? .dateTime.month(.narrow) : .dateTime.day())
                        }
                    }
                    .frame(height: 220)
                    .accessibilityLabel(Text("analysis.chart"))
                }
            } header: {
                Text("analysis.trend")
            }

            Section("analysis.categories") {
                if categoryData.isEmpty {
                    Text("empty.analysis.message")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(categoryData, id: \.name) { item in
                        LabeledContent {
                            Text(AppFormat.money(item.amount, language: language, currencyCode: currency))
                                .monospacedDigit()
                        } label: {
                            Text(verbatim: item.name)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("analysis.title")
    }
}
