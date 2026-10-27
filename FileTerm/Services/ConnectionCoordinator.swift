import AppKit
import FileTermCore
import NetFS
import Observation

enum ConnectionError: Error, LocalizedError, Equatable {
  case notYetAvailable(protocolName: String, ticket: String)
  case mountFailed(String)
  case couldNotOpen

  var errorDescription: String? {
    switch self {
    case .notYetAvailable(let name, let ticket):
      "\(name) connections are not available yet. They arrive with M08 \(ticket)."
    case .mountFailed(let message): message
    case .couldNotOpen: "No application could open the screen-sharing address."
    }
  }
}

/// Mounts a network share through the OS and returns the local mount point.
protocol VolumeMounter: Sendable {
  func mount(_ url: URL, user: String?, password: String?) async throws -> URL
}

struct NetFSMounter: VolumeMounter {
  func mount(_ url: URL, user: String?, password: String?) async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      let options = NSMutableDictionary()
      // Without a stored password the system may ask for one; with one it must stay silent.
      // A URL without a share name needs the system's share picker, so it cannot be silent.
      if password != nil, !url.path.isEmpty, url.path != "/" {
        options[kNAUIOptionKey as String] = kNAUIOptionNoUI
      }
      var request: AsyncRequestID?
      let status = NetFSMountURLAsync(
        url as CFURL, nil, user as CFString?, password as CFString?, options, nil, &request,
        DispatchQueue.global()
      ) { status, _, mountPoints in
        if status == 0 || status == EEXIST,
          let path = (mountPoints as? [String])?.first
        {
          continuation.resume(returning: URL(fileURLWithPath: path))
        } else {
          let reason =
            status == EAUTH || status == EACCES
            ? "The server rejected the user name or password."
            : NSError(domain: NSPOSIXErrorDomain, code: Int(status)).localizedDescription
          let message = "\(reason) (NetFS error \(status))"
          continuation.resume(throwing: ConnectionError.mountFailed(message))
        }
      }
      if status != 0 {
        continuation.resume(
          throwing: ConnectionError.mountFailed("Could not start the connection."))
      }
    }
  }
}

struct OpenConnection: Identifiable, Equatable {
  let profile: ConnectionProfile
  let mountURL: URL
  var id: UUID { profile.id }
}

@MainActor @Observable final class ConnectionCoordinator {
  private(set) var open: [OpenConnection] = []
  private(set) var isConnecting = false
  @ObservationIgnored private let settings: AppSettings
  @ObservationIgnored private let credentials: CredentialStore
  @ObservationIgnored private let mounter: VolumeMounter
  @ObservationIgnored private let openExternal: (URL) -> Bool

  init(
    settings: AppSettings, credentials: CredentialStore = KeychainCredentialStore(),
    mounter: VolumeMounter = NetFSMounter(),
    openExternal: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
  ) {
    self.settings = settings
    self.credentials = credentials
    self.mounter = mounter
    self.openExternal = openExternal
  }

  var profiles: [ConnectionProfile] { settings.connections.profiles }
  var savedProfiles: [ConnectionProfile] { profiles.filter(\.isFavorite) }

  func storedPassword(for profile: ConnectionProfile) -> String? {
    credentials.password(for: profile.id)
  }

  /// Saves without connecting. An empty password keeps the one already in the keychain.
  func save(_ profile: ConnectionProfile, password: String) throws {
    if !password.isEmpty { try credentials.setPassword(password, for: profile.id) }
    if let index = settings.connections.profiles.firstIndex(where: { $0.id == profile.id }) {
      settings.connections.profiles[index] = profile
    } else {
      settings.connections.profiles.append(profile)
    }
  }

  func remove(_ profile: ConnectionProfile) {
    settings.connections.profiles.removeAll { $0.id == profile.id }
    credentials.deletePassword(for: profile.id)
  }

  /// The only call that touches the network. Returns the mount point to browse, or nil for
  /// protocols handed to another application (VNC).
  @discardableResult
  func connect(_ profile: ConnectionProfile, password: String? = nil) async throws -> URL? {
    guard profile.kind.availability == .available else {
      if case .plannedIn(let ticket) = profile.kind.availability {
        throw ConnectionError.notYetAvailable(
          protocolName: profile.kind.title, ticket: ticket)
      }
      return nil
    }
    let url = try profile.url()
    if profile.kind == .vnc {
      guard openExternal(url) else { throw ConnectionError.couldNotOpen }
      return nil
    }
    isConnecting = true
    defer { isConnecting = false }
    let secret = password.flatMap { $0.isEmpty ? nil : $0 } ?? credentials.password(for: profile.id)
    let mountURL = try await mounter.mount(
      url, user: profile.username.isEmpty ? nil : profile.username, password: secret)
    open.removeAll { $0.id == profile.id }
    open.append(OpenConnection(profile: profile, mountURL: mountURL.standardizedFileURL))
    return mountURL
  }

  /// Applies Settings › General › Open remote connections in.
  func placementPane(in browser: BrowserModel) -> PaneID {
    switch settings.connections.remotePlacement {
    case .left:
      browser.activePaneID = .first
      return .first
    case .right:
      if browser.layout == .single { browser.setLayout(.vertical) }
      return .second
    case .active: return browser.activePaneID
    }
  }

  func reveal(_ connection: OpenConnection, in browser: BrowserModel) async {
    let pane = placementPane(in: browser)
    await browser.navigate(
      to: Location(providerID: "local", path: connection.mountURL.path), in: pane)
  }

  func connectAndReveal(
    _ profile: ConnectionProfile, password: String? = nil, in browser: BrowserModel
  ) async throws {
    guard let mountURL = try await connect(profile, password: password),
      let connection = open.first(where: { $0.mountURL == mountURL.standardizedFileURL })
    else { return }
    await reveal(connection, in: browser)
  }

  func disconnect(_ connection: OpenConnection) throws {
    try NSWorkspace.shared.unmountAndEjectDevice(at: connection.mountURL)
  }

  func handleUnmount(at url: URL) {
    let path = url.standardizedFileURL.path
    open.removeAll { $0.mountURL.path == path }
  }

  /// The Base URL for a location below an open connection's mount (M08.02).
  func publicURL(for location: Location) -> URL? {
    guard location.providerID == "local" else { return nil }
    for connection in open {
      let root = connection.mountURL.path
      guard location.path == root || location.path.hasPrefix(root + "/") else { continue }
      return connection.profile.publicURL(
        forRelativePath: String(location.path.dropFirst(root.count)))
    }
    return nil
  }
}
