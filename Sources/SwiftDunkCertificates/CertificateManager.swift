import _CryptoExtras
import Foundation
import SwiftDunkCore
public import SwiftDunkPortal
import SwiftASN1
import X509

/// Coordinates RSA keys and Apple development certificates.
///
/// The manager never revokes a certificate implicitly. When Apple reports a certificate
/// limit, the caller must explicitly name serial numbers through ``CertificateLimitAction``.
public actor CertificateManager {
    private let session: DeveloperSession
    private let keyStore: any PrivateKeyStore
    private let subject: CertificateSubject
    private let generatePrivateKey: @Sendable () throws -> _RSA.Signing.PrivateKey
    private var activeTeamIDs: Set<Team.ID> = []

    /// Creates a certificate manager.
    public init(
        session: DeveloperSession,
        keyStore: any PrivateKeyStore,
        subject: CertificateSubject = CertificateSubject()
    ) {
        self.session = session
        self.keyStore = keyStore
        self.subject = subject
        generatePrivateKey = {
            try _RSA.Signing.PrivateKey(keySize: .bits2048)
        }
    }

    init(
        session: DeveloperSession,
        keyStore: any PrivateKeyStore,
        subject: CertificateSubject,
        generatePrivateKey: @escaping @Sendable () throws -> _RSA.Signing.PrivateKey
    ) {
        self.session = session
        self.keyStore = keyStore
        self.subject = subject
        self.generatePrivateKey = generatePrivateKey
    }

    /// Finds or creates a development certificate identity for a team.
    ///
    /// Existing certificates are matched by machine name and typed RSA public key. If
    /// Apple reports that the account has no certificate slots, the callback decides
    /// whether to cancel or explicitly revoke named serial numbers. Revoking a
    /// certificate can break installed applications and is never done automatically.
    /// The callback receives the certificates eligible for revocation and runs at most
    /// once, after Apple reports result code 7460.
    /// - Throws: ``SwiftDunkError`` for invalid stored keys, CSR failures, certificate
    ///   limits, missing certificates, Portal failures, malformed certificate data, or
    ///   when another identity operation is already running for the same team.
    public func identity(
        teamID: Team.ID,
        machineName: String = "SwiftDunk",
        onCertificateLimitReached:
            @Sendable (CertificateLimitDetails) async -> CertificateLimitAction
    ) async throws -> CertificateIdentity {
        guard activeTeamIDs.insert(teamID).inserted else {
            throw SwiftDunkError(code: .operationInProgress("certificate identity"))
        }
        defer {
            activeTeamIDs.remove(teamID)
        }

        let certificates = try await session.certificates(teamID: teamID)
        let privateKey = try await loadOrCreatePrivateKey(teamID: teamID)

        if let identity = try matchingIdentity(
            certificates: certificates,
            privateKey: privateKey,
            machineName: machineName
        ) {
            return identity
        }

        let csr = try makeCSR(privateKey: privateKey)
        let request: CertificateRequest
        do {
            request = try await session.submitCSR(
                teamID: teamID,
                csr: csr,
                machineName: machineName
            )
        } catch {
            guard isCertificateLimit(error) else { throw error }
            request = try await resolveCertificateLimit(
                certificates: certificates,
                teamID: teamID,
                csr: csr,
                machineName: machineName,
                action: await onCertificateLimitReached(
                    CertificateLimitDetails(certificates: certificates)
                )
            )
        }

        let refreshed = try await session.certificates(teamID: teamID)
        guard let issued = refreshed.first(where: { $0.id == request.certificateID }) else {
            throw SwiftDunkError(code: .certificateNotFound)
        }
        return try identity(from: issued, privateKey: privateKey, isNewlyCreated: true)
    }

    private func loadOrCreatePrivateKey(
        teamID: Team.ID
    ) async throws -> _RSA.Signing.PrivateKey {
        if let stored = try await keyStore.loadPrivateKey(for: teamID) {
            do {
                return try _RSA.Signing.PrivateKey(derRepresentation: stored)
            } catch {
                throw SwiftDunkError(code: .keyGenerationFailed, underlyingError: error)
            }
        }

        do {
            let privateKey = try generatePrivateKey()
            try await keyStore.savePrivateKey(
                privateKey.pkcs8DERRepresentation,
                for: teamID
            )
            return privateKey
        } catch let error as SwiftDunkError {
            throw error
        } catch {
            throw SwiftDunkError(code: .keyGenerationFailed, underlyingError: error)
        }
    }

    private func matchingIdentity(
        certificates: [SwiftDunkPortal.Certificate],
        privateKey: _RSA.Signing.PrivateKey,
        machineName: String
    ) throws -> CertificateIdentity? {
        // machineName is only a label, the public key decides the match
        let publicKey = X509.Certificate.PublicKey(privateKey.publicKey)
        for certificate in certificates where certificate.machineName == machineName {
            guard let content = certificate.content else { continue }
            let parsed: X509.Certificate
            do {
                parsed = try X509.Certificate(derEncoded: Array(content))
            } catch {
                throw malformedCertificate(error)
            }
            if parsed.publicKey == publicKey {
                return CertificateIdentity(
                    certificate: parsed,
                    certificateDER: content,
                    privateKey: privateKey,
                    serialNumber: certificate.serialNumber,
                    machineID: certificate.machineID,
                    isNewlyCreated: false
                )
            }
        }
        return nil
    }

    private func makeCSR(privateKey: _RSA.Signing.PrivateKey) throws -> String {
        do {
            let request = try CertificateSigningRequest(
                version: .v1,
                subject: subject.distinguishedName(),
                privateKey: X509.Certificate.PrivateKey(privateKey),
                attributes: .init(),
                signatureAlgorithm: .sha256WithRSAEncryption
            )
            return try request.serializeAsPEM().pemString
        } catch {
            throw SwiftDunkError(code: .keyGenerationFailed, underlyingError: error)
        }
    }

    private func resolveCertificateLimit(
        certificates: [SwiftDunkPortal.Certificate],
        teamID: Team.ID,
        csr: String,
        machineName: String,
        action: CertificateLimitAction
    ) async throws -> CertificateRequest {
        switch action {
        case .cancel:
            throw limitError(certificates: certificates)
        case .revoke(let serialNumbers):
            let available = Set(certificates.map(\.serialNumber))
            var seen: Set<String> = []
            let requested = serialNumbers.filter { seen.insert($0).inserted }
            guard
                !requested.isEmpty,
                Set(requested).isSubset(of: available)
            else {
                throw SwiftDunkError(code: .certificateNotFound)
            }
            for serialNumber in requested {
                try await session.revokeCertificate(
                    teamID: teamID,
                    serialNumber: serialNumber
                )
            }
            do {
                return try await session.submitCSR(
                    teamID: teamID,
                    csr: csr,
                    machineName: machineName
                )
            } catch {
                if isCertificateLimit(error) {
                    throw limitError(certificates: certificates)
                }
                throw error
            }
        }
    }

    private func identity(
        from certificate: SwiftDunkPortal.Certificate,
        privateKey: _RSA.Signing.PrivateKey,
        isNewlyCreated: Bool
    ) throws -> CertificateIdentity {
        guard let content = certificate.content else {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "certContent",
                    expected: "DER-encoded certificate data"
                )
            )
        }
        do {
            let parsed = try X509.Certificate(derEncoded: Array(content))
            guard parsed.publicKey == X509.Certificate.PublicKey(privateKey.publicKey) else {
                throw SwiftDunkError(code: .certificateNotFound)
            }
            return CertificateIdentity(
                certificate: parsed,
                certificateDER: content,
                privateKey: privateKey,
                serialNumber: certificate.serialNumber,
                machineID: certificate.machineID,
                isNewlyCreated: isNewlyCreated
            )
        } catch let error as SwiftDunkError {
            throw error
        } catch {
            throw malformedCertificate(error)
        }
    }

    private func isCertificateLimit(_ error: any Error) -> Bool {
        guard let error = error as? SwiftDunkError else { return false }
        guard case .developerAPI(let resultCode, _, _) = error.code else { return false }
        // apple uses 7460 for the certificate limit
        return resultCode == 7460
    }

    private func limitError(
        certificates: [SwiftDunkPortal.Certificate]
    ) -> SwiftDunkError {
        SwiftDunkError(
            code: .certificateLimitReached,
            underlyingError: CertificateLimitDetails(certificates: certificates)
        )
    }

    private func malformedCertificate(_ error: any Error) -> SwiftDunkError {
        SwiftDunkError(
            code: .malformedResponse(
                key: "certContent",
                expected: "a valid DER-encoded X.509 certificate"
            ),
            underlyingError: error
        )
    }
}
