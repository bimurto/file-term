import AppKit
import FileTermCore
import Settings
import SwiftUI

@MainActor final class SettingsCoordinator {
  private let settings: AppSettings
  private let registry: () -> CommandRegistry
  private lazy var controller = SettingsWindowController(
    panes: SettingsCategory.allCases.map { category in
      Settings.Pane(
        identifier: Settings.PaneIdentifier(category.rawValue),
        title: category.rawValue,
        toolbarIcon: NSImage(
          systemSymbolName: category.symbol, accessibilityDescription: category.rawValue)!
      ) {
        SettingsCategoryView(
          category: category, settings: self.settings, registry: self.registry
        ) { [weak self] target in self?.show(target) }
      }
    },
    animated: false
  )

  init(settings: AppSettings, registry: @escaping () -> CommandRegistry) {
    self.settings = settings
    self.registry = registry
  }

  func show(_ category: SettingsCategory? = nil) {
    let target = category ?? SettingsCategory(rawValue: settings.selectedCategory) ?? .general
    settings.selectedCategory = target.rawValue
    controller.show(pane: Settings.PaneIdentifier(target.rawValue))
  }
}

private struct SettingsCategoryView: View {
  let category: SettingsCategory
  let settings: AppSettings
  let registry: () -> CommandRegistry
  let selectCategory: (SettingsCategory) -> Void

  private var paneHeight: CGFloat {
    switch category {
    case .general: 700
    case .terminal, .transfers: 640
    case .shortcuts, .tools, .editing, .tags, .themes: 480
    default: 320
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 4) {
        ForEach(SettingsCategory.allCases) { item in
          Button(item.rawValue) { selectCategory(item) }
            .buttonStyle(.bordered)
            .tint(item == category ? .accentColor : nil)
            .accessibilityIdentifier("settingsTab.\(item.rawValue)")
        }
      }
      Text(category.rawValue).font(.title2).fontWeight(.semibold)
      if category == .general {
        GeneralSettingsView(settings: settings, registry: registry())
      } else if category == .shortcuts {
        ShortcutsSettingsView(registry: registry())
      } else if category == .transfers {
        TransfersSettingsView(settings: settings)
      } else if category == .terminal {
        TerminalSettingsView(settings: settings)
      } else if category == .tools {
        ToolsSettingsView(settings: settings)
      } else if category == .editing {
        EditingSettingsView(settings: settings)
      } else if category == .tags {
        TagsSettingsView(settings: settings)
      } else if category == .themes {
        ThemesSettingsView(settings: settings)
      }
      Spacer()
    }
    .padding(28)
    .frame(
      width: 660,
      height: paneHeight,
      alignment: .topLeading
    )
    .onAppear { settings.selectedCategory = category.rawValue }
  }
}

private struct TransfersSettingsView: View {
  @Bindable var settings: AppSettings

