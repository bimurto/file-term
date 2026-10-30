import Foundation

public enum FTPError: Error, Equatable, LocalizedError, Sendable {
  case curlMissing
  case hostNotFound(String)
  case cannotConnect(host: String, port: Int)
  case loginDenied
  case certificate
  case tlsUnsupported
  case timeout
  case activeModeFailed
  case refused(String)

  public var errorDescription: String? {
    switch self {
    case .curlMissing: "FTP needs /usr/bin/curl, which was not found on this Mac."
    case .hostNotFound(let host): "The server “\(host)” could not be found."
    case .cannotConnect(let host, let port):
      "Could not connect to \(host) on port \(port). Check the address and port. "
        + "In passive mode the server’s data ports must also be reachable."
    case .loginDenied: "The server rejected the user name or password."
    case .certificate:
      "The server’s certificate is not trusted. For a server you know, turn on "
        + "Allow invalid certificate under Show Advanced."
    case .tlsUnsupported: "The server does not support TLS. Choose FTP instead of FTP-TLS."
    case .timeout: "The server did not answer in time."
    case .activeModeFailed:
      "Active mode failed: the server could not connect back to this Mac. "
        + "Use passive mode, or allow incoming connections."
    case .refused(let message): message
    }
  }
}

/// Browses an FTP or FTP-TLS server through the system `curl`. Network.framework cannot upgrade
/// an open connection to TLS (explicit FTP-TLS needs that) and curl already speaks passive,
/// active and both TLS modes. Every operation is one curl process with its own connection.
///
/// `Location.path` is relative to the login folder, written with a leading slash ("/" is the
/// folder the server opens after login).
public actor FTPProvider: ValidatingProvider {
  public nonisolated let id: String
  private let host: String
  private let port: Int?
  private let username: String?
  private let password: String?
  private let secure: Bool
  private let activeMode: Bool
  private let allowInvalidCertificate: Bool
  private let curl: URL
  private var encoding: String

  public init(
    id: String, host: String, port: Int? = nil, username: String?, password: String?,
    secure: Bool = false, activeMode: Bool = false, allowInvalidCertificate: Bool = false,
    textEncoding: String = "UTF-8", curl: URL = URL(fileURLWithPath: "/usr/bin/curl")
  ) {
    self.id = id
    encoding = textEncoding
    self.host = host
    self.port = port
    self.username = username
    self.password = password
    self.secure = secure
    self.activeMode = activeMode
    self.allowInvalidCertificate = allowInvalidCertificate
    self.curl = curl
    // A write to curl after it exited must fail with an error, not kill the app.
    signal(SIGPIPE, SIG_IGN)
  }

  /// Names on this server are read and sent in the given encoding from now on.
  public func setTextEncoding(_ name: String) { encoding = name }

  public func validate(root: String = "/") async throws {
    _ = try await list(Location(providerID: id, path: root), includeHidden: true)
  }

  // MARK: FileSystemProvider

  public func list(_ location: Location) async throws -> [FileEntry] {
    try await list(location, includeHidden: false)
  }

  public func list(_ location: Location, includeHidden: Bool) async throws -> [FileEntry] {
    let folder = Self.folderPath(location.path)
    let entries: [FileEntry]
    do {
      let data = try await collect(path: folder, options: ["-X", "MLSD"])
      entries = FTPListing.parseMLSD(
        TextEncoding.decodeName(data, using: encoding), in: location, providerID: id)
    } catch let error as CurlFailure where Self.listFallbackStatuses.contains(error.status) {
      let data = try await mapping { try await collect(path: folder, options: []) }
      entries = FTPListing.parseList(
        TextEncoding.decodeName(data, using: encoding), in: location, providerID: id)
    } catch let error as CurlFailure {
      throw error.mapped(host: host, port: port ?? defaultPort)
    }
    return entries.filter { includeHidden || !$0.isHidden }
  }

  public func stat(_ location: Location) async throws -> FileEntry {
    let path = Self.normalized(location.path)
    if path == "/" {
      return FileEntry(location: Location(providerID: id, path: "/"), name: "/", kind: .directory)
    }
    let parent = Location(providerID: id, path: ProviderTransfer.parentPath(path))
    let name = (path as NSString).lastPathComponent
    guard let entry = try await list(parent, includeHidden: true).first(where: { $0.name == name })
    else { throw FileSystemError.notFound }
    return entry
  }

  public func read(_ location: Location) async throws -> any FileByteReader {
    let run = try makeRun(path: Self.normalized(location.path), options: [])
    try run.start()
    return FTPByteReader(run: run, host: host, port: port ?? defaultPort)
  }

  /// Refuses to replace an existing file: FTP `STOR` overwrites silently, so the destination is
  /// checked first (another client could still create it in between).
  public func write(_ contents: any FileByteReader, to location: Location) async throws {
    if (try? await stat(location)) != nil { throw FileSystemError.destinationExists }
    let run = try makeRun(
      path: Self.normalized(location.path), options: ["--upload-file", "-"], feedsInput: true)
    try await withTaskCancellationHandler {
      try run.start()
      do {
        while let chunk = try await contents.next() {
          try Task.checkCancellation()
          try await run.write(chunk)
        }
      } catch {
        if error is CurlWriteFailure, !Task.isCancelled {
          // curl ended early; its own message says why.
          let result = await run.finish(readingOutput: true)
          throw CurlFailure(status: result.status, message: result.message)
            .mapped(host: host, port: port ?? defaultPort)
        }
        run.terminate()
        _ = await run.finish(readingOutput: true)
        if Task.isCancelled { throw CancellationError() }
        throw error
      }
      run.closeInput()
      let result = await run.finish(readingOutput: true)
      try check(result)
    } onCancel: {
      run.terminate()
    }
  }

  public func move(_ source: Location, to destination: Location) async throws {
    if (try? await stat(destination)) != nil { throw FileSystemError.destinationExists }
    _ = try await command(
      ["RNFR \(try Self.relative(source.path))", "RNTO \(try Self.relative(destination.path))"])
  }

  public func createDirectory(_ location: Location) async throws {
    if (try? await stat(location)) != nil { throw FileSystemError.destinationExists }
    _ = try await command(["MKD \(try Self.relative(location.path))"])
  }

  public func delete(_ location: Location) async throws {
    let path = Self.normalized(location.path)
    guard path != "/" else { throw FileSystemError.unsupportedOperation }
    let entry = try await stat(location)
    guard entry.kind == .directory else {
      _ = try await command(["DELE \(try Self.relative(path))"])
      return
    }
    for child in try await list(location, includeHidden: true) {
      try await delete(child.location)
    }
    _ = try await command(["RMD \(try Self.relative(path))"])
  }

  // MARK: Running curl

  private var defaultPort: Int { 21 }

  private func mapping<T: Sendable>(_ body: () async throws -> T) async throws -> T {
    do { return try await body() } catch let error as CurlFailure {
      throw error.mapped(host: host, port: port ?? defaultPort)
    }
  }

  /// Sends FTP commands on a connection that transfers nothing.
  private func command(_ commands: [String]) async throws -> Data {
    try await mapping { try await collect(path: "/", options: ["--head"], quotes: commands) }
  }

  private func collect(path: String, options: [String], quotes: [String] = []) async throws -> Data
  {
    let run = try makeRun(path: path, options: options, quotes: quotes)
    return try await withTaskCancellationHandler {
      try run.start()
      let result = await run.finish(readingOutput: true)
      if Task.isCancelled { throw CancellationError() }
      if result.status != 0 { throw CurlFailure(status: result.status, message: result.message) }
      return result.output
    } onCancel: {
      run.terminate()
    }
  }

  private func check(_ result: CurlResult) throws {
    if Task.isCancelled { throw CancellationError() }
    if result.status != 0 {
      throw CurlFailure(status: result.status, message: result.message)
        .mapped(host: host, port: port ?? defaultPort)
    }
  }

  func makeRun(
    path: String, options: [String], quotes: [String] = [], feedsInput: Bool = false
  ) throws -> CurlRun {
    guard FileManager.default.isExecutableFile(atPath: curl.path) else {
      throw FTPError.curlMissing
    }
    let configuration =
      Data(
        try Self.configuration(
          host: host, port: port, path: path, username: username, password: password,
          secure: secure, encoding: encoding
        ).utf8)
      + Self.quoteLines(quotes, encoding: encoding)
    let arguments =
      Self.arguments(
        secure: secure, activeMode: activeMode, allowInvalidCertificate: allowInvalidCertificate)
      + options
    return try CurlRun(
      executable: curl, arguments: arguments, configuration: configuration, feedsInput: feedsInput)
  }

  // MARK: Pure helpers (unit-tested)

  /// MLSD is missing or refused on some servers; those answer 500/502 to the command.
  static let listFallbackStatuses: Set<Int32> = [8, 19, 21]

  static func arguments(secure: Bool, activeMode: Bool, allowInvalidCertificate: Bool) -> [String] {
    var arguments = ["--silent", "--show-error", "--globoff", "--connect-timeout", "15"]
    if secure { arguments.append("--ssl-reqd") }
    if secure, allowInvalidCertificate { arguments.append("--insecure") }
    if activeMode { arguments += ["--ftp-port", "-"] }
    return arguments
  }

  /// The curl config text. The credentials live here, not in the arguments, so `ps` never shows
  /// them.
  static func configuration(
    host: String, port: Int?, path: String, username: String?, password: String?, secure: Bool,
    encoding: String = "UTF-8"
  ) throws -> String {
    for value in [host, path, username ?? "", password ?? ""]
    where value.contains("\n") || value.contains("\r") {
      throw FileSystemError.io("Names and credentials cannot contain line breaks.")
    }
    let scheme = secure && port == 990 ? "ftps" : "ftp"
    let location = url(scheme: scheme, host: host, port: port, path: path, encoding: encoding)
    var lines = ["url = \"\(quote(location))\""]
    if let username, !username.isEmpty {
      lines.append("user = \"\(quote(username + ":" + (password ?? "")))\"")
    }
    return lines.joined(separator: "\n") + "\n"
  }

  /// Each path part is percent-encoded from its bytes in the connection's text encoding.
  static func url(
    scheme: String, host: String, port: Int?, path: String, encoding: String = "UTF-8"
  ) -> String {
    let encoded = normalized(path).split(separator: "/", omittingEmptySubsequences: true)
      .map { part in
        TextEncoding.encodeName(String(part), using: encoding).map { byte in
          pathAllowed.contains(Unicode.Scalar(byte))
            ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte)
        }.joined()
      }
      .joined(separator: "/")
    let trailing = path.hasSuffix("/") && !encoded.isEmpty ? "/" : ""
    return "\(scheme)://\(host)\(port.map { ":\($0)" } ?? "")/\(encoded)\(trailing)"
  }

  private static let pathAllowed = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

  /// `quote = "-<command>"` config lines. The commands go in the config, not the arguments,
  /// because arguments can only carry UTF-8 and names may be in another encoding. Backslash and
  /// quote are escaped on the encoded bytes: in Shift_JIS 0x5C can be the second byte of a
  /// character, and curl would otherwise read it as an escape.
  static func quoteLines(_ commands: [String], encoding: String) -> Data {
    var lines = Data()
    for command in commands {
      lines.append(Data("quote = \"-".utf8))
      for byte in TextEncoding.encodeName(command, using: encoding) {
        if byte == 0x5C || byte == 0x22 { lines.append(0x5C) }
        lines.append(byte)
      }
      lines.append(Data("\"\n".utf8))
    }
    return lines
  }

  private static func quote(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
  }

  /// A listing needs the trailing slash so curl changes into the folder before listing.
  static func folderPath(_ path: String) -> String {
    let path = normalized(path)
    return path == "/" ? path : path + "/"
  }

  static func normalized(_ path: String) -> String {
    let trimmed = path.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    return "/" + trimmed
  }

  /// FTP commands take paths relative to the login folder.
  static func relative(_ path: String) throws -> String {
    guard !path.contains("\n"), !path.contains("\r") else {
      throw FileSystemError.io("Names cannot contain line breaks.")
    }
    return String(normalized(path).dropFirst())
  }
}

