import Foundation

public enum TransferPolicy: String, Codable, CaseIterable, Sendable {
  case ask, replace, replaceOlder, keepBoth, skip, stop, merge

  public var decision: ConflictDecision? {
    switch self {
    case .ask: nil
    case .replace: .replace
    case .replaceOlder: .replaceOlder
    case .keepBoth: .keepBoth
    case .skip: .skip
    case .stop: .stop
    case .merge: .merge
    }
  }
}

public struct TransferPreferences: Codable, Equatable, Sendable {
  public var replacePolicy: TransferPolicy = .ask
  public var mergePolicy: TransferPolicy = .ask
  public var resumePolicy: TransferPolicy = .ask
  public var limitUpload = false
  public var limitDownload = false
  public var uploadBytesPerSecond: Int64 = 1_048_576
  public var downloadBytesPerSecond: Int64 = 1_048_576
  public var automaticallyRetry = false
  public var maximumRetries = 5
  public var maximumConcurrent = 5
  public var verification: CopyVerification = .none
  public init() {}
}
