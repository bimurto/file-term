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
  let root: Location
  /// Set for OS-mounted shares; remote providers have none.
  let mountURL: URL?
  var id: UUID { profile.id }
}

typealias RemoteProviderFactory =
  @Sendable (ConnectionProfile, String?) throws -> any ValidatingProvider

func makeRemoteProvider(_ profile: ConnectionProfile, password: String?) throws
  -> any ValidatingProvider
{
  guard profile.kind.isWebDAV else { throw ConnectionProfileError.unsupportedURL }
  return WebDAVProvider(
    id: "webdav.\(profile.id.uuidString)", baseURL: try profile.webDAVBaseURL(),
    username: profile.username.isEmpty ? nil : profile.username, password: password)
}

@MainActor @Observable final class ConnectionCoordinator {
  private(set) var open: [OpenConnection] = []
  private(set) var isConnecting = false
  @ObservationIgnored private let settings: AppSettings
  @ObservationIgnored private let credentials: CredentialStore
  @ObservationIgnored private let mounter: VolumeMounter
  @ObservationIgnored private let openExternal: (URL) -> Bool
  @ObservationIgnored private let registry: ProviderRegistry
  @ObservationIgnored private let remoteFactory: RemoteProviderFactory

  init(
    settings: AppSettings, registry: ProviderRegistry = ProviderRegistry(),
    credentials: CredentialStore = KeychainCredentialStore(),
    mounter: VolumeMounter = NetFSMounter(),
    remoteFactory: @escaping RemoteProviderFactory = { try makeRemoteProvider($0, password: $1) },
    openExternal: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
  ) {
    self.settings = settings
    self.registry = registry
    self.remoteFactory = remoteFactory
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
    if profile.kind.isWebDAV {
      try await connectRemote(profile, password: password)
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
    let standardized = mountURL.standardizedFileURL
    open.append(
      OpenConnection(
        profile: profile, root: Location(providerID: "local", path: standardized.path),
        mountURL: standardized))
    return mountURL
  }

  /// Validates the server, then registers its provider so any pane can browse it.
  private func connectRemote(_ profile: ConnectionProfile, password: String?) async throws {
    isConnecting = true
    defer { isConnecting = false }
    let secret = password.flatMap { $0.isEmpty ? nil : $0 } ?? credentials.password(for: profile.id)
    let provider = try remoteFactory(profile, secret)
    try await provider.validate(root: profile.rootPath)
    if let previous = open.first(where: { $0.id == profile.id }) {
      registry.unregister(id: previous.root.providerID)
      open.removeAll { $0.id == profile.id }
    }
    registry.register(provider)
    open.append(
      OpenConnection(
        profile: profile, root: Location(providerID: provider.id, path: profile.rootPath),
        mountURL: nil))
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
    await browser.navigate(to: connection.root, in: pane)
  }

  func connectAndReveal(
    _ profile: ConnectionProfile, password: String? = nil, in browser: BrowserModel
  ) async throws {
    try await connect(profile, password: password)
    guard let connection = open.first(where: { $0.id == profile.id }) else { return }
    await reveal(connection, in: browser)
  }

  func disconnect(_ connection: OpenConnection, in browser: BrowserModel, home: Location)
    async throws
  {
    if let mountURL = connection.mountURL {
      try NSWorkspace.shared.unmountAndEjectDevice(at: mountURL)
    } else {
      registry.unregister(id: connection.root.providerID)
      open.removeAll { $0.id == connection.id }
      await browser.handleDisconnect(providerID: connection.root.providerID, home: home)
    }
  }

  func handleUnmount(at url: URL) {
    let path = url.standardizedFileURL.path
    open.removeAll { $0.mountURL?.path == path }
  }

  /// "Connection name: /path" for remote locations, the plain path for local ones.
  func describe(_ location: Location) -> String {
    guard location.providerID != "local",
      let connection = open.first(where: { $0.root.providerID == location.providerID })
    else { return location.path }
    return "\(connection.profile.displayName): \(location.path)"
  }

  /// The Base URL for a location below an open connection's root (M08.02).
  func publicURL(for location: Location) -> URL? {
    for connection in open {
      let root = connection.root
      guard location.providerID == root.providerID else { continue }
      let prefix = root.path == "/" ? "" : root.path
      guard location.path == root.path || location.path.hasPrefix(prefix + "/") else { continue }
      return connection.profile.publicURL(
        forRelativePath: String(location.path.dropFirst(prefix.count)))
    }
    return nil
  }
}
