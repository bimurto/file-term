import AppKit
import Darwin
import Observation
import SwiftTerm

/// Owns one PTY for its entire lifetime, independently of SwiftUI view mounting.
@MainActor @Observable
final class TerminalSession {
  enum Status: Equatable {
    case starting, ready, busy, syncPaused
    case exited(Int32?)
    case failed(String)
    case closed
  }

  private(set) var directory: String?
  private(set) var isBusy = true
  private(set) var hasPendingInput = false
  private(set) var status: Status = .starting
  private(set) var title = "Terminal"
  private(set) var isReady = false
  var onDirectory: ((String) -> Void)?
  var onReady: (() -> Void)?
  var onStateChange: (() -> Void)?
  var onRevealPath: ((String) -> Void)?

  @ObservationIgnored let terminalView: SessionTerminalView
  /// Alias useful to NSViewRepresentable hosts. Do not replace its process delegate.
  var view: LocalProcessTerminalView { terminalView }
  @ObservationIgnored private var integration: ShellIntegration?
  @ObservationIgnored private var monitor: Timer?
  @ObservationIgnored private var parser = ShellOSCParser()
  @ObservationIgnored private var atPrompt = false
  @ObservationIgnored private var freshPromptCycle = false
  @ObservationIgnored private var closed = false
  @ObservationIgnored private var pendingDirectory: String?
  @ObservationIgnored private let delegateProxy = SessionProcessDelegate()

  init(directory: String, preferences: TerminalPreferences) {
    let cursor: CursorStyle =
      switch preferences.cursorStyle {
      case .block: .steadyBlock
      case .underline: .steadyUnderline
      case .bar: .steadyBar
      }
    let fontSize = CGFloat(
      preferences.fontSize.isFinite ? min(48, max(8, preferences.fontSize)) : 13)
    terminalView = SessionTerminalView(
      frame: NSRect(x: 0, y: 0, width: 800, height: 400),
      font: NSFont(name: preferences.fontName, size: fontSize)
        ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
      options: TerminalOptions(
        cursorStyle: cursor, scrollback: min(100_000, max(0, preferences.scrollbackLines)))
    )
    terminalView.session = self
    delegateProxy.session = self
    terminalView.processDelegate = delegateProxy
    do {
      let integration = try ShellIntegration(
        shell: preferences.shellPath,
        login: preferences.loginShell, interactive: preferences.interactiveShell,
        enabled: preferences.integrationEnabled)
      self.integration = integration
      terminalView.startProcess(
        executable: integration.executable, args: integration.arguments,
        environment: integration.environment, currentDirectory: directory)
      if !terminalView.process.running {
        status = .failed("Unable to launch \(preferences.shellPath)")
        integration.cleanup()
      } else {
        if !integration.isSupported { status = .syncPaused }
        monitor = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
          MainActor.assumeIsolated { self?.pollProcess() }
        }
      }
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  /// The PTY foreground check is mandatory even if a program forged OSC prompt markers.
  var canSendDirectory: Bool {
    !closed && isReady && atPrompt && !isBusy && !hasPendingInput && shellOwnsForeground
  }

  private var shellOwnsForeground: Bool {
    let process = terminalView.process!
    return process.running && process.shellPid > 0 && process.childfd >= 0
      && tcgetpgrp(process.childfd) == process.shellPid
  }

  @discardableResult
  func sendDirectory(_ path: String) -> Bool {
    guard path.hasPrefix("/") else { return false }
    return sendCommand(" cd -- \(quotePath(path))")
  }

  /// Types one line into an idle local shell, with the same guards as a directory change. Only
  /// for commands the app builds itself; never text that came from a remote program.
  @discardableResult
  func sendCommand(_ line: String) -> Bool {
    guard canSendDirectory, !line.utf8.contains(0),
      !line.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { return false }
    pendingDirectory = nil
    atPrompt = false
    isBusy = true
    status = .busy
    onStateChange?()
    // Bypass the user-input callback: this is a guarded, app-generated command.
    terminalView.process.send(data: Array((line + "\r").utf8)[...])
    return true
  }

  @discardableResult
  func sendDirectory(path: String) -> Bool { sendDirectory(path) }

  func quotePath(_ path: String) -> String {
    let fish = URL(fileURLWithPath: integration?.executable ?? "").lastPathComponent == "fish"
    return fish ? ShellIntegration.fishQuote(path) : ShellIntegration.quote(path)
  }

  func insert(_ text: String) {
    guard !closed, terminalView.process.running, !text.utf8.contains(0) else { return }
    userInput()
    // Insertion is not execution: strip terminal controls, including CR/LF, from supplied text.
    let safe = String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
    if terminalView.getTerminal().bracketedPasteMode {
      terminalView.send(txt: "\u{1b}[200~" + safe + "\u{1b}[201~")
    } else {
      terminalView.send(txt: safe)
    }
  }

  func insert(text: String) { insert(text) }

  func focus() { terminalView.window?.makeFirstResponder(terminalView) }

  func clear() {
    terminalView.feed(text: "\u{1b}[3J\u{1b}[2J\u{1b}[H")
  }

  @discardableResult
  func find(_ text: String) -> Bool {
    if text.isEmpty {
      terminalView.clearSearch()
      return false
    }
    return terminalView.findNext(text)
  }

  func close() {
    guard !closed else { return }
    closed = true
    monitor?.invalidate()
    monitor = nil
    isReady = false
    isBusy = false
    status = .closed
    let process = terminalView.process!
    let pid = process.shellPid
    if process.running && pid > 0 {
      // A foreground job is a separate process group. Signal it too while its identity is live.
      let foreground = tcgetpgrp(process.childfd)
      if foreground > 0 && foreground != pid {
        ForegroundJobShutdown.begin(group: foreground, session: pid)
      }
      kill(-pid, SIGHUP)
      kill(pid, SIGHUP)
      // Retain the process through escalation, never signal after SwiftTerm observes its exit.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
        guard process.running, process.shellPid == pid, getpgid(pid) == pid else { return }
        kill(-pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
          guard process.running, process.shellPid == pid, getpgid(pid) == pid else { return }
          kill(-pid, SIGKILL)
        }
      }
    }
    integration?.cleanup()
  }

