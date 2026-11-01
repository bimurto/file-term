import Foundation

/// Parsers for the directory listings FTP servers send: MLSD (RFC 3659) and the two `LIST`
/// layouts that are still common, Unix `ls -l` and DOS/IIS.
enum FTPListing {
  static func parseMLSD(_ text: String, in folder: Location, providerID: String) -> [FileEntry] {
    lines(text).compactMap { line in
      // "fact=value;fact=value; name": the name starts after the first space.
      guard let space = line.firstIndex(of: " ") else { return nil }
      let name = String(line[line.index(after: space)...])
      var facts: [String: String] = [:]
      for fact in line[..<space].split(separator: ";") {
        guard let equals = fact.firstIndex(of: "=") else { continue }
        facts[fact[..<equals].lowercased()] = String(fact[fact.index(after: equals)...])
      }
      guard let type = facts["type"]?.lowercased() else { return nil }
      let kind: FileEntry.Kind
      switch type {
      case "file": kind = .file
      case "dir": kind = .directory
      default:
        // Symbolic links are "OS.unix=slink:<target>".
        guard type.hasPrefix("os.unix=slink") || type.hasPrefix("os.unix=symlink") else {
          return nil
        }
        kind = .symbolicLink
      }
      guard FileName.isListable(name) else { return nil }
      return FileEntry(
        location: ProviderTransfer.child(folder, name), name: name, kind: kind,
        size: kind == .file ? facts["size"].flatMap { Int64($0) } : nil,
        createdAt: facts["create"].flatMap(mlsdDate),
        modifiedAt: facts["modify"].flatMap(mlsdDate),
        owner: facts["unix.owner"] ?? facts["unix.uid"],
        group: facts["unix.group"] ?? facts["unix.gid"],
        permissions: facts["unix.mode"].flatMap { Int($0, radix: 8) }.map { $0 & 0o7777 },
        isHidden: name.hasPrefix("."))
    }
  }

  static func parseList(
    _ text: String, in folder: Location, providerID: String, now: Date = Date()
  ) -> [FileEntry] {
    lines(text).compactMap { line in
      unixEntry(line, in: folder, now: now) ?? dosEntry(line, in: folder)
    }
  }

  // MARK: Unix

  private static let unixPattern = try! NSRegularExpression(
    pattern:
      #"^([\-dlbcps])([rwxsStT\-]{9})[+@.]?\s+\d+\s+(\S+)\s+(\S+)\s+(\d+)\s+(\w{3})\s+(\d{1,2})\s+(\d{4}|\d{1,2}:\d{2})\s(.+)$"#
  )

  private static func unixEntry(_ line: String, in folder: Location, now: Date) -> FileEntry? {
    let range = NSRange(line.startIndex..., in: line)
    guard let match = unixPattern.firstMatch(in: line, range: range) else { return nil }
    func group(_ index: Int) -> String {
      Range(match.range(at: index), in: line).map { String(line[$0]) } ?? ""
    }
    var name = group(9)
    let kind: FileEntry.Kind =
      switch group(1) {
      case "d": .directory
      case "l": .symbolicLink
      case "-": .file
      default: .other
      }
    if kind == .symbolicLink, let arrow = name.range(of: " -> ") {
      name = String(name[..<arrow.lowerBound])
    }
    guard FileName.isListable(name) else { return nil }
    return FileEntry(
      location: ProviderTransfer.child(folder, name), name: name, kind: kind,
      size: kind == .file ? Int64(group(5)) : nil,
      modifiedAt: listDate(month: group(6), day: group(7), yearOrTime: group(8), now: now),
      owner: group(3), group: group(4), permissions: permissions(group(2)),
      isHidden: name.hasPrefix("."))
  }

  private static func permissions(_ text: String) -> Int {
    var value = 0
    for (index, character) in text.enumerated() where !"-".contains(character) {
      let bit = 8 - index
      if index % 3 == 2, "sStT".contains(character) {
        if character == "s" || character == "t" { value |= 1 << bit }
      } else {
        value |= 1 << bit
      }
    }
    return value
  }

  private static let months = [
    "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
  ]

  /// `ls -l` shows a time for recent files and a year for older ones; servers give no zone, so
  /// the time is read as UTC.
  static func listDate(month: String, day: String, yearOrTime: String, now: Date) -> Date? {
    guard let monthIndex = months.firstIndex(of: month.lowercased()), let day = Int(day) else {
      return nil
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    var components = DateComponents(month: monthIndex + 1, day: day)
    if let colon = yearOrTime.firstIndex(of: ":") {
      components.hour = Int(yearOrTime[..<colon])
      components.minute = Int(yearOrTime[yearOrTime.index(after: colon)...])
      components.year = calendar.component(.year, from: now)
      guard let date = calendar.date(from: components) else { return nil }
      // A "recent" time cannot lie in the future, so it belongs to last year.
      if date > now.addingTimeInterval(24 * 3600) {
        components.year = (components.year ?? 0) - 1
        return calendar.date(from: components)
      }
      return date
    }
    components.year = Int(yearOrTime)
    return calendar.date(from: components)
  }

  // MARK: DOS

  private static let dosPattern = try! NSRegularExpression(
    pattern: #"^(\d{2})-(\d{2})-(\d{2,4})\s+(\d{1,2}):(\d{2})\s*(AM|PM)?\s+(<DIR>|\d+)\s+(.+)$"#,
    options: .caseInsensitive)

  private static func dosEntry(_ line: String, in folder: Location) -> FileEntry? {
    let range = NSRange(line.startIndex..., in: line)
    guard let match = dosPattern.firstMatch(in: line, range: range) else { return nil }
    func group(_ index: Int) -> String {
      Range(match.range(at: index), in: line).map { String(line[$0]) } ?? ""
    }
    let name = group(8)
    guard FileName.isListable(name) else { return nil }
    let isDirectory = group(7).uppercased() == "<DIR>"
    var year = Int(group(3)) ?? 0
    if year < 100 { year += year < 70 ? 2000 : 1900 }
    var hour = Int(group(4)) ?? 0
    switch group(6).uppercased() {
    case "PM": if hour < 12 { hour += 12 }
    case "AM": if hour == 12 { hour = 0 }
    default: break
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let date = calendar.date(
      from: DateComponents(
        year: year, month: Int(group(1)), day: Int(group(2)), hour: hour, minute: Int(group(5))))
    return FileEntry(
      location: ProviderTransfer.child(folder, name), name: name,
      kind: isDirectory ? .directory : .file, size: isDirectory ? nil : Int64(group(7)),
      modifiedAt: date, isHidden: name.hasPrefix("."))
  }

  // MARK: Shared

  private static func lines(_ text: String) -> [String] {
    text.split(
      omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
    )
    .map(String.init)
  }

  /// MLSD times are `YYYYMMDDHHMMSS[.fff]` in UTC.
  static func mlsdDate(_ text: String) -> Date? {
    let digits = text.prefix { $0 != "." }
    guard digits.count == 14 || digits.count == 8 else { return nil }
    let numbers = Array(digits).map { Int(String($0)) }
    guard !numbers.contains(nil) else { return nil }
    let values = numbers.compactMap { $0 }
    func number(_ range: Range<Int>) -> Int { values[range].reduce(0) { $0 * 10 + $1 } }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(
      from: DateComponents(
        year: number(0..<4), month: number(4..<6), day: number(6..<8),
        hour: digits.count == 14 ? number(8..<10) : 0,
        minute: digits.count == 14 ? number(10..<12) : 0,
        second: digits.count == 14 ? number(12..<14) : 0))
  }
}
