import CryptoKit
import Foundation
import Testing

@testable import FileTermCore

/// Serves canned responses so no network or server is needed. Separate from the WebDAV stub so
/// suites that run in parallel never share handler state.
final class S3StubProtocol: URLProtocol, @unchecked Sendable {
  struct Reply {
    var status = 200
    var headers: [String: String] = [:]
    var body = ""
  }
  nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Reply)?
  nonisolated(unsafe) static var requests: [URLRequest] = []

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.requests.append(request)
    let reply = Self.handler?(request) ?? Reply(status: 500)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
      headerFields: reply.headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized) struct S3ProviderTests {
  private func provider(
    singleRequestLimit: Int64 = 5 * 1024 * 1024 * 1024,
    _ handler: @escaping @Sendable (URLRequest) -> S3StubProtocol.Reply
  ) -> S3Provider {
    S3StubProtocol.handler = handler
    S3StubProtocol.requests = []
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [S3StubProtocol.self]
    return S3Provider(
      id: "s3.test", endpoint: URL(string: "http://s3.test:9000")!, region: "us-east-1",
      accessKey: "AKID", secretKey: "secret", configuration: configuration,
      singleRequestLimit: singleRequestLimit)
  }

  private func at(_ path: String) -> Location { Location(providerID: "s3.test", path: path) }

  @Test func listingsDropKeysAndPrefixesThatLeaveTheFolder() async throws {
    let provider = provider { _ in
      S3StubProtocol.Reply(
        body: """
          <?xml version="1.0"?>
          <ListBucketResult>
          <IsTruncated>false</IsTruncated>
          <CommonPrefixes><Prefix>../</Prefix></CommonPrefixes>
          <Contents><Key>../../evil</Key><Size>1</Size></Contents>
          <Contents><Key>ok.txt</Key><Size>1</Size></Contents>
          </ListBucketResult>
          """)
    }
    let entries = try await provider.list(at("/bucket"), includeHidden: true)
    #expect(entries.map(\.name) == ["ok.txt"])
  }

  private func xml(_ body: String) -> String {
    "<?xml version=\"1.0\"?>" + body
  }

  private func errorBody(_ code: String, _ message: String = "msg", region: String? = nil)
    -> String
  {
    xml(
      "<Error><Code>\(code)</Code><Message>\(message)</Message>"
        + (region.map { "<Region>\($0)</Region>" } ?? "") + "</Error>")
  }

  // MARK: Listing

  @Test func listsBucketsAsFolders() async throws {
    let s3 = provider { _ in
      .init(
        body: self.xml(
          """
          <ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Buckets>
          <Bucket><Name>photos</Name><CreationDate>2026-01-02T03:04:05.000Z</CreationDate></Bucket>
          <Bucket><Name>backups</Name><CreationDate>2026-02-03T00:00:00Z</CreationDate></Bucket>
          </Buckets></ListAllMyBucketsResult>
          """))
    }
    let entries = try await s3.list(at("/"))
    #expect(entries.map(\.name) == ["photos", "backups"])
    #expect(entries.allSatisfy { $0.kind == .directory })
    #expect(entries[0].location.path == "/photos" && entries[0].createdAt != nil)
    let request = try #require(S3StubProtocol.requests.first)
    #expect(request.httpMethod == "GET" && request.url?.path == "/")
    #expect(
      request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("AWS4-HMAC-SHA256") == true)
  }

  @Test func listsPrefixesAsFoldersAndFollowsPagination() async throws {
    let s3 = provider { request in
      let query = request.url?.query ?? ""
      if query.contains("continuation-token=TOKEN") {
        return .init(
          body: self.xml(
            """
            <ListBucketResult><IsTruncated>false</IsTruncated>
            <Contents><Key>docs/b &amp; c.txt</Key><Size>7</Size>
            <LastModified>2026-03-04T05:06:07.000Z</LastModified></Contents>
            <Contents><Key>docs/.hidden</Key><Size>1</Size></Contents>
            </ListBucketResult>
            """))
      }
      return .init(
        body: self.xml(
          """
          <ListBucketResult><Prefix>docs/</Prefix><IsTruncated>true</IsTruncated>
          <NextContinuationToken>TOKEN</NextContinuationToken>
          <Contents><Key>docs/</Key><Size>0</Size></Contents>
          <Contents><Key>docs/a.txt</Key><Size>42</Size></Contents>
          <CommonPrefixes><Prefix>docs/sub folder/</Prefix></CommonPrefixes>
          </ListBucketResult>
          """))
    }
    let entries = try await s3.list(at("/bucket/docs"))
    #expect(Set(entries.map(\.name)) == ["a.txt", "b & c.txt", "sub folder"])
    let folder = try #require(entries.first { $0.name == "sub folder" })
    #expect(folder.kind == .directory && folder.location.path == "/bucket/docs/sub folder")
    let file = try #require(entries.first { $0.name == "b & c.txt" })
    #expect(file.size == 7 && file.modifiedAt != nil)
    #expect(S3StubProtocol.requests.count == 2)
    let first = try #require(S3StubProtocol.requests.first?.url?.query)
    #expect(first == "delimiter=%2F&list-type=2&max-keys=1000&prefix=docs%2F")
    let withHidden = try await s3.list(at("/bucket/docs"), includeHidden: true)
    #expect(withHidden.contains { $0.name == ".hidden" })
  }

  // MARK: Stat

  @Test func statsFilesFoldersAndMissingItems() async throws {
    let s3 = provider { request in
      let path = request.url?.path ?? ""
      if request.httpMethod == "HEAD" {
        return path == "/b/file.txt"
          ? .init(
            headers: [
              "Content-Length": "12", "Last-Modified": "Wed, 21 Oct 2026 07:28:00 GMT",
            ]) : .init(status: 404)
      }
      let prefix = request.url?.query ?? ""
      return prefix.contains("prefix=dir%2F")
        ? .init(
          body: self.xml(
            "<ListBucketResult><Contents><Key>dir/x</Key><Size>1</Size></Contents></ListBucketResult>"
          ))
        : .init(body: self.xml("<ListBucketResult></ListBucketResult>"))
    }
    let file = try await s3.stat(at("/b/file.txt"))
    #expect(file.kind == .file && file.size == 12 && file.modifiedAt != nil)
    #expect(try await s3.stat(at("/b/dir")).kind == .directory)
    await #expect(throws: FileSystemError.notFound) { try await s3.stat(self.at("/b/none")) }
  }

  // MARK: Writing

  @Test func writeSendsAConditionalSignedPutAndMapsExistingObjects() async throws {
    let s3 = provider { _ in .init() }
    try await s3.write(OneShot("hello"), to: at("/b/dir/a b.txt"))
    let put = try #require(S3StubProtocol.requests.last)
    #expect(put.httpMethod == "PUT" && put.url?.absoluteString.contains("/b/dir/a%20b.txt") == true)
    #expect(put.value(forHTTPHeaderField: "If-None-Match") == "*")
    let expected = S3Signer.hex(SHA256.hash(data: Data("hello".utf8)))
    #expect(put.value(forHTTPHeaderField: "x-amz-content-sha256") == expected)

    let existing = provider { _ in .init(status: 412, body: self.errorBody("PreconditionFailed")) }
    await #expect(throws: FileSystemError.destinationExists) {
      try await existing.write(OneShot("x"), to: self.at("/b/a.txt"))
    }
  }

  @Test func writeFallsBackWhenTheStoreIgnoresConditionalWrites() async throws {
    let calls = Counter()
    let s3 = provider { request in
      if request.httpMethod == "PUT" {
        return calls.next() == 0
          ? .init(status: 501, body: self.errorBody("NotImplemented")) : .init()
      }
      return .init(status: 404)
    }
    try await s3.write(OneShot("data"), to: at("/b/new.txt"))
    let methods = S3StubProtocol.requests.map { $0.httpMethod ?? "" }
    #expect(methods == ["PUT", "HEAD", "PUT"])
    #expect(S3StubProtocol.requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
  }

  @Test func writeRefusesFilesOverTheSingleRequestLimit() async throws {
    let s3 = provider(singleRequestLimit: 4) { _ in .init() }
    await #expect(throws: S3Error.tooLarge) {
      try await s3.write(OneShot("hello"), to: self.at("/b/a"))
    }
    #expect(S3StubProtocol.requests.isEmpty)
    await #expect(throws: FileSystemError.unsupportedOperation) {
      try await s3.write(OneShot("x"), to: self.at("/bucket-only"))
    }
  }

  // MARK: Move, folders, delete

  @Test func moveCopiesThenDeletesAndNeverOverwrites() async throws {
    let s3 = provider { request in
      switch (request.httpMethod ?? "", request.url?.path ?? "") {
      case ("HEAD", "/b/.tmp.part"): return .init(headers: ["Content-Length": "3"])
      case ("HEAD", _): return .init(status: 404)
      default: return .init(status: 200)
      }
    }
    try await s3.move(at("/b/.tmp.part"), to: at("/b/final name.txt"))
    let methods = S3StubProtocol.requests.map { $0.httpMethod ?? "" }
    #expect(methods == ["HEAD", "HEAD", "PUT", "DELETE"])
    let copy = S3StubProtocol.requests[2]
    #expect(copy.value(forHTTPHeaderField: "x-amz-copy-source") == "/b/.tmp.part")
    #expect(copy.url?.absoluteString.contains("/b/final%20name.txt") == true)
    #expect(S3StubProtocol.requests[3].url?.path == "/b/.tmp.part")

    let occupied = provider { _ in .init(headers: ["Content-Length": "3"]) }
    await #expect(throws: FileSystemError.destinationExists) {
      try await occupied.move(self.at("/b/a"), to: self.at("/b/c"))
    }
  }

  @Test func moveSurfacesAnErrorInsideASuccessfulCopyResponse() async throws {
    let s3 = provider { request in
      switch request.httpMethod ?? "" {
      case "HEAD":
        return request.url?.path == "/b/src"
          ? .init(headers: ["Content-Length": "1"]) : .init(status: 404)
      default: return .init(body: self.errorBody("AccessDenied"))
      }
    }
    await #expect(throws: S3Error.accessDenied(bucket: "b")) {
      try await s3.move(self.at("/b/src"), to: self.at("/b/dst"))
    }
    #expect(!S3StubProtocol.requests.contains { $0.httpMethod == "DELETE" })
  }

  @Test func createDirectoryWritesAMarkerObject() async throws {
    let s3 = provider { _ in .init() }
    try await s3.createDirectory(at("/b/new folder"))
    let request = try #require(S3StubProtocol.requests.last)
    #expect(
      request.httpMethod == "PUT" && request.url?.path(percentEncoded: true) == "/b/new%20folder/")
    await #expect(throws: FileSystemError.unsupportedOperation) {
      try await s3.createDirectory(self.at("/new-bucket"))
    }
  }

  @Test func deleteRemovesFilesAndEveryKeyUnderAFolder() async throws {
    let file = provider { _ in .init(headers: ["Content-Length": "1"]) }
    try await file.delete(at("/b/a.txt"))
    #expect(S3StubProtocol.requests.map { $0.httpMethod ?? "" } == ["HEAD", "DELETE"])

    let folder = provider { request in
      if request.httpMethod == "HEAD" { return .init(status: 404) }
      if request.httpMethod == "GET" {
        return .init(
          body: self.xml(
            "<ListBucketResult><Contents><Key>dir/a</Key><Size>1</Size></Contents>"
              + "<Contents><Key>dir/sub/b</Key><Size>1</Size></Contents></ListBucketResult>"))
      }
      return .init(status: 204)
    }
    try await folder.delete(at("/b/dir"))
    let deleted = S3StubProtocol.requests.filter { $0.httpMethod == "DELETE" }.compactMap {
      $0.url?.path
    }
    #expect(deleted == ["/b/dir/a", "/b/dir/sub/b"])
    await #expect(throws: FileSystemError.unsupportedOperation) {
      try await folder.delete(self.at("/b"))
    }
  }

  // MARK: Errors, regions, validation

  @Test func mapsServiceErrorsAndNamesTheBucket() async throws {
    let denied = provider { _ in .init(status: 403, body: self.errorBody("AccessDenied")) }
    await #expect(throws: S3Error.accessDenied(bucket: "secret")) {
      try await denied.list(self.at("/secret"))
    }
    let headOnly = provider { _ in .init(status: 403) }
    await #expect(throws: S3Error.accessDenied(bucket: "locked")) {
      try await headOnly.stat(self.at("/locked/x"))
    }
    let missing = provider { _ in .init(status: 404, body: self.errorBody("NoSuchBucket")) }
    await #expect(throws: FileSystemError.notFound) { try await missing.list(self.at("/ghost")) }
    let badSignature = provider { _ in
      .init(status: 403, body: self.errorBody("SignatureDoesNotMatch"))
    }
    await #expect(throws: URLError.self) { try await badSignature.list(self.at("/")) }
    let other = provider { _ in
      .init(status: 503, body: self.errorBody("SlowDown", "Reduce your rate"))
    }
    await #expect(throws: S3Error.service(code: "SlowDown", message: "Reduce your rate")) {
      try await other.list(self.at("/b"))
    }
    #expect(S3Error.accessDenied(bucket: "b").errorDescription?.contains("“b”") == true)
  }

  @Test func retriesOnceInTheBucketsRegionAndRemembersIt() async throws {
    let s3 = provider { request in
      let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
      if auth.contains("/us-east-1/s3/") {
        return .init(
          status: 400,
          body: self.errorBody("AuthorizationHeaderMalformed", region: "eu-west-1"))
      }
      return .init(body: self.xml("<ListBucketResult></ListBucketResult>"))
    }
    _ = try await s3.list(at("/eu-bucket"))
    #expect(S3StubProtocol.requests.count == 2)
    #expect(
      S3StubProtocol.requests[1].value(forHTTPHeaderField: "Authorization")?
        .contains("/eu-west-1/s3/aws4_request") == true)
    _ = try await s3.list(at("/eu-bucket"))
    #expect(S3StubProtocol.requests.count == 3)
  }

  @Test func validateChecksTheBucketOrTheBucketList() async throws {
    let ok = provider { _ in
      .init(body: self.xml("<ListAllMyBucketsResult><Buckets/></ListAllMyBucketsResult>"))
    }
    try await ok.validate(root: "/")
    let bucket = provider { _ in .init(body: self.xml("<ListBucketResult></ListBucketResult>")) }
    try await bucket.validate(root: "/photos/2026")
    let query = try #require(S3StubProtocol.requests.last?.url?.query)
    #expect(query.contains("max-keys=1") && query.contains("prefix=2026%2F"))

    let restricted = provider { _ in .init(status: 403, body: self.errorBody("AccessDenied")) }
    await #expect(throws: S3Error.cannotListBuckets) { try await restricted.validate(root: "/") }
    await #expect(throws: S3Error.accessDenied(bucket: "photos")) {
      try await restricted.validate(root: "/photos")
    }
    let wrong = provider { _ in .init(status: 403, body: self.errorBody("InvalidAccessKeyId")) }
    await #expect(throws: URLError.self) { try await wrong.validate(root: "/") }
  }

  @Test func splitsPathsIntoBucketAndKey() {
    #expect(S3Provider.split("/").bucket == nil)
    #expect(S3Provider.split("/b").bucket == "b" && S3Provider.split("/b").key == "")
    #expect(S3Provider.split("/b/dir/").key == "dir/")
    #expect(S3Provider.split("/b/a b/c").key == "a b/c")
    #expect(S3Provider.folderPrefix("dir") == "dir/" && S3Provider.folderPrefix("") == "")
  }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0
  func next() -> Int {
    lock.lock()
    defer { lock.unlock() }
    defer { value += 1 }
    return value
  }
}

private final class OneShot: FileByteReader, @unchecked Sendable {
  private var data: Data?
  init(_ text: String) { data = Data(text.utf8) }
  func next() async throws -> Data? {
    defer { data = nil }
    return data
  }
}