  fileprivate func userInput() {
    guard !closed else { return }
    defer { onStateChange?() }
    // Even backspace, arrow keys and Ctrl-U latch; only a genuine next prompt resets this.
    hasPendingInput = true
    freshPromptCycle = false
    pendingDirectory = nil
  }

  fileprivate func submittedInput() {
    atPrompt = false
    isBusy = true
    status = .busy
    onStateChange?()
  }

  fileprivate func received(_ bytes: ArraySlice<UInt8>) {
    guard !closed else { return }
    defer { onStateChange?() }
    for event in parser.consume(bytes) {
      switch event {
      case .directory(let path):
        // OSC 7 is staged until a matching integration prompt; never trust arbitrary applications.
        if shellOwnsForeground { pendingDirectory = path }
      case .prompt(let payload):
        guard let integration, integration.isSupported,
          payload.split(separator: ";").contains(Substring("fileterm=\(integration.token)")),
          shellOwnsForeground
        else { continue }
        let marker = payload.split(separator: ";").first
        if marker == "A" {
          freshPromptCycle = true
          atPrompt = false
        } else if marker == "B" {
          guard freshPromptCycle else { continue }
          freshPromptCycle = false
          atPrompt = true
          isBusy = false
          hasPendingInput = false
          status = .ready
          if let path = pendingDirectory {
            let changed = directory != path
            directory = path
            pendingDirectory = nil
            if changed { onDirectory?(path) }
          }
          isReady = true
          onReady?()
        } else if marker == "C" {
          freshPromptCycle = false
          atPrompt = false
          isBusy = true
          status = .busy
        }
      }
    }
  }

  fileprivate func ended(_ code: Int32?) {
    defer { onStateChange?() }
    monitor?.invalidate()
    monitor = nil
    isReady = false
    atPrompt = false
    isBusy = false
    if !closed { status = .exited(code) }
    integration?.cleanup()
  }

  fileprivate func changedTitle(_ value: String) { title = value }

  private func pollProcess() {
    guard !closed else { return }
    let previousBusy = isBusy
    defer { if previousBusy != isBusy { onStateChange?() } }
    guard terminalView.process.running else {
      ended(nil)
      return
    }
    if !shellOwnsForeground {
      atPrompt = false
      isBusy = true
      if integration?.isSupported == true { status = .busy }
    }
    // Do not infer readiness from foreground ownership: only a new prompt can authorize injection.
  }
}

/// Captures foreground group members' kernel start times before signaling, preventing
/// delayed escalation from hitting reused PIDs even after the group leader has exited.
@MainActor
private enum ForegroundJobShutdown {
  private struct Identity: Equatable {
    let seconds: UInt64
    let microseconds: UInt64
  }

  private static func identity(_ pid: pid_t) -> Identity? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return Identity(seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec)
  }

  static func begin(group: pid_t, session: pid_t) {
    // A pipeline can outlive its group leader. Enumerate members instead of treating
    // the group ID as a live PID; every delayed signal validates that member's identity.
    let needed = proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(group), nil, 0)
    guard needed > 0 else { return }
    var pids = [pid_t](repeating: 0, count: Int(needed) / MemoryLayout<pid_t>.size + 32)
    let bytes = pids.withUnsafeMutableBytes {
      proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(group), $0.baseAddress, Int32($0.count))
    }
    guard bytes > 0 else { return }
    let members = pids.prefix(Int(bytes) / MemoryLayout<pid_t>.size).compactMap {
      pid -> (pid_t, Identity)? in
      guard pid > 0, getsid(pid) == session, getpgid(pid) == group, let original = identity(pid)
      else { return nil }
      return (pid, original)
    }
    func signal(_ value: Int32) {
      for (pid, original) in members {
        guard identity(pid) == original, getsid(pid) == session, getpgid(pid) == group else {
          continue
        }
        kill(pid, value)
      }
    }
    signal(SIGHUP)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
      signal(SIGTERM)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { signal(SIGKILL) }
    }
  }
}

