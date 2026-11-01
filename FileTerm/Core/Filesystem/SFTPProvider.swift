import Foundation

public enum SFTPError: Error, Equatable, LocalizedError, Sendable {
  case sshMissing
  case unknownHostKey(host: String, port: Int)
  case hostKeyChanged(host: String)
  case hostNotFound(String)
  case cannotConnect(host: String, port: Int)
  case loginDenied
  case timeout
  case noSFTP
  case connectionLost
  case protocolError(String)

  public var errorDescription: String? {
    switch self {
    case .sshMissing: "SFTP needs /usr/bin/ssh, which was not found on this Mac."
    case .unknownHostKey(let host, _): "The identity of “\(host)” has not been confirmed yet."
    case .hostKeyChanged(let host):
      "The host key of “\(host)” has changed. Someone may be intercepting the connection. "
        + "If the server was reinstalled, remove its old line from ~/.ssh/known_hosts or "
        + "FileTerm’s known_hosts file and connect again."
    case .hostNotFound(let host): "The server “\(host)” could not be found."
    case .cannotConnect(let host, let port):
      "Could not connect to \(host) on port \(port). Check the address and port."
    case .loginDenied:
      "The server rejected the sign-in. Check the user name, password or private key."
    case .timeout: "The server did not answer in time."
    case .noSFTP: "The server does not offer SFTP for this account."
    case .connectionLost: "The connection to the server was lost."
    case .protocolError(let message): message
    }
  }
}

