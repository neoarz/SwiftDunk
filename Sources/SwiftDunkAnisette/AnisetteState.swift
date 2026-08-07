public import Foundation

/// Durable identity and provisioning data for a remote anisette device.
///
/// `keychainIdentifier` is sensitive and must remain stable. Replacing it makes the
/// account appear to Apple as a new device and can trigger re-verification or rate limits.
public struct AnisetteState: Codable, Sendable, Equatable {
    /// The stable 16-byte device identifier.
    public let keychainIdentifier: Data

    /// The provisioned ADI blob, or `nil` before provisioning.
    public var adiPB: Data?

    /// Creates validated anisette state.
    /// - Throws: ``SwiftDunkError`` when the identifier is not exactly 16 bytes.
    public init(keychainIdentifier: Data, adiPB: Data? = nil) throws {
        guard keychainIdentifier.count == AnisetteConstants.identifierLength else {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "keychainIdentifier",
                    expected: "exactly 16 bytes"
                )
            )
        }
        self.keychainIdentifier = keychainIdentifier
        self.adiPB = adiPB
    }

    /// Decodes state while enforcing the 16-byte device-identifier invariant.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identifier = try container.decode(Data.self, forKey: .keychainIdentifier)
        let adiPB = try container.decodeIfPresent(Data.self, forKey: .adiPB)
        try self.init(keychainIdentifier: identifier, adiPB: adiPB)
    }

    private enum CodingKeys: String, CodingKey {
        case keychainIdentifier = "keychain_identifier"
        case adiPB = "adi_pb"
    }
}

/// Persistence for the stable remote-anisette device identity and ADI blob.
public protocol AnisetteStateStore: Sendable {
    /// Loads persisted state.
    /// - Throws: ``SwiftDunkError`` when stored state exists but cannot be read or decoded.
    func load() async throws -> AnisetteState?

    /// Persists state without exposing it through logs or user defaults.
    /// - Throws: ``SwiftDunkError`` when persistence fails.
    func save(_ state: AnisetteState) async throws
}
