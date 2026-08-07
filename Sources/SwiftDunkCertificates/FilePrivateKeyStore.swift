public import Foundation
import SwiftDunkCore
public import SwiftDunkPortal

/// A directory-backed PKCS#8 private-key store.
///
/// Each team key is written atomically to a distinct owner-readable file. Keep the
/// directory in a private application-support location and protect its backups.
public actor FilePrivateKeyStore: PrivateKeyStore {
    private let directoryURL: URL

    /// Creates a file-backed private-key store.
    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    /// Loads a team's key.
    /// - Throws: A file-system error when existing data cannot be read.
    public func loadPrivateKey(for teamID: Team.ID) async throws -> Data? {
        let url = keyURL(for: teamID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// Atomically saves a team's key with owner-only file permissions.
    /// - Throws: A file-system error when the key cannot be saved.
    public func savePrivateKey(_ privateKey: Data, for teamID: Team.ID) async throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let url = keyURL(for: teamID)
        try SecureAtomicFileWriter.write(privateKey, to: url)
    }

    /// Removes a team's key file when present.
    /// - Throws: A file-system error when an existing key cannot be removed.
    public func removePrivateKey(for teamID: Team.ID) async throws {
        let url = keyURL(for: teamID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func keyURL(for teamID: Team.ID) -> URL {
        let safeName = Data(teamID.rawValue.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return directoryURL.appendingPathComponent("\(safeName).p8", isDirectory: false)
    }
}
