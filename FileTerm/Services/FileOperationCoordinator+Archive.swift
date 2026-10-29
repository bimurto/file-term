import AppKit
import FileTermCore

enum ArchiveOpenBehavior {
  /// Hand the archive to the default application.
  case system
  /// Extract next to the archive.
  case extract
  /// Browse it as a folder.
  case browse
}

extension FileOperationCoordinator {
  func isArchive(_ entry: FileEntry) -> Bool {
    entry.location.providerID == "local" && entry.kind != .directory
      && ArchiveFormat.isArchive(name: entry.name)
  }

  /// Applies Settings › General to an archive the user opened. Returns false to open it normally.
  func openArchive(_ entry: FileEntry, in browser: BrowserModel) -> Bool {
    guard entry.kind != .directory, ArchiveFormat.isArchive(name: entry.name) else { return false }
    switch archiveOpenBehavior() {
    case .system:
      return false
    case .extract:
      guard isArchive(entry) else { return false }
      browser.activePane.selection = [entry.id]
      extract(browser, choose: false, window: nil)
      return true
    case .browse:
      browseArchive(entry, in: browser)
      return true
    }
  }

  /// Opens an archive as a read-only folder in the active pane. An archive on a server (or inside
  /// another archive) is downloaded first, as a queue job.
  func browseArchive(_ entry: FileEntry, in browser: BrowserModel) {
    let paneID = browser.activePaneID
    let registry = registry
    let container = entry.location.parent
    func show(_ provider: ArchiveProvider) async {
      do {
        try await provider.load()
        openingArchives.insert(provider.id)
        defer { openingArchives.remove(provider.id) }
        registry.register(provider)
        if let container { registry.setContainer(container, for: provider.id) }
        await browser.navigate(
          to: Location(providerID: provider.id, path: "/"), in: paneID)
      } catch {
        await provider.close()
        let alert = NSAlert()
        alert.messageText = "Could not open \(entry.name) as a folder"
        alert.informativeText = error.localizedDescription
        alert.runModal()
      }
    }
    if entry.location.providerID == "local" {
      let provider = ArchiveProvider(archive: URL(fileURLWithPath: entry.location.path))
      Task { await show(provider) }
      return
    }
    submitRemote(
      kind: .open, locations: [entry.location], direction: .download, totalBytes: entry.size
    ) { control in
      guard let source = registry.provider(for: entry.location.providerID) else {
        throw FileSystemError.unsupportedOperation
      }
      let file = try await Self.download(entry, provider: source, control: control)
      await show(
        ArchiveProvider(archive: file, temporaryFolder: file.deletingLastPathComponent()))
      return TransferSummary(succeeded: 1)
    }
  }

  /// Closes archives no tab shows any more, and deletes the copies downloaded for them.
  func pruneArchives(inUse: Set<String>) {
    for id in registry.providerIDs(withPrefix: "archive:")
    where !inUse.contains(id) && !openingArchives.contains(id) {
      let provider = registry.provider(for: id) as? ArchiveProvider
      registry.unregister(id: id)
      if let provider { Task { await provider.close() } }
    }
  }

  /// Archives opened as folders are read-only; tell the user instead of failing mid-job.
  func rejectsArchiveEdit(_ pane: PaneModel) -> Bool {
    guard pane.location?.providerID.hasPrefix("archive:") == true else { return false }
    let alert = NSAlert()
    alert.messageText = "This archive is read-only"
    alert.informativeText =
      "Items inside an archive opened as a folder cannot be changed. Extract it first."
    alert.runModal()
    return true
  }

