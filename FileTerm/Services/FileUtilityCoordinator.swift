import AppKit
import FileTermCore
import Observation
import SwiftUI

/// Owns utility windows independently of whichever pane becomes active later.
@MainActor @Observable final class FileUtilityCoordinator {
  @ObservationIgnored private var windows: [UUID: FileUtilityWindowController] = [:]
  var refresh: (() async -> Void)?

  func showChecksum(_ pane: PaneModel, window: NSWindow? = nil) {
    let files = pane.selectedEntries.filter {
      $0.location.providerID == "local" && $0.kind == .file
    }
    guard files.count == 1, pane.selectedEntries.count == 1, let entry = files.first else {
      showMessage("Select one local regular file to calculate its checksum.", window: window)
      return
    }
    showChecksum(URL(fileURLWithPath: entry.location.path))
  }

  func showChecksum(_ url: URL) {
    guard url.isFileURL else { return }
    let model = ChecksumUtilityModel(url: url)
    let id = UUID()
    let controller = FileUtilityWindowController(title: "File Checksum")
    controller.window?.contentView = NSHostingView(
      rootView: ChecksumUtilityView(model: model) { [weak controller] in controller?.close() })
    retain(controller, id: id) { model.cancel() }
    model.calculate()
  }

  func calculateFolderSizes(_ pane: PaneModel) {
    calculateAllFolderSizes(pane)
  }

  func calculateAllFolderSizes(_ pane: PaneModel, window: NSWindow? = nil) {
    let folders = pane.visibleEntries.filter {
      $0.kind == .directory && $0.location.providerID == "local"
    }
    guard !folders.isEmpty else {
      showMessage("There are no local folders in the visible listing to calculate.", window: window)
      return
    }
    let model = FolderSizesUtilityModel(pane: pane, folders: folders)
    let id = UUID()
    let controller = FileUtilityWindowController(title: "Calculate All Folder Sizes")
    controller.window?.contentView = NSHostingView(
      rootView: FolderSizesUtilityView(model: model) { [weak controller] in controller?.close() })
    retain(controller, id: id) { model.cancel() }
    model.start()
  }

  /// Creates uniquely named links beside each selected local item. The service never overwrites.
  func createLink(_ pane: PaneModel, kind: LocalLinkKind, window: NSWindow? = nil) {
    let sources = pane.selectedEntries.filter { $0.location.providerID == "local" }
      .map { URL(fileURLWithPath: $0.location.path) }
    guard !sources.isEmpty else { return }
    let revision = pane.navigationRevision
    Task { [weak self, weak pane, weak window] in
      guard let self else { return }
      let service = LocalLinkService()
      var failures: [String] = []
      for source in sources {
        do {
          switch kind {
          case .alias: _ = try await service.createAlias(source: source)
          case .symlink: _ = try await service.createSymlink(source: source)
          }
        } catch {
          failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
        }
      }
      if let refresh = self.refresh {
        await refresh()
      } else if let pane, pane.navigationRevision == revision {
        await pane.refresh()
      }
      if !failures.isEmpty {
        self.showMessage(failures.joined(separator: "\n"), window: window)
      }
    }
  }

  private func retain(
    _ controller: FileUtilityWindowController, id: UUID, onClose: @escaping @MainActor () -> Void
  ) {
    windows[id] = controller
    controller.onClose = { [weak self] in
      onClose()
      self?.windows[id] = nil
    }
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
  }

  private func showMessage(_ message: String, window: NSWindow?) {
    let alert = NSAlert()
    alert.messageText = message
    if let window, window.isVisible {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }
}

@MainActor private final class FileUtilityWindowController: NSWindowController, NSWindowDelegate {
  var onClose: (@MainActor () -> Void)?

  init(title: String) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = title
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.delegate = self
    window.center()
  }

  required init?(coder: NSCoder) { nil }

  func windowWillClose(_ notification: Notification) { onClose?() }
}

@MainActor @Observable final class ChecksumUtilityModel {
  let url: URL
  var algorithm: ChecksumAlgorithm = .sha256
  var expectedDigest = ""
  private(set) var digest: String?
  private(set) var isRunning = false
  private(set) var fractionCompleted = 0.0
  private(set) var progressDescription = ""
  private(set) var message: String?
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var generation = UUID()

  init(url: URL) { self.url = url }

