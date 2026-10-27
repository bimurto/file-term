import Foundation

public enum ConnectionField: String, Codable, CaseIterable, Sendable {
  case port, path, localPath, baseURL, textEncoding, note, colorLabel
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
    case .s3, .b2, .googleDrive, .oneDrive, .dropbox, .rackspace: false
    default: true
    }
  }

  /// Fields shown under Show Advanced (M08.02).
  public var advancedFields: [ConnectionField] {
    switch self {
    case .sftp, .ftp, .ftps:
      [.port, .path, .localPath, .baseURL, .textEncoding, .note, .colorLabel]
    case .webdav, .webdavHTTPS:
      [.port, .path, .localPath, .baseURL, .note, .colorLabel]
    case .s3, .b2, .rackspace, .googleDrive, .oneDrive, .dropbox:
      [.path, .localPath, .baseURL, .note, .colorLabel]
    case .smb, .afp, .nfs: [.port, .path, .note, .colorLabel]
    case .vnc: [.port, .note, .colorLabel]
    }
  }

  public var availability: ConnectionAvailability {
    switch self {
    case .smb, .afp, .nfs, .vnc: .available
    case .webdav, .webdavHTTPS: .plannedIn("T2")
    case .s3, .b2: .plannedIn("T4")
    case .ftp, .ftps: .plannedIn("T5")
    case .sftp: .plannedIn("T6")
    case .rackspace: .plannedIn("T8")
    case .googleDrive, .oneDrive, .dropbox: .plannedIn("T9")
    }
  }

  /// Opened through the OS networking stack and browsed as a local mount.
  public var isOSMount: Bool { self == .smb || self == .afp || self == .nfs }

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
  case missingServer, invalidServer, unsupportedURL

  public var errorDescription: String? {
    switch self {
    case .missingServer: "Enter a server name or address."
    case .invalidServer: "The server name is not valid."
    case .unsupportedURL: "This protocol cannot be opened through the system."
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
  public var path = ""
  public var localPath = ""
  public var baseURL = ""
  public var textEncoding = "UTF-8"
  public var note = ""
  public var colorLabel = ""
  public var isFavorite = false

  public init(kind: ConnectionKind) { self.kind = kind }

  public var displayName: String {
    name.isEmpty ? (server.isEmpty ? kind.title : server) : name
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
