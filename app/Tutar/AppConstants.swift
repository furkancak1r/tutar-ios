// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import Foundation
import SwiftUI

enum AppConstants {
    static let appGroup = "group.com.furkancakir.tutar"
    static let cloudContainer = "iCloud.com.furkancakir.tutar"
    static let sourceURL = URL(string: "https://github.com/furkancak1r/tutar-ios")!
    static let upstreamURL = URL(string: "https://github.com/rafsoh/dimeApp")!
    static let supportURL = URL(string: "https://furkancak1r.github.io/tutar-ios/support.html")!
    static let privacyURL = URL(string: "https://furkancak1r.github.io/tutar-ios/privacy.html")!
    static let feedbackEmail = "furkancakr7@gmail.com"
    static let modificationDate = "2026-08-04"
}

extension UserDefaults {
    static let tutar = UserDefaults(suiteName: AppConstants.appGroup) ?? .standard
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case turkish = "tr"
    case english = "en"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .turkish:
            return Locale(identifier: "tr_TR")
        case .english:
            let region = Locale.autoupdatingCurrent.region?.identifier ?? "US"
            return Locale(identifier: "en_\(region)")
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "language.system"
        case .turkish: "language.turkish"
        case .english: "language.english"
        }
    }

    var isEffectivelyTurkish: Bool {
        locale.language.languageCode?.identifier == "tr"
    }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue = AppLanguage.system
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

enum AppFormat {
    static let currencyCodes = Array(Set(Locale.Currency.isoCurrencies.map(\.identifier))).sorted()

    static func currencyCode(language: AppLanguage, preferred: String) -> String {
        guard preferred.isEmpty else { return preferred }
        return language.isEffectivelyTurkish ? "TRY" : (Locale.autoupdatingCurrent.currency?.identifier ?? "USD")
    }

    static func currencyName(_ code: String, language: AppLanguage) -> String {
        language.locale.localizedString(forCurrencyCode: code) ?? code
    }

    static func money(_ amount: Double, language: AppLanguage, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = language.locale
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "—"
    }

    static func date(_ date: Date, language: AppLanguage) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(language.locale))
    }

    static func month(_ date: Date, language: AppLanguage) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(language.locale))
    }

    static func dayHeader(_ date: Date, language: AppLanguage) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return localized("date.today", language: language)
        }
        if calendar.isDateInYesterday(date) {
            return localized("date.yesterday", language: language)
        }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(language.locale))
    }

    static func localized(_ key: String, language: AppLanguage) -> String {
        localizedBundle(language: language).localizedString(forKey: key, value: nil, table: nil)
    }

    static func plural(_ key: String, count: Int, language: AppLanguage) -> String {
        let format = localizedBundle(language: language).localizedString(forKey: key, value: nil, table: nil)
        return String.localizedStringWithFormat(format, count)
    }

    static func format(_ key: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        String(
            format: localized(key, language: language),
            locale: language.locale,
            arguments: arguments
        )
    }

    private static func localizedBundle(language: AppLanguage) -> Bundle {
        let identifier: String
        switch language {
        case .turkish:
            identifier = "tr"
        case .english:
            identifier = "en"
        case .system:
            identifier = language.isEffectivelyTurkish ? "tr" : "en"
        }
        guard let path = Bundle.main.path(forResource: identifier, ofType: "lproj"), let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let number = UInt64(value, radix: 16) ?? 0x232326
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}
