import Testing

@testable import FileTermCore

@MainActor struct CommandRegistryTests {
  @Test func statesBuildTheCommandsOnceAndMatchPerCommandAnswers() {
    var builds = 0
    let command = { (id: String, enabled: Bool, checked: Bool) in
      AppCommand(
        id: id, title: id, menuPath: ["Go"], isEnabled: { _ in enabled },
        disabledReason: { _ in "No." }, isChecked: { _ in checked }, handler: {})
    }
    let registry = CommandRegistry(
      commands: [command("base", true, false)],
      dynamicCommands: {
        builds += 1
        return [command("off", false, true), command("off", true, false)]
      },
      context: { CommandContext(hasBrowserWindow: true, hasKeyWindow: true, isLoading: false) })

    let states = registry.states()
    #expect(builds == 1)
    #expect(states.count == 2)
    #expect(states["base"]?.disabledReason == nil)
    #expect(states["base"]?.isChecked == false)
    // When a dynamic ID repeats, the first one wins, as it does for command(_:).
    #expect(states["off"]?.disabledReason == "No.")
    #expect(states["off"]?.isChecked == true)
    #expect(registry.disabledReason(for: "off") == "No.")
    #expect(registry.isChecked("off"))
  }

  @Test func selectedEntriesSkipsTheScanWithoutASelection() async throws {
    let provider = LocalFileSystemProvider()
    let pane = PaneModel(providers: [provider])
    #expect(await pane.navigate(to: Location(providerID: "local", path: "/")))
    #expect(!pane.entries.isEmpty)
    #expect(pane.selectedEntries.isEmpty)
    let first = try #require(pane.entries.first)
    pane.selection = [first.id]
    #expect(pane.selectedEntries.map(\.id) == [first.id])
  }

  @Test func dynamicCommandsAndCheckedStateUseTheCurrentContext() {
    var paths = ["/first"]
    var source = Location(providerID: "local", path: "/first")
    var target: Location?
    let registry = CommandRegistry(
      commands: [],
      dynamicCommands: {
        paths.map { path in
          AppCommand(
            id: path, title: path, menuPath: ["Go", "Recent Folders"],
            isEnabled: { $0.targetLocation != nil }, disabledReason: { _ in "Open two panes." },
            isChecked: { $0.sourceLocation?.path == path }, handler: {})
        }
      },
      context: {
        CommandContext(
          hasBrowserWindow: true, hasKeyWindow: true, isLoading: false,
          sourceLocation: source, targetLocation: target)
      })
    #expect(registry.isChecked("/first"))
    #expect(!registry.execute("/first"))
    target = Location(providerID: "local", path: "/second")
    #expect(registry.execute("/first"))
    source = Location(providerID: "local", path: "/second")
    #expect(!registry.isChecked("/first"))
    paths = ["/second"]
    #expect(registry.command("/first") == nil)
    #expect(registry.isChecked("/second"))
    #expect(registry.execute("/second"))
  }

  @Test func reevaluatesAvailabilityBeforeExecuting() {
    var hasWindow = false
    var executions = 0
    let registry = CommandRegistry(
      commands: [
        AppCommand(
          id: "test", title: "Test", menuPath: ["Go"],
          isEnabled: { $0.hasBrowserWindow },
          disabledReason: { _ in "Open a browser window first." },
          handler: { executions += 1 }
        )
      ],
      context: {
        CommandContext(hasBrowserWindow: hasWindow, hasKeyWindow: hasWindow, isLoading: false)
      }
    )
    #expect(registry.disabledReason(for: "test") == "Open a browser window first.")
    #expect(!registry.execute("test"))
    #expect(executions == 0)
    hasWindow = true
    #expect(registry.disabledReason(for: "test") == nil)
    #expect(registry.execute("test"))
    #expect(executions == 1)
    #expect(!registry.execute("unknown"))
  }
}
