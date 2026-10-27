import CryptoKit
import Foundation

public enum S3Error: Error, Equatable, LocalizedError, Sendable {
  case accessDenied(bucket: String?)
  case cannotListBuckets
  case tooLarge
  case service(code: String, message: String)

  public var errorDescription: String? {
    switch self {
    case .accessDenied(let bucket):
      if let bucket {
        "Access denied to bucket “\(bucket)”. Check the key’s permissions."
      } else {
        "Access denied. Check the key’s permissions."
      }
    case .cannotListBuckets:
      "These credentials cannot list buckets. Enter the bucket name in Path."
    case .tooLarge: "Files over 5 GB cannot be uploaded or copied within S3 yet."
    case .service(let code, let message): "S3 error \(code): \(message)"
    }
  }
}

/// Browses Amazon S3 and S3-compatible stores (Backblaze B2, MinIO). `Location.path` is
/// `/bucket/key`; `/` lists the buckets. Folders are key prefixes.
public actor S3Provider: ValidatingProvider {
  public nonisolated let id: String
  private let endpoint: URL
  private let accessKey: String
  private let secretKey: String
  private let defaultRegion: String
  private let session: URLSession
  private var bucketRegions: [String: String] = [:]
  private let singleRequestLimit: Int64

  public init(
    id: String, endpoint: URL, region: String, accessKey: String, secretKey: String,
    configuration: URLSessionConfiguration = .ephemeral,
    singleRequestLimit: Int64 = 5 * 1024 * 1024 * 1024
  ) {
    self.singleRequestLimit = singleRequestLimit
    self.id = id
    self.endpoint = endpoint
    self.accessKey = accessKey
    self.secretKey = secretKey
    defaultRegion = region
    session = URLSession(configuration: configuration)
  }

  // MARK: FileSystemProvider

  public func validate(root: String = "/") async throws {
    let (bucket, key) = Self.split(root)
    guard let bucket else {
      do { _ = try await listBuckets() } catch S3Error.accessDenied {
        throw S3Error.cannotListBuckets
      }
      return
    }
    _ = try await listPage(bucket: bucket, prefix: key, delimiter: true, token: nil, limit: 1)
  }

  public func list(_ location: Location) async throws -> [FileEntry] {
    try await list(location, includeHidden: false)
  }

  public func list(_ location: Location, includeHidden: Bool) async throws -> [FileEntry] {
    let (bucket, key) = Self.split(location.path)
    guard let bucket else {
      return try await listBuckets().filter { includeHidden || !$0.isHidden }
    }
    let prefix = Self.folderPrefix(key)
    var entries: [FileEntry] = []
    var token: String?
    repeat {
      let page = try await listPage(
        bucket: bucket, prefix: prefix, delimiter: true, token: token, limit: 1000)
      for folder in page.prefixes {
        let name = String(folder.dropFirst(prefix.count).dropLast())
        entries.append(
          FileEntry(
            location: Location(providerID: id, path: "/\(bucket)/\(folder.dropLast())"),
            name: name, kind: .directory, isHidden: name.hasPrefix(".")))
      }
      for object in page.objects where object.key != prefix && !object.key.hasSuffix("/") {
        let name = String(object.key.dropFirst(prefix.count))
        entries.append(
          FileEntry(
            location: Location(providerID: id, path: "/\(bucket)/\(object.key)"), name: name,
            kind: .file, size: object.size, modifiedAt: object.modified,
            isHidden: name.hasPrefix(".")))
      }
      token = page.nextToken
    } while token != nil
    return includeHidden ? entries : entries.filter { !$0.isHidden }
  }

  public func stat(_ location: Location) async throws -> FileEntry {
    let (bucket, key) = Self.split(location.path)
    guard let bucket else {
      return FileEntry(location: location, name: "/", kind: .directory)
    }
    if key.isEmpty {
      let (_, response) = try await perform(
        request("HEAD", bucket: bucket), bucket: bucket)
      try check(response, data: Data(), bucket: bucket)
      return FileEntry(location: location, name: bucket, kind: .directory)
    }
    let name = (key as NSString).lastPathComponent
    let (_, response) = try await perform(request("HEAD", bucket: bucket, key: key), bucket: bucket)
    if response.statusCode == 404 {
      let page = try await listPage(
        bucket: bucket, prefix: Self.folderPrefix(key), delimiter: true, token: nil, limit: 1)
      guard !page.objects.isEmpty || !page.prefixes.isEmpty else { throw FileSystemError.notFound }
      return FileEntry(location: location, name: name, kind: .directory)
    }
    try check(response, data: Data(), bucket: bucket)
    return FileEntry(
      location: location, name: name, kind: .file,
      size: response.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init),
      modifiedAt: response.value(forHTTPHeaderField: "Last-Modified").flatMap(Self.httpDate))
  }

  public func read(_ location: Location) async throws -> any FileByteReader {
    let (bucket, key) = Self.split(location.path)
    guard let bucket, !key.isEmpty else { throw FileSystemError.unsupportedOperation }
    let signed = signed(request("GET", bucket: bucket, key: key), bucket: bucket)
    let (bytes, response) = try await session.bytes(for: signed)
    guard let http = response as? HTTPURLResponse else {
      throw FileSystemError.unsupportedOperation
    }
    if !(200..<300).contains(http.statusCode) {
      var body = Data()
      for try await byte in bytes {
        body.append(byte)
        if body.count > 16_384 { break }
      }
      try check(http, data: body, bucket: bucket)
    }
    return HTTPByteReader(bytes: bytes.makeAsyncIterator())
  }

  public func write(_ contents: any FileByteReader, to location: Location) async throws {
    let (bucket, key) = Self.split(location.path)
    guard let bucket, !key.isEmpty else { throw FileSystemError.unsupportedOperation }
    let spool = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    FileManager.default.createFile(atPath: spool.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: spool) }
    let handle = try FileHandle(forWritingTo: spool)
    var hash = SHA256()
    var size: Int64 = 0
    do {
      while let chunk = try await contents.next() {
        try Task.checkCancellation()
        size += Int64(chunk.count)
        guard size <= singleRequestLimit else { throw S3Error.tooLarge }
        hash.update(data: chunk)
        try handle.write(contentsOf: chunk)
      }
      try handle.close()
    } catch {
      try? handle.close()
      throw error
    }
    let payload = S3Signer.hex(hash.finalize())
    var put = request("PUT", bucket: bucket, key: key)
    put.setValue("*", forHTTPHeaderField: "If-None-Match")
    var (data, response) = try await perform(
      put, bucket: bucket, payloadHash: payload, upload: spool)
    if response.statusCode == 501 {
      // The store ignores conditional writes; check for an existing object ourselves.
      if try await objectExists(bucket: bucket, key: key) {
        throw FileSystemError.destinationExists
      }
      put.setValue(nil, forHTTPHeaderField: "If-None-Match")
      (data, response) = try await perform(put, bucket: bucket, payloadHash: payload, upload: spool)
    }
    try check(response, data: data, bucket: bucket)
  }

  public func move(_ source: Location, to destination: Location) async throws {
    let (sourceBucket, sourceKey) = Self.split(source.path)
    let (bucket, key) = Self.split(destination.path)
    guard let sourceBucket, let bucket, !sourceKey.isEmpty, !key.isEmpty else {
      throw FileSystemError.unsupportedOperation
    }
    let original = try await stat(source)
    guard original.kind == .file else { throw FileSystemError.unsupportedOperation }
    if (original.size ?? 0) > singleRequestLimit { throw S3Error.tooLarge }
    if try await objectExists(bucket: bucket, key: key) { throw FileSystemError.destinationExists }
    var copy = request("PUT", bucket: bucket, key: key)
    copy.setValue(
      "/\(sourceBucket)/\(S3Signer.encode(sourceKey, keepSlash: true))",
      forHTTPHeaderField: "x-amz-copy-source")
    let (data, response) = try await perform(copy, bucket: bucket)
    try check(response, data: data, bucket: bucket)
    try await deleteObject(bucket: sourceBucket, key: sourceKey)
  }

  public func createDirectory(_ location: Location) async throws {
    let (bucket, key) = Self.split(location.path)
    guard let bucket, !key.isEmpty else { throw FileSystemError.unsupportedOperation }
    let marker = request("PUT", bucket: bucket, key: Self.folderPrefix(key))
    let (data, response) = try await perform(marker, bucket: bucket)
    try check(response, data: data, bucket: bucket)
  }

  public func delete(_ location: Location) async throws {
    let (bucket, key) = Self.split(location.path)
    guard let bucket, !key.isEmpty else { throw FileSystemError.unsupportedOperation }
    let entry = try await stat(location)
    guard entry.kind == .directory else {
      try await deleteObject(bucket: bucket, key: key)
      return
    }
    let prefix = Self.folderPrefix(key)
    var token: String?
    repeat {
      let page = try await listPage(
        bucket: bucket, prefix: prefix, delimiter: false, token: token, limit: 1000)
      for object in page.objects { try await deleteObject(bucket: bucket, key: object.key) }
      token = page.nextToken
    } while token != nil
  }

  // MARK: Requests

  private func listBuckets() async throws -> [FileEntry] {
    let (data, response) = try await perform(request("GET", bucket: nil), bucket: nil)
    try check(response, data: data, bucket: nil)
    return try S3XML.parse(data).buckets.map {
      FileEntry(
        location: Location(providerID: id, path: "/\($0.name)"), name: $0.name,
        kind: .directory, createdAt: $0.created, isHidden: false)
    }
  }

  private func listPage(
    bucket: String, prefix: String, delimiter: Bool, token: String?, limit: Int
  ) async throws -> S3XML.Result {
    var query: [(String, String)] = [("list-type", "2"), ("max-keys", String(limit))]
    if delimiter { query.append(("delimiter", "/")) }
    let folder = Self.folderPrefix(prefix)
    if !folder.isEmpty { query.append(("prefix", folder)) }
    if let token { query.append(("continuation-token", token)) }
    let (data, response) = try await perform(
      request("GET", bucket: bucket, query: query), bucket: bucket)
    try check(response, data: data, bucket: bucket)
    return try S3XML.parse(data)
  }

  /// An object and a folder prefix with the same name can coexist in S3, so a HEAD is enough.
  private func objectExists(bucket: String, key: String) async throws -> Bool {
    let (_, response) = try await perform(request("HEAD", bucket: bucket, key: key), bucket: bucket)
    if response.statusCode == 404 { return false }
    try check(response, data: Data(), bucket: bucket)
    return true
  }

  private func deleteObject(bucket: String, key: String) async throws {
    let (data, response) = try await perform(
      request("DELETE", bucket: bucket, key: key), bucket: bucket)
    try check(response, data: data, bucket: bucket)
  }

  private func request(
    _ method: String, bucket: String?, key: String = "", query: [(String, String)] = []
  ) -> URLRequest {
    var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) ?? URLComponents()
    var path = "/"
    if let bucket { path += bucket + (key.isEmpty ? "" : "/" + key) }
    components.percentEncodedPath = S3Signer.encode(path, keepSlash: true)
    components.percentEncodedQuery = query.isEmpty ? nil : S3Signer.query(query)
    var request = URLRequest(url: components.url ?? endpoint)
    request.httpMethod = method
    return request
  }

  private func signed(
    _ request: URLRequest, bucket: String?, payloadHash: String = S3Signer.emptyPayloadHash
  ) -> URLRequest {
    let region = bucket.flatMap { bucketRegions[$0] } ?? defaultRegion
    return S3Signer(accessKey: accessKey, secretKey: secretKey, region: region)
      .sign(request, payloadHash: payloadHash)
  }

  /// Sends a signed request. A bucket that lives in another region answers with its region; the
  /// request is then repeated once with that region, which is remembered for the bucket.
  private func perform(
    _ request: URLRequest, bucket: String?, payloadHash: String = S3Signer.emptyPayloadHash,
    upload: URL? = nil
  ) async throws -> (Data, HTTPURLResponse) {
    var attempts = 0
    while true {
      let signedRequest = signed(request, bucket: bucket, payloadHash: payloadHash)
      let data: Data
      let response: URLResponse
      do {
        if let upload {
          (data, response) = try await session.upload(for: signedRequest, fromFile: upload)
        } else {
          (data, response) = try await session.data(for: signedRequest)
        }
      } catch let error as URLError where WebDAVProvider.isCertificateError(error) {
        throw FileSystemError.io(
          "The server's certificate is not trusted, so the connection was not made.")
      }
      guard let http = response as? HTTPURLResponse else {
        throw FileSystemError.unsupportedOperation
      }
      if attempts == 0, let bucket, let region = Self.redirectRegion(http, data),
        region != (bucketRegions[bucket] ?? defaultRegion)
      {
        bucketRegions[bucket] = region
        attempts += 1
        continue
      }
      return (data, http)
    }
  }

  // MARK: Errors and helpers

  private func check(_ response: HTTPURLResponse, data: Data, bucket: String?) throws {
    guard !(200..<300).contains(response.statusCode) else {
      // CopyObject can answer 200 with an error document.
      if let info = S3XML.errorInfo(data) {
        throw Self.error(code: info.code, message: info.message, status: 500, bucket: bucket)
      }
      return
    }
    let info = S3XML.errorInfo(data)
    throw Self.error(
      code: info?.code, message: info?.message, status: response.statusCode, bucket: bucket)
  }

  static func error(code: String?, message: String?, status: Int, bucket: String?) -> any Error {
    switch code ?? "" {
    case "AccessDenied", "AllAccessDisabled": return S3Error.accessDenied(bucket: bucket)
    case "NoSuchBucket", "NoSuchKey", "NotFound": return FileSystemError.notFound
    case "InvalidAccessKeyId", "SignatureDoesNotMatch", "ExpiredToken", "InvalidToken":
      return URLError(.userAuthenticationRequired)
    case "PreconditionFailed": return FileSystemError.destinationExists
    default: break
    }
    switch status {
    case 403: return S3Error.accessDenied(bucket: bucket)
    case 404: return FileSystemError.notFound
    case 412: return FileSystemError.destinationExists
    default:
      return S3Error.service(
        code: code ?? "HTTP \(status)", message: message ?? "The request failed.")
    }
  }

  private static func redirectRegion(_ response: HTTPURLResponse, _ data: Data) -> String? {
    guard [301, 400].contains(response.statusCode) else { return nil }
    if let header = response.value(forHTTPHeaderField: "x-amz-bucket-region") { return header }
    return S3XML.errorInfo(data)?.region
  }

  static func split(_ path: String) -> (bucket: String?, key: String) {
    let trimmed = path.drop { $0 == "/" }
    guard !trimmed.isEmpty else { return (nil, "") }
    guard let slash = trimmed.firstIndex(of: "/") else { return (String(trimmed), "") }
    return (String(trimmed[..<slash]), String(trimmed[trimmed.index(after: slash)...]))
  }

  /// A folder key always ends in `/`; the bucket root is the empty prefix.
  static func folderPrefix(_ key: String) -> String {
    key.isEmpty || key.hasSuffix("/") ? key : key + "/"
  }

  private static func httpDate(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "GMT")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.date(from: value)
  }
}

