// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import CoreData
import Foundation
import SwiftUI

enum SavingsAsset: String, CaseIterable, Identifiable {
    case TRY, USD, EUR, GBP, CHF, AED, AUD, AZN, CAD, CNY, DKK, JPY, KRW, KWD, KZT, NOK, PKR, QAR, RON, RUB, SAR, SEK, XDR, XAU995, XAU1000, XAG

    var id: String { rawValue }
    static var selectableCases: [SavingsAsset] {
        [.XAU995, .XAG] + allCases.filter { !$0.isMetal }
    }
    var isMetal: Bool { self == .XAU995 || self == .XAU1000 || self == .XAG }
    var unitKey: LocalizedStringKey { isMetal ? "savings.unit.gram" : "savings.unit.currency" }
    var symbol: String {
        switch self {
        case .XAU995, .XAU1000: "circle.hexagongrid.fill"
        case .XAG: "circle.hexagongrid"
        case .TRY: "banknote"
        default: "coloncurrencysign.circle"
        }
    }

    func name(language: AppLanguage) -> String {
        switch self {
        case .XAU995, .XAU1000: AppFormat.localized("savings.asset.gold", language: language)
        case .XAG: AppFormat.localized("savings.asset.silver", language: language)
        default: AppFormat.currencyName(rawValue, language: language)
        }
    }
}

enum SavingsQuoteSource: String, Codable {
    case live, tcmb, cached, manual
}

struct SavingsQuote: Codable, Equatable {
    let priceTRY: Decimal
    let updatedAt: Date
    let source: SavingsQuoteSource
}

enum SavingsQuoteMath {
    static let gramsPerTroyOunce = Decimal(string: "31.1034768")!

    static func metalPriceTRY(ounceUSD: Decimal, usdTRY: Decimal, purity: Decimal = 1) -> Decimal {
        ounceUSD * usdTRY / gramsPerTroyOunce * purity
    }

    static func crossRate(priceInTRY: Decimal, targetPriceInTRY: Decimal) -> Decimal? {
        guard priceInTRY > 0, targetPriceInTRY > 0 else { return nil }
        return priceInTRY / targetPriceInTRY
    }
}

@MainActor
final class SavingsQuoteStore: ObservableObject {
    @Published private(set) var quotes = [String: SavingsQuote]()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: Error?

    private static let cacheKey = "savingsQuoteCacheV1"
    private static let refreshInterval: TimeInterval = 15 * 60
    private var lastRefresh: Date?

    init() {
        if let data = UserDefaults.tutar.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode([String: SavingsQuote].self, from: data) {
            quotes = cached.mapValues { SavingsQuote(priceTRY: $0.priceTRY, updatedAt: $0.updatedAt, source: .cached) }
        }
    }

