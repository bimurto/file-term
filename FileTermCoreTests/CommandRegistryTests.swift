import Testing

@testable import FileTermCore

@MainActor struct CommandRegistryTests {
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
