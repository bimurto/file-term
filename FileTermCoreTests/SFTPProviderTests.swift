import Foundation
import Testing

@testable import FileTermCore

/// Serves the real filesystem through macOS's own `sftp-server`, started by a stand-in for ssh,
/// so the provider's requests run against a genuine SFTP implementation without a network.
@Suite(.serialized) struct SFTPProviderTests {
  private let target = SSHTarget(host: "stand-in")

  private struct Chunks: FileByteReader {
    private let box: Box
    final class Box: @unchecked Sendable {
      var chunks: [Data]
      init(chunks: [Data]) { self.chunks = chunks }
    }
    init(_ chunks: [Data]) { box = Box(chunks: chunks) }
    func next() async throws -> Data? { box.chunks.isEmpty ? nil : box.chunks.removeFirst() }
  }

  private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "fileterm-sftp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
  }

  private func fakeSSH(in folder: URL, script: String) throws -> URL {
    let url = folder.appendingPathComponent("fake-ssh")
    try "#!/bin/sh\n\(script)\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
  }

  private func provider(in folder: URL, script: String = "exec /usr/libexec/sftp-server")
    throws -> SFTPProvider
  {
    SFTPProvider(
      id: "sftp", target: target, password: nil,
      knownHosts: folder.appendingPathComponent("known_hosts"),
      ssh: try fakeSSH(in: folder, script: script))
  }

  private func location(_ url: URL) -> Location { Location(providerID: "sftp", path: url.path) }

  private func bytes(_ reader: any FileByteReader) async throws -> Data {
    var all = Data()
    while let chunk = try await reader.next() { all.append(chunk) }
    return all
  }

  @Test func listsKindsSizesHiddenItemsAndFollowsLinks() async throws {
    let folder = try scratch()
    let work = folder.appendingPathComponent("work")
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(
      at: work.appendingPathComponent("sub"), withIntermediateDirectories: true)
    try Data("hello".utf8).write(to: work.appendingPathComponent("a.txt"))
    try Data().write(to: work.appendingPathComponent(".hidden"))
    try FileManager.default.createSymbolicLink(
      at: work.appendingPathComponent("link"),
      withDestinationURL: work.appendingPathComponent("sub"))
    try FileManager.default.createSymbolicLink(
      atPath: work.appendingPathComponent("broken").path, withDestinationPath: "/nowhere/at/all")
    let sftp = try provider(in: folder)

    let visible = try await sftp.list(location(work)).sorted { $0.name < $1.name }
    #expect(visible.map(\.name) == ["a.txt", "broken", "link", "sub"])
    let byName = Dictionary(uniqueKeysWithValues: visible.map { ($0.name, $0) })
    #expect(byName["a.txt"]?.kind == .file && byName["a.txt"]?.size == 5)
    #expect(byName["sub"]?.kind == .directory && byName["link"]?.kind == .directory)
    #expect(byName["broken"]?.kind == .symbolicLink)
    #expect(byName["a.txt"]?.location.path == work.appendingPathComponent("a.txt").path)
    #expect(byName["a.txt"]?.permissions == 0o644 || byName["a.txt"]?.permissions == 0o600)

    let all = try await sftp.list(location(work), includeHidden: true)
    #expect(all.contains { $0.name == ".hidden" && $0.isHidden })
  }

  @Test func writesAndReadsMoreThanOneChunkAndRefusesOverwrite() async throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sftp = try provider(in: folder)
    let payload = Data((0..<(SFTPProvider.chunkSize * 3 + 123)).map { UInt8($0 % 251) })
    let destination = location(folder.appendingPathComponent("big.bin"))

    try await sftp.write(
      Chunks([payload.prefix(70_000), payload.dropFirst(70_000)]), to: destination)
    #expect(try Data(contentsOf: folder.appendingPathComponent("big.bin")) == payload)
    #expect(try await bytes(try await sftp.read(destination)) == payload)
    #expect(try await sftp.stat(destination).size == Int64(payload.count))

    await #expect(throws: FileSystemError.destinationExists) {
      try await sftp.write(Chunks([Data("x".utf8)]), to: destination)
    }
    #expect(try Data(contentsOf: folder.appendingPathComponent("big.bin")) == payload)
  }

  @Test func failedWriteLeavesNoPartialFile() async throws {
    struct Broken: FileByteReader {
      let box = Chunks.Box(chunks: [Data("part".utf8)])
      func next() async throws -> Data? {
        if let first = box.chunks.first {
          box.chunks.removeFirst()
          return first
        }
        throw FileSystemError.io("source failed")
      }
    }
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sftp = try provider(in: folder)
    await #expect(throws: FileSystemError.io("source failed")) {
      try await sftp.write(Broken(), to: self.location(folder.appendingPathComponent("p.bin")))
    }
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("p.bin").path))
  }

  @Test func replacingKeepsPermissionsAndSavingThroughALinkKeepsTheLink() async throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sftp = try provider(in: folder)
    let fm = FileManager.default
    let script = folder.appendingPathComponent("run.sh")
    try Data("old".utf8).write(to: script)
    try fm.setAttributes([.posixPermissions: 0o750], ofItemAtPath: script.path)
    let link = folder.appendingPathComponent("link.sh")
    try fm.createSymbolicLink(at: link, withDestinationURL: script)
    let local = folder.appendingPathComponent("new.sh")
    try Data("new".utf8).write(to: local)
    let localProvider = LocalFileSystemProvider()

    // Remote Edit saves through the link to its target.
    let target = try await sftp.resolvedTarget(of: location(link))
    #expect((target.path as NSString).lastPathComponent == "run.sh")
    let transfer = ProviderTransfer(
      registry: ProviderRegistry(providers: [sftp, localProvider]), control: TransferControl(),
      resolve: { _ in ConflictResolution(decision: .replace) })
    _ = try await transfer.copy(
      sources: [localProvider.location(for: local)],
      to: Location(providerID: "sftp", path: (target.path as NSString).deletingLastPathComponent),
      newName: (target.path as NSString).lastPathComponent)

    #expect(try String(contentsOf: script, encoding: .utf8) == "new")
    #expect(
      try fm.attributesOfItem(atPath: script.path)[.posixPermissions] as? Int == 0o750)
    #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == script.path)
    #expect(
      try fm.contentsOfDirectory(atPath: folder.path).sorted().filter {
        $0.hasSuffix(".old") || $0.hasSuffix(".part")
      } == [])
  }

  @Test func movesCreatesAndDeletes() async throws {
    let folder = try scratch()
    let outside = try scratch()
    defer {
      try? FileManager.default.removeItem(at: folder)
      try? FileManager.default.removeItem(at: outside)
    }
    let sftp = try provider(in: folder)
    let tree = folder.appendingPathComponent("tree")
    try await sftp.createDirectory(location(tree))
    await #expect(throws: FileSystemError.destinationExists) {
      try await sftp.createDirectory(self.location(tree))
    }
    try await sftp.createDirectory(location(tree.appendingPathComponent("inner")))
    try await sftp.write(
      Chunks([Data("1".utf8)]), to: location(tree.appendingPathComponent("inner/one.txt")))
    try await sftp.write(
      Chunks([Data("2".utf8)]), to: location(tree.appendingPathComponent("two.txt")))
    try Data("keep".utf8).write(to: outside.appendingPathComponent("keep.txt"))
    try FileManager.default.createSymbolicLink(
      at: tree.appendingPathComponent("escape"), withDestinationURL: outside)

    try await sftp.move(
      location(tree.appendingPathComponent("two.txt")),
      to: location(tree.appendingPathComponent("three.txt")))
    #expect(FileManager.default.fileExists(atPath: tree.appendingPathComponent("three.txt").path))
    await #expect(throws: FileSystemError.destinationExists) {
      try await sftp.move(
        self.location(tree.appendingPathComponent("three.txt")),
        to: self.location(tree.appendingPathComponent("inner")))
    }

    try await sftp.delete(location(tree))
    #expect(!FileManager.default.fileExists(atPath: tree.path))
    // The link was removed; the folder it pointed to was left alone.
    #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("keep.txt").path))
    await #expect(throws: FileSystemError.unsupportedOperation) {
      try await sftp.delete(Location(providerID: "sftp", path: "/"))
    }
  }

  @Test func missingItemsAreNotFound() async throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sftp = try provider(in: folder)
    let missing = location(folder.appendingPathComponent("nope"))
    await #expect(throws: FileSystemError.notFound) { try await sftp.stat(missing) }
    await #expect(throws: FileSystemError.notFound) { try await sftp.list(missing) }
    await #expect(throws: FileSystemError.notFound) { _ = try await sftp.read(missing) }
  }

  @Test func resolvesAndValidatesTheRootFolder() async throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sftp = try provider(in: folder)
    // The server resolves links; its working folder (a login's home folder) is the empty path.
    func real(_ path: String) -> String { String(cString: realpath(path, nil)) }
    #expect(try await sftp.resolveRoot(folder.path) == real(folder.path))
    #expect(try await sftp.resolveRoot("") == real(FileManager.default.currentDirectoryPath))
    try await sftp.validate(root: folder.path)
    try Data("x".utf8).write(to: folder.appendingPathComponent("file"))
    await #expect(throws: FileSystemError.self) {
      try await sftp.validate(root: folder.appendingPathComponent("file").path)
    }
    await #expect(throws: FileSystemError.notFound) {
      try await sftp.validate(root: folder.appendingPathComponent("gone").path)
    }
  }

  @Test func concurrentFirstRequestsShareOneConnection() async throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let marker = folder.appendingPathComponent("starts")
    let sftp = try provider(
      in: folder, script: "echo started >> '\(marker.path)'\nexec /usr/libexec/sftp-server")
    try await withThrowingTaskGroup(of: Int.self) { group in
      for _ in 0..<6 { group.addTask { try await sftp.list(self.location(folder)).count } }
      for try await _ in group {}
    }
    let starts = try String(contentsOf: marker, encoding: .utf8).split(separator: "\n")
    #expect(starts.count == 1)
  }

  @Test func reconnectsAfterTheConnectionDrops() async throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sftp = try provider(in: folder)
    _ = try await sftp.list(location(folder))
    await sftp.close()
    try await Task.sleep(for: .milliseconds(300))
    #expect(try await sftp.list(location(folder)).isEmpty == false)  // the fake-ssh script is there
  }

  @Test func reportsSigninFailureFromSSH() async throws {
    let folder = try scratch()
    defer { try? FileManager.default.removeItem(at: folder) }
    let sftp = try provider(
      in: folder, script: "echo 'tester@stand-in: Permission denied (publickey).' >&2\nexit 255")
    await #expect(throws: SFTPError.loginDenied) { try await sftp.list(self.location(folder)) }
  }

  @Test func reportsAMissingSSH() async {
    let sftp = SFTPProvider(
      id: "sftp", target: target, password: nil, ssh: URL(fileURLWithPath: "/nonexistent/ssh"))
    await #expect(throws: SFTPError.sshMissing) {
      try await sftp.list(Location(providerID: "sftp", path: "/"))
    }
  }

  @Test func mapsSSHStartupMessages() {
    let target = SSHTarget(host: "box", port: 2222)
    func error(_ text: String, status: Int32 = 255) -> SFTPError? {
      SFTPProvider.startupError(stderr: text, status: status, target: target) as? SFTPError
    }
    #expect(
      error(
        "No ED25519 host key is known for [box]:2222 and you have requested strict checking.\r\nHost key verification failed.\r\n"
      )
        == .unknownHostKey(host: "box", port: 2222))
    #expect(
      error(
        "@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @\nHost key verification failed."
      )
        == .hostKeyChanged(host: "box"))
    #expect(error("u@box: Permission denied (publickey,password).") == .loginDenied)
    #expect(
      error("ssh: Could not resolve hostname box: nodename nor servname") == .hostNotFound("box"))
    #expect(
      error("ssh: connect to host box port 2222: Connection refused")
        == .cannotConnect(host: "box", port: 2222))
    #expect(error("ssh: connect to host box port 2222: Operation timed out") == .timeout)
    #expect(error("Subsystem request failed on channel 0") == .noSFTP)
    #expect(
      SFTPProvider.startupError(
        stderr: "\n  Load key \"/k\": bad format \n", status: 255, target: target)
        as? FileSystemError == .io("Load key \"/k\": bad format"))
    #expect(
      SFTPProvider.startupError(stderr: "", status: 7, target: target) as? FileSystemError
        == .io("ssh stopped with status 7."))
  }

  @Test func normalizesPaths() {
    #expect(SFTPProvider.normalized("/a//b/") == "/a/b")
    #expect(SFTPProvider.normalized("") == "/")
    #expect(SFTPProvider.normalized("a/b") == "/a/b")
  }
}
