// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import Foundation

struct InstallmentSlice: Equatable {
    let index: Int
    let count: Int
    let amountMinorUnits: Int64
    let date: Date
}

enum InstallmentError: Error, Equatable {
    case invalidAmount
    case invalidCount
    case invalidInterval
    case invalidDate
    case duplicate
    case missingGroup
}

enum InstallmentPlanner {
    static func plan(
        totalMinorUnits: Int64,
        count: Int,
        firstDate: Date,
        intervalMonths: Int,
        calendar: Calendar = .current
    ) throws -> [InstallmentSlice] {
        guard totalMinorUnits >= count else { throw InstallmentError.invalidAmount }
        guard (1 ... 120).contains(count) else { throw InstallmentError.invalidCount }
        guard (1 ... 24).contains(intervalMonths) else { throw InstallmentError.invalidInterval }

        let base = totalMinorUnits / Int64(count)
        let remainder = totalMinorUnits % Int64(count)

        return try (0 ..< count).map { offset in
            guard let date = monthlyDate(
                from: firstDate,
                monthOffset: offset * intervalMonths,
                calendar: calendar
            ) else {
                throw InstallmentError.invalidDate
            }

            return InstallmentSlice(
                index: offset + 1,
                count: count,
                amountMinorUnits: base + (offset == count - 1 ? remainder : 0),
                date: date
            )
        }
    }

    static func monthlyDate(from firstDate: Date, monthOffset: Int, calendar: Calendar) -> Date? {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: firstDate)
        guard
            let year = parts.year,
            let month = parts.month,
            let day = parts.day,
            let firstMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
            let targetMonth = calendar.date(byAdding: .month, value: monthOffset, to: firstMonth),
            let validDays = calendar.range(of: .day, in: .month, for: targetMonth)
        else {
            return nil
        }

        var target = calendar.dateComponents([.year, .month], from: targetMonth)
        target.day = min(day, validDays.count)
        target.hour = parts.hour
        target.minute = parts.minute
        target.second = parts.second
        return calendar.date(from: target)
    }
}

enum MoneyInput {
    static func minorUnits(from text: String, locale: Locale) -> Int64? {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true

        guard let decimal = formatter.number(from: text.trimmingCharacters(in: .whitespacesAndNewlines))?.decimalValue else {
            return nil
        }

        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard rounded == scaled else { return nil }

        let value = NSDecimalNumber(decimal: rounded)
        guard value != .notANumber, value.compare(NSDecimalNumber.zero) == .orderedDescending else { return nil }
        return value.int64Value
    }
}
