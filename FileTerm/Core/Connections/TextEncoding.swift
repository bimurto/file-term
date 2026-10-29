import Foundation

/// How a server's file names turn into text and back. Names are raw bytes on FTP and SFTP; the
/// connection's Text Encoding says which character set they use.
public enum TextEncoding {
  public static let names = [
    "UTF-8", "ISO-8859-1", "Windows-1252", "Shift_JIS", "EUC-KR", "GB18030",
  ]

  public static func encoding(named name: String) -> String.Encoding {
    let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
    guard cfEncoding != kCFStringEncodingInvalidId else { return .utf8 }
    return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
  }

  /// The name in the given encoding; bytes it cannot read fall back to lossy UTF-8.
  public static func decodeName(_ data: Data, using name: String) -> String {
    String(data: data, encoding: encoding(named: name))
      ?? String(decoding: data, as: UTF8.self)
  }

  /// The bytes to send for a name; characters the encoding cannot hold fall back to UTF-8.
  public static func encodeName(_ text: String, using name: String) -> Data {
    text.data(using: encoding(named: name)) ?? Data(text.utf8)
  }

  /// A path read under one encoding, re-read under another: the bytes are what the server holds.
  /// nil when the original bytes cannot be rebuilt (the old reading was lossy).
  public static func recode(_ path: String, from old: String, to new: String) -> String? {
    guard !path.contains("\u{FFFD}"), let data = path.data(using: encoding(named: old)) else {
      return nil
    }
    return String(data: data, encoding: encoding(named: new))
  }
}
