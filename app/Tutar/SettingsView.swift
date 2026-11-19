// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    let showOnboarding: () -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.appLanguage) private var language
    @AppStorage("appLanguage", store: .tutar) private var languageRaw = AppLanguage.system.rawValue
    @AppStorage("appearance", store: .tutar) private var appearance = 0
    @AppStorage("currencyCode", store: .tutar) private var currencyCode = ""
    @AppStorage("numberEntryType", store: .tutar) private var numberEntryType = 2
    @AppStorage("haptics", store: .tutar) private var haptics = true
    @AppStorage("showSuggestions", store: .tutar) private var showSuggestions = true
    @AppStorage("showUpcoming", store: .tutar) private var showUpcoming = true
    @AppStorage("biometricLock", store: .tutar) private var biometricLock = false
    @AppStorage("icloudSync", store: .tutar) private var iCloudSync = true
    @AppStorage("dailyReminder", store: .tutar) private var dailyReminder = false
    @AppStorage("reminderHour", store: .tutar) private var reminderHour = 20
    var periodSettings = MonthPeriodSettings()

    @State private var showingDeleteConfirmation = false

    private var periodSummary: String {
        periodSettings.mode == 1
            ? "\(AppFormat.localized("period.mode.custom", language: language)) · \(periodSettings.cutoffDay)"
            : AppFormat.localized("period.mode.calendar", language: language)
    }
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument: TransferDocument?
    @State private var exportContentType = UTType.json
    @State private var exportFilename = "Tutar"
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        Form {
            Section {
                Picker("settings.language", selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.titleKey).tag(option.rawValue)
                    }
                }
                .accessibilityIdentifier("languagePicker")
            } header: {
                Text("settings.language.section")
            } footer: {
                Text("settings.language.footer")
            }

            Section("settings.appearance.section") {
                Picker("settings.appearance", selection: $appearance) {
                    Text("appearance.system").tag(0)
                    Text("appearance.light").tag(1)
                    Text("appearance.dark").tag(2)
                }
            }

            Section("settings.entry.section") {
                Picker("settings.numberEntry", selection: $numberEntryType) {
                    Text("settings.numberEntry.automatic").tag(1)
                    Text("settings.numberEntry.decimal").tag(2)
                }
                Toggle("settings.haptics", isOn: $haptics)
                    .tint(Color(.systemGray))
                    .accessibilityIdentifier("hapticsToggle")
                Toggle("settings.suggestions", isOn: $showSuggestions)
                    .tint(Color(.systemGray))
                Toggle("settings.upcoming", isOn: $showUpcoming)
                    .tint(Color(.systemGray))
            }

            Section {
                NavigationLink {
                    CurrencyPickerView(selection: $currencyCode)
                } label: {
                    HStack {
                        Text("settings.currency")
                        Spacer()
                        Text(verbatim: AppFormat.currencyCode(language: language, preferred: currencyCode))
                            .font(.body.monospaced())
                            .foregroundStyle(.primary)
                    }
                }
                .accessibilityIdentifier("currencyPicker")
                NavigationLink {
                    MonthPeriodSettingsView()
                } label: {
                    LabeledContent("period.title") {
                        Text(verbatim: periodSummary)
                    }
                }
                .accessibilityIdentifier("monthPeriodSettingsButton")
            } header: {
                Text("settings.money.section")
            } footer: {
                Text("settings.currency.footer")
            }

            Section {
                Toggle(isOn: biometricBinding) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("settings.lock")
                        Text("settings.lock.detail")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(Color(.systemGray))
                .accessibilityIdentifier("biometricLockToggle")
                Toggle("settings.icloud", isOn: $iCloudSync)
                    .tint(Color(.systemGray))
                    .accessibilityIdentifier("icloudToggle")
            } header: {
                Text("settings.privacy.section")
            } footer: {
                Text("settings.privacy.footer")
            }

            Section("settings.data.section") {
                NavigationLink {
                    CategoriesView()
                } label: {
                    Label("settings.categories", systemImage: "square.grid.2x2")
                }

                Button {
                    showingImporter = true
                } label: {
                    Label("settings.import", systemImage: "square.and.arrow.down")
                }

                Button {
                    prepareExport(type: .commaSeparatedText)
                } label: {
                    Label("settings.export.csv", systemImage: "tablecells")
                }

                Button {
                    prepareExport(type: .json)
                } label: {
                    Label("settings.export.backup", systemImage: "archivebox")
                }
            }

            Section("settings.reminder.section") {
                Toggle("settings.reminder", isOn: $dailyReminder)
                    .tint(Color(.systemGray))
                    .onChange(of: dailyReminder) { _, enabled in
                        Task { await updateReminder(enabled: enabled) }
                    }

                if dailyReminder {
                    Picker("settings.reminder.hour", selection: $reminderHour) {
                        ForEach(0 ..< 24, id: \.self) { hour in
                            Text(DateComponents(calendar: .current, hour: hour).date?.formatted(
                                .dateTime.hour().locale(language.locale)
                            ) ?? "\(hour)")
                            .tag(hour)
                        }
                    }
                    .onChange(of: reminderHour) { _, _ in
                        Task { await updateReminder(enabled: true) }
                    }
                }
            }

            Section("settings.info.section") {
                Button(action: showOnboarding) {
                    Label("settings.onboarding", systemImage: "sparkles")
                }
                .accessibilityIdentifier("showOnboardingButton")

                NavigationLink("settings.about") { AboutView() }

                Link(destination: AppConstants.supportURL) {
                    Label("settings.support", systemImage: "questionmark.circle")
                }

                Link(destination: AppConstants.privacyURL) {
                    Label("settings.privacy", systemImage: "hand.raised")
                }

                if let emailURL = URL(string: "mailto:\(AppConstants.feedbackEmail)") {
                    Link(destination: emailURL) {
                        Label("settings.feedback", systemImage: "envelope")
                    }
                }
            }

            Section {
                Button("settings.erase", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } footer: {
                Text("settings.erase.footer")
            }
        }
        .headerProminence(.increased)
        .navigationTitle("settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .confirmationDialog("settings.erase.confirmTitle", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("settings.erase.confirm", role: .destructive) { eraseData() }
            Button("action.cancel", role: .cancel) {}
        } message: {
            Text("settings.erase.confirmMessage")
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json, .commaSeparatedText, .plainText]
        ) { result in
            importFile(result)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            if case let .failure(error) = result {
                showAlert(titleKey: "data.export.error.title", message: error.localizedDescription)
            }
        }
        .alert(Text(verbatim: alertTitle), isPresented: alertBinding) {
            Button("action.ok") {
                alertTitle = ""
                alertMessage = ""
            }
        } message: {
            Text(verbatim: alertMessage)
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { !alertTitle.isEmpty },
            set: {
                if !$0 {
                    alertTitle = ""
                    alertMessage = ""
                }
            }
        )
    }

    private var biometricBinding: Binding<Bool> {
        Binding(
            get: { biometricLock },
            set: { enabled in
                if !enabled {
                    biometricLock = false
                } else if DeviceAuthentication.isAvailable {
                    biometricLock = true
                } else {
                    showAlert(
                        titleKey: "settings.lock.unavailable.title",
                        message: AppFormat.localized("settings.lock.unavailable.message", language: language)
                    )
                }
            }
        )
    }

    private func prepareExport(type: UTType) {
        do {
            exportContentType = type
            exportFilename = type == .json
                ? "Tutar-\(Self.filenameDate.string(from: .now))"
                : "Tutar-Transactions-\(Self.filenameDate.string(from: .now))"
            exportDocument = TransferDocument(
                data: type == .json
                    ? try dataController.exportBackup()
                    : try dataController.exportCSV(language: language)
            )
            showingExporter = true
        } catch {
            showAlert(titleKey: "data.export.error.title", message: error.localizedDescription)
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 50 * 1_024 * 1_024 {
                throw DataTransferError.fileTooLarge
            }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let summary = try dataController.importData(
                data,
                fileExtension: url.pathExtension,
                language: language
            )
            showAlert(
                titleKey: "data.import.success.title",
                message: AppFormat.format(
                    "data.import.success.message",
                    language: language,
                    summary.imported,
                    summary.skipped
                )
            )
        } catch {
            showAlert(
                titleKey: "data.import.error.title",
                message: importErrorMessage(error)
            )
        }
    }

    private func importErrorMessage(_ error: Error) -> String {
        switch error as? DataTransferError {
        case let .invalidRow(row):
            AppFormat.format("data.import.error.row", language: language, row)
        case .missingRequiredColumn:
            AppFormat.localized("data.import.error.columns", language: language)
        case .unsupportedVersion:
            AppFormat.localized("data.import.error.version", language: language)
        case .fileTooLarge:
            AppFormat.localized("data.import.error.size", language: language)
        case .invalidFormat, .unreadableFile:
            AppFormat.localized("data.import.error.format", language: language)
        case nil:
            error.localizedDescription
        }
    }

    private func showAlert(titleKey: String, message: String) {
        alertTitle = AppFormat.localized(titleKey, language: language)
        alertMessage = message
    }

    private func updateReminder(enabled: Bool) async {
        do {
            if enabled {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    await MainActor.run { dailyReminder = false }
                    return
                }
                try await ReminderScheduler.schedule(hour: reminderHour, language: language)
            } else {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [ReminderScheduler.identifier])
            }
        } catch {
            await MainActor.run {
                dailyReminder = false
                showAlert(titleKey: "error.save.title", message: error.localizedDescription)
            }
        }
    }

    private func eraseData() {
        do {
            try dataController.deleteAll()
        } catch {
            showAlert(titleKey: "error.save.title", message: error.localizedDescription)
        }
    }

    private static let filenameDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct CurrencyPickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @State private var searchText = ""

    private var codes: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return AppFormat.currencyCodes }
        return AppFormat.currencyCodes.filter {
            $0.localizedCaseInsensitiveContains(query)
                || AppFormat.currencyName($0, language: language).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            Button {
                selection = ""
                dismiss()
            } label: {
                currencyRow(
                    code: AppFormat.currencyCode(language: language, preferred: ""),
                    name: AppFormat.localized("settings.currency.automatic", language: language),
                    selected: selection.isEmpty
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("currencyOption-automatic")

            ForEach(codes, id: \.self) { code in
                Button {
                    selection = code
                    dismiss()
                } label: {
                    currencyRow(
                        code: code,
                        name: AppFormat.currencyName(code, language: language),
                        selected: selection == code
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("currencyOption-\(code)")
            }
        }
        .navigationTitle("settings.currency")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "settings.currency.search"
        )
    }

    private func currencyRow(code: String, name: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: code)
                .font(.body.monospaced().weight(.semibold))
                .frame(width: 42, alignment: .leading)
            Text(verbatim: name)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Month period settings: "1st to 1st" or a statement cut-off day with per-month overrides.
/// A change writes only settings. It does not change a record.
struct MonthPeriodSettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.appLanguage) private var language
    var periodSettings = MonthPeriodSettings()
    @State private var overrideMonth: String?
    @State private var overrideDay = MonthPeriods.defaultCutoffDay

    private var periods: MonthPeriods { periodSettings.periods() }

    private var overrides: [(key: String, month: Date, day: Int)] {
        periods.overrides
            .compactMap { key, day in periods.month(forKey: key).map { (key, $0, day) } }
            .sorted { $0.month < $1.month }
    }

    /// Period months from 12 months before to 12 months after the current period month.
    private var selectableMonths: [String] {
        let current = periods.month(containing: .now)
        return (-12 ... 12).compactMap { offset in
            periods.calendar.date(byAdding: .month, value: offset, to: current).map(periods.key(for:))
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("period.title", selection: periodSettings.$mode) {
                    Text("period.mode.calendar").tag(0)
                    Text("period.mode.custom").tag(1)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("periodModePicker")
            } footer: {
                Text("period.mode.footer")
            }

            if periods.isCustom {
                Section {
                    Picker("period.cutoff", selection: periodSettings.$cutoffDay) {
                        ForEach(1 ... 31, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                    }
                    .accessibilityIdentifier("periodCutoffDayPicker")
                    LabeledContent("period.current") {
                        let current = periods.interval(containing: .now)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: AppFormat.month(periods.month(containing: .now), language: language))
                            Text(verbatim: AppFormat.periodRange(current, language: language, calendar: periods.calendar))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("periodCurrentRange")
                } footer: {
                    Text("period.cutoff.footer")
                }

                Section {
                    Picker("period.override.month", selection: overrideMonthBinding) {
                        ForEach(selectableMonths, id: \.self) { key in
                            Text(verbatim: periods.month(forKey: key).map { AppFormat.month($0, language: language) } ?? key)
                                .tag(key)
                        }
                    }
                    .accessibilityIdentifier("periodOverrideMonthPicker")
                    Picker("period.override.day", selection: $overrideDay) {
                        ForEach(1 ... 31, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                    }
                    .accessibilityIdentifier("periodOverrideDayPicker")
                    Button {
                        setOverride(overrideMonthBinding.wrappedValue, day: overrideDay)
                    } label: {
                        Label("period.override.add", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("periodOverrideAddButton")

                    if overrides.isEmpty {
                        Text("period.overrides.empty")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(overrides, id: \.key) { item in
                        HStack {
                            Text(verbatim: "\(AppFormat.month(item.month, language: language)) · \(item.day)")
                                .monospacedDigit()
                                .accessibilityIdentifier("periodOverrideRow")
                            Spacer()
                            Button(role: .destructive) {
                                setOverride(item.key, day: nil)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("period.override.remove"))
                            .accessibilityIdentifier("periodOverrideRemoveButton")
                        }
                    }
                } header: {
                    Text("period.overrides.section")
                } footer: {
                    Text("period.overrides.footer")
                }
            }
        }
        .navigationTitle("period.title")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .onChange(of: periods) { _, _ in
            PeriodSettingsSync.push()
            dataController.updateWidgetSnapshot()
        }
    }

    private var overrideMonthBinding: Binding<String> {
        Binding(
            get: { overrideMonth ?? periods.key(for: periods.month(containing: .now)) },
            set: { overrideMonth = $0 }
        )
    }

    private func setOverride(_ key: String, day: Int?) {
        var values = periods.overrides
        values[key] = day
        periodSettings.overridesJSON = MonthPeriods.encode(values)
    }
}

/// Syncs the month period settings between devices with iCloud key-value storage.
/// The App Group copy stays the source for the app, the widget and offline use.
@MainActor
enum PeriodSettingsSync {
    private static var observer: NSObjectProtocol?

    /// Off in tests and when the user turned off iCloud sync.
    private static var isEnabled: Bool {
        !DataController.isTesting && UserDefaults.tutar.bool(forKey: "icloudSync")
    }

    static func start() {
        guard observer == nil, isEnabled else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                pull()
                DataController.shared.updateWidgetSnapshot()
            }
        }
        cloud.synchronize()
        pull()
    }

    static func push() {
        guard isEnabled else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        for key in MonthPeriods.Keys.all {
            let value = UserDefaults.tutar.object(forKey: key)
            if (cloud.object(forKey: key) as? NSObject) != (value as? NSObject) {
                cloud.set(value, forKey: key)
            }
        }
    }

    /// Copies only valid values: the store holds data from other devices.
    private static func pull() {
        guard isEnabled else { return }
        let cloud = NSUbiquitousKeyValueStore.default
        let defaults = UserDefaults.tutar
        if let mode = cloud.object(forKey: MonthPeriods.Keys.mode) as? Int, [0, 1].contains(mode) {
            defaults.set(mode, forKey: MonthPeriods.Keys.mode)
        }
        if let day = cloud.object(forKey: MonthPeriods.Keys.cutoffDay) as? Int, (1 ... 31).contains(day) {
            defaults.set(day, forKey: MonthPeriods.Keys.cutoffDay)
        }
        if let json = cloud.string(forKey: MonthPeriods.Keys.overrides) {
            defaults.set(MonthPeriods.encode(MonthPeriods.decode(json)), forKey: MonthPeriods.Keys.overrides)
        }
    }
}

enum DeviceAuthentication {
    static var isAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = AppFormat.localized("action.cancel", language: .system)
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: reason
        )) ?? false
    }
}

enum ReminderScheduler {
    static let identifier = "tutar.daily-reminder"

    static func schedule(hour: Int, language: AppLanguage) async throws {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = AppFormat.localized("notification.title", language: language)
        content.body = AppFormat.localized("notification.body", language: language)
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(hour: hour),
            repeats: true
        )
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}

struct AboutView: View {
    @Environment(\.appLanguage) private var language

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .accessibilityHidden(true)
                    Text("about.appName")
                        .font(.largeTitle.bold())
                    Text("about.tagline")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            Section("about.openSource.section") {
                Text("about.attribution")
                Text(verbatim: "\(AppFormat.localized("about.modified", language: language)): \(AppConstants.modificationDate)")
                Text("about.gpl")

                Link(destination: AppConstants.sourceURL) {
                    Label("about.source", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: AppConstants.upstreamURL) {
                    Label("about.upstream", systemImage: "arrow.up.right.square")
                }
            }

            Section("about.privacy.section") {
                Text("about.privacy")
            }

            Section("about.version.section") {
                LabeledContent(
                    "about.version",
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                )
                LabeledContent(
                    "about.build",
                    value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "9"
                )
            }
        }
        .navigationTitle("about.title")
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }
}
