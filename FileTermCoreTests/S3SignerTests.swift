import Foundation
import Testing

@testable import FileTermCore

@Suite struct S3SignerTests {
  private let signer = S3Signer(
    accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    region: "us-east-1", now: { Date(timeIntervalSince1970: 1_369_353_600) })  // 20130524T000000Z

  /// The "GET Object" example from the AWS Signature Version 4 documentation for S3.
  @Test func matchesTheDocumentedGetObjectExample() throws {
    var request = URLRequest(url: URL(string: "https://examplebucket.s3.amazonaws.com/test.txt")!)
    request.httpMethod = "GET"
    request.setValue("bytes=0-9", forHTTPHeaderField: "Range")
    let signed = signer.sign(request, payloadHash: S3Signer.emptyPayloadHash)
    let authorization = try #require(signed.value(forHTTPHeaderField: "Authorization"))
    #expect(
      authorization
        == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,"
        + " SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,"
        + " Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
  }

  /// The "GET Bucket (List Objects)" example from the same documentation page.
  @Test func matchesTheDocumentedListObjectsExample() throws {
    let url = URL(string: "https://examplebucket.s3.amazonaws.com/?max-keys=2&prefix=J")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    let signed = signer.sign(request, payloadHash: S3Signer.emptyPayloadHash)
    let authorization = try #require(signed.value(forHTTPHeaderField: "Authorization"))
    #expect(
      authorization.hasSuffix(
        "Signature=34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7"))
  }

  @Test func encodesKeysStrictlyAndSortsQueries() {
    #expect(
      S3Signer.encode("a b/café!*'().txt", keepSlash: true) == "a%20b/caf%C3%A9%21%2A%27%28%29.txt")
    #expect(S3Signer.encode("a/b") == "a%2Fb")
    #expect(
      S3Signer.query([("prefix", "photos/2026 trip/"), ("delimiter", "/"), ("list-type", "2")])
        == "delimiter=%2F&list-type=2&prefix=photos%2F2026%20trip%2F")
  }

  @Test func signsEveryAmzHeaderIncludingTheCopySource() throws {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:9000/b/new.txt")!)
    request.httpMethod = "PUT"
    request.setValue("/b/old%20name.txt", forHTTPHeaderField: "x-amz-copy-source")
    let signed = signer.sign(request, payloadHash: S3Signer.emptyPayloadHash)
    let authorization = try #require(signed.value(forHTTPHeaderField: "Authorization"))
    #expect(
      authorization.contains(
        "SignedHeaders=host;x-amz-content-sha256;x-amz-copy-source;x-amz-date"))
    #expect(signed.value(forHTTPHeaderField: "Host") == "127.0.0.1:9000")
  }

  @Test func aTrailingSlashChangesTheSignature() throws {
    func signature(_ url: String) throws -> String {
      var request = URLRequest(url: URL(string: url)!)
      request.httpMethod = "PUT"
      let signed = signer.sign(request, payloadHash: S3Signer.emptyPayloadHash)
      return try #require(signed.value(forHTTPHeaderField: "Authorization"))
    }
    #expect(try signature("http://s3.test/b/dir/") != signature("http://s3.test/b/dir"))
  }
}
