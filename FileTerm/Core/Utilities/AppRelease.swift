import Foundation

/// The latest published release, as the GitHub releases API returns it.
public struct AppRelease: Decodable, Equatable, Sendable {
  public let tag: String
  public let page: URL

  enum CodingKeys: String, CodingKey {
    case tag = "tag_name"
    case page = "html_url"
  }

  public init(tag: String, page: URL) {
    self.tag = tag
    self.page = page
  }

  /// The tag without a leading "v".
  public var version: String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }

  public func isNewer(than current: String) -> Bool {
    version.compare(current, options: .numeric) == .orderedDescending
  }
}
