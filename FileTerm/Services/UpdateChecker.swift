import AppKit
import FileTermCore

/// Looks up the latest GitHub release and offers its download page. It does not install anything.
@MainActor final class UpdateChecker {
  enum Outcome: Equatable {
    case upToDate
    case available(AppRelease)
    case noRelease
    case failed(String)
  }

  private static let latestRelease = URL(
    string: "https://api.github.com/repos/bimurto/file-term/releases/latest")!
  private let fetch: @Sendable (URL) async throws -> (Data, URLResponse)

  init(
    fetch: @escaping @Sendable (URL) async throws -> (Data, URLResponse) = {
      try await URLSession.shared.data(from: $0)
    }
  ) {
    self.fetch = fetch
  }

  static var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
  }

  func latest(current: String) async -> Outcome {
    do {
      let (data, response) = try await fetch(Self.latestRelease)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 200
      if status == 404 { return .noRelease }
      guard status == 200 else { return .failed("The update server returned \(status).") }
      let release = try JSONDecoder().decode(AppRelease.self, from: data)
      return release.isNewer(than: current) ? .available(release) : .upToDate
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  /// An automatic check stays quiet unless there is an update to offer.
  func check(reportsUpToDate: Bool) async {
    let current = Self.currentVersion
    let outcome = await latest(current: current)
    let alert = NSAlert()
    switch outcome {
    case .available(let release):
      alert.messageText = "FileTerm \(release.version) is available"
      alert.informativeText = "You have version \(current)."
      alert.addButton(withTitle: "Open Download Page")
      alert.addButton(withTitle: "Later")
      if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.page) }
      return
    case .upToDate:
      alert.messageText = "FileTerm is up to date"
      alert.informativeText = "You have version \(current), the latest release."
    case .noRelease:
      alert.messageText = "No release is published yet"
      alert.informativeText = "You have version \(current)."
    case .failed(let message):
      alert.messageText = "Could not check for updates"
      alert.informativeText = message
    }
    if reportsUpToDate { alert.runModal() }
  }
}