    func refresh(force: Bool = false) async {
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < Self.refreshInterval { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let goldTask: SpotResponse? = try? Self.fetchSpot(symbol: "XAU")
            async let silverTask: SpotResponse? = try? Self.fetchSpot(symbol: "XAG")
            let (tcmbData, response) = try await URLSession.shared.data(from: URL(string: "https://www.tcmb.gov.tr/kurlar/today.xml")!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            var fresh = try TCMBQuoteParser.parse(tcmbData)
            let now = Date()
            fresh["TRY"] = SavingsQuote(priceTRY: 1, updatedAt: now, source: .tcmb)

            if let usd = fresh["USD"]?.priceTRY {
                if let goldSpot = await goldTask {
                    fresh["XAU1000"] = SavingsQuote(
                        priceTRY: SavingsQuoteMath.metalPriceTRY(ounceUSD: goldSpot.price, usdTRY: usd),
                        updatedAt: goldSpot.updatedAt,
                        source: .live
                    )
                    fresh["XAU995"] = SavingsQuote(
                        priceTRY: SavingsQuoteMath.metalPriceTRY(ounceUSD: goldSpot.price, usdTRY: usd, purity: Decimal(string: "0.995")!),
                        updatedAt: goldSpot.updatedAt,
                        source: .live
                    )
                } else if let fallback = try? await Self.fetchTCMBMetals() {
                    fresh.merge(fallback) { _, new in new }
                }
                if let silverSpot = await silverTask {
                    fresh["XAG"] = SavingsQuote(
                        priceTRY: SavingsQuoteMath.metalPriceTRY(ounceUSD: silverSpot.price, usdTRY: usd),
                        updatedAt: silverSpot.updatedAt,
                        source: .live
                    )
                }
            }
            mergeAndCache(fresh)
            lastRefresh = now
            lastError = nil
        } catch {
            lastError = error
            do {
                let fallback = try await Self.fetchTCMBMetals()
                mergeAndCache(fallback)
                lastRefresh = .now
            } catch {
                // Cached and manual quotes remain usable offline.
            }
        }
    }

    func quote(for asset: SavingsAsset, in currencyCode: String) -> SavingsQuote? {
        if asset.rawValue == currencyCode {
            return SavingsQuote(priceTRY: 1, updatedAt: .now, source: .tcmb)
        }
        guard let assetQuote = quotes[asset.rawValue],
              let targetPrice = priceInTRY(for: currencyCode),
              let price = SavingsQuoteMath.crossRate(
                  priceInTRY: assetQuote.priceTRY,
                  targetPriceInTRY: targetPrice.priceTRY
              ) else { return nil }
        return SavingsQuote(
            priceTRY: price,
            updatedAt: min(assetQuote.updatedAt, targetPrice.updatedAt),
            source: assetQuote.source == .cached || targetPrice.source == .cached ? .cached : assetQuote.source
        )
    }

    func manualQuote(
        price: Decimal,
        currencyCode: String,
        targetCurrencyCode: String,
        updatedAt: Date
    ) -> SavingsQuote? {
        if currencyCode == targetCurrencyCode {
            return SavingsQuote(priceTRY: price, updatedAt: updatedAt, source: .manual)
        }
        guard let source = priceInTRY(for: currencyCode),
              let target = priceInTRY(for: targetCurrencyCode),
              let converted = SavingsQuoteMath.crossRate(
                  priceInTRY: price * source.priceTRY,
                  targetPriceInTRY: target.priceTRY
              ) else { return nil }
        return SavingsQuote(
            priceTRY: converted,
            updatedAt: min(updatedAt, min(source.updatedAt, target.updatedAt)),
            source: .manual
        )
    }

    private func priceInTRY(for currencyCode: String) -> SavingsQuote? {
        if currencyCode == "TRY" {
            return SavingsQuote(priceTRY: 1, updatedAt: .now, source: .tcmb)
        }
        return quotes[currencyCode]
    }

    private func mergeAndCache(_ fresh: [String: SavingsQuote]) {
        quotes.merge(fresh) { _, new in new }
        if let data = try? JSONEncoder().encode(quotes) {
            UserDefaults.tutar.set(data, forKey: Self.cacheKey)
        }
    }

    private struct SpotResponse: Decodable {
        let price: Decimal
        let updatedAt: Date

        private enum CodingKeys: String, CodingKey { case price, updatedAt }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            price = try container.decode(Decimal.self, forKey: .price)
            let value = try container.decode(String.self, forKey: .updatedAt)
            guard let date = ISO8601DateFormatter().date(from: value) else { throw DecodingError.dataCorruptedError(forKey: .updatedAt, in: container, debugDescription: "Invalid date") }
            updatedAt = date
        }
    }

    private static func fetchSpot(symbol: String) async throws -> SpotResponse {
        let url = URL(string: "https://api.gold-api.com/price/\(symbol)")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(SpotResponse.self, from: data)
    }

    private static func fetchTCMBMetals() async throws -> [String: SavingsQuote] {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for dayOffset in 0 ... 7 {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: .now)!
            formatter.dateFormat = "yyyyMM"
            let folder = formatter.string(from: date)
            formatter.dateFormat = "ddMMyyyy"
            let day = formatter.string(from: date)
            for hour in ["1100", "1500", "1400", "1300", "1200", "1000"] {
                let url = URL(string: "https://www.tcmb.gov.tr/reeskontkur/\(folder)/\(day)-\(hour).xml")!
                guard let (data, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
                let result = try TCMBQuoteParser.parse(data)
                if result["XAU995"] != nil || result["XAU1000"] != nil { return result }
            }
        }
        throw URLError(.resourceUnavailable)
    }
}