/// A failed curl run, before it is translated into an error the user can act on.
struct CurlFailure: Error {
  let status: Int32
  let message: String

  func mapped(host: String, port: Int) -> any Error {
    switch status {
    case 6: return FTPError.hostNotFound(host)
    case 7: return FTPError.cannotConnect(host: host, port: port)
    case 9, 78: return FileSystemError.notFound
    case 28: return FTPError.timeout
    case 30: return FTPError.activeModeFailed
    case 35, 51, 60, 83: return FTPError.certificate
    case 64: return FTPError.tlsUnsupported
    case 67: return FTPError.loginDenied
    case 21: return FTPError.refused("The server refused the command.")
    default:
      let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
      return FileSystemError.io(detail.isEmpty ? "FTP error \(status)." : detail)
    }
  }
}

private struct CurlWriteFailure: Error {}

struct CurlResult {
  let status: Int32
  let output: Data
  let message: String
}

/// One curl process. Cleans up its credentials file when it ends or is dropped.
final class CurlRun: @unchecked Sendable {
  private let process = Process()
  private let output = Pipe()
  private let errors = Pipe()
  private let input: Pipe?
  private let configurationURL: URL
  private let queue = DispatchQueue(label: "fileterm.ftp.io")
  private let exited = DispatchSemaphore(value: 0)

