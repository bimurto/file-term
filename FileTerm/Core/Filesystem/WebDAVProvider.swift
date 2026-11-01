import Foundation

public enum WebDAVError: Error, Equatable, LocalizedError, Sendable {
  case notWebDAV

  public var errorDescription: String? {
    "This address is not a WebDAV server. A normal website address cannot be browsed as WebDAV."
  }
}

/// Browses a WebDAV server. `Location.path` is the absolute, percent-decoded server path.
public actor WebDAVProvider: ValidatingProvider {
  public nonisolated let id: String
  private let baseURL: URL
  private let session: URLSession
  private let authentication: WebDAVAuthenticator

  public init(
    id: String, baseURL: URL, username: String?, password: String?,
    configuration: URLSessionConfiguration = .ephemeral
  ) {
    self.init(
      id: id, baseURL: baseURL, username: username, password: password,
      configuration: configuration, trustedCertificate: nil)
  }

  /// `trustedCertificate`, DER data, is for test servers: it replaces the system's trusted roots.
  init(
    id: String, baseURL: URL, username: String?, password: String?,
    configuration: URLSessionConfiguration = .ephemeral, trustedCertificate: Data?
  ) {
    self.id = id
    self.baseURL = baseURL
    authentication = WebDAVAuthenticator(
      username: username, password: password, trustedCertificate: trustedCertificate)
    session = URLSession(configuration: configuration, delegate: authentication, delegateQueue: nil)
  }

  /// The M08.05 check: only a server that speaks WebDAV may be registered.
  public func validate(root: String = "/") async throws {
    var options = request(root, method: "OPTIONS")
    options.timeoutInterval = 20
    let (_, optionsResponse) = try await send(options)
    try Self.check(optionsResponse.statusCode)
    guard optionsResponse.value(forHTTPHeaderField: "DAV") != nil else {
      throw WebDAVError.notWebDAV
    }
    var probe = request(root, method: "PROPFIND")
    probe.setValue("0", forHTTPHeaderField: "Depth")
    let (data, response) = try await send(probe)
    try Self.check(response.statusCode, allowing: [207])
    guard response.statusCode == 207, !(try WebDAVMultistatus.parse(data)).isEmpty else {
      throw WebDAVError.notWebDAV
    }
  }

  public func list(_ location: Location) async throws -> [FileEntry] {
    try await list(location, includeHidden: false)
  }

  public func list(_ location: Location, includeHidden: Bool) async throws -> [FileEntry] {
    var propfind = request(location.path, method: "PROPFIND")
    propfind.setValue("1", forHTTPHeaderField: "Depth")
    let (data, response) = try await send(propfind)
    try Self.check(response.statusCode, allowing: [207])
    let own = Self.trimmed(location.path)
    return try WebDAVMultistatus.parse(data).compactMap { item -> FileEntry? in
      guard Self.trimmed(item.path) != own else { return nil }
      let entry = entry(for: item)
      guard FileName.isListable(entry.name) else { return nil }
      return includeHidden || !entry.isHidden ? entry : nil
    }
  }

  public func stat(_ location: Location) async throws -> FileEntry {
    var propfind = request(location.path, method: "PROPFIND")
    propfind.setValue("0", forHTTPHeaderField: "Depth")
    let (data, response) = try await send(propfind)
    try Self.check(response.statusCode, allowing: [207])
    guard let item = try WebDAVMultistatus.parse(data).first else { throw FileSystemError.notFound }
    return entry(for: item)
  }

  public func read(_ location: Location) async throws -> any FileByteReader {
    let (bytes, response) = try await session.bytes(for: request(location.path, method: "GET"))
    guard let http = response as? HTTPURLResponse else {
      throw FileSystemError.unsupportedOperation
    }
    try Self.check(http.statusCode)
    return HTTPByteReader(bytes: bytes.makeAsyncIterator())
  }

  public func write(_ contents: any FileByteReader, to location: Location) async throws {
    let spool = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    FileManager.default.createFile(atPath: spool.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: spool) }
    let handle = try FileHandle(forWritingTo: spool)
    do {
      while let chunk = try await contents.next() {
        try Task.checkCancellation()
        try handle.write(contentsOf: chunk)
      }
      try handle.close()
    } catch {
      try? handle.close()
      throw error
    }
    var put = request(location.path, method: "PUT")
    put.setValue("*", forHTTPHeaderField: "If-None-Match")
    let (_, response) = try await upload(put, from: spool)
    try Self.check(response.statusCode)
  }

  public func move(_ source: Location, to destination: Location) async throws {
    var move = request(source.path, method: "MOVE")
    move.setValue(url(destination.path).absoluteString, forHTTPHeaderField: "Destination")
    move.setValue("F", forHTTPHeaderField: "Overwrite")
    let (_, response) = try await send(move)
    try Self.check(response.statusCode)
  }

  public func createDirectory(_ location: Location) async throws {
    let (_, response) = try await send(request(location.path, method: "MKCOL"))
    // MKCOL answers 405 when the collection already exists.
    if response.statusCode == 405 { throw FileSystemError.destinationExists }
    try Self.check(response.statusCode)
  }

  public func delete(_ location: Location) async throws {
    let (_, response) = try await send(request(location.path, method: "DELETE"))
    try Self.check(response.statusCode)
  }

  // MARK: Requests

  private func url(_ path: String) -> URL {
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
    components.path = path.hasPrefix("/") ? path : "/" + path
    return components.url ?? baseURL
  }

  private func request(_ path: String, method: String) -> URLRequest {
    var request = URLRequest(url: url(path))
    request.httpMethod = method
    return request
  }

  private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    var request = request
    if request.httpMethod == "PROPFIND" {
      request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
      request.httpBody = Data(WebDAVMultistatus.requestBody.utf8)
    }
    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        throw FileSystemError.unsupportedOperation
      }
      return (data, http)
    } catch let error as URLError where Self.isCertificateError(error) {
      throw FileSystemError.io(
        "The server's certificate is not trusted, so the connection was not made.")
    }
  }

  private func upload(_ request: URLRequest, from file: URL) async throws -> (Data, HTTPURLResponse)
  {
    let (data, response) = try await session.upload(for: request, fromFile: file)
    guard let http = response as? HTTPURLResponse else {
      throw FileSystemError.unsupportedOperation
    }
    return (data, http)
  }

  static func check(_ status: Int, allowing extra: Set<Int> = []) throws {
    if (200..<300).contains(status) || extra.contains(status) { return }
    switch status {
    case 401: throw URLError(.userAuthenticationRequired)
    case 403: throw FileSystemError.permissionDenied
    case 404: throw FileSystemError.notFound
    case 405, 501: throw FileSystemError.unsupportedOperation
    case 409: throw FileSystemError.io("The parent folder does not exist on the server.")
    case 412: throw FileSystemError.destinationExists
    default: throw FileSystemError.io("The server returned error \(status).")
    }
  }

  static func isCertificateError(_ error: URLError) -> Bool {
    [
      .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
      .serverCertificateNotYetValid, .secureConnectionFailed,
    ].contains(error.code)
  }

  private static func trimmed(_ path: String) -> String {
    path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }

  private func entry(for item: WebDAVMultistatus.Item) -> FileEntry {
    let path = Self.trimmed(item.path)
    let name = path == "/" ? "/" : (path as NSString).lastPathComponent
    return FileEntry(
      location: Location(providerID: id, path: path), name: name,
      kind: item.isCollection ? .directory : .file,
      size: item.isCollection ? nil : item.size, createdAt: item.created,
      modifiedAt: item.modified, typeIdentifier: nil, isHidden: name.hasPrefix("."))
  }
}