final class TCMBQuoteParser: NSObject, XMLParserDelegate {
    private var code = ""
    private var unit = Decimal(1)
    private var value = ""
    private var text = ""
    private var timestamp = Date()
    private(set) var quotes = [String: SavingsQuote]()

    static func parse(_ data: Data) throws -> [String: SavingsQuote] {
        let delegate = TCMBQuoteParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        return delegate.quotes
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "Tarih_Date", let date = attributeDict["Tarih"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "dd.MM.yyyy"
            timestamp = formatter.date(from: date) ?? .now
        }
        if elementName == "Currency" { code = attributeDict["CurrencyCode"] ?? attributeDict["Kod"] ?? "" }
        if elementName == "doviz_kur_liste", let date = attributeDict["gecerlilik_tarihi"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-M-d"
            timestamp = formatter.date(from: date) ?? .now
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "Unit", "birim": unit = decimal(trimmed) ?? 1
        case "doviz_cinsi": code = trimmed == "XAU" ? "XAU995" : trimmed == "XAS" ? "XAU1000" : trimmed
        case "ForexBuying", "alis": value = trimmed
        case "Currency", "kur":
            if let price = decimal(value), price > 0, unit > 0 {
                quotes[code] = SavingsQuote(priceTRY: price / unit, updatedAt: timestamp, source: .tcmb)
            }
            code = ""; unit = 1; value = ""
        default: break
        }
    }

    private func decimal(_ string: String) -> Decimal? {
        Decimal(string: string.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension DataController {
    @discardableResult
    func saveHolding(
        _ holding: SavingsHolding? = nil,
        asset: SavingsAsset,
        quantity: Decimal,
        quoteMode: Int,
        manualPrice: Decimal,
        manualPriceCurrencyCode: String
    ) throws -> SavingsHolding {
        guard quantity > 0, AppFormat.currencyCodes.contains(manualPriceCurrencyCode),
              quoteMode == 0 || (quoteMode == 1 && manualPrice > 0) else { throw SavingsError.invalidInput }
        let item = holding ?? NSEntityDescription.insertNewObject(forEntityName: "SavingsHolding", into: context) as! SavingsHolding
        item.id = item.id ?? UUID()
        item.institution = nil
        item.assetCode = asset.rawValue
        item.quantity = NSDecimalNumber(decimal: quantity)
        item.quoteMode = Int16(quoteMode)
        item.manualPrice = NSDecimalNumber(decimal: manualPrice)
        item.manualPriceCurrencyCode = manualPriceCurrencyCode
        item.manualQuoteDeclined = false
        item.createdAt = item.createdAt ?? .now
        item.updatedAt = .now
        try save()
        return item
    }

    func delete(_ holding: SavingsHolding) throws {
        context.delete(holding)
        try save()
    }

    func keepManualQuote(_ holding: SavingsHolding) throws {
        holding.manualQuoteDeclined = true
        try save()
    }

    func useAutomaticQuote(_ holding: SavingsHolding) throws {
        holding.quoteMode = 0
        holding.manualQuoteDeclined = false
        try save()
    }
}

enum SavingsError: Error { case invalidInput }

extension SavingsHolding {
    var wrappedAsset: SavingsAsset { SavingsAsset(rawValue: assetCode ?? "") ?? .TRY }
    var wrappedQuantity: Decimal { quantity?.decimalValue ?? 0 }
    var wrappedManualPrice: Decimal { manualPrice?.decimalValue ?? 0 }
    var wrappedManualPriceCurrencyCode: String {
        let code = manualPriceCurrencyCode ?? ""
        return AppFormat.currencyCodes.contains(code) ? code : "TRY"
    }
}
