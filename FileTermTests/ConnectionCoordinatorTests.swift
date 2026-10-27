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
    var profile = ConnectionProfile(kind: .sftp)
    profile.server = "host"
    await #expect(throws: ConnectionError.notYetAvailable(protocolName: "SFTP", ticket: "T6")) {
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
}
