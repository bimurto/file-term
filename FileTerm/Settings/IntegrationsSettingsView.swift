import FileTermCore
import SwiftUI

struct IntegrationsSettingsView: View {
  @Bindable var settings: AppSettings
  let cloudFiles: CloudFileActions
  var viewer = DefaultFileViewer.system
  private let bundleID = Bundle.main.bundleIdentifier ?? "com.fileterm.app"
  @State private var isDefaultViewer = false
  @State private var token = ""
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Default File Viewer").font(.headline)
      Toggle(
        "Use FileTerm for Reveal and Show in Finder",
        isOn: Binding(get: { isDefaultViewer }, set: { setDefaultViewer($0) })
      )
      .accessibilityIdentifier("defaultFileViewer")
      Text(
        "Other apps ask FileTerm to show files instead of Finder. Apps pick this up when they next "
          + "start. Turn it off to go back. This does not replace the system Open and Save "
          + "dialogs, which keep working as before."
      ).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      Text("Dropbox").font(.headline)
      SecureField(
        cloudFiles.hasDropboxToken ? "Token saved. Enter a new one to replace it." : "Access token",
        text: $token
      )
      .textFieldStyle(.roundedBorder).accessibilityIdentifier("dropboxToken")
      HStack {
        Button("Save Token") { saveToken(token) }.disabled(token.isEmpty)
        Button("Remove Token") { saveToken("") }.disabled(!cloudFiles.hasDropboxToken)
      }
      Text(
        "Copy Dropbox Link needs a token with the sharing.write scope, created in the Dropbox App "
          + "Console. It is stored in your keychain and sent only to Dropbox."
      ).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
    }.onAppear { isDefaultViewer = viewer.isDefault(bundleID) }
  }

  private func setDefaultViewer(_ enabled: Bool) {
    if enabled {
      settings.previousFileViewer = viewer.enable(bundleID) ?? settings.previousFileViewer
    } else {
      viewer.revert(bundleID, to: settings.previousFileViewer)
      settings.previousFileViewer = nil
    }
    isDefaultViewer = viewer.isDefault(bundleID)
  }

  private func saveToken(_ value: String) {
    do {
      try cloudFiles.setDropboxToken(value)
      token = ""
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
  }
}
