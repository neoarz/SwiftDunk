public import Foundation
public import SwiftDunkPortal

/// Persistent storage for an RSA private key associated with a developer team.
///
/// Implementations receive PKCS#8 DER data. Private keys are sensitive credentials:
/// stores must not log their contents and should use platform data protection.
public protocol PrivateKeyStore: Sendable {
    /// Loads a team's PKCS#8-encoded private key.
    /// - Throws: An error when existing key data cannot be read.
    func loadPrivateKey(for teamID: Team.ID) async throws -> Data?

    /// Replaces a team's PKCS#8-encoded private key.
    /// - Throws: An error when the key cannot be persisted.
    func savePrivateKey(_ privateKey: Data, for teamID: Team.ID) async throws

    /// Removes a team's private key.
    ///
    /// Calling this method when no key exists succeeds.
    /// - Throws: An error when an existing key cannot be removed.
    func removePrivateKey(for teamID: Team.ID) async throws
}