  /// Commands › Compress (zip with default settings) and Compress With Options….
  func compress(_ browser: BrowserModel, withOptions: Bool, window: NSWindow?) {
    let pane = browser.activePane
    let sources = localURLs(pane)
    guard !sources.isEmpty, let folder = pane.location else { return }
    var format = ArchiveFormat.zip
    var stem = ArchiveTool.defaultStem(for: sources)
    var directory = URL(fileURLWithPath: folder.path)
    if withOptions {
      let formats = NSPopUpButton(frame: .zero, pullsDown: false)
      formats.addItems(withTitles: ArchiveFormat.allCases.map(\.title))
      let name = NSTextField(string: stem)
      let place = destinationPopUp(browser, folder: directory)
      let alert = NSAlert()
      alert.messageText = "Compress \(sources.count) item(s)"
      alert.accessoryView = form([("Format", formats), ("Name", name), ("Save in", place.popUp)])
      alert.addButton(withTitle: "Compress")
      alert.addButton(withTitle: "Cancel")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      format = ArchiveFormat.allCases[formats.indexOfSelectedItem]
      guard let chosen = place.resolve() else { return }
      directory = chosen
      let typed = Self.fileName(name.stringValue)
      if !typed.isEmpty { stem = typed }
      if stem.lowercased().hasSuffix("." + format.fileExtension) {
        stem = String(stem.dropLast(format.fileExtension.count + 1))
      }
    }
    let destination = directory
    run(kind: .compress, sources: sources, destination: destination, pane: pane, window: window) {
      _ in
      let target = ArchiveTool.uniqueURL(in: destination, stem: stem, ext: format.fileExtension)
      try await ArchiveTool.compress(sources: sources, format: format, destination: target)
      return [target]
    }
  }

  /// Commands › Extract (next to each archive) and Extract to… (`choose`).
  func extract(_ browser: BrowserModel, choose: Bool, window: NSWindow?) {
    let pane = browser.activePane
    let archives = pane.selectedEntries.filter(isArchive)
      .map { URL(fileURLWithPath: $0.location.path) }
    guard !archives.isEmpty, let folder = pane.location else { return }
    var directory: URL?
    var newFolder = false
    if choose {
      let place = destinationPopUp(browser, folder: URL(fileURLWithPath: folder.path))
      let box = NSButton(
        checkboxWithTitle: "Create a new folder for the contents", target: nil, action: nil)
      let alert = NSAlert()
      alert.messageText = "Extract \(archives.count) archive(s) to…"
      alert.accessoryView = form([("Extract to", place.popUp), ("", box)])
      alert.addButton(withTitle: "Extract")
      alert.addButton(withTitle: "Cancel")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      guard let chosen = place.resolve() else { return }
      directory = chosen
      newFolder = box.state == .on
    }
    let destination = directory
    let wantsFolder = newFolder
    run(kind: .extract, sources: archives, destination: destination, pane: pane, window: window) {
      _ in
      var results: [URL] = []
      for archive in archives {
        try Task.checkCancellation()
        results += try await ArchiveTool.extract(
          archive: archive, into: destination ?? archive.deletingLastPathComponent(),
          newFolder: wantsFolder)
      }
      return results
    }
  }

  /// "This folder", the other pane when it shows a local folder, and Choose… (asked on resolve).
  private func destinationPopUp(_ browser: BrowserModel, folder: URL)
    -> (popUp: NSPopUpButton, resolve: () -> URL?)
  {
    let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
    popUp.addItem(withTitle: "This folder")
    var other: URL?
    if let location = browser.targetPane?.location, location.providerID == "local" {
      other = URL(fileURLWithPath: location.path)
      popUp.addItem(withTitle: "Other pane: " + (location.path as NSString).lastPathComponent)
    }
    popUp.addItem(withTitle: "Choose…")
    return (
      popUp,
      {
        let title = popUp.titleOfSelectedItem ?? ""
        if title == "This folder" { return folder }
        if title.hasPrefix("Other pane") { return other }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
      }
    )
  }

  private func form(_ rows: [(String, NSView)]) -> NSView {
    let grid = NSGridView(
      views: rows.map { [NSTextField(labelWithString: $0.0), $0.1] })
    grid.column(at: 0).xPlacement = .trailing
    grid.rowSpacing = 8
    grid.setContentHuggingPriority(.required, for: .horizontal)
    grid.frame.size = NSSize(width: 380, height: CGFloat(rows.count) * 30)
    for row in 0..<grid.numberOfRows {
      grid.cell(atColumnIndex: 1, rowIndex: row).xPlacement = .fill
    }
    return grid
  }

  private static func fileName(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
  }
}
