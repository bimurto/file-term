import AppKit
import Darwin
import Foundation

struct FileMetadata: Sendable {
  let url: URL
  let device: UInt64
  let inode: UInt64
  let bytes: Int64
  let created: Date
  let modified: Date
  let accessed: Date
  let mode: UInt16
  let ownerID: UInt32
  let groupID: UInt32
  let owner: String
  let group: String
  let hidden: Bool
  let locked: Bool
  let isSymbolicLink: Bool
  let tags: [String]
  let comment: String
  /// A nonmutating descriptor-based xattr probe runs during every load.
  let commentDisabledReason: String?
}

struct MetadataAccount: Identifiable, Sendable {
  let id: UInt32
  let name: String
}

/// All filesystem work runs off the main actor. Mutations never follow the final symlink,
/// are nonrecursive, and verify the opened inode against the inspected item before editing.
/// Parent-directory symlinks are followed. No privilege escalation or ACL rewriting is done.
actor FileMetadataService {
  enum Change: Sendable {
    case tags([String])
    case comment(String)
    case permissions(UInt16)
    case owner(UInt32)
    case group(UInt32)
    case locked(Bool)
  }

  enum MetadataError: LocalizedError {
    case symbolicLink, changedItem, invalidPermissions, unsupportedFile
    var errorDescription: String? {
      switch self {
      case .symbolicLink:
        return
          "Symbolic links are read-only in the inspector. Inspect the target separately to edit it."
      case .changedItem:
        return "This item has changed since it was inspected. Refresh and try again."
      case .invalidPermissions: return "Enter three or four octal digits (0–7)."
      case .unsupportedFile: return "Only regular files and folders can be edited in the inspector."
      }
    }
  }

  static func permissions(from text: String) throws -> UInt16 {
    guard (3...4).contains(text.count), text.allSatisfy({ ("0"..."7").contains(String($0)) }),
      let value = UInt16(text, radix: 8), value <= 0o7777
    else { throw MetadataError.invalidPermissions }
    return value
  }

  func load(_ url: URL) throws -> FileMetadata {
    let info = try status(url)
    let symlink = info.st_mode & S_IFMT == S_IFLNK
    var tags: [String] = []
    var comment = ""
    var commentDisabledReason: String? =
      symlink ? "Comments cannot be edited on symbolic links." : nil
    if !symlink, info.st_mode & S_IFMT == S_IFREG || info.st_mode & S_IFMT == S_IFDIR {
      let fd = try openVerified(url, info: info)
      defer { close(fd) }
      // Probe the actual item without writing, rather than assuming its volume supports xattrs.
      // flistxattr is a public Darwin API; no NSURL volumeSupportsExtendedAttributesKey exists.
      if flistxattr(fd, nil, 0, 0) < 0 {
        if errno == ENOTSUP {
          commentDisabledReason =
            "This filesystem does not support extended attributes. Finder comments and tags are unavailable."
        } else {
          throw posixError()
        }
      }
      if commentDisabledReason == nil {
        do {
          if let data = try attribute("com.apple.metadata:_kMDItemUserTags", fd: fd) {
            tags =
              (try PropertyListSerialization.propertyList(from: data, format: nil)) as? [String]
              ?? []
          }
          if let data = try attribute("com.apple.metadata:kMDItemFinderComment", fd: fd) {
            comment =
              (try PropertyListSerialization.propertyList(from: data, format: nil)) as? String ?? ""
          }
        } catch let error as NSError
          where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOTSUP)
        {
          commentDisabledReason =
            "This filesystem does not support Finder metadata extended attributes."
        }
      }
    } else if !symlink {
      commentDisabledReason = "Comments are only supported for regular files and folders."
    }
    return FileMetadata(
      url: url, device: UInt64(info.st_dev), inode: UInt64(info.st_ino), bytes: info.st_size,
      created: date(info.st_birthtimespec), modified: date(info.st_mtimespec),
      accessed: date(info.st_atimespec), mode: UInt16(info.st_mode & 0o7777),
      ownerID: info.st_uid, groupID: info.st_gid,
      owner: getpwuid(info.st_uid).map { String(cString: $0.pointee.pw_name) }
        ?? String(info.st_uid),
      group: getgrgid(info.st_gid).map { String(cString: $0.pointee.gr_name) }
        ?? String(info.st_gid),
      hidden: url.lastPathComponent.hasPrefix(".") || info.st_flags & UInt32(UF_HIDDEN) != 0,
      locked: info.st_flags & UInt32(UF_IMMUTABLE) != 0, isSymbolicLink: symlink,
      tags: tags, comment: comment, commentDisabledReason: commentDisabledReason)
  }

  func accounts() -> (owners: [MetadataAccount], groups: [MetadataAccount]) {
    var owners: [MetadataAccount] = []
    var groups: [MetadataAccount] = []
    setpwent()
    while let entry = getpwent() {
      owners.append(
        MetadataAccount(id: entry.pointee.pw_uid, name: String(cString: entry.pointee.pw_name)))
    }
    endpwent()
    setgrent()
    while let entry = getgrent() {
      groups.append(
        MetadataAccount(id: entry.pointee.gr_gid, name: String(cString: entry.pointee.gr_name)))
    }
    endgrent()
    return (owners.sorted { $0.name < $1.name }, groups.sorted { $0.name < $1.name })
  }

  func apply(_ change: Change, to snapshot: FileMetadata) throws {
    guard !snapshot.isSymbolicLink else { throw MetadataError.symbolicLink }
    let info = try status(snapshot.url)
    guard UInt64(info.st_dev) == snapshot.device, UInt64(info.st_ino) == snapshot.inode else {
      throw MetadataError.changedItem
    }
    let fd = try openVerified(snapshot.url, info: info)
    defer { close(fd) }
    let result: Int32
    switch change {
    case .permissions(let mode):
      guard mode <= 0o7777 else { throw MetadataError.invalidPermissions }
      result = fchmod(fd, mode_t(mode))
    case .owner(let id): result = fchown(fd, uid_t(id), gid_t.max)
    case .group(let id): result = fchown(fd, uid_t.max, gid_t(id))
    case .locked(let locked):
      result = fchflags(
        fd, locked ? info.st_flags | UInt32(UF_IMMUTABLE) : info.st_flags & ~UInt32(UF_IMMUTABLE))
    case .tags(let tags):
      try writeAttribute("com.apple.metadata:_kMDItemUserTags", value: tags, fd: fd)
      return
    case .comment(let text):
      try writeAttribute("com.apple.metadata:kMDItemFinderComment", value: text, fd: fd)
      return
    }
    guard result == 0 else { throw posixError() }
  }

  private func status(_ url: URL) throws -> stat {
    guard url.isFileURL else { throw MetadataError.unsupportedFile }
    var info = stat()
    guard url.withUnsafeFileSystemRepresentation({ lstat($0!, &info) }) == 0 else {
      throw posixError()
    }
    return info
  }

  private func openVerified(_ url: URL, info: stat) throws -> Int32 {
    guard info.st_mode & S_IFMT != S_IFLNK else { throw MetadataError.symbolicLink }
    guard info.st_mode & S_IFMT == S_IFREG || info.st_mode & S_IFMT == S_IFDIR else {
      throw MetadataError.unsupportedFile
    }
    let fd = url.withUnsafeFileSystemRepresentation {
      open($0!, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    }
    guard fd >= 0 else { throw posixError() }
    var opened = stat()
    guard fstat(fd, &opened) == 0 else {
      let error = posixError()
      close(fd)
      throw error
    }
    guard opened.st_dev == info.st_dev, opened.st_ino == info.st_ino else {
      close(fd)
      throw MetadataError.changedItem
    }
    return fd
  }

  private func attribute(_ name: String, fd: Int32) throws -> Data? {
    let size = fgetxattr(fd, name, nil, 0, 0, 0)
    if size < 0 {
      if errno == ENOATTR { return nil }
      throw posixError()
    }
    var data = Data(count: size)
    let count = data.withUnsafeMutableBytes { fgetxattr(fd, name, $0.baseAddress, size, 0, 0) }
    guard count >= 0 else { throw posixError() }
    data.count = count
    return data
  }

  private func writeAttribute(_ name: String, value: Any, fd: Int32) throws {
    let data = try PropertyListSerialization.data(
      fromPropertyList: value, format: .binary, options: 0)
    let result = data.withUnsafeBytes { fsetxattr(fd, name, $0.baseAddress, data.count, 0, 0) }
    guard result == 0 else { throw posixError() }
  }

  private func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
  private func date(_ value: timespec) -> Date {
    Date(timeIntervalSince1970: Double(value.tv_sec) + Double(value.tv_nsec) / 1_000_000_000)
  }

  /// Public NSWorkspace APIs, macOS 12+. The system handles any required consent.
  @MainActor static func setOpeningApplication(_ application: URL, for item: URL, changeAll: Bool)
    async throws
  {
    let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
    guard values.isSymbolicLink != true else { throw MetadataError.symbolicLink }
    if changeAll {
      try await NSWorkspace.shared.setDefaultApplication(
        at: application, toOpenContentTypeOfFileAt: item)
    } else {
      try await NSWorkspace.shared.setDefaultApplication(at: application, toOpenFileAt: item)
    }
  }
}
