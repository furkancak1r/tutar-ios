// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import SwiftUI

@main
struct TutarApp: App {
    @StateObject private var dataController = DataController.shared
    @AppStorage("appLanguage", store: .tutar) private var languageRaw = AppLanguage.system.rawValue
    @AppStorage("appearance", store: .tutar) private var appearance = 0
    @AppStorage("currencyCode", store: .tutar) private var currencyCode = ""

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .system
    }

    init() {
        UserDefaults.tutar.register(defaults: [
            "appLanguage": AppLanguage.system.rawValue,
            "appearance": 0,
            "icloudSync": true,
            "currencyCode": Locale.autoupdatingCurrent.currency?.identifier ?? "USD"
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, dataController.context)
                .environmentObject(dataController)
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
                .preferredColorScheme(appearance == 1 ? .light : appearance == 2 ? .dark : nil)
                .tint(.tutarCoral)
        }
    }
}

