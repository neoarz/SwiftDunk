import Foundation
import Security
import SwiftDunkAuth

/// A Keychain-backed session store suitable for iOS and macOS applications.
///
/// The encoded session is stored as a generic-password item accessible after the device
/// is first unlocked. It contains a bearer token and must never be logged or displayed.
public struct KeychainSessionStore: SessionStore {
    private let service: String
    private let account: String

    /// Creates a Keychain session store.
    public init(
        service: String = "dev.swiftdunk.session",
        account: String = "authenticated-session"
    ) {
        self.service = service
        self.account = account
    }

    /// Loads and validates a session from the Keychain.
    /// - Throws: ``SwiftDunkError`` for malformed persisted data or Keychain failures.
    public func load() async throws -> StoredSession? {
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
                code: .malformedResponse(
                    key: "Keychain session result",
                    expected: "stored session data"
                )
            )
        }

        do {
            return try PropertyListDecoder().decode(StoredSession.self, from: data)
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "stored session",
                    expected: "a valid Keychain session property list"
                ),
                underlyingError: error
            )
        }
    }

    /// Replaces the stored Keychain session or creates it when absent.
    /// - Throws: An encoding error or ``SwiftDunkError`` when the session cannot be saved.
    public func save(_ session: StoredSession) async throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(session)
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

    /// Removes the stored Keychain session.
    ///
    /// Calling this method when no matching item exists succeeds.
    /// - Throws: ``SwiftDunkError`` when an existing item cannot be removed.
    public func clear() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SwiftDunkError.securityFrameworkError(status: Int(status))
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
