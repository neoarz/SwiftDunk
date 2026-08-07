import _CryptoExtras
import Foundation
import Security
import SwiftASN1
import SwiftDunk
@testable import SwiftDunkCertificates
import SwiftDunkTestSupport
import Testing
import X509

@Suite("Certificate identities")
struct CertificateTests {
    @Test("A stored key matches an existing certificate by typed public key")
    func existingIdentity() async throws {
        let key = try CertificateFixtures.privateKey()
        let keyStore = InMemoryPrivateKeyStore(keys: [
            Team.ID(rawValue: PortalFixtures.teamID): key.pkcs8DERRepresentation
        ])
        let scenario = CertificateScenario(mode: .existing)
        let manager = try await makeManager(
            scenario: scenario,
            keyStore: keyStore,
            key: key
        )

        let identity = try await manager.identity(
            teamID: Team.ID(rawValue: PortalFixtures.teamID)
        ) { _ in
            .cancel
        }

        #expect(!identity.isNewlyCreated)
        #expect(identity.serialNumber == PortalFixtures.serialNumber)
        #expect(identity.certificate.publicKey == X509.Certificate.PublicKey(key.publicKey))
        #expect(await scenario.submitAttempts == 0)
    }

    @Test("RSA-2048 CSR generation has the configured subject and matching key")
    func csrStructure() async throws {
        let key = try CertificateFixtures.privateKey()
        let scenario = CertificateScenario(mode: .create)
        let manager = try await makeManager(
            scenario: scenario,
            keyStore: InMemoryPrivateKeyStore(),
            key: key
        )

        let identity = try await manager.identity(
            teamID: Team.ID(rawValue: PortalFixtures.teamID)
        ) { _ in
            .cancel
        }
        let pem = try #require(await scenario.submittedCSR)
        let request = try CertificateSigningRequest(pemEncoded: pem)
        let expectedSubject = try CertificateSubject().distinguishedName()
        let expectedCertificateDER = try CertificateFixtures.certificateDER()

        #expect(key.keySizeInBits == 2048)
        #expect(request.subject == expectedSubject)
        #expect(request.publicKey == X509.Certificate.PublicKey(key.publicKey))
        #expect(request.signatureAlgorithm == .sha256WithRSAEncryption)
        #expect(request.publicKey.isValidSignature(request.signature, for: request))
        #expect(identity.isNewlyCreated)
        #expect(identity.privateKeyPEM.hasPrefix("-----BEGIN PRIVATE KEY-----"))
        #expect(identity.certificateDER == expectedCertificateDER)
    }

