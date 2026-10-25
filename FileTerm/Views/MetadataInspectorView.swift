import AppKit
import SwiftUI

/// Standalone inspector. Each metadata section has its own explicit apply action;
/// preview document saving is owned by FilePreviewContentView.
struct MetadataInspectorView: View {
  let url: URL
  var onChange: () -> Void = {}
  @State private var service = FileMetadataService()
  @State private var metadata: FileMetadata?
  @State private var owners: [MetadataAccount] = []
  @State private var groups: [MetadataAccount] = []
  @State private var applications: [URL] = []
  @State private var selectedApplication: URL?
  @State private var currentApplication: URL?
  @State private var tags = ""
  @State private var comment = ""
  @State private var octal = ""
  @State private var ownerID: UInt32 = 0
  @State private var groupID: UInt32 = 0
  @State private var errorMessage: String?
  @State private var loading = true
  @State private var busy = false
  @State private var generation = UUID()
  @State private var pendingSecurityChange: FileMetadataService.Change?
  @State private var confirmSecurity = false
  @State private var confirmChangeAll = false

  init(url: URL, onChange: @escaping () -> Void = {}) {
    self.url = url
    self.onChange = onChange
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text(url.lastPathComponent).font(.headline).lineLimit(2)
          Spacer()
          Button {
            Task { await reload() }
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .help("Refresh metadata").disabled(busy)
        }
        // Stable identity lets the text editor guard unsaved changes as selection changes.
        FilePreviewContentView(url: url).frame(minHeight: 180, maxHeight: 320)
        Divider()
        if loading { ProgressView("Loading metadata…") }
        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle")
            .foregroundStyle(.red).font(.callout).textSelection(.enabled)
        }
        if let item = metadata, item.url == url {
          general(item)
          Divider()
          editableMetadata(item)
            .disabled(busy || item.isSymbolicLink)
          if item.isSymbolicLink {
            Text(
              "Symbolic link: metadata describes the link itself. Editing and embedded preview are disabled; inspect its target separately."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        }
      }.padding(16)
    }
    .frame(minWidth: 300)
    .task(id: url) { await reload() }
    .confirmationDialog(
      "Apply security change?", isPresented: $confirmSecurity, titleVisibility: .visible
    ) {
      Button("Apply Change", role: .destructive) {
        if let change = pendingSecurityChange { apply(change) }
        pendingSecurityChange = nil
      }
      Button("Cancel", role: .cancel) { pendingSecurityChange = nil }
    } message: {
      Text(
        "Changes apply only to this item, not its contents. Permissions or ownership changes can remove your access. ACLs are not changed; macOS may refuse changes without authorization."
      )
    }
    .confirmationDialog(
      "Change the default application for all files of this type?", isPresented: $confirmChangeAll,
      titleVisibility: .visible
    ) {
      Button("Change All") { changeApplication(all: true) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "This changes the system-wide default for the item’s content type, not just its filename extension. macOS may ask for consent."
      )
    }
  }

  private func general(_ item: FileMetadata) -> some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
      detail("Path", item.url.path)
      detail("Size", "\(item.bytes.formatted()) bytes")
      detail("Extension", item.url.pathExtension.isEmpty ? "None" : item.url.pathExtension)
      detail("Created", item.created.formatted(date: .abbreviated, time: .standard))
      detail("Modified", item.modified.formatted(date: .abbreviated, time: .standard))
      detail("Accessed", item.accessed.formatted(date: .abbreviated, time: .standard))
      detail("Hidden", item.hidden ? "Yes" : "No")
      detail("Owner", "\(item.owner) (\(item.ownerID))")
      detail("Group", "\(item.group) (\(item.groupID))")
      detail("Permissions", String(format: "%04o", Int(item.mode)))
    }.font(.callout)
  }

  private func detail(_ title: String, _ value: String) -> some View {
    GridRow(alignment: .top) {
      Text(title).foregroundStyle(.secondary)
      Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func editableMetadata(_ item: FileMetadata) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      GroupBox("Tags") {
        VStack(alignment: .leading, spacing: 8) {
          TextField("Tags separated by commas", text: $tags)
            .accessibilityIdentifier("inspectorTags")
          Button("Apply Tags") {
            let names = tags.split(separator: ",").map {
              $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            // Preserve Finder color suffixes for existing tags.
            let values = Array(NSOrderedSet(array: names)) as? [String] ?? names
            apply(
              .tags(
                values.map { name in
                  item.tags.first { $0.components(separatedBy: "\n").first == name } ?? name
                }))
          }
          Text(
            "Existing tag colors are preserved. Use Finder to choose colors; commas separate tag names here."
          )
          .font(.caption).foregroundStyle(.secondary)
        }.padding(4)
      }.disabled(item.commentDisabledReason != nil)
      GroupBox("Comments") {
        VStack(alignment: .leading, spacing: 8) {
          TextEditor(text: $comment).frame(height: 72)
            .accessibilityLabel("Finder comment").accessibilityIdentifier("inspectorComment")
            .disabled(item.commentDisabledReason != nil)
          Button("Apply Comment") { apply(.comment(comment)) }
            .disabled(item.commentDisabledReason != nil)
          Text(
            item.commentDisabledReason
              ?? "Stored as Finder metadata. Spotlight and other apps may refresh later."
          )
          .font(.caption).foregroundStyle(.secondary)
        }.padding(4)
      }
      GroupBox("Sharing & Permissions") {
        VStack(alignment: .leading, spacing: 10) {
          TextField("Octal mode", text: $octal)
            .accessibilityIdentifier("inspectorOctal")
          permissionRow("Owner", shift: 6)
          permissionRow("Group", shift: 3)
          permissionRow("Everyone", shift: 0)
          Text(
            "Octal supports special bits (setuid, setgid, sticky). Checkboxes edit only rwx bits. ACLs may grant additional access."
          )
          .font(.caption).foregroundStyle(.secondary)
          Button("Apply Permissions…") {
            do {
              requestSecurity(.permissions(try FileMetadataService.permissions(from: octal)))
            } catch { errorMessage = error.localizedDescription }
          }
          Picker("Owner", selection: $ownerID) {
            Text("\(item.owner) (\(item.ownerID))").tag(item.ownerID)
            ForEach(owners.filter { $0.id != item.ownerID }) { Text($0.name).tag($0.id) }
          }
          Button("Apply Owner…") { requestSecurity(.owner(ownerID)) }.disabled(
            ownerID == item.ownerID)
          Picker("Group", selection: $groupID) {
            Text("\(item.group) (\(item.groupID))").tag(item.groupID)
            ForEach(groups.filter { $0.id != item.groupID }) { Text($0.name).tag($0.id) }
          }
          Button("Apply Group…") { requestSecurity(.group(groupID)) }.disabled(
            groupID == item.groupID)
          Toggle(
            "Locked", isOn: Binding(get: { item.locked }, set: { requestSecurity(.locked($0)) }))
          Text(
            "No administrator elevation or recursive changes. Read access is required to edit metadata safely."
          )
          .font(.caption).foregroundStyle(.secondary)
        }.padding(4)
      }
      GroupBox("Open with") {
        VStack(alignment: .leading, spacing: 8) {
          Picker("Application", selection: $selectedApplication) {
            Text("Choose application").tag(nil as URL?)
            ForEach(applications, id: \.self) { application in
              Text(application.deletingPathExtension().lastPathComponent).tag(Optional(application))
            }
          }
          HStack {
            Button("Other…") { chooseApplication() }
            Button("Apply to This File") { changeApplication(all: false) }
              .disabled(selectedApplication == nil || selectedApplication == currentApplication)
          }
          Button("Change All…") { confirmChangeAll = true }.disabled(selectedApplication == nil)
          Text(
            "This File changes only this item. Change All changes the default for its content type."
          )
          .font(.caption).foregroundStyle(.secondary)
        }.padding(4)
      }
    }
  }

  private func permissionRow(_ name: String, shift: Int) -> some View {
    HStack {
      Text(name).frame(width: 70, alignment: .leading)
      ForEach(Array(zip(["Read", "Write", "Execute"], [4, 2, 1])), id: \.0) { label, bit in
        Toggle(
          label,
          isOn: Binding(
            get: {
              ((try? FileMetadataService.permissions(from: octal)) ?? 0) & UInt16(bit << shift) != 0
            },
            set: { enabled in
              let mask = UInt16(bit << shift)
              let mode = (try? FileMetadataService.permissions(from: octal)) ?? metadata?.mode ?? 0
              octal = String(format: "%04o", Int(enabled ? mode | mask : mode & ~mask))
            }
          )
        ).toggleStyle(.checkbox).accessibilityLabel("\(name) \(label)")
      }
    }.font(.caption)
  }

  private func requestSecurity(_ change: FileMetadataService.Change) {
    pendingSecurityChange = change
    confirmSecurity = true
  }

  @MainActor private func reload() async {
    let token = UUID()
    generation = token
    pendingSecurityChange = nil
    confirmSecurity = false
    confirmChangeAll = false
    let target = url
    loading = true
    metadata = nil
    errorMessage = nil
    do {
      let item = try await service.load(target)
      let accounts = await service.accounts()
      guard generation == token, url == target, !Task.isCancelled else { return }
      metadata = item
      owners = accounts.owners
      groups = accounts.groups
      tags = item.tags.map { $0.components(separatedBy: "\n").first ?? $0 }.joined(separator: ", ")
      comment = item.comment
      octal = String(format: "%04o", Int(item.mode))
      ownerID = item.ownerID
      groupID = item.groupID
      applications =
        item.isSymbolicLink ? [] : NSWorkspace.shared.urlsForApplications(toOpen: target)
      currentApplication =
        item.isSymbolicLink ? nil : NSWorkspace.shared.urlForApplication(toOpen: target)
      if let currentApplication, !applications.contains(currentApplication) {
        applications.insert(currentApplication, at: 0)
      }
      selectedApplication = currentApplication
    } catch {
      guard generation == token, url == target, !Task.isCancelled else { return }
      errorMessage = error.localizedDescription
    }
    if generation == token { loading = false }
  }

  @MainActor private func apply(_ change: FileMetadataService.Change) {
    guard let item = metadata, !busy else { return }
    let token = generation
    busy = true
    Task {
      do {
        try await service.apply(change, to: item)
        onChange()
        if token == generation { await reload() }
      } catch {
        if token == generation { errorMessage = error.localizedDescription }
      }
      busy = false
    }
  }

  @MainActor private func chooseApplication() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let application = panel.url {
      if !applications.contains(application) { applications.append(application) }
      selectedApplication = application
    }
  }

  @MainActor private func changeApplication(all: Bool) {
    guard let application = selectedApplication, !busy else { return }
    let target = url
    let token = generation
    busy = true
    Task {
      do {
        try await FileMetadataService.setOpeningApplication(
          application, for: target, changeAll: all)
        onChange()
        if token == generation { await reload() }
      } catch {
        if token == generation { errorMessage = error.localizedDescription }
      }
      busy = false
    }
  }
}