private final class WebDAVAuthenticator: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  private let credential: URLCredential?
  private let trustedCertificate: Data?

  init(username: String?, password: String?, trustedCertificate: Data?) {
    credential = username.flatMap { name in
      name.isEmpty ? nil : URLCredential(user: name, password: password ?? "", persistence: .none)
    }
    self.trustedCertificate = trustedCertificate
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    let method = challenge.protectionSpace.authenticationMethod
    if method == NSURLAuthenticationMethodServerTrust, let trustedCertificate,
      let trust = challenge.protectionSpace.serverTrust
    {
      guard
        let certificate = SecCertificateCreateWithData(nil, trustedCertificate as CFData),
        SecTrustSetAnchorCertificates(trust, [certificate] as CFArray) == errSecSuccess,
        SecTrustEvaluateWithError(trust, nil)
      else {
        completionHandler(.cancelAuthenticationChallenge, nil)
        return
      }
      completionHandler(.useCredential, URLCredential(trust: trust))
      return
    }
    guard
      method == NSURLAuthenticationMethodHTTPBasic
        || method == NSURLAuthenticationMethodHTTPDigest,
      challenge.previousFailureCount == 0, let credential
    else {
      completionHandler(.performDefaultHandling, nil)
      return
    }
    completionHandler(.useCredential, credential)
  }
}

