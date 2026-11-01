import Foundation

/// A read-only view of an archive's contents as folders (Settings › Treat archives as folders).
/// The listing comes from one `bsdtar -tv` run; a file's bytes are extracted on demand.
public actor ArchiveProvider: FileSystemProvider {
  public nonisolated let id: String
  /// The local archive file.
  public nonisolated let archive: URL
  /// A folder this provider owns and deletes on `close()`, for archives downloaded from a server.
  public nonisolated let temporaryFolder: URL?

  struct Node: Sendable {
    var kind: FileEntry.Kind
    var size: Int64?
    var modifiedAt: Date?
    var permissions: Int?
  }

  private var nodes: [String: Node] = ["/": Node(kind: .directory)]
  private var children: [String: Set<String>] = [:]
  private var loaded = false

  public init(archive: URL, temporaryFolder: URL? = nil) {
    self.id = "archive:" + UUID().uuidString
    self.archive = archive
    self.temporaryFolder = temporaryFolder
  }

  /// Reads the archive's table of contents. Call once before listing.
  public func load() async throws {
    guard !loaded else { return }
    let output = try await ProcessRunner.run(
      ArchiveTool.bsdtar, ["-tvf", archive.path],
      environment: ["LC_ALL": "en_US.UTF-8"])
    let now = Date()
    for line in String(decoding: output, as: UTF8.self).split(separator: "\n") {
      guard let item = Self.parse(String(line), now: now) else { continue }
      add(item.path, node: item.node)
    }
    loaded = true
  }

  public func close() {
    if let temporaryFolder { try? FileManager.default.removeItem(at: temporaryFolder) }
  }

  public func list(_ location: Location) async throws -> [FileEntry] {
    try await list(location, includeHidden: true)
  }

  public func list(_ location: Location, includeHidden: Bool) async throws -> [FileEntry] {
    let path = Self.normalize(location.path)
    guard nodes[path]?.kind == .directory else { throw FileSystemError.notFound }
    return (children[path] ?? []).sorted().compactMap { child in
      let entry = entry(for: child)
      return includeHidden || !entry.isHidden ? entry : nil
    }
  }

  public func stat(_ location: Location) async throws -> FileEntry {
    let path = Self.normalize(location.path)
    guard nodes[path] != nil else { throw FileSystemError.notFound }
    return entry(for: path)
  }

  /// Extracts the member to a temporary folder and streams it; the folder goes away at the end.
  public func read(_ location: Location) async throws -> any FileByteReader {
    let path = Self.normalize(location.path)
    guard let node = nodes[path] else { throw FileSystemError.notFound }
    guard node.kind == .file else { throw FileSystemError.unsupportedOperation }
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("FileTerm-archive-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    do {
      let member = String(path.dropFirst())
      try await ProcessRunner.run(
        ArchiveTool.bsdtar,
        [
          "-xf", archive.path, "-C", folder.path,
          ArchiveTool.nameArgument(Self.escapePattern(member)),
        ],
        environment: ["LC_ALL": "en_US.UTF-8"])
      let file = folder.appendingPathComponent(member)
      return try ExtractedFileReader(file: file, folder: folder)
    } catch {
      try? FileManager.default.removeItem(at: folder)
      throw error
    }
  }

  public func write(_ contents: any FileByteReader, to location: Location) async throws {
    throw FileSystemError.unsupportedOperation
  }
  public func move(_ source: Location, to destination: Location) async throws {
    throw FileSystemError.unsupportedOperation
  }
  public func delete(_ location: Location) async throws {
    throw FileSystemError.unsupportedOperation
  }

  // MARK: Tree

  private func add(_ path: String, node: Node) {
    nodes[path] = node
    var current = path
    while current != "/" {
      let parent = Self.parent(of: current)
      children[parent, default: []].insert(current)
      // Folders the archive never lists on their own still need to exist.
      if nodes[parent] == nil { nodes[parent] = Node(kind: .directory) }
      current = parent
    }
  }

  private func entry(for path: String) -> FileEntry {
    let node = nodes[path] ?? Node(kind: .directory)
    let name = path == "/" ? "/" : (path as NSString).lastPathComponent
    return FileEntry(
      location: Location(providerID: id, path: path), name: name, kind: node.kind,
      size: node.kind == .file ? node.size : nil, modifiedAt: node.modifiedAt,
      permissions: node.permissions, isHidden: name.hasPrefix("."))
  }

  // MARK: Parsing

  static func normalize(_ path: String) -> String {
    var parts = path.split(separator: "/").map(String.init)
    parts.removeAll { $0 == "." }
    return "/" + parts.joined(separator: "/")
  }

  static func parent(of path: String) -> String {
    let parent = (path as NSString).deletingLastPathComponent
    return parent.isEmpty ? "/" : parent
  }

  /// bsdtar treats member arguments as shell-style patterns; escape them to match literally.
  static func escapePattern(_ name: String) -> String {
    var result = ""
    for character in name {
      if "\\*?[]".contains(character) { result.append("\\") }
      result.append(character)
    }
    return result
  }

  private static let line = try! NSRegularExpression(
    pattern:
      #"^(\S{10})\s+\d+\s+\S+\s+\S+\s+(\d+)\s+([A-Z][a-z]{2})\s+(\d{1,2})\s+(\d{2}:\d{2}|\d{4})\s(.+)$"#
  )

  static func parse(_ text: String, now: Date) -> (path: String, node: Node)? {
    let range = NSRange(text.startIndex..., in: text)
    guard let match = line.firstMatch(in: text, range: range) else { return nil }
    func group(_ index: Int) -> String {
      Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
    }
    let mode = group(1)
    var name = group(6)
    let kind: FileEntry.Kind
    switch mode.first {
    case "d": kind = .directory
    case "-": kind = .file
    case "l":
      kind = .symbolicLink
      if let arrow = name.range(of: " -> ") { name = String(name[..<arrow.lowerBound]) }
    default: kind = .other
    }
    if name.hasSuffix("/") { name.removeLast() }
    let path = normalize(name)
    // Finder-made zips carry resource-fork copies that are not part of what the user sees.
    if path == "/" || path.hasPrefix("/__MACOSX/") || path == "/__MACOSX"
      || (path as NSString).lastPathComponent.hasPrefix("._")
    {
      return nil
    }
    if path.split(separator: "/").contains("..") { return nil }
    return (
      path,
      Node(
        kind: kind, size: Int64(group(2)),
        modifiedAt: date(month: group(3), day: group(4), when: group(5), now: now),
        permissions: permissions(mode))
    )
  }

  private static func permissions(_ mode: String) -> Int? {
    let bits = Array(mode.dropFirst())
    guard bits.count == 9 else { return nil }
    var value = 0
    for (index, bit) in bits.enumerated() where bit != "-" && bit != "S" && bit != "T" {
      value |= 1 << (8 - index)
    }
    return value
  }

  private static func date(month: String, day: String, when: String, now: Date) -> Date? {
    var parts = DateComponents()
    let calendar = Calendar(identifier: .gregorian)
    guard
      let monthIndex = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct",
        "Nov", "Dec",
      ].firstIndex(of: month), let dayNumber = Int(day)
    else { return nil }
    parts.month = monthIndex + 1
    parts.day = dayNumber
    if when.contains(":") {
      // Recent entries show a time instead of a year: assume the latest year not in the future.
      let clock = when.split(separator: ":").compactMap { Int($0) }
      guard clock.count == 2 else { return nil }
      parts.hour = clock[0]
      parts.minute = clock[1]
      parts.year = calendar.component(.year, from: now)
      if let candidate = calendar.date(from: parts), candidate > now.addingTimeInterval(86_400) {
        parts.year = (parts.year ?? 0) - 1
      }
    } else {
      parts.year = Int(when)
    }
    return calendar.date(from: parts)
  }
}

/// Streams an extracted file, then removes the folder it was extracted into.
private final class ExtractedFileReader: FileByteReader, @unchecked Sendable {
  private let lock = NSLock()
  private let handle: FileHandle
  private let folder: URL
  private var finished = false

  init(file: URL, folder: URL) throws {
    // A member that is a link could point outside the extraction folder.
    guard
      (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    else { throw FileSystemError.notFound }
    handle = try FileHandle(forReadingFrom: file)
    self.folder = folder
  }

  deinit { finish() }

  func next() async throws -> Data? {
    try Task.checkCancellation()
    return readChunk()
  }

  private func readChunk() -> Data? {
    lock.lock()
    defer { lock.unlock() }
    guard !finished else { return nil }
    let data = try? handle.read(upToCount: 64 * 1024)
    if let data, !data.isEmpty { return data }
    closeLocked()
    return nil
  }

  private func finish() {
    lock.lock()
    defer { lock.unlock() }
    closeLocked()
  }

  private func closeLocked() {
    guard !finished else { return }
    finished = true
    try? handle.close()
    try? FileManager.default.removeItem(at: folder)
  }
}
