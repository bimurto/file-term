import AppKit
import PDFKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// Retain one coordinator for the application's lifetime. All arguments are local URLs;
/// callers should pass selected entries in display order and the originating browser window.
@MainActor final class FilePreviewCoordinator: NSResponder, QLPreviewPanelDataSource {
  var onMetadataChange: () -> Void = {}
  private var previewURLs: [URL] = []
  private weak var sourceWindow: NSWindow?
  private var infoWindows: [NSWindowController] = []

  func showQuickLook(_ urls: [URL]) { quickLook(urls: urls, window: NSApp.mainWindow) }
  func showSlideshow(_ urls: [URL]) { slideshow(urls: urls, window: NSApp.mainWindow) }
  static func canPrint(_ url: URL) -> Bool {
    FilePreviewCoordinator().canPrint(urls: [url])
  }
  func printFile(_ url: URL) { printFiles(urls: [url], window: NSApp.mainWindow) }
  func showInfo(_ urls: [URL]) { getInfo(urls: urls) }

  /// Opens the system floating Quick Look panel for the selection.
  func quickLook(urls: [URL], window: NSWindow?) {
    present(urls: urls, window: window, fullScreen: false)
  }

  /// Uses Quick Look's native full-screen slideshow, filtering out non-images.
  func slideshow(urls: [URL], window: NSWindow?) {
    let images = urls.filter {
      (try? PreviewFileType.type(of: $0).conforms(to: .image)) == true
    }
    present(urls: images, window: window, fullScreen: true)
  }

  func canSlideshow(urls: [URL]) -> Bool {
    urls.contains { (try? PreviewFileType.type(of: $0).conforms(to: .image)) == true }
  }

  /// Printing is intentionally single-file only. Media, folders, unknown data, oversized
  /// text, and unsupported encodings are not advertised as printable.
  func canPrint(urls: [URL]) -> Bool {
    guard urls.count == 1, let url = urls.first,
      let type = try? PreviewFileType.type(of: url)
    else { return false }
    if type.conforms(to: .pdf) { return PDFDocument(url: url) != nil }
    if type.conforms(to: .image) { return NSImage(contentsOf: url) != nil }
    return (try? PreviewTextDocument(url: url)) != nil
  }

  /// Presents the native print dialog. Revalidates eligibility instead of relying on menu state.
  func printFiles(urls: [URL], window: NSWindow?) {
    guard urls.count == 1, let url = urls.first else { return }
    do {
      let type = try PreviewFileType.type(of: url)
      let operation: NSPrintOperation
      if type.conforms(to: .pdf), let document = PDFDocument(url: url),
        let pdfOperation = document.printOperation(
          for: NSPrintInfo.shared, scalingMode: .pageScaleToFit, autoRotate: true)
      {
        operation = pdfOperation
      } else if type.conforms(to: .image), let image = NSImage(contentsOf: url) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        let view = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        operation = NSPrintOperation(view: view, printInfo: info)
      } else {
        let document = try PreviewTextDocument(url: url)
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 700))
        view.string = document.text
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.sizeToFit()
        operation = NSPrintOperation(view: view)
      }
      operation.jobTitle = url.lastPathComponent
      if let window {
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
      } else {
        operation.run()
      }
    } catch { show(error, window: window) }
  }

  /// Opens an independent inspector for each selected local item.
  func getInfo(urls: [URL]) {
    infoWindows.removeAll { $0.window?.isVisible != true }
    for url in urls where url.isFileURL {
      let controller = NSWindowController(
        window: NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 420, height: 680),
          styleMask: [.titled, .closable, .miniaturizable, .resizable],
          backing: .buffered, defer: false))
      guard let window = controller.window else { continue }
      window.title = "\(url.lastPathComponent) Info"
      window.isReleasedWhenClosed = false
      window.contentView = NSHostingView(
        rootView: MetadataInspectorView(url: url, onChange: onMetadataChange))
      window.center()
      controller.showWindow(nil)
      infoWindows.append(controller)
    }
  }

  private func present(urls: [URL], window: NSWindow?, fullScreen: Bool) {
    let local = urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
    guard !local.isEmpty, let window = window ?? NSApp.mainWindow,
      let panel = QLPreviewPanel.shared()
    else { return }
    if sourceWindow !== window {
      detach()
      sourceWindow = window
      nextResponder = window.nextResponder
      window.nextResponder = self
    }
    previewURLs = local
    panel.updateController()
    // Only the accepted controller may alter the shared system panel.
    guard panel.currentController as AnyObject? === self else { return }
    if panel.isInFullScreenMode && !fullScreen { panel.exitFullScreenMode(options: nil) }
    panel.reloadData()
    panel.currentPreviewItemIndex = 0
    if fullScreen {
      _ = panel.enterFullScreenMode(nil, withOptions: nil)
    } else {
      panel.makeKeyAndOrderFront(nil)
    }
  }

  private func detach() {
    if sourceWindow?.nextResponder === self { sourceWindow?.nextResponder = nextResponder }
    nextResponder = nil
    sourceWindow = nil
  }

  // Quick Look's Objective-C callbacks are not annotated for concurrency, but AppKit
  // invokes them on the main thread. Assert that contract at this boundary.
  nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
    MainActor.assumeIsolated { !previewURLs.isEmpty }
  }

  nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    MainActor.assumeIsolated { panel.dataSource = self }
  }

  nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    MainActor.assumeIsolated { panel.dataSource = nil }
  }

  nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
    MainActor.assumeIsolated { previewURLs.count }
  }

  nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (
    any QLPreviewItem
  )! {
    let url: URL? = MainActor.assumeIsolated {
      previewURLs.indices.contains(index) ? previewURLs[index] : nil
    }
    return url.map { $0 as NSURL }
  }

  private func show(_ error: Error, window: NSWindow?) {
    let alert = NSAlert(error: error)
    if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
  }
}
