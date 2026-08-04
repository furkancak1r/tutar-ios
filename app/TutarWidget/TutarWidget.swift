// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import SwiftUI
import WidgetKit

private let appGroup = "group.com.furkancakir.tutar"

private struct TutarEntry: TimelineEntry {
    let date: Date
    let monthExpense: Double
    let nextNote: String?
    let nextCategoryKey: String?
    let nextCategoryName: String?
    let nextDate: Date?
    let nextIndex: Int
    let nextCount: Int
}

private struct TutarProvider: TimelineProvider {
    func placeholder(in _: Context) -> TutarEntry {
        TutarEntry(
            date: .now,
            monthExpense: 3_000,
            nextNote: "",
            nextCategoryKey: "category.shopping",
            nextCategoryName: nil,
            nextDate: .now,
            nextIndex: 1,
            nextCount: 3
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (TutarEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<TutarEntry>) -> Void) {
        let current = entry()
        let refresh = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [current], policy: .after(refresh)))
    }

    private func entry() -> TutarEntry {
        let defaults = UserDefaults(suiteName: appGroup) ?? .standard
        return TutarEntry(
            date: .now,
            monthExpense: defaults.double(forKey: "widget.monthExpense"),
            nextNote: defaults.string(forKey: "widget.nextNote"),
            nextCategoryKey: defaults.string(forKey: "widget.nextCategoryKey"),
            nextCategoryName: defaults.string(forKey: "widget.nextCategoryName"),
            nextDate: defaults.object(forKey: "widget.nextDate") as? Date,
            nextIndex: defaults.integer(forKey: "widget.nextIndex"),
            nextCount: defaults.integer(forKey: "widget.nextCount")
        )
    }
}

private struct TutarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TutarEntry

    private var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    private var locale: Locale {
        switch defaults.string(forKey: "appLanguage") {
        case "tr": Locale(identifier: "tr_TR")
        case "en": Locale(identifier: "en_\(Locale.current.region?.identifier ?? "US")")
        default: .autoupdatingCurrent
        }
    }

    private var currencyCode: String {
        locale.language.languageCode?.identifier == "tr"
            ? "TRY"
            : (defaults.string(forKey: "currencyCode") ?? Locale.current.currency?.identifier ?? "USD")
    }

    private var expense: String {
        entry.monthExpense.formatted(.currency(code: currencyCode).locale(locale))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundStyle(Color(red: 47 / 255, green: 107 / 255, blue: 1))
                Text("widget.title")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(expense)
                .font(.title2.bold().monospacedDigit())
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            if family == .systemMedium {
                Divider()
                if let date = entry.nextDate {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("widget.next")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            nextTitle
                                .font(.subheadline.bold())
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: "\(entry.nextIndex)/\(entry.nextCount)")
                                .font(.caption.bold())
                            Text(date, format: .dateTime.day().month(.abbreviated).locale(locale))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("widget.none")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
        .environment(\.locale, locale)
        .widgetURL(URL(string: "tutar://add"))
    }

    @ViewBuilder
    private var nextTitle: some View {
        if let note = entry.nextNote, !note.isEmpty {
            Text(verbatim: note)
        } else if let key = entry.nextCategoryKey, !key.isEmpty {
            Text(LocalizedStringKey(key))
        } else {
            Text(verbatim: entry.nextCategoryName ?? "—")
        }
    }
}

private struct TutarSummaryWidget: Widget {
    let kind = "TutarSummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TutarProvider()) { entry in
            TutarWidgetView(entry: entry)
        }
        .configurationDisplayName("widget.title")
        .description("widget.open")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct TutarWidgets: WidgetBundle {
    var body: some Widget {
        TutarSummaryWidget()
    }
}
