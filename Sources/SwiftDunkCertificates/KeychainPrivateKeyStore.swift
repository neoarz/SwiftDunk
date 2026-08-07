public import Foundation
import Security
import SwiftDunkCore
public import SwiftDunkPortal

/// A Keychain-backed private-key store suitable for iOS and macOS applications.
///
/// PKCS#8 key data is stored as a generic-password item accessible after the device is
/// first unlocked. Key contents are never included in errors.
public struct KeychainPrivateKeyStore: PrivateKeyStore {
    private let service: String

    /// Creates a Keychain private-key store.
    public init(service: String = "dev.swiftdunk.private-key") {
        self.service = service
    }

    /// Loads a team's key from the Keychain.
    /// - Throws: ``SwiftDunkError`` when the Keychain cannot be read.
    public func loadPrivateKey(for teamID: Team.ID) async throws -> Data? {
        var query = baseQuery(teamID: teamID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SwiftDunkError.securityFrameworkError(status: Int(status))
        }
        guard let data = result as? Data else {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "Keychain private-key result",
                    expected: "PKCS#8 private-key data"
                )
            )
        }
        return data
    }

    /// Replaces or creates a team's Keychain key.
    /// - Throws: ``SwiftDunkError`` when the key cannot be saved.
    public func savePrivateKey(_ privateKey: Data, for teamID: Team.ID) async throws {
        let query = baseQuery(teamID: teamID)
        let attributes: [String: Any] = [
            kSecValueData as String: privateKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SwiftDunkError.securityFrameworkError(status: Int(updateStatus))
        }

        var item = query
        for (key, value) in attributes {
            item[key] = value
        }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SwiftDunkError.securityFrameworkError(status: Int(addStatus))
        }
    }

    /// Removes a team's Keychain key.
    /// - Throws: ``SwiftDunkError`` when an existing item cannot be removed.
    public func removePrivateKey(for teamID: Team.ID) async throws {
        let status = SecItemDelete(baseQuery(teamID: teamID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SwiftDunkError.securityFrameworkError(status: Int(status))
        }
    }

    private func baseQuery(teamID: Team.ID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: teamID.rawValue,
        ]
    }
}
