public import Foundation

/// A complete set of Apple device-attestation headers and the time they were generated.
public struct AnisetteHeaders: Sendable, Equatable {
    /// Header names and their values.
    public let values: [String: String]

    /// The instant at which the one-time anisette values were generated.
    public let generatedAt: Date

    /// Creates an anisette header bundle.
    public init(values: [String: String], generatedAt: Date) {
        self.values = values
        self.generatedAt = generatedAt
    }

    /// Returns a header value using case-insensitive name matching.
    ///
    /// The value itself is returned verbatim and is never lowercased.
    public func header(_ name: String) -> String? {
        values.first { candidate, _ in
            candidate.compare(name, options: .caseInsensitive) == .orderedSame
        }?.value
    }
}
