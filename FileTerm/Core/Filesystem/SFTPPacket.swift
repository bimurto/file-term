import Foundation

/// SFTP protocol version 3 (draft-ietf-secsh-filexfer-02), the version OpenSSH speaks.
/// Pure encoding and decoding; `SFTPProvider` owns the ssh process.
enum SFTPPacketType: UInt8 {
  case initialize = 1
  case version = 2
  case open = 3
  case close = 4
  case read = 5
  case write = 6
  case lstat = 7
  case opendir = 11
  case readdir = 12
  case remove = 13
  case mkdir = 14
  case rmdir = 15
  case realpath = 16
  case stat = 17
  case rename = 18
  case status = 101
  case handle = 102
  case data = 103
  case name = 104
  case attrs = 105
}

enum SFTPStatusCode: UInt32 {
  case ok = 0
  case eof, noSuchFile, permissionDenied, failure, badMessage, noConnection
  case connectionLost, operationUnsupported
}

struct SFTPOpenFlags: OptionSet {
  let rawValue: UInt32
  static let read = SFTPOpenFlags(rawValue: 0x01)
  static let write = SFTPOpenFlags(rawValue: 0x02)
  static let create = SFTPOpenFlags(rawValue: 0x08)
  static let exclusive = SFTPOpenFlags(rawValue: 0x20)
}

struct SFTPAttributes: Equatable {
  var size: Int64?
  var uid: UInt32?
  var gid: UInt32?
  var permissions: UInt32?
  var accessTime: UInt32?
  var modifyTime: UInt32?

  private static let typeMask: UInt32 = 0o170000

  var isDirectory: Bool { permissions.map { $0 & Self.typeMask == 0o040000 } ?? false }
  var isRegularFile: Bool { permissions.map { $0 & Self.typeMask == 0o100000 } ?? false }
  var isSymbolicLink: Bool { permissions.map { $0 & Self.typeMask == 0o120000 } ?? false }
}

struct SFTPNameEntry: Equatable {
  let filename: String
  let attributes: SFTPAttributes
}

enum SFTPReply: Equatable {
  case version(UInt32)
  case status(code: UInt32, message: String)
  case handle(Data)
  case data(Data)
  case names([SFTPNameEntry])
  case attributes(SFTPAttributes)
}

struct SFTPProtocolError: Error, Equatable {
  let message: String
}

struct SFTPWriter {
  private(set) var bytes = Data()

  mutating func byte(_ value: UInt8) { bytes.append(value) }

  mutating func uint32(_ value: UInt32) {
    bytes.append(contentsOf: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) })
  }

  mutating func uint64(_ value: UInt64) {
    bytes.append(
      contentsOf: stride(from: 56, through: 0, by: -8).map {
        UInt8(truncatingIfNeeded: value >> UInt64($0))
      })
  }

  mutating func string(_ data: Data) {
    uint32(UInt32(data.count))
    bytes.append(data)
  }

  mutating func string(_ text: String) { string(Data(text.utf8)) }
}

struct SFTPReader {
  private let bytes: Data
  private var offset: Int

  init(_ bytes: Data) {
    self.bytes = bytes
    offset = bytes.startIndex
  }

  var isAtEnd: Bool { offset >= bytes.endIndex }

  mutating func byte() throws -> UInt8 {
    guard offset < bytes.endIndex else { throw SFTPProtocolError(message: "Truncated packet.") }
    defer { offset += 1 }
    return bytes[offset]
  }

  mutating func uint32() throws -> UInt32 {
    var value: UInt32 = 0
    for _ in 0..<4 { value = value << 8 | UInt32(try byte()) }
    return value
  }

  mutating func uint64() throws -> UInt64 {
    var value: UInt64 = 0
    for _ in 0..<8 { value = value << 8 | UInt64(try byte()) }
    return value
  }

  mutating func string() throws -> Data {
    let length = Int(try uint32())
    guard length <= bytes.endIndex - offset else {
      throw SFTPProtocolError(message: "Truncated packet.")
    }
    defer { offset += length }
    return Data(bytes[offset..<offset + length])
  }

  mutating func text() throws -> String { String(decoding: try string(), as: UTF8.self) }

  mutating func attributes() throws -> SFTPAttributes {
    let flags = try uint32()
    var result = SFTPAttributes()
    if flags & 0x01 != 0 { result.size = Int64(clamping: try uint64()) }
    if flags & 0x02 != 0 {
      result.uid = try uint32()
      result.gid = try uint32()
    }
    if flags & 0x04 != 0 { result.permissions = try uint32() }
    if flags & 0x08 != 0 {
      result.accessTime = try uint32()
      result.modifyTime = try uint32()
    }
    if flags & 0x8000_0000 != 0 {
      for _ in 0..<(try uint32()) {
        _ = try string()
        _ = try string()
      }
    }
    return result
  }
}

