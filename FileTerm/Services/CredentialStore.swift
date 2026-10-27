import Foundation
import Security

protocol CredentialStore: AnyObject {
  func password(for id: UUID) -> String?
  func setPassword(_ password: String, for id: UUID) throws
  func deletePassword(for id: UUID)
}

enum CredentialStoreError: Error, LocalizedError {
  case keychain(OSStatus)

  var errorDescription: String? {
    switch self {
    case .keychain(let status):
      "The password could not be saved to the keychain (status \(status))."
    }
  }
}

final class KeychainCredentialStore: CredentialStore {
  private let service: String

  init(service: String = "com.fileterm.connection") { self.service = service }

  private func query(_ id: UUID) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: id.uuidString,
    ]
  }

  func password(for id: UUID) -> String? {
    var request = query(id)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func setPassword(_ password: String, for id: UUID) throws {
    let data = Data(password.utf8)
    let status = SecItemUpdate(
      query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = query(id)
      item[kSecValueData as String] = data
      let added = SecItemAdd(item as CFDictionary, nil)
      guard added == errSecSuccess else { throw CredentialStoreError.keychain(added) }
    } else if status != errSecSuccess {
      throw CredentialStoreError.keychain(status)
    }
  }

  func deletePassword(for id: UUID) { SecItemDelete(query(id) as CFDictionary) }
}
