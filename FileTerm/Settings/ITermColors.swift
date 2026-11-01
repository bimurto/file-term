import AppKit
import FileTermCore

/// Reads iTerm2 `.itermcolors` color schemes.
enum ITermColors {
  enum ImportError: LocalizedError {
    case invalidFile

    var errorDescription: String? {
      "This file isn't a complete iTerm2 color scheme. It needs 16 ANSI colors, a foreground and a background."
    }
  }

  static func theme(from data: Data, name: String) throws -> TerminalTheme {
    guard
      let scheme = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else { throw ImportError.invalidFile }

    func color(_ key: String) -> String? {
      (scheme[key] as? [String: Any]).flatMap(hex(from:))
    }
    let ansi = (0..<16).compactMap { color("Ansi \($0) Color") }
    guard ansi.count == 16, let foreground = color("Foreground Color"),
      let background = color("Background Color")
    else { throw ImportError.invalidFile }

    // Without a selection color, swap the text colors so that selected text stays readable.
    let selection = color("Selection Color")
    return TerminalTheme(
      id: "imported.\(name)", name: name, foreground: foreground, background: background,
      cursor: color("Cursor Color") ?? foreground, selection: selection ?? foreground,
      ansi: ansi, selectedText: selection == nil ? background : color("Selected Text Color"),
      cursorText: color("Cursor Text Color"))
  }

  /// Themes store sRGB. A color with no named color space is from an older iTerm2, which wrote
  /// calibrated values, so reading its numbers as sRGB would show a different color.
  private static func hex(from color: [String: Any]) -> String? {
    guard let red = color["Red Component"] as? Double,
      let green = color["Green Component"] as? Double,
      let blue = color["Blue Component"] as? Double,
      red.isFinite, green.isFinite, blue.isFinite
    else { return nil }
    let space: NSColorSpace =
      switch color["Color Space"] as? String {
      case "sRGB": .sRGB
      case "P3": .displayP3
      default: .genericRGB
      }
    let components = [CGFloat(red), CGFloat(green), CGFloat(blue), 1]
    guard
      let converted = NSColor(colorSpace: space, components: components, count: 4)
        .usingColorSpace(.sRGB)
    else { return nil }
    let bytes = [converted.redComponent, converted.greenComponent, converted.blueComponent].map {
      Int((min(1, max(0, $0)) * 255).rounded())
    }
    return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
  }
}
