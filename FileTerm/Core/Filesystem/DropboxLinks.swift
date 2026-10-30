import Foundation

public enum DropboxLinkError: Error, Equatable, LocalizedError {
  case invalidToken
  case api(String)

  public var errorDescription: String? {
    switch self {
    case .invalidToken:
      "Dropbox rejected the access token. Enter a new one in Settings › Integrations."
    case .api(let summary): "Dropbox could not create the link: \(summary)"
    }
  }
}

/// Finds Dropbox folders on this Mac and talks to the Dropbox sharing API.
public enum DropboxLinks {
  private static let endpoint = URL(
    string: "https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings")!

  /// Folder paths from the desktop app's `~/.dropbox/info.json`.
  public static func roots(infoJSON: Data) -> [String] {
    guard let info = try? JSONSerialization.jsonObject(with: infoJSON) as? [String: Any] else {
      return []
    }
    return ["personal", "business"].compactMap {
      (info[$0] as? [String: Any])?["path"] as? String
    }
  }

  /// Every Dropbox folder the desktop app has set up for the current user.
  public static func installedRoots(home: String = NSHomeDirectory()) -> [String] {
    let info = (try? Data(contentsOf: URL(fileURLWithPath: home + "/.dropbox/info.json")))
      .map(roots(infoJSON:)) ?? []
    let cloudStorage = home + "/Library/CloudStorage"
    let providers = ((try? FileManager.default.contentsOfDirectory(atPath: cloudStorage)) ?? [])
      .filter { $0 == "Dropbox" || $0.hasPrefix("Dropbox-") }
      .map { cloudStorage + "/" + $0 }
    return Array(Set(info + providers)).sorted()
  }

  /// The path Dropbox uses for a local item, or nil when it is outside `roots`. A root itself
  /// cannot be shared, so it also gives nil.
  public static func remotePath(of path: String, roots: [String]) -> String? {
    let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    for root in roots {
      let base = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
      if resolved.hasPrefix(base + "/") { return String(resolved.dropFirst(base.count)) }
    }
    return nil
  }

  public static func request(remotePath: String, token: String) throws -> URLRequest {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["path": remotePath])
    return request
  }

  /// The link from a response. An item that is already shared comes back as a 409 holding its
  /// existing link.
  public static func link(status: Int, body: Data) throws -> String {
    if status == 401 { throw DropboxLinkError.invalidToken }
    let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    if status == 200, let url = json?["url"] as? String { return url }
    let error = json?["error"] as? [String: Any]
    let existing = error?["shared_link_already_exists"] as? [String: Any]
    if let url = (existing?["metadata"] as? [String: Any])?["url"] as? String { return url }
    throw DropboxLinkError.api(json?["error_summary"] as? String ?? "HTTP \(status)")
  }
}