  private var normalizedExpected: String {
    expectedDigest.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  var checksumMatches: Bool { digest != nil && digest == normalizedExpected }
  var comparisonDescription: String? {
    guard digest != nil, !normalizedExpected.isEmpty else { return nil }
    return checksumMatches ? "Checksums match" : "Checksums do not match"
  }

  func clearResult() {
    guard !isRunning else { return }
    digest = nil
    message = nil
    fractionCompleted = 0
  }

  func calculate() {
    guard !isRunning else { return }
    clearResult()
    isRunning = true
    let token = UUID()
    generation = token
    let url = url
    let algorithm = algorithm
    task = Task { [weak self] in
      do {
        let result = try await FileChecksum.calculate(at: url, algorithm: algorithm) {
          [weak self] progress in
          await self?.update(progress, token: token)
        }
        try Task.checkCancellation()
        guard let self, self.generation == token else { return }
        self.digest = result
        self.fractionCompleted = 1
        self.message = "Checksum calculated."
        self.isRunning = false
        self.task = nil
      } catch {
        guard let self, self.generation == token else { return }
        self.message =
          error is CancellationError ? "Calculation cancelled." : error.localizedDescription
        self.isRunning = false
        self.task = nil
      }
    }
  }

  private func update(_ progress: ChecksumProgress, token: UUID) {
    guard generation == token, isRunning else { return }
    fractionCompleted =
      progress.totalBytes == 0
      ? 0 : min(1, Double(progress.bytesRead) / Double(progress.totalBytes))
    progressDescription =
      "\(progress.bytesRead.formatted()) of \(progress.totalBytes.formatted()) bytes read"
  }

  func cancel() {
    task?.cancel()
    generation = UUID()
    task = nil
    if isRunning { message = "Calculation cancelled." }
    isRunning = false
  }

  func copyDigest() {
    guard let digest else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(digest, forType: .string)
  }
}

@MainActor @Observable final class FolderSizesUtilityModel {
  let rootPath: String
  let totalCount: Int
  private(set) var completedCount = 0
  private(set) var currentName = ""
  private(set) var progressDescription = "Preparing…"
  private(set) var message: String?
  private(set) var failures: [String] = []
  private(set) var isRunning = false
  @ObservationIgnored private weak var pane: PaneModel?
  @ObservationIgnored private let revision: UUID
  @ObservationIgnored private let folders: [FileEntry]
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var generation = UUID()

  init(pane: PaneModel, folders: [FileEntry]) {
    self.pane = pane
    self.folders = folders
    revision = pane.navigationRevision
    rootPath = pane.location?.path ?? "Visible folders"
    totalCount = folders.count
  }

  func start() {
    guard !isRunning, completedCount == 0 else { return }
    isRunning = true
    let token = UUID()
    generation = token
    task = Task { [weak self] in
      guard let self else { return }
      defer {
        if self.generation == token {
          self.isRunning = false
          self.task = nil
        }
      }
      for folder in self.folders {
        guard self.isCurrent(token) else { return }
        self.currentName = folder.name
        do {
          let result = try await FolderSizeScanner.scan(
            at: URL(fileURLWithPath: folder.location.path)
          ) { [weak self] progress in
            await self?.update(progress, token: token)
          }
          try Task.checkCancellation()
          guard self.isCurrent(token), let pane = self.pane else { return }
          guard let bytes = Int64(exactly: result.logicalBytes) else {
            self.failures.append("\(folder.name): Size exceeds the supported range.")
            continue
          }
          pane.setCalculatedSize(bytes, for: folder.location)
          self.completedCount += 1
        } catch is CancellationError {
          return
        } catch {
          guard self.isCurrent(token) else { return }
          self.failures.append("\(folder.name): \(error.localizedDescription)")
        }
      }
      self.currentName = ""
      self.message =
        self.failures.isEmpty
        ? "All folder sizes calculated."
        : "Finished with \(self.failures.count) folder(s) unavailable."
    }
  }

  private func isCurrent(_ token: UUID) -> Bool {
    guard generation == token, !Task.isCancelled else { return false }
    guard let pane, pane.navigationRevision == revision else {
      message = "Stopped because the original pane navigated or refreshed."
      return false
    }
    return true
  }

  private func update(_ progress: FolderSizeProgress, token: UUID) {
    guard generation == token, isRunning else { return }
    guard let pane, pane.navigationRevision == revision else {
      cancel()
      message = "Stopped because the original pane navigated or refreshed."
      return
    }
    progressDescription =
      "\(progress.itemsVisited.formatted()) items visited · \(progress.logicalBytes.formatted()) bytes in current folder"
  }

  func cancel() {
    task?.cancel()
    generation = UUID()
    task = nil
    if isRunning { message = "Calculation cancelled. Completed folder sizes were kept." }
    isRunning = false
  }
}
