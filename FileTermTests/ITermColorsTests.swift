import AppKit
import FileTermCore
import Foundation
import Testing

@testable import FileTerm

struct ITermColorsTests {
  private func color(_ red: Double, _ green: Double, _ blue: Double, space: String? = "sRGB")
    -> [String: Any]
  {
    var color: [String: Any] = [
      "Red Component": red, "Green Component": green, "Blue Component": blue,
    ]
    if let space { color["Color Space"] = space }
    return color
  }

  private func scheme() -> [String: Any] {
    var scheme: [String: Any] = [
      "Foreground Color": color(1, 1, 1), "Background Color": color(0, 0, 0),
    ]
    for index in 0..<16 { scheme["Ansi \(index) Color"] = color(Double(index) / 15, 0, 0) }
    return scheme
  }

  private func data(_ scheme: [String: Any]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: scheme, format: .xml, options: 0)
  }

  @Test func aCompleteSchemeKeepsEveryColor() throws {
    var scheme = scheme()
    scheme["Cursor Color"] = color(0.2, 0.4, 0.6)
    scheme["Cursor Text Color"] = color(0.6, 0.4, 0.2)
    scheme["Selection Color"] = color(0.8, 0.8, 0.8)
    scheme["Selected Text Color"] = color(0.2, 0.2, 0.2)

    let theme = try ITermColors.theme(from: try data(scheme), name: "My Scheme")

    #expect(theme.id == "imported.My Scheme")
    #expect(theme.name == "My Scheme")
    #expect(theme.foreground == "#FFFFFF")
    #expect(theme.background == "#000000")
    #expect(theme.cursor == "#336699")
    #expect(theme.cursorText == "#996633")
    #expect(theme.selection == "#CCCCCC")
    #expect(theme.selectedText == "#333333")
    #expect(theme.ansi.count == 16)
    #expect(theme.ansi[15] == "#FF0000")
  }

  @Test func missingOptionalColorsStayReadable() throws {
    let theme = try ITermColors.theme(from: try data(scheme()), name: "Minimal")

    #expect(theme.cursor == "#FFFFFF")
    #expect(theme.selection == "#FFFFFF")
    #expect(theme.selectedText == "#000000")
    #expect(theme.cursorText == nil)
  }

  /// Dracula's published iTerm2 file has no color space. These values are its background.
  @Test func aColorWithoutAColorSpaceIsConverted() throws {
    var scheme = scheme()
    scheme["Background Color"] = color(
      0.11765811592340469, 0.12215272337198257, 0.15977837145328522, space: nil)

    let theme = try ITermColors.theme(from: try data(scheme), name: "Old")

    let actual = try #require(AppTheme.components(hex: theme.background))
    let expected = try #require(AppTheme.components(hex: "#282A36"))
    #expect(abs(actual.red - expected.red) < 0.02)
    #expect(abs(actual.green - expected.green) < 0.02)
    #expect(abs(actual.blue - expected.blue) < 0.02)
  }

  @Test func displayP3ColorsAreConvertedAndOutOfRangeValuesAreClamped() throws {
    var scheme = scheme()
    scheme["Foreground Color"] = color(1, 0, 0, space: "P3")
    scheme["Background Color"] = color(-1, 2, 0.5)

    let theme = try ITermColors.theme(from: try data(scheme), name: "Wide")

    #expect(theme.foreground == "#FF0000")
    #expect(theme.background == "#00FF80")
  }

  @Test func incompleteFilesAreRejected() throws {
    var noColor = scheme()
    noColor["Ansi 7 Color"] = nil
    var noBackground = scheme()
    noBackground["Background Color"] = nil
    var notANumber = scheme()
    notANumber["Foreground Color"] = color(.nan, 0, 0)
    var wrongType = scheme()
    wrongType["Foreground Color"] = "white"
    for bad in [
      try data(noColor), try data(noBackground), try data(notANumber), try data(wrongType),
      Data("not a scheme".utf8), Data(),
    ] {
      #expect(throws: ITermColors.ImportError.self) {
        try ITermColors.theme(from: bad, name: "Bad")
      }
    }
  }
}
