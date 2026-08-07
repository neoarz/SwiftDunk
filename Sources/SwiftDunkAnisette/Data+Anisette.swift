package import Foundation
import Security

package extension Data {
    var anisetteHexadecimalString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

package extension AnisetteState {
    static func generated() throws -> AnisetteState {
        var identifier = Data(count: AnisetteConstants.identifierLength)
        let status = identifier.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(
                kSecRandomDefault,
                AnisetteConstants.identifierLength,
                baseAddress
            )
        }
        guard status == errSecSuccess else {
            throw SwiftDunkError(
                code: .anisetteProvisioningFailed(
                    "A stable anisette device identifier could not be generated."
                ),
                underlyingError: NSError(
                    domain: NSOSStatusErrorDomain,
                    code: Int(status)
                )
            )
        }
        return try AnisetteState(keychainIdentifier: identifier)
    }

    var localUserID: String {
        SwiftDunkCrypto.sha256(keychainIdentifier).anisetteHexadecimalString
    }

    var deviceID: String {
        var result = ""
        // apple wants these bytes in the 8-4-4-4-12 uuid shape
        for (index, byte) in keychainIdentifier.enumerated() {
            if [4, 6, 8, 10].contains(index) {
                result.append("-")
            }
            result.append(String(format: "%02x", byte))
        }
        return result
    }
}
