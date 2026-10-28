import AppKit
import FileTermCore
import NetFS
import Observation

enum ConnectionError: Error, LocalizedError, Equatable {
  case notYetAvailable(protocolName: String, ticket: String)
  case mountFailed(String)
  case couldNotOpen
  case hostNotTrusted

  var errorDescription: String? {
    switch self {
    case .notYetAvailable(let name, let ticket):
      "\(name) connections are not available yet. They arrive with M08 \(ticket)."
    case .mountFailed(let message): message
    case .couldNotOpen: "No application could open the screen-sharing address."
    case .hostNotTrusted: "The server’s host key was not trusted, so no connection was made."
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

/// An SSH server FileTerm has not seen before, with the keys it presented.
struct HostKeyChallenge: Equatable {
  let target: SSHTarget
  let keys: [HostKey]

  var serverName: String {
    HostKeyStore.hostPattern(host: target.host, port: target.port)
  }

  /// One line per key: the algorithm and its SHA256 fingerprint, as `ssh-keygen -l` prints it.
  var details: String {
    keys.map { "\($0.algorithm)  \($0.fingerprint ?? "unreadable key")" }.joined(separator: "\n")
  }
}

typealias HostKeyConfirmation = @MainActor (HostKeyChallenge) async -> Bool

/// Asks whether to trust a new server. Cancel is the default button: trusting is the choice that
/// must be deliberate.
@MainActor func confirmHostKeyWithAlert(_ challenge: HostKeyChallenge) -> Bool {
  let alert = NSAlert()
  alert.alertStyle = .warning
  alert.messageText = "Trust the server “\(challenge.serverName)”?"
  alert.informativeText =
    "FileTerm has not connected to this server before. Trust it only if these fingerprints "
    + "match the ones its administrator gave you.\n\n\(challenge.details)"
  let trust = alert.addButton(withTitle: "Trust")
  let cancel = alert.addButton(withTitle: "Cancel")
  trust.keyEquivalent = ""
  cancel.keyEquivalent = "\r"
  return alert.runModal() == .alertFirstButtonReturn
}

typealias RemoteProviderFactory =
  @Sendable (ConnectionProfile, String?) throws -> any ValidatingProvider

func makeRemoteProvider(
  _ profile: ConnectionProfile, password: String?,
  knownHosts: URL = HostKeyStore.defaultFileURL
) throws -> any ValidatingProvider {
  let user = profile.username.isEmpty ? nil : profile.username
  if profile.kind.isSFTP {
    return SFTPProvider(
      id: "sftp.\(profile.id.uuidString)", target: try SSHTarget(profile: profile),
      password: password, knownHosts: knownHosts)
  }
  if profile.kind.isWebDAV {
    return WebDAVProvider(
      id: "webdav.\(profile.id.uuidString)", baseURL: try profile.webDAVBaseURL(),
      username: user, password: password)
  }
  if profile.kind.isFTP {
    let endpoint = try profile.ftpEndpoint()
    return FTPProvider(
      id: "ftp.\(profile.id.uuidString)", host: endpoint.host, port: endpoint.port,
      username: user ?? "anonymous", password: user == nil ? "anonymous@" : password,
      secure: profile.kind == .ftps, activeMode: profile.ftpActiveMode,
      allowInvalidCertificate: profile.allowInvalidCertificate)
  }
  guard profile.kind.isObjectStore else { throw ConnectionProfileError.unsupportedURL }
  guard let user, let password, !password.isEmpty else {
    throw ConnectionProfileError.missingCredentials
  }
  return S3Provider(
    id: "s3.\(profile.id.uuidString)", endpoint: try profile.objectStoreEndpoint(),
    region: profile.resolvedRegion, accessKey: user, secretKey: password)
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
  @ObservationIgnored private let hostKeys: HostKeyStore
  @ObservationIgnored private let confirmHostKey: HostKeyConfirmation

  init(
    settings: AppSettings, registry: ProviderRegistry = ProviderRegistry(),
    credentials: CredentialStore = KeychainCredentialStore(),
    mounter: VolumeMounter = NetFSMounter(),
    remoteFactory: @escaping RemoteProviderFactory = { try makeRemoteProvider($0, password: $1) },
    hostKeys: HostKeyStore = HostKeyStore(),
    confirmHostKey: @escaping HostKeyConfirmation = { confirmHostKeyWithAlert($0) },
    openExternal: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
  ) {
    self.settings = settings
    self.registry = registry
    self.remoteFactory = remoteFactory
    self.hostKeys = hostKeys
    self.confirmHostKey = confirmHostKey
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
    if profile.kind.usesProvider {
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
    let root = try await openRoot(of: provider, for: profile)
    if let previous = open.first(where: { $0.id == profile.id }) {
      registry.unregister(id: previous.root.providerID)
      open.removeAll { $0.id == profile.id }
    }
    registry.register(provider)
    open.append(
      OpenConnection(
        profile: profile, root: Location(providerID: provider.id, path: root),
        mountURL: nil))
  }

  /// Resolves the folder to open and checks it. An SSH server seen for the first time is shown to
  /// the user once; if they trust it, its keys are saved and the connection is tried again.
  private func openRoot(of provider: any ValidatingProvider, for profile: ConnectionProfile)
    async throws -> String
  {
    do {
      return try await validatedRoot(of: provider, for: profile)
    } catch let error as SFTPError {
      guard case .unknownHostKey = error else { throw error }
      let target = try SSHTarget(profile: profile)
      let keys = try await hostKeys.scan(target)
      guard await confirmHostKey(HostKeyChallenge(target: target, keys: keys)) else {
        throw ConnectionError.hostNotTrusted
      }
      try hostKeys.trust(keys, for: target)
      return try await validatedRoot(of: provider, for: profile)
    }
  }

  private func validatedRoot(of provider: any ValidatingProvider, for profile: ConnectionProfile)
    async throws -> String
  {
    let root = try await provider.resolveRoot(profile.path)
    try await provider.validate(root: root)
    return root
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

  /// The ssh command for a folder on an open SFTP connection (M06.10 extension), or nil for any
  /// other location. The folder is the SFTP path; a server that confines SFTP to a jail may use
  /// different paths in a shell.
  func sshSession(for location: Location) -> SSHSessionCommand? {
    guard
      let connection = open.first(where: {
        $0.root.providerID == location.providerID && $0.profile.kind.isSFTP
      }), let target = try? SSHTarget(profile: connection.profile)
    else { return nil }
    return SSHSessionCommand(
      executable: SSHCommand.executable.path,
      arguments: SSHCommand.terminalArguments(
        target: target, knownHosts: hostKeys.fileURL, directory: location.path))
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
