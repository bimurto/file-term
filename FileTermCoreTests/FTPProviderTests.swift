import Foundation
import Testing

@testable import FileTermCore

@Suite struct FTPProviderTests {
  private let folder = Location(providerID: "ftp", path: "/pub")

  @Test func parsesMLSDFactsAndNamesWithSpaces() {
    let text = """
      type=cdir;modify=20261027215617; .\r
      type=pdir;modify=20261027215617; ..\r
      type=file;size=1234;modify=20240102030405.123;UNIX.mode=0644;UNIX.owner=ann; my file; v2.txt\r
      type=dir;modify=20240102000000;UNIX.mode=0755; sub\r
      type=OS.unix=slink:/x;modify=20240102000000; link\r
      type=file;size=5; .hidden
      """
    let entries = FTPListing.parseMLSD(text, in: folder, providerID: "ftp")
    #expect(entries.map(\.name) == ["my file; v2.txt", "sub", "link", ".hidden"])
    let file = entries[0]
    #expect(file.kind == .file && file.size == 1234 && file.owner == "ann")
    #expect(file.permissions == 0o644 && file.location.path == "/pub/my file; v2.txt")
    #expect(
      file.modifiedAt == ISO8601DateFormatter().date(from: "2024-01-02T03:04:05Z"))
    #expect(entries[1].kind == .directory && entries[1].size == nil)
    #expect(entries[2].kind == .symbolicLink && entries[3].isHidden)
  }

  @Test func parsesUnixListWithTimesYearsLinksAndSpaces() {
    let now = ISO8601DateFormatter().date(from: "2026-10-27T12:00:00Z")!
    let text = """
      total 12
      drwxr-xr-x    2 ftp      ftp          4096 Oct 20 10:15 docs
      -rw-r--r--    1 ftp      ftp          1500 Jan  3  2020 old report.pdf
      lrwxrwxrwx    1 ftp      ftp             4 Mar  1 08:00 latest -> docs
      -rw-r--r--    1 ftp      ftp             0 Dec 30 23:59 future.txt
      drwxr-xr-x    2 ftp      ftp          4096 Oct 20 10:15 .
      """
    let entries = FTPListing.parseList(text, in: folder, providerID: "ftp", now: now)
    #expect(entries.map(\.name) == ["docs", "old report.pdf", "latest", "future.txt"])
    #expect(entries[0].kind == .directory && entries[0].permissions == 0o755)
    #expect(entries[1].size == 1500)
    #expect(entries[1].modifiedAt == ISO8601DateFormatter().date(from: "2020-01-03T00:00:00Z"))
    #expect(entries[2].kind == .symbolicLink)
    // A time with no year that would lie in the future belongs to last year.
    #expect(entries[3].modifiedAt == ISO8601DateFormatter().date(from: "2025-12-30T23:59:00Z"))
  }

  @Test func parsesDOSList() {
    let text = """
      10-27-26  01:05PM       <DIR>          Backups
      01-02-24  09:30AM                 2048 notes final.txt
      """
    let entries = FTPListing.parseList(text, in: folder, providerID: "ftp")
    #expect(entries.map(\.name) == ["Backups", "notes final.txt"])
    #expect(entries[0].kind == .directory && entries[1].size == 2048)
    #expect(entries[0].modifiedAt == ISO8601DateFormatter().date(from: "2026-10-27T13:05:00Z"))
  }

  @Test func buildsCurlArgumentsForEachMode() {
    let plain = FTPProvider.arguments(
      secure: false, activeMode: false, allowInvalidCertificate: true)
    #expect(!plain.contains("--ssl-reqd") && !plain.contains("--insecure"))
    #expect(!plain.contains("--ftp-port"))
    let tls = FTPProvider.arguments(secure: true, activeMode: true, allowInvalidCertificate: false)
    #expect(tls.contains("--ssl-reqd") && !tls.contains("--insecure"))
    #expect(Array(tls.suffix(2)) == ["--ftp-port", "-"])
    let loose = FTPProvider.arguments(
      secure: true, activeMode: false, allowInvalidCertificate: true)
    #expect(loose.contains("--insecure"))
  }

  @Test func credentialsGoInTheConfigNotTheArguments() throws {
    let arguments = FTPProvider.arguments(
      secure: false, activeMode: false, allowInvalidCertificate: false)
    let config = try FTPProvider.configuration(
      host: "ftp.example.com", port: 2121, path: "/a b/é.txt", username: "ann",
      password: "p\"w\\d", secure: false)
    #expect(!arguments.joined().contains("p\"w"))
    #expect(config.contains(#"url = "ftp://ftp.example.com:2121/a%20b/%C3%A9.txt""#))
    #expect(config.contains(#"user = "ann:p\"w\\d""#))
    #expect(
      try FTPProvider.configuration(
        host: "h", port: 990, path: "/", username: nil, password: nil, secure: true
      ).contains("url = \"ftps://h:990/\""))
    #expect(throws: (any Error).self) {
      try FTPProvider.configuration(
        host: "h", port: nil, path: "/x\ny", username: nil, password: nil, secure: false)
    }
  }

  @Test func foldersKeepTheirTrailingSlashAndPathsAreRelative() throws {
    #expect(FTPProvider.folderPath("/") == "/")
    #expect(FTPProvider.folderPath("/a//b/") == "/a/b/")
    #expect(try FTPProvider.relative("/a/b c") == "a/b c")
    #expect(throws: (any Error).self) { try FTPProvider.relative("/a\nb") }
  }

  @Test func mapsCurlExitCodesToMessages() {
    func message(_ status: Int32, _ text: String = "") -> String {
      CurlFailure(status: status, message: text).mapped(host: "h", port: 21).localizedDescription
    }
    #expect(message(6).contains("could not be found"))
    #expect(message(7).contains("port 21"))
    #expect(message(67).contains("user name or password"))
    #expect(message(60).contains("Allow invalid certificate"))
    #expect(message(30).contains("passive"))
    #expect(
      CurlFailure(status: 78, message: "").mapped(host: "h", port: 21) as? FileSystemError
        == .notFound)
    #expect(message(19, "curl: (19) RETR response: 550\n") == "curl: (19) RETR response: 550")
  }
}
