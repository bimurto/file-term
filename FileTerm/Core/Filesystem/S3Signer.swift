import CryptoKit
import Foundation

/// AWS Signature Version 4 for the S3 service.
public struct S3Signer: Sendable {
  public let accessKey: String
  public let secretKey: String
  public let region: String
  private let now: @Sendable () -> Date

  public static let emptyPayloadHash = Self.hex(SHA256.hash(data: Data()))

  public init(
    accessKey: String, secretKey: String, region: String,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.accessKey = accessKey
    self.secretKey = secretKey
    self.region = region
    self.now = now
  }

  /// Adds `Host`, `x-amz-date`, `x-amz-content-sha256` and `Authorization`. Every header present
  /// on the request (including `x-amz-*` ones such as the copy source) is signed.
  public func sign(_ request: URLRequest, payloadHash: String) -> URLRequest {
    var request = request
    guard let url = request.url, let host = url.host else { return request }
    let date = now()
    let stamp = Self.format(date, "yyyyMMdd")
    let amzDate = Self.format(date, "yyyyMMdd'T'HHmmss'Z'")
    request.setValue(url.port.map { "\(host):\($0)" } ?? host, forHTTPHeaderField: "Host")
    request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
    request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

    let headers = (request.allHTTPHeaderFields ?? [:])
      .filter { $0.key.lowercased() != "authorization" }
      .map { ($0.key.lowercased(), $0.value.trimmingCharacters(in: .whitespaces)) }
      .sorted { $0.0 < $1.0 }
    let signedHeaders = headers.map(\.0).joined(separator: ";")
    let canonicalRequest = [
      request.httpMethod ?? "GET",
      Self.encode(Self.decodedPath(url), keepSlash: true),
      Self.canonicalQuery(url),
      headers.map { "\($0.0):\($0.1)\n" }.joined(),
      signedHeaders,
      payloadHash,
    ].joined(separator: "\n")

    let scope = "\(stamp)/\(region)/s3/aws4_request"
    let stringToSign = [
      "AWS4-HMAC-SHA256", amzDate, scope, Self.hex(SHA256.hash(data: Data(canonicalRequest.utf8))),
    ].joined(separator: "\n")
    var key = Self.hmac(Data("AWS4\(secretKey)".utf8), stamp)
    for part in [region, "s3", "aws4_request"] { key = Self.hmac(key, part) }
    let signature = Self.hex(
      HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: .init(data: key)))
    request.setValue(
      "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope), SignedHeaders=\(signedHeaders), "
        + "Signature=\(signature)", forHTTPHeaderField: "Authorization")
    return request
  }

  /// RFC 3986 encoding: only unreserved characters stay literal. S3 encodes object keys once.
  public static func encode(_ value: String, keepSlash: Bool = false) -> String {
    var allowed = CharacterSet(
      charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    if keepSlash { allowed.insert("/") }
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }

  /// Query items sorted by name then value, encoded strictly; used on the wire and when signing.
  public static func query(_ items: [(String, String)]) -> String {
    let encoded: [(name: String, value: String)] = items.map { (encode($0.0), encode($0.1)) }
    let sorted = encoded.sorted { lhs, rhs in
      lhs.name == rhs.name ? lhs.value < rhs.value : lhs.name < rhs.name
    }
    return sorted.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
  }

  /// `URL.path` drops a trailing slash, which S3 folder markers depend on.
  private static func decodedPath(_ url: URL) -> String {
    let encoded = url.path(percentEncoded: true)
    return encoded.removingPercentEncoding ?? encoded
  }

  private static func canonicalQuery(_ url: URL) -> String {
    guard let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery,
      !raw.isEmpty
    else { return "" }
    var items: [(String, String)] = []
    for pair in raw.split(separator: "&", omittingEmptySubsequences: true) {
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let name = String(parts[0]).removingPercentEncoding ?? String(parts[0])
      let value = parts.count > 1 ? (String(parts[1]).removingPercentEncoding ?? "") : ""
      items.append((name, value))
    }
    return query(items)
  }

  public static func hex(_ digest: some Sequence<UInt8>) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
  }

  private static func hmac(_ key: Data, _ message: String) -> Data {
    Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: .init(data: key)))
  }

  private static func format(_ date: Date, _ pattern: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = pattern
    return formatter.string(from: date)
  }
}
