import Foundation
import Testing

@testable import FileTermCore

struct ICloudFilesTests {
  @Test func stateComesFromUbiquityAndDownloadStatus() {
    #expect(ICloudFileState(isUbiquitous: false, status: nil) == .notInICloud)
    #expect(ICloudFileState(isUbiquitous: true, status: .notDownloaded) == .cloudOnly)
    #expect(ICloudFileState(isUbiquitous: true, status: .current) == .downloaded)
    #expect(ICloudFileState(isUbiquitous: true, status: .downloaded) == .downloaded)
  }

  @Test func aTemporaryFileIsNotInICloud() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(ICloudFiles.state(of: url) == .notInICloud)
  }
}

struct DropboxLinksTests {
  @Test func readsPersonalAndBusinessFoldersFromInfoJSON() {
    let json = #"{"personal":{"path":"/U/me/Dropbox"},"business":{"path":"/U/me/Work"}}"#
    #expect(DropboxLinks.roots(infoJSON: Data(json.utf8)) == ["/U/me/Dropbox", "/U/me/Work"])
    #expect(DropboxLinks.roots(infoJSON: Data("nonsense".utf8)).isEmpty)
  }

  @Test func remotePathIsRelativeToTheRootAndNeverMatchesASiblingFolder() {
    let roots = ["/tmp/Dropbox"]
    #expect(DropboxLinks.remotePath(of: "/tmp/Dropbox/a/b é.txt", roots: roots) == "/a/b é.txt")
    #expect(DropboxLinks.remotePath(of: "/tmp/Dropbox", roots: roots) == nil)
    #expect(DropboxLinks.remotePath(of: "/tmp/Dropbox Backup/a.txt", roots: roots) == nil)
  }

  @Test func requestCarriesThePathAndToken() throws {
    let request = try DropboxLinks.request(remotePath: "/a “b”.txt", token: "secret")
    #expect(request.url?.scheme == "https")
    #expect(request.url?.host == "api.dropboxapi.com")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: String]
    #expect(body == ["path": "/a “b”.txt"])
  }

