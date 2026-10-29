import Foundation
import Testing

@testable import FileTermCore

@Suite struct TextEncodingTests {
  @Test func everyListedNameIsARealEncoding() {
    for name in TextEncoding.names {
      let encoding = TextEncoding.encoding(named: name)
      // Only UTF-8 itself may map to .utf8.
      #expect((encoding == .utf8) == (name == "UTF-8"), "\(name)")
    }
  }

  @Test func namesRoundTripThroughTheEncoding() {
    let latin1 = TextEncoding.encodeName("café", using: "ISO-8859-1")
    #expect(latin1 == Data([0x63, 0x61, 0x66, 0xE9]))
    #expect(TextEncoding.decodeName(latin1, using: "ISO-8859-1") == "café")
    #expect(TextEncoding.decodeName(latin1, using: "UTF-8") == "caf\u{FFFD}")
    let japanese = TextEncoding.encodeName("表.txt", using: "Shift_JIS")
    #expect(TextEncoding.decodeName(japanese, using: "Shift_JIS") == "表.txt")
  }

  @Test func charactersTheEncodingCannotHoldFallBackToUTF8() {
    #expect(TextEncoding.encodeName("表", using: "ISO-8859-1") == Data("表".utf8))
  }

  @Test func recodeRereadsTheSameServerBytes() {
    // Listed as UTF-8, the server's Latin-1 bytes C3 A9 show as "Ã©".
    #expect(TextEncoding.recode("/cafÃ©", from: "ISO-8859-1", to: "UTF-8") == "/café")
    #expect(TextEncoding.recode("/café", from: "UTF-8", to: "ISO-8859-1") == "/cafÃ©")
    #expect(TextEncoding.recode("/plain", from: "UTF-8", to: "Shift_JIS") == "/plain")
  }

  @Test func recodeGivesUpOnLossyPaths() {
    #expect(TextEncoding.recode("/caf\u{FFFD}", from: "UTF-8", to: "ISO-8859-1") == nil)
  }
}