/// Browses an SFTP server through the system `ssh`: one long-lived `ssh -s sftp` process per
/// connection, speaking SFTP version 3 on its pipes (`SFTPPacket`). ssh does the transport, key
/// and agent handling and reads `~/.ssh/config`.
///
/// `Location.path` is an absolute path on the server.
public actor SFTPProvider: ValidatingProvider {
  public nonisolated let id: String
  private let target: SSHTarget
  private let secret: String?
  private let knownHosts: URL
  private let ssh: URL

  private var encoding: String
  private var session: SFTPSession?
  private var isReady = false
  private var decoder = SFTPFrameDecoder()
  private var connecting: Task<SFTPSession, any Error>?
  private var pending: [UInt32: CheckedContinuation<SFTPReply, any Error>] = [:]
  private var nextID: UInt32 = 1

  /// The size of one read or write request. 32 KiB is accepted by every server.
  static let chunkSize = 32 * 1024

  public init(
    id: String, target: SSHTarget, password: String?,
    textEncoding: String = "UTF-8",
    knownHosts: URL = HostKeyStore.defaultFileURL, ssh: URL = SSHCommand.executable
  ) {
    self.id = id
    encoding = textEncoding
    self.target = target
    secret = password.flatMap { $0.isEmpty ? nil : $0 }
    self.knownHosts = knownHosts
    self.ssh = ssh
    // A write to ssh after it exited must fail with an error, not kill the app.
    signal(SIGPIPE, SIG_IGN)
  }

  deinit { session?.terminate() }

  /// Names on this server are read and sent in the given encoding from now on.
  public func setTextEncoding(_ name: String) { encoding = name }

  /// Ends the ssh process. Later calls connect again.
  public func close() {
    session?.terminate()
  }

  // MARK: ValidatingProvider

  public func resolveRoot(_ requested: String) async throws -> String {
    let trimmed = requested.trimmingCharacters(in: .whitespacesAndNewlines)
    let reply = try await send {
      SFTPPacket.path(.realpath, id: $0, trimmed.isEmpty ? "." : trimmed, encoding: encoding)
    }
    guard case .names(let names) = reply, let first = names.first else {
      try requireOK(reply)
      throw SFTPError.protocolError("The server could not resolve the folder.")
    }
    return first.filename
  }

  public func validate(root: String = "/") async throws {
    let entry = try await stat(Location(providerID: id, path: root))
    guard entry.kind == .directory else {
      throw FileSystemError.io("“\(root)” is not a folder.")
    }
    _ = try await list(entry.location, includeHidden: true)
  }

  // MARK: FileSystemProvider

  public func list(_ location: Location) async throws -> [FileEntry] {
    try await list(location, includeHidden: false)
  }

  public func list(_ location: Location, includeHidden: Bool) async throws -> [FileEntry] {
    let folder = Location(providerID: id, path: Self.normalized(location.path))
    let handle = try await openHandle(.opendir, folder.path)
    var names: [SFTPNameEntry] = []
    do {
      readLoop: while true {
        let reply = try await send { SFTPPacket.handle(.readdir, id: $0, handle) }
        switch reply {
        case .names(let batch): names += batch
        case .status(let code, _) where code == SFTPStatusCode.eof.rawValue: break readLoop
        default:
          try requireOK(reply)
          throw SFTPError.protocolError("Unexpected reply from the server.")
        }
      }
    } catch {
      await closeHandle(handle)
      throw error
    }
    await closeHandle(handle)
    var entries: [FileEntry] = []
    for name in names where FileName.isListable(name.filename) {
      let location = ProviderTransfer.child(folder, name.filename)
      var attributes = name.attributes
      if attributes.isSymbolicLink,
        let target = try? await attributesOf(location.path, follow: true)
      {
        // A link to a folder or file behaves like what it points to; a broken link stays a link.
        attributes = target
      }
      entries.append(Self.entry(attributes, name: name.filename, at: location))
    }
    return entries.filter { includeHidden || !$0.isHidden }
  }

  public func stat(_ location: Location) async throws -> FileEntry {
    let path = Self.normalized(location.path)
    let attributes: SFTPAttributes
    do {
      attributes = try await attributesOf(path, follow: true)
    } catch FileSystemError.notFound {
      // A broken link has no target to describe, but it is still an item.
      attributes = try await attributesOf(path, follow: false)
    }
    return Self.entry(
      attributes, name: path == "/" ? "/" : (path as NSString).lastPathComponent,
      at: Location(providerID: id, path: path))
  }

  public func read(_ location: Location) async throws -> any FileByteReader {
    let handle = try await openHandle(.open, Self.normalized(location.path), flags: .read)
    return SFTPByteReader(provider: self, handle: handle)
  }

  /// Opens with CREAT|EXCL, so an existing destination is refused by the server itself.
  public func write(_ contents: any FileByteReader, to location: Location) async throws {
    let path = Self.normalized(location.path)
    let handle: Data
    do {
      handle = try await openHandle(.open, path, flags: [.write, .create, .exclusive])
    } catch FileSystemError.io(let message) {
      // OpenSSH reports an existing file as a plain failure.
      if (try? await attributesOf(path, follow: false)) != nil {
        throw FileSystemError.destinationExists
      }
      throw FileSystemError.io(message)
    }
    var offset: UInt64 = 0
    do {
      while let chunk = try await contents.next() {
        var start = chunk.startIndex
        while start < chunk.endIndex {
          let end = min(start + Self.chunkSize, chunk.endIndex)
          let piece = chunk[start..<end]
          try Task.checkCancellation()
          let at = offset
          try requireOK(
            await send { SFTPPacket.write(id: $0, handle: handle, offset: at, data: Data(piece)) })
          offset += UInt64(piece.count)
          start = end
        }
      }
      try requireOK(await send { SFTPPacket.handle(.close, id: $0, handle) })
    } catch {
      // Leave no half-written file behind; the file was created by this call.
      await closeHandle(handle)
      _ = try? await send(cancellable: false) {
        SFTPPacket.path(.remove, id: $0, path, encoding: encoding)
      }
      throw error
    }
  }

  public func move(_ source: Location, to destination: Location) async throws {
    let target = Self.normalized(destination.path)
    if (try? await attributesOf(target, follow: false)) != nil {
      throw FileSystemError.destinationExists
    }
    let from = Self.normalized(source.path)
    try requireOK(
      await send { SFTPPacket.rename(id: $0, from: from, to: target, encoding: encoding) })
  }

  public func createDirectory(_ location: Location) async throws {
    let path = Self.normalized(location.path)
    if (try? await attributesOf(path, follow: false)) != nil {
      throw FileSystemError.destinationExists
    }
    try requireOK(await send { SFTPPacket.makeDirectory(id: $0, path: path, encoding: encoding) })
  }

  public func delete(_ location: Location) async throws {
    let path = Self.normalized(location.path)
    guard path != "/" else { throw FileSystemError.unsupportedOperation }
    // Not following links: deleting a link to a folder removes the link, never the folder's files.
    let attributes = try await attributesOf(path, follow: false)
    guard attributes.isDirectory else {
      try requireOK(await send { SFTPPacket.path(.remove, id: $0, path, encoding: encoding) })
      return
    }
    for child in try await list(Location(providerID: id, path: path), includeHidden: true) {
      try await delete(child.location)
    }
    try requireOK(await send { SFTPPacket.path(.rmdir, id: $0, path, encoding: encoding) })
  }

  // MARK: Requests

  private func attributesOf(_ path: String, follow: Bool) async throws -> SFTPAttributes {
    let reply = try await send {
      SFTPPacket.path(follow ? .stat : .lstat, id: $0, path, encoding: encoding)
    }
    guard case .attributes(let attributes) = reply else {
      try requireOK(reply)
      throw SFTPError.protocolError("Unexpected reply from the server.")
    }
    return attributes
  }

  private func openHandle(_ type: SFTPPacketType, _ path: String, flags: SFTPOpenFlags = [])
    async throws -> Data
  {
    let reply = try await send {
      type == .open
        ? SFTPPacket.open(id: $0, path: path, flags: flags, encoding: encoding)
        : SFTPPacket.path(type, id: $0, path, encoding: encoding)
    }
    guard case .handle(let handle) = reply else {
      try requireOK(reply)
      throw SFTPError.protocolError("Unexpected reply from the server.")
    }
    return handle
  }

  func closeHandle(_ handle: Data) async {
    _ = try? await send(cancellable: false) { SFTPPacket.handle(.close, id: $0, handle) }
  }

  /// The next chunk of an open file, or nil at its end.
  func readChunk(_ handle: Data, offset: UInt64) async throws -> Data? {
    let reply = try await send {
      SFTPPacket.read(id: $0, handle: handle, offset: offset, length: UInt32(Self.chunkSize))
    }
    switch reply {
    case .data(let data): return data.isEmpty ? nil : data
    case .status(let code, _) where code == SFTPStatusCode.eof.rawValue: return nil
    default:
      try requireOK(reply)
      throw SFTPError.protocolError("Unexpected reply from the server.")
    }
  }

  private func requireOK(_ reply: SFTPReply) throws {
    guard case .status(let code, let message) = reply else {
      throw SFTPError.protocolError("Unexpected reply from the server.")
    }
    if let error = SFTPPacket.error(code: code, message: message) { throw error }
  }

  /// Sends one request and waits for its reply. Cancellation is checked before sending, so
  /// cleanup requests can still run for a cancelled task.
  private func send(cancellable: Bool = true, _ build: (UInt32) -> Data) async throws -> SFTPReply {
    if cancellable { try Task.checkCancellation() }
    let session = try await ensureSession()
    let id = nextID
    nextID = nextID == UInt32.max ? 1 : nextID + 1
    let packet = build(id)
    return try await withCheckedThrowingContinuation { continuation in
      guard self.session === session else {
        continuation.resume(throwing: SFTPError.connectionLost)
        return
      }
      pending[id] = continuation
      session.send(packet) { [weak self] in
        Task { await self?.fail(id, SFTPError.connectionLost) }
      }
    }
  }

  private func fail(_ id: UInt32, _ error: any Error) {
    pending.removeValue(forKey: id)?.resume(throwing: error)
  }

  // MARK: Session

  private func ensureSession() async throws -> SFTPSession {
    if let session, isReady { return session }
    if let connecting { return try await connecting.value }
    let task = Task { try await self.openSession() }
    connecting = task
    do {
      let opened = try await task.value
      connecting = nil
      return opened
    } catch {
      connecting = nil
      throw error
    }
  }

  private func openSession() async throws -> SFTPSession {
    guard FileManager.default.isExecutableFile(atPath: ssh.path) else { throw SFTPError.sshMissing }
    let askpass = try secret.map { try SSHAskpass(secret: $0) }
    let arguments = SSHCommand.sftpArguments(
      target: target, knownHosts: knownHosts, hasSecret: askpass != nil)
    let environment = ProcessInfo.processInfo.environment.merging(askpass?.environment ?? [:]) {
      $1
    }
    let opened = SFTPSession(
      executable: ssh, arguments: arguments, environment: environment, askpass: askpass)
    try opened.start()
    session = opened
    isReady = false
    decoder = SFTPFrameDecoder()
    Task.detached { [weak self] in
      while let chunk = await opened.readChunk() {
        guard let provider = self else { return }
        await provider.receive(chunk, from: opened)
      }
      await self?.sessionEnded(opened)
    }
    let version = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<SFTPReply, any Error>) in
      pending[0] = continuation
      opened.send(SFTPPacket.initialize()) { [weak self] in
        Task { await self?.fail(0, SFTPError.connectionLost) }
      }
    }
    guard case .version = version else { throw SFTPError.protocolError("The server is not SFTP.") }
    isReady = true
    // Signed in: the password file is no longer needed.
    askpass?.remove()
    return opened
  }

  private func receive(_ chunk: Data, from sender: SFTPSession) {
    guard session === sender else { return }
    decoder.append(chunk)
    do {
      while let payload = try decoder.next() {
        let (id, reply) = try SFTPPacket.decode(payload, encoding: encoding)
        pending.removeValue(forKey: id ?? 0)?.resume(returning: reply)
      }
    } catch {
      sender.terminate()
    }
  }

  private func sessionEnded(_ ended: SFTPSession) async {
    let status = await ended.waitForExit()
    let errors = await ended.collectErrors()
    guard session === ended else { return }
    session = nil
    let wasReady = isReady
    isReady = false
    let error: any Error =
      wasReady
      ? SFTPError.connectionLost : Self.startupError(stderr: errors, status: status, target: target)
    let waiting = pending
    pending = [:]
    for continuation in waiting.values { continuation.resume(throwing: error) }
  }

  // MARK: Pure helpers (unit-tested)

  static func normalized(_ path: String) -> String {
    let parts = path.split(separator: "/", omittingEmptySubsequences: true)
    return "/" + parts.joined(separator: "/")
  }

  static func entry(_ attributes: SFTPAttributes, name: String, at location: Location) -> FileEntry
  {
    let kind: FileEntry.Kind =
      attributes.isDirectory
      ? .directory
      : attributes.isSymbolicLink
        ? .symbolicLink : attributes.permissions == nil || attributes.isRegularFile ? .file : .other
    return FileEntry(
      location: location, name: name, kind: kind, size: kind == .file ? attributes.size : nil,
      modifiedAt: attributes.modifyTime.map { Date(timeIntervalSince1970: TimeInterval($0)) },
      owner: attributes.uid.map(String.init), group: attributes.gid.map(String.init),
      permissions: attributes.permissions.map { Int($0 & 0o7777) },
      isHidden: name.hasPrefix("."))
  }

  /// Turns what ssh printed before it gave up into an error the user can act on.
  static func startupError(stderr: String, status: Int32, target: SSHTarget) -> any Error {
    let port = target.port ?? 22
    func has(_ text: String) -> Bool { stderr.localizedCaseInsensitiveContains(text) }
    if has("REMOTE HOST IDENTIFICATION HAS CHANGED") || has("has changed and you have requested") {
      return SFTPError.hostKeyChanged(host: target.host)
    }
    if has("Host key verification failed") || has("host key is known") {
      return SFTPError.unknownHostKey(host: target.host, port: port)
    }
    if has("Permission denied") || has("Too many authentication failures") {
      return SFTPError.loginDenied
    }
    if has("Could not resolve hostname") { return SFTPError.hostNotFound(target.host) }
    if has("timed out") { return SFTPError.timeout }
    if has("Connection refused") || has("No route to host") || has("Network is unreachable") {
      return SFTPError.cannotConnect(host: target.host, port: port)
    }
    if has("subsystem request failed") { return SFTPError.noSFTP }
    let line = stderr.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    return FileSystemError.io(line ?? "ssh stopped with status \(status).")
  }
}

