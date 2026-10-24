import CoreServices
import Foundation

/// Watches folders with FSEvents and reports which watched folders changed (debounced).
@MainActor final class FolderWatcher {
  var onChange: ((Set<String>) -> Void)?
  private var stream: FSEventStreamRef?
  private var watched: Set<String> = []
  private var box: Box?

  private final class Box: @unchecked Sendable {
    let watched: Set<String>
    let handler: @Sendable (Set<String>) -> Void
    init(watched: Set<String>, handler: @escaping @Sendable (Set<String>) -> Void) {
      self.watched = watched
      self.handler = handler
    }
  }

  func watch(_ paths: Set<String>) {
    guard paths != watched else { return }
    stop()
    watched = paths
    guard !paths.isEmpty else { return }
    let box = Box(watched: paths) { [weak self] changed in
      Task { @MainActor in self?.onChange?(changed) }
    }
    self.box = box
    var context = FSEventStreamContext(
      version: 0, info: Unmanaged.passUnretained(box).toOpaque(), retain: nil, release: nil,
      copyDescription: nil)
    let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
      guard let info else { return }
      let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
      let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
      var changed: Set<String> = []
      for path in paths.prefix(count) {
        let parent = (path as NSString).deletingLastPathComponent
        for folder in box.watched where folder == path || folder == parent {
          changed.insert(folder)
        }
      }
      if !changed.isEmpty { box.handler(changed) }
    }
    let flags = UInt32(
      kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents
        | kFSEventStreamCreateFlagNoDefer)
    guard
      let stream = FSEventStreamCreate(
        kCFAllocatorDefault, callback, &context, Array(paths) as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags)
    else { return }
    FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
    FSEventStreamStart(stream)
    self.stream = stream
  }

  private func stop() {
    if let stream {
      FSEventStreamStop(stream)
      FSEventStreamInvalidate(stream)
      FSEventStreamRelease(stream)
    }
    stream = nil
    box = nil
    watched = []
  }
}
