public import Foundation

/// A source of Apple device-attestation headers.
public protocol AnisetteProvider: Sendable {
    /// Returns a current anisette header bundle.
    /// - Throws: Built-in providers throw ``SwiftDunkError`` for attestation,
    ///   provisioning, or persistence failures. Custom providers may throw their own errors.
    func headers() async throws -> AnisetteHeaders
}

/// A fixed anisette provider for tests and bring-your-own attestation integrations.
public struct StaticAnisetteProvider: AnisetteProvider {
    private let storedHeaders: AnisetteHeaders

    /// Creates a provider that always returns the same bundle.
    public init(headers: AnisetteHeaders) {
        storedHeaders = headers
    }

    /// Creates a provider from fixed values and a generation time.
    public init(values: [String: String], generatedAt: Date) {
        storedHeaders = AnisetteHeaders(values: values, generatedAt: generatedAt)
    }

    /// Returns the fixed header bundle.
    public func headers() async throws -> AnisetteHeaders {
        storedHeaders
    }
}
