import FileTermCore
import Foundation
import Observation

/// State of the Sync dialog: the roots, the options and the analysed list of actions. Any option
/// change re-runs the analysis, and Synchronize stays off until it has finished.
@MainActor @Observable final class SyncDialogModel: Identifiable {
  let left: Location
  let right: Location
  let leftLabel: String
  let rightLabel: String
  var options: SyncOptions {
    didSet { if options != oldValue { analyze(after: .milliseconds(300)) } }
  }
  private(set) var actions: [SyncAction] = []
  private(set) var isAnalyzing = false
  private(set) var errorMessage: String?
  @ObservationIgnored private let registry: ProviderRegistry
  @ObservationIgnored private let submit: ([SyncAction], Location, Location) -> Void
  @ObservationIgnored private var task: Task<Void, Never>?

  init(
    left: Location, right: Location, leftLabel: String, rightLabel: String,
    options: SyncOptions = SyncOptions(), registry: ProviderRegistry,
    submit: @escaping ([SyncAction], Location, Location) -> Void
  ) {
    self.left = left
    self.right = right
    self.leftLabel = leftLabel
    self.rightLabel = rightLabel
    self.options = options
    self.registry = registry
    self.submit = submit
  }

  nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

  var hasRemoteSide: Bool { left.providerID != "local" || right.providerID != "local" }
  var checkedCount: Int { actions.filter(\.isChecked).count }
  var canSynchronize: Bool { !isAnalyzing && errorMessage == nil && checkedCount > 0 }

  func analyze(after delay: Duration = .zero) {
    task?.cancel()
    isAnalyzing = true
    errorMessage = nil
    let (left, right, options, registry) = (left, right, options, registry)
    task = Task {
      if delay > .zero { try? await Task.sleep(for: delay) }
      guard !Task.isCancelled else { return }
      do {
        let result = try await SyncAnalyzer.analyze(
          left: left, right: right, options: options, registry: registry)
        guard !Task.isCancelled else { return }
        actions = result
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        actions = []
        errorMessage = error.localizedDescription
      }
      isAnalyzing = false
    }
  }

  func cancel() { task?.cancel() }

  func setChecked(_ id: String, _ value: Bool) {
    guard let index = actions.firstIndex(where: { $0.id == id }), actions[index].isRunnable else {
      return
    }
    actions[index].isChecked = value
  }

  func setConflictDirection(_ id: String, _ side: SyncAction.Side) {
    guard let index = actions.firstIndex(where: { $0.id == id }) else { return }
    actions[index].towards = side
  }

  func synchronize() {
    guard canSynchronize else { return }
    submit(actions, left, right)
  }
}
