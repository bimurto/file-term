import AppKit
import FileTermCore
import Observation
import SwiftUI

@MainActor @Observable final class ConnectionFormModel: Identifiable {
  let id = UUID()
  var profile: ConnectionProfile
  var password = ""
  var showAdvanced = false
  var errorMessage: String?
  var isWorking = false
  let isEditing: Bool
  let browser: BrowserModel
  private let coordinator: ConnectionCoordinator

  init(
    profile: ConnectionProfile = ConnectionProfile(kind: .sftp), isEditing: Bool = false,
    coordinator: ConnectionCoordinator, browser: BrowserModel
  ) {
    self.profile = profile
    self.isEditing = isEditing
    self.coordinator = coordinator
    self.browser = browser
  }

  /// Opening or editing the form never connects; only this method does.
  func connect() async -> Bool {
    guard !isWorking else { return false }
    isWorking = true
    defer { isWorking = false }
    do {
      if profile.isFavorite || isEditing { try coordinator.save(profile, password: password) }
      try await coordinator.connectAndReveal(profile, password: password, in: browser)
      errorMessage = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func save() -> Bool {
    // Only favorites appear in Go › Connections, so a connection saved here must be one.
    if !isEditing { profile.isFavorite = true }
    do {
      try coordinator.save(profile, password: password)
      errorMessage = nil
      return true
    } catch {
      errorMessage = error.localizedDescription
      return false
    }
  }

  func delete() {
    coordinator.remove(profile)
  }
}

struct ConnectionFormSheet: View {
  @Bindable var model: ConnectionFormModel
  @Environment(\.dismiss) private var dismiss

  private static let colors = ["", "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"]

  private var kind: ConnectionKind { model.profile.kind }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Connect to Server").font(.headline)
      Form {
        Picker("Protocol", selection: $model.profile.kind) {
          ForEach(ConnectionKind.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .accessibilityIdentifier("connectionProtocol")
        .onChange(of: model.profile.kind) { _, _ in model.profile.port = nil }
        if kind.usesServer {
          TextField(
            kind.serverTitle, text: $model.profile.server,
            prompt: Text(kind == .s3 ? "s3.amazonaws.com (default)" : "")
          )
          .accessibilityIdentifier("connectionServer")
        }
        if kind.usesCredentials {
          TextField(kind.usernameTitle, text: $model.profile.username)
            .accessibilityIdentifier("connectionUsername")
          SecureField(
            kind.passwordTitle, text: $model.password,
            prompt: Text(
              model.isEditing
                ? "Leave empty to keep the saved password"
                : kind.isSFTP ? "Password or key passphrase" : "")
          )
          .accessibilityIdentifier("connectionPassword")
        }
        Toggle("Add to Favorites", isOn: $model.profile.isFavorite)
        DisclosureGroup("Show Advanced", isExpanded: $model.showAdvanced) {
          ForEach(kind.advancedFields, id: \.self) { advancedField($0) }
        }
        .accessibilityIdentifier("connectionAdvanced")
        if case .plannedIn(let ticket) = kind.availability {
          Label("\(kind.title) arrives with M08 \(ticket).", systemImage: "clock")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      .formStyle(.grouped)
      if let message = model.errorMessage {
        Text(message).font(.caption).foregroundStyle(.red)
          .accessibilityIdentifier("connectionError")
      }
      HStack {
        if model.isEditing {
          Button("Delete", role: .destructive) {
            model.delete()
            dismiss()
          }
        }
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Save") { if model.save() { dismiss() } }
          .disabled(kind.usesServer && kind != .s3 && model.profile.server.isEmpty)
          .accessibilityIdentifier("connectionSave")
        Button("Connect") {
          Task { if await model.connect() { dismiss() } }
        }
        .keyboardShortcut(.defaultAction).disabled(model.isWorking)
        .accessibilityIdentifier("connectionConnect")
      }
    }
    .padding(16).frame(width: 460)
  }

  private func chooseKey() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.showsHiddenFiles = true
    panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".ssh")
    if panel.runModal() == .OK, let url = panel.url {
      model.profile.privateKeyPath = url.path
    }
  }

  @ViewBuilder private func advancedField(_ field: ConnectionField) -> some View {
    switch field {
    case .port:
      TextField(
        "Port", value: $model.profile.port, format: .number.grouping(.never),
        prompt: Text(kind.defaultPort.map(String.init) ?? "Default"))
    case .region:
      TextField("Region", text: $model.profile.region, prompt: Text(model.profile.resolvedRegion))
    case .path:
      TextField(
        kind.isObjectStore ? "Bucket / Prefix" : "Path", text: $model.profile.path)
    case .localPath: TextField("Local Path", text: $model.profile.localPath)
    case .baseURL: TextField("Base URL", text: $model.profile.baseURL)
    case .textEncoding:
      Picker("Text Encoding", selection: $model.profile.textEncoding) {
        ForEach(TextEncoding.names, id: \.self) { Text($0).tag($0) }
      }
    case .ftpMode:
      Picker("Transfer Mode", selection: $model.profile.ftpActiveMode) {
        Text("Passive").tag(false)
        Text("Active").tag(true)
      }
    case .allowInvalidCertificate:
      Toggle("Allow invalid certificate", isOn: $model.profile.allowInvalidCertificate)
    case .privateKey:
      HStack {
        TextField(
          "Private Key", text: $model.profile.privateKeyPath,
          prompt: Text("Agent and default keys"))
        Button("Choose…") { chooseKey() }
      }
    case .note: TextField("Note", text: $model.profile.note)
    case .colorLabel:
      Picker("Color Label", selection: $model.profile.colorLabel) {
        ForEach(Self.colors, id: \.self) { Text($0.isEmpty ? "None" : $0).tag($0) }
      }
    }
  }
}
