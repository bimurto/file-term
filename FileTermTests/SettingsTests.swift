import Foundation
import Testing

@testable import FileTerm

@MainActor struct SettingsTests {
  @Test func persistsSettingsInAnIsolatedSuite() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let initial = AppSettings(suite: suite)
    #expect(initial.visiblePanels.isEmpty)
    #expect(initial.selectedCategory == "General")
    initial.toggle(.preview)
    initial.selectedCategory = "Themes"
    let restored = AppSettings(suite: suite)
    #expect(restored.isVisible(.preview))
    #expect(restored.selectedCategory == "Themes")
    #expect(SettingsCategory.allCases.count == 7)
  }
}
