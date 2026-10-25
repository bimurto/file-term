import FileTermCore
import Foundation

/// A bounded streaming OSC decoder. Escape sequences may cross arbitrary PTY reads.
struct ShellOSCParser {
  enum Event: Equatable {
    case directory(String)
    case prompt(String)
  }

  private enum State { case text, escape, osc, oscEscape, discard, discardEscape }
  private var state = State.text
  private var payload: [UInt8] = []

  mutating func consume(_ bytes: ArraySlice<UInt8>) -> [Event] {
    var events: [Event] = []
    for byte in bytes {
      switch state {
      case .text:
        if byte == 0x1b { state = .escape }
      case .escape:
        state = byte == 0x5d ? .osc : (byte == 0x1b ? .escape : .text)
        payload.removeAll(keepingCapacity: true)
      case .osc:
        if byte == 7 {
          finish(into: &events)
        } else if byte == 0x1b {
          state = .oscEscape
        } else if byte == 0x18 || byte == 0x1a {
          state = .text
        } else if payload.count < 16384 {
          payload.append(byte)
        } else {
          payload.removeAll(keepingCapacity: true)
          state = .discard
        }
      case .oscEscape:
        if byte == 0x5c {
          finish(into: &events)
        } else {
          payload.removeAll(keepingCapacity: true)
          state = byte == 0x5d ? .osc : .text
        }
      case .discard:
        if byte == 7 { state = .text } else if byte == 0x1b { state = .discardEscape }
      case .discardEscape:
        state = byte == 0x5c ? .text : .discard
      }
    }
    return events
  }

  private mutating func finish(into events: inout [Event]) {
    state = .text
    guard let text = String(bytes: payload, encoding: .utf8) else { return }
    if text.hasPrefix("133;") {
      events.append(.prompt(String(text.dropFirst(4))))
    } else if text.hasPrefix("7;"), let path = Self.localDirectory(String(text.dropFirst(2))) {
      events.append(.directory(path))
    }
    payload.removeAll(keepingCapacity: true)
  }

  static func localDirectory(_ value: String) -> String? {
    TerminalSyncState.localDirectory(
      fromOSC7: value,
      localHostnames: [ProcessInfo.processInfo.hostName])?.path
  }
}

/// Ephemeral shell startup files; never edits a user's rc files.
final class ShellIntegration {
  let executable: String
  let arguments: [String]
  let environment: [String]
  let isSupported: Bool
  let token = UUID().uuidString
  private(set) var temporaryDirectory: URL?

  static func quote(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  /// Fish's single-quote rules differ from POSIX shells.
  static func fishQuote(_ text: String) -> String {
    "'"
      + text.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "'", with: "\\'") + "'"
  }

