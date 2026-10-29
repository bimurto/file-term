import Foundation

/// Formats FileTerm can create. Extraction also reads `.7z` and `.rar` through bsdtar.
public enum ArchiveFormat: String, CaseIterable, Sendable, Identifiable {
  case zip, tar, tarGz, tarBz2, tarXz

  public var id: String { rawValue }

  public var fileExtension: String {
    switch self {
    case .zip: "zip"
    case .tar: "tar"
    case .tarGz: "tar.gz"
    case .tarBz2: "tar.bz2"
    case .tarXz: "tar.xz"
    }
  }

  public var title: String {
    switch self {
    case .zip: "Zip (.zip)"
    case .tar: "Tar (.tar)"
    case .tarGz: "Gzip tar (.tar.gz)"
    case .tarBz2: "Bzip2 tar (.tar.bz2)"
    case .tarXz: "XZ tar (.tar.xz)"
    }
  }

  private static let extractOnly = ["7z", "rar"]
  private static let aliases = ["tgz", "tbz2", "tbz", "txz"]

  /// True for names bsdtar can unpack, ignoring case.
  public static func isArchive(name: String) -> Bool {
    let lower = name.lowercased()
    if lower.hasPrefix(".") && !lower.dropFirst().contains(".") { return false }
    let candidates = allCases.map(\.fileExtension) + extractOnly + aliases
    return candidates.contains { lower.hasSuffix("." + $0) && lower.count > $0.count + 1 }
  }

  /// The name without its archive extension, e.g. `photos.tar.gz` → `photos`.
  public static func stem(of name: String) -> String {
    let lower = name.lowercased()
    let candidates = (allCases.map(\.fileExtension) + extractOnly + aliases)
      .sorted { $0.count > $1.count }
    for ext in candidates where lower.hasSuffix("." + ext) && lower.count > ext.count + 1 {
      return String(name.dropLast(ext.count + 1))
    }
    return (name as NSString).deletingPathExtension
  }
}
