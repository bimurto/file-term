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
        GeneralSettingsView(settings: settings)
      } else if category == .shortcuts {
        ShortcutsSettingsView(registry: registry())
      } else if category == .terminal {
        TerminalSettingsView(settings: settings)
      } else {
        Text("Settings for \(category.rawValue.lowercased()) will appear here.").foregroundStyle(
          .secondary)
      }
      Spacer()
    }
    .padding(28)
    .frame(
      width: 660, height: category == .terminal ? 640 : (category == .shortcuts ? 480 : 320),
      alignment: .topLeading
    )
    .onAppear { settings.selectedCategory = category.rawValue }
  }
}

private struct GeneralSettingsView: View {
  @Bindable var settings: AppSettings
  @State private var directory = ""
  @State private var error: String?
  @State private var isSaving = false

  var body: some View {
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
      Text("Current: " + settings.workspace.startingDirectory).font(.caption).foregroundStyle(
        .secondary)
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
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
