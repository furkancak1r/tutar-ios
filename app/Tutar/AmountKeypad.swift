// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import SwiftUI
import UIKit

struct MoneyEntry: Equatable {
    enum Mode: Int {
        case automaticCents = 1
        case decimal = 2
    }

    static let maximumMinorUnits: Int64 = 99_999_999_999

    let mode: Mode
    private(set) var automaticMinorUnits: Int64
    private(set) var decimalText: String

    init(minorUnits: Int64 = 0, mode: Mode = .automaticCents) {
        self.mode = mode
        automaticMinorUnits = max(0, min(minorUnits, Self.maximumMinorUnits))

        let whole = automaticMinorUnits / 100
        let fraction = automaticMinorUnits % 100
        decimalText = fraction == 0
            ? String(whole)
            : String(format: "%lld.%02lld", whole, fraction)
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

    mutating func append(_ digit: Int) {
        guard (0 ... 9).contains(digit) else { return }

        switch mode {
        case .automaticCents:
            guard automaticMinorUnits <= (Self.maximumMinorUnits - Int64(digit)) / 10 else { return }
            automaticMinorUnits = automaticMinorUnits * 10 + Int64(digit)
        case .decimal:
            let fractionCount = decimalText.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
            guard !decimalText.contains(".") || fractionCount < 2 else { return }

            let candidate: String
            if decimalText == "0" && digit != 0 {
                candidate = String(digit)
            } else if decimalText.isEmpty {
                candidate = String(digit)
            } else {
                candidate = decimalText + String(digit)
            }
            guard let value = Self.minorUnits(fromInvariantText: candidate), value <= Self.maximumMinorUnits else { return }
            decimalText = candidate
        }
    }

    mutating func insertDecimalSeparator() {
        guard mode == .decimal, !decimalText.contains(".") else { return }
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

    private let rows = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { digit in
                        digitButton(digit)
                    }
                }
            }

            GridRow {
                if entry.mode == .automaticCents {
                    keypadButton(systemImage: "delete.left", identifier: "keypadDelete") {
                        entry.deleteLast()
                    }
                    .accessibilityLabel(Text("keypad.delete"))
                } else {
                    keypadButton(title: decimalSeparator, identifier: "keypadDecimal") {
                        entry.insertDecimalSeparator()
                    }
                    .accessibilityLabel(Text("keypad.decimal"))
                }

                digitButton(0)

                Button(action: submit) {
                    Image(systemName: "checkmark")
                        .font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(Color(.systemBackground))
                        .background(Color.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("action.save"))
                .accessibilityIdentifier("keypadSubmit")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
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
        action: @escaping () -> Void
    ) -> some View {
        Button {
            if haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            action()
        } label: {
            Group {
                if let title {
                    Text(verbatim: title)
                        .font(.title2.weight(.medium).monospacedDigit())
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.medium))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(.primary)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
