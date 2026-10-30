import Foundation

/// Whether an item lives in iCloud, and whether its contents are on this Mac.
public enum ICloudFileState: Equatable, Sendable {
  case notInICloud, cloudOnly, downloaded

  public init(isUbiquitous: Bool, status: URLUbiquitousItemDownloadingStatus?) {
    if !isUbiquitous {
      self = .notInICloud
    } else {
      self = status == .notDownloaded ? .cloudOnly : .downloaded
    }
  }
}

public enum ICloudFiles {
  public static func state(of url: URL) -> ICloudFileState {
    let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
      .ubiquitousItemDownloadingStatus
    return ICloudFileState(
      isUbiquitous: FileManager.default.isUbiquitousItem(at: url), status: status)
  }

  /// Starts the download and returns; macOS finishes it in the background.
  public static func download(_ url: URL) throws {
    try FileManager().startDownloadingUbiquitousItem(at: url)
  }

  /// Deletes only the local copy. The file stays in iCloud and can be downloaded again.
  public static func removeDownload(_ url: URL) throws {
    try FileManager().evictUbiquitousItem(at: url)
  }
}
