import Foundation
import Testing

@testable import FileTermCore

struct ToolCommandBuilderTests {
  private func run(
    _ command: String, _ context: ToolCommandBuilder.Context, perFile: Bool = false
  ) -> [String] {
    ToolCommandBuilder.expand(
      UserTool(name: "t", command: command, runForEachFile: perFile), context: context)
  }

  private func shellWords(_ line: String) throws -> [String] {
    // Lets a real shell split the line, so quoting is tested for what it means rather than shape.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "printf '%s\\0' " + line]
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
  }

  @Test func quotesSpacesAsOneWord() throws {
    let line = run("ls $SOURCE_PATH", .init(sourcePath: "/Users/me/My Files"))[0]
    #expect(line == "ls '/Users/me/My Files'")
    let path = run("$SOURCE_PATH", .init(sourcePath: "/Users/me/My Files"))[0]
    #expect(try shellWords(path) == ["/Users/me/My Files"])
  }

  @Test func singleAndDoubleQuotesSurviveTheShell() throws {
    let tricky = ["it's", "say \"hi\"", "both ' and \"", "$HOME `date` $(id)", "back\\slash"]
    for name in tricky {
      let line = run("$SOURCE_SELECTION_PATHS", .init(sourcePath: "/", sourceSelection: [name]))[0]
      #expect(try shellWords(line) == [name])
    }
  }

  @Test func unicodePathsAreKeptVerbatim() throws {
    let paths = ["/Users/me/café", "/Users/me/日本語 ファイル", "/Users/me/🙂 notes", "/tmp/e\u{301}"]
    let line = run("$SOURCE_SELECTION_PATHS", .init(sourcePath: "/", sourceSelection: paths))[0]
    #expect(try shellWords(line) == paths)
  }

  @Test func namesAreTheLastComponent() throws {
    let context = ToolCommandBuilder.Context(
      sourcePath: "/a", targetPath: "/b", sourceSelection: ["/a/one two.txt", "/a/x"],
      targetSelection: ["/b/it's.md"])
    #expect(run("$SOURCE_SELECTION_NAMES", context) == ["'one two.txt' 'x'"])
    #expect(try shellWords(run("$TARGET_SELECTION_NAMES", context)[0]) == ["it's.md"])
  }

  @Test func eachPlaceholderFillsFromItsOwnSide() {
    let context = ToolCommandBuilder.Context(
      sourcePath: "/s", targetPath: "/t", sourceSelection: ["/s/a"], targetSelection: ["/t/b"])
    let line = run(
      "$SOURCE_PATH $TARGET_PATH $SOURCE_SELECTION_PATHS $TARGET_SELECTION_PATHS", context)[0]
    #expect(line == "'/s' '/t' '/s/a' '/t/b'")
  }

  @Test func longerPlaceholdersAreNotClobberedByShorterOnes() {
    let context = ToolCommandBuilder.Context(
      sourcePath: "/s", sourceSelection: ["/s/a", "/s/b"])
    #expect(run("$SOURCE_SELECTION_PATHS", context) == ["'/s/a' '/s/b'"])
    #expect(run("$SOURCE_PATH/x", context) == ["'/s'/x"])
  }

  @Test func aSubstitutedValueIsNeverExpandedAgain() {
    let context = ToolCommandBuilder.Context(
      sourcePath: "/weird/$TARGET_PATH", targetPath: "/t")
    #expect(run("echo $SOURCE_PATH", context) == ["echo '/weird/$TARGET_PATH'"])
  }

  @Test func unknownNamesAndWordSuffixesAreLeftAlone() {
    let context = ToolCommandBuilder.Context(sourcePath: "/s")
    #expect(
      run("echo $HOME $SOURCE_PATHS $SOURCE_PATH_X", context) == [
        "echo $HOME $SOURCE_PATHS $SOURCE_PATH_X"
      ])
  }

  @Test func missingValuesBecomeEmpty() {
    let context = ToolCommandBuilder.Context(sourcePath: "/s")
    #expect(run("cp $SOURCE_SELECTION_PATHS $TARGET_PATH", context) == ["cp  "])
  }

  @Test func runForEachFileMakesOneLinePerSelectedItem() {
    let context = ToolCommandBuilder.Context(
      sourcePath: "/s", targetPath: "/t", sourceSelection: ["/s/a b", "/s/c"])
    #expect(
      run("cp $SOURCE_SELECTION_PATHS $TARGET_PATH", context, perFile: true) == [
        "cp '/s/a b' '/t'", "cp '/s/c' '/t'",
      ])
  }

  @Test func runForEachFileWithNothingSelectedRunsNothing() {
    #expect(run("echo $SOURCE_SELECTION_PATHS", .init(sourcePath: "/s"), perFile: true).isEmpty)
  }

  @Test func toolsRoundTripThroughJSON() throws {
    let tool = UserTool(
      name: "Zip", command: "zip $SOURCE_SELECTION_NAMES", runForEachFile: true,
      enableForRemote: true, showOutput: true, showInToolbar: true)
    let data = try JSONEncoder().encode([tool])
    #expect(try JSONDecoder().decode([UserTool].self, from: data) == [tool])
  }
}
