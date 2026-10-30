import CoreGraphics
import Foundation
import Testing

@testable import FileTermCore

struct IconGridNavigationTests {
  private func items(_ names: String...) -> [Location] {
    names.map { Location(providerID: "local", path: "/\($0)") }
  }

  private func move(
    _ from: String?, _ direction: IconGridNavigation.Direction, _ groups: [[Location]],
    columns: Int = 3
  ) -> String? {
    let current = from.map { Location(providerID: "local", path: "/\($0)") }
    return IconGridNavigation.move(from: current, direction, groups: groups, columns: columns)?
      .path.replacingOccurrences(of: "/", with: "")
  }

  @Test func arrowsMoveThroughRowsAndStopAtEdges() {
    // a b c
    // d e f
    // g
    let grid = [items("a", "b", "c", "d", "e", "f", "g")]
    #expect(move("b", .right, grid) == "c")
    #expect(move("c", .right, grid) == "d")
    #expect(move("g", .right, grid) == "g")
    #expect(move("a", .left, grid) == "a")
    #expect(move("b", .down, grid) == "e")
    #expect(move("b", .up, grid) == "b")
    #expect(move("e", .up, grid) == "b")
    #expect(move("g", .down, grid) == "g")
  }

  @Test func movingDownIntoAShortLastRowLandsOnItsLastItem() {
    let grid = [items("a", "b", "c", "d", "e", "f", "g")]
    #expect(move("f", .down, grid) == "g")
  }

  @Test func arrowsCrossGroupsKeepingTheColumn() {
    let groups = [items("a", "b", "c", "d"), items("e", "f"), [], items("g", "h", "i")]
    #expect(move("c", .down, groups) == "d")
    #expect(move("d", .down, groups) == "e")
    #expect(move("b", .down, groups) == "d")
    #expect(move("e", .up, groups) == "d")
    #expect(move("f", .up, groups) == "d")
    #expect(move("f", .down, groups) == "h")
    #expect(move("g", .up, groups) == "e")
  }

  @Test func anyArrowStartsAtTheFirstItemWithoutASelection() {
    let grid = [items("a", "b")]
    #expect(move(nil, .down, grid) == "a")
    #expect(move("missing", .left, grid) == "a")
    #expect(move(nil, .right, [[]]) == nil)
  }

  @Test func columnsComeFromTheWidestLaidOutRow() {
    let locations = items("a", "b", "c", "d")
    let frames: [Location: CGRect] = [
      locations[0]: CGRect(x: 0, y: 0, width: 90, height: 90),
      locations[1]: CGRect(x: 100, y: 0.2, width: 90, height: 90),
      locations[2]: CGRect(x: 0, y: 100, width: 90, height: 90),
      locations[3]: CGRect(x: 0, y: 200, width: 90, height: 90),
    ]
    #expect(IconGridNavigation.columns(in: frames) == 2)
    #expect(IconGridNavigation.columns(in: [:]) == 1)
  }

  @Test func theBandSelectsEveryItemItTouches() {
    let locations = items("a", "b", "c")
    let frames: [Location: CGRect] = [
      locations[0]: CGRect(x: 0, y: 0, width: 90, height: 90),
      locations[1]: CGRect(x: 100, y: 0, width: 90, height: 90),
      locations[2]: CGRect(x: 0, y: 100, width: 90, height: 90),
    ]
    let band = CGRect(x: 80, y: 10, width: 30, height: 30)
    #expect(
      IconGridNavigation.selection(in: band, frames: frames) == [locations[0], locations[1]])
    #expect(IconGridNavigation.selection(in: .zero, frames: [:]).isEmpty)
  }

  @Test func typeSelectMatchesThePrefixIgnoringCaseAndAccents() {
    let entry = { (name: String) in
      FileEntry(location: Location(providerID: "local", path: "/\(name)"), name: name, kind: .file)
    }
    let entries = [entry("Alpha.txt"), entry("Éclair.txt"), entry("beta.txt"), entry("bet.txt")]
    #expect(IconGridNavigation.match("a", in: entries)?.path == "/Alpha.txt")
    #expect(IconGridNavigation.match("ecl", in: entries)?.path == "/Éclair.txt")
    #expect(IconGridNavigation.match("BET", in: entries)?.path == "/beta.txt")
    #expect(IconGridNavigation.match("lpha", in: entries) == nil)
  }

  @Test func aPauseStartsANewTypeSelectAttempt() {
    var buffer = TypeSelectBuffer()
    let start = Date(timeIntervalSince1970: 0)
    #expect(!buffer.isTyping(at: start))
    #expect(buffer.append("a", at: start) == "a")
    #expect(buffer.append("b", at: start.addingTimeInterval(0.5)) == "ab")
    #expect(buffer.isTyping(at: start.addingTimeInterval(1)))
    #expect(!buffer.isTyping(at: start.addingTimeInterval(2)))
    #expect(buffer.append("c", at: start.addingTimeInterval(2)) == "c")
  }
}
