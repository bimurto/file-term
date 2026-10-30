import AppKit
import FileTermCore

extension FileOperationCoordinator {
  /// Copies or moves dropped files into the pane's folder through the queue.
  func drop(
    _ urls: [URL], onto pane: PaneModel, confirm: Bool, optionPressed: Bool, window: NSWindow?
  ) async {
    guard let location = pane.location, !rejectsArchiveEdit(pane) else { return }
    let remote = isRemote(pane)
    let paths = urls.map(\.path)
    let sources = (remote ? paths : FileDrop.sources(paths, into: location.path))
      .map { URL(fileURLWithPath: $0) }
    guard !sources.isEmpty else { return }
    let destination = URL(fileURLWithPath: location.path)
    var move =
      !remote
      && FileDrop.movesByDefault(
        sameVolume: Self.onSameVolume(sources, destination), optionPressed: optionPressed)
    if confirm {
      guard
        let choice = await confirmDrop(
          count: sources.count, destination: describe(location), suggestsMove: move, window: window)
      else { return }
      move = choice
    }
    if remote {
      let items = sources.map { Location(providerID: "local", path: $0.path) }
      submitProviderCopy(sources: items, to: location, move: move, window: window)
      return
    }
    run(
      kind: move ? .move : .copy, sources: sources, destination: destination, pane: pane,
      window: window
    ) { operations in
      try await operations.transfer(
        sources: sources, to: destination, move: move, newName: nil
      ) { await self.resolve($0, window: window) }
    }
  }

  /// The chosen action, true for move, or nil when the drop is cancelled.
  private func confirmDrop(
    count: Int, destination: String, suggestsMove: Bool, window: NSWindow?
  ) async -> Bool? {
    let alert = NSAlert()
    alert.messageText = "Copy or move \(count) item(s)?"
    alert.informativeText = "Destination: \(destination)"
    let order = suggestsMove ? [true, false] : [false, true]
    for move in order { alert.addButton(withTitle: move ? "Move" : "Copy") }
    alert.addButton(withTitle: "Cancel")
    let response: NSApplication.ModalResponse
    if let window, window.isVisible {
      response = await alert.beginSheetModal(for: window)
    } else {
      response = alert.runModal()
    }
    let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    return order.indices.contains(index) ? order[index] : nil
  }

  private static func onSameVolume(_ sources: [URL], _ destination: URL) -> Bool {
    func volume(_ url: URL) -> NSObject? {
      (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
    }
    guard let target = volume(destination) else { return false }
    return sources.allSatisfy { volume($0) == target }
  }
}
