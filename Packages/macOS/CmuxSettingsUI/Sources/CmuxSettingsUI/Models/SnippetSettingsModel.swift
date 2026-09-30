import Foundation
import Observation

/// One group in the Snippets list: `category` nil means uncategorised.
struct SnippetSettingsSection: Equatable, Identifiable {
    let id: String
    let category: String?
    let items: [SnippetSettingsItem]
}

/// Main-actor projection of the host's snippet controller for SwiftUI.
/// Owns the list, save/delete state, and the grouping the section renders.
@MainActor
@Observable
final class SnippetSettingsModel {
    private let controller: (any SnippetSettingsControlling)?

    private(set) var items: [SnippetSettingsItem] = []
    private(set) var isMutating = false
    private(set) var lastErrorMessage: String?

    init(controller: (any SnippetSettingsControlling)?) {
        self.controller = controller
    }

    /// Whether the host provided a controller at all.
    var isAvailable: Bool { controller != nil }

    /// Items grouped for display: uncategorised first, then categories sorted
    /// by name, items sorted by title. Category names merge case-insensitively
    /// and keep the first spelling seen.
    var sections: [SnippetSettingsSection] { Self.sections(for: items) }

    /// Loads once, then follows host updates until cancelled.
    func observe() async {
        guard let controller else { return }
        items = await controller.snippets()
        for await next in controller.snippetUpdates() {
            guard !Task.isCancelled else { return }
            items = next
        }
    }

    /// Persists a new or edited snippet. Blank title or text is rejected here
    /// so the host never sees an invalid draft. Returns success.
    func save(_ draft: SnippetSettingsDraft, replacing id: String?) async -> Bool {
        guard let controller, !isMutating else { return false }
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastErrorMessage = String(
                localized: "settings.snippets.validation.blank",
                defaultValue: "A snippet needs both a title and some text."
            )
            return false
        }
        let trimmedCategory = draft.category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = SnippetSettingsDraft(
            title: trimmedTitle,
            category: (trimmedCategory?.isEmpty ?? true) ? nil : trimmedCategory,
            text: draft.text,
            submit: draft.submit
        )
        isMutating = true
        defer { isMutating = false }
        do {
            _ = try await controller.saveSnippet(normalized, replacing: id)
            items = await controller.snippets()
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    /// Removes a snippet and refreshes the list. Returns success.
    func delete(id: String) async -> Bool {
        guard let controller, !isMutating else { return false }
        isMutating = true
        defer { isMutating = false }
        do {
            try await controller.deleteSnippet(id: id)
            items = await controller.snippets()
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func clearError() {
        lastErrorMessage = nil
    }

    static func sections(for items: [SnippetSettingsItem]) -> [SnippetSettingsSection] {
        var uncategorized: [SnippetSettingsItem] = []
        var order: [String] = []
        var names: [String: String] = [:]
        var grouped: [String: [SnippetSettingsItem]] = [:]
        for item in items {
            let trimmed = item.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                uncategorized.append(item)
                continue
            }
            let key = trimmed.lowercased()
            if names[key] == nil {
                names[key] = trimmed
                order.append(key)
            }
            grouped[key, default: []].append(item)
        }
        func byTitle(_ lhs: SnippetSettingsItem, _ rhs: SnippetSettingsItem) -> Bool {
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        var sections: [SnippetSettingsSection] = []
        if !uncategorized.isEmpty {
            sections.append(SnippetSettingsSection(id: "", category: nil, items: uncategorized.sorted(by: byTitle)))
        }
        let categorized = order
            .map { key in
                SnippetSettingsSection(id: key, category: names[key], items: (grouped[key] ?? []).sorted(by: byTitle))
            }
            .sorted { ($0.category ?? "").localizedStandardCompare($1.category ?? "") == .orderedAscending }
        sections.append(contentsOf: categorized)
        return sections
    }
}
