import Foundation

/// A user-defined shell command. Placeholders in `command` are filled from the panes.
public struct UserTool: Codable, Hashable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var command: String
  /// Runs once per selected item instead of once with the whole selection.
  public var runForEachFile: Bool
  public var enableForRemote: Bool
  public var showOutput: Bool
  public var showInToolbar: Bool

  public init(
    id: UUID = UUID(), name: String, command: String, runForEachFile: Bool = false,
    enableForRemote: Bool = false, showOutput: Bool = false, showInToolbar: Bool = false
  ) {
    self.id = id
    self.name = name
    self.command = command
    self.runForEachFile = runForEachFile
    self.enableForRemote = enableForRemote
    self.showOutput = showOutput
    self.showInToolbar = showInToolbar
  }
}

/// Source is the active pane, target is the other one.
public enum ToolPlaceholder: String, CaseIterable, Sendable {
  case sourcePath = "$SOURCE_PATH"
  case targetPath = "$TARGET_PATH"
  case sourceSelectionPaths = "$SOURCE_SELECTION_PATHS"
  case targetSelectionPaths = "$TARGET_SELECTION_PATHS"
  case sourceSelectionNames = "$SOURCE_SELECTION_NAMES"
  case targetSelectionNames = "$TARGET_SELECTION_NAMES"

  public var summary: String {
    switch self {
    case .sourcePath: "Folder of the active pane"
    case .targetPath: "Folder of the other pane"
    case .sourceSelectionPaths: "Selected items in the active pane (full paths)"
    case .targetSelectionPaths: "Selected items in the other pane (full paths)"
    case .sourceSelectionNames: "Selected items in the active pane (names)"
    case .targetSelectionNames: "Selected items in the other pane (names)"
    }
  }
}

public enum ToolCommandBuilder {
  public struct Context: Sendable {
    public var sourcePath: String?
    public var targetPath: String?
    public var sourceSelection: [String]
    public var targetSelection: [String]

    public init(
      sourcePath: String?, targetPath: String? = nil, sourceSelection: [String] = [],
      targetSelection: [String] = []
    ) {
      self.sourcePath = sourcePath
      self.targetPath = targetPath
      self.sourceSelection = sourceSelection
      self.targetSelection = targetSelection
    }
  }

  /// The shell command lines to run. Every substituted path or name is quoted as one literal
  /// shell word; a missing value becomes an empty string. With `runForEachFile` there is one line
  /// per selected source item, and none when nothing is selected.
  public static func expand(_ tool: UserTool, context: Context) -> [String] {
    guard tool.runForEachFile else { return [substitute(tool.command, context)] }
    return context.sourceSelection.map { item in
      var single = context
      single.sourceSelection = [item]
      return substitute(tool.command, single)
    }
  }

  /// Longest names first, so `$SOURCE_PATH` never matches the start of `$SOURCE_SELECTION_PATHS`.
  private static let placeholders = ToolPlaceholder.allCases.sorted {
    $0.rawValue.count > $1.rawValue.count
  }

  /// One pass over the command, so text inside a substituted path is never expanded again.
  private static func substitute(_ command: String, _ context: Context) -> String {
    var result = ""
    var index = command.startIndex
    while index < command.endIndex {
      let rest = command[index...]
      if rest.first == "$",
        let match = placeholders.first(where: { placeholder in
          rest.hasPrefix(placeholder.rawValue)
            && !isWordCharacter(rest.dropFirst(placeholder.rawValue.count).first)
        })
      {
        result += value(of: match, context)
        index = command.index(index, offsetBy: match.rawValue.count)
      } else {
        result.append(command[index])
        index = command.index(after: index)
      }
    }
    return result
  }

  private static func isWordCharacter(_ character: Character?) -> Bool {
    guard let character else { return false }
    return character == "_" || character.isLetter || character.isNumber
  }

  private static func value(of placeholder: ToolPlaceholder, _ context: Context) -> String {
    func quote(_ values: [String]) -> String {
      values.map(CopyPathFormatter.shellQuoted).joined(separator: " ")
    }
    func names(_ paths: [String]) -> [String] { paths.map { ($0 as NSString).lastPathComponent } }
    switch placeholder {
    case .sourcePath: return quote(context.sourcePath.map { [$0] } ?? [])
    case .targetPath: return quote(context.targetPath.map { [$0] } ?? [])
    case .sourceSelectionPaths: return quote(context.sourceSelection)
    case .targetSelectionPaths: return quote(context.targetSelection)
    case .sourceSelectionNames: return quote(names(context.sourceSelection))
    case .targetSelectionNames: return quote(names(context.targetSelection))
    }
  }
}