  var body: some View {
    Form {
      Section("Conflicts") {
        policyPicker(
          "Existing files", selection: $settings.transfers.replacePolicy,
          choices: [.ask, .replace, .replaceOlder, .keepBoth, .skip, .stop], id: "replacePolicy")
        policyPicker(
          "Existing folders", selection: $settings.transfers.mergePolicy,
          choices: [.ask, .merge, .replace, .keepBoth, .skip, .stop], id: "mergePolicy")
        policyPicker(
          "Resume policy (future capability)", selection: $settings.transfers.resumePolicy,
          choices: [.ask, .replace, .keepBoth, .skip, .stop], id: "resumePolicy"
        )
        .disabled(true)
        Text(
          "Pause and resume work in this session. Resuming partial files after restarting is not supported."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section("Bandwidth") {
        bandwidth(
          "upload", enabled: $settings.transfers.limitUpload,
          value: $settings.transfers.uploadBytesPerSecond)
        bandwidth(
          "download", enabled: $settings.transfers.limitDownload,
          value: $settings.transfers.downloadBytesPerSecond)
        Text(
          "Upload and download limits apply to directional transfers. Local copies are not rate-limited."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Section("Reliability") {
        Toggle(
          "Automatically retry temporary failures", isOn: $settings.transfers.automaticallyRetry
        )
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("automaticallyRetry")
        Stepper(
          "Maximum retries: \(settings.transfers.maximumRetries)",
          value: $settings.transfers.maximumRetries, in: 0...100
        )
        .disabled(!settings.transfers.automaticallyRetry).accessibilityIdentifier("maximumRetries")
        Stepper(
          "Concurrent operations: \(settings.transfers.maximumConcurrent)",
          value: $settings.transfers.maximumConcurrent, in: 1...64
        )
        .accessibilityIdentifier("maximumConcurrent")
        Picker("Verify copies", selection: $settings.transfers.verification) {
          Text("None").tag(CopyVerification.none)
          Text("File size").tag(CopyVerification.size)
          Text("Checksum").tag(CopyVerification.checksum)
        }.accessibilityIdentifier("copyVerification")
      }
    }.formStyle(.grouped).accessibilityIdentifier("transfersSettings")
  }

  private func policyPicker(
    _ title: String, selection: Binding<TransferPolicy>,
    choices: [TransferPolicy], id: String
  ) -> some View {
    Picker(title, selection: selection) {
      ForEach(choices, id: \.self) { policy in
        Text(policyTitle(policy)).tag(policy)
      }
    }.accessibilityIdentifier(id)
  }

  private func policyTitle(_ policy: TransferPolicy) -> String {
    switch policy {
    case .ask: "Ask"
    case .replace: "Replace"
    case .replaceOlder: "Replace Older"
    case .keepBoth: "Keep Both"
    case .skip: "Skip"
    case .stop: "Stop"
    case .merge: "Merge"
    }
  }

  private func bandwidth(_ direction: String, enabled: Binding<Bool>, value: Binding<Int64>)
    -> some View
  {
    HStack {
      Toggle("Limit \(direction)", isOn: enabled)
        .accessibilityIdentifier("limit\(direction.capitalized)")
      Spacer()
      TextField(
        "Bytes/s",
        value: Binding(
          get: { value.wrappedValue },
          set: { value.wrappedValue = max(1, $0) }), format: .number.grouping(.never)
      )
      .frame(width: 110).disabled(!enabled.wrappedValue)
      .accessibilityLabel("\(direction.capitalized) bytes per second")
      .accessibilityIdentifier("\(direction)BytesPerSecond")
      Text("Bytes/s").foregroundStyle(.secondary)
    }
  }
}

private struct GeneralSettingsView: View {
  @Bindable var settings: AppSettings
  let registry: CommandRegistry
  @State private var directory = ""
  @State private var error: String?
  @State private var isSaving = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Toggle("Restore windows and tabs on startup", isOn: $settings.workspace.restoreWindows)
          .accessibilityIdentifier("restoreSession")
        Text("Starting Directory").font(.headline)
        TextField("Absolute folder path", text: $directory).textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("startingDirectory")
          .onSubmit { saveDirectory() }
        HStack {
          Button("Set Starting Directory") { saveDirectory() }.disabled(isSaving)
          Text("Used by new windows and when session restoration is off.").font(.caption)
            .foregroundStyle(.secondary)
        }
        Picker("Open remote connections in", selection: $settings.connections.remotePlacement) {
          ForEach(RemotePanePlacement.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .accessibilityIdentifier("remotePlacement")
        Text("Archives").font(.headline)
        Toggle("Handle archives with FileTerm", isOn: $settings.handleArchives)
          .accessibilityIdentifier("handleArchives")
        Toggle("Treat archives as folders", isOn: $settings.archivesAsFolders)
          .disabled(!settings.handleArchives)
          .accessibilityIdentifier("archivesAsFolders")
        Text("Double-clicking an archive extracts it next to the archive, or opens it as a folder.")
          .font(.caption).foregroundStyle(.secondary)
        Toggle("Detect application when deleting", isOn: $settings.detectAppOnDelete)
          .accessibilityIdentifier("detectAppOnDelete")
        Text("Moving a .app to the Trash first lists its preferences, caches and support folders.")
          .font(.caption).foregroundStyle(.secondary)
        Picker("Compare tool", selection: $settings.compareTool) {
          ForEach(CompareTool.allCases, id: \.self) {
            Text($0.isInstalled ? $0.title : $0.title + " (not installed)").tag($0)
          }
        }
        .accessibilityIdentifier("compareTool")
        Picker("Terminal application", selection: $settings.terminalApplication) {
          ForEach(TerminalApplication.allCases, id: \.self) {
            Text($0.isInstalled ? $0.title : $0.title + " (not installed)").tag($0)
          }
        }
        .accessibilityIdentifier("terminalApplication")
        Text("Used by File › Open in Terminal. The built-in terminal panel is separate.")
          .font(.caption).foregroundStyle(.secondary)
        Toggle("Sync Favorites to iCloud", isOn: $settings.syncFavoritesToICloud)
          .accessibilityIdentifier("syncFavorites")
        Text(
          "Syncs only the favorites list, never file contents. Syncing is not available in this build; "
            + "the setting is saved for when it is."
        ).font(.caption).foregroundStyle(.secondary)
        Toggle("Ask for confirmation for drag operations", isOn: $settings.askBeforeDrag)
          .accessibilityIdentifier("askBeforeDrag")
        Text("Dropping items on a pane asks whether to copy or move them.")
          .font(.caption).foregroundStyle(.secondary)
        Text("Updates").font(.headline)
        Toggle("Automatically check for updates", isOn: $settings.automaticUpdateChecks)
          .accessibilityIdentifier("automaticUpdateChecks")
        Button("Check for Updates Now") { registry.execute("app.checkForUpdates") }
          .accessibilityIdentifier("checkForUpdatesNow")
        Text("Current: " + settings.workspace.startingDirectory).font(.caption).foregroundStyle(
          .secondary)
        if let error { Text(error).font(.caption).foregroundStyle(.red) }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.onAppear { directory = settings.workspace.startingDirectory }
  }

  private func saveDirectory() {
    guard !isSaving else { return }
    isSaving = true
    Task {
      defer { isSaving = false }
      do {
        let location = try await LocalFileSystemProvider().resolveFolderPath(directory)
        settings.workspace.startingDirectory = location.path
        directory = location.path
        error = nil
      } catch { self.error = error.localizedDescription }
    }
  }
}

private struct ShortcutsSettingsView: View {
  let registry: CommandRegistry
  @State private var filter = ""
  @State private var revision = 0
  @State private var editing: String?
  @State private var pending: Shortcut?
  @State private var conflicts: [AppCommand] = []

  private var commands: [AppCommand] {
    registry.commands.filter { command in
      !command.id.hasPrefix("go.recent") && !command.id.hasPrefix("go.connections")
        && (command.id == "go.favorites.manage" || !command.id.hasPrefix("go.favorites."))
        && (filter.isEmpty
          || command.title.localizedCaseInsensitiveContains(filter)
          || command.menuPath.joined(separator: " ").localizedCaseInsensitiveContains(filter)
          || (registry.effectiveShortcut(for: command.id)?.display ?? "")
            .localizedCaseInsensitiveContains(filter))
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("Search commands or shortcuts", text: $filter)
          .textFieldStyle(.roundedBorder).accessibilityIdentifier("shortcutSearch")
        Button("Restore Defaults") {
          registry.restoreDefaultShortcuts()
          editing = nil
          conflicts = []
          revision += 1
        }.accessibilityIdentifier("restoreShortcutDefaults")
      }
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 6) {
          ForEach(commands) { command in
            row(command)
            Divider()
          }
        }
        .padding(.vertical, 4)
      }
      .accessibilityIdentifier("shortcutList").id(revision)
      if let editing, let command = registry.command(editing) {
        editor(command)
      }
    }
  }

  private func row(_ command: AppCommand) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 1) {
        Text(command.title)
        Text(command.menuPath.joined(separator: " › ")).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Text(registry.effectiveShortcut(for: command.id)?.display ?? "—")
        .monospaced().foregroundStyle(
          registry.shortcutMap.isCustomized(command.id) ? Color.accentColor : .secondary
        )
        .accessibilityIdentifier("shortcut.\(command.id)")
      Button("Edit") {
        editing = command.id
        pending = nil
        conflicts = []
      }.accessibilityIdentifier("editShortcut.\(command.id)")
    }
    .accessibilityElement(children: .contain)
  }

