import Foundation
import Testing

@testable import FileTermCore

struct EditorMappingTests {
  private let code = EditorMapping(
    applicationPath: "/Applications/Visual Studio Code.app", extensions: ["swift", "md"])
  private let text = EditorMapping(
    applicationPath: "/System/Applications/TextEdit.app", extensions: ["txt", "md", "tar.gz"])

  @Test func matchesTheExtensionCaseInsensitively() {
    #expect(EditorMapping.mapping(for: "Main.SWIFT", in: [code, text]) == code)
    #expect(EditorMapping.mapping(for: "notes.txt", in: [code, text]) == text)
  }

  @Test func theFirstMappingInListOrderWins() {
    #expect(EditorMapping.mapping(for: "README.md", in: [code, text]) == code)
    #expect(EditorMapping.mapping(for: "README.md", in: [text, code]) == text)
  }

  @Test func noMatchMeansNoMapping() {
    #expect(EditorMapping.mapping(for: "photo.png", in: [code, text]) == nil)
    #expect(EditorMapping.mapping(for: "swift", in: [code, text]) == nil)
    #expect(EditorMapping.mapping(for: "a.txt", in: []) == nil)
  }

  @Test func extensionsMustMatchAtAWordBoundary() {
    #expect(EditorMapping.mapping(for: "script.notswift", in: [code]) == nil)
    #expect(EditorMapping.mapping(for: "archive.tar.gz", in: [text]) == text)
    #expect(EditorMapping.mapping(for: "archive.gz", in: [text]) == nil)
  }

  @Test func dotFilesMatchTheirWholeName() {
    let ignore = EditorMapping(applicationPath: "/Applications/Zed.app", extensions: ["gitignore"])
    #expect(EditorMapping.mapping(for: ".gitignore", in: [ignore]) == ignore)
  }

  @Test func parsesCommaAndSpaceSeparatedExtensions() {
    #expect(EditorMapping.parseExtensions("swift, .MD  txt,,") == ["swift", "md", "txt"])
    #expect(EditorMapping.parseExtensions("md, .md, MD") == ["md"])
    #expect(EditorMapping.parseExtensions(" , ") == [])
  }

  @Test func initNormalizesAndNamesTheApplication() {
    let mapping = EditorMapping(applicationPath: "/Applications/BBEdit.app", extensions: [".TXT"])
    #expect(mapping.extensions == ["txt"])
    #expect(mapping.displayName == "BBEdit")
  }

  @Test func roundTripsThroughJSON() throws {
    let data = try JSONEncoder().encode([code, text])
    #expect(try JSONDecoder().decode([EditorMapping].self, from: data) == [code, text])
  }
}
