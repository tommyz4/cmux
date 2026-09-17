import AppKit
import CmuxSettingsUI
import CmuxTextActions
import Combine
import Foundation

/// Bridges Settings > Snippets to the app's config store and the
/// JSONC-preserving action saver. Only actions defined in the global
/// cmux.json are editable; project-local ones are listed read-only.
@MainActor
final class SnippetSettingsController: SnippetSettingsControlling {
    enum Failure: LocalizedError {
        case unavailable
        case blankText
        case notEditable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return String(
                    localized: "snippets.error.unavailable",
                    defaultValue: "Snippets are unavailable until a cmux window has loaded its configuration."
                )
            case .blankText:
                return String(
                    localized: "snippets.error.blankText",
                    defaultValue: "Snippet text must not be blank."
                )
            case .notEditable:
                return String(
                    localized: "snippets.error.notEditable",
                    defaultValue: "This snippet is defined in a project config and can only be changed there."
                )
            }
        }
    }

    private let storeProvider: @MainActor () -> CmuxConfigStore?

    init(storeProvider: @escaping @MainActor () -> CmuxConfigStore?) {
        self.storeProvider = storeProvider
    }

    /// Reads through the key terminal window's store when one is available,
    /// otherwise any loaded window's store. Every store shares the same global
    /// config file, so writes land in the same place either way.
    static func appDefault() -> SnippetSettingsController {
        SnippetSettingsController {
            guard let delegate = AppDelegate.shared else { return nil }
            if let window = NSApp.mainWindow,
               let store = delegate.contextForMainTerminalWindow(window)?.cmuxConfigStore {
                return store
            }
            return delegate.mainWindowContexts.values.compactMap(\.cmuxConfigStore).first
        }
    }

    func snippets() async -> [SnippetSettingsItem] {
        guard let store = storeProvider() else { return [] }
        return Self.items(in: store)
    }

    func snippetUpdates() -> AsyncStream<[SnippetSettingsItem]> {
        AsyncStream { continuation in
            guard let store = storeProvider() else {
                continuation.finish()
                return
            }
            let cancellable = store.$configRevision
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak store] _ in
                    guard let store else { return }
                    continuation.yield(Self.items(in: store))
                }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    func saveSnippet(_ draft: SnippetSettingsDraft, replacing id: String?) async throws -> String {
        guard let store = storeProvider() else { throw Failure.unavailable }
        guard let payload = CmuxTextActionPayload(text: draft.text, submit: draft.submit) else {
            throw Failure.blankText
        }
        if let id {
            guard let existing = store.resolvedAction(id: id), Self.isEditable(existing, in: store) else {
                throw Failure.notEditable
            }
        }
        let result = try CmuxConfigActionSaver.saveTextAction(
            id: id,
            title: draft.title,
            category: draft.category,
            payload: payload,
            globalConfigPath: store.globalConfigPath,
            reservedActionIDs: Set(store.loadedActions.map(\.id))
        )
        store.loadAll()
        return result.actionID
    }

    func deleteSnippet(id: String) async throws {
        guard let store = storeProvider() else { throw Failure.unavailable }
        guard let existing = store.resolvedAction(id: id), Self.isEditable(existing, in: store) else {
            throw Failure.notEditable
        }
        try CmuxConfigActionSaver.deleteAction(id: id, globalConfigPath: store.globalConfigPath)
        store.loadAll()
    }

    private static func items(in store: CmuxConfigStore) -> [SnippetSettingsItem] {
        store.loadedActions.compactMap { action in
            guard let payload = action.action.textPayload else { return nil }
            return SnippetSettingsItem(
                id: action.id,
                title: action.title,
                category: action.category,
                text: payload.text,
                submit: payload.submit,
                isEditable: isEditable(action, in: store)
            )
        }
    }

    private static func isEditable(_ action: CmuxResolvedConfigAction, in store: CmuxConfigStore) -> Bool {
        guard let sourcePath = action.actionSourcePath else { return false }
        return canonical(sourcePath) == canonical(store.globalConfigPath)
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