  private func editor(_ command: AppCommand) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Divider()
      HStack {
        Text("Shortcut for “\(command.title)”:").font(.headline)
        ShortcutRecorder { shortcut in
          pending = shortcut
          conflicts = registry.shortcutConflicts(for: shortcut, excluding: command.id)
          if conflicts.isEmpty {
            registry.assignShortcut(shortcut, to: command.id)
            revision += 1
          }
        }
        .frame(width: 150, height: 24)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Shortcut recorder")
        .accessibilityIdentifier("shortcutRecorder")
      }
      Text("Click the field, then press the new key combination.").font(.caption)
        .foregroundStyle(.secondary)
      if let pending, !conflicts.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Label(
            "\(pending.display) is already used by "
              + conflicts.map(\.title).joined(separator: ", ") + ".",
            systemImage: "exclamationmark.triangle.fill"
          ).foregroundStyle(.orange).accessibilityIdentifier("shortcutConflict")
          HStack {
            Button("Reassign") {
              for other in conflicts { registry.assignShortcut(nil, to: other.id) }
              registry.assignShortcut(pending, to: command.id)
              conflicts = []
              revision += 1
            }.accessibilityIdentifier("reassignShortcut")
            Button("Cancel") {
              self.pending = nil
              conflicts = []
            }
          }
        }
      }
      HStack {
        Button("Clear") {
          registry.assignShortcut(nil, to: command.id)
          conflicts = []
          revision += 1
        }
        Button("Restore Default") {
          var map = registry.shortcutMap
          map.restoreDefault(command.id)
          if let value = map.effective(for: command.id) {
            registry.assignShortcut(value, to: command.id)
          } else {
            registry.assignShortcut(nil, to: command.id)
          }
          conflicts = []
          revision += 1
        }
        Spacer()
        Button("Done") {
          editing = nil
          conflicts = []
        }
      }
    }
  }
}

