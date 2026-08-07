public import Foundation
import SwiftDunkAuth
import SwiftDunkCore

/// A property-list session store for command-line tools and caller-selected files.
///
/// Session files contain a bearer token. Use a private application-support location and
/// protect any backups containing the file. SwiftDunk writes the file atomically with
/// owner-only permissions.
public actor FileSessionStore: SessionStore {
    private let fileURL: URL

    /// Creates a file-backed session store.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Loads and validates the stored session.
    /// - Throws: ``SwiftDunkError`` when existing data is malformed, or a file-system
    ///   error when the file cannot be read.
    public func load() async throws -> StoredSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let data = try Data(contentsOf: fileURL)
        do {
            return try PropertyListDecoder().decode(StoredSession.self, from: data)
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "stored session",
                    expected: "a valid session property list"
                ),
                underlyingError: error,
                url: fileURL
            )
        }
    }

    /// Atomically saves a session with owner-only file permissions.
    ///
    /// The parent directory is created when necessary.
    /// - Throws: An encoding or file-system error when the session cannot be saved.
    public func save(_ session: StoredSession) async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try SecureAtomicFileWriter.write(encoder.encode(session), to: fileURL)
    }

    /// Removes the session file when it exists.
    /// - Throws: A file-system error when an existing file cannot be removed.
    public func clear() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
