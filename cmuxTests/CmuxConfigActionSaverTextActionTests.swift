import CmuxTextActions
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Settings > Snippets write path: creating, editing in place, and deleting
/// `type: "text"` actions in a real cmux.json while preserving its comments.
struct CmuxConfigActionSaverTextActionTests {
    private func makeConfigPath(_ contents: String?) throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cmux-text-action-saver-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("cmux.json").path
        if let contents {
            try contents.write(toFile: path, atomically: true, encoding: .utf8)
        }
        return path
    }

    private func payload(_ text: String, submit: Bool = false) throws -> CmuxTextActionPayload {
        try #require(CmuxTextActionPayload(text: text, submit: submit))
    }

    @Test func savesNewSnippetWithSluggedIDCategoryAndSubmit() throws {
        let path = try makeConfigPath("""
        {
          // keep me
          "actions": {
            "existing": { "type": "command", "command": "ls" }
          }
        }
        """)
        let result = try CmuxConfigActionSaver.saveTextAction(
            title: "Fixup last commit",
            category: "Git",
            payload: try payload("git commit --fixup HEAD", submit: true),
            globalConfigPath: path
        )
        #expect(result.actionID == "fixup-last-commit")
        let written = try String(contentsOfFile: path, encoding: .utf8)
        #expect(written.contains("// keep me"))
        #expect(written.contains("\"existing\""))
        let config = try JSONDecoder().decode(CmuxConfigFile.self, from: JSONCParser.preprocess(data: Data(written.utf8)))
        let saved = try #require(config.actions["fixup-last-commit"])
        #expect(saved.title == "Fixup last commit")
        #expect(saved.category == "Git")
        #expect(saved.action?.textPayload?.text == "git commit --fixup HEAD")
        #expect(saved.action?.textPayload?.submit == true)
    }

    @Test func savingWithExistingIDReplacesInPlaceAndKeepsID() throws {
        let path = try makeConfigPath("""
        {
          "actions": {
            "review": { "type": "text", "title": "Review", "category": "Prompts", "text": "old" },
            "after": { "type": "command", "command": "ls" }
          }
        }
        """)
        let result = try CmuxConfigActionSaver.saveTextAction(
            id: "review",
            title: "Review diff",
            category: nil,
            payload: try payload("new text\nline two"),
            globalConfigPath: path
        )
        #expect(result.actionID == "review")
        let written = try String(contentsOfFile: path, encoding: .utf8)
        let reviewRange = try #require(written.range(of: "\"review\""))
        let afterRange = try #require(written.range(of: "\"after\""))
        #expect(reviewRange.lowerBound < afterRange.lowerBound)
        let config = try JSONDecoder().decode(CmuxConfigFile.self, from: JSONCParser.preprocess(data: Data(written.utf8)))
        let saved = try #require(config.actions["review"])
        #expect(saved.title == "Review diff")
        #expect(saved.category == nil)
        #expect(saved.action?.textPayload?.text == "new text\nline two")
        #expect(config.actions.count == 2)
    }

    @Test func uniquifiesAgainstFileAndReservedIDs() throws {
        let path = try makeConfigPath(#"{ "actions": { "note": { "type": "text", "text": "a" } } }"#)
        let result = try CmuxConfigActionSaver.saveTextAction(
            title: "Note",
            category: nil,
            payload: try payload("b"),
            globalConfigPath: path,
            reservedActionIDs: ["note-2"]
        )
        #expect(result.actionID == "note-3")
    }

    @Test func createsConfigFromTemplateWhenMissing() throws {
        let path = try makeConfigPath(nil)
        try CmuxConfigActionSaver.saveTextAction(
            title: "Hello",
            category: "Misc",
            payload: try payload("echo hi"),
            globalConfigPath: path
        )
        let written = try String(contentsOfFile: path, encoding: .utf8)
        let config = try JSONDecoder().decode(CmuxConfigFile.self, from: JSONCParser.preprocess(data: Data(written.utf8)))
        #expect(config.actions["hello"]?.action?.textPayload?.text == "echo hi")
    }

    @Test func deleteRemovesSnippetAndKeepsNeighbours() throws {
        let path = try makeConfigPath("""
        {
          "actions": {
            "a": { "type": "text", "text": "a" },
            "b": { "type": "text", "text": "b" }
          }
        }
        """)
        try CmuxConfigActionSaver.deleteAction(id: "a", globalConfigPath: path)
        let written = try String(contentsOfFile: path, encoding: .utf8)
        let config = try JSONDecoder().decode(CmuxConfigFile.self, from: JSONCParser.preprocess(data: Data(written.utf8)))
        #expect(Array(config.actions.keys) == ["b"])
    }
}