/// Captures a key combination. Handles ⌘-combos in `performKeyEquivalent` so the menu bar does
/// not run them while recording.
private struct ShortcutRecorder: NSViewRepresentable {
  let onRecord: (Shortcut) -> Void

  func makeNSView(context: Context) -> RecorderView {
    let view = RecorderView()
    view.onRecord = onRecord
    return view
  }

  func updateNSView(_ view: RecorderView, context: Context) { view.onRecord = onRecord }

  final class RecorderView: NSView {
    var onRecord: ((Shortcut) -> Void)?
    private var recording = false { didSet { needsDisplay = true } }
    private var last: String = "Click to record"

    override init(frame: NSRect) {
      super.init(frame: frame)
      setAccessibilityElement(true)
      setAccessibilityRole(.button)
      setAccessibilityLabel("Shortcut recorder")
      setAccessibilityIdentifier("shortcutRecorder")
    }

    required init?(coder: NSCoder) {
      super.init(coder: coder)
      setAccessibilityElement(true)
      setAccessibilityRole(.button)
      setAccessibilityLabel("Shortcut recorder")
      setAccessibilityIdentifier("shortcutRecorder")
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Shortcut recorder" }
    override func accessibilityIdentifier() -> String { "shortcutRecorder" }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
      recording = true
      return true
    }
    override func resignFirstResponder() -> Bool {
      recording = false
      return true
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
      guard recording, window?.firstResponder === self else { return false }
      capture(event)
      return true
    }
    override func keyDown(with event: NSEvent) {
      guard recording else { return super.keyDown(with: event) }
      capture(event)
    }

    private func capture(_ event: NSEvent) {
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      let key: String
      if event.keyCode == 53 {
        key = Shortcut.escape
      } else if event.keyCode == 36 {
        key = "\r"
      } else if let characters = event.charactersIgnoringModifiers?.lowercased(),
        let first = characters.first, !first.isNewline
      {
        key = String(first)
      } else {
        return
      }
      let shortcut = Shortcut(
        key: key, command: flags.contains(.command), shift: flags.contains(.shift),
        option: flags.contains(.option), control: flags.contains(.control))
      last = shortcut.display
      onRecord?(shortcut)
      needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
      let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
      (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
      path.stroke()
      let text = recording ? "Press shortcut…" : last
      let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor,
      ]
      let size = (text as NSString).size(withAttributes: attributes)
      (text as NSString).draw(
        at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
        withAttributes: attributes)
    }
  }
}
