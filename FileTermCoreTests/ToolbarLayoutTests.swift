import FileTermCore
import Testing

struct ToolbarLayoutTests {
  private let items = [
    "go.back", "go.forward", "go.connect", "view.single", "view.vertical", "view.asList",
    "view.asIcons", "view.preview", "view.logs", "view.refresh", "tools.run.x",
  ]

  @Test func levelZeroKeepsEveryButtonInRunsOfOneGroup() {
    #expect(
      ToolbarLayout.segments(for: items, foldLevel: 0) == [
        .buttons(["go.back", "go.forward"]), .buttons(["go.connect"]),
        .buttons(["view.single", "view.vertical"]), .buttons(["view.asList", "view.asIcons"]),
        .buttons(["view.preview", "view.logs"]), .buttons(["view.refresh", "tools.run.x"]),
      ])
  }

  @Test func levelOneFoldsLayoutAndViewMode() {
    let segments = ToolbarLayout.segments(for: items, foldLevel: 1)
    #expect(segments.contains(.menu(.layout, ["view.single", "view.vertical"])))
    #expect(segments.contains(.menu(.viewMode, ["view.asList", "view.asIcons"])))
    #expect(segments.contains(.buttons(["view.preview", "view.logs"])))
  }

  @Test func levelTwoAlsoFoldsPanels() {
    #expect(
      ToolbarLayout.segments(for: items, foldLevel: 2).contains(
        .menu(.panels, ["view.preview", "view.logs"])))
  }

  @Test func theLastLevelMovesTheRestToOneMoreMenuAndLosesNoButton() {
    let segments = ToolbarLayout.segments(
      for: items, foldLevel: ToolbarLayout.foldLevels.upperBound)
    #expect(segments.first == .buttons(["go.back", "go.forward"]))
    #expect(segments.last == .menu(.other, ["go.connect", "view.refresh", "tools.run.x"]))
    let ids = segments.flatMap { segment -> [String] in
      switch segment {
      case .buttons(let ids), .menu(_, let ids): ids
      }
    }
    #expect(Set(ids) == Set(items))
  }

  @Test func aLoneButtonDoesntBecomeADropdown() {
    #expect(
      ToolbarLayout.segments(for: ["view.single", "go.back"], foldLevel: 2) == [
        .buttons(["view.single"]), .buttons(["go.back"]),
      ])
  }

  @Test func theUsersOrderIsKept() {
    #expect(
      ToolbarLayout.segments(for: ["view.single", "go.back", "view.vertical"], foldLevel: 1) == [
        .buttons(["view.single"]), .buttons(["go.back"]), .buttons(["view.vertical"]),
      ])
  }
}
