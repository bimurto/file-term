import Testing

@testable import FileTermCore

@MainActor struct CommandRegistryTests {
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
