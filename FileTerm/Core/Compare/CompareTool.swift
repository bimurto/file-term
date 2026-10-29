import Foundation

/// External tools that can show two files side by side (Settings › General › Compare Tool).
public enum CompareTool: String, CaseIterable, Sendable {
  case fileMerge = "FileMerge"
  case kaleidoscope = "Kaleidoscope"
  case bbedit = "BBEdit"
  case vscode = "Visual Studio Code"

  public var title: String { rawValue }

  /// Where `xcode-select` points, found once; FileMerge lives inside the developer directory.
  private static let developerDirectory: String? = {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    process.arguments = ["-p"]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
  }()

  /// The tool counts as installed when its app is present and a command-line launcher exists.
  private func requirements(developerDirectory: String?) -> (apps: [String], launchers: [String]) {
    switch self {
    case .fileMerge:
      return (
        [developerDirectory.map { $0 + "/Applications/FileMerge.app" }].compactMap { $0 } + [
          "/Applications/Xcode.app/Contents/Applications/FileMerge.app",
          "/Applications/FileMerge.app",
        ], ["/usr/bin/opendiff"]
      )
    case .kaleidoscope:
      return (
        ["/Applications/Kaleidoscope.app"],
        ["/usr/local/bin/ksdiff", "/opt/homebrew/bin/ksdiff"]
      )
    case .bbedit:
      return (
        ["/Applications/BBEdit.app"], ["/usr/local/bin/bbdiff", "/opt/homebrew/bin/bbdiff"]
      )
    case .vscode:
      return (
        ["/Applications/Visual Studio Code.app"],
        [
          "/usr/local/bin/code", "/opt/homebrew/bin/code",
          "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
        ]
      )
    }
  }

  private func arguments(left: URL, right: URL) -> [String] {
    self == .vscode ? ["--diff", left.path, right.path] : [left.path, right.path]
  }

  public struct Invocation: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
  }

  /// The command that opens `left` and `right`, or nil when the tool is not installed.
  public func invocation(left: URL, right: URL) -> Invocation? {
    invocation(
      left: left, right: right, fileExists: { FileManager.default.fileExists(atPath: $0) },
      developerDirectory: CompareTool.developerDirectory)
  }

  func invocation(
    left: URL, right: URL, fileExists: (String) -> Bool, developerDirectory: String?
  ) -> Invocation? {
    let needs = requirements(developerDirectory: developerDirectory)
    guard needs.apps.contains(where: fileExists),
      let launcher = needs.launchers.first(where: fileExists)
    else { return nil }
    return Invocation(executable: launcher, arguments: arguments(left: left, right: right))
  }

  public var isInstalled: Bool {
    invocation(left: URL(fileURLWithPath: "/"), right: URL(fileURLWithPath: "/")) != nil
  }

  /// Starts the tool and returns without waiting for it to close.
  public func launch(left: URL, right: URL) throws {
    guard let invocation = invocation(left: left, right: right) else {
      throw FileSystemError.io("\(title) is not installed.")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: invocation.executable)
    process.arguments = invocation.arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
  }
}

/// Which two files Commands › Compare would open.
public enum CompareSelection: Equatable {
  case pair(left: URL, right: URL)
  case unavailable(String)

  /// Two files selected in the active pane, or one file in each pane.
  public static func resolve(active: [FileEntry], other: [FileEntry]) -> CompareSelection {
    let hint = "Select two files, or one file in each pane."
    let chosen: [FileEntry]
    if active.count == 2 {
      chosen = active
    } else if active.count == 1, other.count == 1 {
      chosen = active + other
    } else {
      return .unavailable(hint)
    }
    guard chosen.allSatisfy({ $0.location.providerID == "local" }) else {
      return .unavailable("Compare works on local files only.")
    }
    guard chosen.allSatisfy({ $0.kind == .file }) else {
      return .unavailable("Compare works on files, not folders.")
    }
    return .pair(
      left: URL(fileURLWithPath: chosen[0].location.path),
      right: URL(fileURLWithPath: chosen[1].location.path))
  }
}