  init(executable: URL, arguments: [String], configuration: Data, feedsInput: Bool) throws {
    configurationURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("fileterm-ftp-\(UUID().uuidString).conf")
    guard
      FileManager.default.createFile(
        atPath: configurationURL.path, contents: configuration,
        attributes: [.posixPermissions: 0o600])
    else { throw FileSystemError.io("Could not prepare the FTP request.") }
    input = feedsInput ? Pipe() : nil
    process.executableURL = executable
    process.arguments = ["--config", configurationURL.path] + arguments
    process.standardOutput = output
    process.standardError = errors
    if let input {
      process.standardInput = input
    } else {
      process.standardInput = FileHandle.nullDevice
    }
  }

  deinit {
    terminate()
    try? FileManager.default.removeItem(at: configurationURL)
  }

  func start() throws {
    process.terminationHandler = { [exited] _ in exited.signal() }
    try process.run()
    // The parent must not hold the child's ends open, or reads never see end of file.
    try? output.fileHandleForWriting.close()
    try? errors.fileHandleForWriting.close()
    try? input?.fileHandleForReading.close()
  }

  func terminate() {
    if process.isRunning { process.terminate() }
  }

  func closeInput() { try? input?.fileHandleForWriting.close() }

  /// Writes without blocking a Swift concurrency thread; a closed pipe becomes an error.
  func write(_ data: Data) async throws {
    guard let handle = input?.fileHandleForWriting else { return }
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      queue.async {
        do {
          try handle.write(contentsOf: data)
          continuation.resume()
        } catch { continuation.resume(throwing: CurlWriteFailure()) }
      }
    }
  }

  func readChunk() async -> Data? {
    let handle = output.fileHandleForReading
    return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
      queue.async { continuation.resume(returning: try? handle.read(upToCount: 64 * 1024)) }
    }
  }

  /// Waits for the process to end. With `readingOutput` it also collects what curl printed.
  func finish(readingOutput: Bool) async -> CurlResult {
    let process = process
    let output = output
    let errors = errors
    return await withCheckedContinuation { (continuation: CheckedContinuation<CurlResult, Never>) in
      queue.async {
        let data =
          readingOutput ? ((try? output.fileHandleForReading.readToEnd()) ?? Data()) : Data()
        let message = (try? errors.fileHandleForReading.readToEnd()) ?? Data()
        self.exited.wait()
        try? FileManager.default.removeItem(at: self.configurationURL)
        continuation.resume(
          returning: CurlResult(
            status: process.terminationStatus, output: data,
            message: String(decoding: message, as: UTF8.self)))
      }
    }
  }
}

/// Pulls a download from curl's standard output, 64 KiB at a time.
private final class FTPByteReader: FileByteReader, @unchecked Sendable {
  private let run: CurlRun
  private let host: String
  private let port: Int
  private var finished = false

  init(run: CurlRun, host: String, port: Int) {
    self.run = run
    self.host = host
    self.port = port
  }

  deinit { run.terminate() }

  func next() async throws -> Data? {
    guard !finished else { return nil }
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      if let chunk = await run.readChunk(), !chunk.isEmpty { return chunk }
      finished = true
      let result = await run.finish(readingOutput: false)
      if Task.isCancelled { throw CancellationError() }
      if result.status != 0 {
        throw CurlFailure(status: result.status, message: result.message)
          .mapped(host: host, port: port)
      }
      return nil
    } onCancel: {
      run.terminate()
    }
  }
}
