import AppKit
import FileTermCore

/// App-wide local history and clipboard, with each operation bound to its originating pane.
@MainActor final class FileOperationCoordinator {
  let operations = LocalFileOperations()
  private(set) var isBusy = false
  private(set) var canUndo = false
  private(set) var canRedo = false
  private(set) var undoReason = "Nothing to undo. Permanent and remote deletes cannot be undone."
  private(set) var redoReason = "Nothing to redo. Permanent and remote deletes cannot be undone."
  var refresh: (() async -> Void)?

  var clipboardURLs: [URL] {
    (NSPasteboard.general.readObjects(
      forClasses: [NSURL.self],
      options: [
        .urlReadingFileURLsOnly: true
      ]) as? [URL]) ?? []
  }

  func copy(_ pane: PaneModel) {
    let urls = localURLs(pane)
    guard !urls.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects(urls as [NSURL])
  }

  func localURLs(_ pane: PaneModel) -> [URL] {
    pane.selectedEntries.filter { $0.location.providerID == "local" }
      .map { URL(fileURLWithPath: $0.location.path) }
  }

  func bindRename(_ pane: PaneModel, window: NSWindow?) {
    pane.onRename = { [weak self, weak pane, weak window] location, name in
      guard let self, let pane else { return }
      let source = URL(fileURLWithPath: location.path)
      let oldExtension = source.pathExtension
      let newExtension = (name as NSString).pathExtension
      let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
      if !isDirectory, oldExtension != newExtension {
        let alert = NSAlert()
        alert.messageText = "Change the filename extension?"
        alert.informativeText =
          "Changing the extension may cause the file to open in a different application."
        alert.addButton(withTitle: "Change Extension")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
      }
      self.run(pane: pane, window: window) {
        [try await self.operations.rename(source: source, name: name)]
      }
    }
  }

  func startRename(_ pane: PaneModel, window: NSWindow?) {
    guard pane.selection.count == 1 else {
      let alert = NSAlert()
      alert.messageText = "Batch Rename"
      alert.informativeText =
        "Renaming multiple items will be available in M09. Select one item to rename it now."
      alert.runModal()
      return
    }
    bindRename(pane, window: window)
    pane.renamingLocation = pane.selection.first
  }

  func create(_ pane: PaneModel, directory: Bool, withSelection: Bool, window: NSWindow?) {
    guard let location = pane.location else { return }
    let destination = URL(fileURLWithPath: location.path)
    let sources = withSelection ? localURLs(pane) : []
    bindRename(pane, window: window)
    run(pane: pane, window: window, renameResult: true) {
      if !sources.isEmpty {
        let folder = try await self.operations.createWithSelection(
          in: destination, name: "untitled folder", sources: sources
        ) { await self.resolve($0, window: window) }
        return [folder]
      }
      return [
        try await self.operations.create(
          in: destination, name: directory ? "untitled folder" : "untitled", directory: directory)
      ]
    }
  }

  func transfer(
    _ browser: BrowserModel, move: Bool, clipboard: Bool = false,
    asNewName: Bool = false, window: NSWindow?
  ) {
    let pane = browser.activePane
    let target = clipboard ? pane : browser.targetPane
    guard let location = target?.location else { return }
    let pasteboardRevision = NSPasteboard.general.changeCount
    let sources = clipboard ? clipboardURLs : localURLs(pane)
    guard !sources.isEmpty else { return }
    let destination = URL(fileURLWithPath: location.path)
    let alert = NSAlert()
    alert.messageText = "\(move ? "Move" : "Copy") \(sources.count) item(s)?"
    alert.informativeText = "Destination: \(destination.path)"
    var newName: String?
    let field = NSTextField(string: sources.first?.lastPathComponent ?? "")
    if asNewName {
      field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
      alert.accessoryView = field
    }
    alert.addButton(withTitle: move ? "Move" : "Copy")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    if asNewName { newName = field.stringValue }
    run(pane: target ?? pane, window: window) {
      let results = try await self.operations.transfer(
        sources: sources, to: destination, move: move, newName: newName
      ) { await self.resolve($0, window: window) }
      if clipboard, move,
        sources.allSatisfy({ (try? FileManager.default.attributesOfItem(atPath: $0.path)) == nil }),
        NSPasteboard.general.changeCount == pasteboardRevision
      {
        NSPasteboard.general.clearContents()
      }
      return results
    }
  }

