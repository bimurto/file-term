import Foundation

public enum ConnectionField: String, Codable, CaseIterable, Sendable {
  case port, region, path, localPath, baseURL, textEncoding, note, colorLabel
  case ftpMode, allowInvalidCertificate
}

public enum ConnectionAvailability: Equatable, Sendable {
  case available
  /// The protocol is listed but its provider ships in the named M08 ticket.
  case plannedIn(String)
}

public enum ConnectionKind: String, CaseIterable, Codable, Sendable {
  case sftp, ftp, ftps, webdav, webdavHTTPS, s3, b2
  case googleDrive, oneDrive, dropbox, rackspace
  case smb, afp, nfs, vnc

  public var title: String {
    switch self {
    case .sftp: "SFTP"
    case .ftp: "FTP"
    case .ftps: "FTP-TLS"
    case .webdav: "WebDAV"
    case .webdavHTTPS: "WebDAV (HTTPS)"
    case .s3: "Amazon S3"
    case .b2: "Backblaze B2"
    case .googleDrive: "Google Drive"
    case .oneDrive: "OneDrive"
    case .dropbox: "Dropbox"
    case .rackspace: "Rackspace Cloud Files"
    case .smb: "SMB"
    case .afp: "AFP (Legacy)"
    case .nfs: "NFS"
    case .vnc: "VNC"
    }
  }

  public var isLegacy: Bool { self == .afp }

  public var defaultPort: Int? {
    switch self {
    case .sftp: 22
    case .ftp, .ftps: 21
    case .webdav: 80
    case .webdavHTTPS: 443
    case .smb: 445
    case .afp: 548
    case .nfs: 2049
    case .vnc: 5900
    case .s3, .b2, .googleDrive, .oneDrive, .dropbox, .rackspace: nil
    }
  }

  /// Protocols that show Server, Username and Password in the basic section.
  public var usesCredentials: Bool {
    switch self {
    case .nfs, .vnc, .googleDrive, .oneDrive, .dropbox: false
    default: true
    }
  }

  public var usesServer: Bool {
    switch self {
    case .googleDrive, .oneDrive, .dropbox, .rackspace: false
    default: true
    }
  }

  public var serverTitle: String { isObjectStore ? "Endpoint" : "Server" }
  public var usernameTitle: String {
    switch self {
    case .s3: "Access Key ID"
    case .b2: "Application Key ID"
    default: "Username"
    }
  }
  public var passwordTitle: String {
    switch self {
    case .s3: "Secret Access Key"
    case .b2: "Application Key"
    default: "Password"
    }
  }

  /// Fields shown under Show Advanced (M08.02).
  public var advancedFields: [ConnectionField] {
    switch self {
    case .sftp:
      [.port, .path, .localPath, .baseURL, .textEncoding, .note, .colorLabel]
    case .ftp:
      [.port, .ftpMode, .path, .localPath, .baseURL, .textEncoding, .note, .colorLabel]
    case .ftps:
      [
        .port, .ftpMode, .allowInvalidCertificate, .path, .localPath, .baseURL, .textEncoding,
        .note, .colorLabel,
      ]
    case .webdav, .webdavHTTPS:
      [.port, .path, .localPath, .baseURL, .note, .colorLabel]
    case .s3, .b2: [.port, .region, .path, .localPath, .baseURL, .note, .colorLabel]
    case .rackspace, .googleDrive, .oneDrive, .dropbox:
      [.path, .localPath, .baseURL, .note, .colorLabel]
    case .smb, .afp, .nfs: [.port, .path, .note, .colorLabel]
    case .vnc: [.port, .note, .colorLabel]
    }
  }

  public var availability: ConnectionAvailability {
    switch self {
    case .smb, .afp, .nfs, .vnc, .webdav, .webdavHTTPS, .s3, .b2, .ftp, .ftps: .available
    case .sftp: .plannedIn("T6")
    case .rackspace: .plannedIn("T8")
    case .googleDrive, .oneDrive, .dropbox: .plannedIn("T9")
    }
  }

  /// Opened through the OS networking stack and browsed as a local mount.
  public var isOSMount: Bool { self == .smb || self == .afp || self == .nfs }
  public var isWebDAV: Bool { self == .webdav || self == .webdavHTTPS }
  public var isObjectStore: Bool { self == .s3 || self == .b2 }
  /// Browsed through a provider registered at runtime rather than an OS mount.
  public var isFTP: Bool { self == .ftp || self == .ftps }
  public var usesProvider: Bool { isWebDAV || isObjectStore || isFTP }

