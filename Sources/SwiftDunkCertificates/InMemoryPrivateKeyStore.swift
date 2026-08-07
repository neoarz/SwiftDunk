public import Foundation
public import SwiftDunkPortal

/// An in-memory private-key store for tests and intentionally ephemeral identities.
public actor InMemoryPrivateKeyStore: PrivateKeyStore {
    private var keys: [Team.ID: Data]

    /// Creates an in-memory key store.
    public init(keys: [Team.ID: Data] = [:]) {
        self.keys = keys
    }

    /// Loads a team's key.
    /// - Throws: This implementation does not throw.
    public func loadPrivateKey(for teamID: Team.ID) async throws -> Data? {
        keys[teamID]
    }

    /// Saves a team's key.
    /// - Throws: This implementation does not throw.
    public func savePrivateKey(_ privateKey: Data, for teamID: Team.ID) async throws {
        keys[teamID] = privateKey
    }

    /// Removes a team's key.
    /// - Throws: This implementation does not throw.
    public func removePrivateKey(for teamID: Team.ID) async throws {
        keys[teamID] = nil
    }
}
