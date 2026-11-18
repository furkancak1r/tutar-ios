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