  var urlScheme: String? {
    switch self {
    case .smb: "smb"
    case .afp: "afp"
    case .nfs: "nfs"
    case .vnc: "vnc"
    default: nil
    }
  }
}

public enum ConnectionProfileError: Error, Equatable, LocalizedError, Sendable {
  case missingServer, invalidServer, unsupportedURL, missingCredentials

  public var errorDescription: String? {
    switch self {
    case .missingServer: "Enter a server name or address."
    case .invalidServer: "The server name is not valid."
    case .unsupportedURL: "This protocol cannot be opened through the system."
    case .missingCredentials: "Enter the access key ID and the secret."
    }
  }
}

/// Everything about a saved connection except its password, which lives only in the keychain.
public struct ConnectionProfile: Codable, Identifiable, Hashable, Sendable {
  public var id = UUID()
  public var kind: ConnectionKind
  public var name = ""
  public var server = ""
  public var username = ""
  public var port: Int?
  public var region = ""
  public var path = ""
  public var localPath = ""
  public var baseURL = ""
  public var textEncoding = "UTF-8"
  /// FTP only: connect back from the server (active) instead of the usual passive mode.
  public var ftpActiveMode = false
  /// FTP-TLS only: accept a self-signed or otherwise untrusted server certificate.
  public var allowInvalidCertificate = false
  public var note = ""
  public var colorLabel = ""
  public var isFavorite = false

  public init(kind: ConnectionKind) { self.kind = kind }

  private enum CodingKeys: String, CodingKey {
    case id, kind, name, server, username, port, region, path, localPath, baseURL
    case textEncoding, note, colorLabel, isFavorite, ftpActiveMode, allowInvalidCertificate
  }