  init(
    shell: String, login: Bool, interactive: Bool, enabled: Bool,
    environment base: [String: String] = ProcessInfo.processInfo.environment
  ) throws {
    executable = shell
    let kind = URL(fileURLWithPath: shell).lastPathComponent
    isSupported = enabled && interactive && ["zsh", "bash", "fish"].contains(kind)
    var env = base
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"
    if env["LANG"] == nil || env["LANG"] == "C" {
      env["LANG"] = "en_US.UTF-8"
    }
    var args: [String] = []
    if !isSupported {
      if login { args.append("-l") }
      if interactive { args.append("-i") }
      arguments = args
      environment = env.map { "\($0.key)=\($0.value)" }
      return
    }
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("fileterm-shell-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    temporaryDirectory = root
    do {
      switch kind {
      case "zsh":
        let original = env["ZDOTDIR"] ?? env["HOME"] ?? NSHomeDirectory()
        // .zshenv may change ZDOTDIR; remember it while keeping the shim in the startup chain.
        try Self.write(
          """
          typeset -g __fileterm_user_zdotdir=\(Self.quote(original))
          [[ -f "$__fileterm_user_zdotdir/.zshenv" ]] && source "$__fileterm_user_zdotdir/.zshenv"
          __fileterm_user_zdotdir=${ZDOTDIR:-$HOME}
          [[ "$__fileterm_user_zdotdir" == \(Self.quote(root.path)) ]] && __fileterm_user_zdotdir=\(Self.quote(original))
          ZDOTDIR=\(Self.quote(root.path))
          """, name: ".zshenv", root: root)
        for name in [".zprofile", ".zshrc", ".zlogin"] {
          var content = """
            ZDOTDIR=$__fileterm_user_zdotdir
            [[ -f "$ZDOTDIR/\(name)" ]] && source "$ZDOTDIR/\(name)"
            __fileterm_user_zdotdir=${ZDOTDIR:-$HOME}
            ZDOTDIR=\(Self.quote(root.path))

            """
          if name == ".zshrc" { content += Self.zshHooks(token: token) }
          if name == ".zlogin" || (name == ".zshrc" && !login) {
            content += "\nZDOTDIR=$__fileterm_user_zdotdir\n"
          }
          try Self.write(content, name: name, root: root)
        }
        env["ZDOTDIR"] = root.path
        args = login ? ["-l", "-i"] : ["-i"]
      case "bash":
        if login {
          // A real login shell owns profile/logout semantics. If a profile replaces
          // PROMPT_COMMAND, integration safely remains unavailable; never inject bootstrap input.
          let previous = env["PROMPT_COMMAND"] ?? ""
          let startup =
            "PROMPT_COMMAND=" + Self.quote(previous) + "\n"
            + Self.bashHooks(token: token) + "\n__fileterm_prompt\n"
          try Self.write(startup, name: "bashrc", root: root)
          env["PROMPT_COMMAND"] = "source " + Self.quote(root.appendingPathComponent("bashrc").path)
          args = ["-l", "-i"]
        } else {
          let startup = "[[ -f \"$HOME/.bashrc\" ]] && source \"$HOME/.bashrc\"\n"
          try Self.write(startup + Self.bashHooks(token: token), name: "bashrc", root: root)
          args = ["--rcfile", root.appendingPathComponent("bashrc").path, "-i"]
        }
      default:
        try Self.write(Self.fishHooks(token: token), name: "integration.fish", root: root)
        args =
          (login ? ["-l"] : []) + [
            "-i", "--init-command",
            "source " + Self.fishQuote(root.appendingPathComponent("integration.fish").path),
          ]
      }
      arguments = args
      environment = env.map { "\($0.key)=\($0.value)" }
    } catch {
      try? FileManager.default.removeItem(at: root)
      throw error
    }
  }

  func cleanup() {
    if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    temporaryDirectory = nil
  }

  deinit { cleanup() }

  private static func write(_ value: String, name: String, root: URL) throws {
    try value.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
  }

  // Encode UTF-8 bytes, not Unicode scalar values. Keep only '/' literal in the URI path.
  private static let encodePWD =
    #"printf '%s' "$PWD" | /usr/bin/od -An -v -tu1 | /usr/bin/awk '{for(i=1;i<=NF;i++) if($i==47) printf "/"; else printf "%%%02X",$i}'"#

  static func zshHooks(token: String) -> String {
    """

    setopt HIST_IGNORE_SPACE
    __fileterm_precmd() {
      local __fileterm_status=$?
      printf '\\033]133;D;%s;fileterm=\(token)\\007' "$__fileterm_status"
      printf '\\033]7;file://localhost%s\\007' "$(\(encodePWD))"
      printf '\\033]133;A;fileterm=\(token)\\007'
      local __fileterm_marker=$'%{\\e]133;B;fileterm=\(token)\\a%}'
      [[ $PS1 == *$__fileterm_marker* ]] || PS1+=$__fileterm_marker
    }
    __fileterm_preexec() { printf '\\033]133;C;fileterm=\(token)\\007'; }
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd __fileterm_precmd
    add-zsh-hook preexec __fileterm_preexec
    PS1+=$'%{\\e]133;B;fileterm=\(token)\\a%}'
    """
  }

  static func bashHooks(token: String) -> String {
    """

    HISTCONTROL="${HISTCONTROL:+$HISTCONTROL:}ignorespace"
    __fileterm_prompt() {
      local __fileterm_status=$?
      printf '\\033]133;D;%s;fileterm=\(token)\\007' "$__fileterm_status"
      printf '\\033]7;file://localhost%s\\007' "$(\(encodePWD))"
      printf '\\033]133;A;fileterm=\(token)\\007'
    }
    if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == 'declare -a'* ]]; then
      PROMPT_COMMAND+=(__fileterm_prompt)
    else
      PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }__fileterm_prompt"
    fi
    PS1+='\\[\\e]133;B;fileterm=\(token)\\a\\]'
    """
  }

  static func fishHooks(token: String) -> String {
    """
    function __fileterm_prompt --on-event fish_prompt
      set -l __fileterm_status $status
      printf '\\033]133;D;%s;fileterm=\(token)\\007' $__fileterm_status
      set -l __fileterm_uri (\(encodePWD))
      printf '\\033]7;file://localhost%s\\007' "$__fileterm_uri"
      printf '\\033]133;A;fileterm=\(token)\\007'
    end
    functions -c fish_prompt __fileterm_original_fish_prompt
    function fish_prompt
      __fileterm_original_fish_prompt
      printf '\\033]133;B;fileterm=\(token)\\007'
    end
    function __fileterm_preexec --on-event fish_preexec
      printf '\\033]133;C;fileterm=\(token)\\007'
    end
    """
  }
}
