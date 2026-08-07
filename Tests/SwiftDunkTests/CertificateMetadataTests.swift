import Foundation
import SwiftDunk
import SwiftDunkTestSupport
import Testing

@Suite("Certificate metadata")
struct CertificateMetadataTests {
    @Test("Alternate metadata keys decode and encode canonically")
    func alternateKeys() throws {
        let certificate = try decodeCertificate(
            metadataFields: [
                "certificateType": metadata(
                    distributionType: "alternate",
                    maximumValues: ["maxActiveCerts": .integer(4)]
                )
            ]
        )

        let type = try #require(certificate.type)
        #expect(type.distributionType == "alternate")
        #expect(type.distributionMethod == PortalFixtures.certificateDistributionMethod)
        #expect(type.maximumActive == 4)

        let encoded = try encodedDictionary(certificate)
        #expect(encoded["certificateType"] == nil)
        let encodedType = try #require(encoded["certType"]?.dictionary)
        #expect(encodedType["maxActiveCerts"] == nil)
        #expect(encodedType["maxActive"]?.integer == 4)
    }

    @Test("Preferred metadata keys take precedence in a synthetic payload")
    func preferredKeyPrecedence() throws {
        let certificate = try decodeCertificate(
            metadataFields: [
                "certType": metadata(
                    distributionType: "preferred",
                    maximumValues: [
                        "maxActive": .integer(3),
                        "maxActiveCerts": .integer(8),
                    ]
                ),
                "certificateType": metadata(
                    distributionType: "alternate",
                    maximumValues: ["maxActiveCerts": .integer(9)]
                ),
            ]
        )

        #expect(certificate.type?.distributionType == "preferred")
        #expect(certificate.type?.maximumActive == 3)
    }

    @Test("Certificate metadata remains optional")
    func missingMetadata() throws {
        let certificate = try decodeCertificate(metadataFields: [:])

        #expect(certificate.type == nil)
    }

    @Test("Malformed preferred metadata keys do not use fallbacks")
    func malformedPreferredKeys() async throws {
        try await expectMalformed(
            metadataFields: [
                "certType": .string("not-a-dictionary"),
                "certificateType": metadata(
                    maximumValues: ["maxActiveCerts": .integer(9)]
                ),
            ],
            codingKey: "certType"
        )
        try await expectMalformed(
            metadataFields: [
                "certType": metadata(
                    maximumValues: [
                        "maxActive": .string("not-an-integer"),
                        "maxActiveCerts": .integer(9),
                    ]
                )
            ],
            codingKey: "maxActive"
        )
    }

    private func expectMalformed(
        metadataFields: [String: PlistValue],
        codingKey: String
    ) async throws {
        let session = try await session(metadataFields: metadataFields)

        await #expect {
            try await session.certificates(
                teamID: Team.ID(rawValue: PortalFixtures.teamID)
            )
        } throws: { error in
            guard let error = error as? SwiftDunkError,
                error.code
                    == .malformedResponse(
                        key: "response",
                        expected:
                            "the QH response for /QH65B2/ios/listAllDevelopmentCerts.action"
                    ),
                let decodingError = error.underlyingError as? DecodingError
            else {
                return false
            }
            return decodingPath(decodingError).contains(codingKey)
        }
    }

    private func session(
        metadataFields: [String: PlistValue]
    ) async throws -> DeveloperSession {
        let response = try qhResponse(metadataFields: metadataFields)
        let transport = MockTransport { request in
            if request.url.path.hasSuffix("/listTeams.action") {
                return HTTPResponse(statusCode: 200, body: try PortalFixtures.teams())
            }
            return HTTPResponse(statusCode: 200, body: response)
        }
        return try await DeveloperSession(
            restoring: StoredSession(
                appleID: "test@example.com",
                adsid: "1234567890",
                xcodeGSToken: "fixture-xcode-token"
            ),
            anisette: .mock,
            transport: transport
        )
    }

    private func qhResponse(
        metadataFields: [String: PlistValue]
    ) throws -> Data {
        try PropertyListEncoder().encode(
            PlistValue.dictionary([
                "resultCode": .integer(0),
                "certificates": .array([
                    certificateValue(metadataFields: metadataFields)
                ]),
            ])
        )
    }

    private func decodeCertificate(
        metadataFields: [String: PlistValue]
    ) throws -> Certificate {
        let data = try PropertyListEncoder().encode(
            certificateValue(metadataFields: metadataFields)
        )
        return try PropertyListDecoder().decode(Certificate.self, from: data)
    }

    private func certificateValue(
        metadataFields: [String: PlistValue]
    ) -> PlistValue {
        var values: [String: PlistValue] = [
            "certificateId": .string(PortalFixtures.certificateID),
            "serialNumber": .string(PortalFixtures.serialNumber),
            "expirationDate": .date(PortalFixtures.expirationDate),
        ]
        values.merge(metadataFields) { _, new in new }
        return .dictionary(values)
    }

    private func metadata(
        distributionType: String = PortalFixtures.certificateDistributionType,
        maximumValues: [String: PlistValue]
    ) -> PlistValue {
        var values: [String: PlistValue] = [
            "distributionType": .string(distributionType),
            "distributionMethod": .string(PortalFixtures.certificateDistributionMethod),
        ]
        values.merge(maximumValues) { _, new in new }
        return .dictionary(values)
    }

    private func encodedDictionary(_ certificate: Certificate) throws -> [String: PlistValue] {
        let encoded = try PropertyListEncoder().encode(certificate)
        return try #require(
            PropertyListDecoder().decode(PlistValue.self, from: encoded).dictionary
        )
    }

    private func decodingPath(_ error: DecodingError) -> [String] {
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context),
            .keyNotFound(_, let context), .dataCorrupted(let context):
            return context.codingPath.map(\.stringValue)
        @unknown default:
            return []
        }
    }
}
