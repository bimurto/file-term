import Darwin
import Foundation

/// The PATH of the user's login shell. Apps opened from Finder inherit launchd's short PATH, so
/// tools installed through Homebrew, nvm and the like would otherwise not be found.
public enum LoginShellPath {
  private final class Cache: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String: String] = [:]
    func set(_ newValue: [String: String]) {
      lock.lock()
      value = newValue
      lock.unlock()
    }
    func get() -> [String: String] {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
  }

  private static let marker = "__FILETERM_PATH__"
  private static let cache = Cache()
  private static let lookup = Task<[String: String], Never> {
    let found = await read(shell: userShell, timeout: .seconds(10)).map { ["PATH": $0] } ?? [:]
    cache.set(found)
    return found
  }

  /// Starts the lookup, so a later synchronous launch can use `loadedEnvironment`.
  public static func prepare() { _ = lookup }

  /// Waits for the lookup. Empty when it failed, leaving the inherited PATH in place.
  public static func environment() async -> [String: String] { await lookup.value }

  /// What the lookup has found so far, for launches that can't wait for it.
  public static var loadedEnvironment: [String: String] {
    prepare()
    return cache.get()
  }

  private static var userShell: String {
    if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
      return String(cString: shell)
    }
    return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
  }

  /// Interactive as well as login, because many people set PATH only in `.zshrc` or `.bashrc`.
  /// Doesn't wait for the process after the timeout: a background job started by a startup file
  /// can hold the output pipe open long after the shell has been terminated.
  static func read(shell: String, timeout: Duration) async -> String? {
    let (results, continuation) = AsyncStream.makeStream(of: String?.self)
    let command = "printf '\(marker)%s\(marker)' \"$PATH\""
    let work = Task {
      let output = try? await ProcessRunner.capture(shell, ["-ilc", command])
      continuation.yield(output.flatMap { $0.status == 0 ? parse($0.stdout) : nil })
    }
    Task {
      try? await Task.sleep(for: timeout)
      work.cancel()
      continuation.yield(nil)
    }
    for await result in results { return result }
    return nil
  }

  /// Startup files can print anything around the value, so only the text between markers counts.
  static func parse(_ output: String) -> String? {
    let parts = output.components(separatedBy: marker)
    guard parts.count >= 3, !parts[parts.count - 2].isEmpty else { return nil }
    return parts[parts.count - 2]
  }
}
