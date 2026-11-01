import Foundation

public enum ArchiveToolError: Error, LocalizedError, Equatable {
  case empty(String)

  public var errorDescription: String? {
    switch self {
    case .empty(let name): return "“\(name)” has nothing to extract."
    }
  }
}

/// Creates and unpacks archives with the system `ditto` and `bsdtar`.
public enum ArchiveTool {
  static let ditto = "/usr/bin/ditto"
  static let bsdtar = "/usr/bin/bsdtar"

  /// bsdtar reads a leading `-` as an option (some run programs) and `@` as an archive to include.
  /// A `./` prefix makes either one a plain name.
  static func nameArgument(_ name: String) -> String {
    name.hasPrefix("-") || name.hasPrefix("@") ? "./" + name : name
  }

  /// `directory/stem.ext`, or `directory/stem 2.ext`, `stem 3.ext` … when taken.
  public static func uniqueURL(in directory: URL, stem: String, ext: String = "") -> URL {
    let suffix = ext.isEmpty ? "" : "." + ext
    var candidate = directory.appendingPathComponent(stem + suffix)
    var index = 2
    while exists(candidate) {
      candidate = directory.appendingPathComponent("\(stem) \(index)\(suffix)")
      index += 1
    }
    return candidate
  }

  /// The name a new archive gets by default: the item's own name, or `Archive` for several.
  public static func defaultStem(for sources: [URL]) -> String {
    sources.count == 1 ? sources[0].lastPathComponent : "Archive"
  }

  /// Writes `destination`, which must not exist. A failed or cancelled run leaves nothing behind.
  public static func compress(sources: [URL], format: ArchiveFormat, destination: URL) async throws
  {
    guard !sources.isEmpty else { return }
    do {
      // ditto's --keepParent stores a file's parent folder, so it only suits a single folder.
      if format == .zip, sources.count == 1,
        (try? sources[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      {
        try await ProcessRunner.run(
          ditto, ["-c", "-k", "--sequesterRsrc", "--keepParent", sources[0].path, destination.path])
      } else {
        var arguments = ["--no-mac-metadata"]
        switch format {
        case .zip: arguments += ["--format", "zip", "-cf", destination.path]
        case .tar: arguments += ["-cf", destination.path]
        case .tarGz: arguments += ["-czf", destination.path]
        case .tarBz2: arguments += ["-cjf", destination.path]
        case .tarXz: arguments += ["-cJf", destination.path]
        }
        for source in sources {
          arguments += [
            "-C", source.deletingLastPathComponent().path,
            nameArgument(source.lastPathComponent),
          ]
        }
        try await ProcessRunner.run(bsdtar, arguments)
      }
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
  }

  /// Unpacks into a hidden staging folder first, so nothing existing is overwritten, then moves
  /// the result into `directory`. One top-level item lands as itself; several (or `newFolder`)
  /// go into a new folder named after the archive. Returns the created top-level URLs.
  public static func extract(archive: URL, into directory: URL, newFolder: Bool = false)
    async throws -> [URL]
  {
    let fm = FileManager.default
    let staging = directory.appendingPathComponent(".FileTerm-extract-\(UUID().uuidString)")
    try fm.createDirectory(at: staging, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: staging) }
    try await ProcessRunner.run(bsdtar, ["-xf", archive.path, "-C", staging.path])
    let items = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
    guard !items.isEmpty else { throw ArchiveToolError.empty(archive.lastPathComponent) }
    if newFolder || items.count > 1 {
      let folder = uniqueURL(
        in: directory, stem: ArchiveFormat.stem(of: archive.lastPathComponent))
      try fm.createDirectory(at: folder, withIntermediateDirectories: false)
      for item in items {
        try fm.moveItem(at: item, to: folder.appendingPathComponent(item.lastPathComponent))
      }
      return [folder]
    }
    let item = items[0]
    let ext = item.pathExtension
    let stem = ext.isEmpty ? item.lastPathComponent : item.deletingPathExtension().lastPathComponent
    let target = uniqueURL(in: directory, stem: stem, ext: ext)
    try fm.moveItem(at: item, to: target)
    return [target]
  }

  private static func exists(_ url: URL) -> Bool {
    (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
  }
}
