import FileTermCore
import Foundation
import Observation

/// State of the Batch Rename dialog: the items in the order shown in the pane and the rule list.
@MainActor @Observable final class BatchRenameModel: Identifiable {
  private(set) var items: [RenameItem]
  var rules: [RenameRule] { didSet { loadMetadataIfNeeded() } }
  /// Extension changes are a warning: Rename stays off until the user allows them.
  var allowExtensionChanges = false
  var presetName = ""
  private(set) var presets: [RenamePreset]
  /// Rename stays off while files are being read, because the preview isn't final yet.
  private(set) var isReadingMetadata = false
  @ObservationIgnored private var metadataRead = false
  @ObservationIgnored private let readMetadata: @Sendable ([RenameItem]) async -> [RenameItem]
  @ObservationIgnored private let now = Date()
  @ObservationIgnored private let existingNames: [String: Set<String>]
  @ObservationIgnored private let savePreset: (RenamePreset) -> Void
  @ObservationIgnored private let deletePreset: (UUID) -> Void
  @ObservationIgnored private let submit: ([(location: Location, name: String)]) -> Void

  init(
    items: [RenameItem], rules: [RenameRule] = [RenameRule(kind: .replaceText)],
    existingNames: [String: Set<String>] = [:], presets: [RenamePreset] = [],
    savePreset: @escaping (RenamePreset) -> Void = { _ in },
    deletePreset: @escaping (UUID) -> Void = { _ in },
    readMetadata: @escaping @Sendable ([RenameItem]) async -> [RenameItem] =
      RenameMetadataReader.enriched,
    submit: @escaping ([(location: Location, name: String)]) -> Void
  ) {
    self.items = items
    self.rules = rules
    self.existingNames = existingNames
    self.presets = presets
    self.savePreset = savePreset
    self.deletePreset = deletePreset
    self.readMetadata = readMetadata
    self.submit = submit
    loadMetadataIfNeeded()
  }

  nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

  /// Reads files once, and only if a rule uses what's in them, so opening the dialog stays instant.
  private func loadMetadataIfNeeded() {
    guard !metadataRead, rules.contains(where: { $0.kind == .addMetadata }) else { return }
    metadataRead = true
    isReadingMetadata = true
    let items = items
    let read = readMetadata
    Task { [weak self] in
      let enriched = await read(items)
      self?.items = enriched
      self?.isReadingMetadata = false
    }
  }

  var rows: [RenameRow] {
    BatchRenamePlanner.preview(
      items: items, rules: rules, now: now, existingNames: existingNames)
  }
  var changedCount: Int { rows.filter(\.isChanged).count }

  /// What the rows are blocked or warned about, e.g. "2 duplicate names".
  var issueSummary: [String] {
    let all = rows.flatMap(\.issues)
    return [RenameIssue.duplicateName, .invalidName, .nameExists, .extensionChanged].compactMap {
      issue in
      let count = all.filter { $0 == issue }.count
      return count == 0 ? nil : "\(count) × \(issue.message.lowercased())"
    }
  }

  var canRename: Bool {
    let current = rows
    return !isReadingMetadata && current.contains(where: \.isChanged)
      && !current.contains(where: \.hasError)
      && (allowExtensionChanges || !current.contains(where: \.hasWarning))
  }

  func addRule(_ kind: RenameRule.Kind) { rules.append(RenameRule(kind: kind)) }

  func removeRule(_ id: UUID) { rules.removeAll { $0.id == id } }

  func moveRule(_ id: UUID, by offset: Int) {
    guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
    let target = index + offset
    guard rules.indices.contains(target) else { return }
    rules.swapAt(index, target)
  }

  func saveAsPreset() {
    let name = presetName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty, !rules.isEmpty else { return }
    let preset = RenamePreset(name: name, rules: rules)
    presets.append(preset)
    savePreset(preset)
  }

  func load(_ preset: RenamePreset) {
    // Fresh IDs: loading twice must not give two rules the same identity.
    rules = preset.rules.map {
      var rule = $0
      rule.id = UUID()
      return rule
    }
  }

  func delete(_ preset: RenamePreset) {
    presets.removeAll { $0.id == preset.id }
    deletePreset(preset.id)
  }

  func rename() {
    guard canRename else { return }
    submit(rows.filter(\.isChanged).map { ($0.item.location, $0.proposed) })
  }
}
