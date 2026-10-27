import Foundation
import Testing

@testable import FileTermCore

@Suite struct ConnectionProfileTests {
  @Test func buildsOSURLsWithoutPasswords() throws {
    var smb = ConnectionProfile(kind: .smb)
    smb.server = "nas.local"
    smb.username = "ann"
    smb.path = "media"
    #expect(try smb.url().absoluteString == "smb://ann@nas.local/media")
    smb.port = 4455
    #expect(try smb.url().absoluteString == "smb://ann@nas.local:4455/media")
    var vnc = ConnectionProfile(kind: .vnc)
    vnc.server = "10.0.0.5"
    #expect(try vnc.url().absoluteString == "vnc://10.0.0.5")
  }

  @Test func rejectsMissingServerAndUnsupportedKinds() {
    #expect(throws: ConnectionProfileError.missingServer) {
      try ConnectionProfile(kind: .nfs).url()
    }
    #expect(throws: ConnectionProfileError.unsupportedURL) {
      try ConnectionProfile(kind: .sftp).url()
    }
  }

  @Test func protocolsDefineDefaultsAndFields() {
    #expect(ConnectionKind.sftp.defaultPort == 22)
    #expect(ConnectionKind.afp.isLegacy)
    #expect(!ConnectionKind.vnc.usesCredentials)
    #expect(!ConnectionKind.nfs.usesCredentials)
    #expect(ConnectionKind.ftp.advancedFields.contains(.textEncoding))
    #expect(!ConnectionKind.smb.advancedFields.contains(.textEncoding))
    #expect(ConnectionKind.smb.availability == .available)
    #expect(ConnectionKind.sftp.availability == .plannedIn("T6"))
    #expect(ConnectionKind.webdav.availability == .available)
  }

  @Test func joinsBaseURLWithEncodedRelativePath() {
    var profile = ConnectionProfile(kind: .smb)
    profile.baseURL = "https://files.example.com/share/"
    #expect(
      profile.publicURL(forRelativePath: "/a b/café.txt")?.absoluteString
        == "https://files.example.com/share/a%20b/caf%C3%A9.txt")
    profile.baseURL = ""
    #expect(profile.publicURL(forRelativePath: "x") == nil)
    profile.baseURL = "ftp://example.com"
    #expect(profile.publicURL(forRelativePath: "x") == nil)
  }

  @Test func encodedProfilesCarryNoPassword() throws {
    var profile = ConnectionProfile(kind: .smb)
    profile.server = "nas"
    var preferences = ConnectionPreferences()
    preferences.profiles = [profile]
    let json = try String(decoding: JSONEncoder().encode(preferences), as: UTF8.self)
    #expect(!json.localizedCaseInsensitiveContains("password"))
    let decoded = try JSONDecoder().decode(ConnectionPreferences.self, from: Data(json.utf8))
    #expect(decoded == preferences)
    #expect(decoded.remotePlacement == .right)
  }

  @Test func buildsWebDAVBaseURLs() throws {
    var profile = ConnectionProfile(kind: .webdav)
    profile.server = "dav.example.com"
    #expect(try profile.webDAVBaseURL().absoluteString == "http://dav.example.com")
    profile.port = 8080
    #expect(try profile.webDAVBaseURL().absoluteString == "http://dav.example.com:8080")
    profile.kind = .webdavHTTPS
    profile.port = nil
    #expect(try profile.webDAVBaseURL().absoluteString == "https://dav.example.com")
    #expect(profile.rootPath == "/")
    profile.path = "files/docs"
    #expect(profile.rootPath == "/files/docs")
    profile.server = "https://dav.example.com"
    #expect(throws: ConnectionProfileError.invalidServer) { try profile.webDAVBaseURL() }
    profile.server = ""
    #expect(throws: ConnectionProfileError.missingServer) { try profile.webDAVBaseURL() }
    #expect(throws: ConnectionProfileError.unsupportedURL) {
      try ConnectionProfile(kind: .smb).webDAVBaseURL()
    }
  }

  @Test func displayNameSeparatesServersOnTheSameHost() {
    var profile = ConnectionProfile(kind: .webdav)
    #expect(profile.displayName == "WebDAV")
    profile.server = "127.0.0.1"
    #expect(profile.displayName == "127.0.0.1")
    profile.port = 8081
    #expect(profile.displayName == "127.0.0.1:8081")
    profile.port = 80
    #expect(profile.displayName == "127.0.0.1")
    profile.name = "Backup"
    #expect(profile.displayName == "Backup")
  }
}
