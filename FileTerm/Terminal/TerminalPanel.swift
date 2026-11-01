import AppKit
import SwiftUI

struct TerminalPanel: View {
  @Bindable var workspace: TerminalWorkspace

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      toolbar
      Divider()
      if let session = workspace.currentSession {
        TerminalContainer(session: session)
          .id(ObjectIdentifier(session))
          .accessibilityIdentifier("terminalContent")
          .overlay(alignment: .bottomLeading) {
            if case .failed(let message) = session.status {
              endedNotice(message)
            } else if case .exited(let code) = session.status {
              endedNotice("Shell exited" + (code.map { " (\($0))" } ?? ""))
            }
          }
      } else {
        ContentUnavailableView(
          "Terminal", systemImage: "terminal",
          description: Text("Open the terminal to start a shell."))
      }
    }
    .background(Color(nsColor: .textBackgroundColor))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("terminalPanel")
    .background {
      GeometryReader { geometry in
        Color.clear
          .onChange(of: geometry.size) { _, size in
            let extent = workspace.panel.dock == .bottom ? size.height : size.width
            if extent.isFinite, extent >= 100, abs(workspace.panel.size - extent) > 1 {
              workspace.panel.size = extent
            }
          }
      }
    }
  }

  private func endedNotice(_ message: String) -> some View {
    HStack(spacing: 10) {
      Text(message).font(.callout).accessibilityIdentifier("terminalEnded")
      Button("New Shell") { workspace.startNewShell() }
        .controlSize(.small).accessibilityIdentifier("terminalNewShell")
    }
    .padding(10).background(.regularMaterial)
  }

  private var header: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 10) {
        title
        Spacer(minLength: 4)
        controls
      }
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          title
          Spacer()
          closeButton
        }
        HStack(spacing: 8) {
          compactControls
          Spacer(minLength: 0)
        }
      }
    }
    .font(.caption)
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(.bar)
  }

  private var title: some View {
    VStack(alignment: .leading, spacing: 2) {
      Label(workspace.linkedPaneTitle, systemImage: "terminal")
        .font(.caption.weight(.semibold)).lineLimit(1)
      Text(workspace.status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        .accessibilityIdentifier("terminalStatus")
    }
    .accessibilityElement(children: .combine)
  }

  private var controls: some View {
    Group {
      compactControls
      closeButton
    }
  }

  private var compactControls: some View {
    Group {
      Picker("Follow", selection: $workspace.followMode) {
        ForEach(TerminalFollowMode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .labelsHidden().fixedSize()
      .help("Choose which pane’s selected tab is shown")
      .accessibilityIdentifier("terminalFollowMode")
      Menu {
        Toggle("Reverse Sync", isOn: $workspace.reverseSync)
        Picker("Dock", selection: $workspace.panel.dock) {
          ForEach(TerminalDock.allCases) { dock in Text(dock.title).tag(dock) }
        }
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton).fixedSize()
      .help("Terminal options").accessibilityLabel("Terminal options")
      Button {
        workspace.syncNow()
      } label: {
        Image(systemName: "arrow.triangle.2.circlepath")
      }
      .disabled(!workspace.canSyncNow)
      .help("Sync to pane directory when the shell is idle and input is empty")
      .accessibilityLabel("Sync terminal now")
    }
    .controlSize(.small)
  }

  private var toolbar: some View {
    HStack(spacing: 6) {
      toolbarButton(
        .link, symbol: workspace.isLinked ? "lock.fill" : "lock.open",
        title: workspace.isLinked ? "Unlink Terminal" : "Link Terminal"
      ) { workspace.toggleLinked() }
      toolbarButton(.reveal, symbol: "folder", title: "Reveal Directory in Pane") {
        workspace.revealDirectory()
      }
      Divider().frame(height: 14).padding(.horizontal, 3)
      toolbarButton(.openSSH, symbol: "network", title: "Open SSH Session") {
        workspace.openSSHSession()
      }
      toolbarButton(.insertSelection, symbol: "text.insert", title: "Insert Selected Paths") {
        workspace.insertSelection()
      }
      Divider().frame(height: 14).padding(.horizontal, 3)
      toolbarButton(.clear, symbol: "eraser", title: "Clear Terminal") {
        workspace.perform(command: "terminal.clear")
      }
      toolbarButton(.find, symbol: "magnifyingglass", title: "Find in Terminal") {
        workspace.perform(command: "terminal.find")
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(.bar)
    .accessibilityIdentifier("terminalToolbar")
  }

  private func toolbarButton(
    _ action: TerminalAction, symbol: String, title: String, perform: @escaping () -> Void
  ) -> some View {
    let reason = workspace.disabledReason(for: action)
    return Button(action: perform) {
      Image(systemName: symbol).frame(width: 20, height: 18)
    }
    .buttonStyle(.borderless)
    .disabled(reason != nil)
    .help(reason ?? title)
    .accessibilityLabel(title)
    .accessibilityIdentifier("terminalToolbar.\(action.rawValue)")
  }

  private var closeButton: some View {
    Button {
      workspace.perform(command: "terminal.close")
    } label: {
      Image(systemName: "xmark")
    }
    .buttonStyle(.borderless)
    .help("Close terminal and terminate its sessions")
    .accessibilityLabel("Close terminal")
    .accessibilityIdentifier("terminalClose")
  }
}

/// Only this lightweight host is replaced when switching tabs. The session retains the renderer
/// and process, preserving scrollback, selection and shell input while its tab is offscreen.
@MainActor private struct TerminalContainer: NSViewRepresentable {
  let session: TerminalSession

  func makeNSView(context: Context) -> TerminalHostView {
    let host = TerminalHostView()
    host.attach(session)
    return host
  }

  func updateNSView(_ nsView: TerminalHostView, context: Context) { nsView.attach(session) }

  static func dismantleNSView(_ nsView: TerminalHostView, coordinator: ()) {
    nsView.detach()
  }
}

@MainActor private final class TerminalHostView: NSView {
  private weak var session: TerminalSession?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    registerForDraggedTypes([.fileURL])
  }

  required init?(coder: NSCoder) { nil }

  func attach(_ session: TerminalSession) {
    guard self.session !== session || session.view.superview !== self else { return }
    detach()
    self.session = session
    let terminal = session.view
    terminal.removeFromSuperview()
    terminal.translatesAutoresizingMaskIntoConstraints = false
    addSubview(terminal)
    NSLayoutConstraint.activate([
      terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
      terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
      terminal.topAnchor.constraint(equalTo: topAnchor),
      terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  func detach() {
    if session?.view.superview === self { session?.view.removeFromSuperview() }
    session = nil
  }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    fileURLs(from: sender).isEmpty ? [] : .copy
  }

  override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    !fileURLs(from: sender).isEmpty
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    let paths = fileURLs(from: sender).map(\.path)
    guard let session, !paths.isEmpty else { return false }
    // Paste arguments only, never a newline or a command submission.
    session.insert(paths.map(session.quotePath).joined(separator: " ") + " ")
    return true
  }

  private func fileURLs(from sender: any NSDraggingInfo) -> [URL] {
    (sender.draggingPasteboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
      .filter(\.isFileURL)
  }
}
