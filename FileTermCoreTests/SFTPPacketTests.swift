import Foundation
import Testing

@testable import FileTermCore

struct SFTPPacketTests {
  private func payload(_ framed: Data) -> Data { Data(framed.dropFirst(4)) }

  private func reply(_ type: SFTPPacketType, id: UInt32?, _ build: (inout SFTPWriter) -> Void)
    -> Data
  {
    var body = SFTPWriter()
    body.byte(type.rawValue)
    if let id { body.uint32(id) }
    build(&body)
    return body.bytes
  }

  @Test func initializeAnnouncesVersionThree() {
    #expect(SFTPPacket.initialize() == Data([0, 0, 0, 5, 1, 0, 0, 0, 3]))
  }

  @Test func readRequestIsBigEndian() {
    let data = SFTPPacket.read(
      id: 7, handle: Data([0xAA]), offset: 0x0102_0304_0506_0708, length: 9)
    #expect(
      data
        == Data([0, 0, 0, 22, 5, 0, 0, 0, 7, 0, 0, 0, 1, 0xAA, 1, 2, 3, 4, 5, 6, 7, 8, 0, 0, 0, 9]))
  }

  @Test func openCarriesFlagsAndEmptyAttributes() throws {
    let framed = SFTPPacket.open(id: 1, path: "a b", flags: [.write, .create, .exclusive])
    var reader = SFTPReader(payload(framed))
    #expect(try reader.byte() == SFTPPacketType.open.rawValue)
    #expect(try reader.uint32() == 1)
    #expect(try reader.text() == "a b")
    #expect(try reader.uint32() == 0x2A)
    #expect(try reader.uint32() == 0)
    #expect(reader.isAtEnd)
  }

  @Test func decodesStatusHandleDataAndVersion() throws {
    let version = try SFTPPacket.decode(reply(.version, id: nil) { $0.uint32(3) })
    #expect(version.id == nil && version.reply == .version(3))

    let status = try SFTPPacket.decode(
      reply(.status, id: 4) {
        $0.uint32(2)
        $0.string("No such file")
        $0.string("en")
      })
    #expect(status.id == 4 && status.reply == .status(code: 2, message: "No such file"))

    let bare = try SFTPPacket.decode(reply(.status, id: 5) { $0.uint32(0) })
    #expect(bare.reply == .status(code: 0, message: ""))

    let handle = try SFTPPacket.decode(reply(.handle, id: 6) { $0.string(Data([1, 2])) })
    #expect(handle.reply == .handle(Data([1, 2])))
    let data = try SFTPPacket.decode(reply(.data, id: 7) { $0.string(Data("hi".utf8)) })
    #expect(data.reply == .data(Data("hi".utf8)))
  }

  @Test func decodesAttributesWithAndWithoutOptionalFields() throws {
    let full = try SFTPPacket.decode(
      reply(.attrs, id: 1) {
        $0.uint32(0x8000_000F)
        $0.uint64(1234)
        $0.uint32(1000)
        $0.uint32(100)
        $0.uint32(0o100644)
        $0.uint32(10)
        $0.uint32(20)
        $0.uint32(1)  // one extended pair, skipped
        $0.string("k")
        $0.string("v")
      })
    let attributes = SFTPAttributes(
      size: 1234, uid: 1000, gid: 100, permissions: 0o100644, accessTime: 10, modifyTime: 20)
    #expect(full.reply == .attributes(attributes))
    #expect(attributes.isRegularFile && !attributes.isDirectory)

    let empty = try SFTPPacket.decode(reply(.attrs, id: 2) { $0.uint32(0) })
    #expect(empty.reply == .attributes(SFTPAttributes()))
  }

  @Test func decodesNameListsAndKinds() throws {
    let decoded = try SFTPPacket.decode(
      reply(.name, id: 3) {
        $0.uint32(2)
        for (name, mode) in [("dir", UInt32(0o040755)), ("link", 0o120777)] {
          $0.string(name)
          $0.string("long line")
          $0.uint32(0x04)
          $0.uint32(mode)
        }
      })
    guard case .names(let entries) = decoded.reply else {
      Issue.record("not a name list")
      return
    }
    #expect(entries.map(\.filename) == ["dir", "link"])
    #expect(entries[0].attributes.isDirectory && entries[1].attributes.isSymbolicLink)
  }

  @Test func rejectsTruncatedAndUnknownPackets() {
    #expect(throws: SFTPProtocolError.self) {
      try SFTPPacket.decode(self.reply(.handle, id: 1) { $0.uint32(50) })
    }
    #expect(throws: SFTPProtocolError.self) { try SFTPPacket.decode(Data([200, 0, 0, 0, 1])) }
    #expect(throws: SFTPProtocolError.self) { try SFTPPacket.decode(Data()) }
  }

  @Test func frameDecoderHandlesSplitAndCombinedChunks() throws {
    let first = SFTPPacket.initialize()
    let second = SFTPPacket.path(.stat, id: 9, "/x")
    var decoder = SFTPFrameDecoder()
    let stream = first + second
    decoder.append(stream.prefix(3))
    #expect(try decoder.next() == nil)
    decoder.append(stream.dropFirst(3).prefix(4))
    #expect(try decoder.next() == nil)
    decoder.append(stream.dropFirst(7))
    #expect(try decoder.next() == payload(first))
    #expect(try decoder.next() == payload(second))
    #expect(try decoder.next() == nil)
  }

  @Test func frameDecoderRejectsAbsurdLengths() {
    var decoder = SFTPFrameDecoder()
    decoder.append(Data([0x7F, 0xFF, 0xFF, 0xFF, 1]))
    #expect(throws: SFTPProtocolError.self) { try decoder.next() }
    var empty = SFTPFrameDecoder()
    empty.append(Data([0, 0, 0, 0]))
    #expect(throws: SFTPProtocolError.self) { try empty.next() }
  }

  @Test func statusCodesMapToFileSystemErrors() {
    #expect(SFTPPacket.error(code: 0, message: "") == nil)
    #expect(SFTPPacket.error(code: 2, message: "") == .notFound)
    #expect(SFTPPacket.error(code: 3, message: "") == .permissionDenied)
    #expect(SFTPPacket.error(code: 8, message: "") == .unsupportedOperation)
    #expect(SFTPPacket.error(code: 4, message: "Failure") == .io("Failure"))
    #expect(SFTPPacket.error(code: 4, message: "") == .io("The server reported a failure."))
  }
}