/// SwiftTerm's LocalProcess delivers callbacks on DispatchQueue.main by default.
/// Intercept input here rather than keyDown so paste and IME input are also tracked.
@MainActor
final class SessionTerminalView: LocalProcessTerminalView {
  weak var session: TerminalSession?
  private var outputFilter = ClipboardOSCFilter()

  override init(frame: CGRect, font: NSFont? = nil, options: TerminalOptions) {
    super.init(frame: frame, font: font, options: options)
    updateAppearance()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateAppearance()
  }

  private func updateAppearance() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      nativeForegroundColor = NSColor.textColor.usingColorSpace(.deviceRGB) ?? .textColor
      nativeBackgroundColor =
        NSColor.textBackgroundColor.usingColorSpace(.deviceRGB) ?? .textBackgroundColor
      caretColor = NSColor.textColor.usingColorSpace(.deviceRGB) ?? .textColor
    }
  }

  required init?(coder: NSCoder) { fatalError("Use init(frame:font:options:)") }

  override func dataReceived(slice: ArraySlice<UInt8>) {
    session?.received(slice)
    let filtered = outputFilter.consume(slice)
    super.dataReceived(slice: filtered[...])
  }

  override func send(source: TerminalView, data: ArraySlice<UInt8>) {
    if !data.isEmpty {
      session?.userInput()
      if data.contains(13) || data.contains(10) { session?.submittedInput() }
    }
    super.send(source: source, data: data)
  }

  override func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
    if let path = ShellOSCParser.localDirectory(link) {
      session?.onRevealPath?(path)
    } else if let url = URL(string: link), ["https", "http"].contains(url.scheme ?? "") {
      NSWorkspace.shared.open(url)
    }
  }
}

@MainActor
private final class SessionProcessDelegate: @preconcurrency LocalProcessTerminalViewDelegate {
  weak var session: TerminalSession?
  func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
  func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
    session?.changedTitle(title)
  }
  func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
  func processTerminated(source: TerminalView, exitCode: Int32?) { session?.ended(exitCode) }
}

/// SwiftTerm's LocalProcessTerminalView clipboard-read delegate is not overridable.
/// Filter OSC 52 (both copy and read) before the emulator sees it, including split sequences.
struct ClipboardOSCFilter {
  private var pending: [UInt8] = []
  private var inOSC = false
  private var escaped = false
  private var dropping = false
  private var utf8Remaining = 0

  /// SwiftTerm reads the OSC number as a decimal, so `052` also means 52.
  private static func isClipboardSequence(_ sequence: [UInt8]) -> Bool {
    let body = sequence.first == 0x9d ? sequence.dropFirst() : sequence.dropFirst(2)
    let digits = body.prefix { $0 >= 48 && $0 <= 57 }
    return digits.drop { $0 == 48 }.elementsEqual([53, 50])
  }

  mutating func consume(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
    var output: [UInt8] = []
    for byte in bytes {
      let continuation = utf8Remaining > 0 && byte >= 0x80 && byte <= 0xbf
      if continuation {
        utf8Remaining -= 1
      } else {
        utf8Remaining =
          byte >= 0xc2 && byte <= 0xdf
          ? 1
          : (byte >= 0xe0 && byte <= 0xef ? 2 : (byte >= 0xf0 && byte <= 0xf4 ? 3 : 0))
      }
      if inOSC {
        if !dropping { pending.append(byte) }
        if byte == 7 || (byte == 0x9c && !continuation) || byte == 0x18 || byte == 0x1a
          || (escaped && byte == 0x5c)
        {
          if !dropping && !Self.isClipboardSequence(pending) { output += pending }
          pending.removeAll(keepingCapacity: true)
          inOSC = false
          dropping = false
          escaped = false
        } else {
          escaped = byte == 27
          if pending.count > 65536 {
            dropping = true
            pending.removeAll(keepingCapacity: true)
          }
        }
      } else if pending == [27] {
        if byte == 93 {
          pending.append(byte)
          inOSC = true
        } else {
          output.append(27)
          pending.removeAll(keepingCapacity: true)
          if byte == 27 { pending.append(byte) } else { output.append(byte) }
        }
      } else if byte == 27 {
        pending.append(byte)
      } else if byte == 0x9d && !continuation {
        pending.append(byte)
        inOSC = true
      } else {
        output.append(byte)
      }
    }
    return output
  }
}
