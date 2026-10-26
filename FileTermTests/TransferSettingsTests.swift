import FileTermCore
import Foundation
import Testing

@testable import FileTerm

@MainActor struct TransferSettingsTests {
  @Test func transferDefaults() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let preferences = AppSettings(suite: suite).transfers
    #expect(preferences == TransferPreferences())
    #expect(preferences.replacePolicy == .ask)
    #expect(preferences.mergePolicy == .ask)
    #expect(preferences.resumePolicy == .ask)
    #expect(!preferences.limitUpload && !preferences.limitDownload)
    #expect(!preferences.automaticallyRetry)
    #expect(preferences.maximumRetries == 5)
    #expect(preferences.maximumConcurrent == 5)
    #expect(preferences.verification == .none)
  }

  @Test func transferPreferencesRoundTripThroughDefaults() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let settings = AppSettings(suite: suite)
    settings.transfers.replacePolicy = .replaceOlder
    settings.transfers.mergePolicy = .merge
    settings.transfers.resumePolicy = .skip
    settings.transfers.limitUpload = true
    settings.transfers.limitDownload = true
    settings.transfers.uploadBytesPerSecond = 2_048
    settings.transfers.downloadBytesPerSecond = 4_096
    settings.transfers.automaticallyRetry = true
    settings.transfers.maximumRetries = 3
    settings.transfers.maximumConcurrent = 2
    settings.transfers.verification = .checksum
    #expect(AppSettings(suite: suite).transfers == settings.transfers)
    #expect(
      try JSONDecoder().decode(
        TransferPreferences.self,
        from: JSONEncoder().encode(settings.transfers)) == settings.transfers)
  }

  @Test func corruptTransferPreferencesFallBackWithoutChangingTerminalSettings() throws {
    let name = "com.fileterm.tests.\(UUID().uuidString)"
    let suite = try #require(UserDefaults(suiteName: name))
    defer { suite.removePersistentDomain(forName: name) }
    let settings = AppSettings(suite: suite)
    settings.terminal.fontSize = 18
    suite.set(Data("not-json".utf8), forKey: "transferPreferences")
    let restored = AppSettings(suite: suite)
    #expect(restored.transfers == TransferPreferences())
    #expect(restored.terminal.fontSize == 18)
  }
}
