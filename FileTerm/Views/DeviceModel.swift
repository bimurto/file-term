import AppKit
import FileTermCore
import Foundation
import Observation

struct MountedVolume: Identifiable, Equatable, Sendable {
  var id: String { url.path }
  let url: URL
  let name: String
  let isEjectable: Bool
  let isInternal: Bool
  /// False for network volumes, such as a mounted SMB share.
  let isLocal: Bool
  let capacity: Int64?
  let available: Int64?
}

protocol VolumeService: Sendable {
  func volumes() async -> [MountedVolume]
  func availableCapacity(at location: Location) async -> Int64?
  func eject(_ volume: MountedVolume) async throws
}

actor NativeVolumeService: VolumeService {
  func volumes() -> [MountedVolume] {
    let keys: Set<URLResourceKey> = [
      .volumeNameKey, .volumeIsEjectableKey, .volumeIsInternalKey,
      .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsBrowsableKey,
      .volumeIsLocalKey,
    ]
    var urls =
      FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
    if !urls.contains(where: { $0.path == "/" }) { urls.insert(URL(fileURLWithPath: "/"), at: 0) }
    return urls.compactMap { url in
      guard let values = try? url.resourceValues(forKeys: keys),
        url.path == "/" || values.volumeIsBrowsable != false
      else { return nil }
      return MountedVolume(
        url: url, name: values.volumeName ?? url.lastPathComponent,
        isEjectable: values.volumeIsEjectable == true, isInternal: values.volumeIsInternal == true,
        isLocal: values.volumeIsLocal != false,
        capacity: values.volumeTotalCapacity.map(Int64.init),
        available: values.volumeAvailableCapacity.map(Int64.init))
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  func availableCapacity(at location: Location) -> Int64? {
    guard location.providerID == "local" else { return nil }
    return try? URL(fileURLWithPath: location.path)
      .resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity.map(
        Int64.init)
  }

  func eject(_ volume: MountedVolume) throws {
    guard volume.isEjectable else { throw FileSystemError.unsupportedOperation }
    try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
  }
}

@MainActor @Observable final class DeviceModel {
  private(set) var volumes: [MountedVolume] = []
  var selectedVolumeID: String?
  private(set) var isEjecting = false
  var errorMessage: String?
  let service: any VolumeService
  private var refreshID = UUID()

  init(service: any VolumeService) { self.service = service }
  var selectedVolume: MountedVolume? { volumes.first { $0.id == selectedVolumeID } }
  var canEject: Bool { selectedVolume?.isEjectable == true && !isEjecting }

  func refresh() async {
    let request = UUID()
    refreshID = request
    let result = await service.volumes()
    guard request == refreshID else { return }
    volumes = result
    if selectedVolume == nil { selectedVolumeID = nil }
  }

  func ejectSelected() async {
    guard canEject, let volume = selectedVolume else { return }
    await eject(volume)
  }

  func eject(_ volume: MountedVolume) async {
    guard volume.isEjectable, !isEjecting else { return }
    isEjecting = true
    errorMessage = nil
    defer { isEjecting = false }
    do {
      try await service.eject(volume)
      await refresh()
    } catch { errorMessage = "Could not eject \(volume.name). \(error.localizedDescription)" }
  }
}

@MainActor @Observable final class PaneStatusModel {
  private(set) var availableBytes: Int64?
  private var requestID = UUID()

  func update(for location: Location?, service: any VolumeService) async {
    let request = UUID()
    requestID = request
    availableBytes = nil
    guard let location else { return }
    let available = await service.availableCapacity(at: location)
    guard requestID == request, !Task.isCancelled else { return }
    availableBytes = available
  }
}
