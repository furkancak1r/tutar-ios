// Copyright © 2026 Furkan Çakır. Licensed under GPLv3.

import CoreData
import SwiftUI
import UIKit

struct CategoriesView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Category.order, ascending: true)],
        animation: .default
    ) private var categories: FetchedResults<Category>
    @EnvironmentObject private var dataController: DataController
    @Environment(\.appLanguage) private var language
    @State private var showingNew = false
    @State private var showingIncome = false
    @State private var editing: Category?
    @State private var deleting: Category?
    @State private var errorMessage = ""

    private var selectedCategories: [Category] {
        categories.filter { $0.income == showingIncome }
    }

    private var availableSuggestions: [CategorySuggestion] {
        Self.suggestions.filter { suggestion in
            suggestion.income == showingIncome && !categories.contains { category in
                category.income == suggestion.income
                    && (category.systemKey == suggestion.key
                        || category.displayName(language: language).localizedCaseInsensitiveCompare(
                            AppFormat.localized(suggestion.key, language: language)
                        ) == .orderedSame)
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("categories.type", selection: $showingIncome) {
                    Text("editor.expense").tag(false)
                    Text("editor.income").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("categoryTypePicker")
            }

            categorySection("categories.yours.section", items: selectedCategories)

            Section {
                if availableSuggestions.isEmpty {
                    Text("categories.suggested.empty")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availableSuggestions) { suggestion in
                        Button {
                            add(suggestion)
                        } label: {
                            HStack(spacing: 12) {
                                Text(verbatim: suggestion.emoji)
                                    .font(.title3)
                                    .frame(width: 28)
                                Text(verbatim: AppFormat.localized(suggestion.key, language: language))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.primary)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("suggestedCategory-\(suggestion.key)")
                        .accessibilityLabel(Text(verbatim: String(
                            format: AppFormat.localized("categories.suggested.add", language: language),
                            AppFormat.localized(suggestion.key, language: language)
                        )))
                    }
                }
            } header: {
                Text("categories.suggested.section")
            } footer: {
                Text("categories.suggested.footer")
            }
        }
        .navigationTitle("categories.title")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNew = true
                } label: {
                    Label("categories.add", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingNew) {
            CategoryEditorView()
        }
        .sheet(item: $editing) { category in
            CategoryEditorView(
                category: category,
                initialName: category.displayName(language: language)
            )
        }
        .confirmationDialog("categories.delete.title", isPresented: deleteBinding, titleVisibility: .visible) {
            Button("action.delete", role: .destructive, action: performDelete)
            Button("action.cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("categories.delete.message")
        }
        .alert("error.save.title", isPresented: errorBinding) {
            Button("action.ok") { errorMessage = "" }
        } message: {
            Text(verbatim: errorMessage)
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })
    }

    private func categorySection(_ title: LocalizedStringKey, items: [Category]) -> some View {
        Section(title) {
            ForEach(items) { category in
                HStack(spacing: 12) {
                    Text(verbatim: category.wrappedEmoji)
                        .font(.title3)
                        .frame(width: 28)
                    Text(verbatim: category.displayName(language: language))
                    Spacer()
                    Circle()
                        .fill(Color(hex: category.colour ?? "#232326"))
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .onTapGesture { editing = category }
                .accessibilityIdentifier("categoryRow-\(category.systemKey ?? category.objectID.uriRepresentation().absoluteString)")
                .swipeActions {
                    Button(role: .destructive) { deleting = category } label: {
                        Label("action.delete", systemImage: "trash")
                    }
                    Button { editing = category } label: {
                        Label("action.edit", systemImage: "pencil")
                    }
                    .tint(.accentColor)
                }
            }
            .onMove { source, destination in
                var reordered = items
                reordered.move(fromOffsets: source, toOffset: destination)
                do {
                    try dataController.reorderCategories(reordered)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func performDelete() {
        guard let deleting else { return }
        do {
            try dataController.deleteCategory(deleting)
        } catch {
            errorMessage = error.localizedDescription
        }
        self.deleting = nil
    }

    private func add(_ suggestion: CategorySuggestion) {
        do {
            try dataController.saveCategory(
                name: suggestion.key,
                emoji: suggestion.emoji,
                colour: suggestion.colour,
                income: suggestion.income,
                systemKey: suggestion.key
            )
        } catch {
            errorMessage = AppFormat.localized("categories.error.add", language: language)
        }
    }

    private static let suggestions = [
        CategorySuggestion(key: "category.market", emoji: "🛒", colour: "#9B554D", income: false),
        CategorySuggestion(key: "category.food", emoji: "🍽️", colour: "#9A7B4F", income: false),
        CategorySuggestion(key: "category.transport", emoji: "🚇", colour: "#5F6B5C", income: false),
        CategorySuggestion(key: "category.bills", emoji: "🧾", colour: "#5C5A57", income: false),
        CategorySuggestion(key: "category.shopping", emoji: "🛍️", colour: "#7A6068", income: false),
        CategorySuggestion(key: "category.health", emoji: "🩺", colour: "#87504D", income: false),
        CategorySuggestion(key: "category.entertainment", emoji: "🎟️", colour: "#736A62", income: false),
        CategorySuggestion(key: "category.housing", emoji: "🏠", colour: "#6B6258", income: false),
        CategorySuggestion(key: "category.education", emoji: "🎓", colour: "#5C6674", income: false),
        CategorySuggestion(key: "category.travel", emoji: "✈️", colour: "#5F6771", income: false),
        CategorySuggestion(key: "category.insurance", emoji: "🛡️", colour: "#555F66", income: false),
        CategorySuggestion(key: "category.pets", emoji: "🐾", colour: "#78645A", income: false),
        CategorySuggestion(key: "category.personalCare", emoji: "🧴", colour: "#80616F", income: false),
        CategorySuggestion(key: "category.subscriptions", emoji: "🔁", colour: "#62626E", income: false),
        CategorySuggestion(key: "category.taxes", emoji: "🧮", colour: "#6B5B54", income: false),
        CategorySuggestion(key: "category.salary", emoji: "💼", colour: "#4F705F", income: true),
        CategorySuggestion(key: "category.freelance", emoji: "🧑‍💻", colour: "#4F665E", income: true),
        CategorySuggestion(key: "category.bonus", emoji: "🎉", colour: "#6D6551", income: true),
        CategorySuggestion(key: "category.investment", emoji: "📈", colour: "#526C63", income: true),
        CategorySuggestion(key: "category.rentalIncome", emoji: "🏡", colour: "#5C6757", income: true),
        CategorySuggestion(key: "category.refund", emoji: "↩️", colour: "#5C666B", income: true),
        CategorySuggestion(key: "category.otherIncome", emoji: "💰", colour: "#5C6657", income: true)
    ]
}

private struct CategorySuggestion: Identifiable {
    let key: String
    let emoji: String
    let colour: String
    let income: Bool

    var id: String { key }
}

private struct CategoryEditorView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language

    let category: Category?
    let initialName: String

    @State private var name: String
    @State private var emoji: String
    @State private var colour: String
    @State private var income: Bool
    @State private var errorKey: String?

    private let colours = [
        "#232326", "#5C5A57", "#736A62", "#5F6B5C",
        "#9A7B4F", "#9B554D", "#7A6068", "#8E8E93"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("categories.details.section") {
                    TextField("categories.name", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("categoryNameField")
                    EmojiKeyboardField(
                        text: $emoji,
                        placeholder: AppFormat.localized("categories.emoji", language: language)
                    )
                    Picker("editor.type.label", selection: $income) {
                        Text("editor.expense").tag(false)
                        Text("editor.income").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(category != nil)
                }

                Section("categories.colour.section") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(colours, id: \.self) { option in
                            Button {
                                colour = option
                            } label: {
                                Circle()
                                    .fill(Color(hex: option))
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if colour == option {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("categories.colour"))
                            .accessibilityValue(Text(verbatim: option))
                            .accessibilityAddTraits(colour == option ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                }

                if let errorKey {
                    Section {
                        Label(LocalizedStringKey(errorKey), systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(category == nil ? "categories.new.title" : "categories.edit.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save", action: save)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    init(category: Category? = nil, initialName: String = "") {
        self.category = category
        self.initialName = initialName
        _name = State(initialValue: initialName)
        _emoji = State(initialValue: category?.emoji ?? "")
        _colour = State(initialValue: category?.colour ?? "#232326")
        _income = State(initialValue: category?.income ?? false)
    }

    private func save() {
        do {
            try dataController.saveCategory(
                category,
                name: name,
                emoji: emoji,
                colour: colour,
                income: income,
                replacesSystemName: category?.systemKey != nil && name != initialName
            )
            dismiss()
        } catch CategoryError.invalidName {
            errorKey = "categories.error.name"
        } catch CategoryError.invalidEmoji {
            errorKey = "categories.error.emoji"
        } catch CategoryError.duplicate {
            errorKey = "categories.error.duplicate"
        } catch {
            errorKey = "editor.error.save"
        }
    }
}

private struct EmojiKeyboardField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> EmojiKeyboardTextField {
        let field = EmojiKeyboardTextField()
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.accessibilityIdentifier = "categoryEmojiField"
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: EmojiKeyboardTextField, context: Context) {
        if field.text != text { field.text = text }
        field.placeholder = placeholder
    }

    final class Coordinator: NSObject {
        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func textChanged(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }
    }
}

private final class EmojiKeyboardTextField: UITextField {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}
