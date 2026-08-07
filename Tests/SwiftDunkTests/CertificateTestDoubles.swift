import Foundation
import SwiftDunk
import Testing

enum CertificateScenarioMode: Sendable {
    case existing
    case create
    case limit
}

actor CertificateScenario {
    private let mode: CertificateScenarioMode
    private let blocksFirstSubmission: Bool
    private var submitted = false
    private var submissionContinuation: CheckedContinuation<Void, Never>?
    private var submissionStartContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var submitAttempts = 0
    private(set) var revokedSerialNumbers: [String] = []
    private(set) var submittedCSR: String?

    init(mode: CertificateScenarioMode, blocksFirstSubmission: Bool = false) {
        self.mode = mode
        self.blocksFirstSubmission = blocksFirstSubmission
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        switch request.url.path {
        case let path where path.hasSuffix("/listTeams.action"):
            return HTTPResponse(statusCode: 200, body: try PortalFixtures.teams())
        case let path where path.hasSuffix("/ios/listAllDevelopmentCerts.action"):
            return HTTPResponse(
                statusCode: 200,
                body: try certificateList(
                    includeMatchingCertificate: mode == .existing || submitted
                )
            )
        case let path where path.hasSuffix("/ios/submitDevelopmentCSR.action"):
            submitAttempts += 1
            if blocksFirstSubmission, submitAttempts == 1 {
                let waiting = submissionStartContinuations
                submissionStartContinuations.removeAll()
                for continuation in waiting {
                    continuation.resume()
                }
                await withCheckedContinuation { continuation in
                    submissionContinuation = continuation
                }
            }
            let body = try plistBody(request)
            submittedCSR = try body.requireString("csrContent")
            let machineID = try body.requireString("machineId")
            #expect(UUID(uuidString: machineID) != nil)
            #expect(machineID == machineID.uppercased())
            #expect(try body.requireString("machineName") == "SwiftDunk")
            if mode == .limit, submitAttempts == 1 {
                return HTTPResponse(statusCode: 200, body: try limitResponse())
            }
            submitted = true
            return HTTPResponse(statusCode: 200, body: try requestResponse())
        case let path where path.hasSuffix("/ios/revokeDevelopmentCert.action"):
            let body = try plistBody(request)
            revokedSerialNumbers.append(try body.requireString("serialNumber"))
            return HTTPResponse(statusCode: 200, body: try qh([:]))
        default:
            Issue.record("Unexpected certificate endpoint: \(request.url.path)")
            return HTTPResponse(statusCode: 404)
        }
    }

    func waitUntilSubmissionStarts() async {
        if submitAttempts > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            submissionStartContinuations.append(continuation)
        }
    }

    func releaseSubmission() {
        submissionContinuation?.resume()
        submissionContinuation = nil
    }

    private func plistBody(_ request: HTTPRequest) throws -> PlistValue {
        try PropertyListDecoder().decode(
            PlistValue.self,
            from: try #require(request.body)
        )
    }

    private func certificateList(includeMatchingCertificate: Bool) throws -> Data {
        let certificate = PlistValue.dictionary([
            "certificateId": .string(PortalFixtures.certificateID),
            "name": .string("Development"),
            "serialNumber": .string(PortalFixtures.serialNumber),
            "status": .string("Issued"),
            "statusCode": .integer(1),
            "expirationDate": .date(PortalFixtures.expirationDate),
            "certContent": .data(try CertificateFixtures.certificateDER()),
            "machineId": .string("MACHINE123"),
            "machineName": .string(includeMatchingCertificate ? "SwiftDunk" : "Other"),
        ])
        return try qh(["certificates": .array([certificate])])
    }

    private func requestResponse() throws -> Data {
        try qh([
            "certRequest": .dictionary([
                "certRequestId": .string("REQUEST123"),
                "certificateId": .string(PortalFixtures.certificateID),
                "serialNum": .string(PortalFixtures.serialNumber),
                "machineId": .string("MACHINE123"),
                "machineName": .string("SwiftDunk"),
            ])
        ])
    }

    private func limitResponse() throws -> Data {
        try qh(
            [
                "userString": .string("Maximum number of certificates reached"),
                "httpCode": .integer(403),
            ],
            resultCode: 7460
        )
    }

    private func qh(
        _ values: [String: PlistValue],
        resultCode: Int = 0
    ) throws -> Data {
        var root = values
        root["resultCode"] = .integer(resultCode)
        root["creationTimestamp"] = .string("2026-01-01T00:00:00Z")
        root["userLocale"] = .string("en_US")
        root["protocolVersion"] = .string("QH65B2")
        root["responseId"] = .string("CERTIFICATE-RESPONSE")
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try encoder.encode(PlistValue.dictionary(root))
    }
}

actor RecordingPrivateKeyStore: PrivateKeyStore {
    private var keys: [Team.ID: Data] = [:]
    private(set) var saveCount = 0

    func loadPrivateKey(for teamID: Team.ID) async throws -> Data? {
        keys[teamID]
    }

    func savePrivateKey(_ privateKey: Data, for teamID: Team.ID) async throws {
        saveCount += 1
        keys[teamID] = privateKey
    }

    func removePrivateKey(for teamID: Team.ID) async throws {
        keys[teamID] = nil
    }
}
