import FileTermCore
import Foundation
import Observation

enum StandardDestination: String, CaseIterable {
  case documents = "Documents"
  case desktop = "Desktop"
  case downloads = "Downloads"
  case home = "Home"
  case library = "Library"
  case applications = "Applications"
  case utilities = "Utilities"

  var commandID: String { "go.\(rawValue.lowercased())" }
  func url() throws -> URL {
    if self == .home { return FileManager.default.homeDirectoryForCurrentUser }
    let directory: FileManager.SearchPathDirectory
    switch self {
    case .documents: directory = .documentDirectory
    case .desktop: directory = .desktopDirectory
    case .downloads: directory = .downloadsDirectory
    case .library: directory = .libraryDirectory
    case .applications: directory = .applicationDirectory
    case .utilities: directory = .applicationDirectory
    case .home: return FileManager.default.homeDirectoryForCurrentUser
    }
    let domain: FileManager.SearchPathDomainMask =
      self == .applications || self == .utilities ? .localDomainMask : .userDomainMask
    let url = try FileManager.default.url(
      for: directory, in: domain, appropriateFor: nil, create: false)
    return self == .utilities ? url.appendingPathComponent("Utilities", isDirectory: true) : url
  }
}

@MainActor @Observable final class GoToFolderModel {
  var path: String
  private(set) var errorMessage: String?
  private(set) var isSubmitting = false
  private let browser: BrowserModel
  private let provider: LocalFileSystemProvider
  private let paneID: PaneID
  private var cancelled = false

  init(browser: BrowserModel, provider: LocalFileSystemProvider, paneID: PaneID) {
    self.browser = browser
    self.provider = provider
    self.paneID = paneID
    path = browser.pane(paneID).location?.path ?? "/"
  }

  func cancel() { cancelled = true }

  func submit() async -> Bool {
    guard !isSubmitting, !cancelled else { return false }
    isSubmitting = true
    errorMessage = nil
    defer { isSubmitting = false }
    do {
      let destination = try await provider.resolveFolderPath(path)
      guard !cancelled else { return false }
      if await browser.navigate(to: destination, in: paneID) { return true }
      errorMessage = browser.pane(paneID).errorMessage ?? "The folder could not be opened."
    } catch { errorMessage = error.localizedDescription }
    return false
  }
}