  func duplicate(_ pane: PaneModel, window: NSWindow?) {
    let sources = localURLs(pane)
    run(pane: pane, window: window) { try await self.operations.duplicate(sources: sources) }
  }

  func trash(_ pane: PaneModel, window: NSWindow?) {
    let sources = localURLs(pane)
    run(pane: pane, window: window) {
      _ = try await self.operations.trash(sources: sources)
      return []
    }
  }

  func history(redo: Bool, pane: PaneModel, window: NSWindow?) {
    run(pane: pane, window: window) {
      if redo { try await self.operations.redo() } else { try await self.operations.undo() }
      return []
    }
  }

  private func run(
    pane: PaneModel, window: NSWindow?, renameResult: Bool = false,
    action: @escaping @MainActor () async throws -> [URL]
  ) {
    guard !isBusy else { return }
    isBusy = true
    let originalLocation = pane.location
    Task {
      defer { isBusy = false }
      do {
        let results = try await action()
        await refresh?()
        if pane.location == originalLocation, !results.isEmpty {
          pane.selection = Set(results.map { Location(providerID: "local", path: $0.path) })
          if renameResult { pane.renamingLocation = pane.selection.first }
        }
      } catch {
        await refresh?()
        let alert = NSAlert(error: error)
        if let window, window.isVisible {
          await alert.beginSheetModal(for: window)
        } else {
          alert.runModal()
        }
      }
      let state = await operations.historyState()
      canUndo = state.canUndo
      canRedo = state.canRedo
      undoReason = state.undoReason ?? ""
      redoReason = state.redoReason ?? ""
    }
  }

  private func resolve(_ conflict: FileConflict, window: NSWindow?) async -> ConflictResolution {
    let alert = NSAlert()
    alert.messageText = "An item named “\(conflict.destination.lastPathComponent)” already exists."
    alert.informativeText =
      "Source: \(conflict.source.path)\nDestination: \(conflict.destination.path)"
    var choices: [(String, ConflictDecision)] = [
      ("Keep Both", .keepBoth), ("Replace", .replace), ("Replace Older", .replaceOlder),
      ("Skip", .skip), ("Stop", .stop),
    ]
    if conflict.isDirectoryMerge { choices.append(("Merge", .merge)) }
    for choice in choices { alert.addButton(withTitle: choice.0) }
    alert.showsSuppressionButton = true
    alert.suppressionButton?.title = "Apply to all conflicts"
    let response: NSApplication.ModalResponse
    if let window, window.isVisible {
      response = await alert.beginSheetModal(for: window)
    } else {
      response = alert.runModal()
    }
    let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    return ConflictResolution(
      decision: choices.indices.contains(index) ? choices[index].1 : .stop,
      applyToAll: alert.suppressionButton?.state == .on)
  }

  func open(_ browser: BrowserModel, packageContents: Bool = false, application: URL? = nil) {
    let paneID = browser.activePaneID
    let entries = browser.activePane.selectedEntries
    for entry in entries {
      let url = URL(fileURLWithPath: entry.location.path)
      let package = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
      if application == nil, entry.kind == .directory, !package || packageContents {
        Task { await browser.enterFolder(entry.location, in: paneID) }
        break
      } else if let application {
        NSWorkspace.shared.open(
          [url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
      } else if !NSWorkspace.shared.open(url) {
        let alert = NSAlert()
        alert.messageText = "Could not open \(entry.name)"
        alert.runModal()
      }
    }
  }

  func chooseApplication(_ browser: BrowserModel, window: NSWindow?) {
    let panel = NSOpenPanel()
    panel.title = "Choose an application"
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.applicationBundle]
    let entries = browser.activePane.selectedEntries
    let completion: (NSApplication.ModalResponse) -> Void = { response in
      guard response == .OK, let application = panel.url else { return }
      NSWorkspace.shared.open(
        entries.map { URL(fileURLWithPath: $0.location.path) },
        withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration())
    }
    if let window {
      panel.beginSheetModal(for: window, completionHandler: completion)
    } else {
      panel.begin(completionHandler: completion)
    }
  }
}