enum SFTPPacket {
  /// Largest frame accepted from the server. Servers answer reads with at most the size asked for.
  static let maxFrame = 1 << 20

  static func frame(_ type: SFTPPacketType, _ build: (inout SFTPWriter) -> Void) -> Data {
    var body = SFTPWriter()
    body.byte(type.rawValue)
    build(&body)
    var framed = SFTPWriter()
    framed.uint32(UInt32(body.bytes.count))
    return framed.bytes + body.bytes
  }

  static func initialize() -> Data { frame(.initialize) { $0.uint32(3) } }

  /// A request that carries an ID, then whatever `build` adds.
  static func request(
    _ type: SFTPPacketType, id: UInt32, _ build: (inout SFTPWriter) -> Void = { _ in }
  ) -> Data {
    frame(type) {
      $0.uint32(id)
      build(&$0)
    }
  }

  static func path(_ type: SFTPPacketType, id: UInt32, _ path: String) -> Data {
    request(type, id: id) { $0.string(path) }
  }

  static func handle(_ type: SFTPPacketType, id: UInt32, _ handle: Data) -> Data {
    request(type, id: id) { $0.string(handle) }
  }

  static func open(id: UInt32, path: String, flags: SFTPOpenFlags) -> Data {
    request(.open, id: id) {
      $0.string(path)
      $0.uint32(flags.rawValue)
      $0.uint32(0)  // no attributes: the server applies its umask
    }
  }

  static func read(id: UInt32, handle: Data, offset: UInt64, length: UInt32) -> Data {
    request(.read, id: id) {
      $0.string(handle)
      $0.uint64(offset)
      $0.uint32(length)
    }
  }

  static func write(id: UInt32, handle: Data, offset: UInt64, data: Data) -> Data {
    request(.write, id: id) {
      $0.string(handle)
      $0.uint64(offset)
      $0.string(data)
    }
  }

  static func makeDirectory(id: UInt32, path: String) -> Data {
    request(.mkdir, id: id) {
      $0.string(path)
      $0.uint32(0)
    }
  }

  static func rename(id: UInt32, from: String, to: String) -> Data {
    request(.rename, id: id) {
      $0.string(from)
      $0.string(to)
    }
  }

  /// Decodes one frame's payload (the bytes after the length). VERSION has no request ID.
  static func decode(_ payload: Data) throws -> (id: UInt32?, reply: SFTPReply) {
    var reader = SFTPReader(payload)
    guard let type = SFTPPacketType(rawValue: try reader.byte()) else {
      throw SFTPProtocolError(message: "Unexpected reply from the server.")
    }
    if type == .version { return (nil, .version(try reader.uint32())) }
    let id = try reader.uint32()
    switch type {
    case .status:
      let code = try reader.uint32()
      // Older servers may omit the message and language tag.
      let message = reader.isAtEnd ? "" : try reader.text()
      return (id, .status(code: code, message: message))
    case .handle: return (id, .handle(try reader.string()))
    case .data: return (id, .data(try reader.string()))
    case .name:
      var entries: [SFTPNameEntry] = []
      for _ in 0..<(try reader.uint32()) {
        let name = try reader.text()
        _ = try reader.string()  // long name, a pre-formatted `ls -l` line
        entries.append(SFTPNameEntry(filename: name, attributes: try reader.attributes()))
      }
      return (id, .names(entries))
    case .attrs: return (id, .attributes(try reader.attributes()))
    default: throw SFTPProtocolError(message: "Unexpected reply from the server.")
    }
  }

  /// A status reply as an error. nil for OK; EOF is the caller's to handle before calling.
  static func error(code: UInt32, message: String) -> FileSystemError? {
    switch SFTPStatusCode(rawValue: code) {
    case .ok: nil
    case .noSuchFile: .notFound
    case .permissionDenied: .permissionDenied
    case .operationUnsupported: .unsupportedOperation
    case .eof: .io("The server ended the data early.")
    case .noConnection, .connectionLost: .io("The connection to the server was lost.")
    default: .io(message.isEmpty ? "The server reported a failure." : message)
    }
  }
}

/// Splits the server's byte stream into frames, whatever the chunking.
struct SFTPFrameDecoder {
  private var buffer = Data()

  mutating func append(_ data: Data) { buffer.append(data) }

  /// The next complete frame's payload, or nil while more bytes are needed.
  mutating func next() throws -> Data? {
    guard buffer.count >= 4 else { return nil }
    let start = buffer.startIndex
    let length = buffer[start..<start + 4].reduce(0) { $0 << 8 | Int($1) }
    guard length > 0, length <= SFTPPacket.maxFrame else {
      throw SFTPProtocolError(message: "The server sent an invalid packet.")
    }
    guard buffer.count >= 4 + length else { return nil }
    let payload = Data(buffer[start + 4..<start + 4 + length])
    buffer = Data(buffer[(start + 4 + length)...])
    return payload
  }
}
