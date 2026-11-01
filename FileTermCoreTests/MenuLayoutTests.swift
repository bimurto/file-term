import FileTermCore
import Testing

struct MenuLayoutTests {
  @Test func arrangesCommandsIntoTheTablesGroupsAndOrder() {
    let keys = ["file.close", "file.newWindow", "file.closeTab", "file.newTab"]
    let groups = MenuLayout.arrange(keys, in: ["File"]).map { $0.map { keys[$0] } }
    #expect(groups == [["file.newWindow", "file.newTab"], ["file.closeTab", "file.close"]])
  }

  @Test func closeWindowIsTheLastItemInTheFileMenu() {
    let keys = ["file.close", "file.closeOtherTabs", "file.closeTab", "file.find", "Tags"]
    let last = MenuLayout.arrange(keys, in: ["File"]).last?.last
    #expect(last.map { keys[$0] } == "file.close")
  }

  @Test func unlistedCommandsGoInAFinalGroupInRegistryOrder() {
    let keys = ["file.future2", "file.newTab", "file.future1"]
    let groups = MenuLayout.arrange(keys, in: ["File"]).map { $0.map { keys[$0] } }
    #expect(groups == [["file.newTab"], ["file.future2", "file.future1"]])
    #expect(!MenuLayout.isListed("file.future1", in: ["File"]))
  }

  @Test func aMenuWithoutATableKeepsItsOrderInOneGroup() {
    #expect(MenuLayout.arrange(["b", "a"], in: ["Go", "Favorites"]) == [[0, 1]])
    #expect(MenuLayout.arrange([], in: ["Go", "Favorites"]).isEmpty)
    #expect(MenuLayout.isListed("anything", in: ["Go", "Favorites"]))
  }

  @Test func numberedTabCommandsMatchTheirFamily() {
    #expect(MenuLayout.isListed("window.tab3", in: ["Window"]))
    #expect(!MenuLayout.isListed("window.tabs", in: ["Window"]))
  }

  @Test(arguments: [
    ([MenuLayout.Row.item, .separator, .item], [Int]()),
    ([.separator, .item], [0]),
    ([.item, .separator], [1]),
    ([.item, .separator, .separator, .item], [2]),
    ([.item, .separator, .hiddenItem, .separator, .item], [3]),
    ([.item, .separator, .hiddenItem], [1]),
    ([.hiddenItem, .separator, .item], [1]),
    ([.separator, .separator], [0, 1]),
  ])
  func hidesSeparatorsThatAreFirstLastOrRepeated(rows: [MenuLayout.Row], hidden: [Int]) {
    #expect(MenuLayout.separatorsToHide(rows) == Set(hidden))
  }
}
