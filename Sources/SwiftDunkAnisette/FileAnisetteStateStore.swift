public import Foundation
import SwiftDunkCore

/// A property-list-backed anisette state store for command-line tools and explicit files.
///
/// The file contains sensitive stable device identity and provisioning data. Choose a
/// private application-support location and include it in backups.
public actor FileAnisetteStateStore: AnisetteStateStore {
    private let fileURL: URL

    /// Creates a file-backed store.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Loads and validates the property-list state.
    /// - Throws: ``SwiftDunkError`` when an existing file cannot be read or decoded.
    public func load() async throws -> AnisetteState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            return try PropertyListDecoder().decode(AnisetteState.self, from: data)
        } catch {
            throw SwiftDunkError(
                code: .anisetteProvisioningFailed("Persisted anisette state is invalid."),
                underlyingError: error,
                url: fileURL
            )
        }
    }

    /// Atomically saves property-list state, creating its parent directory when needed.
    /// - Throws: ``SwiftDunkError`` when encoding or writing fails.
    public func save(_ state: AnisetteState) async throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try SecureAtomicFileWriter.write(encoder.encode(state), to: fileURL)
        } catch {
            throw SwiftDunkError(
                code: .anisetteProvisioningFailed("Anisette state could not be saved."),
                underlyingError: error,
                url: fileURL
            )
        }
    }
}
