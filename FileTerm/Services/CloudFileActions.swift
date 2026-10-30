import AppKit
import FileTermCore
import Observation

/// iCloud Drive and Dropbox commands for local items, shared by the menus and context menus.
@MainActor @Observable final class CloudFileActions {
  enum DropboxLinkState: Equatable {
    case ready(remotePath: String)
    case unavailable(String)
    case outsideDropbox
  }

  /// Keychain account for the Dropbox access token.
  private static let tokenID = UUID(uuidString: "6D1F1D7E-3B7C-4C55-9A5E-0D2C6A4B9E11")!

  @ObservationIgnored private let credentials: any CredentialStore
  @ObservationIgnored private let roots: () -> [String]
  @ObservationIgnored private let send: (URLRequest) async throws -> (Data, URLResponse)
  /// Shows a message in the front browser window.
  @ObservationIgnored var onNotice: (String) -> Void = { _ in }
  private(set) var hasDropboxToken: Bool

  init(
    credentials: any CredentialStore = KeychainCredentialStore(service: "com.fileterm.dropbox"),
    roots: @escaping () -> [String] = { DropboxLinks.installedRoots() },
    send: @escaping (URLRequest) async throws -> (Data, URLResponse) = {
      try await URLSession.shared.data(for: $0)
    }
  ) {
    self.credentials = credentials
    self.roots = roots
    self.send = send
    hasDropboxToken = credentials.password(for: Self.tokenID) != nil
  }

  func setDropboxToken(_ token: String) throws {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      credentials.deletePassword(for: Self.tokenID)
    } else {
      try credentials.setPassword(trimmed, for: Self.tokenID)
    }
    hasDropboxToken = !trimmed.isEmpty
  }

  func dropboxLinkState(_ path: String) -> DropboxLinkState {
    let roots = roots()
    if roots.isEmpty { return .unavailable("Dropbox is not set up on this Mac.") }
    guard let remotePath = DropboxLinks.remotePath(of: path, roots: roots) else {
      return .outsideDropbox
    }
    return hasDropboxToken
      ? .ready(remotePath: remotePath)
      : .unavailable("Add a Dropbox access token in Settings › Integrations.")
  }

  func copyDropboxLink(_ path: String) async {
    guard case .ready(let remotePath) = dropboxLinkState(path),
      let token = credentials.password(for: Self.tokenID)
    else { return }
    do {
      let request = try DropboxLinks.request(remotePath: remotePath, token: token)
      let (body, response) = try await send(request)
      let link = try DropboxLinks.link(
        status: (response as? HTTPURLResponse)?.statusCode ?? 0, body: body)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(link, forType: .string)
      onNotice("Dropbox link copied.")
    } catch {
      onNotice(error.localizedDescription)
    }
  }

  func downloadNow(_ paths: [String]) {
    do {
      for path in paths { try ICloudFiles.download(URL(fileURLWithPath: path)) }
      onNotice("Downloading from iCloud Drive.")
    } catch {
      onNotice(error.localizedDescription)
    }
  }

  /// Asks first, because the local copies disappear even though the files stay in iCloud.
  func removeDownload(_ paths: [String]) {
    let alert = NSAlert()
    alert.messageText =
      paths.count == 1
      ? "Remove the download of “\((paths[0] as NSString).lastPathComponent)”?"
      : "Remove the downloads of \(paths.count) items?"
    alert.informativeText =
      "This removes only the copy on this Mac. The file stays in iCloud Drive and is not deleted. "
      + "You can download it again at any time."
    alert.addButton(withTitle: "Remove Download")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    Task {
      do {
        try await Task.detached {
          for path in paths { try ICloudFiles.removeDownload(URL(fileURLWithPath: path)) }
        }.value
        onNotice("Download removed. The file is still in iCloud Drive.")
      } catch {
        onNotice(error.localizedDescription)
      }
    }
  }
}
