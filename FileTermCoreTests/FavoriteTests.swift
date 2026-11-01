import Foundation
import Testing

@testable import FileTermCore

struct FavoriteTests {
  private let docs = FavoriteItem(name: "Docs", target: .local(path: "/Users/me/Documents"))
  private let server = FavoriteItem(
    name: "Server",
    target: .connection(profileID: UUID(), paths: ["/var/www", "/home/me"]))
  private let group = FavoriteGroup(name: "Work")

  @Test func roundTripsThroughJSON() throws {
    let list: [FavoriteNode] = [.item(docs), .group(FavoriteGroup(name: "Work", items: [server]))]
    let data = try JSONEncoder().encode(list)
    #expect(try JSONDecoder().decode([FavoriteNode].self, from: data) == list)
  }

  @Test func movesAnItemIntoAGroupAndBackOut() {
    let list: [FavoriteNode] = [.item(docs), .group(group)]
    let inside = list.moving(docs.id, intoGroup: group.id)
    #expect(inside.count == 1)
    #expect(inside.allItems == [docs])
    guard case .group(let moved) = inside[0] else {
      Issue.record("expected a group")
      return
    }
    #expect(moved.items == [docs])

    let outside = inside.moving(docs.id, intoGroup: nil)
    #expect(outside.count == 2)
    #expect(outside.last == .item(docs))
  }

  @Test func movingToAnUnknownGroupOrItemChangesNothing() {
    let list: [FavoriteNode] = [.item(docs), .group(group)]
    #expect(list.moving(docs.id, intoGroup: UUID()) == list)
    #expect(list.moving(UUID(), intoGroup: group.id) == list)
  }

  @Test func removesItemsAndWholeGroups() {
    let list: [FavoriteNode] = [.item(docs), .group(FavoriteGroup(name: "Work", items: [server]))]
    #expect(list.removing(server.id).allItems == [docs])
    #expect(list.removing(list[1].id) == [.item(docs)])
  }

  @Test func replacesAnItemInsideAGroup() {
    let list: [FavoriteNode] = [.group(FavoriteGroup(name: "Work", items: [docs]))]
    var renamed = docs
    renamed.name = "Papers"
    #expect(list.replacing(.item(renamed)).allItems.map(\.name) == ["Papers"])
  }

  @Test func addingSkipsATargetAlreadyInTheListOrAGroup() {
    let path = FavoriteItem.Target.local(path: "/a")
    let group = FavoriteGroup(name: "G", items: [FavoriteItem(name: "A", target: path)])
    let nodes: [FavoriteNode] = [.group(group)]
    #expect(nodes.adding(FavoriteItem(name: "Again", target: path)).count == 1)
    let added = nodes.adding(FavoriteItem(name: "B", target: .local(path: "/b")))
    #expect(added.count == 2)
    #expect(added.allItems.last?.name == "B")
  }

  @Test func iCloudDriveSitsInsideMobileDocuments() {
    #expect(FavoriteItem.iCloudDrivePath.hasSuffix("/Library/Mobile Documents/com~apple~CloudDocs"))
  }
}

struct FavoritesSyncPayloadTests {
  @Test func roundTripsOnlyTheFavoritesList() throws {
    let list: [FavoriteNode] = [
      .item(FavoriteItem(name: "Docs", target: .local(path: "/Users/me/Documents"))),
      .group(FavoriteGroup(name: "Work")),
    ]
    let data = try FavoritesSyncPayload(favorites: list).encoded()
    let payload = try FavoritesSyncPayload.decode(data)
    #expect(payload.favorites == list)
    #expect(payload.version == FavoritesSyncPayload.currentVersion)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(Set(object?.keys.map { $0 } ?? []) == ["version", "favorites"])
  }

  @Test func refusesDataFromANewerVersion() throws {
    let data = try FavoritesSyncPayload(favorites: [], version: 99).encoded()
    #expect(throws: FavoritesSyncError.newerVersion) { try FavoritesSyncPayload.decode(data) }
  }
}
