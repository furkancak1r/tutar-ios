// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import CoreData
import SwiftUI

struct InstallmentsView: View {
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Transaction.installmentGroupID, ascending: true),
            NSSortDescriptor(keyPath: \Transaction.installmentIndex, ascending: true)
        ],
        predicate: NSPredicate(format: "installmentGroupID != nil AND installmentIndex > 0"),
        animation: .default
    ) private var installments: FetchedResults<Transaction>
    @EnvironmentObject private var dataController: DataController
    @Environment(\.appLanguage) private var language
    @AppStorage("currencyCode", store: .tutar) private var preferredCurrency = ""
    @State private var editing: Transaction?
    @State private var deleting: Transaction?
    @State private var errorMessage = ""

    private var groups: [[Transaction]] {
        Dictionary(grouping: installments) { $0.installmentGroupID ?? UUID() }
            .values
            .map { $0.sorted { $0.installmentIndex < $1.installmentIndex } }
            .sorted { ($0.first?.wrappedDate ?? .distantPast) > ($1.first?.wrappedDate ?? .distantPast) }
    }

    var body: some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label("empty.installments.title", systemImage: "square.stack.3d.up")
                } description: {
                    Text("empty.installments.message")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(groups, id: \.first?.installmentGroupID) { group in
                            InstallmentGroupCard(
                                items: group,
                                edit: { editing = $0 },
                                delete: { deleting = $0 }
                            )
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("installments.title")
        .sheet(item: $editing) { TransactionEditorView(transaction: $0) }
        .confirmationDialog("delete.installment.title", isPresented: deleteDialogBinding, titleVisibility: .visible) {
            Button("delete.one", role: .destructive) { performDelete(.one) }
            Button("delete.following", role: .destructive) { performDelete(.thisAndFollowing) }
            Button("action.cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("delete.installment.message")
        }
        .alert("error.save.title", isPresented: .constant(errorMessage.isEmpty == false)) {
            Button("action.ok") { errorMessage = "" }
        } message: {
            Text(verbatim: errorMessage)
        }
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private func performDelete(_ scope: EditScope) {
        guard let deleting else { return }
        do {
            try dataController.delete(deleting, scope: scope)
        } catch {
            errorMessage = error.localizedDescription
        }
        self.deleting = nil
    }
}

private struct InstallmentGroupCard: View {
    @Environment(\.appLanguage) private var language
    @AppStorage("currencyCode", store: .tutar) private var preferredCurrency = ""
    let items: [Transaction]
    let edit: (Transaction) -> Void
    let delete: (Transaction) -> Void

    private var total: Double { items.reduce(0) { $0 + $1.amount } }
    private var completed: Int { items.filter { $0.wrappedDate <= Date.now }.count }
    private var next: Transaction? { items.first { $0.wrappedDate > Date.now } }
    private var formattedTotal: String {
        AppFormat.money(
            total,
            language: language,
            currencyCode: AppFormat.currencyCode(language: language, preferred: preferredCurrency)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: items.first?.displayNote(language: language) ?? "")
                        .font(.title3.bold())
                    Text(items.first?.category?.displayName(language: language) ?? AppFormat.localized("category.uncategorized", language: language))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formattedTotal)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .accessibilityLabel(Text("accessibility.totalAmount"))
                .accessibilityValue(Text(verbatim: formattedTotal))
            }

            ProgressView(value: Double(completed), total: Double(max(items.count, 1)))
                .tint(.tutarMint)
                .accessibilityLabel(Text("installments.progress"))
                .accessibilityValue(Text(verbatim: "\(completed)/\(items.count)"))

            HStack {
                Label {
                    Text(verbatim: AppFormat.plural("installments.completed", count: completed, language: language))
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                Spacer()
                if let next {
                    Label {
                        Text(AppFormat.date(next.wrappedDate, language: language))
                    } icon: {
                        Image(systemName: "calendar")
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Divider()

            ForEach(items) { item in
                TransactionRow(transaction: item)
                    .contentShape(Rectangle())
                    .onTapGesture { edit(item) }
                    .contextMenu {
                        Button { edit(item) } label: { Label("action.edit", systemImage: "pencil") }
                        Button(role: .destructive) { delete(item) } label: { Label("action.delete", systemImage: "trash") }
                    }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.tutarMint)
                .frame(width: 42, height: 5)
                .padding(.leading, 18)
        }
    }
}
