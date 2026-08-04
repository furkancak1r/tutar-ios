// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import SwiftUI

@main
struct TutarApp: App {
    @StateObject private var dataController = DataController.shared
    @StateObject private var appLockController: AppLockController
    @AppStorage("appLanguage", store: .tutar) private var languageRaw = AppLanguage.system.rawValue
    @AppStorage("appearance", store: .tutar) private var appearance = 0
    @AppStorage("biometricLock", store: .tutar) private var biometricLock = false

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .system
    }

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        if arguments.contains("-ui-test-app-lock") {
            let succeeds = !arguments.contains("-ui-test-authentication-fails")
            _appLockController = StateObject(wrappedValue: AppLockController { _ in
                try? await Task.sleep(nanoseconds: 150_000_000)
                return succeeds
            })
        } else {
            _appLockController = StateObject(wrappedValue: AppLockController())
        }
        #else
        _appLockController = StateObject(wrappedValue: AppLockController())
        #endif

        UserDefaults.tutar.register(defaults: [
            "appLanguage": AppLanguage.system.rawValue,
            "appearance": 0,
            "icloudSync": true,
            "currencyCode": "",
            "numberEntryType": 1,
            "haptics": true,
            "showSuggestions": true,
            "showUpcoming": true,
            "biometricLock": false
        ])
        #if DEBUG
        if arguments.contains("-ui-testing") {
            UserDefaults.tutar.set("", forKey: "currencyCode")
        }
        if arguments.contains("-ui-test-app-lock") {
            UserDefaults.tutar.set(true, forKey: "biometricLock")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(\.managedObjectContext, dataController.context)
                .environmentObject(dataController)
                .environmentObject(appLockController)
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
                .preferredColorScheme(appearance == 1 ? .light : appearance == 2 ? .dark : nil)
                .tint(.accentColor)
                .privacySensitive(biometricLock)
        }
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
        if NSClassFromString("XCTestCase") != nil,
           !ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            EmptyView()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-test-largest-text") {
            RootView().dynamicTypeSize(.accessibility5)
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }
}
