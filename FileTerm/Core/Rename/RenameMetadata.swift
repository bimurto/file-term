import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A value the Add Metadata rename rule can insert.
public enum RenameMetadataField: String, Codable, CaseIterable, Sendable {
  case dateTaken, cameraModel, dimensions
  case title, artist, album, track
  case created, modified, size

  public var title: String {
    switch self {
    case .dateTaken: "EXIF Date Taken"
    case .cameraModel: "EXIF Camera"
    case .dimensions: "EXIF Dimensions"
    case .title: "ID3 Title"
    case .artist: "ID3 Artist"
    case .album: "ID3 Album"
    case .track: "ID3 Track"
    case .created: "File Created"
    case .modified: "File Modified"
    case .size: "File Size in Bytes"
    }
  }

  public var isDate: Bool { self == .dateTaken || self == .created || self == .modified }
}

/// What the files themselves say, as opposed to what the listing already knows.
public struct RenameEmbeddedMetadata: Hashable, Sendable {
  public var dateTaken: Date?
  public var text: [RenameMetadataField: String] = [:]
  public init() {}
}

public enum RenameMetadataReader {
  /// The same items with embedded metadata filled in. Only local files can be read, so folders and
  /// remote items stay as they are. A field a file doesn't have is left out.
  public static func enriched(_ items: [RenameItem]) async -> [RenameItem] {
    var result: [RenameItem] = []
    for item in items {
      guard item.location.providerID == "local", !item.isDirectory else {
        result.append(item)
        continue
      }
      var enriched = item
      enriched.embedded = await read(URL(fileURLWithPath: item.location.path))
      result.append(enriched)
    }
    return result
  }

  static func read(_ url: URL) async -> RenameEmbeddedMetadata {
    let type = UTType(filenameExtension: url.pathExtension)
    if type?.conforms(to: .image) == true { return readImage(url) }
    if type?.conforms(to: .audiovisualContent) == true { return await readMedia(url) }
    return RenameEmbeddedMetadata()
  }

  private static func readImage(_ url: URL) -> RenameEmbeddedMetadata {
    var metadata = RenameEmbeddedMetadata()
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return metadata }
    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
    let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
    if let taken = exif?[kCGImagePropertyExifDateTimeOriginal] as? String {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
      metadata.dateTaken = formatter.date(from: taken)
    }
    metadata.text[.cameraModel] = tiff?[kCGImagePropertyTIFFModel] as? String
    if let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    {
      metadata.text[.dimensions] = "\(width)x\(height)"
    }
    return metadata
  }

  private static func readMedia(_ url: URL) async -> RenameEmbeddedMetadata {
    var metadata = RenameEmbeddedMetadata()
    let asset = AVURLAsset(url: url)
    guard let items = try? await asset.load(.metadata) else { return metadata }
    let common = try? await asset.load(.commonMetadata)
    func text(_ key: AVMetadataKey) async -> String? {
      let matches = AVMetadataItem.metadataItems(
        from: common ?? [], withKey: key, keySpace: .common)
      guard let first = matches.first else { return nil }
      return try? await first.load(.stringValue)
    }
    metadata.text[.title] = await text(.commonKeyTitle)
    metadata.text[.artist] = await text(.commonKeyArtist)
    metadata.text[.album] = await text(.commonKeyAlbumName)
    let tracks = AVMetadataItem.metadataItems(
      from: items, filteredByIdentifier: .id3MetadataTrackNumber)
    if let track = tracks.first, let value = try? await track.load(.stringValue) {
      // ID3 stores "3/12" for track 3 of 12.
      metadata.text[.track] = value.split(separator: "/").first.map(String.init)
    }
    return metadata
  }
}
