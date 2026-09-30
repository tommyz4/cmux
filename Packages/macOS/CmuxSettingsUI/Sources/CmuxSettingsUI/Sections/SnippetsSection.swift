import SwiftUI

/// Settings > Snippets: list, add, edit, and remove `type: "text"` actions
/// stored in the global cmux.json. Project-local snippets are listed
/// read-only so the user can see everything the right-click menu offers.
@MainActor
public struct SnippetsSection: View {
    @State private var model: SnippetSettingsModel
    @State private var showsEditor = false
    @State private var editedSnippetID: String?
    @State private var pendingRemovalID: String?

    public init(hostActions: SettingsHostActions) {
        _model = State(initialValue: SnippetSettingsModel(controller: hostActions.snippetSettingsController()))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(
                String(localized: "settings.section.snippets", defaultValue: "Snippets"),
                section: .snippets
            )
            SettingsCard {
                SettingsCardRow(
                    configurationReview: .json("actions"),
                    searchAnchorID: "setting:snippets:add",
                    String(localized: "settings.snippets.addRow.title", defaultValue: "New Snippet"),
                    subtitle: String(
                        localized: "settings.snippets.addRow.subtitle",
                        defaultValue: "Reusable text you can insert from the terminal's right-click Snippets menu or the Command Palette."
                    )
                ) {
                    Button(String(localized: "settings.snippets.add", defaultValue: "Add…")) {
                        editedSnippetID = nil
                        showsEditor = true
                    }
                    .disabled(!model.isAvailable || model.isMutating)
                }
                if model.items.isEmpty {
                    SettingsCardDivider()
                    SettingsCardNote(
                        String(
                            localized: "settings.snippets.empty",
                            defaultValue: "No snippets yet. Add one and it appears under Snippets in the terminal's right-click menu."
                        )
                    )
                } else {
                    ForEach(model.sections) { section in
                        ForEach(section.items) { item in
                            SettingsCardDivider()
                            snippetRow(item, in: section)
                        }
                    }
                }
            }
            SettingsCardNote(
                String(
                    localized: "settings.snippets.note",
                    defaultValue: "Snippets are saved as \"text\" actions in cmux.json. Snippets from a project's .cmux/cmux.json are shown here but can only be changed in that file."
                )
            )
        }
        .task { await model.observe() }
        .sheet(isPresented: $showsEditor) {
            NavigationStack {
                SnippetEditor(snippet: editedSnippet) { draft, id in
                    await model.save(draft, replacing: id)
                }
            }
        }
        .alert(
            String(localized: "settings.snippets.saveFailed", defaultValue: "Could Not Save Snippet"),
            isPresented: Binding(
                get: { model.lastErrorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button(String(localized: "settings.common.ok", defaultValue: "OK"), role: .cancel) {}
        } message: {
            Text(model.lastErrorMessage ?? "")
        }
        .confirmationDialog(
            String(localized: "settings.snippets.remove.confirm", defaultValue: "Remove this snippet?"),
            isPresented: Binding(
                get: { pendingRemovalID != nil },
                set: { if !$0 { pendingRemovalID = nil } }
            )
        ) {
            Button(String(localized: "settings.common.remove", defaultValue: "Remove"), role: .destructive) {
                if let id = pendingRemovalID {
                    Task { _ = await model.delete(id: id) }
                }
                pendingRemovalID = nil
            }
        }
    }

    private var editedSnippet: SnippetSettingsItem? {
        guard let editedSnippetID else { return nil }
        return model.items.first { $0.id == editedSnippetID }
    }

    private func snippetRow(_ item: SnippetSettingsItem, in section: SnippetSettingsSection) -> some View {
        SettingsCardRow(
            configurationReview: .json("actions.\(item.id)"),
            searchAnchorID: "setting:snippets:\(item.id)",
            item.title,
            subtitle: subtitle(for: item, in: section)
        ) {
            HStack(spacing: 6) {
                Button(String(localized: "settings.common.edit", defaultValue: "Edit")) {
                    editedSnippetID = item.id
                    showsEditor = true
                }
                Button(role: .destructive) {
                    pendingRemovalID = item.id
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(String(localized: "settings.common.remove", defaultValue: "Remove"))
            }
            .buttonStyle(.bordered)
            .disabled(!item.isEditable || model.isMutating)
        }
    }

    private func subtitle(for item: SnippetSettingsItem, in section: SnippetSettingsSection) -> String {
        var parts: [String] = []
        parts.append(section.category ?? String(localized: "settings.snippets.uncategorized", defaultValue: "No category"))
        if item.submit {
            parts.append(String(localized: "settings.snippets.submitHint", defaultValue: "Presses Enter"))
        }
        if !item.isEditable {
            parts.append(String(localized: "settings.snippets.readOnly", defaultValue: "Defined in project config"))
        }
        let preview = item.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if !preview.isEmpty {
            parts.append(preview.count > 60 ? String(preview.prefix(60)) + "…" : preview)
        }
        return parts.joined(separator: " · ")
    }
}
