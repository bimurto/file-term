import Foundation
import UniformTypeIdentifiers

/// Something outside the app that a feature needs before it can succeed.
public enum Prerequisite: Hashable, Sendable {
  case remoteAccount(ConnectionKind, server: String, username: String, hasPassword: Bool)
  case gitRepository(folder: String)
  case compareTool(CompareTool)
  case previewSupport(path: String)
  case commandLineProgram(String)
}

/// Checks prerequisites and says what is missing in words the user can act on.
public struct Prerequisites: Sendable {
  private let fileExists: @Sendable (String) -> Bool
  private let isExecutable: @Sendable (String) -> Bool
  private let searchPath: [String]
  private let compareToolInstalled: @Sendable (CompareTool) -> Bool

  public init(
    fileExists: @escaping @Sendable (String) -> Bool,
    isExecutable: @escaping @Sendable (String) -> Bool, searchPath: [String],
    compareToolInstalled: @escaping @Sendable (CompareTool) -> Bool
  ) {
    self.fileExists = fileExists
    self.isExecutable = isExecutable
    self.searchPath = searchPath
    self.compareToolInstalled = compareToolInstalled
  }

  /// Uses the same `PATH` that tools inherit when they run through `/bin/sh`.
  public static let live = Prerequisites(
    fileExists: { FileManager.default.fileExists(atPath: $0) },
    isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
    searchPath: (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
      .split(separator: ":").map(String.init),
    compareToolInstalled: { $0.isInstalled })

  /// What is missing for each prerequisite that is not met, in order.
  public func missing(_ prerequisites: [Prerequisite]) -> [String] {
    prerequisites.compactMap(missing)
  }

  /// What is missing, or nil when the prerequisite is met.
  public func missing(_ prerequisite: Prerequisite) -> String? {
    switch prerequisite {
    case .remoteAccount(let kind, let server, let username, let hasPassword):
      // Other protocols can sign in anonymously or with a key, so only object stores need these.
      // Object stores have a default endpoint, so only the other protocols need a server.
      guard kind.isObjectStore else {
        return kind.usesServer && server.trimmingCharacters(in: .whitespaces).isEmpty
          ? "\(kind.title) needs the server's address." : nil
      }
      if username.isEmpty { return "\(kind.title) needs the \(kind.usernameTitle)." }
      return hasPassword ? nil : "\(kind.title) needs the \(kind.passwordTitle)."
    case .gitRepository(let folder):
      return hasGitRepository(above: folder) ? nil : "\(folder) is not in a Git repository."
    case .compareTool(let tool):
      return compareToolInstalled(tool)
        ? nil
        : "\(tool.title) is not installed. Choose another tool in Settings › General › Compare Tool."
    case .previewSupport(let path):
      return Self.canPreview(path) ? nil : "There is no preview for this type of file."
    case .commandLineProgram(let program):
      return hasProgram(program) ? nil : "The program “\(program)” was not found on this Mac."
    }
  }

  /// A clearer message than the local-folder one when a server refuses access.
  public static func remotePermissionMessage(server: String) -> String {
    "Your account does not have permission to open this location on \(server). "
      + "Check the account and folder with the server's administrator."
  }

  private func hasGitRepository(above folder: String) -> Bool {
    var current = folder
    while true {
      if fileExists(current + "/.git") { return true }
      let parent = (current as NSString).deletingLastPathComponent
      if parent == current || parent.isEmpty { return false }
      current = parent
    }
  }

  private func hasProgram(_ program: String) -> Bool {
    if program.contains("/") { return isExecutable(program) }
    return searchPath.contains { isExecutable($0 + "/" + program) }
  }

  private static func canPreview(_ path: String) -> Bool {
    let fileExtension = (path as NSString).pathExtension
    guard !fileExtension.isEmpty, let type = UTType(filenameExtension: fileExtension) else {
      return false
    }
    return [UTType.image, .audiovisualContent, .pdf, .text].contains { type.conforms(to: $0) }
  }
}

extension UserTool {
  /// The program the command starts, or nil when only the shell can tell: a builtin, a variable,
  /// an assignment or a compound command.
  public var requiredProgram: String? {
    guard
      let first = command.split(whereSeparator: \.isWhitespace).first.map(String.init),
      first.rangeOfCharacter(from: CharacterSet(charactersIn: "$=(){}'\"`;&|<>\\")) == nil,
      !Self.shellWords.contains(first)
    else { return nil }
    return first
  }

  private static let shellWords: Set<String> = [
    ".", ":", "alias", "bg", "break", "case", "cd", "command", "continue", "eval", "exec", "exit",
    "export", "fg", "for", "if", "jobs", "read", "readonly", "return", "set", "shift", "source",
    "test", "times", "trap", "type", "ulimit", "umask", "unalias", "unset", "until", "wait",
    "while", "[", "!",
  ]
}
