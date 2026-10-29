import FileTermCore
import Foundation
import Testing

@testable import FileTerm

private final class FakeCredentials: CredentialStore {
  var passwords: [UUID: String] = [:]
  func password(for id: UUID) -> String? { passwords[id] }
  func setPassword(_ password: String, for id: UUID) throws { passwords[id] = password }
  func deletePassword(for id: UUID) { passwords[id] = nil }
}

private final class FakeMounter: VolumeMounter, @unchecked Sendable {
  private(set) var mounts: [(url: URL, user: String?, password: String?)] = []
  func mount(_ url: URL, user: String?, password: String?) async throws -> URL {
    mounts.append((url, user, password))
    return URL(fileURLWithPath: "/Volumes/share")
  }
}

private actor FakeRemote: ValidatingProvider {
  nonisolated let id: String
  let failure: (any Error)?
  init(id: String, failure: (any Error)? = nil) {
    self.id = id
    self.failure = failure
  }
  func validate(root: String) async throws { if let failure { throw failure } }
  func list(_ location: Location) async throws -> [FileEntry] {
    [FileEntry(location: Location(providerID: id, path: "/a.txt"), name: "a.txt", kind: .file)]
  }
  func stat(_ location: Location) async throws -> FileEntry {
    FileEntry(location: location, name: "a.txt", kind: .file)
  }
  func read(_ location: Location) async throws -> any FileByteReader {
    throw FileSystemError.unsupportedOperation
  }
  func write(_ contents: any FileByteReader, to location: Location) async throws {}
  func move(_ source: Location, to destination: Location) async throws {}
  func delete(_ location: Location) async throws {}
}

/// A remote whose file-name encoding can be switched; remembers the last one it was given.
private actor SwitchableRemote: ValidatingProvider, TextEncodingSwitchable {
  nonisolated let id: String
  private(set) var encoding: String
  init(id: String, encoding: String) {
    self.id = id
    self.encoding = encoding
  }
  func setTextEncoding(_ name: String) { encoding = name }
  func validate(root: String) async throws {}
  func list(_ location: Location) async throws -> [FileEntry] { [] }
  func stat(_ location: Location) async throws -> FileEntry {
    FileEntry(location: location, name: "x", kind: .directory)
  }
  func read(_ location: Location) async throws -> any FileByteReader {
    throw FileSystemError.unsupportedOperation
  }
  func write(_ contents: any FileByteReader, to location: Location) async throws {}
  func move(_ source: Location, to destination: Location) async throws {}
  func delete(_ location: Location) async throws {}
}

/// Fails its first folder lookups with the given errors, then resolves "upload" to a home path.
private actor ScriptedSFTP: ValidatingProvider {
  nonisolated let id: String
  private var failures: [any Error]
  private(set) var lookups = 0
  init(id: String, failures: [any Error]) {
    self.id = id
    self.failures = failures
  }
  func resolveRoot(_ requested: String) async throws -> String {
    lookups += 1
    if !failures.isEmpty { throw failures.removeFirst() }
    return "/home/tester/" + requested
  }
  func validate(root: String) async throws {}
  func list(_ location: Location) async throws -> [FileEntry] { [] }
  func stat(_ location: Location) async throws -> FileEntry {
    FileEntry(location: location, name: "x", kind: .directory)
  }
  func read(_ location: Location) async throws -> any FileByteReader {
    throw FileSystemError.unsupportedOperation
  }
  func write(_ contents: any FileByteReader, to location: Location) async throws {}
  func move(_ source: Location, to destination: Location) async throws {}
  func delete(_ location: Location) async throws {}
}

@MainActor struct ConnectionCoordinatorTests {
  private func make(
    opened: @escaping (URL) -> Bool = { _ in true }
  ) throws -> (ConnectionCoordinator, AppSettings, FakeCredentials, FakeMounter, UserDefaults) {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    let settings = AppSettings(suite: suite)
    let credentials = FakeCredentials()
    let mounter = FakeMounter()
    let coordinator = ConnectionCoordinator(
      settings: settings, credentials: credentials, mounter: mounter, openExternal: opened)
    return (coordinator, settings, credentials, mounter, suite)
  }