/// Reads the S3 XML documents this provider needs. Local names only, so the namespace is ignored.
enum S3XML {
  struct Object {
    var key = ""
    var size: Int64?
    var modified: Date?
  }
  struct Bucket {
    var name = ""
    var created: Date?
  }
  struct Result {
    var objects: [Object] = []
    var prefixes: [String] = []
    var buckets: [Bucket] = []
    var nextToken: String?
  }

  static func parse(_ data: Data) throws -> Result {
    let delegate = Delegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = true
    guard parser.parse() else { throw FileSystemError.io("The server sent an unreadable listing.") }
    return delegate.result
  }

  static func errorInfo(_ data: Data) -> (code: String, message: String, region: String?)? {
    guard !data.isEmpty else { return nil }
    let delegate = Delegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate
    parser.shouldProcessNamespaces = true
    _ = parser.parse()
    guard let code = delegate.errorCode else { return nil }
    return (code, delegate.errorMessage ?? "", delegate.errorRegion)
  }

  static func date(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }

  private final class Delegate: NSObject, XMLParserDelegate {
    var result = Result()
    var errorCode: String?
    var errorMessage: String?
    var errorRegion: String?
    private var path: [String] = []
    private var text = ""
    private var object = Object()
    private var bucket = Bucket()

