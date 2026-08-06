// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import SwiftUI

struct MoneyEntry: Equatable {
    enum Mode: Int {
        case automaticCents = 1
        case decimal = 2
    }

    static let maximumMinorUnits: Int64 = 99_999_999_999

    private(set) var mode: Mode
    private(set) var automaticMinorUnits: Int64
    private(set) var decimalText: String
    private let maximumFractionDigits: Int
    private var hasAutomaticInput = false

    init(minorUnits: Int64 = 0, mode: Mode = .decimal, maximumFractionDigits: Int = 2) {
        self.mode = mode
        self.maximumFractionDigits = maximumFractionDigits
        automaticMinorUnits = max(0, min(minorUnits, Self.maximumMinorUnits))

        let whole = automaticMinorUnits / 100
        let fraction = automaticMinorUnits % 100
        decimalText = fraction == 0
            ? String(whole)
            : String(format: "%lld.%02lld", whole, fraction)
    }

    init(decimal: Decimal, maximumFractionDigits: Int) {
        mode = .decimal
        self.maximumFractionDigits = maximumFractionDigits
        automaticMinorUnits = 0
        decimalText = NSDecimalNumber(decimal: decimal).stringValue
    }

    var minorUnits: Int64 {
        switch mode {
        case .automaticCents:
            automaticMinorUnits
        case .decimal:
            Self.minorUnits(fromInvariantText: decimalText) ?? 0
        }
    }

    var isEmpty: Bool { minorUnits == 0 }

    var decimalValue: Decimal {
        switch mode {
        case .automaticCents:
            Decimal(automaticMinorUnits) / 100
        case .decimal:
            Decimal(string: decimalText, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        }
    }

    mutating func append(_ digit: Int) {
        guard (0 ... 9).contains(digit) else { return }

        switch mode {
        case .automaticCents:
            guard automaticMinorUnits <= (Self.maximumMinorUnits - Int64(digit)) / 10 else { return }
            automaticMinorUnits = automaticMinorUnits * 10 + Int64(digit)
            hasAutomaticInput = true
        case .decimal:
            let fractionCount = decimalText.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
            guard !decimalText.contains(".") || fractionCount < maximumFractionDigits else { return }

            let candidate: String
            if decimalText == "0" && digit != 0 {
                candidate = String(digit)
            } else if decimalText.isEmpty {
                candidate = String(digit)
            } else {
                candidate = decimalText + String(digit)
            }
            if maximumFractionDigits == 2 {
                guard let value = Self.minorUnits(fromInvariantText: candidate), value <= Self.maximumMinorUnits else { return }
            } else {
                guard Decimal(string: candidate, locale: Locale(identifier: "en_US_POSIX")) != nil else { return }
            }
            decimalText = candidate
        }
    }

    mutating func insertDecimalSeparator() {
        if mode == .automaticCents {
            mode = .decimal
            decimalText = hasAutomaticInput ? String(automaticMinorUnits) : decimalText
        }
        guard !decimalText.contains(".") else { return }
        decimalText = decimalText.isEmpty ? "0." : decimalText + "."
    }

    mutating func deleteLast() {
        switch mode {
        case .automaticCents:
            automaticMinorUnits /= 10
        case .decimal:
            guard !decimalText.isEmpty else { return }
            decimalText.removeLast()
        }
    }

    private static func minorUnits(fromInvariantText text: String) -> Int64? {
        guard !text.isEmpty else { return 0 }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let whole = Int64(parts[0].isEmpty ? "0" : parts[0]) else { return nil }
        let fractionText = parts.count == 2 ? String(parts[1]) : ""
        guard fractionText.count <= 2, let fraction = Int64(fractionText.isEmpty ? "0" : fractionText) else { return nil }
        let scale: Int64 = fractionText.count == 1 ? 10 : 1
        let (scaledWhole, overflow) = whole.multipliedReportingOverflow(by: 100)
        guard !overflow else { return nil }
        let (result, additionOverflow) = scaledWhole.addingReportingOverflow(fraction * scale)
        return additionOverflow ? nil : result
    }
}

struct AmountKeypad: View {
    @Binding var entry: MoneyEntry
    let submit: () -> Void

    @Environment(\.appLanguage) private var language
    @AppStorage("haptics", store: .tutar) private var haptics = true
    @State private var hapticTrigger = 0

    private let rows = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(rows, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { digit in
                            digitButton(digit)
                        }
                    }
                }

                GridRow {
                    keypadButton(title: decimalSeparator, identifier: "keypadDecimal") {
                        entry.insertDecimalSeparator()
                    }
                    .accessibilityLabel(Text("keypad.decimal"))

                    digitButton(0)

                    keypadButton(systemImage: "arrow.right", identifier: "keypadSubmit", prominent: true) {
                        submit()
                    }
                    .accessibilityLabel(Text("action.save"))
                }
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .sensoryFeedback(.impact(weight: .light, intensity: 0.8), trigger: hapticTrigger) { _, _ in
            haptics
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("amountKeypad")
    }

    private var decimalSeparator: String {
        language.locale.decimalSeparator ?? "."
    }

    private func digitButton(_ digit: Int) -> some View {
        keypadButton(title: String(digit), identifier: "keypad\(digit)") {
            entry.append(digit)
        }
        .accessibilityLabel(Text(verbatim: String(digit)))
    }

    private func keypadButton(
        title: String? = nil,
        systemImage: String? = nil,
        identifier: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            hapticTrigger &+= 1
            action()
        } label: {
            Group {
                if let title {
                    Text(verbatim: title)
                        .font(.title3.weight(.medium).monospacedDigit())
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.medium))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(prominent ? Color(.systemBackground) : .primary)
            .background(prominent ? Color.primary : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

struct AmountDeleteButton: View {
    @Binding var entry: MoneyEntry
    @AppStorage("haptics", store: .tutar) private var haptics = true
    @State private var hapticTrigger = 0

    var body: some View {
        Button {
            hapticTrigger &+= 1
            entry.deleteLast()
        } label: {
            Image(systemName: "delete.left")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("keypad.delete"))
        .accessibilityIdentifier("amountDeleteButton")
        .sensoryFeedback(.impact(weight: .light, intensity: 0.8), trigger: hapticTrigger) { _, _ in haptics }
    }
}
