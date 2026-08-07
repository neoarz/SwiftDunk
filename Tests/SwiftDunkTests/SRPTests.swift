import Foundation
import SwiftDunkAuth
import SwiftDunkCore
import Testing

@Suite("Apple SRP")
struct SRPTests {
    @Test("Derived public keys are always padded to N-2048 size")
    func derivedKeysArePadded() {
        let keys = AppleSRP.deriveKeys(privateKey: Data(repeating: 0xA5, count: 32))

        #expect(keys.publicKey.count == 256)
    }

    @Test("Apple's colon-preserving no-username-in-x variant matches every fixed vector")
    func appleVariantMatchesFixedVectors() throws {
        let vector = SRPVectors.apple
        let keys = AppleSRP.deriveKeys(privateKey: try TestData.hex(vector.privateKey))
        let proof = try AppleSRP.calculateProof(
            username: vector.username,
            salt: TestData.hex(vector.salt),
            derivedPassword: TestData.hex(vector.derivedPassword),
            serverPublicKey: TestData.hex(vector.serverPublicKey),
            keys: keys
        )
        let expectedPublicKey = try TestData.hex(vector.publicKey)
        let expectedSharedSecret = try TestData.hex(vector.sharedSecret)
        let expectedSessionKey = try TestData.hex(vector.sessionKey)
        let expectedClientProof = try TestData.hex(vector.clientProof)
        let expectedServerProof = try TestData.hex(vector.serverProof)

        #expect(keys.publicKey == expectedPublicKey)
        #expect(proof.sharedSecret == expectedSharedSecret)
        #expect(proof.sessionKey == expectedSessionKey)
        #expect(proof.clientProof == expectedClientProof)
        #expect(proof.expectedServerProof == expectedServerProof)
        try AppleSRP.verifyServerProof(expectedServerProof, for: proof)
    }

    @Test("A 255-byte server key is padded to sizeN before calculating u")
    func leadingZeroServerKeyIsPadded() throws {
        let base = SRPVectors.apple
        let vector = SRPVectors.leadingZeroServerPublicKey
        let rawServerKey = try TestData.hex(vector.unpaddedServerPublicKey)
        #expect(rawServerKey.count == 255)

        let keys = AppleSRP.deriveKeys(privateKey: try TestData.hex(base.privateKey))
        let proof = try AppleSRP.calculateProof(
            username: base.username,
            salt: TestData.hex(base.salt),
            derivedPassword: TestData.hex(base.derivedPassword),
            serverPublicKey: rawServerKey,
            keys: keys
        )
        let expectedSharedSecret = try TestData.hex(vector.sharedSecret)
        let expectedSessionKey = try TestData.hex(vector.sessionKey)
        let expectedClientProof = try TestData.hex(vector.clientProof)

        #expect(proof.sharedSecret == expectedSharedSecret)
        #expect(proof.sessionKey == expectedSessionKey)
        #expect(proof.clientProof == expectedClientProof)
    }

    @Test(arguments: [
        ("s2k", SRPVectors.passwordDerivation.s2k),
        ("s2k_fo", SRPVectors.passwordDerivation.s2kFO),
    ])
    func passwordProtocolsMatchFixedVectors(
        protocolName: String,
        expected: String
    ) throws {
        let vector = SRPVectors.passwordDerivation
        let derived = try AppleSRP.derivePassword(
            vector.password,
            protocolName: protocolName,
            salt: TestData.hex(vector.salt),
            iterations: vector.iterations
        )
        let expectedData = try TestData.hex(expected)

        #expect(derived == expectedData)
    }

    @Test("Unknown password protocols fail descriptively")
    func unknownPasswordProtocolThrows() {
        #expect {
            try AppleSRP.derivePassword(
                "password",
                protocolName: "s2k_v9",
                salt: Data([0x01]),
                iterations: 1
            )
        } throws: { error in
            guard let error = error as? SwiftDunkError else { return false }
            return error.code == .unsupportedSRPProtocol("s2k_v9")
        }
    }

    @Test("A mismatched server proof is rejected")
    func mismatchedServerProofThrows() throws {
        let vector = SRPVectors.apple
        let keys = AppleSRP.deriveKeys(privateKey: try TestData.hex(vector.privateKey))
        let proof = try AppleSRP.calculateProof(
            username: vector.username,
            salt: TestData.hex(vector.salt),
            derivedPassword: TestData.hex(vector.derivedPassword),
            serverPublicKey: TestData.hex(vector.serverPublicKey),
            keys: keys
        )

        #expect {
            try AppleSRP.verifyServerProof(Data(repeating: 0, count: 32), for: proof)
        } throws: { error in
            guard let error = error as? SwiftDunkError else { return false }
            return error.code == .srpVerificationFailed
        }
    }
}
