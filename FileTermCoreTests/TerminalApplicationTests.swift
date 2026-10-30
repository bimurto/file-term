import Foundation
import Testing

@testable import FileTermCore

struct TerminalApplicationTests {
  @Test func theFirstExistingLocationWins() {
    let found = TerminalApplication.iTerm.applicationPath(
      homeDirectory: "/Users/me",
      fileExists: { $0 == "/Users/me/Applications/iTerm.app" || $0 == "/Applications/iTerm.app" })
    #expect(found == "/Applications/iTerm.app")
    let onlyInHome = TerminalApplication.iTerm.applicationPath(
      homeDirectory: "/Users/me", fileExists: { $0 == "/Users/me/Applications/iTerm.app" })
    #expect(onlyInHome == "/Users/me/Applications/iTerm.app")
  }

  @Test func aMissingAppHasNoPath() {
    for app in TerminalApplication.allCases {
      #expect(app.applicationPath(fileExists: { _ in false }) == nil)
    }
  }

  @Test func terminalIsFoundInEitherSystemLocation() {
    let system = TerminalApplication.terminal.applicationPath(fileExists: {
      $0 == "/System/Applications/Utilities/Terminal.app"
    })
    let legacy = TerminalApplication.terminal.applicationPath(fileExists: {
      $0 == "/Applications/Utilities/Terminal.app"
    })
    #expect(system == "/System/Applications/Utilities/Terminal.app")
    #expect(legacy == "/Applications/Utilities/Terminal.app")
  }

  @Test func everyAppHasItsOwnBundleName() {
    let names = TerminalApplication.allCases.map {
      ($0.candidatePaths(homeDirectory: "/h")[0] as NSString).lastPathComponent
    }
    #expect(Set(names).count == TerminalApplication.allCases.count)
    #expect(names.allSatisfy { $0.hasSuffix(".app") })
  }

  @Test func terminalIsInstalledOnThisMac() {
    #expect(TerminalApplication.terminal.isInstalled)
  }
}
