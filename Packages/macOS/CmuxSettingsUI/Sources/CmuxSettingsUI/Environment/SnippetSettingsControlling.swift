import Foundation

/// One `type: "text"` action as Settings > Snippets shows it. Foundation-only
/// so the settings package never sees the app's config types.
public struct SnippetSettingsItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var category: String?
    public var text: String
    public var submit: Bool
    /// False for snippets that come from a project-local config or a
    /// built-in source; those are listed but cannot be changed here.
    public var isEditable: Bool

    public init(
        id: String,
        title: String,
        category: String? = nil,
        text: String,
        submit: Bool = false,
        isEditable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.text = text
        self.submit = submit
        self.isEditable = isEditable
    }
}

/// Fields the editor sheet collects. Validation of blank values happens in
/// the model before the host is asked to persist anything.
public struct SnippetSettingsDraft: Equatable, Sendable {
    public var title: String
    public var category: String?
    public var text: String
    public var submit: Bool

    public init(title: String, category: String? = nil, text: String, submit: Bool = false) {
        self.title = title
        self.category = category
        self.text = text
        self.submit = submit
    }
}

/// Host-side owner of snippet persistence. The app conforms with a bridge
/// over its config store and JSONC-preserving action saver.
@MainActor
public protocol SnippetSettingsControlling: AnyObject {
    /// Current snippets from every loaded config source.
    func snippets() async -> [SnippetSettingsItem]
    /// Emits the full list whenever the config reloads, without polling.
    func snippetUpdates() -> AsyncStream<[SnippetSettingsItem]>
    /// Creates a new global snippet, or replaces the one with `id` in place.
    /// Returns the persisted action id.
    func saveSnippet(_ draft: SnippetSettingsDraft, replacing id: String?) async throws -> String
    /// Removes a global snippet from the config file.
    func deleteSnippet(id: String) async throws
}
