import Foundation
import Testing

@testable import FileTermCore

/// Serves canned responses so no network or server is needed.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
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

@Suite(.serialized) struct WebDAVProviderTests {
  private func provider(_ handler: @escaping @Sendable (URLRequest) -> StubURLProtocol.Reply)
    -> WebDAVProvider
  {
    StubURLProtocol.handler = handler
    StubURLProtocol.requests = []
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return WebDAVProvider(
      id: "webdav.test", baseURL: URL(string: "http://dav.test")!, username: nil, password: nil,
      configuration: configuration)
  }

  @Test func listingsDropParentFolderNames() async throws {
    let provider = provider { _ in
      StubURLProtocol.Reply(
        status: 207,
        body: """
          <?xml version="1.0"?>
          <D:multistatus xmlns:D="DAV:">
          <D:response><D:href>/docs/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
          <D:response><D:href>/docs/..</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
          <D:response><D:href>/docs/ok.txt</D:href><D:propstat><D:prop><D:resourcetype/></D:prop></D:propstat></D:response>
          </D:multistatus>
          """)
    }
    let entries = try await provider.list(
      Location(providerID: "webdav.test", path: "/docs"), includeHidden: true)
    #expect(entries.map(\.name) == ["ok.txt"])
  }

  private final class IgnoringSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
  }

  private func authenticator(base: String) -> WebDAVAuthenticator {
    WebDAVAuthenticator(
      baseURL: URL(string: base)!, username: "user", password: "secret", trustedCertificate: nil)
  }

  private func credential(
    base: String, host: String, port: Int, scheme: String,
    method: String = NSURLAuthenticationMethodHTTPBasic
  ) -> URLCredential? {
    let space = URLProtectionSpace(
      host: host, port: port, protocol: scheme, realm: "dav", authenticationMethod: method)
    let challenge = URLAuthenticationChallenge(
      protectionSpace: space, proposedCredential: nil, previousFailureCount: 0,
      failureResponse: nil, error: nil, sender: IgnoringSender())
    nonisolated(unsafe) var answer: URLCredential?
    authenticator(base: base).urlSession(
      URLSession.shared, task: URLSession.shared.dataTask(with: URL(string: base)!),
      didReceive: challenge
    ) { _, credential in answer = credential }
    return answer
  }

  @Test func thePasswordIsOnlyOfferedToTheConfiguredServer() {
    let base = "https://dav.test"
    #expect(credential(base: base, host: "dav.test", port: 443, scheme: "https") != nil)
    #expect(credential(base: base, host: "DAV.test", port: 443, scheme: "https") != nil)
    #expect(credential(base: base, host: "evil.test", port: 443, scheme: "https") == nil)
    #expect(credential(base: base, host: "dav.test", port: 8443, scheme: "https") == nil)
    #expect(credential(base: base, host: "dav.test", port: 80, scheme: "http") == nil)
    #expect(
      credential(base: "http://dav.test:8080", host: "dav.test", port: 8080, scheme: "http") != nil)
    #expect(
      credential(base: "http://dav.test", host: "dav.test", port: 443, scheme: "https") != nil)
  }

  private func redirect(base: String, to target: String) -> URL? {
    let response = HTTPURLResponse(
      url: URL(string: base)!, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil)!
    nonisolated(unsafe) var answer: URL?
    authenticator(base: base).urlSession(
      URLSession.shared, task: URLSession.shared.dataTask(with: URL(string: base)!),
      willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: target)!)
    ) { answer = $0?.url }
    return answer
  }

  @Test func redirectsMayNotLeaveTheServerOrDropTLS() {
    let base = "https://dav.test"
    #expect(redirect(base: base, to: "https://dav.test/docs/") != nil)
    #expect(redirect(base: base, to: "https://evil.test/docs/") == nil)
    #expect(redirect(base: base, to: "http://dav.test/docs/") == nil)
    #expect(redirect(base: "http://dav.test", to: "https://dav.test/docs/") != nil)
  }

  private func multistatus(_ prefix: String, root: String = "/docs/") -> String {
    let p = prefix.isEmpty ? "" : prefix + ":"
    let ns = prefix.isEmpty ? "xmlns=\"DAV:\"" : "xmlns:\(prefix)=\"DAV:\""
    return """
      <?xml version="1.0"?>
      <\(p)multistatus \(ns)>
      <\(p)response><\(p)href>\(root)</\(p)href><\(p)propstat><\(p)prop>
      <\(p)resourcetype><\(p)collection/></\(p)resourcetype></\(p)prop></\(p)propstat></\(p)response>
      <\(p)response><\(p)href>\(root)a%20b.txt</\(p)href><\(p)propstat><\(p)prop>
      <\(p)resourcetype/><\(p)getcontentlength>42</\(p)getcontentlength>
      <\(p)getlastmodified>Wed, 21 Oct 2026 07:28:00 GMT</\(p)getlastmodified>
      </\(p)prop></\(p)propstat></\(p)response>
      <\(p)response><\(p)href>http://dav.test\(root)caf%C3%A9/</\(p)href><\(p)propstat><\(p)prop>
      <\(p)resourcetype><\(p)collection/></\(p)resourcetype></\(p)prop></\(p)propstat></\(p)response>
      <\(p)response><\(p)href>\(root).hidden</\(p)href><\(p)propstat><\(p)prop>
      <\(p)resourcetype/></\(p)prop></\(p)propstat></\(p)response>
      </\(p)multistatus>
      """
  }

  @Test(arguments: ["D", "d", ""]) func listsWithAnyNamespacePrefix(prefix: String) async throws {
    let body = multistatus(prefix)
    let dav = provider { _ in .init(status: 207, body: body) }
    let entries = try await dav.list(Location(providerID: "webdav.test", path: "/docs"))
    let names = Set(entries.map(\.name))
    #expect(names == ["a b.txt", "café"])
    let file = try #require(entries.first { $0.name == "a b.txt" })
    #expect(file.kind == .file && file.size == 42 && file.modifiedAt != nil)
    #expect(file.location.path == "/docs/a b.txt")
    #expect(try #require(entries.first { $0.name == "café" }).kind == .directory)
    let withHidden = try await dav.list(
      Location(providerID: "webdav.test", path: "/docs"), includeHidden: true)
    #expect(withHidden.count == 3)
  }

  @Test func namesAreDecodedOnlyOnce() async throws {
    let body = """
      <D:multistatus xmlns:D="DAV:">
      <D:response><D:href>/docs/</D:href><D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
      <D:response><D:href>/docs/a%2520b.txt</D:href><D:propstat><D:prop><D:resourcetype/></D:prop></D:propstat></D:response>
      </D:multistatus>
      """
    let dav = provider { _ in .init(status: 207, body: body) }
    let entries = try await dav.list(Location(providerID: "webdav.test", path: "/docs"))
    #expect(entries.map(\.name) == ["a%20b.txt"])
    #expect(entries.first?.location.path == "/docs/a%20b.txt")
  }

  @Test func sendsDepthAndEncodesPaths() async throws {
    let body = multistatus("D", root: "/my docs/")
    let dav = provider { _ in .init(status: 207, body: body) }
    _ = try await dav.list(Location(providerID: "webdav.test", path: "/my docs"))
    let request = try #require(StubURLProtocol.requests.first)
    #expect(request.httpMethod == "PROPFIND")
    #expect(request.value(forHTTPHeaderField: "Depth") == "1")
    #expect(request.url?.absoluteString == "http://dav.test/my%20docs")
  }

  @Test func validateAcceptsARealWebDAVServer() async throws {
    let body = multistatus("D", root: "/")
    let dav = provider { request in
      request.httpMethod == "OPTIONS"
        ? .init(headers: ["DAV": "1,2"]) : .init(status: 207, body: body)
    }
    try await dav.validate()
  }

  @Test func validateRejectsOrdinaryWebsites() async throws {
    let page = provider { _ in .init(body: "<html><body>Hello</body></html>") }
    await #expect(throws: WebDAVError.notWebDAV) { try await page.validate() }
    let noHeader = provider { request in
      request.httpMethod == "OPTIONS" ? .init() : .init(status: 207, body: "<x/>")
    }
    await #expect(throws: WebDAVError.notWebDAV) { try await noHeader.validate() }
    let badBody = provider { request in
      request.httpMethod == "OPTIONS"
        ? .init(headers: ["DAV": "1"]) : .init(status: 207, body: "<html></html>")
    }
    await #expect(throws: WebDAVError.notWebDAV) { try await badBody.validate() }
  }

  @Test func authenticationFailureIsNotReportedAsNotWebDAV() async throws {
    let dav = provider { _ in .init(status: 401) }
    await #expect(throws: URLError.self) { try await dav.validate() }
  }

  @Test func mapsStatusCodes() throws {
    #expect(throws: URLError.self) { try WebDAVProvider.check(401) }
    #expect(throws: FileSystemError.permissionDenied) { try WebDAVProvider.check(403) }
    #expect(throws: FileSystemError.notFound) { try WebDAVProvider.check(404) }
    #expect(throws: FileSystemError.unsupportedOperation) { try WebDAVProvider.check(405) }
    #expect(throws: FileSystemError.destinationExists) { try WebDAVProvider.check(412) }
    #expect(throws: FileSystemError.io("The server returned error 503.")) {
      try WebDAVProvider.check(503)
    }
    #expect(throws: Never.self) { try WebDAVProvider.check(204) }
  }

  @Test func readStreamsTheBody() async throws {
    let payload = String(repeating: "x", count: 70_000)
    let dav = provider { _ in .init(body: payload) }
    let reader = try await dav.read(Location(providerID: "webdav.test", path: "/big.bin"))
    var total = 0
    var chunks = 0
    while let chunk = try await reader.next() {
      total += chunk.count
      chunks += 1
    }
    #expect(total == 70_000 && chunks == 2)
  }

  @Test func writeRefusesToOverwrite() async throws {
    let dav = provider { _ in .init(status: 412) }
    let reader = OneShotReader(data: Data("hi".utf8))
    await #expect(throws: FileSystemError.destinationExists) {
      try await dav.write(reader, to: Location(providerID: "webdav.test", path: "/f.txt"))
    }
    let request = try #require(StubURLProtocol.requests.last)
    #expect(request.httpMethod == "PUT")
    #expect(request.value(forHTTPHeaderField: "If-None-Match") == "*")
  }

  @Test func createDirectorySendsMKCOLAndMapsExistingFolders() async throws {
    let created = provider { _ in .init(status: 201) }
    try await created.createDirectory(Location(providerID: "webdav.test", path: "/new dir"))
    let request = try #require(StubURLProtocol.requests.last)
    #expect(request.httpMethod == "MKCOL")
    #expect(request.url?.absoluteString == "http://dav.test/new%20dir")
    let existing = provider { _ in .init(status: 405) }
    await #expect(throws: FileSystemError.destinationExists) {
      try await existing.createDirectory(Location(providerID: "webdav.test", path: "/new"))
    }
    let missingParent = provider { _ in .init(status: 409) }
    await #expect(throws: FileSystemError.io("The parent folder does not exist on the server.")) {
      try await missingParent.createDirectory(Location(providerID: "webdav.test", path: "/a/b"))
    }
  }

  @Test func moveNeverOverwritesTheDestination() async throws {
    let dav = provider { _ in .init(status: 201) }
    try await dav.move(
      Location(providerID: "webdav.test", path: "/.f.part"),
      to: Location(providerID: "webdav.test", path: "/f.txt"))
    let request = try #require(StubURLProtocol.requests.last)
    #expect(request.httpMethod == "MOVE")
    #expect(request.value(forHTTPHeaderField: "Overwrite") == "F")
    #expect(request.value(forHTTPHeaderField: "Destination") == "http://dav.test/f.txt")
  }
}

private final class OneShotReader: FileByteReader, @unchecked Sendable {
  private var data: Data?
  init(data: Data) { self.data = data }
  func next() async throws -> Data? {
    defer { data = nil }
    return data
  }
}
