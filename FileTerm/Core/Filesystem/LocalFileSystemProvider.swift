import CoreServices
import Darwin
import Foundation

public actor LocalFileSystemProvider: FileSystemProvider {
  public nonisolated let id = "local"
  private let manager = FileManager()
  private var ownerNames: [uid_t: String] = [:]
  private var groupNames: [gid_t: String] = [:]

  public init() {}

  public nonisolated func location(for url: URL) -> Location {
    Location(providerID: id, path: url.standardizedFileURL.path)
  }

  public nonisolated func url(for location: Location) throws -> URL {
    guard location.providerID == id, location.path.hasPrefix("/") else {
      throw FileSystemError.unsupportedOperation
    }
    return URL(fileURLWithPath: location.path)
  }

  public func resolveFolderPath(_ path: String) throws -> Location {
    guard path.hasPrefix("/") else {
      throw FileSystemError.io("Enter an absolute folder path beginning with /.")
    }
    do {
      let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
      guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
        throw FileSystemError.io("The path does not point to a folder.")
      }
      return location(for: url)
    } catch { throw Self.normalized(error) }
  }

  public func list(_ location: Location) throws -> [FileEntry] {
    try list(location, includeHidden: false)
  }

  public func list(_ location: Location, includeHidden: Bool) throws -> [FileEntry] {
    do {
      return try manager.contentsOfDirectory(
        at: url(for: location), includingPropertiesForKeys: Self.keys,
        options: includeHidden ? [] : [.skipsHiddenFiles]
      ).compactMap { url in
        do { return try entry(at: url) } catch CocoaError.fileReadNoSuchFile { return nil }
      }
    } catch { throw Self.normalized(error) }
  }

  public func stat(_ location: Location) throws -> FileEntry {
    do { return try entry(at: url(for: location)) } catch { throw Self.normalized(error) }
  }

  public func read(_ location: Location) throws -> any FileByteReader {
    do { return try LocalByteReader(url: url(for: location)) } catch {
      throw Self.normalized(error)
    }
  }

  public func write(_ contents: any FileByteReader, to location: Location) async throws {
    let destination = try url(for: location)
    // O_EXCL makes the no-overwrite guarantee atomic, including for symlinks.
    let descriptor = open(destination.path, O_WRONLY | O_CREAT | O_EXCL, 0o666)
    guard descriptor >= 0 else {
      throw Self.normalized(NSError(domain: NSPOSIXErrorDomain, code: Int(errno)))
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    do {
      while let chunk = try await contents.next() {
        try Task.checkCancellation()
        try handle.write(contentsOf: chunk)
      }
      try handle.close()
    } catch {
      try? handle.close()
      try? manager.removeItem(at: destination)
      throw Self.normalized(error)
    }
  }

  public func move(_ source: Location, to destination: Location) throws {
    do { try manager.moveItem(at: url(for: source), to: url(for: destination)) } catch {
      throw Self.normalized(error)
    }
  }

  public func createDirectory(_ location: Location) throws {
    do {
      try manager.createDirectory(
        at: url(for: location), withIntermediateDirectories: false)
    } catch { throw Self.normalized(error) }
  }

  public func delete(_ location: Location) throws {
    do { try manager.removeItem(at: url(for: location)) } catch { throw Self.normalized(error) }
  }

  private static let keys: [URLResourceKey] = [
    .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey,
    .creationDateKey, .contentModificationDateKey, .addedToDirectoryDateKey,
    .tagNamesKey, .typeIdentifierKey, .isHiddenKey,
  ]

  private func entry(at url: URL) throws -> FileEntry {
    let values = try url.resourceValues(forKeys: Set(Self.keys))
    let kind: FileEntry.Kind =
      values.isSymbolicLink == true
      ? .symbolicLink
      : values.isDirectory == true ? .directory : values.isRegularFile == true ? .file : .other
    var status = Darwin.stat()
    let hasStatus = lstat(url.path, &status) == 0
    let lastOpened = Self.lastOpened(url, kind: kind)
    return FileEntry(
      location: location(for: url), name: url.lastPathComponent, kind: kind,
      size: kind == .file ? values.fileSize.map(Int64.init) : nil,
      createdAt: values.creationDate, modifiedAt: values.contentModificationDate,
      typeIdentifier: values.typeIdentifier, addedAt: values.addedToDirectoryDate,
      openedAt: lastOpened, tags: values.tagNames ?? [],
      owner: hasStatus ? ownerName(status.st_uid) : nil,
      group: hasStatus ? groupName(status.st_gid) : nil,
      permissions: hasStatus ? Int(status.st_mode & 0o7777) : nil,
      isHidden: values.isHidden == true || url.lastPathComponent.hasPrefix(".")
    )
  }

  /// A folder usually has one owner and group, so each name is looked up once.
  private func ownerName(_ id: uid_t) -> String? {
    if let name = ownerNames[id] { return name }
    var entry = passwd()
    var result: UnsafeMutablePointer<passwd>?
    var buffer = [CChar](repeating: 0, count: 4096)
    guard getpwuid_r(id, &entry, &buffer, buffer.count, &result) == 0, result != nil else {
      return nil
    }
    let name = String(cString: entry.pw_name)
    ownerNames[id] = name
    return name
  }

  private func groupName(_ id: gid_t) -> String? {
    if let name = groupNames[id] { return name }
    var entry = Darwin.group()
    var result: UnsafeMutablePointer<Darwin.group>?
    var buffer = [CChar](repeating: 0, count: 4096)
    guard getgrgid_r(id, &entry, &buffer, buffer.count, &result) == 0, result != nil else {
      return nil
    }
    let name = String(cString: entry.gr_name)
    groupNames[id] = name
    return name
  }

  /// Files keep this date in an extended attribute, which is what Spotlight reports for them, and
  /// asking Spotlight per file makes a 100k folder take about 30 s to list. Apps and folders often
  /// have the date only in Spotlight, so they still ask it.
  private static func lastOpened(_ url: URL, kind: FileEntry.Kind) -> Date? {
    var time = timespec()
    let size = getxattr(
      url.path, "com.apple.lastuseddate#PS", &time, MemoryLayout<timespec>.size, 0, 0)
    if size == MemoryLayout<timespec>.size {
      return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1e9)
    }
    guard kind == .directory else { return nil }
    let metadata = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL)
    return metadata.flatMap { MDItemCopyAttribute($0, kMDItemLastUsedDate) as? Date }
  }

  static func normalized(_ error: any Error) -> any Error {
    if error is CancellationError { return error }
    if let error = error as? FileSystemError { return error }
    let nsError = error as NSError
    if nsError.domain == NSPOSIXErrorDomain {
      switch Int32(nsError.code) {
      case ENOENT: return FileSystemError.notFound
      // macOS privacy blocks fail with EPERM, and file modes with EACCES.
      case EACCES: return FileSystemError.fileModesDenied
      case EPERM: return FileSystemError.permissionDenied
      case EEXIST: return FileSystemError.destinationExists
      default: break
      }
    }
    if nsError.domain == NSCocoaErrorDomain {
      switch nsError.code {
      case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return FileSystemError.notFound
      case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        return underlying?.domain == NSPOSIXErrorDomain && underlying?.code == Int(EACCES)
          ? FileSystemError.fileModesDenied : FileSystemError.permissionDenied
      case NSFileWriteFileExistsError: return FileSystemError.destinationExists
      default: break
      }
    }
    return FileSystemError.io(error.localizedDescription)
  }
}

private actor LocalByteReader: FileByteReader {
  private let handle: FileHandle
  private var finished = false

  init(url: URL) throws { handle = try FileHandle(forReadingFrom: url) }

  func next() throws -> Data? {
    guard !finished else { return nil }
    do {
      try Task.checkCancellation()
      let data = try handle.read(upToCount: 64 * 1024)
      if let data, !data.isEmpty { return data }
      finished = true
      try handle.close()
      return nil
    } catch {
      finished = true
      try? handle.close()
      throw LocalFileSystemProvider.normalized(error)
    }
  }
}
