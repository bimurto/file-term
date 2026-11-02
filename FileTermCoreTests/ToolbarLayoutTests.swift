import FileTermCore
import Testing

struct ToolbarLayoutTests {
  @Test func layoutAndViewModeButtonsBecomeOneGroupEachInPlace() {
    #expect(
      ToolbarLayout.items(from: [
        "go.back", "view.single", "view.vertical", "view.asList", "go.forward", "view.asIcons",
      ]) == ["go.back", "group.layout", "group.viewMode", "go.forward"])
  }

  @Test func otherItemsKeepTheirOrder() {
    let items = ["view.refresh", "tools.run.x", "go.back", "search"]
    #expect(ToolbarLayout.items(from: items) == items)
  }

  @Test func spacesMayRepeatButNothingElseDoes() {
    let space = ToolbarLayout.space
    #expect(
      ToolbarLayout.items(from: [space, "go.back", space, "go.back", "group.layout", "view.single"])
        == [space, "go.back", space, "group.layout"])
  }

  @Test func aGroupIsFoundByItsItemID() {
    #expect(ToolbarLayout.Group(itemID: "group.viewMode") == .viewMode)
    #expect(ToolbarLayout.Group(itemID: "view.asList") == nil)
    #expect(ToolbarLayout.itemID(for: "view.horizontal") == "group.layout")
  }
}
