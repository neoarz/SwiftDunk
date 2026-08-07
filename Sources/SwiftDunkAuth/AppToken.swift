public import Foundation

/// A GrandSlam application token and its server-provided lifetime.
public struct AppToken: Sendable, Equatable {
    /// The normalized application name, including the `com.apple.gs.` prefix.
    public let name: String

    /// The bearer-token value.
    public let value: String

    /// The instant after which the token should no longer be used.
    public let expiry: Date

    /// The instant at which Apple created the token.
    public let createdAt: Date

    /// Creates an application-token value.
    public init(name: String, value: String, expiry: Date, createdAt: Date) {
        self.name = name
        self.value = value
        self.expiry = expiry
        self.createdAt = createdAt
    }
}

public extension Account {
    /// Requests and decrypts a GrandSlam application token.
    ///
    /// Names without `com.apple.gs.` are normalized automatically. The response's
    /// `XYZ` envelope, 16-byte GCM nonce, authentication tag, token value, and lifetime
    /// fields are all validated before this method returns.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, GrandSlam, decryption, or
    ///   malformed-response failures.
    func appToken(_ name: String) async throws -> AppToken {
        try await AppTokenClient(
            account: self,
            now: Date.init
        ).token(named: name)
    }
}
