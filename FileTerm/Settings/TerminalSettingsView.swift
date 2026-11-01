import FileTermCore
import SwiftUI
import UniformTypeIdentifiers

struct TerminalSettingsView: View {
  @Bindable var settings: AppSettings

  /// A saved theme that no longer exists shows as System, which is what the terminal uses.
  private var colorTheme: Binding<String?> {
    Binding {
      TerminalTheme.theme(id: settings.terminal.themeID, in: settings.terminal.colorThemes)?.id
    } set: {
      settings.terminal.themeID = $0
    }
  }

  var body: some View {
    Form {
      Section("Appearance") {
        Picker("Color Theme", selection: colorTheme) {
          Text("System").tag(String?.none)
          ForEach(settings.terminal.colorThemes) { theme in
            Text(theme.name).tag(String?.some(theme.id))
          }
        }
        .accessibilityIdentifier("terminalColorTheme")
        HStack {
          Button("Import iTerm2 Color Scheme…", action: importColorScheme)
            .accessibilityIdentifier("terminalImportColorScheme")
          if let imported = settings.terminal.importedThemes?.first(where: {
            $0.id == settings.terminal.themeID
          }) {
            Button("Remove “\(imported.name)”") {
              settings.terminal.removeImportedTheme(id: imported.id)
            }
            .accessibilityIdentifier("terminalRemoveColorScheme")
          }
        }
        TextField("Font name", text: $settings.terminal.fontName)
        Stepper(value: $settings.terminal.fontSize, in: 8...48, step: 1) {
          Text("Font size: \(settings.terminal.fontSize, specifier: "%.0f") pt")
        }
        Picker("Cursor", selection: $settings.terminal.cursorStyle) {
          ForEach(TerminalCursorStyle.allCases) { style in
            Text(style.title).tag(style)
          }
        }
        Stepper(value: $settings.terminal.scrollbackLines, in: 0...100_000, step: 1_000) {
          Text("Scrollback: \(settings.terminal.scrollbackLines) lines")
        }
      }
      Section("Shell") {
        TextField("Shell path", text: $settings.terminal.shellPath)
          .accessibilityIdentifier("terminalShellPath")
        Toggle("Login shell", isOn: $settings.terminal.loginShell)
        Toggle("Interactive shell", isOn: $settings.terminal.interactiveShell)
        Text("Shell changes apply to new terminal sessions.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Section("Folder Synchronization") {
        Toggle("Enable shell integration", isOn: $settings.terminal.integrationEnabled)
          .accessibilityIdentifier("terminalIntegration")
        Picker("Follow", selection: $settings.terminal.followMode) {
          ForEach(TerminalFollowMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        Toggle(
          "Update browser when the shell changes directory", isOn: $settings.terminal.reverseSync
        )
        .accessibilityIdentifier("terminalReverseSync")
        Text("Synchronization requires shell integration. Unlinked terminals do not follow a pane.")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .accessibilityIdentifier("terminalSettings")
  }

  private func importColorScheme() {
    let panel = NSOpenPanel()
    panel.title = "Import an iTerm2 color scheme"
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [UTType(filenameExtension: "itermcolors")].compactMap { $0 }
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let name = url.deletingPathExtension().lastPathComponent
      settings.terminal.importTheme(
        try ITermColors.theme(from: try Data(contentsOf: url), name: name))
    } catch {
      NSAlert(error: error).runModal()
    }
  }
}
