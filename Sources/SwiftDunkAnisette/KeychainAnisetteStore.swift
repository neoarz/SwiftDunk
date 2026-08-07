import Foundation
import Security

/// A Keychain-backed anisette state store suitable for iOS and macOS apps.
///
/// The stable device identifier is stored as a generic-password item and is never
/// regenerated when a Keychain read fails.
public struct KeychainAnisetteStore: AnisetteStateStore {
    private let service: String
    private let account: String

    /// Creates a Keychain store.
    public init(
        service: String = "dev.swiftdunk.anisette",
        account: String = "remote-v3-state"
    ) {
        self.service = service
        self.account = account
    }

    /// Loads and validates state from the Keychain.
    /// - Throws: ``SwiftDunkError`` for Keychain or decoding failures.
    public func load() async throws -> AnisetteState? {
        var query = baseQuery
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
                code: .anisetteProvisioningFailed(
                    "The Keychain returned no anisette state data."
                )
            )
        }

        do {
            return try PropertyListDecoder().decode(AnisetteState.self, from: data)
        } catch {
            throw SwiftDunkError(
                code: .anisetteProvisioningFailed("Keychain anisette state is invalid."),
                underlyingError: error
            )
        }
    }

    /// Saves state to an existing Keychain item or creates it once.
    /// - Throws: ``SwiftDunkError`` for encoding or Keychain failures.
    public func save(_ state: AnisetteState) async throws {
        let data: Data
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            data = try encoder.encode(state)
        } catch {
            throw SwiftDunkError(
                code: .anisetteProvisioningFailed("Anisette state could not be encoded."),
                underlyingError: error
            )
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SwiftDunkError.securityFrameworkError(status: Int(updateStatus))
        }

        var item = baseQuery
        for (key, value) in attributes {
            item[key] = value
        }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SwiftDunkError.securityFrameworkError(status: Int(addStatus))
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
