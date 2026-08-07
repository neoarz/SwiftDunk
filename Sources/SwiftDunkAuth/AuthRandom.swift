package import Foundation
import Security

enum AuthRandom {
    static func privateKey() throws -> Data {
        var data = Data(count: AuthConstants.SRP.privateKeyLength)
        let status = data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(
                kSecRandomDefault,
                AuthConstants.SRP.privateKeyLength,
                baseAddress
            )
        }
        guard status == errSecSuccess else {
            throw SwiftDunkError(
                code: .keyGenerationFailed,
                underlyingError: AuthRandomError(status: status)
            )
        }
        return data
    }
}

private struct AuthRandomError: Error, Sendable {
    let status: OSStatus
}
