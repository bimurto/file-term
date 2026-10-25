import Foundation

/// One instance belongs to one pane-tab/terminal pair. This type performs no I/O or scheduling.
/// Apply returned effects in order on the coordinator's serialized event loop. Only report `.idle`
/// when shell integration confirms a prompt; silence/output inactivity is not evidence of idle.
public struct TerminalSyncState: Sendable {
  public enum ShellPhase: Equatable, Sendable {
    case unknown, idle, running
  }

  public enum Effect: Equatable, Sendable {
    /// Complete shell input including its terminating carriage return. Never paste into a busy shell.
    case sendCommand(String)
    case navigatePane(Location)
  }

  public private(set) var paneLocation: Location
  public private(set) var terminalLocation: Location?
  public private(set) var pendingPaneLocation: Location?
  public private(set) var isLinked: Bool
  public private(set) var reverseSyncEnabled: Bool
  public private(set) var shellPhase: ShellPhase = .unknown
  public private(set) var hasPendingInput = true
  public var isPausedForNonlocalLocation: Bool { paneLocation.providerID != "local" }

  private let localHostnames: Set<String>
  private var commandInFlight = false

  /// Hostnames must be explicitly supplied by the runtime; no DNS or machine-name lookup occurs.
  /// Empty host and localhost are always accepted. Initial pane location is not a navigation event.
  public init(
    paneLocation: Location, isLinked: Bool = true, reverseSyncEnabled: Bool = true,
    localHostnames: Set<String> = []
  ) {
    self.paneLocation = paneLocation
    self.isLinked = isLinked
    self.reverseSyncEnabled = reverseSyncEnabled
    self.localHostnames = localHostnames
  }

  /// Unlinking discards pending pane intent. Relinking reconciles using the latest terminal cwd.
  @discardableResult
  public mutating func setLinked(_ linked: Bool) -> [Effect] {
    isLinked = linked
    if !linked { pendingPaneLocation = nil }
    return reconcile()
  }

  @discardableResult
  public mutating func setReverseSyncEnabled(_ enabled: Bool) -> [Effect] {
    reverseSyncEnabled = enabled
    return reconcile()
  }

  /// Notify on actual navigation, including navigation caused by a returned effect. Identical
  /// locations are ignored, suppressing reverse-sync echoes without swallowing later user intent.
  @discardableResult
  public mutating func paneNavigated(to location: Location) -> [Effect] {
    guard location != paneLocation else { return [] }
    paneLocation = location
    guard isLinked, location.providerID == "local", Self.isSafePath(location.path) else {
      pendingPaneLocation = nil
      return []
    }
    pendingPaneLocation = location
    return reconcile()
  }

  /// A fresh idle notification acknowledges completion of any emitted cd (including failure).
  /// When editing input, keep hasPendingInput true even if the foreground process is the shell.
  @discardableResult
  public mutating func shellUpdated(phase: ShellPhase, hasPendingInput: Bool) -> [Effect] {
    shellPhase = phase
    self.hasPendingInput = hasPendingInput
    if phase == .idle { commandInFlight = false }
    return reconcile()
  }

  /// Accepts only the OSC 7 payload, not the OSC framing or escape terminator. Invalid payloads
  /// leave the last known cwd untouched. OSC 7 alone never proves that a shell is idle.
  @discardableResult
  public mutating func receiveOSC7(_ payload: String) -> [Effect] {
    guard let url = Self.localDirectory(fromOSC7: payload, localHostnames: localHostnames) else {
      return []
    }
    terminalLocation = Location(providerID: "local", path: url.path)
    return reconcile()
  }

  private mutating func reconcile() -> [Effect] {
    guard isLinked, !isPausedForNonlocalLocation, Self.isSafePath(paneLocation.path),
      shellPhase == .idle, !hasPendingInput, !commandInFlight
    else { return [] }

    if let target = pendingPaneLocation {
      pendingPaneLocation = nil
      if target == terminalLocation { return [] }
      // Reserve the shell immediately: no second write before a fresh prompt notification.
      commandInFlight = true
      return [.sendCommand("cd -- " + CopyPathFormatter.shellQuoted(target.path) + "\r")]
    }
    guard reverseSyncEnabled, let terminalLocation, terminalLocation != paneLocation else {
      return []
    }
    paneLocation = terminalLocation
    return [.navigatePane(terminalLocation)]
  }

  /// Strict local file URL validation. Rejects remote authorities, credentials, ports, query,
  /// fragments, malformed percent escapes, invalid UTF-8 and control characters after decoding.
  /// Does not check existence, resolve symlinks, access the filesystem, or infer remote locality.
  public static func localDirectory(
    fromOSC7 payload: String, localHostnames: Set<String> = []
  ) -> URL? {
    guard payload.lowercased().hasPrefix("file://"),
      !payload.unicodeScalars.contains(where: {
        CharacterSet.whitespacesAndNewlines.contains($0)
          || CharacterSet.controlCharacters.contains($0)
      })
    else { return nil }

    // Foundation can repair malformed escapes; validate the original wire representation first.
    let bytes = Array(payload.utf8)
    for index in bytes.indices where bytes[index] == 0x25 {
      guard index + 2 < bytes.count, isHex(bytes[index + 1]), isHex(bytes[index + 2]) else {
        return nil
      }
    }
    guard let components = URLComponents(string: payload),
      components.scheme?.lowercased() == "file", components.user == nil,
      components.password == nil, components.port == nil,
      components.query == nil, components.fragment == nil
    else { return nil }
    let host = (components.host ?? "").lowercased()
    let allowedHosts = Set(localHostnames.map { $0.lowercased() }).union(["", "localhost"])
    guard allowedHosts.contains(host),
      let path = components.percentEncodedPath.removingPercentEncoding, isSafePath(path)
    else { return nil }
    return URL(fileURLWithPath: path)
  }

  private static func isHex(_ byte: UInt8) -> Bool {
    (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
  }

  private static func isSafePath(_ path: String) -> Bool {
    path.hasPrefix("/")
      && !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
  }
}