  /// Fields added after the first release decode with defaults, so saved profiles keep loading.
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    kind = try values.decode(ConnectionKind.self, forKey: .kind)
    name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
    server = try values.decodeIfPresent(String.self, forKey: .server) ?? ""
    username = try values.decodeIfPresent(String.self, forKey: .username) ?? ""
    port = try values.decodeIfPresent(Int.self, forKey: .port)
    region = try values.decodeIfPresent(String.self, forKey: .region) ?? ""
    path = try values.decodeIfPresent(String.self, forKey: .path) ?? ""
    localPath = try values.decodeIfPresent(String.self, forKey: .localPath) ?? ""
    baseURL = try values.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
    textEncoding = try values.decodeIfPresent(String.self, forKey: .textEncoding) ?? "UTF-8"
    note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
    colorLabel = try values.decodeIfPresent(String.self, forKey: .colorLabel) ?? ""
    isFavorite = try values.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    ftpActiveMode = try values.decodeIfPresent(Bool.self, forKey: .ftpActiveMode) ?? false
    allowInvalidCertificate =
      try values.decodeIfPresent(Bool.self, forKey: .allowInvalidCertificate) ?? false
  }

  /// The given name, else the server with its port when it is not the protocol default, so two
  /// servers on one host stay distinguishable.
  public var displayName: String {
    if !name.isEmpty { return name }
    guard !server.isEmpty else { return kind.title }
    if let port, port != kind.defaultPort { return "\(server):\(port)" }
    return server
  }

  /// The URL handed to the OS (NetFS or the screen-sharing client). Never contains a password.
  public func url() throws -> URL {
    guard let scheme = kind.urlScheme else { throw ConnectionProfileError.unsupportedURL }
    let host = server.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else { throw ConnectionProfileError.missingServer }
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    if !username.isEmpty { components.user = username }
    if let port, port != kind.defaultPort { components.port = port }
    if !path.isEmpty { components.path = path.hasPrefix("/") ? path : "/" + path }
    guard let url = components.url else { throw ConnectionProfileError.invalidServer }
    return url
  }

  /// Scheme, host and port of a WebDAV server. The server field takes a bare host name.
  public func webDAVBaseURL() throws -> URL {
    guard kind.isWebDAV else { throw ConnectionProfileError.unsupportedURL }
    let host = server.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else { throw ConnectionProfileError.missingServer }
    guard !host.contains("/"), !host.contains(":") || host.hasPrefix("[") else {
      throw ConnectionProfileError.invalidServer
    }
    var components = URLComponents()
    components.scheme = kind == .webdavHTTPS ? "https" : "http"
    components.host = host
    if let port, port != kind.defaultPort { components.port = port }
    guard let url = components.url else { throw ConnectionProfileError.invalidServer }
    return url
  }

  /// Host and port of an FTP server. The server field takes a bare host name or address.
  public func ftpEndpoint() throws -> (host: String, port: Int?) {
    guard kind.isFTP else { throw ConnectionProfileError.unsupportedURL }
    let host = server.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty else { throw ConnectionProfileError.missingServer }
    guard !host.contains("/"), !host.contains(" "), !host.contains("://"),
      !host.contains(":") || host.hasPrefix("[")
    else { throw ConnectionProfileError.invalidServer }
    return (host, port)
  }

  /// The signing region: the Region field, else the one in a `s3.<region>.…` host, else us-east-1.
  public var resolvedRegion: String {
    let explicit = region.trimmingCharacters(in: .whitespacesAndNewlines)
    if !explicit.isEmpty { return explicit }
    let pattern = #"s3[.-]([a-z0-9-]+)\.(?:amazonaws|backblazeb2)\.com"#
    if let expression = try? NSRegularExpression(pattern: pattern),
      let match = expression.firstMatch(
        in: server, range: NSRange(server.startIndex..., in: server)),
      let range = Range(match.range(at: 1), in: server), server[range] != "dualstack"
    {
      return String(server[range])
    }
    return "us-east-1"
  }

  /// Scheme, host and port of an S3-compatible endpoint. A bare host uses https; `http://` is
  /// accepted for local servers such as MinIO. An empty S3 endpoint means Amazon's.
  public func objectStoreEndpoint() throws -> URL {
    guard kind.isObjectStore else { throw ConnectionProfileError.unsupportedURL }
    var host = server.trimmingCharacters(in: .whitespacesAndNewlines)
    var scheme = "https"
    if let separator = host.range(of: "://") {
      scheme = String(host[..<separator.lowerBound]).lowercased()
      host = String(host[separator.upperBound...])
      guard scheme == "http" || scheme == "https" else {
        throw ConnectionProfileError.invalidServer
      }
    }
    host = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    var embeddedPort: Int?
    if let colon = host.lastIndex(of: ":"), !host.hasPrefix("[") {
      embeddedPort = Int(host[host.index(after: colon)...])
      host = String(host[..<colon])
    }
    if host.isEmpty {
      guard kind == .s3 else { throw ConnectionProfileError.missingServer }
      host =
        resolvedRegion == "us-east-1" ? "s3.amazonaws.com" : "s3.\(resolvedRegion).amazonaws.com"
    }
    guard !host.contains("/"), !host.contains(" ") else {
      throw ConnectionProfileError.invalidServer
    }
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = port ?? embeddedPort
    guard let url = components.url else { throw ConnectionProfileError.invalidServer }
    return url
  }

  /// The folder a WebDAV connection opens first, as an absolute server path.
  public var rootPath: String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
  }

  /// Joins the Base URL with a path relative to the connection root (M08.02 → M05.08).
  public func publicURL(forRelativePath relative: String) -> URL? {
    let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !base.isEmpty, var components = URLComponents(string: base),
      components.scheme?.hasPrefix("http") == true, components.host != nil
    else { return nil }
    let trimmedBase =
      components.percentEncodedPath.hasSuffix("/")
      ? String(components.percentEncodedPath.dropLast()) : components.percentEncodedPath
    let encoded = relative.split(separator: "/").compactMap {
      String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }.joined(separator: "/")
    components.percentEncodedPath = trimmedBase + (encoded.isEmpty ? "/" : "/" + encoded)
    return components.url
  }
}

public enum RemotePanePlacement: String, Codable, CaseIterable, Sendable {
  case left, right, active

  public var title: String {
    switch self {
    case .left: "Left Pane"
    case .right: "Right Pane"
    case .active: "Active Pane"
    }
  }
}

public struct ConnectionPreferences: Codable, Equatable, Sendable {
  public var profiles: [ConnectionProfile] = []
  public var remotePlacement: RemotePanePlacement = .right
  public init() {}
}
