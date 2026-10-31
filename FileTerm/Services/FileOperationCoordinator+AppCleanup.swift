import AppKit
import FileTermCore

/// The App Deleter (M10.06): moving a `.app` to the Trash lists the files it left in ~/Library.
extension FileOperationCoordinator {
  nonisolated static func isApplication(_ url: URL) -> Bool {
    url.pathExtension.lowercased() == "app"
      && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
  }

  /// Lists each app's related files with a checkbox. Nothing is ticked at first, and only ticked
  /// files are returned. Nil means the user cancelled.
  func chooseAppCleanup(_ apps: [URL]) -> [URL]? {
    let groups = apps.map { app in
      (
        app: app,
        related: AppLeftovers.relatedFiles(
          bundleID: Bundle(url: app)?.bundleIdentifier,
          appName: app.deletingPathExtension().lastPathComponent)
      )
    }
    let list = NSStackView()
    list.orientation = .vertical
    list.alignment = .leading
    list.spacing = 4
    var boxes: [(NSButton, URL)] = []
    let all = NSButton(checkboxWithTitle: "Select all related files", target: nil, action: nil)
    let selectAll = SelectAll()
    all.target = selectAll
    all.action = #selector(SelectAll.toggle(_:))
    if groups.contains(where: { !$0.related.isEmpty }) { list.addArrangedSubview(all) }
    for group in groups {
      let title = NSTextField(labelWithString: group.app.lastPathComponent)
      title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
      list.addArrangedSubview(title)
      if group.related.isEmpty {
        list.addArrangedSubview(NSTextField(labelWithString: "No related files found."))
      }
      for url in group.related {
        let box = NSButton(
          checkboxWithTitle: (url.path as NSString).abbreviatingWithTildeInPath, target: nil,
          action: nil)
        (box.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingMiddle
        box.toolTip = url.path
        list.addArrangedSubview(box)
        boxes.append((box, url))
      }
    }
    selectAll.boxes = boxes.map(\.0)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 220))
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    list.translatesAutoresizingMaskIntoConstraints = false
    let document = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 10))
    document.addSubview(list)
    NSLayoutConstraint.activate([
      list.topAnchor.constraint(equalTo: document.topAnchor),
      list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
      list.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor),
      list.bottomAnchor.constraint(equalTo: document.bottomAnchor),
    ])
    document.frame.size.height = list.fittingSize.height
    scroll.documentView = document

    let alert = NSAlert()
    alert.messageText =
      apps.count == 1
      ? "Move “\(apps[0].lastPathComponent)” to the Trash?"
      : "Move \(apps.count) applications to the Trash?"
    alert.informativeText =
      "Tick the related files to move to the Trash as well. Only ticked files are moved."
    alert.accessoryView = scroll
    alert.addButton(withTitle: "Move to Trash")
    alert.addButton(withTitle: "Cancel")
    // The button holds its target weakly, so keep Select All alive while the alert is up.
    let response = withExtendedLifetime(selectAll) { alert.runModal() }
    guard response == .alertFirstButtonReturn else { return nil }
    return boxes.filter { $0.0.state == .on }.map(\.1)
  }
}

@MainActor private final class SelectAll: NSObject {
  var boxes: [NSButton] = []
  @objc func toggle(_ sender: NSButton) {
    for box in boxes { box.state = sender.state }
  }
}
