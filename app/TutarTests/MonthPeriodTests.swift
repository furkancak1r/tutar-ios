// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import CoreData
import XCTest
@testable import Tutar

/// Deterministic random numbers, so that a failed case can be repeated.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

private func gregorian(_ zone: String) throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "tr_TR")
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
    return calendar
}

private func date(
    _ calendar: Calendar,
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
) throws -> Date {
    try XCTUnwrap(calendar.date(from: DateComponents(
        year: year, month: month, day: day, hour: hour, minute: minute, second: second
    )))
}

private struct Record {
    let date: Date
    let amount: Int
}

private func sum(_ records: [Record], where include: (Date) -> Bool) -> Int {
    records.reduce(0) { include($1.date) ? $0 + $1.amount : $0 }
}

private func randomDate(from start: Date, to end: Date, using generator: inout SplitMix64) -> Date {
    start.addingTimeInterval(Double(Int.random(in: 0 ..< Int(end.timeIntervalSince(start)), using: &generator)))
}

/// The code before this change, kept as the reference for the default mode.
private enum Legacy {
    static func analysisInterval(_ period: AnalysisPeriod, _ date: Date, _ calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: period.component, for: date)
            ?? calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: date, duration: 86_400)
    }

    static func move(_ period: AnalysisPeriod, _ offset: Int, _ date: Date, _ calendar: Calendar) -> Date {
        calendar.date(byAdding: period.component, value: offset, to: analysisInterval(period, date, calendar).start) ?? date
    }

    static func budgetInterval(start originalStart: Date, type: Int, reference: Date) -> DateInterval {
        let calendar = Calendar.current
        let component: Calendar.Component
        let value: Int
        switch type {
        case 1: component = .day; value = 1
        case 2: component = .day; value = 7
        case 3: component = .month; value = 1
        default: component = .year; value = 1
        }
        var start = originalStart
        var end = calendar.date(byAdding: component, value: value, to: start) ?? start.addingTimeInterval(86_400)
        while end <= reference {
            start = end
            end = calendar.date(byAdding: component, value: value, to: start) ?? start.addingTimeInterval(86_400)
        }
        return DateInterval(start: start, end: end)
    }
}

final class MonthPeriodTests: XCTestCase {
    private let zones = ["Europe/Istanbul", "Europe/Berlin"]

    // Test 1: the default mode equals calendar months for 3 years (2028 is a leap year, Berlin has DST).
    func testDefaultModeEqualsCalendarMonthsAndAnalysisPeriods() throws {
        for zone in zones {
            let calendar = try gregorian(zone)
            let periods = MonthPeriods(calendar: calendar)
            XCTAssertFalse(periods.isCustom)
            var day = try date(calendar, 2026, 1, 1)
            let end = try date(calendar, 2029, 1, 1)
            while day < end {
                for hour in [0, 1, 2, 3, 12, 23] {
                    let instant = try XCTUnwrap(calendar.date(byAdding: .hour, value: hour, to: day))
                    let month = try XCTUnwrap(calendar.dateInterval(of: .month, for: instant))
                    XCTAssertEqual(periods.interval(containing: instant), month, "\(zone) \(instant)")
                    XCTAssertEqual(periods.month(containing: instant), month.start, "\(zone) \(instant)")
                    for kind in AnalysisPeriod.allCases {
                        XCTAssertEqual(kind.interval(containing: instant, in: periods), Legacy.analysisInterval(kind, instant, calendar))
                        XCTAssertEqual(kind.chartRange(containing: instant, in: periods), Legacy.analysisInterval(kind, instant, calendar))
                        for offset in [-1, 1] {
                            XCTAssertEqual(
                                kind.date(byMoving: offset, from: instant, in: periods),
                                Legacy.move(kind, offset, instant, calendar)
                            )
                        }
                    }
                }
                day = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
            }
        }
    }

