import AppKit
import FileTermCore
import SwiftUI

/// Shows what an older configuration holds and adds only what is ticked. Nothing is overwritten.
struct FavoritesImportSheet: View {
  @Bindable var settings: AppSettings
  @Environment(\.dismiss) private var dismiss
  @State private var preview: FavoritesImportPreview?
  @State private var chosen: Set<UUID> = []
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Import Favorites").font(.headline)
      Text("Adds favorites from ForkLift 3. Your current favorites stay as they are.")
        .font(.caption)
      if let preview {
        List(preview.favorites) { favorite in
          Toggle(
            isOn: Binding(
              get: { chosen.contains(favorite.id) },
              set: { if $0 { chosen.insert(favorite.id) } else { chosen.remove(favorite.id) } })
          ) {
            VStack(alignment: .leading, spacing: 1) {
              Text(favorite.name)
              Text(
                ([favorite.group, favorite.path] + [favorite.isDuplicate ? "Already added" : nil])
                  .compactMap { $0 }.joined(separator: " · ")
              ).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        .frame(height: 240).accessibilityIdentifier("favoritesImportList")
        if !preview.skippedRemote.isEmpty {
          Text(
            "Not imported, add these with Go › Connect…: "
              + preview.skippedRemote.joined(separator: ", ")
          ).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
      } else {
        Text("Choose ForkLift 3's Favorites.json.").foregroundStyle(.secondary)
      }
      if let error { Text(error).font(.caption).foregroundStyle(.red) }
      HStack {
        Button("Choose File…") { choose() }
        Spacer()
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("Import") {
          let selected = preview?.favorites.filter { chosen.contains($0.id) } ?? []
          settings.favorites = FavoritesImport.merge(selected, into: settings.favorites)
          dismiss()
        }
        .keyboardShortcut(.defaultAction).disabled(chosen.isEmpty)
      }
    }
    .padding(20).frame(width: 560)
    .onAppear {
      if FileManager.default.fileExists(atPath: FavoritesImport.forkLift3Path) {
        load(URL(fileURLWithPath: FavoritesImport.forkLift3Path))
      }
    }
  }

  private func choose() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    if panel.runModal() == .OK, let url = panel.url { load(url) }
  }

  private func load(_ url: URL) {
    do {
      let result = try FavoritesImport.preview(
        data: Data(contentsOf: url), existing: settings.favorites)
      preview = result
      chosen = Set(result.favorites.filter { !$0.isDuplicate }.map(\.id))
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
  }
}