  private func makeRemote(failure: (any Error)? = nil) throws
    -> (ConnectionCoordinator, ProviderRegistry)
  {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    let registry = ProviderRegistry()
    let coordinator = ConnectionCoordinator(
      settings: AppSettings(suite: suite), registry: registry, credentials: FakeCredentials(),
      mounter: FakeMounter(),
      remoteFactory: { profile, _ in
        FakeRemote(id: "webdav.\(profile.id.uuidString)", failure: failure)
      })
    return (coordinator, registry)
  }

  private func dav() -> ConnectionProfile {
    var profile = ConnectionProfile(kind: .webdav)
    profile.server = "dav.local"
    profile.path = "files"
    profile.baseURL = "https://dav.example.com"
    return profile
  }

  @Test func webDAVConnectRegistersProviderAndOpensRootInThePlacementPane() async throws {
    let (coordinator, registry) = try makeRemote()
    let profile = dav()
    let browser = BrowserModel(registry: registry)
    try await coordinator.connectAndReveal(profile, in: browser)
    let id = "webdav.\(profile.id.uuidString)"
    #expect(registry.provider(for: id) != nil)
    #expect(browser.layout == .vertical)
    #expect(browser.secondPane.location == Location(providerID: id, path: "/files"))
    #expect(coordinator.open.first?.mountURL == nil)
  }

  @Test func failedValidationRegistersNothing() async throws {
    let (coordinator, registry) = try makeRemote(failure: WebDAVError.notWebDAV)
    let profile = dav()
    await #expect(throws: WebDAVError.notWebDAV) { try await coordinator.connect(profile) }
    #expect(registry.provider(for: "webdav.\(profile.id.uuidString)") == nil)
    #expect(coordinator.open.isEmpty)
  }

  @Test func disconnectUnregistersAndMovesTabsHome() async throws {
    let (coordinator, registry) = try makeRemote()
    let local = FakeRemote(id: "local")
    registry.register(local)
    let browser = BrowserModel(registry: registry)
    let profile = dav()
    try await coordinator.connectAndReveal(profile, in: browser)
    let connection = try #require(coordinator.open.first)
    let home = Location(providerID: "local", path: "/home")
    try await coordinator.disconnect(connection, in: browser, home: home)
    #expect(registry.provider(for: connection.root.providerID) == nil)
    #expect(coordinator.open.isEmpty)
    #expect(browser.secondPane.location == home)
  }