    func parser(
      _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
      qualifiedName: String?, attributes: [String: String] = [:]
    ) {
      path.append(name)
      text = ""
      if name == "Contents" { object = Object() }
      if name == "Bucket" { bucket = Bucket() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(
      _ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
      qualifiedName: String?
    ) {
      let value = text
      switch path.joined(separator: "/") {
      case "ListBucketResult/Contents/Key": object.key = value
      case "ListBucketResult/Contents/Size": object.size = Int64(value)
      case "ListBucketResult/Contents/LastModified": object.modified = S3XML.date(value)
      case "ListBucketResult/Contents": result.objects.append(object)
      case "ListBucketResult/CommonPrefixes/Prefix": result.prefixes.append(value)
      case "ListBucketResult/NextContinuationToken": result.nextToken = value
      case "ListAllMyBucketsResult/Buckets/Bucket/Name": bucket.name = value
      case "ListAllMyBucketsResult/Buckets/Bucket/CreationDate": bucket.created = S3XML.date(value)
      case "ListAllMyBucketsResult/Buckets/Bucket": result.buckets.append(bucket)
      case "Error/Code": errorCode = value
      case "Error/Message": errorMessage = value
      case "Error/Region": errorRegion = value
      default: break
      }
      path.removeLast()
    }
  }
}
