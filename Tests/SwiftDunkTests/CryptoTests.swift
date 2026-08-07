import Foundation
import SwiftDunkCore
import Testing

@Suite("Crypto primitives")
struct CryptoTests {
    @Test("PBKDF2-HMAC-SHA256 matches the RFC vector")
    func pbkdf2MatchesRFCVector() throws {
        let vector = CryptoVectors.pbkdf2RFC
        let result = try SwiftDunkCrypto.pbkdf2SHA256(
            password: vector.password,
            salt: vector.salt,
            rounds: vector.rounds,
            length: vector.length
        )
        let expected = try TestData.hex(vector.output)

        #expect(result == expected)
    }

    @Test("PBKDF2 accepts a binary password containing a NUL byte")
    func pbkdf2AcceptsBinaryPassword() throws {
        let vector = CryptoVectors.binaryPBKDF2
        let result = try SwiftDunkCrypto.pbkdf2SHA256(
            password: vector.password,
            salt: vector.salt,
            rounds: vector.rounds,
            length: vector.length
        )
        let expected = try TestData.hex(vector.output)

        #expect(result == expected)
    }

    @Test("AES-GCM opens a blob using Apple's 16-byte nonce")
    func aesGCMOpensSixteenByteNonce() throws {
        let vector = CryptoVectors.aesGCM
        let plaintext = try SwiftDunkCrypto.aesGCMDecrypt(
            ciphertext: TestData.hex(vector.ciphertext),
            tag: TestData.hex(vector.tag),
            key: vector.key,
            nonce: vector.nonce,
            aad: vector.aad
        )

        #expect(plaintext == vector.plaintext)
    }

    @Test("AES-CBC removes PKCS#7 padding")
    func aesCBCDecryptsPaddedCiphertext() throws {
        let vector = CryptoVectors.aesCBC
        let plaintext = try SwiftDunkCrypto.aesCBCDecrypt(
            TestData.hex(vector.ciphertext),
            key: vector.key,
            iv: vector.initializationVector
        )

        #expect(plaintext == vector.plaintext)
    }

    @Test("Session-key HMAC labels retain their trailing colons")
    func sessionKeyLabelsAreExact() throws {
        let vector = CryptoVectors.hmac
        let key = vector.key
        let extraDataKey = SwiftDunkCrypto.hmacSHA256(
            key: key,
            vector.extraDataKeyLabel
        )
        let extraDataIV = SwiftDunkCrypto.hmacSHA256(
            key: key,
            vector.extraDataIVLabel
        )
        let expectedKey = try TestData.hex(vector.extraDataKey)
        let expectedIV = try TestData.hex(vector.extraDataIV)
        let expectedIVPrefix = try TestData.hex(vector.extraDataIVPrefix)

        #expect(extraDataKey == expectedKey)
        #expect(extraDataIV == expectedIV)
        #expect(extraDataIV.prefix(16) == expectedIVPrefix)
    }

    @Test("SHA-256 matches its standard empty-input digest")
    func sha256MatchesKnownDigest() throws {
        let expected = try TestData.hex(CryptoVectors.emptySHA256)

        #expect(SwiftDunkCrypto.sha256(Data()) == expected)
    }
}
