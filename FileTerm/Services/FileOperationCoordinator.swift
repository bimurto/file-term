import AppKit
import FileTermCore

/// App-wide local history and clipboard, with each operation bound to its originating pane.
@MainActor final class FileOperationCoordinator {
  let transfers = TransferQueue()
  var preferences: () -> TransferPreferences = { TransferPreferences() }
  private var undoHistory: [LocalFileOperations] = []
  private var redoHistory: [LocalFileOperations] = []
  var isBusy: Bool { transfers.hasPendingWork }
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
      self.run(
        kind: .rename, sources: [source],
        destination: source.deletingLastPathComponent().appendingPathComponent(name), pane: pane,
        window: window
      ) { operations in
        [try await operations.rename(source: source, name: name)]
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
    run(
      kind: .create, sources: sources, destination: destination, pane: pane, window: window,
      renameResult: true
    ) { operations in
      if !sources.isEmpty {
        let folder = try await operations.createWithSelection(
          in: destination, name: "untitled folder", sources: sources
        ) { await self.resolve($0, window: window) }
        return [folder]
      }
      return [
        try await operations.create(
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
    run(
      kind: move ? .move : .copy, sources: sources, destination: destination, pane: target ?? pane,
      window: window
    ) { operations in
      let results = try await operations.transfer(
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
    run(kind: .duplicate, sources: sources, pane: pane, window: window) { operations in
      try await operations.duplicate(sources: sources)
    }
  }

  func trash(_ pane: PaneModel, window: NSWindow?) {
    let sources = localURLs(pane)
    run(kind: .delete, sources: sources, pane: pane, window: window) { operations in
      _ = try await operations.trash(sources: sources)
      return []
    }
  }

  func history(redo: Bool, pane: PaneModel, window: NSWindow?) {
    guard !isBusy, let operations = redo ? redoHistory.last : undoHistory.last else { return }
    transfers.submit(kind: redo ? .redo : .undo, resources: ["*"], retrySafe: false) { control in
      await operations.setTransferControl(control, verification: self.preferences().verification)
      do {
        if redo {
          try await operations.redo()
          self.redoHistory.removeLast()
          self.undoHistory.append(operations)
        } else {
          try await operations.undo()
          self.undoHistory.removeLast()
          self.redoHistory.append(operations)
        }
        await self.refresh?()
        await self.updateHistory()
        return TransferSummary(succeeded: 1)
      } catch {
        await self.refresh?()
        await self.updateHistory()
        throw error
      }
    }
  }

  private func updateHistory() async {
    let undo = await undoHistory.last?.historyState()
    let redo = await redoHistory.last?.historyState()
    canUndo = undo?.canUndo ?? false
    canRedo = redo?.canRedo ?? false
    undoReason = undo?.undoReason ?? "Nothing to undo."
    redoReason = redo?.redoReason ?? "Nothing to redo."
  }

  private func run(
    kind: TransferJobKind, sources: [URL] = [], destination: URL? = nil,
    pane: PaneModel, window: NSWindow?, renameResult: Bool = false,
    action: @escaping @MainActor (LocalFileOperations) async throws -> [URL]
  ) {
    let policy = preferences()
    transfers.preferences = policy
    let originalLocation = pane.location
    let operations = LocalFileOperations()
    // Reserve top-level filesystem roots conservatively. Independent roots can run together;
    // overlapping subtrees must never race replacement recovery or undo history.
    let resources = Set(
      (sources + [destination].compactMap { $0 }).map {
        $0.deletingLastPathComponent().resolvingSymlinksInPath().path
      })
    var jobID: UUID?
    jobID = transfers.submit(
      kind: kind, sources: sources, destination: destination, resources: resources
    ) { control in
      let scan = Task.detached { Self.transferSize(sources) }
      let total = await withTaskCancellationHandler {
        await scan.value
      } onCancel: {
        scan.cancel()
      }
      if let jobID { self.transfers.setTotalBytes(jobID, total) }
      await operations.setTransferControl(control, verification: policy.verification)
      do {
        try await control.checkpoint()
        let results = try await action(operations)
        if await operations.hasUndoHistory() {
          self.undoHistory.append(operations)
          self.redoHistory.removeAll()
        }
        await self.refresh?()
        if pane.location == originalLocation, !results.isEmpty {
          pane.selection = Set(results.map { Location(providerID: "local", path: $0.path) })
          if renameResult { pane.renamingLocation = pane.selection.first }
        }
        await self.updateHistory()
        if kind == .copy || kind == .move || kind == .duplicate {
          return await operations.outcomeSummary()
        }
        return TransferSummary(succeeded: kind == .delete ? sources.count : results.count)
      } catch {
        if let jobID { self.transfers.setSummary(jobID, await operations.outcomeSummary()) }
        let hasHistory = await operations.hasUndoHistory()
        if hasHistory && !self.undoHistory.contains(where: { $0 === operations }) {
          self.undoHistory.append(operations)
          self.redoHistory.removeAll()
        }
        await self.refresh?()
        await self.updateHistory()
        if hasHistory, !(error is CancellationError) {
          throw PartialTransferError(error.localizedDescription)
        }
        throw error
      }
    }
  }

  nonisolated private static func transferSize(_ sources: [URL]) -> Int64? {
    let fm = FileManager.default
    var total: Int64 = 0
    func add(_ url: URL) throws {
      try Task.checkCancellation()
      let attributes = try fm.attributesOfItem(atPath: url.path)
      if attributes[.type] as? FileAttributeType == .typeDirectory {
        for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
          try add(child)
        }
      } else if attributes[.type] as? FileAttributeType == .typeRegular {
        let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let (next, overflow) = total.addingReportingOverflow(bytes)
        guard !overflow else { throw CocoaError(.fileReadTooLarge) }
        total = next
      }
    }
    do {
      for source in sources { try add(source) }
      return total
    } catch { return nil }
  }

  private func resolve(_ conflict: FileConflict, window: NSWindow?) async -> ConflictResolution {
    let policy = preferences()
    let selected = conflict.isDirectoryMerge ? policy.mergePolicy : policy.replacePolicy
    if let decision = selected.decision {
      for job in transfers.jobs where job.state == .running {
        if job.sources.contains(where: {
          conflict.source.path == $0.path || conflict.source.path.hasPrefix($0.path + "/")
        }) {
          transfers.log(job.id, "Conflict: \(selected.rawValue) — \(conflict.destination.path)")
        }
      }
      return ConflictResolution(decision: decision)
    }
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
    let decision = choices.indices.contains(index) ? choices[index].1 : .stop
    for job in transfers.jobs where job.state == .running {
      if job.sources.contains(where: {
        conflict.source.path == $0.path || conflict.source.path.hasPrefix($0.path + "/")
      }) {
        transfers.log(job.id, "Conflict: \(decision) — \(conflict.destination.path)")
      }
    }
    return ConflictResolution(decision: decision, applyToAll: alert.suppressionButton?.state == .on)
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
