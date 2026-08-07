package import Foundation
import Crypto
import _CryptoExtras

package enum SwiftDunkCrypto {
    package static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    package static func hmacSHA256(key: Data, _ message: Data) -> Data {
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: message,
            using: SymmetricKey(data: key)
        )
        return Data(authenticationCode)
    }

    package static func pbkdf2SHA256(
        password: Data,
        salt: Data,
        rounds: Int,
        length: Int
    ) throws -> Data {
        guard rounds > 0, length > 0 else {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "PBKDF2 parameters",
                    expected: "positive rounds and output length"
                )
            )
        }

        do {
            let key = try KDF.Insecure.PBKDF2.deriveKey(
                from: password,
                salt: salt,
                using: .sha256,
                outputByteCount: length,
                unsafeUncheckedRounds: rounds
            )
            return key.withUnsafeBytes { Data($0) }
        } catch {
            throw SwiftDunkError(code: .keyGenerationFailed, underlyingError: error)
        }
    }

    package static func aesCBCDecrypt(
        _ ciphertext: Data,
        key: Data,
        iv: Data
    ) throws -> Data {
        do {
            let initializationVector = try AES._CBC.IV(ivBytes: iv)
            return try AES._CBC.decrypt(
                ciphertext,
                using: SymmetricKey(data: key),
                iv: initializationVector
            )
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(key: "ciphertext", expected: "valid AES-CBC data"),
                underlyingError: error
            )
        }
    }

    package static func aesGCMDecrypt(
        ciphertext: Data,
        tag: Data,
        key: Data,
        nonce: Data,
        aad: Data
    ) throws -> Data {
        do {
            let sealedBox = try AES.GCM.SealedBox(
                nonce: AES.GCM.Nonce(data: nonce),
                ciphertext: ciphertext,
                tag: tag
            )
            return try AES.GCM.open(
                sealedBox,
                using: SymmetricKey(data: key),
                authenticating: aad
            )
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(key: "ciphertext", expected: "valid AES-GCM data"),
                underlyingError: error
            )
        }
    }
}
