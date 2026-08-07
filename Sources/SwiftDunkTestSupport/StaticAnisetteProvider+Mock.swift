import Foundation
public import SwiftDunk

public extension AnisetteProvider where Self == StaticAnisetteProvider {
    /// A deterministic, non-secret anisette provider for consumer tests.
    static var mock: StaticAnisetteProvider {
        StaticAnisetteProvider(
            values: [
                "X-Apple-I-MD": "test-one-time-password",
                "X-Apple-I-MD-M": "test-machine-token",
                "X-Mme-Client-Info": "<Test> <macOS;0;0> <SwiftDunkTests>",
            ],
            generatedAt: Date()
        )
    }
}
