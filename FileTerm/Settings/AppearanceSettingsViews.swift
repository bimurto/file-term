import FileTermCore
import SwiftUI

struct ThemesSettingsView: View {
  @Bindable var settings: AppSettings

  var body: some View {
    List(ThemeLibrary.themes, selection: $settings.themeID) { theme in
      HStack(spacing: 10) {
        HStack(spacing: 0) {
          ForEach(
            Array([theme.sidebar, theme.background, theme.accent].enumerated()), id: \.offset
          ) { _, hex in
            Rectangle().fill(Color(themeHex: hex) ?? systemSwatch(theme))
          }
        }
        .frame(width: 54, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
        Text(theme.name)
        Spacer()
        if theme.id == AppTheme.defaultID {
          Text("Follows the system appearance").font(.caption).foregroundStyle(.secondary)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("theme.\(theme.id)")
    }
    .accessibilityIdentifier("themeList")
    .onChange(of: settings.themeID) { ThemeLibrary.apply(settings.theme) }
  }

  /// Themes without their own colors show the appearance they select.
  private func systemSwatch(_ theme: AppTheme) -> Color {
    switch theme.appearance {
    case .system: Color(nsColor: .windowBackgroundColor)
    case .dark: Color(white: 0.15)
    case .light: .white
    }
  }
}

struct TagsSettingsView: View {
  @Bindable var settings: AppSettings
  @State private var newName = ""
  @State private var newColor = FileTagColor.gray

  private var canAdd: Bool {
    FileTag.adding(newName, color: newColor, to: settings.tags) != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("These tags appear in the sidebar. Removing one here leaves it on your files.")
        .font(.caption).foregroundStyle(.secondary)
      List {
        ForEach(settings.tags) { tag in
          HStack {
            Circle().fill(tag.color.swatch).frame(width: 10, height: 10)
            Text(tag.name)
            Spacer()
            Button("Remove") { settings.tags.removeAll { $0 == tag } }
              .accessibilityIdentifier("removeTag.\(tag.name)")
          }
        }
      }
      .accessibilityIdentifier("tagList")
      HStack {
        TextField("Tag name", text: $newName)
          .textFieldStyle(.roundedBorder).accessibilityIdentifier("newTagName")
          .onSubmit(add)
        Picker("Color", selection: $newColor) {
          ForEach(FileTagColor.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .fixedSize().accessibilityIdentifier("newTagColor")
        Button("Add", action: add).disabled(!canAdd).accessibilityIdentifier("addTag")
      }
    }
  }

  private func add() {
    guard let tags = FileTag.adding(newName, color: newColor, to: settings.tags) else { return }
    settings.tags = tags
    newName = ""
  }
}
