// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import CoreData
import SwiftUI

struct SavingsView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SavingsHolding.createdAt, ascending: true)],
        animation: .default
    ) private var holdings: FetchedResults<SavingsHolding>

    @EnvironmentObject private var dataController: DataController
    @Environment(\.appLanguage) private var language
    @AppStorage("currencyCode", store: .tutar) private var preferredCurrency = ""
    @StateObject private var quotes = SavingsQuoteStore()
    @State private var editor: SavingsHolding?
    @State private var showingNewEditor = false
    @State private var deleting: SavingsHolding?
    @State private var showingInfo = false
    @State private var errorMessage = ""

    private var currency: String {
        AppFormat.currencyCode(language: language, preferred: preferredCurrency)
    }

    private var valuedHoldings: [(SavingsHolding, Decimal)] {
        holdings.compactMap { holding in
            unitPrice(for: holding).map { (holding, holding.wrappedQuantity * $0.priceTRY) }
        }
    }

    private var total: Decimal { valuedHoldings.reduce(0) { $0 + $1.1 } }
    private var missingCount: Int { holdings.count - valuedHoldings.count }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 7) {
                    Text(missingCount > 0 ? "savings.total.minimum" : "savings.total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(SavingsFormatting.money(total, language: language, currencyCode: currency))
                        .font(.system(.largeTitle, design: .rounded, weight: .medium))
                        .monospacedDigit()
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                    if missingCount > 0 {
                        Text(AppFormat.plural("savings.missing.count", count: missingCount, language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let updated = valuedHoldings.compactMap({ unitPrice(for: $0.0)?.updatedAt }).min() {
                        Text(updated.formatted(.relative(presentation: .named).locale(language.locale)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            if !holdings.isEmpty {
                Section {
                    ForEach(holdings) { holding in
                        holdingRow(holding)
                            .contentShape(Rectangle())
                            .onTapGesture { editor = holding }
                            .tutarDeleteSwipeAction { deleting = holding }
                            .confirmationDialog(
                                "savings.delete.title",
                                isPresented: deleteBinding(for: holding),
                                titleVisibility: .visible
                            ) {
                                Button("action.delete", role: .destructive) { performDelete() }
                                Button("action.cancel", role: .cancel) { deleting = nil }
                            } message: {
                                Text("savings.delete.message")
                            }
                    }
                }
            }

            if holdings.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("savings.empty.title", systemImage: "building.columns")
                    } description: {
                        Text("savings.empty.message")
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("savings.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingInfo = true } label: {
                    Label("savings.info", systemImage: "info.circle").labelStyle(.iconOnly)
                }
                .popover(isPresented: $showingInfo, arrowEdge: .top) {
                    Text(verbatim: AppFormat.format("savings.info.message", language: language, currency))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(18)
                        .frame(idealWidth: 320)
                        .presentationCompactAdaptation(.popover)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if quotes.isRefreshing { ProgressView().controlSize(.small) }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button { showingNewEditor = true } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 54, height: 54)
                    .background(Color.primary, in: Circle())
            }
            .accessibilityLabel(Text("savings.add"))
            .accessibilityIdentifier("addSavingsButton")
            .padding(.trailing, 20)
            .padding(.bottom, 18)
        }
        .refreshable { await quotes.refresh(force: true) }
        .task { await quotes.refresh() }
        .sheet(isPresented: $showingNewEditor) { SavingsEditorView() }
        .sheet(item: $editor) { SavingsEditorView(holding: $0) }
        .alert("error.save.title", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) { Button("action.ok") { errorMessage = "" } } message: { Text(verbatim: errorMessage) }
    }

    @ViewBuilder
    private func holdingRow(_ holding: SavingsHolding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: holding.wrappedAsset.symbol)
                    .font(.title3)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(holding.wrappedAsset.name(language: language))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(verbatim: quantityText(holding))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(unitPrice(for: holding).map {
                        SavingsFormatting.money(
                            holding.wrappedQuantity * $0.priceTRY,
                            language: language,
                            currencyCode: currency
                        )
                    } ?? "—")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text(sourceText(for: holding))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            if holding.quoteMode == 1, !holding.manualQuoteDeclined,
               quotes.quote(for: holding.wrappedAsset, in: currency) != nil {
                HStack(spacing: 10) {
                    Text("savings.automatic.available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("savings.automatic.use") { useAutomatic(holding) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("savings.manual.keep") { keepManual(holding) }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func unitPrice(for holding: SavingsHolding) -> SavingsQuote? {
        if holding.quoteMode == 1, holding.wrappedManualPrice > 0 {
            return quotes.manualQuote(
                price: holding.wrappedManualPrice,
                currencyCode: holding.wrappedManualPriceCurrencyCode,
                targetCurrencyCode: currency,
                updatedAt: holding.updatedAt ?? .now
            )
        }
        return quotes.quote(for: holding.wrappedAsset, in: currency)
    }

    private func quantityText(_ holding: SavingsHolding) -> String {
        let unit = holding.wrappedAsset.isMetal
            ? AppFormat.localized("savings.unit.gram.short", language: language)
            : holding.wrappedAsset.rawValue
        return "\(SavingsFormatting.quantity(holding.wrappedQuantity, language: language)) \(unit)"
    }

    private func sourceText(for holding: SavingsHolding) -> String {
        guard let quote = unitPrice(for: holding) else {
            return AppFormat.format("savings.manual.required", language: language, currency)
        }
        return AppFormat.localized("savings.source.\(quote.source.rawValue)", language: language)
    }

    private func deleteBinding(for holding: SavingsHolding) -> Binding<Bool> {
        let id = holding.objectID
        return Binding(
            get: { deleting?.objectID == id },
            set: { if !$0, deleting?.objectID == id { deleting = nil } }
        )
    }

    private func performDelete() {
        guard let target = deleting else { return }
        deleting = nil
        do { try dataController.delete(target) } catch { errorMessage = error.localizedDescription }
    }

    private func useAutomatic(_ holding: SavingsHolding) {
        do { try dataController.useAutomaticQuote(holding) } catch { errorMessage = error.localizedDescription }
    }

    private func keepManual(_ holding: SavingsHolding) {
        do { try dataController.keepManualQuote(holding) } catch { errorMessage = error.localizedDescription }
    }
}

private struct SavingsEditorView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @AppStorage("currencyCode", store: .tutar) private var preferredCurrency = ""
    let holding: SavingsHolding?

    @StateObject private var quotes = SavingsQuoteStore()
    @State private var asset: SavingsAsset
    @State private var quantityEntry: MoneyEntry
    @State private var quoteMode: Int
    @State private var manualPriceEntry: MoneyEntry
    @State private var manualPriceCurrencyCode: String
    @State private var didCheckQuotes = false
    @State private var errorMessage = ""
    @State private var activeField = Field.quantity

    private enum Field { case quantity, price }

    private var currency: String {
        AppFormat.currencyCode(language: language, preferred: preferredCurrency)
    }

    private var pickerAssets: [SavingsAsset] {
        asset == .XAU1000
            ? [.XAU1000] + SavingsAsset.selectableCases.filter { $0 != .XAU995 }
            : SavingsAsset.selectableCases
    }

    private var activeEntry: Binding<MoneyEntry> {
        activeField == .price ? $manualPriceEntry : $quantityEntry
    }

    init(holding: SavingsHolding? = nil) {
        self.holding = holding
        _asset = State(initialValue: holding?.wrappedAsset ?? .XAU995)
        _quantityEntry = State(initialValue: MoneyEntry(
            decimal: holding?.wrappedQuantity ?? 0,
            maximumFractionDigits: 6
        ))
        _quoteMode = State(initialValue: Int(holding?.quoteMode ?? 0))
        _manualPriceEntry = State(initialValue: MoneyEntry(
            decimal: holding?.wrappedManualPrice ?? 0,
            maximumFractionDigits: 6
        ))
        _manualPriceCurrencyCode = State(initialValue: holding?.wrappedManualPriceCurrencyCode ?? "TRY")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section("savings.asset.section") {
                        Picker("savings.asset", selection: $asset) {
                            ForEach(pickerAssets) { item in
                                Text(item.name(language: language)).tag(item)
                            }
                        }
                        decimalInput(
                            title: Text("savings.quantity"),
                            field: .quantity,
                            entry: $quantityEntry,
                            identifier: "savingsQuantityInput"
                        )
                    }

                    Section("savings.valuation.section") {
                        Picker("savings.valuation", selection: $quoteMode) {
                            Text("savings.valuation.automatic").tag(0)
                            Text("savings.valuation.manual").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: quoteMode) { _, mode in
                            activeField = mode == 1 ? .price : .quantity
                        }
                        if quoteMode == 1 {
                            decimalInput(
                                title: Text(verbatim: AppFormat.format("savings.manual.price", language: language, currency)),
                                field: .price,
                                entry: $manualPriceEntry,
                                identifier: "savingsManualPriceInput"
                            )
                            Text(verbatim: AppFormat.format("savings.manual.help", language: language, currency))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if didCheckQuotes,
                                  quotes.quote(for: asset, in: currency) == nil {
                            Text(verbatim: AppFormat.format("savings.automatic.unavailable", language: language, currency))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("savings.manual.enter") {
                                quoteMode = 1
                                activeField = .price
                            }
                        }
                    }
                }

                AmountKeypad(entry: activeEntry, submit: advanceOrSave)
            }
            .navigationTitle(holding == nil ? "savings.add" : "savings.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("action.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("action.save", action: save) }
            }
            .onAppear {
                if holding == nil {
                    manualPriceCurrencyCode = currency
                } else if quoteMode == 1, manualPriceCurrencyCode != currency {
                    manualPriceEntry = MoneyEntry(decimal: 0, maximumFractionDigits: 6)
                }
            }
            .task(id: asset) {
                await quotes.refresh()
                if quoteMode == 1, manualPriceCurrencyCode != currency,
                   let converted = quotes.manualQuote(
                       price: holding?.wrappedManualPrice ?? 0,
                       currencyCode: manualPriceCurrencyCode,
                       targetCurrencyCode: currency,
                       updatedAt: holding?.updatedAt ?? .now
                   ) {
                    manualPriceEntry = MoneyEntry(decimal: converted.priceTRY, maximumFractionDigits: 6)
                    manualPriceCurrencyCode = currency
                }
                didCheckQuotes = true
            }
            .alert("error.save.title", isPresented: Binding(
                get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } }
            )) { Button("action.ok") { errorMessage = "" } } message: { Text(verbatim: errorMessage) }
        }
    }

    private func decimalInput(
        title: Text,
        field: Field,
        entry: Binding<MoneyEntry>,
        identifier: String
    ) -> some View {
        LabeledContent {
            HStack(spacing: 2) {
                Button {
                    activeField = field
                } label: {
                    Text(verbatim: displayText(entry.wrappedValue))
                        .monospacedDigit()
                        .foregroundStyle(activeField == field ? Color.primary : .secondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityValue(Text(verbatim: displayText(entry.wrappedValue)))
                .accessibilityIdentifier(identifier)

                if activeField == field {
                    AmountDeleteButton(entry: entry)
                }
            }
        } label: {
            title
        }
    }

    private func displayText(_ entry: MoneyEntry) -> String {
        entry.decimalText.replacingOccurrences(of: ".", with: language.locale.decimalSeparator ?? ".")
    }

    private func advanceOrSave() {
        if quoteMode == 1, activeField == .quantity {
            activeField = .price
        } else {
            save()
        }
    }

    private func save() {
        do {
            try dataController.saveHolding(
                holding,
                asset: asset,
                quantity: quantityEntry.decimalValue,
                quoteMode: quoteMode,
                manualPrice: manualPriceEntry.decimalValue,
                manualPriceCurrencyCode: quoteMode == 1 ? currency : manualPriceCurrencyCode
            )
            dismiss()
        } catch {
            errorMessage = AppFormat.localized("savings.error.invalid", language: language)
        }
    }
}

enum SavingsFormatting {
    static func money(_ amount: Decimal, language: AppLanguage, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = language.locale
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "—"
    }

    static func quantity(_ value: Decimal, language: AppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = language.locale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    static func editable(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func parse(_ value: String, language: AppLanguage) -> Decimal? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: language.locale.decimalSeparator ?? ",", with: ".")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}
