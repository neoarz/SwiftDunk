package import Foundation
import BigNum
import Crypto
import SRP
import SwiftDunkAnisette

package struct AppleSRPKeys {
    fileprivate let rawValue: SRPKeyPair

    package let publicKey: Data
}

package struct AppleSRPProof {
    fileprivate let clientPublicKey: SRPKey
    fileprivate let sharedSecretKey: SRPKey

    package let sharedSecret: Data
    package let sessionKey: Data
    package let clientProof: Data
    package let expectedServerProof: Data
}

package enum AppleSRP {
    private typealias Configuration = SRPConfiguration<SHA256>

    package static func deriveKeys(privateKey: Data) -> AppleSRPKeys {
        let configuration = Configuration(.N2048)
        let privateKey = key(privateKey, configuration: configuration)
        let publicNumber = configuration.g.power(
            privateKey.number,
            modulus: configuration.N
        )
        let publicKey = key(Data(publicNumber.bytes), configuration: configuration)

        return AppleSRPKeys(
            rawValue: SRPKeyPair(public: publicKey, private: privateKey),
            publicKey: Data(publicKey.bytes)
        )
    }

    package static func derivePassword(
        _ password: String,
        protocolName: String,
        salt: Data,
        iterations: Int
    ) throws -> Data {
        let passwordHash = SwiftDunkCrypto.sha256(Data(password.utf8))
        let pbkdf2Password: Data

        switch protocolName {
        case AuthConstants.SRP.s2k:
            pbkdf2Password = passwordHash
        case AuthConstants.SRP.s2kFO:
            // s2k_fo gives pbkdf2 the lowercase hex digest, not the raw bytes
            let hexadecimal = passwordHash.map { String(format: "%02x", $0) }.joined()
            pbkdf2Password = Data(hexadecimal.utf8)
        default:
            throw SwiftDunkError(code: .unsupportedSRPProtocol(protocolName))
        }

        return try SwiftDunkCrypto.pbkdf2SHA256(
            password: pbkdf2Password,
            salt: salt,
            rounds: iterations,
            length: AuthConstants.SRP.derivedPasswordLength
        )
    }

    package static func calculateProof(
        username: String,
        salt: Data,
        derivedPassword: Data,
        serverPublicKey: Data,
        keys: AppleSRPKeys
    ) throws -> AppleSRPProof {
        let configuration = Configuration(.N2048)
        let client = SRPClient(configuration: configuration)
        let serverPublicKey = key(serverPublicKey, configuration: configuration)

        do {
            // this overload keeps the colon in H(0x3A || derivedPassword)
            let sharedSecret = try client.calculateSharedSecret(
                password: [UInt8](derivedPassword),
                salt: [UInt8](salt),
                clientKeys: keys.rawValue,
                serverPublicKey: serverPublicKey
            )
            let clientProof = client.calculateClientProof(
                username: username,
                salt: [UInt8](salt),
                clientPublicKey: keys.rawValue.public,
                serverPublicKey: serverPublicKey,
                sharedSecret: sharedSecret
            )
            let expectedServerProof = client.calculateServerProof(
                clientPublicKey: keys.rawValue.public,
                clientProof: clientProof,
                sharedSecret: sharedSecret
            )

            return AppleSRPProof(
                clientPublicKey: keys.rawValue.public,
                sharedSecretKey: sharedSecret,
                sharedSecret: Data(sharedSecret.bytes),
                sessionKey: SwiftDunkCrypto.sha256(Data(sharedSecret.bytes)),
                clientProof: Data(clientProof),
                expectedServerProof: Data(expectedServerProof)
            )
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(key: "B", expected: "a valid SRP public key"),
                underlyingError: error
            )
        }
    }

    package static func verifyServerProof(
        _ serverProof: Data,
        for proof: AppleSRPProof
    ) throws {
        let configuration = Configuration(.N2048)
        let client = SRPClient(configuration: configuration)
        do {
            try client.verifyServerProof(
                serverProof: [UInt8](serverProof),
                clientProof: [UInt8](proof.clientProof),
                clientPublicKey: proof.clientPublicKey,
                sharedSecret: proof.sharedSecretKey
            )
        } catch {
            throw SwiftDunkError(code: .srpVerificationFailed, underlyingError: error)
        }
    }

    // srp hashes fixed-width values, including a server B with a leading zero
    private static func key(
        _ bytes: Data,
        configuration: Configuration
    ) -> SRPKey {
        SRPKey(bytes, padding: configuration.sizeN)
    }
}
