import Foundation
import Testing

@testable import FileTermCore

struct AppLeftoversTests {
  private func library(_ paths: [String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    for path in paths {
      let url = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      if path.hasSuffix("/") {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      } else {
        try Data().write(to: url)
      }
    }
    return root
  }

  @Test func findsRelatedItemsByBundleIdentifierAndName() throws {
    let root = try library([
      "Preferences/com.acme.Tool.plist",
      "Preferences/ByHost/com.acme.Tool.ABC123.plist",
      "Preferences/com.acme.ToolHelper.plist",
      "Caches/com.acme.Tool/",
      "Application Support/Tool/",
      "Application Support/com.acme.Tool/",
      "Containers/com.acme.Tool/",
      "Group Containers/ABCDE12345.com.acme.Tool/",
      "Saved Application State/com.acme.Tool.savedState/",
      "LaunchAgents/com.acme.Tool.helper.plist",
      "Caches/com.other.App/",
      "Application Support/Other/",
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let found = AppLeftovers.relatedFiles(bundleID: "com.acme.Tool", appName: "Tool", library: root)
    let relative = found.map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }
    #expect(
      relative == [
        "Application Support/com.acme.Tool",
        "Application Support/Tool",
        "Caches/com.acme.Tool",
        "Containers/com.acme.Tool",
        "Group Containers/ABCDE12345.com.acme.Tool",
        "LaunchAgents/com.acme.Tool.helper.plist",
        "Preferences/ByHost/com.acme.Tool.ABC123.plist",
        "Preferences/com.acme.Tool.plist",
        "Saved Application State/com.acme.Tool.savedState",
      ])
  }

  @Test func withoutAUsableBundleIdentifierOnlyNamedFoldersMatch() throws {
    let root = try library(["Caches/Tool/", "Preferences/.plist", "Caches/com.acme.Tool/"])
    defer { try? FileManager.default.removeItem(at: root) }
    for id in [nil, "", "Tool", "."] as [String?] {
      let found = AppLeftovers.relatedFiles(bundleID: id, appName: "Tool", library: root)
      #expect(found.map(\.lastPathComponent) == ["Tool"], "\(String(describing: id))")
    }
  }

  @Test func missingLibraryFoldersGiveNoResults() {
    let nothing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    #expect(
      AppLeftovers.relatedFiles(bundleID: "com.acme.Tool", appName: "Tool", library: nothing)
        .isEmpty)
  }
}