/// Single-consumer reader: callers pull chunks one at a time, as the transfer engine does.
final class HTTPByteReader: FileByteReader, @unchecked Sendable {
  private var bytes: URLSession.AsyncBytes.AsyncIterator
  private var finished = false

  init(bytes: URLSession.AsyncBytes.AsyncIterator) { self.bytes = bytes }

  func next() async throws -> Data? {
    guard !finished else { return nil }
    var chunk = Data()
    while chunk.count < 64 * 1024 {
      try Task.checkCancellation()
      guard let byte = try await bytes.next() else {
        finished = true
        break
      }
      chunk.append(byte)
    }
    return chunk.isEmpty ? nil : chunk
  }
}

/// Parses a WebDAV 207 multistatus body, matching on local element names so any namespace
/// prefix (or none) works.
enum WebDAVMultistatus {
  struct Item {
    var path = ""
    var isCollection = false
    var size: Int64?
    var created: Date?
    var modified: Date?
  }

  static let requestBody = """
    <?xml version="1.0" encoding="utf-8"?>
    <propfind xmlns="DAV:"><prop><resourcetype/><getcontentlength/><getlastmodified/>\
    <creationdate/></prop></propfind>
    """

  static func parse(_ data: Data) throws -> [Item] {
    let parser = XMLParser(data: data)
    let delegate = Delegate()
    parser.delegate = delegate
    parser.shouldProcessNamespaces = true
    guard parser.parse(), delegate.sawMultistatus else { throw WebDAVError.notWebDAV }
    return delegate.items
  }

  private final class Delegate: NSObject, XMLParserDelegate {
    var items: [Item] = []
    var sawMultistatus = false
    private var current: Item?
    private var text = ""
    private var inResourceType = false

    func parser(
      _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
      qualifiedName: String?, attributes: [String: String] = [:]
    ) {
      text = ""
      switch name {
      case "multistatus": sawMultistatus = true
      case "response": current = Item()
      case "resourcetype": inResourceType = true
      case "collection" where inResourceType: current?.isCollection = true
      default: break
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(
      _ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
      qualifiedName: String?
    ) {
      let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
      switch name {
      case "href" where current != nil && current?.path.isEmpty == true:
        let path = URL(string: value)?.path ?? value
        current?.path = path.removingPercentEncoding ?? path
      case "getcontentlength": current?.size = Int64(value)
      case "getlastmodified": current?.modified = Self.httpDate(value)
      case "creationdate": current?.created = ISO8601DateFormatter().date(from: value)
      case "resourcetype": inResourceType = false
      case "response":
        if let item = current, !item.path.isEmpty { items.append(item) }
        current = nil
      default: break
      }
    }

    private static func httpDate(_ value: String) -> Date? {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(identifier: "GMT")
      formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
      return formatter.date(from: value)
    }
  }
}
