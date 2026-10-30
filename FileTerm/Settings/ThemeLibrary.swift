import AppKit
import FileTermCore
import SwiftUI

/// The themes shipped as data files in the app bundle.
enum ThemeLibrary {
  static let themes = AppTheme.load(
    from: Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])

  @MainActor static func apply(_ theme: AppTheme) {
    switch theme.appearance {
    case .system: NSApp.appearance = nil
    case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
    case .light: NSApp.appearance = NSAppearance(named: .aqua)
    }
  }
}

extension Color {
  init?(themeHex hex: String?) {
    guard let hex, let color = AppTheme.components(hex: hex) else { return nil }
    self.init(red: color.red, green: color.green, blue: color.blue)
  }
}

extension FileTagColor {
  var swatch: Color {
    switch self {
    case .gray: .gray
    case .green: .green
    case .purple: .purple
    case .blue: .blue
    case .yellow: .yellow
    case .red: .red
    case .orange: .orange
    }
  }
}

/// Colors the browser from a theme. Views with no theme color keep the system's.
struct ThemedBrowser: ViewModifier {
  let theme: AppTheme

  func body(content: Content) -> some View {
    content
      .scrollContentBackground(theme.background == nil ? .automatic : .hidden)
      .alternatingRowBackgrounds(theme.background == nil ? .automatic : .disabled)
      .background {
        if let background = Color(themeHex: theme.background) {
          background
        } else {
          Rectangle().fill(.background)
        }
      }
      .foregroundStyle(Color(themeHex: theme.foreground) ?? .primary)
      // `Color.accentColor` follows this modifier, and does not follow `tint`.
      .accentColor(Color(themeHex: theme.accent))
  }
}
