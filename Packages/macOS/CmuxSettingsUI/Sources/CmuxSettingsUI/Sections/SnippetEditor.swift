import SwiftUI

/// Sheet for creating or editing one snippet. `snippet == nil` means Add.
@MainActor
struct SnippetEditor: View {
    private let existingID: String?
    private let onSave: (SnippetSettingsDraft, String?) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var category: String
    @State private var text: String
    @State private var submit: Bool
    @State private var isSaving = false

    init(
        snippet: SnippetSettingsItem?,
        onSave: @escaping (SnippetSettingsDraft, String?) async -> Bool
    ) {
        existingID = snippet?.id
        self.onSave = onSave
        _title = State(initialValue: snippet?.title ?? "")
        _category = State(initialValue: snippet?.category ?? "")
        _text = State(initialValue: snippet?.text ?? "")
        _submit = State(initialValue: snippet?.submit ?? false)
    }

    var body: some View {
        Form {
            TextField(
                String(localized: "settings.snippets.editor.title", defaultValue: "Title"),
                text: $title
            )
            TextField(
                String(localized: "settings.snippets.editor.category", defaultValue: "Category"),
                text: $category,
                prompt: Text(String(localized: "settings.snippets.editor.categoryPrompt", defaultValue: "Optional"))
            )
            Section(String(localized: "settings.snippets.editor.text", defaultValue: "Text")) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 160)
                    .accessibilityLabel(String(localized: "settings.snippets.editor.text", defaultValue: "Text"))
            }
            Toggle(
                String(localized: "settings.snippets.editor.submit", defaultValue: "Press Enter after inserting"),
                isOn: $submit
            )
            Text(String(
                localized: "settings.snippets.editor.submitNote",
                defaultValue: "Off: the text waits at the prompt for you to edit or confirm. On: it runs or submits immediately."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 440)
        .navigationTitle(existingID == nil
            ? String(localized: "settings.snippets.editor.add", defaultValue: "Add Snippet")
            : String(localized: "settings.snippets.editor.edit", defaultValue: "Edit Snippet"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "settings.common.cancel", defaultValue: "Cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "settings.common.save", defaultValue: "Save")) { save() }
                    .disabled(!isValid || isSaving)
            }
        }
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard isValid, !isSaving else { return }
        isSaving = true
        let draft = SnippetSettingsDraft(
            title: title,
            category: category,
            text: text,
            submit: submit
        )
        Task {
            if await onSave(draft, existingID) { dismiss() }
            isSaving = false
        }
    }
}
