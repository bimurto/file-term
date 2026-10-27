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
}

private final class OneShotReader: FileByteReader, @unchecked Sendable {
  private var data: Data?
  init(data: Data) { self.data = data }
  func next() async throws -> Data? {
    defer { data = nil }
    return data
  }
}