    // Test 1: totals equal the old totals, except that a record at 00:00:00 on the 1st now counts once (F08).
    func testDefaultModeTotalsMatchOldTotalsExceptMidnightOnTheFirst() throws {
        var generator = SplitMix64(state: 7)
        for zone in zones {
            let calendar = try gregorian(zone)
            let periods = MonthPeriods(calendar: calendar)
            let start = try date(calendar, 2026, 1, 1)
            let end = try date(calendar, 2029, 1, 1)
            var monthStarts = [start]
            while let last = monthStarts.last, last < end {
                monthStarts.append(try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: last)))
            }
            var records = [Record]()
            for _ in 0 ..< 3_000 {
                let instant = randomDate(from: start, to: end, using: &generator)
                records.append(Record(date: instant, amount: Int.random(in: 1 ... 100_000, using: &generator)))
            }
            for boundary in monthStarts {
                for offset in [-1.0, 0, 1] {
                    records.append(Record(date: boundary.addingTimeInterval(offset), amount: 1_000))
                }
            }

            var newTotal = 0
            for monthStart in monthStarts.dropLast() {
                let old = try XCTUnwrap(calendar.dateInterval(of: .month, for: monthStart))
                let new = periods.interval(containing: monthStart)
                let oldSum = sum(records) { old.contains($0) }
                let newSum = sum(records) { new.containsHalfOpen($0) }
                let onNextFirst = sum(records) { $0 == old.end }
                XCTAssertEqual(newSum, oldSum - onNextFirst, "\(zone) \(monthStart)")
                newTotal += newSum
            }
            let inRange = sum(records) { $0 >= start && $0 < end }
            XCTAssertEqual(newTotal, inRange)

