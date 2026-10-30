import Foundation

/// Provider-agnostic scanning search (works for any `FileSystemProvider`).
public enum BuiltInSearch {
  public static func run(
    _ query: SearchQuery, in root: Location, provider: any FileSystemProvider,
    limit: Int = 5000
  ) async throws -> [FileEntry] {
    guard !query.isEmpty else { return [] }
    var results: [FileEntry] = []
    var queue = [root]
    var visited: Set<Location> = [root]
    while !queue.isEmpty, results.count < limit {
      try Task.checkCancellation()
      let folder = queue.removeFirst()
      let entries: [FileEntry]
      do { entries = try await provider.list(folder, includeHidden: query.includeHidden) } catch {
        if folder == root { throw error }
        continue  // unreadable subfolders are skipped
      }
      for entry in entries {
        try Task.checkCancellation()
        if query.matchesMetadata(entry) {
          results.append(entry)
        } else if query.matchContents, entry.kind == .file,
          await contains(query.text, in: entry.location, provider: provider)
        {
          results.append(entry)
        }
        if entry.kind == .directory, query.includeSubfolders,
          visited.insert(entry.location).inserted
        {
          queue.append(entry.location)
        }
      }
    }
    return results
  }

  static func contains(_ text: String, in location: Location, provider: any FileSystemProvider)
    async -> Bool
  {
    let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
    guard !needle.isEmpty, let reader = try? await provider.read(location) else { return false }
    var carry = ""
    var total = 0
    while let chunk = try? await reader.next() {
      total += chunk.count
      guard let string = String(data: chunk, encoding: .utf8)?.lowercased() else { return false }
      if (carry + string).contains(needle) { return true }
      carry = String((carry + string).suffix(max(needle.count - 1, 0)))
      if total > 4_000_000 { break }
    }
    return false
  }
}