/// One `ssh -s sftp` process and its pipes.
final class SFTPSession: @unchecked Sendable {
  private let process = Process()
  private let input = Pipe()
  private let output = Pipe()
  private let errors = Pipe()
  private let writeQueue = DispatchQueue(label: "fileterm.sftp.write")
  private let readQueue = DispatchQueue(label: "fileterm.sftp.read")
  private let errorQueue = DispatchQueue(label: "fileterm.sftp.errors")
  private let errorsDone = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var errorText = ""
  private let askpass: SSHAskpass?

  init(
    executable: URL, arguments: [String], environment: [String: String], askpass: SSHAskpass?
  ) {
    self.askpass = askpass
    process.executableURL = executable
    process.arguments = arguments
    process.environment = environment
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
  }

  deinit {
    terminate()
    askpass?.remove()
  }

  func start() throws {
    try process.run()
    // The parent must not hold the child's ends open, or reads never see end of file.
    try? input.fileHandleForReading.close()
    try? output.fileHandleForWriting.close()
    try? errors.fileHandleForWriting.close()
    let handle = errors.fileHandleForReading
    errorQueue.async { [self] in
      let data = (try? handle.readToEnd()) ?? Data()
      lock.withLock { errorText = String(decoding: data.prefix(64 * 1024), as: UTF8.self) }
      errorsDone.signal()
    }
  }

