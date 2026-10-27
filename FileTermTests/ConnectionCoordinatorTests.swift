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