  @Test func linkHandlesNewExistingAndFailedResponses() throws {
    #expect(
      try DropboxLinks.link(status: 200, body: Data(#"{"url":"https://d/new"}"#.utf8))
        == "https://d/new")
    let existing = #"""
      {"error_summary":"shared_link_already_exists/..","error":{".tag":"shared_link_already_exists",
      "shared_link_already_exists":{"metadata":{"url":"https://d/old"}}}}
      """#
    #expect(try DropboxLinks.link(status: 409, body: Data(existing.utf8)) == "https://d/old")
    #expect(throws: DropboxLinkError.invalidToken) {
      try DropboxLinks.link(status: 401, body: Data())
    }
    #expect(throws: DropboxLinkError.api("path/not_found/..")) {
      try DropboxLinks.link(status: 409, body: Data(#"{"error_summary":"path/not_found/.."}"#.utf8))
    }
  }
}

struct DefaultFileViewerTests {
  private final class Store: @unchecked Sendable {
    var value: String?
    init(_ value: String?) { self.value = value }
    var viewer: DefaultFileViewer {
      DefaultFileViewer(read: { self.value }, write: { self.value = $0 })
    }
  }

  @Test func revertClearsTheValueWhenNothingWasSetBefore() {
    let store = Store(nil)
    let previous = store.viewer.enable("app")
    #expect(store.viewer.isDefault("app"))
    store.viewer.revert("app", to: previous)
    #expect(store.value == nil)
  }

  @Test func revertRestoresTheEarlierViewer() {
    let store = Store("com.other")
    let previous = store.viewer.enable("app")
    #expect(previous == "com.other")
    store.viewer.revert("app", to: previous)
    #expect(store.value == "com.other")
  }

  @Test func revertLeavesAViewerChosenLaterAlone() {
    let store = Store(nil)
    let previous = store.viewer.enable("app")
    store.value = "com.later"
    store.viewer.revert("app", to: previous)
    #expect(store.value == "com.later")
  }

  @Test func enablingTwiceDoesNotRememberItselfAsPrevious() {
    let store = Store("app")
    #expect(store.viewer.enable("app") == nil)
  }

  @Test func revealPlanGroupsFilesByFolderAndOpensFoldersAsThemselves() {
    let plan = RevealRequest.plan(paths: ["/a/1.txt", "/b", "/a/2.txt"]) { $0 == "/b" }
    #expect(
      plan == [
        RevealRequest(folder: "/a", selected: ["/a/1.txt", "/a/2.txt"]),
        RevealRequest(folder: "/b", selected: []),
      ])
  }
}

struct FavoritesImportTests {
  private let file = Data(
    #"""
    {"favorites":[
      {"title":"Work","childItems":[
        {"UUID":"1","type":"Local","attributes":{"Name":"Repo","Path":"/Users/me/repo"}},
        {"UUID":"2","type":"SFTP","attributes":{"name":"Server"}}
      ]},
      {"title":"Other","childItems":[
        {"UUID":"3","type":"Local","attributes":{"name":"Again","path":"/Users/me/repo"}},
        {"UUID":"4","type":"Local","attributes":{"name":"Docs","path":"/Users/me/docs"}},
        {"UUID":"5","type":"Local","attributes":{"name":"Web","path":"https://example.com"}}
      ]}
    ]}
    """#.utf8)

  @Test func previewListsLocalItemsAndNamesSkippedServers() throws {
    let preview = try FavoritesImport.preview(data: file, existing: [])
    #expect(preview.favorites.map(\.name) == ["Repo", "Again", "Docs"])
    #expect(preview.favorites.map(\.group) == ["Work", "Other", "Other"])
    #expect(preview.favorites.map(\.isDuplicate) == [false, true, false])
    #expect(preview.skippedRemote == ["Server"])
  }

  @Test func anExistingFavoriteIsMarkedDuplicate() throws {
    let existing = [FavoriteNode.item(.init(name: "Mine", target: .local(path: "/Users/me/docs")))]
    let preview = try FavoritesImport.preview(data: file, existing: existing)
    #expect(preview.favorites.first { $0.name == "Docs" }?.isDuplicate == true)
  }

  @Test func otherFilesAreRejected() {
    #expect(throws: FavoritesImportError.unrecognized) {
      try FavoritesImport.preview(data: Data("{}".utf8), existing: [])
    }
    #expect(throws: FavoritesImportError.unrecognized) {
      try FavoritesImport.preview(data: Data("not json".utf8), existing: [])
    }
  }

  @Test func mergeKeepsExistingFavoritesAndNeverAddsAPathTwice() throws {
    let mine = FavoriteItem(name: "My name", target: .local(path: "/Users/me/repo"))
    let group = FavoriteGroup(name: "Other", items: [])
    let existing: [FavoriteNode] = [.item(mine), .group(group)]
    let preview = try FavoritesImport.preview(data: file, existing: [])
    let merged = FavoritesImport.merge(preview.favorites, into: existing)
    #expect(merged[0] == .item(mine))
    #expect(merged.count == 2)
    guard case .group(let other) = merged[1] else {
      Issue.record("expected a group")
      return
    }
    #expect(other.id == group.id)
    #expect(other.items.map(\.name) == ["Docs"])
  }
}

struct PrerequisitesTests {
  private func checker(files: Set<String> = [], tools: Set<CompareTool> = []) -> Prerequisites {
    Prerequisites(
      fileExists: { files.contains($0) }, isExecutable: { files.contains($0) },
      searchPath: ["/usr/bin", "/opt/bin"], compareToolInstalled: { tools.contains($0) })
  }

  @Test func gitRepositoryIsFoundInAParentFolder() {
    let check = checker(files: ["/r/.git"])
    #expect(check.missing(.gitRepository(folder: "/r/a/b")) == nil)
    #expect(check.missing(.gitRepository(folder: "/other")) == "/other is not in a Git repository.")
  }

  @Test func compareToolMustBeInstalled() {
    #expect(checker(tools: [.bbedit]).missing(.compareTool(.bbedit)) == nil)
    #expect(checker().missing(.compareTool(.bbedit))?.contains("BBEdit is not installed") == true)
  }

  @Test func commandLineProgramsAreFoundOnThePathOrByAbsolutePath() {
    let check = checker(files: ["/opt/bin/rg", "/x/run"])
    #expect(check.missing(.commandLineProgram("rg")) == nil)
    #expect(check.missing(.commandLineProgram("/x/run")) == nil)
    #expect(check.missing(.commandLineProgram("nope"))?.contains("“nope”") == true)
  }

  @Test func remoteAccountsNeedAServerAndObjectStoresNeedKeys() {
    let check = checker()
    #expect(check.missing(.remoteAccount(.s3, server: "", username: "k", hasPassword: true)) == nil)
    #expect(
      check.missing(.remoteAccount(.sftp, server: "", username: "", hasPassword: false)) != nil)
    #expect(
      check.missing(.remoteAccount(.sftp, server: "h", username: "", hasPassword: false)) == nil)
    #expect(
      check.missing(.remoteAccount(.s3, server: "h", username: "", hasPassword: true))?
        .contains("Access Key ID") == true)
    #expect(
      check.missing(.remoteAccount(.s3, server: "h", username: "k", hasPassword: false))?
        .contains("Secret Access Key") == true)
    #expect(
      check.missing(.remoteAccount(.s3, server: "h", username: "k", hasPassword: true)) == nil)
  }

  @Test func previewSupportFollowsTheFileType() {
    let check = checker()
    #expect(check.missing(.previewSupport(path: "/a.png")) == nil)
    #expect(check.missing(.previewSupport(path: "/a.txt")) == nil)
    #expect(check.missing(.previewSupport(path: "/a.zzzunknown")) != nil)
    #expect(check.missing(.previewSupport(path: "/noextension")) != nil)
  }

  @Test func missingListsOnlyWhatIsNotMet() {
    let check = checker(files: ["/r/.git"])
    #expect(
      check.missing([.gitRepository(folder: "/r"), .commandLineProgram("nope")]).count == 1)
  }

  @Test func toolsNameTheProgramOnlyWhenTheShellWouldNotDecide() {
    func program(_ command: String) -> String? {
      UserTool(name: "t", command: command).requiredProgram
    }
    #expect(program("rg foo $SOURCE_PATH") == "rg")
    #expect(program("/opt/bin/rg foo") == "/opt/bin/rg")
    #expect(program("cd $SOURCE_PATH && make") == nil)
    #expect(program("$EDITOR file") == nil)
    #expect(program("FOO=1 make") == nil)
    #expect(program("(make)") == nil)
    #expect(program("  ") == nil)
  }
}
