// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.appLanguage) private var language
    @AppStorage("appLanguage", store: .tutar) private var languageRaw = AppLanguage.system.rawValue
    @AppStorage("appearance", store: .tutar) private var appearance = 0
    @AppStorage("currencyCode", store: .tutar) private var currencyCode = ""
    @AppStorage("numberEntryType", store: .tutar) private var numberEntryType = 1
    @AppStorage("haptics", store: .tutar) private var haptics = true
    @AppStorage("showSuggestions", store: .tutar) private var showSuggestions = true
    @AppStorage("showUpcoming", store: .tutar) private var showUpcoming = true
    @AppStorage("biometricLock", store: .tutar) private var biometricLock = false
    @AppStorage("icloudSync", store: .tutar) private var iCloudSync = true
    @AppStorage("dailyReminder", store: .tutar) private var dailyReminder = false
    @AppStorage("reminderHour", store: .tutar) private var reminderHour = 20

    @State private var showingDeleteConfirmation = false
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
                .pickerStyle(.segmented)
            }

            Section("settings.entry.section") {
                Picker("settings.numberEntry", selection: $numberEntryType) {
                    Text("settings.numberEntry.automatic").tag(1)
                    Text("settings.numberEntry.decimal").tag(2)
                }
                Toggle("settings.haptics", isOn: $haptics)
                Toggle("settings.suggestions", isOn: $showSuggestions)
                Toggle("settings.upcoming", isOn: $showUpcoming)
            }

            Section {
                NavigationLink {
                    CurrencyPickerView(selection: $currencyCode)
                } label: {
                    LabeledContent(
                        "settings.currency",
                        value: AppFormat.currencyCode(language: language, preferred: currencyCode)
                    )
                }
                .accessibilityIdentifier("currencyPicker")
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
                    .accessibilityIdentifier("biometricLockToggle")
                Toggle("settings.icloud", isOn: $iCloudSync)
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
        .navigationTitle("settings.title")
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
    }
}
