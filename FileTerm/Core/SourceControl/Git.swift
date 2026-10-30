import Foundation

public enum GitRepository {
  /// The nearest folder at or above `path` that holds `.git`. A worktree or submodule has a `.git`
  /// file instead of a folder, so anything named `.git` counts.
  public static func root(
    from path: String,
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
  ) -> String? {
    var folder = (path as NSString).standardizingPath
    while folder.hasPrefix("/") {
      if fileExists((folder as NSString).appendingPathComponent(".git")) { return folder }
      if folder == "/" { return nil }
      folder = (folder as NSString).deletingLastPathComponent
    }
    return nil
  }
}

/// The Commands › Source Control actions. Each runs `/usr/bin/git -C <root> …` without a shell, so
/// paths and messages are single arguments and need no quoting.
public enum GitCommand: Equatable, Sendable {
  case add([String])
  case addAll
  case commit(message: String)
  case push
  case pull

  public static let executable = "/usr/bin/git"

  /// Git must never wait for input: there is no terminal to type a password or a merge message in.
  public static let environment = [
    "GIT_TERMINAL_PROMPT": "0", "GIT_MERGE_AUTOEDIT": "no", "GIT_EDITOR": "true",
  ]

  public var title: String {
    switch self {
    case .add: "Add"
    case .addAll: "Add All"
    case .commit: "Commit"
    case .push: "Push"
    case .pull: "Pull"
    }
  }

  public func arguments(root: String) -> [String] {
    ["-C", root]
      + {
        switch self {
        case .add(let paths): ["add", "--"] + paths
        case .addAll: ["add", "--all"]
        case .commit(let message): ["commit", "-m", message]
        case .push: ["push"]
        case .pull: ["pull"]
        }
      }()
  }

  /// The line written to Logs before the output.
  public func logLine(root: String) -> String {
    "$ git " + arguments(root: root).joined(separator: " ")
  }
}
