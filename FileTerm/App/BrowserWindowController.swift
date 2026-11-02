import AppKit
import FileTermCore
import Observation
import SwiftTerm
import SwiftUI

@MainActor final class BrowserWindowController: NSObject, NSWindowDelegate {
  let id = UUID()
  let browser: BrowserModel
  let devices: DeviceModel
  let terminal: TerminalWorkspace
  let window: NSWindow
  var onClose: (() -> Void)?
  var onActivate: (() -> Void)?

  init(
    browser: BrowserModel, devices: DeviceModel, settings: AppSettings,
    registry: CommandRegistry, provider: LocalFileSystemProvider, frame: String? = nil,
    terminalPanel: TerminalPanelState? = nil, transfers: TransferQueue = TransferQueue(),
    connections: ConnectionCoordinator, cloudFiles: CloudFileActions
  ) {
    self.browser = browser
    self.devices = devices
    terminal = TerminalWorkspace(browser: browser, settings: settings, panel: terminalPanel)
    terminal.sshSession = { connections.sshSession(for: $0) }
    window = BrowserWindow(
      registry: registry,
      selectedFiles: { [weak browser] in
        guard let pane = browser?.activePane else { return [] }
        // With nothing selected, Services get the folder being shown.
        let locations =
          pane.selection.isEmpty
          ? [pane.location].compactMap { $0 } : pane.selectedEntries.map(\.location)
        return locations.filter { $0.providerID == "local" }
          .map { URL(fileURLWithPath: $0.path) }
      },
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    super.init()
    window.identifier = NSUserInterfaceItemIdentifier("browserWindow")
    window.isReleasedWhenClosed = false
    window.contentMinSize = NSSize(width: 680, height: 420)
    window.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
    window.tabbingMode = .disallowed
    window.delegate = self
    let host = NSHostingView(
      rootView: BrowserView(
        browser: browser, settings: settings,
        registry: registry, localProvider: provider, devices: devices, terminal: terminal,
        transfers: transfers, connections: connections
      ).environment(cloudFiles))
    window.contentView = host
    // Measuring the minimum size on every frame makes zoom stutter. Zoom only moves between
    // frames that already fit, so the measurement waits until the animation ends.
    (window as? BrowserWindow)?.onAnimatedResize = { [host] animating in
      host.sizingOptions = animating ? [] : .standardBounds
    }
    if let frame {
      let rect = NSRectFromString(frame)
      if rect.width >= 680, rect.height >= 420,
        NSScreen.screens.contains(where: { $0.visibleFrame.intersects(rect) })
      {
        window.setFrame(rect, display: false)
      } else {
        window.center()
      }
    } else {
      window.center()
    }
    applyChrome(settings)
    observeTitle()
  }

  func applyChrome(_ settings: AppSettings) {
    let visible = settings.isVisible(.titleBar)
    window.titleVisibility = visible ? .visible : .hidden
    window.titlebarAppearsTransparent = !visible
    if visible {
      window.styleMask.remove(.fullSizeContentView)
    } else {
      window.styleMask.insert(.fullSizeContentView)
    }
  }

  private func observeTitle() {
    withObservationTracking {
      let path = browser.activePane.location?.path
      let title =
        path.map { $0 == "/" ? "/" : URL(fileURLWithPath: $0).lastPathComponent } ?? "Browser"
      window.title = "FileTerm — " + title
    } onChange: { [weak self] in
      Task { @MainActor in self?.observeTitle() }
    }
  }

  func windowWillClose(_ notification: Notification) {
    terminal.closeAll()
    onClose?()
  }
  func windowDidBecomeKey(_ notification: Notification) { onActivate?() }
  func snapshot() -> WindowSnapshot {
    WindowSnapshot(
      browser: browser.snapshot(), frame: NSStringFromRect(window.frame), terminal: terminal.panel)
  }
}

private final class BrowserWindow: NSWindow, @preconcurrency NSServicesMenuRequestor {
  private let registry: CommandRegistry
  private let selectedFiles: () -> [URL]
  var onAnimatedResize: ((Bool) -> Void)?

  init(
    registry: CommandRegistry, selectedFiles: @escaping () -> [URL], contentRect: NSRect,
    styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool
  ) {
    self.registry = registry
    self.selectedFiles = selectedFiles
    super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
  }

  override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
    guard animateFlag else { return super.setFrame(frameRect, display: flag, animate: false) }
    onAnimatedResize?(true)
    super.setFrame(frameRect, display: flag, animate: true)
    onAnimatedResize?(false)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.keyCode == 53,
      event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
      attachedSheet == nil, !(firstResponder is NSText), !(firstResponder is TerminalView),
      registry.effectiveShortcut(for: "quickOpen") == DefaultShortcuts.quickOpen,
      registry.execute("quickOpen")
    {
      return true
    }
    return super.performKeyEquivalent(with: event)
  }

  /// Text fields answer first for their own text. This offers the selected files to Services.
  override func validRequestor(
    forSendType sendType: NSPasteboard.PasteboardType?,
    returnType: NSPasteboard.PasteboardType?
  ) -> Any? {
    if returnType == nil, sendType.map(ServiceTypes.files.contains) == true,
      !selectedFiles().isEmpty
    {
      return self
    }
    return super.validRequestor(forSendType: sendType, returnType: returnType)
  }

  func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
    let urls = selectedFiles()
    guard !urls.isEmpty else { return false }
    pboard.clearContents()
    return pboard.writeObjects(urls as [NSURL])
  }
}

enum ServiceTypes {
  /// Older services still ask for files by the filenames type.
  static let files: [NSPasteboard.PasteboardType] = [
    .fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType"),
  ]
}
