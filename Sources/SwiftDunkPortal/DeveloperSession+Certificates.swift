import Foundation
import SwiftDunkCore

public extension DeveloperSession {
    /// Lists every development certificate registered with a team.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, Portal, pagination, or
    ///   malformed-response failures.
    func certificates(teamID: Team.ID) async throws -> [Certificate] {
        record(teamID: teamID)
        return try await qh.paginated(
            path: PortalConstants.QHPath.listCertificates,
            body: teamBody(teamID),
            as: QHCertificatesResponse.self,
            values: \.certificates
        )
    }

    /// Revokes a development certificate selected by serial number.
    ///
    /// Revocation is irreversible and can immediately break other people's installed
    /// applications and signing workflows. SwiftDunk never chooses or revokes a
    /// certificate implicitly; the caller must deliberately supply its serial number.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, or Portal failures.
    func revokeCertificate(teamID: Team.ID, serialNumber: String) async throws {
        record(teamID: teamID)
        var body = teamBody(teamID)
        body[PortalConstants.BodyKey.serialNumber] = .string(serialNumber)
        let _: QHResult<QHEmptyResponse> = try await qh.send(
            path: PortalConstants.QHPath.revokeCertificate,
            body: body
        )
    }

    /// Submits a PEM-encoded PKCS#10 certificate-signing request.
    ///
    /// Apple associates the request with a fresh uppercase UUID machine identifier.
    /// Creating a certificate can consume one of the team's limited certificate slots.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, Portal, certificate-limit,
    ///   or malformed-response failures.
    func submitCSR(
        teamID: Team.ID,
        csr: String,
        machineName: String
    ) async throws -> CertificateRequest {
        record(teamID: teamID)
        var body = teamBody(teamID)
        body[PortalConstants.BodyKey.csrContent] = .string(csr)
        body[PortalConstants.BodyKey.machineID] =
            .string(makeUUID().uuidString.uppercased())
        body[PortalConstants.BodyKey.machineName] = .string(machineName)
        return try await qh.send(
            path: PortalConstants.QHPath.submitCSR,
            body: body,
            as: QHCertificateRequestResponse.self
        ).value.request
    }

    /// Downloads a provisioning profile for an App ID.
    ///
    /// The returned ``ProvisioningProfile/data`` is Apple's encoded CMS profile. Profile
    /// parsing and identity coordination are provided by `SwiftDunkCertificates`.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, Portal, or malformed-response
    ///   failures.
    func provisioningProfile(
        teamID: Team.ID,
        appIDID: AppID.ID
    ) async throws -> ProvisioningProfile {
        record(teamID: teamID)
        var body = teamBody(teamID)
        body[PortalConstants.BodyKey.appIDID] = .string(appIDID.rawValue)
        return try await qh.send(
            path: PortalConstants.QHPath.provisioningProfile,
            body: body,
            as: QHProvisioningProfileResponse.self
        ).value.profile
    }
}

package extension DeveloperSession {
    func submitV1CSR(
        teamID: Team.ID,
        csr: String,
        machineName: String
    ) async throws -> String {
        record(teamID: teamID)
        let request = V1CertificateRequest(
            data: .init(
                type: PortalConstants.V1.certificateType,
                attributes: .init(
                    certificateType: PortalConstants.V1.developmentCertificateType,
                    teamID: teamID.rawValue,
                    csrContent: csr,
                    machineName: machineName,
                    machineID: makeUUID().uuidString.uppercased()
                )
            )
        )
        return try await v1.send(
            path: PortalConstants.V1Path.certificates,
            method: .post,
            body: request,
            as: V1CertificateResponse.self
        ).data.id
    }
}
