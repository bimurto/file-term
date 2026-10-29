import AppKit
import FileTermCore

extension FileOperationCoordinator {
  func isArchive(_ entry: FileEntry) -> Bool {
    entry.location.providerID == "local" && entry.kind != .directory
      && ArchiveFormat.isArchive(name: entry.name)
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
