// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.appLanguage) private var language
    @AppStorage("appLanguage", store: .tutar) private var languageRaw = AppLanguage.system.rawValue
    @AppStorage("appearance", store: .tutar) private var appearance = 0
    @AppStorage("currencyCode", store: .tutar) private var currencyCode = ""
    @AppStorage("icloudSync", store: .tutar) private var iCloudSync = true
    @AppStorage("dailyReminder", store: .tutar) private var dailyReminder = false
    @AppStorage("reminderHour", store: .tutar) private var reminderHour = 20
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage = ""

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

            Section("settings.money.section") {
                if language.isEffectivelyTurkish {
                    LabeledContent("settings.currency", value: "TRY")
                } else {
                    Picker("settings.currency", selection: $currencyCode) {
                        ForEach(["TRY", "USD", "EUR", "GBP"], id: \.self) { code in
                            Text(verbatim: code).tag(code)
                        }
                    }
                }
            }

            Section {
                Toggle("settings.icloud", isOn: $iCloudSync)
                    .accessibilityIdentifier("icloudToggle")
            } header: {
                Text("settings.sync.section")
            } footer: {
                Text("settings.icloud.footer")
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
        .alert("error.save.title", isPresented: .constant(errorMessage.isEmpty == false)) {
            Button("action.ok") { errorMessage = "" }
        } message: {
            Text(verbatim: errorMessage)
        }
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
                errorMessage = error.localizedDescription
            }
        }
    }

    private func eraseData() {
        do {
            try dataController.deleteAll()
        } catch {
            errorMessage = error.localizedDescription
        }
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
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                    value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                )
            }
        }
        .navigationTitle("about.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