  func terminate() {
    if process.isRunning { process.terminate() }
  }

  /// Writes in order on a background queue. `onFailure` runs if the pipe is closed.
  func send(_ data: Data, onFailure: @escaping @Sendable () -> Void) {
    let handle = input.fileHandleForWriting
    writeQueue.async {
      do { try handle.write(contentsOf: data) } catch { onFailure() }
    }
  }

  /// The next bytes ssh wrote, or nil once it closed its output.
  func readChunk() async -> Data? {
    let handle = output.fileHandleForReading
    return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
      readQueue.async {
        // availableData returns what one read delivers; read(upToCount:) would wait for a full
        // buffer, and SFTP replies are small.
        let data = handle.availableData
        continuation.resume(returning: data.isEmpty ? nil : data)
      }
    }
  }

  func waitForExit() async -> Int32 {
    await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
      DispatchQueue.global().async { [process] in
        process.waitUntilExit()
        continuation.resume(returning: process.terminationStatus)
      }
    }
  }

  /// Everything ssh printed to standard error. Call once, after the process ended.
  func collectErrors() async -> String {
    await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
      errorQueue.async { [self] in
        errorsDone.wait()
        continuation.resume(returning: lock.withLock { errorText })
      }
    }
  }
}

/// Pulls a download from the server one request at a time.
private final class SFTPByteReader: FileByteReader, @unchecked Sendable {
  private let provider: SFTPProvider
  private let handle: Data
  private var offset: UInt64 = 0
  private var finished = false

  init(provider: SFTPProvider, handle: Data) {
    self.provider = provider
    self.handle = handle
  }

  deinit {
    guard !finished else { return }
    let provider = provider
    let handle = handle
    Task { await provider.closeHandle(handle) }
  }

  func next() async throws -> Data? {
    guard !finished else { return nil }
    do {
      if let chunk = try await provider.readChunk(handle, offset: offset) {
        offset += UInt64(chunk.count)
        return chunk
      }
    } catch {
      finished = true
      await provider.closeHandle(handle)
      throw error
    }
    finished = true
    await provider.closeHandle(handle)
    return nil
  }
}
