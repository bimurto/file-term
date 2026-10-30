import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import FileTermCore

struct RenameMetadataTests {
  private func rule(_ field: RenameMetadataField, position: RenameRule.Position = .start)
    -> RenameRule
  {
    var rule = RenameRule(kind: .addMetadata)
    rule.metadataField = field
    rule.position = position
    return rule
  }

  private func item(_ name: String = "photo.jpg", _ fill: (inout RenameItem) -> Void = { _ in })
    -> RenameItem
  {
    var item = RenameItem(location: Location(providerID: "local", path: "/d/\(name)"), name: name)
    fill(&item)
    return item
  }

  private func proposed(_ rule: RenameRule, _ item: RenameItem) -> String {
    rule.apply(to: item.name, item: item, index: 0, now: Date())
  }

  private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test func presetsSavedBeforeThisRuleExistedStillDecode() throws {
    let encoded = try JSONEncoder().encode([RenameRule(kind: .addText)])
    #expect(!String(decoding: encoded, as: UTF8.self).contains("storedMetadataField"))
    let rules = try JSONDecoder().decode([RenameRule].self, from: encoded)
    #expect(rules.first?.kind == .addText)
    #expect(rules.first?.metadataField == .dateTaken)
  }

  @Test func theChosenFieldSurvivesARoundTrip() throws {
    let encoded = try JSONEncoder().encode(rule(.artist))
    #expect(try JSONDecoder().decode(RenameRule.self, from: encoded).metadataField == .artist)
  }

  @Test func insertsTextFieldsAtTheChosenPosition() {
    let source = item { $0.embedded.text[.cameraModel] = "X100" }
    #expect(proposed(rule(.cameraModel), source) == "X100photo.jpg")
    #expect(proposed(rule(.cameraModel, position: .end), source) == "photoX100.jpg")
  }

  @Test func datesUseTheRuleFormatAndFileFieldsNeedNoEmbeddedData() throws {
    let date = try #require(
      Calendar(identifier: .gregorian).date(from: DateComponents(year: 2024, month: 3, day: 9)))
    var format = rule(.dateTaken)
    format.dateFormat = "yyyy_MM_dd-"
    #expect(proposed(format, item { $0.embedded.dateTaken = date }) == "2024_03_09-photo.jpg")
    let listed = RenameItem(
      location: Location(providerID: "sftp", path: "/d/a.txt"), name: "a.txt", modifiedAt: date,
      createdAt: date, size: 42)
    format.metadataField = .modified
    #expect(proposed(format, listed) == "2024_03_09-a.txt")
    format.metadataField = .created
    #expect(proposed(format, listed) == "2024_03_09-a.txt")
    #expect(proposed(rule(.size), listed) == "42a.txt")
  }

  @Test func anItemWithoutTheFieldKeepsItsName() {
    for field in RenameMetadataField.allCases {
      #expect(proposed(rule(field), item()) == "photo.jpg")
    }
    #expect(proposed(rule(.artist), item { $0.embedded.text[.artist] = "  " }) == "photo.jpg")
  }

  @Test func charactersAFileNameCantHoldAreReplaced() {
    let tagged = item("song.mp3") {
      $0.embedded.text[.artist] = "AC/DC: Live\nTour"
    }
    #expect(proposed(rule(.artist), tagged) == "AC-DC- Live Toursong.mp3")
    var timed = rule(.modified)
    timed.dateFormat = "HH:mm"
    let result = proposed(
      timed, RenameItem(location: item().location, name: "a", modifiedAt: Date()))
    #expect(!result.contains(":"))
    #expect(
      BatchRenamePlanner.preview(items: [tagged], rules: [rule(.artist)]).first?.hasError == false)
  }

  @Test func readsExifFromARealImage() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("photo.jpg")
    let context = try #require(
      CGContext(
        data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    let image = try #require(context.makeImage())
    let destination = try #require(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    let properties: [CFString: Any] = [
      kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifDateTimeOriginal: "2021:07:04 09:30:00"
      ],
      kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "Test Camera"],
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))

    let metadata = await RenameMetadataReader.read(url)
    #expect(metadata.text[.cameraModel] == "Test Camera")
    #expect(metadata.text[.dimensions] == "4x3")
    let taken = try #require(metadata.dateTaken)
    let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: taken)
    #expect(parts.year == 2021 && parts.month == 7 && parts.day == 4 && parts.hour == 9)
  }

  @Test func readsID3TagsFromARealFile() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("song.mp3")
    try id3File(
      ["TIT2": "A Title", "TPE1": "An Artist", "TALB": "An Album", "TRCK": "3/12"]
    ).write(to: url)

    let metadata = await RenameMetadataReader.read(url)
    #expect(metadata.text[.title] == "A Title")
    #expect(metadata.text[.artist] == "An Artist")
    #expect(metadata.text[.album] == "An Album")
    #expect(metadata.text[.track] == "3")
  }

  @Test func onlyLocalFilesAreReadAndOthersPassThrough() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let text = folder.appendingPathComponent("notes.txt")
    try Data("hello".utf8).write(to: text)
    let items = [
      RenameItem(location: Location(providerID: "local", path: text.path), name: "notes.txt"),
      RenameItem(location: Location(providerID: "sftp", path: "/r/a.jpg"), name: "a.jpg"),
      RenameItem(
        location: Location(providerID: "local", path: folder.path), name: "folder",
        isDirectory: true),
      RenameItem(location: Location(providerID: "local", path: "/missing/a.jpg"), name: "a.jpg"),
    ]
    let result = await RenameMetadataReader.enriched(items)
    #expect(result == items)
  }

  /// An ID3v2.3 tag followed by silent MPEG frames, so the file parses as audio.
  private func id3File(_ frames: [String: String]) -> Data {
    var body = Data()
    for (id, value) in frames.sorted(by: { $0.key < $1.key }) {
      let text = Data([0]) + Data(value.utf8)
      body += Data(id.utf8)
      body += withUnsafeBytes(of: UInt32(text.count).bigEndian) { Data($0) }
      body += Data([0, 0]) + text
    }
    let size = body.count
    var file = Data("ID3".utf8) + Data([3, 0, 0])
    file += Data((0..<4).reversed().map { UInt8((size >> (7 * $0)) & 0x7F) })
    file += body
    let frame = Data([0xFF, 0xFB, 0x90, 0x00]) + Data(repeating: 0, count: 413)
    for _ in 0..<40 { file += frame }
    return file
  }
}
