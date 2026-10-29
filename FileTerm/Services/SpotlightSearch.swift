import FileTermCore
import Foundation

/// Spotlight (NSMetadataQuery) search for local folders, including file contents.
@MainActor final class SpotlightSearch {
  private let query = NSMetadataQuery()
  private var continuation: CheckedContinuation<[URL], any Error>?
  private var observer: (any NSObjectProtocol)?
  private var cancelled = false

  static func run(_ search: SearchQuery, in root: Location, provider: LocalFileSystemProvider)
    async throws -> [FileEntry]
  {
    let runner = SpotlightSearch()
    let rootURL = try provider.url(for: root)
    let urls = try await withTaskCancellationHandler {
      try await runner.start(search, root: rootURL)
    } onCancel: {
      Task { @MainActor in runner.finish(.failure(CancellationError())) }
    }
    var entries: [FileEntry] = []
    for url in urls.prefix(2000) {
      try Task.checkCancellation()
      if let entry = try? await provider.stat(provider.location(for: url)) { entries.append(entry) }
    }
    return entries
  }

  static func predicate(for search: SearchQuery) -> NSPredicate {
    let text = search.text.trimmingCharacters(in: .whitespaces)
    var parts: [NSPredicate] = []
    if search.matchName {
      parts.append(NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, text))
    }
    if search.matchExtension {
      let ext = text.trimmingCharacters(in: CharacterSet(charactersIn: "."))
      parts.append(NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*." + ext))
    }
    if search.matchTag {
      parts.append(NSPredicate(format: "%K CONTAINS[cd] %@", "kMDItemUserTags", text))
    }
    if search.matchContents {
      parts.append(NSPredicate(format: "%K CONTAINS[cd] %@", "kMDItemTextContent", text))
    }
    if parts.isEmpty {
      parts.append(NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, text))
    }
    return NSCompoundPredicate(orPredicateWithSubpredicates: parts)
  }

  private func start(_ search: SearchQuery, root: URL) async throws -> [URL] {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      if cancelled {
        finish(.failure(CancellationError()))
        return
      }
      query.predicate = Self.predicate(for: search)
      query.searchScopes = [root.path]
      observer = NotificationCenter.default.addObserver(
        forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.query.disableUpdates()
          let rootPath = root.standardizedFileURL.path
          let urls = (self.query.results as? [NSMetadataItem] ?? []).compactMap { item -> URL? in
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { return nil }
            let url = URL(fileURLWithPath: path)
            let relative = String(path.dropFirst(rootPath.count)).split(separator: "/")
            if !search.includeSubfolders, relative.count > 1 { return nil }
            if !search.includeHidden, relative.contains(where: { $0.hasPrefix(".") }) {
              return nil
            }
            return url
          }
          self.finish(.success(urls))
        }
      }
      if !query.start() { finish(.failure(FileSystemError.io("Spotlight could not start."))) }
    }
  }

  private func finish(_ result: Result<[URL], any Error>) {
    guard let continuation else {
      if case .failure = result { cancelled = true }
      return
    }
    self.continuation = nil
    query.stop()
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    continuation.resume(with: result)
  }
}
