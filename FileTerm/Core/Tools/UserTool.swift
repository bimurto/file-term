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

/// One shell command of a tool.
public struct ToolCommand: Equatable, Sendable {
  /// The script for `/bin/sh -c`. It refers to file names only through variables.
  public let line: String
  /// The variables `line` reads.
  public let environment: [String: String]
  /// The command with its values written out, for logs and the output window. Never run this.
  public let displayLine: String
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

  /// The commands to run. With `runForEachFile` there is one per selected source item, and none
  /// when nothing is selected. A value never becomes part of the shell's script, only of its
  /// environment, so nothing in a file name can run, however the placeholder is quoted.
  public static func expand(_ tool: UserTool, context: Context) -> [ToolCommand] {
    guard tool.runForEachFile else { return [build(tool.command, context)] }
    return context.sourceSelection.map { item in
      var single = context
      single.sourceSelection = [item]
      return build(tool.command, single)
    }
  }

  /// Longest names first, so `$SOURCE_PATH` never matches the start of `$SOURCE_SELECTION_PATHS`.
  private static let placeholders = ToolPlaceholder.allCases.sorted {
    $0.rawValue.count > $1.rawValue.count
  }

  private enum Quoting { case none, single, double }

  /// One pass over the command, tracking the quoting around each placeholder. A wrong guess, as in
  /// unusual nesting, can only split a value into words or leave it out; it can't run it.
  private static func build(_ command: String, _ context: Context) -> ToolCommand {
    var line = ""
    var shown = ""
    var environment: [String: String] = [:]
    var quoting = Quoting.none
    var outerQuoting: [Quoting] = []
    var index = command.startIndex
    func copy(_ text: Substring) {
      line += text
      shown += text
      index = text.endIndex
    }
    while index < command.endIndex {
      let rest = command[index...]
      let character = command[index]
      let opensSubstitution = character == "$" && rest.dropFirst().first == "("
      if character == "$",
        let match = placeholders.first(where: { placeholder in
          rest.hasPrefix(placeholder.rawValue)
            && !isWordCharacter(rest.dropFirst(placeholder.rawValue.count).first)
        })
      {
        let name = String(match.rawValue.dropFirst())
        let items = values(of: match, context)
        switch quoting {
        case .none:
          line += words(name, items, &environment)
          shown += items.map(CopyPathFormatter.shellQuoted).joined(separator: " ")
        case .double:
          environment[name] = items.joined(separator: " ")
          line += match.rawValue
          shown += items.joined(separator: " ")
        case .single:
          // The shell keeps this as text, but a nested `sh -c '...'` can read the variable.
          environment[name] = items.joined(separator: " ")
          line += match.rawValue
          shown += match.rawValue
        }
        index = command.index(index, offsetBy: match.rawValue.count)
      } else if quoting != .single, character == "\\" {
        copy(rest.prefix(2))
      } else if quoting != .single, opensSubstitution {
        outerQuoting.append(quoting)
        quoting = .none
        copy(rest.prefix(2))
      } else {
        switch (quoting, character) {
        case (.none, "'"): quoting = .single
        case (.single, "'"): quoting = .none
        case (.none, "\""): quoting = .double
        case (.double, "\""): quoting = .none
        case (.none, ")") where !outerQuoting.isEmpty: quoting = outerQuoting.removeLast()
        default: break
        }
        copy(rest.prefix(1))
      }
    }
    return ToolCommand(line: line, environment: environment, displayLine: shown)
  }

  /// Quoted references that keep each value as one word. A missing value leaves no word at all.
  private static func words(
    _ name: String, _ items: [String], _ environment: inout [String: String]
  ) -> String {
    if items.count == 1 {
      environment[name] = items[0]
      return "\"$\(name)\""
    }
    return items.enumerated().map { offset, item in
      let numbered = "\(name)_\(offset + 1)"
      environment[numbered] = item
      return "\"$\(numbered)\""
    }.joined(separator: " ")
  }

  private static func isWordCharacter(_ character: Character?) -> Bool {
    guard let character else { return false }
    return character == "_" || character.isLetter || character.isNumber
  }

  private static func values(of placeholder: ToolPlaceholder, _ context: Context) -> [String] {
    func names(_ paths: [String]) -> [String] { paths.map { ($0 as NSString).lastPathComponent } }
    switch placeholder {
    case .sourcePath: return context.sourcePath.map { [$0] } ?? []
    case .targetPath: return context.targetPath.map { [$0] } ?? []
    case .sourceSelectionPaths: return context.sourceSelection
    case .targetSelectionPaths: return context.targetSelection
    case .sourceSelectionNames: return names(context.sourceSelection)
    case .targetSelectionNames: return names(context.targetSelection)
    }
  }
}
