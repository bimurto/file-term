import Foundation
import Testing

@testable import FileTermCore

struct ToolCommandBuilderTests {
  private func run(
    _ command: String, _ context: ToolCommandBuilder.Context, perFile: Bool = false
  ) -> [String] {
    ToolCommandBuilder.expand(
      UserTool(name: "t", command: command, runForEachFile: perFile), context: context
    ).map(\.displayLine)
  }

  /// Runs the command in a real shell, so quoting is tested for what it means rather than shape.
  private func shellWords(_ command: String, _ context: ToolCommandBuilder.Context) throws
    -> [String]
  {
    let built = ToolCommandBuilder.expand(UserTool(name: "t", command: command), context: context)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "printf '%s\\0' " + built[0].line]
    process.environment = ProcessInfo.processInfo.environment.merging(built[0].environment) { $1 }
    process.currentDirectoryURL = FileManager.default.temporaryDirectory
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
  }

  @Test func nothingInAFileNameRunsHoweverThePlaceholderIsQuoted() throws {
    let marker = FileManager.default.temporaryDirectory
      .appendingPathComponent("fileterm-pwned-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: marker) }
    for name in ["$(touch \(marker.path))", "`touch \(marker.path)`", "';touch \(marker.path);'"] {
      let context = ToolCommandBuilder.Context(sourcePath: name, sourceSelection: [name, "/x"])
      for command in [
        "$SOURCE_PATH", "\"$SOURCE_PATH\"", "'$SOURCE_PATH'", "\"'$SOURCE_PATH'\"",
        "'\"$SOURCE_PATH\"'", "$SOURCE_SELECTION_PATHS", "\"$SOURCE_SELECTION_PATHS\"",
        "\"$(echo $SOURCE_PATH)\"", "\"$(echo \"$SOURCE_PATH\")\"", "`echo $SOURCE_PATH`",
      ] {
        _ = try shellWords(command, context)
        #expect(!FileManager.default.fileExists(atPath: marker.path), "\(command) ran \(name)")
      }
    }
  }

  @Test func doubleQuotesKeepTheValueAsOneWord() throws {
    let context = ToolCommandBuilder.Context(sourcePath: "/a b", sourceSelection: ["/c", "/d e"])
    #expect(try shellWords("\"$SOURCE_PATH\"", context) == ["/a b"])
    #expect(try shellWords("\"x $SOURCE_PATH/y\"", context) == ["x /a b/y"])
    #expect(try shellWords("\"$SOURCE_SELECTION_PATHS\"", context) == ["/c /d e"])
  }

  @Test func singleQuotesFollowTheShellsRules() throws {
    let context = ToolCommandBuilder.Context(sourcePath: "/a b")
    #expect(try shellWords("'$SOURCE_PATH'", context) == ["$SOURCE_PATH"])
    #expect(try shellWords("\"$(sh -c 'printf %s \"$SOURCE_PATH\"')\"", context) == ["/a b"])
  }

  @Test func commandSubstitutionsKeepTheirOwnQuoting() throws {
    let context = ToolCommandBuilder.Context(sourcePath: "/a b/c d")
    #expect(try shellWords("\"$(basename \"$SOURCE_PATH\")\"", context) == ["c d"])
    #expect(try shellWords("\"$(basename $SOURCE_PATH)\"", context) == ["c d"])
  }

  @Test func backslashesAndLaterQuotesAreTracked() throws {
    let context = ToolCommandBuilder.Context(sourcePath: "/a b")
    #expect(try shellWords("\\$SOURCE_PATH", context) == ["$SOURCE_PATH"])
    #expect(try shellWords("it\\'s $SOURCE_PATH", context) == ["it's", "/a b"])
    #expect(
      try shellWords("'x' $SOURCE_PATH \"y\" $SOURCE_PATH", context) == [
        "x", "/a b", "y", "/a b",
      ])
  }

  @Test func listsBecomeSeparateWordsAndMissingValuesNoWord() throws {
    let context = ToolCommandBuilder.Context(sourcePath: "/s", sourceSelection: ["/a b", "/c"])
    #expect(try shellWords("$SOURCE_SELECTION_PATHS", context) == ["/a b", "/c"])
    #expect(try shellWords("x $TARGET_PATH $TARGET_SELECTION_NAMES y", context) == ["x", "y"])
    #expect(try shellWords("$SOURCE_PATH/x", context) == ["/s/x"])
  }

  @Test func quotesSpacesAsOneWord() throws {
    let line = run("ls $SOURCE_PATH", .init(sourcePath: "/Users/me/My Files"))[0]
    #expect(line == "ls '/Users/me/My Files'")
    #expect(
      try shellWords("$SOURCE_PATH", .init(sourcePath: "/Users/me/My Files"))
        == ["/Users/me/My Files"])
  }

  @Test func singleAndDoubleQuotesSurviveTheShell() throws {
    let tricky = ["it's", "say \"hi\"", "both ' and \"", "$HOME `date` $(id)", "back\\slash"]
    for name in tricky {
      let context = ToolCommandBuilder.Context(sourcePath: "/", sourceSelection: [name])
      #expect(try shellWords("$SOURCE_SELECTION_PATHS", context) == [name])
    }
  }

  @Test func unicodePathsAreKeptVerbatim() throws {
    let paths = ["/Users/me/café", "/Users/me/日本語 ファイル", "/Users/me/🙂 notes", "/tmp/e\u{301}"]
    let context = ToolCommandBuilder.Context(sourcePath: "/", sourceSelection: paths)
    #expect(try shellWords("$SOURCE_SELECTION_PATHS", context) == paths)
  }

  @Test func namesAreTheLastComponent() throws {
    let context = ToolCommandBuilder.Context(
      sourcePath: "/a", targetPath: "/b", sourceSelection: ["/a/one two.txt", "/a/x"],
      targetSelection: ["/b/it's.md"])
    #expect(run("$SOURCE_SELECTION_NAMES", context) == ["'one two.txt' 'x'"])
    #expect(try shellWords("$TARGET_SELECTION_NAMES", context) == ["it's.md"])
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
