import Foundation

enum CryptoVectors {
    static let pbkdf2RFC = (
        password: Data("password".utf8),
        salt: Data("salt".utf8),
        rounds: 1,
        length: 32,
        output: "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"
    )

    static let binaryPBKDF2 = (
        password: Data([0x70, 0x61, 0x00, 0x73, 0x73]),
        salt: Data("salt".utf8),
        rounds: 2,
        length: 32,
        output: "128d9af1c5fda77088c82d93e53e1147d78ff81dcdd1d4384349aa7fc63c5ad5"
    )

    static let aesGCM = (
        key: Data(UInt8(0x00)...UInt8(0x1F)),
        nonce: Data(UInt8(0xA0)...UInt8(0xAF)),
        aad: Data("XYZ".utf8),
        ciphertext: "79d44ada6c89b818a8be58f2a034fbf5e1312c0b",
        tag: "8959eb26361ce3470e0ebdd669ffb245",
        plaintext: Data("SwiftDunk GCM vector".utf8)
    )

    static let aesCBC = (
        key: Data(UInt8(0x00)...UInt8(0x1F)),
        initializationVector: Data(UInt8(0xF0)...UInt8(0xFF)),
        ciphertext: "24a0e8ccd1a76d3cf1605665dfa16c80159dfb63262793853e6a41e7a71c4640",
        plaintext: Data("SwiftDunk CBC vector".utf8)
    )

    static let hmac = (
        key: Data(UInt8(0x00)...UInt8(0x1F)),
        extraDataKeyLabel: Data("extra data key:".utf8),
        extraDataIVLabel: Data("extra data iv:".utf8),
        extraDataKey: "250df949063138bbc7e52a909dd4e2a78786af068faf5641a1e4e2e7b65d7694",
        extraDataIV: "40df232a0e13996879417b38f85526d175fdc5c4a219fb07bff7c5c835e4663a",
        extraDataIVPrefix: "40df232a0e13996879417b38f85526d1"
    )

    static let emptySHA256 =
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}
