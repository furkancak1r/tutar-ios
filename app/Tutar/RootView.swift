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
        if scenePhase == .active || (success && scenePhase == .inactive) {
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

    @ViewBuilder
    private var appContent: some View {
        if #available(iOS 26.0, *) {
            tabContent.tabBarMinimizeBehavior(.never)
        } else {
            tabContent
        }
    }

    private var tabContent: some View {
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
        .privacySensitive(biometricLock)
    }

    private var lockEnabled: Bool {
        biometricLock && lockAllowedInCurrentProcess
    }

    private var lockAllowedInCurrentProcess: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return !arguments.contains("-ui-testing")
            || arguments.contains("-ui-test-app-lock")
            || arguments.contains("-ui-test-real-app-lock")
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
                .font(.system(size: 36, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 56, height: 56)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("currencyCode", store: .tutar) private var preferredCurrency = ""
    @AppStorage("showUpcoming", store: .tutar) private var showUpcoming = true
    @Binding var showingEditor: Bool

    @State private var selectedMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: .now)
    ) ?? .now
    @State private var monthTransitionEdge: Edge = .trailing
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
                    transactions: monthTransactions,
                    currency: currency,
                    previous: { moveMonth(-1) },
                    next: { moveMonth(1) }
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if !upcoming.isEmpty {
                Section {
                    ForEach(upcoming) { transaction in
                        row(transaction)
                    }
                } header: {
                    Text("transactions.upcoming")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }

            if groupedHistory.isEmpty, upcoming.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("empty.transactions.title", systemImage: "tray")
                    } description: {
                        Text(searchText.isEmpty ? "empty.transactions.message" : "empty.search.message")
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                ForEach(groupedHistory, id: \.date) { group in
                    Section {
                        ForEach(group.items) { transaction in
                            row(transaction)
                        }
                    } header: {
                        Text(AppFormat.dayHeader(group.date, language: language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .headerProminence(.increased)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .id(selectedMonth)
        .transition(.push(from: monthTransitionEdge))
        .navigationTitle("transactions.title")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "transactions.search"
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Spacer()
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color(.systemBackground))
                        .frame(width: 56, height: 56)
                        .background(Color.primary, in: Circle())
                        .overlay {
                            Circle().stroke(Color(.separator), lineWidth: 0.5)
                        }
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("action.addTransaction"))
                .accessibilityIdentifier("addTransactionButton")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .fullScreenCover(item: $editing) {
            TransactionEditorView(transaction: $0)
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

    private func deleteDialogBinding(for transaction: Transaction) -> Binding<Bool> {
        let objectID = transaction.objectID
        return Binding(
            get: { deleting?.objectID == objectID },
            set: { if !$0, deleting?.objectID == objectID { deleting = nil } }
        )
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
        guard let month = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) else { return }
        monthTransitionEdge = value > 0 ? .trailing : .leading
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            selectedMonth = month
        }
    }

    private func row(_ transaction: Transaction) -> some View {
        TransactionRow(transaction: transaction)
            .contentShape(Rectangle())
            .onTapGesture { editing = transaction }
            .tutarDeleteSwipeAction { deleting = transaction }
            .confirmationDialog(
                "delete.title",
                isPresented: deleteDialogBinding(for: transaction),
                titleVisibility: .visible
            ) {
                if transaction.isInstallment {
                    Button("delete.one", role: .destructive) { performDelete(.one) }
                    Button("delete.following", role: .destructive) { performDelete(.thisAndFollowing) }
                } else {
                    Button("action.delete", role: .destructive) { performDelete(.one) }
                }
                Button("action.cancel", role: .cancel) { deleting = nil }
            } message: {
                Text("delete.message")
            }
            .accessibilityAction(named: Text("action.edit")) { editing = transaction }
            .accessibilityAction(named: Text("action.delete")) { deleting = transaction }
    }

    private func performDelete(_ scope: EditScope) {
        guard let deleting else { return }
        self.deleting = nil
        do {
            try dataController.delete(deleting, scope: scope)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MonthSummaryView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var netAmountSize = 42
    let month: Date
    let expense: Double
    let income: Double
    let transactions: [Transaction]
    let currency: String
    let previous: () -> Void
    let next: () -> Void

    private var net: Double { income - expense }

    var body: some View {
        VStack(spacing: 14) {
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
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 4) {
                            Text("summary.netTotal")
                            monthPill
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text("summary.netTotal")
                            monthPill
                        }
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
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

            Text(AppFormat.money(net, language: language, currencyCode: currency))
                .font(
                    dynamicTypeSize.isAccessibilitySize
                        ? .title.monospacedDigit().weight(.medium)
                        : .system(size: netAmountSize, weight: .regular, design: .default).monospacedDigit()
                )
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .allowsTightening(true)
                .accessibilityIdentifier("monthNetAmount")
                .accessibilityLabel(Text("summary.net"))
                .accessibilityValue(Text(verbatim: AppFormat.money(net, language: language, currencyCode: currency)))

            if !dynamicTypeSize.isAccessibilitySize, !transactions.isEmpty {
                trendChart
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    metricRow("summary.expense", value: expense)
                    metricRow("summary.income", value: income)
                }
            } else {
                HStack(spacing: 16) {
                    metric("summary.expense", value: expense, identifier: "monthExpenseAmount")
                    Divider().frame(height: 30)
                    metric("summary.income", value: income, identifier: "monthIncomeAmount")
                }
            }
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

    private var monthPill: some View {
        Text(AppFormat.month(month, language: language))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }

    private var trendChart: some View {
        Chart {
            ForEach(Array(balancePoints.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Balance", point.balance)
                )
                .interpolationMethod(.stepEnd)
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.primary.opacity(0.58))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: trendDomain)
        .frame(height: 44)
        .accessibilityHidden(true)
        .accessibilityIdentifier("monthTrendChart")
    }

    private var balancePoints: [(date: Date, balance: Double)] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let transactionsByDay = Dictionary(grouping: transactions) {
            calendar.startOfDay(for: $0.wrappedDate)
        }
        var runningBalance = 0.0
        var points = [(date: interval.start, balance: runningBalance)]

        for date in transactionsByDay.keys.sorted() {
            runningBalance += transactionsByDay[date, default: []].reduce(0) {
                $0 + ($1.income ? $1.amount : -$1.amount)
            }
            points.append((date: date, balance: runningBalance))
        }

        points.append((date: interval.end.addingTimeInterval(-1), balance: runningBalance))
        return points
    }

    private var trendDomain: ClosedRange<Double> {
        let balances = balancePoints.map(\.balance)
        let low = balances.min() ?? 0
        let high = balances.max() ?? 0
        let spread = max(high - low, max(abs(low), abs(high)) * 0.1, 1)
        let padding = spread * 0.12
        return (low - padding)...(high + padding)
    }

    private func metric(
        _ key: LocalizedStringKey,
        value: Double,
        identifier: String
    ) -> some View {
        let formattedValue = AppFormat.money(value, language: language, currencyCode: currency)
        return VStack(spacing: 3) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formattedValue)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(identifier)
        .accessibilityElement(children: .combine)
    }

    private func metricRow(_ key: LocalizedStringKey, value: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(AppFormat.money(value, language: language, currencyCode: currency))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TransactionRow: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 10) {
                    categoryIcon
                    VStack(alignment: .leading, spacing: 6) {
                        details
                        amountLabel
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    categoryIcon
                    details
                    Spacer(minLength: 4)
                    amountLabel
                }
            }
        }
        .frame(minHeight: 56)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("transactionRow")
    }

    private var categoryIcon: some View {
        Text(transaction.category?.wrappedEmoji ?? "•")
            .font(.title3)
            .frame(width: 28)
            .accessibilityIdentifier("transactionCategoryIcon")
            .accessibilityHidden(true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: primaryText)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .allowsTightening(true)
                .accessibilityIdentifier("transactionTitle")

            HStack(spacing: 5) {
                Text(verbatim: metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .allowsTightening(true)
                    .accessibilityIdentifier("transactionMetadata")
                scheduleIndicator
            }
            .lineLimit(1)
        }
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
            .minimumScaleFactor(0.78)
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
            .foregroundStyle(.secondary)
            .background(Color(.tertiarySystemFill), in: Capsule())
            .accessibilityLabel(Text(accessibilityKey))
            .accessibilityValue(Text(verbatim: text))
    }

    private var primaryText: String {
        let category = transaction.category?.displayName(language: language)
            ?? AppFormat.localized("category.uncategorized", language: language)
        let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return note.isEmpty ? category : note
    }

    private var metadataText: String {
        let category = transaction.category?.displayName(language: language)
            ?? AppFormat.localized("category.uncategorized", language: language)
        let note = transaction.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let date = AppFormat.date(transaction.wrappedDate, language: language)
        return note.isEmpty ? date : "\(category) · \(date)"
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

                HStack(spacing: 8) {
                    summaryMetric("summary.expense", value: expense)
                    Divider().frame(height: 34)
                    summaryMetric("summary.income", value: income)
                    Divider().frame(height: 34)
                    summaryMetric("summary.net", value: income - expense, isNegative: income < expense)
                }
                .padding(.vertical, 4)
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
                            x: .value(AppFormat.localized("analysis.dateAxis", language: language), chartLabel(point.date)),
                            y: .value(AppFormat.localized("analysis.amountAxis", language: language), point.amount),
                            width: .fixed(20)
                        )
                        .foregroundStyle(Color.primary)
                        .cornerRadius(3)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: period == .month ? 5 : 7))
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
                    }
                    .frame(height: 200)
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("analysis.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summaryMetric(_ key: LocalizedStringKey, value: Double, isNegative: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AppFormat.money(value, language: language, currencyCode: currency))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(isNegative ? Color.red : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func chartLabel(_ date: Date) -> String {
        switch period {
        case .week:
            date.formatted(.dateTime.weekday(.abbreviated).locale(language.locale))
        case .month:
            date.formatted(.dateTime.day().locale(language.locale))
        case .year:
            date.formatted(.dateTime.month(.abbreviated).locale(language.locale))
        }
    }
}