            let first = try date(calendar, 2027, 3, 1)
            let february = try XCTUnwrap(calendar.dateInterval(of: .month, for: try date(calendar, 2027, 2, 10)))
            XCTAssertTrue(february.contains(first), "The old closed interval counted the record in February too.")
            XCTAssertFalse(periods.interval(containing: february.start).containsHalfOpen(first))
            XCTAssertTrue(periods.interval(containing: first).containsHalfOpen(first))
            XCTAssertEqual(periods.month(containing: first), first)
            XCTAssertEqual(
                monthStarts.dropLast().filter { periods.interval(containing: $0).containsHalfOpen(first) }.count,
                1
            )
        }
    }

    // Test 2: with random settings each record is in exactly one period, and the sums match.
    func testRandomSettingsPartitionRecords() throws {
        var generator = SplitMix64(state: 2026)
        for zone in zones + ["America/Santiago", "America/New_York", "Australia/Sydney"] {
            let calendar = try gregorian(zone)
            let first = try date(calendar, 2026, 1, 1)
            let last = try date(calendar, 2029, 1, 1)
            for round in 0 ..< 40 {
                var overrides = [String: Int]()
                for _ in 0 ..< Int.random(in: 0 ... 14, using: &generator) {
                    let key = String(
                        format: "%04d-%02d",
                        Int.random(in: 2025 ... 2029, using: &generator),
                        Int.random(in: 1 ... 12, using: &generator)
                    )
                    overrides[key] = Int.random(in: 1 ... 31, using: &generator)
                }
                let cutoff = Int.random(in: 1 ... 31, using: &generator)
                let periods = MonthPeriods(
                    calendar: calendar,
                    mode: round % 4 == 0 ? 0 : 1,
                    cutoffDay: cutoff,
                    overridesJSON: MonthPeriods.encode(overrides)
                )

                var list = [DateInterval]()
                var month = periods.month(containing: first)
                while list.last.map({ $0.end <= last }) ?? true {
                    let interval = periods.interval(containing: month)
                    XCTAssertLessThan(interval.start, interval.end, "Empty period \(zone) \(month)")
                    XCTAssertTrue(interval.containsHalfOpen(month))
                    XCTAssertEqual(periods.month(containing: interval.start), month)
                    XCTAssertEqual(periods.month(containing: interval.end.addingTimeInterval(-1)), month)
                    if let previous = list.last {
                        XCTAssertEqual(previous.end, interval.start, "Gap or overlap \(zone) \(month)")
                    }
                    if periods.isCustom {
                        // Bank rule: the cut-off day (or the last day of a shorter month) is the last day.
                        let day = overrides[periods.key(for: month)] ?? cutoff
                        let length = try XCTUnwrap(calendar.range(of: .day, in: .month, for: month)).count
                        let lastDay = interval.end.addingTimeInterval(-1)
                        XCTAssertEqual(calendar.component(.day, from: lastDay), min(day, length), "\(zone) \(month)")
                        XCTAssertEqual(calendar.component(.month, from: lastDay), calendar.component(.month, from: month))
                    } else {
                        XCTAssertEqual(interval, calendar.dateInterval(of: .month, for: month))
                    }
                    list.append(interval)
                    month = try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: month))
                }

                var dates = [Date]()
                for _ in 0 ..< 300 {
                    dates.append(randomDate(from: first, to: last, using: &generator))
                }
                for interval in list {
                    dates += [interval.start, interval.start.addingTimeInterval(-1), interval.end.addingTimeInterval(-0.001)]
                }
                var records = [Record]()
                for instant in dates where instant >= first && instant < last {
                    records.append(Record(date: instant, amount: Int.random(in: 1 ... 100_000, using: &generator)))
                }

                for record in records {
                    let matches = list.filter { $0.containsHalfOpen(record.date) }
                    XCTAssertEqual(matches.count, 1, "\(zone) \(record.date)")
                    XCTAssertEqual(matches.first, periods.interval(containing: record.date))
                }
                var periodSum = 0
                for interval in list {
                    periodSum += sum(records) { interval.containsHalfOpen($0) }
                }
                XCTAssertEqual(periodSum, sum(records) { _ in true })
            }
        }
    }

    // Test 4: the approved bank examples.
    func testBankExamples() throws {
        let calendar = try gregorian("Europe/Istanbul")
        let periods = MonthPeriods(calendar: calendar, cutoffDay: 20)
        let november = periods.interval(containing: try date(calendar, 2026, 11, 5))
        XCTAssertEqual(november.start, try date(calendar, 2026, 10, 21))
        XCTAssertEqual(november.end, try date(calendar, 2026, 11, 21))
        XCTAssertEqual(periods.month(containing: try date(calendar, 2026, 10, 21)), try date(calendar, 2026, 11, 1))
        XCTAssertEqual(periods.month(containing: try date(calendar, 2026, 10, 20, 23, 59, 59)), try date(calendar, 2026, 10, 1))
        XCTAssertEqual(periods.month(containing: try date(calendar, 2026, 11, 20, 23, 59, 59)), try date(calendar, 2026, 11, 1))
        XCTAssertEqual(periods.month(containing: try date(calendar, 2026, 11, 21)), try date(calendar, 2026, 12, 1))

        let local = MonthPeriods(calendar: .current, cutoffDay: 20)
        let label = AppFormat.month(local.month(containing: try date(.current, 2026, 10, 25)), language: .turkish)
        XCTAssertTrue(label.hasPrefix("Kasım"), label)
        XCTAssertTrue(
            AppFormat.periodRange(local.interval(containing: try date(.current, 2026, 11, 5)), language: .english)
                .contains("20"),
            "The range shows the cut-off day as the last day."
        )

        let overridden = MonthPeriods(calendar: calendar, mode: 1, cutoffDay: 20, overridesJSON: #"{"2026-11":18}"#)
        XCTAssertEqual(overridden.interval(containing: try date(calendar, 2026, 11, 5)), DateInterval(
            start: try date(calendar, 2026, 10, 21),
            end: try date(calendar, 2026, 11, 19)
        ))
        XCTAssertEqual(overridden.interval(containing: try date(calendar, 2026, 11, 19)), DateInterval(
            start: try date(calendar, 2026, 11, 19),
            end: try date(calendar, 2026, 12, 21)
        ))
        XCTAssertEqual(overridden.month(containing: try date(calendar, 2026, 11, 18, 23, 59, 59)), try date(calendar, 2026, 11, 1))
        XCTAssertEqual(overridden.month(containing: try date(calendar, 2026, 11, 19)), try date(calendar, 2026, 12, 1))

        for (year, lastDay) in [(2027, 28), (2028, 29)] {
            for cutoff in [29, 30, 31] {
                let periods = MonthPeriods(calendar: calendar, cutoffDay: cutoff)
                let february = periods.interval(containing: try date(calendar, year, 2, 15))
                XCTAssertEqual(february.end, try date(calendar, year, 3, 1), "cut-off \(cutoff) in \(year)")
                XCTAssertEqual(calendar.component(.day, from: february.end.addingTimeInterval(-1)), min(cutoff, lastDay))
                XCTAssertEqual(periods.month(containing: try date(calendar, year, 2, lastDay, 12, 0, 0)), try date(calendar, year, 2, 1))
            }
        }
    }

    // "Önceki aya say": the record counts in the period month before the period month of its real date.
    func testPreviousMonthUsesThePeriodMonthBeforeTheRealDate() throws {
        let calendar = try gregorian("Europe/Istanbul")
        let calendarMonths = MonthPeriods(calendar: calendar)
        let november = try date(calendar, 2026, 11, 1)
        let december = try date(calendar, 2026, 12, 1)

        // Same month: the salary comes on 28 November. With the switch off it stays in November.
        let sameMonth = try date(calendar, 2026, 11, 28, 9)
        XCTAssertEqual(calendarMonths.countedMonth(of: sameMonth, previous: false), november)
        XCTAssertTrue(calendarMonths.countedRange(from: november).contains(sameMonth, previous: false))
        // Late: the November salary comes on 2 December. With the switch on it counts in November only.
        let late = try date(calendar, 2026, 12, 2, 9)
        XCTAssertEqual(calendarMonths.countedMonth(of: late, previous: true), november)
        XCTAssertTrue(calendarMonths.countedRange(from: november).contains(late, previous: true))
        XCTAssertFalse(calendarMonths.countedRange(from: december).contains(late, previous: true))
        // Switch off: the same date counts in December.
        XCTAssertEqual(calendarMonths.countedMonth(of: late, previous: false), december)
        XCTAssertFalse(calendarMonths.countedRange(from: november).contains(late, previous: false))
        XCTAssertTrue(calendarMonths.countedRange(from: december).contains(late, previous: false))

        // Year end: the December salary comes on 4 January.
        let january = try date(calendar, 2027, 1, 4, 9)
        XCTAssertEqual(calendarMonths.countedMonth(of: january, previous: true), december)
        XCTAssertTrue(calendarMonths.countedRange(from: december).contains(january, previous: true))
        let year2026 = AnalysisPeriod.year.countedRange(containing: november, in: calendarMonths)
        let year2027 = AnalysisPeriod.year.countedRange(containing: try date(calendar, 2027, 6, 1), in: calendarMonths)
        XCTAssertTrue(year2026.contains(january, previous: true))
        XCTAssertFalse(year2027.contains(january, previous: true))
        XCTAssertTrue(year2027.contains(january, previous: false))
        // A week uses the real date only.
        let week = AnalysisPeriod.week.countedRange(containing: january, in: calendarMonths)
        XCTAssertTrue(week.contains(january, previous: true))
        XCTAssertTrue(week.contains(january, previous: false))
        XCTAssertTrue(AnalysisPeriod.month.countedRange(containing: november, in: calendarMonths).contains(late, previous: true))

        // "Ay dönemi" with cut-off day 20: 22 November is in the December period, so it counts in November.
        let statement = MonthPeriods(calendar: calendar, cutoffDay: 20)
        let afterCutoff = try date(calendar, 2026, 11, 22, 9)
        XCTAssertEqual(statement.countedMonth(of: afterCutoff, previous: true), november)
        XCTAssertTrue(statement.countedRange(from: november).contains(afterCutoff, previous: true))
        XCTAssertFalse(statement.countedRange(from: december).contains(afterCutoff, previous: true))
        // 19 November is in the November period, so it counts in October.
        let beforeCutoff = try date(calendar, 2026, 11, 19, 9)
        XCTAssertEqual(statement.countedMonth(of: beforeCutoff, previous: true), try date(calendar, 2026, 10, 1))
        // A monthly exception moves the boundary: with 18 for November, 19 November is in the December period.
        let overridden = MonthPeriods(calendar: calendar, cutoffDay: 20, overrides: ["2026-11": 18])
        XCTAssertEqual(overridden.countedMonth(of: beforeCutoff, previous: true), november)
        XCTAssertTrue(overridden.countedRange(from: november).contains(beforeCutoff, previous: true))
    }

    // With random settings and switches, each record counts in exactly one month: the one of `countedMonth`.
    func testPreviousMonthRangesPartitionRecords() throws {
        var generator = SplitMix64(state: 11)
        for zone in zones + ["America/Santiago"] {
            let calendar = try gregorian(zone)
            let first = try date(calendar, 2026, 1, 1)
            let last = try date(calendar, 2028, 1, 1)
            for round in 0 ..< 12 {
                let periods = MonthPeriods(
                    calendar: calendar,
                    mode: round % 3 == 0 ? 0 : 1,
                    cutoffDay: Int.random(in: 1 ... 31, using: &generator),
                    overridesJSON: MonthPeriods.encode([
                        MonthPeriods(calendar: calendar).key(for: randomDate(from: first, to: last, using: &generator)):
                            Int.random(in: 1 ... 31, using: &generator)
                    ])
                )
                var months = [periods.month(containing: first)]
                while let month = months.last, month < last {
                    months.append(try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: month)))
                }
                let ranges = months.map { ($0, periods.countedRange(from: $0)) }
                // Dates from the second month on, so that the month before is also in the list.
                let start = periods.interval(containing: months[1]).start
                let end = periods.interval(containing: months[months.count - 2]).end
                for _ in 0 ..< 200 {
                    let instant = randomDate(from: start, to: end, using: &generator)
                    let previous = Bool.random(using: &generator)
                    let matches = ranges.filter { $0.1.contains(instant, previous: previous) }.map(\.0)
                    XCTAssertEqual(matches, [periods.countedMonth(of: instant, previous: previous)], "\(zone) \(instant)")
                }
            }
        }
    }

    func testOverridesJSONDropsInvalidValues() {
        XCTAssertEqual(MonthPeriods.decode(#"{"2026-11":18,"2026-13":5,"bad":4,"2026-12":0,"2027-01":32}"#), ["2026-11": 18])
        XCTAssertEqual(MonthPeriods.decode("not json"), [:])
        XCTAssertEqual(MonthPeriods.encode(["2026-11": 18, "2026-02": 3]), #"{"2026-02":3,"2026-11":18}"#)
        XCTAssertEqual(MonthPeriods(mode: 1, cutoffDay: 99, overridesJSON: "{}").cutoffDay, 31)
        XCTAssertNil(MonthPeriods(mode: 0, cutoffDay: 20, overridesJSON: #"{"2026-11":18}"#).cutoffDay)
    }

    // Test 5: monthly budgets follow the statement period only in custom mode.
    func testBudgetIntervals() throws {
        var generator = SplitMix64(state: 5)
        let calendar = Calendar.current
        let base = try date(calendar, 2026, 1, 1)
        for _ in 0 ..< 300 {
            let start = randomDate(from: base, to: base.addingTimeInterval(3 * 365 * 86_400), using: &generator)
            let reference = start.addingTimeInterval(Double(Int.random(in: -30 * 86_400 ... 2 * 365 * 86_400, using: &generator)))
            let custom = MonthPeriods(
                calendar: calendar,
                cutoffDay: Int.random(in: 1 ... 31, using: &generator),
                overrides: [MonthPeriods(calendar: calendar).key(for: reference): Int.random(in: 1 ... 31, using: &generator)]
            )
            for type in 1 ... 4 {
                let legacy = Legacy.budgetInterval(start: start, type: type, reference: reference)
                XCTAssertEqual(budgetInterval(start: start, type: type, reference: reference), legacy)
                XCTAssertEqual(budgetInterval(start: start, type: type, reference: reference, periods: MonthPeriods(calendar: calendar)), legacy)
                let interval = budgetInterval(start: start, type: type, reference: reference, periods: custom)
                XCTAssertEqual(interval, type == 3 ? custom.interval(containing: max(reference, start)) : legacy)
            }
        }

        let statement = MonthPeriods(calendar: calendar, cutoffDay: 20)
        XCTAssertEqual(
            budgetInterval(start: try date(calendar, 2026, 9, 5, 15, 0, 0), type: 3, reference: try date(calendar, 2026, 11, 18), periods: statement),
            DateInterval(start: try date(calendar, 2026, 10, 21), end: try date(calendar, 2026, 11, 21))
        )
    }
}

@MainActor
final class MonthPeriodDataTests: XCTestCase {
    private static let keys = MonthPeriods.Keys.all + ["widget.monthExpense"]
    private var savedSettings = [String: Any]()

    override func setUp() async throws {
        savedSettings = Self.keys.reduce(into: [:]) { $0[$1] = UserDefaults.tutar.object(forKey: $1) }
    }

    override func tearDown() async throws {
        for key in Self.keys {
            UserDefaults.tutar.set(savedSettings[key], forKey: key)
        }
    }

    // Test 3: setting changes keep every record and every field, and leave the context clean.
    func testSwitchingPeriodSettingsChangesNoRecord() async throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(controller)
        let categories = try controller.context.fetch(Tutar.Category.fetchRequest())
        var generator = SplitMix64(state: 37)
        let start = Date.now.addingTimeInterval(-400 * 86_400)
        for index in 0 ..< 60 {
            let category = try XCTUnwrap(categories.randomElement(using: &generator))
            try controller.createTransaction(
                note: "Record \(index)",
                category: category,
                income: category.income,
                amountMinorUnits: Int64.random(in: 1 ... 500_000, using: &generator),
                date: randomDate(from: start, to: start.addingTimeInterval(800 * 86_400), using: &generator)
            )
        }
        let market = try XCTUnwrap(categories.first { !$0.income })
        try controller.createInstallments(
            note: "Phone", category: market, income: false, totalMinorUnits: 120_000, count: 6,
            firstDate: start, intervalMonths: 1
        )
        try controller.saveOverallBudget(amountMinorUnits: 900_000, type: 3, startDate: start)
        XCTAssertFalse(controller.context.hasChanges)
        let before = try snapshot(controller)
        XCTAssertGreaterThanOrEqual(before.filter { $0.hasPrefix("Transaction:") }.count, 66)

        for round in 0 ..< 30 {
            let defaults = UserDefaults.tutar
            defaults.set(round % 2, forKey: MonthPeriods.Keys.mode)
            defaults.set(Int.random(in: 1 ... 31, using: &generator), forKey: MonthPeriods.Keys.cutoffDay)
            let overrides = round % 3 == 0 ? [:] : [
                MonthPeriods.stored().key(for: Date.now): Int.random(in: 1 ... 31, using: &generator)
            ]
            defaults.set(MonthPeriods.encode(overrides), forKey: MonthPeriods.Keys.overrides)
            // The settings screen does this after each change.
            controller.updateWidgetSnapshot()

            let periods = MonthPeriods.stored()
            let transactions = try controller.context.fetch(Transaction.fetchRequest())
            let total = transactions.reduce(0) { $0 + $1.amountMinorUnits }
            let byPeriod = Dictionary(grouping: transactions) { periods.month(containing: $0.wrappedDate) }
            XCTAssertEqual(byPeriod.values.joined().reduce(0) { $0 + $1.amountMinorUnits }, total)
            XCTAssertFalse(controller.context.hasChanges, "round \(round)")
            // Compare without the large diff text in the log.
            XCTAssertTrue(try snapshot(controller) == before, "Records changed in round \(round)")
        }
    }

    // Test 6: the widget cache holds the expense total of the current period.
    func testWidgetSnapshotHoldsCurrentPeriodExpenseTotal() async throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(controller)
        let categories = try controller.context.fetch(Tutar.Category.fetchRequest())
        let expense = try XCTUnwrap(categories.first { !$0.income })
        let income = try XCTUnwrap(categories.first { $0.income })

        UserDefaults.tutar.set(1, forKey: MonthPeriods.Keys.mode)
        UserDefaults.tutar.set(20, forKey: MonthPeriods.Keys.cutoffDay)
        UserDefaults.tutar.set("{}", forKey: MonthPeriods.Keys.overrides)
        let period = MonthPeriods.stored().interval(containing: .now)
        let records: [(Date, Int64, Bool)] = [
            (period.start, 1_000, false),
            (period.end.addingTimeInterval(-1), 2_000, false),
            (period.end, 4_000, false),
            (period.start.addingTimeInterval(-1), 8_000, false),
            (period.start, 16_000, true)
        ]
        for record in records {
            try controller.createTransaction(
                note: "Widget", category: record.2 ? income : expense, income: record.2,
                amountMinorUnits: record.1, date: record.0
            )
        }
        XCTAssertEqual(UserDefaults.tutar.double(forKey: "widget.monthExpense"), 30, accuracy: 0.001)

        let settings: [(Int, Int, String)] = [(0, 31, "{}"), (1, 1, "{}"), (1, 31, "{}"), (1, 20, MonthPeriods.encode([MonthPeriods.stored().key(for: .now): 3]))]
        for setting in settings {
            UserDefaults.tutar.set(setting.0, forKey: MonthPeriods.Keys.mode)
            UserDefaults.tutar.set(setting.1, forKey: MonthPeriods.Keys.cutoffDay)
            UserDefaults.tutar.set(setting.2, forKey: MonthPeriods.Keys.overrides)
            controller.updateWidgetSnapshot()
            let current = MonthPeriods.stored().interval(containing: .now)
            let expected = try controller.context.fetch(Transaction.fetchRequest())
                .filter { !$0.income && current.containsHalfOpen($0.wrappedDate) }
                .reduce(0) { $0 + $1.amount }
            XCTAssertEqual(UserDefaults.tutar.double(forKey: "widget.monthExpense"), expected, accuracy: 0.001, "\(setting)")
        }
    }

    // "Önceki aya say" is for income only: an expense, a change to expense and a new recurring copy get false.
    func testPreviousMonthFlagIsIncomeOnly() async throws {
        let controller = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(controller)
        let categories = try controller.context.fetch(Tutar.Category.fetchRequest())
        let salary = try XCTUnwrap(categories.first { $0.income })
        let market = try XCTUnwrap(categories.first { !$0.income })
        let paid = Date.now.addingTimeInterval(-3 * 86_400)

        let expense = try controller.createTransaction(
            note: "Market", category: market, income: false, amountMinorUnits: 1_000, date: paid,
            countsInPreviousMonth: true
        )
        XCTAssertFalse(expense.countsInPreviousMonth)
        XCTAssertFalse(expense.countsInPreviousPeriod)

        let income = try controller.createTransaction(
            note: "Maaş", category: salary, income: true, amountMinorUnits: 5_000_000, date: paid,
            countsInPreviousMonth: true
        )
        XCTAssertTrue(income.countsInPreviousPeriod)
        try controller.update(
            income, note: "Maaş", category: market, income: false, amountMinorUnits: 5_000_000, date: paid,
            intervalMonths: 1, countsInPreviousMonth: true
        )
        XCTAssertFalse(income.countsInPreviousMonth, "Saving as expense clears the flag.")
        try controller.update(
            income, note: "Maaş", category: salary, income: true, amountMinorUnits: 5_000_000, date: paid,
            intervalMonths: 1, countsInPreviousMonth: true
        )
        XCTAssertTrue(income.countsInPreviousMonth)

        // A CloudKit merge can leave the flag on an expense. The read side ignores it.
        expense.countsInPreviousMonth = true
        XCTAssertFalse(expense.countsInPreviousPeriod)
        controller.context.rollback()

        // A monthly salary that started 3 months ago: the copies get false.
        let start = try XCTUnwrap(Calendar.current.date(byAdding: .month, value: -3, to: paid))
        let marker = try controller.createTransaction(
            note: "Recurring salary", category: salary, income: true, amountMinorUnits: 4_000_000, date: start,
            recurringType: 3, countsInPreviousMonth: true
        )
        XCTAssertTrue(marker.countsInPreviousMonth)
        let copies = try controller.context.fetch(Transaction.fetchRequest())
            .filter { $0.note == "Recurring salary" && $0 != marker }
        XCTAssertGreaterThanOrEqual(copies.count, 3)
        XCTAssertTrue(copies.allSatisfy { !$0.countsInPreviousMonth })
    }

    // Backup and CSV keep the flag. An old backup without the field imports with the flag off.
    func testPreviousMonthFlagRoundTripsAndOldBackupImports() async throws {
        let source = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(source)
        let salary = try XCTUnwrap(try source.context.fetch(Tutar.Category.fetchRequest()).first { $0.income })
        let paid = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 2, hour: 9)))
        try source.createTransaction(
            note: "Late salary", category: salary, income: true, amountMinorUnits: 8_000_000, date: paid,
            countsInPreviousMonth: true
        )
        try source.createTransaction(
            note: "Bonus", category: salary, income: true, amountMinorUnits: 100_000, date: paid
        )

        let backup = try source.exportBackup()
        let destination = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(destination)
        _ = try destination.importData(backup, fileExtension: "json", language: .turkish)
        try assertFlags(destination, late: true)

        let csv = try source.exportCSV(language: .english)
        XCTAssertTrue(String(decoding: csv, as: UTF8.self).contains("CountsInPreviousMonth"))
        let fromCSV = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(fromCSV)
        _ = try fromCSV.importData(csv, fileExtension: "csv", language: .english)
        try assertFlags(fromCSV, late: true)

        // A backup from version 1.1.0 (38) has no field.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        var transactions = try XCTUnwrap(json["transactions"] as? [[String: Any]])
        for index in transactions.indices { transactions[index].removeValue(forKey: "countsInPreviousMonth") }
        json["transactions"] = transactions
        let old = DataController(inMemory: true, cloudEnabled: false)
        try await waitUntilLoaded(old)
        let result = try old.importData(JSONSerialization.data(withJSONObject: json), fileExtension: "json", language: .turkish)
        XCTAssertGreaterThanOrEqual(result.imported, 2)
        try assertFlags(old, late: false)
    }

    private func assertFlags(_ controller: DataController, late: Bool, line: UInt = #line) throws {
        let transactions = try controller.context.fetch(Transaction.fetchRequest())
        let lateSalary = try XCTUnwrap(transactions.first { $0.note == "Late salary" }, line: line)
        let bonus = try XCTUnwrap(transactions.first { $0.note == "Bonus" }, line: line)
        XCTAssertEqual(lateSalary.countsInPreviousMonth, late, line: line)
        XCTAssertFalse(bonus.countsInPreviousMonth, line: line)
        XCTAssertEqual(
            lateSalary.wrappedDate,
            try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 2, hour: 9))),
            "The real date stays.", line: line
        )
    }

    // A version 6 store gets the new field with the value false.
    func testVersionSixStoreMigratesWithPreviousMonthOff() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TutarPreviousMonth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Main.sqlite")
        let modelDirectory = try XCTUnwrap(Bundle.main.url(forResource: "MainModel", withExtension: "momd"))
        let oldModel = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelDirectory.appendingPathComponent("MainModel 6.mom")))
        XCTAssertNil(oldModel.entitiesByName["Transaction"]?.attributesByName["countsInPreviousMonth"])
        let oldContainer = NSPersistentContainer(name: "MainModel", managedObjectModel: oldModel)
        oldContainer.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        var loadError: Error?
        oldContainer.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)
        let old = NSEntityDescription.insertNewObject(forEntityName: "Transaction", into: oldContainer.viewContext)
        old.setValue(UUID(), forKey: "id")
        old.setValue("Salary v6", forKey: "note")
        old.setValue(true, forKey: "income")
        old.setValue(50.0, forKey: "amount")
        old.setValue(Date(timeIntervalSince1970: 1_790_000_000), forKey: "date")
        try oldContainer.viewContext.save()
        try oldContainer.persistentStoreCoordinator.persistentStores.forEach {
            try oldContainer.persistentStoreCoordinator.remove($0)
        }

        let migrated = DataController(storeURL: storeURL, cloudEnabled: false)
        try await waitUntilLoaded(migrated)
        let salary = try XCTUnwrap(try migrated.context.fetch(Transaction.fetchRequest()).first { $0.note == "Salary v6" })
        XCTAssertFalse(salary.countsInPreviousMonth)
        XCTAssertEqual(salary.amount, 50, accuracy: 0.001)
        for store in migrated.container.persistentStoreCoordinator.persistentStores {
            try migrated.container.persistentStoreCoordinator.remove(store)
        }
    }

    /// Every attribute and relationship of every object, as text.
    private func snapshot(_ controller: DataController) throws -> [String] {
        try controller.container.managedObjectModel.entities.filter { !$0.isAbstract }.compactMap(\.name).sorted().flatMap { name in
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.includesSubentities = false
            return try controller.context.fetch(request).map { object in
                let attributes = object.entity.attributesByName.keys.sorted().map { key -> String in
                    let value = object.value(forKey: key)
                    return "\(key)=\((value as? UUID)?.uuidString ?? String(describing: value))"
                }
                let relationships = object.entity.relationshipsByName.keys.sorted().map { key -> String in
                    let value = object.value(forKey: key)
                    let objects = (value as? NSManagedObject).map { [$0] }
                        ?? (value as? NSSet)?.allObjects as? [NSManagedObject]
                        ?? (value as? NSOrderedSet)?.array as? [NSManagedObject]
                        ?? []
                    return "\(key)=\(objects.map { $0.objectID.uriRepresentation().absoluteString }.sorted())"
                }
                return "\(name): " + (attributes + relationships).joined(separator: "|")
            }
            .sorted()
        }
    }

    private func waitUntilLoaded(_ controller: DataController) async throws {
        for _ in 0 ..< 100 where !controller.isStoreLoaded && controller.loadError == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        if let error = controller.loadError { throw error }
        XCTAssertTrue(controller.isStoreLoaded)
    }
}
