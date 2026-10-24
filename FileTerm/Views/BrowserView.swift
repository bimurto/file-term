import AppKit
import FileTermCore
import SwiftUI
import UniformTypeIdentifiers

struct BrowserView: View {
  @Bindable var pane: PaneModel
  let settings: AppSettings
  let registry: CommandRegistry
  let localProvider: LocalFileSystemProvider

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      HSplitView {
        VStack(spacing: 0) {
          PathBar(
            url: pane.location.flatMap { try? localProvider.url(for: $0) },
            displayPath: pane.location?.path
          )
          .frame(height: 30).padding(.horizontal, 10)
          Divider()
          if let error = pane.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
              .font(.callout).foregroundStyle(.secondary)
              .padding(12).frame(maxWidth: .infinity, alignment: .leading)
              .accessibilityIdentifier("navigationError")
            Divider()
          }
          fileList
          Divider()
          HStack {
            Text("\(pane.entries.count) items")
              .accessibilityIdentifier("itemCount")
            Spacer()
            if pane.isLoading { ProgressView().controlSize(.small) }
          }
          .font(.caption).foregroundStyle(.secondary)
          .padding(.horizontal, 12).frame(height: 28)
        }
        .frame(minWidth: 420)
        if settings.isVisible(.preview) {
          placeholder(.preview).frame(minWidth: 200, idealWidth: 250)
        }
      }
      if settings.isVisible(.activities) || settings.isVisible(.logs) {
        Divider()
        HSplitView {
          if settings.isVisible(.activities) { placeholder(.activities) }
          if settings.isVisible(.logs) { placeholder(.logs) }
        }
        .frame(height: 140)
      }
    }
    .background(.background)
    .frame(minWidth: 680, minHeight: 420)
  }

  private var toolbar: some View {
    HStack(spacing: 8) {
      Text("FileTerm").font(.headline)
      Spacer()
      ForEach(PlaceholderPanel.allCases) { panel in
        Button {
          registry.execute(panel.commandID)
        } label: {
          Label(panel.rawValue, systemImage: panel.symbol)
        }
        .tint(settings.isVisible(panel) ? .accentColor : nil)
        .disabled(registry.disabledReason(for: panel.commandID) != nil)
        .help(
          registry.disabledReason(for: panel.commandID)
            ?? "Show or hide \(panel.rawValue.lowercased())"
        )
        .accessibilityIdentifier(panel.commandID)
        .accessibilityValue(settings.isVisible(panel) ? "Shown" : "Hidden")
      }
    }
    .padding(.horizontal, 12).frame(height: 44)
  }

  private var fileList: some View {
    Table(pane.entries, selection: $pane.selection) {
      TableColumn("Name") { entry in
        HStack(spacing: 6) {
          FileIcon(entry: entry, localProvider: localProvider)
          Text(entry.name).lineLimit(1)
        }
      }.width(min: 180, ideal: 280)
      TableColumn("Size") { entry in
        Text(entry.size.map { $0.formatted(.byteCount(style: .file)) } ?? "—")
          .monospacedDigit().foregroundStyle(.secondary)
      }.width(85)
      TableColumn("Kind") { entry in
        Text(kindDescription(entry)).foregroundStyle(.secondary)
      }.width(min: 90, ideal: 130)
      TableColumn("Modified") { entry in
        Text(entry.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
          .foregroundStyle(.secondary)
      }.width(min: 140, ideal: 170)
    }
    .contextMenu(forSelectionType: Location.self) { _ in
      EmptyView()
    } primaryAction: { locations in
      guard locations.count == 1, let location = locations.first,
        pane.entries.contains(where: { $0.id == location && $0.kind == .directory })
      else { return }
      Task { await pane.navigate(to: location) }
    }
    .accessibilityIdentifier("fileList")
    .overlay {
      if pane.entries.isEmpty && !pane.isLoading {
        ContentUnavailableView(
          pane.location == nil ? "No folder open" : "This folder is empty",
          systemImage: "folder"
        ).allowsHitTesting(false)
      }
    }
  }

  private func kindDescription(_ entry: FileEntry) -> String {
    switch entry.kind {
    case .directory: return "Folder"
    case .symbolicLink: return "Symbolic Link"
    case .other: return "Other"
    case .file:
      let type =
        entry.typeIdentifier.flatMap { UTType($0) }
        ?? UTType(filenameExtension: (entry.name as NSString).pathExtension)
      return type?.localizedDescription ?? "File"
    }
  }

  private func placeholder(_ panel: PlaceholderPanel) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(panel.rawValue, systemImage: panel.symbol).font(.headline)
      Text("\(panel.rawValue) is not implemented yet.").foregroundStyle(.secondary)
      Spacer(minLength: 0)
    }
    .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .accessibilityIdentifier("panel.\(panel.rawValue)")
  }
}

private struct FileIcon: View {
  let entry: FileEntry
  let localProvider: LocalFileSystemProvider
  @State private var icon: NSImage?

  var body: some View {
    Group {
      if let icon {
        Image(nsImage: icon).resizable()
      } else {
        Image(systemName: entry.kind == .directory ? "folder" : "doc").resizable()
      }
    }
    .frame(width: 16, height: 16).accessibilityHidden(true)
    .task(id: entry.location) {
      guard let url = try? localProvider.url(for: entry.location) else { return }
      icon = NSWorkspace.shared.icon(forFile: url.path)
    }
  }
}
