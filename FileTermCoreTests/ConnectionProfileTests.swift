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
    #expect(ConnectionKind.sftp.availability == .available && ConnectionKind.sftp.usesProvider)
    #expect(ConnectionKind.sftp.advancedFields.contains(.privateKey))
    #expect(ConnectionKind.rackspace.availability == .plannedIn("T8"))
    #expect(ConnectionKind.ftp.availability == .available && ConnectionKind.ftps.usesProvider)
    #expect(ConnectionKind.webdav.availability == .available)
  }

  @Test func sshEndpointRejectsOptionLookalikesAndPaths() throws {
    var profile = ConnectionProfile(kind: .sftp)
    profile.server = " example.com "
    profile.port = 2222
    let endpoint = try profile.sshEndpoint()
    #expect(endpoint.host == "example.com" && endpoint.port == 2222)
    for bad in ["-oProxyCommand=x", "host/path", "a b", "ssh://host", ""] {
      profile.server = bad
      #expect(throws: ConnectionProfileError.self) { try profile.sshEndpoint() }
    }
  }

  @Test func profilesSavedBeforeTheKeyFieldStillDecode() throws {
    var profile = ConnectionProfile(kind: .sftp)
    profile.privateKeyPath = "/Users/me/.ssh/id_ed25519"
    let data = try JSONEncoder().encode(profile)
    var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(try JSONDecoder().decode(ConnectionProfile.self, from: data) == profile)
    object["privateKeyPath"] = nil
    let old = try JSONSerialization.data(withJSONObject: object)
    #expect(try JSONDecoder().decode(ConnectionProfile.self, from: old).privateKeyPath == "")
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

  @Test func resolvesObjectStoreEndpointsAndRegions() throws {
    var s3 = ConnectionProfile(kind: .s3)
    #expect(try s3.objectStoreEndpoint().absoluteString == "https://s3.amazonaws.com")
    s3.region = "eu-west-1"
    #expect(try s3.objectStoreEndpoint().absoluteString == "https://s3.eu-west-1.amazonaws.com")
    #expect(s3.resolvedRegion == "eu-west-1")
    s3.region = ""
    s3.server = "http://127.0.0.1"
    s3.port = 9000
    #expect(try s3.objectStoreEndpoint().absoluteString == "http://127.0.0.1:9000")
    #expect(s3.resolvedRegion == "us-east-1")
    s3.port = nil
    s3.server = "localhost:9000"
    #expect(try s3.objectStoreEndpoint().absoluteString == "https://localhost:9000")
    s3.server = "ftp://host"
    #expect(throws: ConnectionProfileError.invalidServer) { try s3.objectStoreEndpoint() }

    var b2 = ConnectionProfile(kind: .b2)
    #expect(throws: ConnectionProfileError.missingServer) { try b2.objectStoreEndpoint() }
    b2.server = "s3.us-west-004.backblazeb2.com"
    #expect(b2.resolvedRegion == "us-west-004")
    #expect(try b2.objectStoreEndpoint().host == "s3.us-west-004.backblazeb2.com")
    b2.server = "s3-us-west-2.amazonaws.com"
    #expect(b2.resolvedRegion == "us-west-2")
    #expect(throws: ConnectionProfileError.unsupportedURL) {
      try ConnectionProfile(kind: .smb).objectStoreEndpoint()
    }
  }

  @Test func objectStoresShowKeyLabelsAndRegion() {
    #expect(ConnectionKind.s3.usernameTitle == "Access Key ID")
    #expect(ConnectionKind.b2.passwordTitle == "Application Key")
    #expect(
      ConnectionKind.s3.serverTitle == "Endpoint" && ConnectionKind.smb.serverTitle == "Server")
    #expect(ConnectionKind.s3.advancedFields.contains(.region))
    #expect(ConnectionKind.s3.availability == .available && ConnectionKind.b2.usesProvider)
  }

  @Test func profilesSavedBeforeRegionExistedStillDecode() throws {
    let id = UUID()
    let json = """
      {"id":"\(id.uuidString)","kind":"webdav","name":"Old","server":"dav.local",
       "username":"ann","path":"files","localPath":"","baseURL":"","textEncoding":"UTF-8",
       "note":"","colorLabel":"","isFavorite":true}
      """
    let profile = try JSONDecoder().decode(ConnectionProfile.self, from: Data(json.utf8))
    #expect(profile.id == id && profile.region == "" && profile.isFavorite)
    #expect(profile.name == "Old" && profile.server == "dav.local")
  }

  @Test func ftpOptionsAndOldProfiles() throws {
    #expect(ConnectionKind.ftp.advancedFields.contains(.ftpMode))
    #expect(!ConnectionKind.ftp.advancedFields.contains(.allowInvalidCertificate))
    #expect(ConnectionKind.ftps.advancedFields.contains(.allowInvalidCertificate))
    var profile = ConnectionProfile(kind: .ftp)
    #expect(throws: ConnectionProfileError.missingServer) { try profile.ftpEndpoint() }
    profile.server = "ftp.example.com"
    profile.port = 2121
    #expect(try profile.ftpEndpoint().host == "ftp.example.com")
    #expect(try profile.ftpEndpoint().port == 2121)
    profile.server = "ftp.example.com:21"
    #expect(throws: ConnectionProfileError.invalidServer) { try profile.ftpEndpoint() }
    #expect(profile.rootPath == "/")
    let json = """
      {"id":"\(UUID().uuidString)","kind":"ftp","name":"Old","server":"h","username":"u"}
      """
    let old = try JSONDecoder().decode(ConnectionProfile.self, from: Data(json.utf8))
    #expect(!old.ftpActiveMode && !old.allowInvalidCertificate)
    profile.ftpActiveMode = true
    let round = try JSONDecoder().decode(
      ConnectionProfile.self, from: JSONEncoder().encode(profile))
    #expect(round.ftpActiveMode)
  }
}
