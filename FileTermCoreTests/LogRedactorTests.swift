import Foundation
import Testing

@testable import FileTermCore

struct LogRedactorTests {
  private let secret = "hunter2secret"

  @Test(arguments: [
    "git push https://me:hunter2secret@github.com/a/b.git",
    "fatal: unable to access 'https://hunter2secret@github.com/a/b.git/'",
    "curl -u me:hunter2secret https://example.com",
    "curl --user me:hunter2secret https://example.com",
    "curl -H 'Authorization: Bearer hunter2secret' https://example.com",
    "Authorization: Basic hunter2secret",
    "tool --password hunter2secret --verbose",
    "tool --password=hunter2secret",
    "tool --api-key \"hunter2secret\"",
    "tool --access_key=hunter2secret",
    "API_TOKEN=hunter2secret deploy",
    "export DB_PASSWORD='hunter2secret'",
    "curl https://example.com/a?token=hunter2secret&page=2",
  ])
  func removesTheSecret(line: String) {
    let redacted = LogRedactor.redact(line)
    #expect(!redacted.contains(secret), "\(redacted)")
    #expect(redacted.contains(LogRedactor.mask))
  }

  @Test(arguments: [
    "ghp_abcdefghijklmnopqrstuvwxyz123456",
    "github_pat_abcdefghijklmnopqrstuvwxyz",
    "xoxb-1234567890-abcdefghij",
    "AKIAIOSFODNN7EXAMPLE",
    "sk-abcdefghijklmnopqrstuvwxyz",
  ])
  func removesTokensRecognisableOnTheirOwn(token: String) {
    let redacted = LogRedactor.redact("using \(token) now")
    #expect(redacted == "using \(LogRedactor.mask) now")
  }

  @Test(arguments: [
    "$ cp /Users/me/a.txt /Users/me/token-notes/b.txt",
    "Uploaded secret-plans.txt to sftp.example.com: /upload/passwords",
    "Exit code 0",
    "Queued copy",
    "tar -czf out.tgz --exclude=build src",
    "Failed: The server rejected the user name or password.",
    "ls -u /tmp",
    "Copied, but could not delete /Users/me/a b.txt: permission denied",
    "feat: it's done",
  ])
  func leavesOrdinaryLogLinesAlone(line: String) {
    #expect(LogRedactor.redact(line) == line)
  }

  @Test func keepsWhatSurroundsTheSecret() {
    #expect(
      LogRedactor.redact("tool --password abc --verbose")
        == "tool --password \(LogRedactor.mask) --verbose")
    #expect(
      LogRedactor.redact("https://me:abc@host/path?page=2")
        == "https://\(LogRedactor.mask)@host/path?page=2")
    #expect(LogRedactor.redact("x?token=abc&page=2") == "x?token=\(LogRedactor.mask)&page=2")
  }

  @Test func hidingPersonalPathsReplacesHomeFolders() {
    #expect(
      LogRedactor.hidingPersonalPaths("a\t/Users/me/Docs/x.txt, /Users/other\t/tmp/y")
        == "a\t~/Docs/x.txt, ~\t/tmp/y")
  }

  @MainActor @Test func theQueueNeverStoresASecretAndCanHidePathsOnExport() throws {
    let queue = TransferQueue()
    let id = queue.submit(
      kind: .tool, sourceLabels: ["https://me:hunter2secret@host/a"],
      destinationLabel: "/Users/me/out?token=hunter2secret"
    ) { _ in TransferSummary() }
    queue.log(id, "$ curl -u me:hunter2secret /Users/me/a.txt")

    let exported = queue.exportedLogs
    #expect(!exported.contains(secret))
    #expect(queue.logs.allSatisfy { !$0.text.contains(secret) })
    #expect(exported.contains("/Users/me/a.txt"))

    let hidden = queue.exportedLogs(hidingPersonalPaths: true)
    #expect(!hidden.contains("/Users/me"))
    #expect(hidden.contains("~/a.txt"))
  }
}
