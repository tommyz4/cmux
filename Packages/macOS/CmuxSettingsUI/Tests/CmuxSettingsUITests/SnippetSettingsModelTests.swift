import Foundation
import Testing

@testable import CmuxSettingsUI

@MainActor
@Suite
struct SnippetSettingsModelTests {
    private func item(_ id: String, _ title: String, category: String? = nil, editable: Bool = true) -> SnippetSettingsItem {
        SnippetSettingsItem(id: id, title: title, category: category, text: "echo \(id)", submit: false, isEditable: editable)
    }

    @Test func observeLoadsThenFollowsUpdates() async {
        let controller = SnippetSettingsControllerDouble(items: [item("a", "Alpha")])
        let model = SnippetSettingsModel(controller: controller)
        let observation = Task { await model.observe() }
        await waitUntil { model.items.count == 1 }
        controller.continuation.yield([item("a", "Alpha"), item("b", "Beta")])
        await waitUntil { model.items.count == 2 }
        observation.cancel()
        await observation.value
        #expect(model.items.map(\.id) == ["a", "b"])
    }

    @Test func saveForwardsTrimmedDraftAndRefreshes() async {
        let controller = SnippetSettingsControllerDouble(items: [])
        let model = SnippetSettingsModel(controller: controller)
        let saved = await model.save(
            SnippetSettingsDraft(title: "  Fixup  ", category: "  Git ", text: "git commit --fixup HEAD", submit: true),
            replacing: nil
        )
        #expect(saved)
        #expect(controller.saves == [
            .init(draft: SnippetSettingsDraft(title: "Fixup", category: "Git", text: "git commit --fixup HEAD", submit: true), replacing: nil),
        ])
        #expect(model.items.map(\.title) == ["Fixup"])
        #expect(model.lastErrorMessage == nil)
    }

    @Test func blankCategoryBecomesNilAndEditKeepsID() async {
        let controller = SnippetSettingsControllerDouble(items: [item("fixup", "Fixup")])
        let model = SnippetSettingsModel(controller: controller)
        let saved = await model.save(
            SnippetSettingsDraft(title: "Fixup", category: "   ", text: "x", submit: false),
            replacing: "fixup"
        )
        #expect(saved)
        #expect(controller.saves.first?.replacing == "fixup")
        #expect(controller.saves.first?.draft.category == nil)
    }

    @Test func blankTitleOrTextIsRejectedBeforeReachingTheHost() async {
        let controller = SnippetSettingsControllerDouble(items: [])
        let model = SnippetSettingsModel(controller: controller)
        #expect(await model.save(SnippetSettingsDraft(title: " ", text: "x"), replacing: nil) == false)
        #expect(await model.save(SnippetSettingsDraft(title: "T", text: " \n "), replacing: nil) == false)
        #expect(controller.saves.isEmpty)
        #expect(model.lastErrorMessage != nil)
    }

    @Test func failedSaveSurfacesErrorAndKeepsItems() async {
        let controller = SnippetSettingsControllerDouble(items: [item("a", "Alpha")])
        controller.saveError = TestFailure.rejected
        let model = SnippetSettingsModel(controller: controller)
        let observation = Task { await model.observe() }
        await waitUntil { model.items.count == 1 }
        observation.cancel()
        await observation.value
        let saved = await model.save(SnippetSettingsDraft(title: "B", text: "b"), replacing: nil)
        #expect(!saved)
        #expect(model.lastErrorMessage == TestFailure.rejected.localizedDescription)
        #expect(model.items.map(\.id) == ["a"])
        model.clearError()
        #expect(model.lastErrorMessage == nil)
    }

    @Test func deleteForwardsIDAndRefreshes() async {
        let controller = SnippetSettingsControllerDouble(items: [item("a", "Alpha"), item("b", "Beta")])
        let model = SnippetSettingsModel(controller: controller)
        let deleted = await model.delete(id: "a")
        #expect(deleted)
        #expect(controller.deletes == ["a"])
        #expect(model.items.map(\.id) == ["b"])
    }

    @Test func sectionsGroupUncategorisedFirstThenSortedCategories() {
        let sections = SnippetSettingsModel.sections(for: [
            item("z", "Zeta", category: "Git"),
            item("a", "Alpha", category: "git"),
            item("l", "Lint", category: "Build"),
            item("loose", "Loose"),
        ])
        #expect(sections.map(\.category) == [nil, "Build", "Git"])
        #expect(sections[2].items.map(\.title) == ["Alpha", "Zeta"])
        #expect(sections[0].items.map(\.id) == ["loose"])
    }

    @Test func modelWithoutControllerIsUnavailableAndInert() async {
        let model = SnippetSettingsModel(controller: nil)
        #expect(!model.isAvailable)
        #expect(await model.save(SnippetSettingsDraft(title: "T", text: "x"), replacing: nil) == false)
        #expect(await model.delete(id: "x") == false)
    }
}

private enum TestFailure: LocalizedError {
    case rejected
    var errorDescription: String? { "rejected by test" }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(2), _ condition: @MainActor () -> Bool) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private final class SnippetSettingsControllerDouble: SnippetSettingsControlling {
    struct Save: Equatable {
        let draft: SnippetSettingsDraft
        let replacing: String?
    }

    var items: [SnippetSettingsItem]
    var saves: [Save] = []
    var deletes: [String] = []
    var saveError: (any Error)?
    let continuation: AsyncStream<[SnippetSettingsItem]>.Continuation
    private let stream: AsyncStream<[SnippetSettingsItem]>

    init(items: [SnippetSettingsItem]) {
        self.items = items
        var continuation: AsyncStream<[SnippetSettingsItem]>.Continuation!
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func snippets() async -> [SnippetSettingsItem] { items }

    func snippetUpdates() -> AsyncStream<[SnippetSettingsItem]> { stream }

    func saveSnippet(_ draft: SnippetSettingsDraft, replacing id: String?) async throws -> String {
        saves.append(Save(draft: draft, replacing: id))
        if let saveError { throw saveError }
        let resolvedID = id ?? draft.title.lowercased().replacingOccurrences(of: " ", with: "-")
        items.removeAll { $0.id == resolvedID }
        items.append(SnippetSettingsItem(
            id: resolvedID, title: draft.title, category: draft.category, text: draft.text, submit: draft.submit
        ))
        return resolvedID
    }

    func deleteSnippet(id: String) async throws {
        deletes.append(id)
        items.removeAll { $0.id == id }
    }
}
