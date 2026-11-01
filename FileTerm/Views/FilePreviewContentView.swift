import AVKit
import AppKit
import Observation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Native local-file preview. Keep this view's identity stable when changing `url` so that
/// pending text edits can be saved or explicitly discarded before the selection changes.
@MainActor public struct FilePreviewContentView: View {
  public let url: URL
  @State private var model = FilePreviewModel()

  public init(url: URL) { self.url = url }

  /// Call from applicationShouldTerminate; false means return .terminateCancel.
  /// Includes both visible previews and retained recovery editing windows.
  public static func confirmTermination() -> Bool {
    FilePreviewModel.confirmTermination()
  }

  @FocusState private var isEditorFocused: Bool

  fileprivate init(url: URL, model: FilePreviewModel) {
    self.url = url
    self._model = State(initialValue: model)
  }

  public var body: some View {
    VStack(spacing: 0) {
      if let current = model.url {
        HStack {
          Text(current.lastPathComponent).lineLimit(1).help(current.path)
          Spacer()
          if model.document != nil {
            if model.isDirty { Text("Edited").foregroundStyle(.secondary) }
            Button("Save") { model.save() }
              .keyboardShortcut("s", modifiers: .command)
              .disabled(!model.isDirty)
              .accessibilityIdentifier("preview.save")
              // ⌘S in the editor with nothing to save stays here instead of reaching Quick Select.
              .background {
                Button("") {}
                  .keyboardShortcut("s", modifiers: .command)
                  .disabled(model.isDirty || !isEditorFocused)
                  .opacity(0).accessibilityHidden(true)
              }
          }
        }.padding(10)
        Divider()
      }
      Group {
        switch model.kind {
        case .image:
          if let image = model.image {
            Image(nsImage: image).resizable().scaledToFit().padding(8)
              .accessibilityLabel(model.url?.lastPathComponent ?? "Image")
          } else {
            unavailable("The image could not be decoded.")
          }
        case .pdf:
          if let url = model.url { PDFPreview(url: url) }
        case .media:
          if let player = model.player { VideoPlayer(player: player) }
        case .text:
          TextEditor(text: $model.text).font(.system(.body, design: .monospaced))
            .focused($isEditorFocused)
            .accessibilityLabel("File text").accessibilityIdentifier("preview.text")
        case .unavailable:
          unavailable(model.reason ?? "Select a supported file to preview.")
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      if let error = model.error {
        Divider()
        Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
          .padding(10).frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .task { model.requestURL(url) }
    .onChange(of: url) { _, newURL in model.requestURL(newURL) }
    .onDisappear {
      model.player?.pause()
      // Selection clearing, panel hiding and parent-window closure can remove this
      // view without a URL change. Transfer ownership rather than dropping edits.
      if model.isDirty && !model.isInEditingWindow {
        PreviewEditingWindow.retainEdits(model)
        // A hidden preview can later reappear for a different selection. It must
        // not share and replace the document now owned by the editing window.
        model = FilePreviewModel()
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func unavailable(_ reason: String) -> some View {
    ContentUnavailableView {
      Label("Preview unavailable", systemImage: "doc.questionmark")
    } description: {
      Text(reason)
    }
  }
}

@MainActor @Observable private final class FilePreviewModel {
  private final class WeakSession {
    weak var model: FilePreviewModel?
    init(_ model: FilePreviewModel) { self.model = model }
  }
  private static var sessions: [WeakSession] = []

  init() {
    Self.sessions.removeAll { $0.model == nil }
    Self.sessions.append(WeakSession(self))
  }

  static func confirmTermination() -> Bool {
    let active = sessions.compactMap(\.model)
    for model in active where model.isDirty {
      let alert = NSAlert()
      alert.messageText =
        "Save changes to \(model.url?.lastPathComponent ?? "this file") before quitting?"
      alert.informativeText = "Unsaved edits will be lost if you discard them and quit."
      alert.addButton(withTitle: "Save")
      alert.addButton(withTitle: "Discard Changes")
      alert.addButton(withTitle: "Cancel Quit")
      switch alert.runModal() {
      case .alertFirstButtonReturn:
        guard model.save() else {
          // Surface the save error even when the original preview is hidden.
          PreviewEditingWindow.retainEdits(model)
          return false
        }
      case .alertSecondButtonReturn: model.text = model.document?.text ?? ""
      default: return false
      }
    }
    return true
  }

  enum Kind { case image, pdf, media, text, unavailable }
  var url: URL?
  var kind = Kind.unavailable
  var text = ""
  var document: PreviewTextDocument?
  var image: NSImage?
  var player: AVPlayer?
  var reason: String?
  var error: String?
  var isInEditingWindow = false
  var isDirty: Bool { document.map { text != $0.text } ?? false }

  func requestURL(_ next: URL) {
    guard next != url else { return }
    if isDirty {
      let alert = NSAlert()
      alert.messageText = "Save changes to \(url?.lastPathComponent ?? "this file")?"
      alert.informativeText =
        "The selection changed. Keep Editing retains this preview and its unsaved changes."
      alert.addButton(withTitle: "Save")
      alert.addButton(withTitle: "Discard Changes")
      alert.addButton(withTitle: "Keep Editing")
      switch alert.runModal() {
      case .alertFirstButtonReturn:
        guard save() else { return }
      case .alertSecondButtonReturn: break
      default: return
      }
    }
    player?.pause()
    player = nil
    image = nil
    document = nil
    text = ""
    error = nil
    reason = nil
    url = next
    kind = .unavailable
    do {
      let type = try PreviewFileType.type(of: next)
      if type.conforms(to: .image) {
        kind = .image
        image = NSImage(contentsOf: next)
      } else if type.conforms(to: .pdf) {
        kind = .pdf
      } else if type.conforms(to: .audio) || type.conforms(to: .movie) {
        kind = .media
        player = AVPlayer(url: next)
      } else {
        let loaded = try PreviewTextDocument(url: next)
        document = loaded
        text = loaded.text
        kind = .text
      }
    } catch { reason = error.localizedDescription }
  }

  @discardableResult func save() -> Bool {
    guard var document else { return true }
    do {
      try document.save(text)
      self.document = document
      error = nil
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
}

/// Owns orphaned edits independently of the browser/inspector view hierarchy.
/// The registry keeps the window and model alive until a successful Save or explicit
/// Discard permits closure; closing the window cannot silently drop a dirty document.
@MainActor private final class PreviewEditingWindow: NSWindowController, NSWindowDelegate {
  private static var retained: [UUID: PreviewEditingWindow] = [:]
  private let token = UUID()
  private let model: FilePreviewModel

  static func retainEdits(_ model: FilePreviewModel) {
    guard model.isDirty, !model.isInEditingWindow, let url = model.url else { return }
    model.isInEditingWindow = true
    let controller = PreviewEditingWindow(model: model, url: url)
    retained[controller.token] = controller
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
  }

  private init(model: FilePreviewModel, url: URL) {
    self.model = model
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    super.init(window: window)
    window.title = "Unsaved Edits — \(url.lastPathComponent)"
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = NSHostingView(rootView: FilePreviewContentView(url: url, model: model))
    window.center()
  }

  required init?(coder: NSCoder) { nil }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard model.isDirty else { return true }
    let alert = NSAlert()
    alert.messageText = "Save changes to \(model.url?.lastPathComponent ?? "this file")?"
    alert.informativeText =
      "Your unsaved edits are retained in this window until you save or explicitly discard them."
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Discard Changes")
    alert.addButton(withTitle: "Keep Editing")
    switch alert.runModal() {
    case .alertFirstButtonReturn: return model.save()
    case .alertSecondButtonReturn:
      model.text = model.document?.text ?? ""
      return true
    default: return false
    }
  }

  func windowWillClose(_ notification: Notification) {
    // Keep the flag set until SwiftUI has dismantled the hosted preview, preventing
    // its onDisappear from recursively creating another recovery window.
    let model = self.model
    let token = self.token
    Task { @MainActor in
      Self.retained.removeValue(forKey: token)
      model.isInEditingWindow = false
    }
  }
}

private struct PDFPreview: NSViewRepresentable {
  let url: URL
  func makeNSView(context: Context) -> PDFView {
    let view = PDFView()
    view.autoScales = true
    view.document = PDFDocument(url: url)
    return view
  }
  func updateNSView(_ view: PDFView, context: Context) {
    if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
  }
}

/// Shared local-file eligibility checks; directories, symlinks and nonregular files are not edited.
enum PreviewFileType {
  static func type(of url: URL) throws -> UTType {
    guard url.isFileURL else { throw PreviewTextError.localOnly }
    let values = try url.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true else {
      throw PreviewTextError.notRegular
    }
    return values.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
  }
}

enum PreviewTextError: LocalizedError {
  case localOnly, notRegular, tooLarge, unsupportedEncoding, binary, changed
  var errorDescription: String? {
    switch self {
    case .localOnly: "Only local files can be previewed."
    case .notRegular: "Select a regular file. Folders and symbolic links cannot be edited here."
    case .tooLarge: "Text editing is limited to 1 MiB. Open this file in another application."
    case .unsupportedEncoding: "Only UTF-8 and BOM-marked UTF-16 text can be edited safely."
    case .binary: "This file contains binary data and cannot be edited as text."
    case .changed:
      "The file changed outside this editor. Your edits have not been saved. Copy them elsewhere, then discard and reopen the preview."
    }
  }
}

/// A bounded, lossless text snapshot. Saves are coordinated, conflict checked and atomically
/// replaced using a copy of the original, retaining permissions, extended attributes and tags.
struct PreviewTextDocument {
  static let maximumBytes = 1_048_576
  let url: URL
  private(set) var text: String
  private var original: Data
  private let encoding: String.Encoding
  private let prefix: Data
  private var modified: Date?
  private var identity: UInt64?

  init(url: URL) throws {
    _ = try PreviewFileType.type(of: url)
    let data = try Self.readBounded(url)
    let encoding: String.Encoding
    let prefix: Data
    if data.starts(with: [0xFF, 0xFE]) {
      encoding = .utf16LittleEndian
      prefix = Data([0xFF, 0xFE])
    } else if data.starts(with: [0xFE, 0xFF]) {
      encoding = .utf16BigEndian
      prefix = Data([0xFE, 0xFF])
    } else {
      encoding = .utf8
      prefix = data.starts(with: [0xEF, 0xBB, 0xBF]) ? Data([0xEF, 0xBB, 0xBF]) : Data()
    }
    let body = data.dropFirst(prefix.count)
    guard let text = String(data: body, encoding: encoding),
      text.data(using: encoding) == Data(body)
    else { throw PreviewTextError.unsupportedEncoding }
    guard
      !text.unicodeScalars.contains(where: {
        ($0.value < 32 && ![9, 10, 13].contains($0.value)) || $0.value == 127
      })
    else { throw PreviewTextError.binary }
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    self.url = url
    self.original = data
    self.text = text
    self.encoding = encoding
    self.prefix = prefix
    self.modified = attrs[.modificationDate] as? Date
    self.identity = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value
  }

  // Internal staging hook allows deterministic conflict tests; production callers omit it.
  // File coordination serializes cooperating writers. Revalidation narrows, but cannot
  // eliminate, the final check/rename race with arbitrary uncoordinated POSIX writes.
  mutating func save(_ newText: String, beforePublication: (() throws -> Void)? = nil) throws {
    guard let body = newText.data(using: encoding, allowLossyConversion: false) else {
      throw PreviewTextError.unsupportedEncoding
    }
    let replacement = prefix + body
    guard replacement.count <= Self.maximumBytes else { throw PreviewTextError.tooLarge }
    let coordinator = NSFileCoordinator()
    var coordinationError: NSError?
    var writeError: Error?
    coordinator.coordinate(writingItemAt: url, options: [], error: &coordinationError) { target in
      do {
        _ = try PreviewFileType.type(of: target)
        let attrs = try FileManager.default.attributesOfItem(atPath: target.path)
        guard attrs[.modificationDate] as? Date == modified,
          (attrs[.systemFileNumber] as? NSNumber)?.uint64Value == identity,
          try Self.readBounded(target) == original
        else { throw PreviewTextError.changed }
        let manager = FileManager.default
        let temporary = target.deletingLastPathComponent()
          .appendingPathComponent(".fileterm-preview-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: temporary) }
        try manager.copyItem(at: target, to: temporary)
        let handle = try FileHandle(forWritingTo: temporary)
        do {
          try handle.truncate(atOffset: 0)
          try handle.write(contentsOf: replacement)
          try handle.synchronize()
          try handle.close()
        } catch {
          try? handle.close()
          throw error
        }
        try beforePublication?()
        // Staging can take time. Never publish based solely on the earlier check.
        let latest = try manager.attributesOfItem(atPath: target.path)
        guard latest[.modificationDate] as? Date == modified,
          (latest[.systemFileNumber] as? NSNumber)?.uint64Value == identity,
          try Self.readBounded(target) == original
        else { throw PreviewTextError.changed }
        _ = try PreviewFileType.type(of: target)
        // Retain the actual replaced file as a recoverable sibling, including in the
        // residual POSIX-writer race. Do not delete backups automatically.
        let backupName = ".\(target.lastPathComponent).fileterm-backup-\(UUID().uuidString)"
        _ = try manager.replaceItemAt(
          target, withItemAt: temporary, backupItemName: backupName,
          options: [.withoutDeletingBackupItem])
      } catch { writeError = error }
    }
    if let coordinationError { throw coordinationError }
    if let writeError { throw writeError }
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    original = replacement
    text = newText
    modified = attrs[.modificationDate] as? Date
    identity = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value
  }

  private static func readBounded(_ url: URL) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
    guard data.count <= maximumBytes else { throw PreviewTextError.tooLarge }
    return data
  }
}