    @Test("Cancelling a certificate limit attaches the full list and revokes nothing")
    func certificateLimitCancel() async throws {
        let key = try CertificateFixtures.privateKey()
        let scenario = CertificateScenario(mode: .limit)
        let manager = try await makeManager(
            scenario: scenario,
            keyStore: InMemoryPrivateKeyStore(),
            key: key
        )

        await #expect {
            try await manager.identity(
                teamID: Team.ID(rawValue: PortalFixtures.teamID)
            ) { details in
                #expect(
                    details.certificates.map(\.serialNumber) == [
                        PortalFixtures.serialNumber
                    ]
                )
                return .cancel
            }
        } throws: { error in
            guard
                let error = error as? SwiftDunkError,
                error.code == .certificateLimitReached,
                let details = error.underlyingError as? CertificateLimitDetails
            else {
                return false
            }
            return details.certificates.map(\.serialNumber) == [
                PortalFixtures.serialNumber
            ]
        }
        #expect(await scenario.revokedSerialNumbers.isEmpty)
        #expect(await scenario.submitAttempts == 1)
    }

    @Test("Only caller-selected serial numbers are revoked before one retry")
    func explicitCertificateRevocation() async throws {
        let key = try CertificateFixtures.privateKey()
        let scenario = CertificateScenario(mode: .limit)
        let manager = try await makeManager(
            scenario: scenario,
            keyStore: InMemoryPrivateKeyStore(),
            key: key
        )

        let identity = try await manager.identity(
            teamID: Team.ID(rawValue: PortalFixtures.teamID)
        ) { details in
            #expect(
                details.certificates.map(\.serialNumber) == [
                    PortalFixtures.serialNumber
                ]
            )
            return .revoke(serialNumbers: [PortalFixtures.serialNumber])
        }

        #expect(identity.isNewlyCreated)
        #expect(await scenario.revokedSerialNumbers == [PortalFixtures.serialNumber])
        #expect(await scenario.submitAttempts == 2)
    }

    @Test("Concurrent identity creation for one team rejects duplicate work")
    func concurrentIdentityCreation() async throws {
        let key = try CertificateFixtures.privateKey()
        let keyStore = RecordingPrivateKeyStore()
        let scenario = CertificateScenario(mode: .create, blocksFirstSubmission: true)
        let manager = try await makeManager(
            scenario: scenario,
            keyStore: keyStore,
            generatePrivateKey: { key }
        )
        let teamID = Team.ID(rawValue: PortalFixtures.teamID)

        let first = Task {
            try await manager.identity(teamID: teamID) { _ in
                .cancel
            }
        }
        await scenario.waitUntilSubmissionStarts()

        await #expect {
            try await manager.identity(teamID: teamID) { _ in
                .cancel
            }
        } throws: { error in
            guard let error = error as? SwiftDunkError else {
                return false
            }
            return error.code == .operationInProgress("certificate identity")
        }

        await scenario.releaseSubmission()
        _ = try await first.value

        #expect(await keyStore.saveCount == 1)
        #expect(await scenario.submitAttempts == 1)
    }

    @Test("A failed identity operation releases its team guard")
    func failedIdentityReleasesGuard() async throws {
        let key = try CertificateFixtures.privateKey()
        let scenario = CertificateScenario(mode: .limit)
        let manager = try await makeManager(
            scenario: scenario,
            keyStore: InMemoryPrivateKeyStore(),
            key: key
        )
        let teamID = Team.ID(rawValue: PortalFixtures.teamID)

        await #expect {
            try await manager.identity(teamID: teamID) { _ in
                .cancel
            }
        } throws: { error in
            (error as? SwiftDunkError)?.code == .certificateLimitReached
        }

        let identity = try await manager.identity(teamID: teamID) { _ in
            .cancel
        }

        #expect(identity.isNewlyCreated)
        #expect(await scenario.submitAttempts == 2)
    }

    @Test("In-memory, file, and Keychain stores round-trip PKCS#8 key data")
    func privateKeyStores() async throws {
        let teamID = Team.ID(rawValue: PortalFixtures.teamID)
        let keyData = try CertificateFixtures.privateKey().pkcs8DERRepresentation
        let memory = InMemoryPrivateKeyStore()
        try await assertRoundTrip(store: memory, teamID: teamID, keyData: keyData)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftDunk-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = FilePrivateKeyStore(directoryURL: directory)
        try await assertRoundTrip(store: file, teamID: teamID, keyData: keyData)

        let keychain = KeychainPrivateKeyStore(
            service: "dev.swiftdunk.tests.\(UUID().uuidString)"
        )
        try await assertRoundTrip(store: keychain, teamID: teamID, keyData: keyData)
    }

    @Test("File private keys use owner-only permissions")
    func filePrivateKeyPermissions() async throws {
        let teamID = Team.ID(rawValue: PortalFixtures.teamID)
        let keyData = try CertificateFixtures.privateKey().pkcs8DERRepresentation
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftDunk-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FilePrivateKeyStore(directoryURL: directory)

        try await store.savePrivateKey(keyData, for: teamID)

        let keyURL = try #require(
            FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).first
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: keyURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("CMS provisioning-profile metadata decodes into typed fields")
    func provisioningProfileMetadata() throws {
        let creationDate = Date(timeIntervalSince1970: 1_700_000_000)
        let expirationDate = creationDate.addingTimeInterval(86_400)
        let payload = try profilePayload(
            creationDate: creationDate,
            expirationDate: expirationDate
        )
        let profile = ProvisioningProfile(
            id: .init(rawValue: "PROFILE123"),
            uuid: "PROFILE-UUID",
            filename: "Fixture.mobileprovision",
            data: cmsEnvelope(payload: payload),
            expirationDate: expirationDate
        )

        let metadata = try profile.metadata()

        #expect(metadata.name == "Fixture Profile")
        #expect(metadata.uuid == "PROFILE-UUID")
        #expect(metadata.teamIdentifiers == [PortalFixtures.teamID])
        #expect(metadata.expirationDate == expirationDate)
        #expect(metadata.entitlements.applicationIdentifier == "TEAM123.com.example.app")
        #expect(metadata.entitlements.getTaskAllow == true)
    }

    #if os(macOS)
        @Test("PKCS#12 export can be imported with its password")
        func pkcs12Export() throws {
            let key = try CertificateFixtures.privateKey()
            let identity = CertificateIdentity(
                certificate: try CertificateFixtures.certificate(),
                certificateDER: try CertificateFixtures.certificateDER(),
                privateKey: key,
                serialNumber: PortalFixtures.serialNumber,
                machineID: "MACHINE123",
                isNewlyCreated: false
            )

            let archive = try identity.exportPKCS12(password: "fixture-password")
            var imported: CFArray?
            let status = SecPKCS12Import(
                archive as CFData,
                [kSecImportExportPassphrase as String: "fixture-password"] as CFDictionary,
                &imported
            )

            #expect(status == errSecSuccess)
            #expect((imported as? [[String: Any]])?.count == 1)
        }
    #endif

    private func makeManager(
        scenario: CertificateScenario,
        keyStore: any PrivateKeyStore,
        key: _RSA.Signing.PrivateKey
    ) async throws -> CertificateManager {
        try await makeManager(
            scenario: scenario,
            keyStore: keyStore,
            generatePrivateKey: { key }
        )
    }

    private func makeManager(
        scenario: CertificateScenario,
        keyStore: any PrivateKeyStore,
        generatePrivateKey: @escaping @Sendable () throws -> _RSA.Signing.PrivateKey
    ) async throws -> CertificateManager {
        let transport = MockTransport { request in
            try await scenario.send(request)
        }
        let session = try await DeveloperSession(
            restoring: StoredSession(
                appleID: "test@example.com",
                adsid: "1234567890",
                xcodeGSToken: "fixture-xcode-token"
            ),
            anisette: .mock,
            transport: transport
        )
        return CertificateManager(
            session: session,
            keyStore: keyStore,
            subject: CertificateSubject(),
            generatePrivateKey: generatePrivateKey
        )
    }

    private func assertRoundTrip(
        store: any PrivateKeyStore,
        teamID: Team.ID,
        keyData: Data
    ) async throws {
        #expect(try await store.loadPrivateKey(for: teamID) == nil)
        try await store.savePrivateKey(keyData, for: teamID)
        #expect(try await store.loadPrivateKey(for: teamID) == keyData)
        try await store.removePrivateKey(for: teamID)
        #expect(try await store.loadPrivateKey(for: teamID) == nil)
    }

    private func profilePayload(
        creationDate: Date,
        expirationDate: Date
    ) throws -> Data {
        let value = PlistValue.dictionary([
            "Name": .string("Fixture Profile"),
            "UUID": .string("PROFILE-UUID"),
            "AppIDName": .string("Fixture App"),
            "TeamIdentifier": .array([.string(PortalFixtures.teamID)]),
            "ApplicationIdentifierPrefix": .array([.string(PortalFixtures.teamID)]),
            "CreationDate": .date(creationDate),
            "ExpirationDate": .date(expirationDate),
            "Platform": .array([.string("iOS")]),
            "ProvisionedDevices": .array([.string("UDID-1")]),
            "Entitlements": .dictionary([
                "application-identifier": .string("TEAM123.com.example.app"),
                "com.apple.developer.team-identifier": .string(PortalFixtures.teamID),
                "keychain-access-groups": .array([
                    .string("TEAM123.com.example.app")
                ]),
                "get-task-allow": .boolean(true),
            ]),
        ])
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try encoder.encode(value)
    }

    private func cmsEnvelope(payload: Data) -> Data {
        let signedDataOID = Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02])
        let dataOID = Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01])
        let octets = der(tag: 0x04, content: payload)
        let encapsulated = der(tag: 0x30, content: dataOID + der(tag: 0xA0, content: octets))
        let signedData = der(
            tag: 0x30,
            content: Data([0x02, 0x01, 0x01, 0x31, 0x00]) + encapsulated + Data([0x31, 0x00])
        )
        return der(tag: 0x30, content: signedDataOID + der(tag: 0xA0, content: signedData))
    }

    private func der(tag: UInt8, content: Data) -> Data {
        var result = Data([tag])
        if content.count < 128 {
            result.append(UInt8(content.count))
        } else {
            let bytes = withUnsafeBytes(of: UInt32(content.count).bigEndian) {
                Array($0.drop(while: { $0 == 0 }))
            }
            result.append(0x80 | UInt8(bytes.count))
            result.append(contentsOf: bytes)
        }
        result.append(content)
        return result
    }
}