  @Test func webDAVPublicURLUsesTheBaseURL() async throws {
    let (coordinator, _) = try makeRemote()
    let profile = dav()
    try await coordinator.connect(profile)
    let root = try #require(coordinator.open.first?.root)
    let file = Location(providerID: root.providerID, path: "/files/a b.txt")
    #expect(
      coordinator.publicURL(for: file)?.absoluteString
        == "https://dav.example.com/a%20b.txt")
    #expect(
      coordinator.publicURL(for: Location(providerID: root.providerID, path: "/other")) == nil)
  }

  @Test func objectStoreConnectOpensTheBucketAndRegistersItsProvider() async throws {
    let (coordinator, registry) = try makeRemote()
    var profile = ConnectionProfile(kind: .s3)
    profile.username = "AKID"
    profile.path = "photos/2026"
    let browser = BrowserModel(registry: registry)
    try await coordinator.connectAndReveal(profile, password: "secret", in: browser)
    let id = "webdav.\(profile.id.uuidString)"  // the fake factory names every provider this way
    #expect(registry.provider(for: id) != nil)
    #expect(browser.secondPane.location == Location(providerID: id, path: "/photos/2026"))
  }

  @Test func providerFactoryValidatesObjectStoreSettings() throws {
    var b2 = ConnectionProfile(kind: .b2)
    b2.username = "keyID"
    #expect(throws: ConnectionProfileError.missingServer) {
      try makeRemoteProvider(b2, password: "key")
    }
    b2.server = "s3.us-west-004.backblazeb2.com"
    #expect(throws: ConnectionProfileError.missingCredentials) {
      try makeRemoteProvider(b2, password: nil)
    }
    let provider = try makeRemoteProvider(b2, password: "key")
    #expect(provider.id == "s3.\(b2.id.uuidString)")
    var dav = ConnectionProfile(kind: .webdav)
    dav.server = "dav.local"
    #expect(try makeRemoteProvider(dav, password: nil).id == "webdav.\(dav.id.uuidString)")
    #expect(throws: ConnectionProfileError.unsupportedURL) {
      try makeRemoteProvider(ConnectionProfile(kind: .smb), password: nil)
    }
  }

  private func smb() -> ConnectionProfile {
    var profile = ConnectionProfile(kind: .smb)
    profile.server = "nas.local"
    profile.username = "ann"
    profile.baseURL = "https://files.example.com"
    return profile
  }

  @Test func savingNeverConnectsAndKeepsPasswordOutOfDefaults() throws {
    let (coordinator, settings, credentials, mounter, suite) = try make()
    let profile = smb()
    try coordinator.save(profile, password: "s3cret")
    #expect(mounter.mounts.isEmpty)
    #expect(credentials.passwords[profile.id] == "s3cret")
    #expect(settings.connections.profiles == [profile])
    let stored = suite.dictionaryRepresentation().values.compactMap { $0 as? Data }
    #expect(!stored.contains { String(decoding: $0, as: UTF8.self).contains("s3cret") })
  }

  @Test func emptyPasswordKeepsTheKeychainEntry() throws {
    let (coordinator, _, credentials, _, _) = try make()
    let profile = smb()
    try coordinator.save(profile, password: "s3cret")
    try coordinator.save(profile, password: "")
    #expect(credentials.passwords[profile.id] == "s3cret")
  }

  @Test func connectMountsOnceWithStoredPassword() async throws {
    let (coordinator, _, credentials, mounter, _) = try make()
    let profile = smb()
    credentials.passwords[profile.id] = "s3cret"
    let mount = try await coordinator.connect(profile)
    #expect(mount?.path == "/Volumes/share")
    #expect(mounter.mounts.count == 1)
    #expect(mounter.mounts.first?.password == "s3cret")
    #expect(mounter.mounts.first?.url.absoluteString == "smb://ann@nas.local")
    #expect(coordinator.open.count == 1)
  }

  @Test func vncHandsOffToTheSystemWithoutMounting() async throws {
    var opened: [URL] = []
    let (coordinator, _, _, mounter, _) = try make {
      opened.append($0)
      return true
    }
    var profile = ConnectionProfile(kind: .vnc)
    profile.server = "10.0.0.5"
    #expect(try await coordinator.connect(profile) == nil)
    #expect(opened.map(\.absoluteString) == ["vnc://10.0.0.5"])
    #expect(mounter.mounts.isEmpty)
    #expect(coordinator.open.isEmpty)
  }

  @Test func ftpBuildsAProviderFromTheProfile() throws {
    var profile = ConnectionProfile(kind: .ftps)
    profile.server = "ftp.example.com"
    profile.port = 990
    profile.username = "ann"
    profile.allowInvalidCertificate = true
    let provider = try makeRemoteProvider(profile, password: "pw")
    #expect(provider is FTPProvider)
    #expect(provider.id == "ftp.\(profile.id.uuidString)")
    profile.server = ""
    #expect(throws: ConnectionProfileError.missingServer) {
      try makeRemoteProvider(profile, password: "pw")
    }
    profile.server = "ftp://host"
    #expect(throws: ConnectionProfileError.invalidServer) {
      try makeRemoteProvider(profile, password: "pw")
    }
  }

  @Test func unimplementedProtocolsNameTheirTicket() async throws {
    let (coordinator, _, _, mounter, _) = try make()
    var profile = ConnectionProfile(kind: .rackspace)
    profile.server = "host"
    await #expect(
      throws: ConnectionError.notYetAvailable(protocolName: "Rackspace Cloud Files", ticket: "T8")
    ) {
      try await coordinator.connect(profile)
    }
    #expect(mounter.mounts.isEmpty)
  }

  @Test func placementAppliesTheSetting() throws {
    let (coordinator, settings, _, _, _) = try make()
    let browser = BrowserModel(providers: [LocalFileSystemProvider()])
    #expect(settings.connections.remotePlacement == .right)
    #expect(coordinator.placementPane(in: browser) == .second)
    #expect(browser.layout == .vertical)
    settings.connections.remotePlacement = .left
    #expect(coordinator.placementPane(in: browser) == .first)
    settings.connections.remotePlacement = .active
    browser.activePaneID = .second
    #expect(coordinator.placementPane(in: browser) == .second)
  }

  @Test func publicURLMapsLocationsUnderTheMount() async throws {
    let (coordinator, _, _, _, _) = try make()
    _ = try await coordinator.connect(smb())
    let inside = Location(providerID: "local", path: "/Volumes/share/docs/a b.txt")
    #expect(
      coordinator.publicURL(for: inside)?.absoluteString
        == "https://files.example.com/docs/a%20b.txt")
    #expect(coordinator.publicURL(for: Location(providerID: "local", path: "/tmp/x")) == nil)
    coordinator.handleUnmount(at: URL(fileURLWithPath: "/Volumes/share"))
    #expect(coordinator.publicURL(for: inside) == nil)
  }

  // MARK: SFTP host keys

  private static let keyBlob =
    "AAAAC3NzaC1lZDI1NTE5AAAAILsDCh5m+CJP4O3x9/4wGhLcOnVU20Z5j+X9TfkV86rU"

  private func sftpProfile() -> ConnectionProfile {
    var profile = ConnectionProfile(kind: .sftp)
    profile.server = "127.0.0.1"
    profile.port = 2222
    profile.username = "tester"
    profile.path = "upload"
    return profile
  }

  /// A coordinator whose provider fails with `failures` first, whose ssh-keyscan prints one key,
  /// and whose host-key prompt answers `trust` and records what it was shown.
  private func makeSFTP(
    failures: [any Error], trust: Bool,
    shown: @escaping @MainActor (HostKeyChallenge) -> Void = { _ in }
  ) throws -> (ConnectionCoordinator, ProviderRegistry, URL, ScriptedSFTP) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fileterm-keys-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let keyscan = folder.appendingPathComponent("keyscan")
    try "#!/bin/sh\necho '[127.0.0.1]:2222 ssh-ed25519 \(Self.keyBlob)'\n"
      .write(to: keyscan, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: keyscan.path)
    let knownHosts = folder.appendingPathComponent("known_hosts")
    let suite = try #require(UserDefaults(suiteName: "com.fileterm.tests.\(UUID().uuidString)"))
    let registry = ProviderRegistry()
    let provider = ScriptedSFTP(id: "sftp.test", failures: failures)
    let coordinator = ConnectionCoordinator(
      settings: AppSettings(suite: suite), registry: registry, credentials: FakeCredentials(),
      mounter: FakeMounter(), remoteFactory: { _, _ in provider },
      hostKeys: HostKeyStore(fileURL: knownHosts, keyscan: keyscan),
      confirmHostKey: { challenge in
        shown(challenge)
        return trust
      })
    return (coordinator, registry, knownHosts, provider)
  }

  @Test func newSFTPServerIsShownSavedAndRetried() async throws {
    var challenges: [HostKeyChallenge] = []
    let (coordinator, registry, knownHosts, provider) = try makeSFTP(
      failures: [SFTPError.unknownHostKey(host: "127.0.0.1", port: 2222)], trust: true,
      shown: { challenges.append($0) })
    let profile = sftpProfile()
    try await coordinator.connect(profile)

    let challenge = try #require(challenges.first)
    #expect(challenges.count == 1 && challenge.serverName == "[127.0.0.1]:2222")
    #expect(challenge.details == "ED25519  SHA256:DhJYvQCPgSQA9Y9JN8bbYNLl1pRhfc74ceXtpnZXxyo")
    #expect(
      try String(contentsOf: knownHosts, encoding: .utf8)
        == "[127.0.0.1]:2222 ssh-ed25519 \(Self.keyBlob)\n")
    #expect(await provider.lookups == 2)
    #expect(registry.provider(for: "sftp.test") != nil)
    // The folder the user typed is resolved by the server, not guessed locally.
    #expect(
      coordinator.open.first?.root
        == Location(providerID: "sftp.test", path: "/home/tester/upload"))
  }

  @Test func decliningTheHostKeyConnectsNothingAndSavesNothing() async throws {
    let (coordinator, registry, knownHosts, provider) = try makeSFTP(
      failures: [SFTPError.unknownHostKey(host: "127.0.0.1", port: 2222)], trust: false)
    await #expect(throws: ConnectionError.hostNotTrusted) {
      try await coordinator.connect(self.sftpProfile())
    }
    #expect(!FileManager.default.fileExists(atPath: knownHosts.path))
    #expect(registry.provider(for: "sftp.test") == nil && coordinator.open.isEmpty)
    #expect(await provider.lookups == 1)
  }

  @Test func otherSFTPFailuresSkipThePrompt() async throws {
    for failure in [SFTPError.loginDenied, .hostKeyChanged(host: "127.0.0.1")] {
      var asked = false
      let (coordinator, _, knownHosts, _) = try makeSFTP(
        failures: [failure], trust: true, shown: { _ in asked = true })
      await #expect(throws: failure) { try await coordinator.connect(self.sftpProfile()) }
      #expect(!asked && !FileManager.default.fileExists(atPath: knownHosts.path))
    }
  }

  @Test func sshSessionIsOfferedOnlyForOpenSFTPLocations() async throws {
    let (coordinator, _, knownHosts, _) = try makeSFTP(failures: [], trust: true)
    #expect(
      coordinator.sshSession(for: Location(providerID: "sftp.test", path: "/home/tester")) == nil)
    try await coordinator.connect(sftpProfile())

    let folder = Location(providerID: "sftp.test", path: "/home/tester/up load")
    let command = try #require(coordinator.sshSession(for: folder))
    #expect(command.executable == "/usr/bin/ssh")
    #expect(command.arguments.contains("StrictHostKeyChecking=yes"))
    #expect(
      command.arguments.contains("UserKnownHostsFile=\"\(knownHosts.path)\" ~/.ssh/known_hosts"))
    #expect(command.arguments.last == "cd '/home/tester/up load' && exec \"$SHELL\" -l")
    #expect(!command.arguments.contains { $0.contains("pw") })
    #expect(coordinator.sshSession(for: Location(providerID: "local", path: "/tmp")) == nil)
  }

  @Test func switchingTheTextEncodingRereadsTheOpenTabs() async throws {
    let suite = try #require(UserDefaults(suiteName: "com.fileterm.tests.\(UUID().uuidString)"))
    let registry = ProviderRegistry()
    let remote = SwitchableRemote(id: "ftp.test", encoding: "ISO-8859-1")
    let coordinator = ConnectionCoordinator(
      settings: AppSettings(suite: suite), registry: registry, credentials: FakeCredentials(),
      mounter: FakeMounter(), remoteFactory: { _, _ in remote })
    var profile = ConnectionProfile(kind: .ftp)
    profile.server = "ftp.local"
    profile.textEncoding = "ISO-8859-1"
    let browser = BrowserModel(registry: registry)
    try await coordinator.connectAndReveal(profile, in: browser)
    let root = Location(providerID: "ftp.test", path: "/")
    #expect(coordinator.textEncoding(for: root) == "ISO-8859-1")

    // The server holds UTF-8 "café" (C3 A9); read as ISO-8859-1 the folder showed as "cafÃ©".
    await browser.navigate(to: Location(providerID: "ftp.test", path: "/cafÃ©"), in: .second)
    await coordinator.setTextEncoding("UTF-8", for: root, in: browser)
    #expect(await remote.encoding == "UTF-8")
    #expect(coordinator.textEncoding(for: root) == "UTF-8")
    #expect(coordinator.profiles.isEmpty)  // the switch is not saved
    #expect(browser.secondPane.location == Location(providerID: "ftp.test", path: "/café"))

    // A path the old reading lost (U+FFFD) cannot be rebuilt: the tab goes to the root.
    await browser.navigate(to: Location(providerID: "ftp.test", path: "/caf\u{FFFD}"), in: .second)
    await coordinator.setTextEncoding("ISO-8859-1", for: root, in: browser)
    #expect(browser.secondPane.location == root)
  }

  @Test func textEncodingIsOnlyOfferedForFTPAndSFTPConnections() async throws {
    let (coordinator, registry) = try makeRemote()
    let browser = BrowserModel(registry: registry)
    let profile = dav()
    try await coordinator.connectAndReveal(profile, in: browser)
    let location = Location(providerID: "webdav.\(profile.id.uuidString)", path: "/files")
    #expect(coordinator.textEncoding(for: location) == nil)
    #expect(coordinator.textEncoding(for: Location(providerID: "local", path: "/")) == nil)
  }

  @Test func sftpProviderIsBuiltFromTheProfile() throws {
    let profile = sftpProfile()
    let provider = try makeRemoteProvider(profile, password: "pw")
    #expect(provider is SFTPProvider && provider.id == "sftp.\(profile.id.uuidString)")
    var bad = profile
    bad.server = "-oProxyCommand=x"
    #expect(throws: ConnectionProfileError.invalidServer) {
      try makeRemoteProvider(bad, password: nil)
    }
  }
}
