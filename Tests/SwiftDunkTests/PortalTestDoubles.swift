import Foundation
import SwiftDunk
import Testing

enum PortalScenarioMode: Sendable {
    case normal
    case qhError
    case v1Error
    case v1NumericStatusError
    case devicePagination
    case appIDPagination
    case paginationOverflow
    case paginationWithoutProgress
    case freeAccount
    case duplicateTeams
    case capabilityDrift
    case ambiguousCapabilityError
}

actor PortalScenario {
    private let mode: PortalScenarioMode
    private(set) var requestCounts: [String: Int] = [:]

    init(mode: PortalScenarioMode = .normal) {
        self.mode = mode
    }

    func send(_ request: HTTPRequest) throws -> HTTPResponse {
        requestCounts[request.url.path, default: 0] += 1
        if request.url.host == "gsa.apple.com" {
            return try appTokenResponse(for: request)
        }

        try verifyPortalHeaders(request)
        if request.url.path.contains("/QH65B2/") {
            return try qhResponse(for: request)
        }
        return try v1Response(for: request)
    }

    func count(path: String) -> Int {
        requestCounts[path, default: 0]
    }

    private func appTokenResponse(for request: HTTPRequest) throws -> HTTPResponse {
        let root = try PropertyListDecoder().decode(
            PlistValue.self,
            from: try #require(request.body)
        )
        #expect(root["Request"]?["o"]?.string == "apptokens")
        return try plistResponse(
            .dictionary([
                "Response": .dictionary([
                    "et": .data(try TestData.hex(AppTokenVectors.encryptedToken)),
                    "Status": .dictionary(["ec": .integer(0)]),
                ])
            ])
        )
    }

    private func qhResponse(for request: HTTPRequest) throws -> HTTPResponse {
        #expect(request.method == .post)
        #expect(request.header(named: "Content-Type") == "text/x-xml-plist")
        #expect(request.header(named: "Accept") == "text/x-xml-plist")
        let body = try PropertyListDecoder().decode(
            PlistValue.self,
            from: try #require(request.body)
        )
        let requestID = try #require(body["requestId"]?.string)
        #expect(UUID(uuidString: requestID) != nil)
        #expect(requestID == requestID.uppercased())

        if mode == .qhError, request.url.path.hasSuffix("/listTeams.action") {
            return try HTTPResponse(statusCode: 200, body: PortalFixtures.qhError())
        }

        let responseBody: Data
        switch request.url.path {
        case let path where path.hasSuffix("/listTeams.action"):
            responseBody =
                try mode == .duplicateTeams
                ? PortalFixtures.duplicateTeams()
                : PortalFixtures.teams(isFreeAccount: mode == .freeAccount)
        case let path where path.hasSuffix("/viewDeveloper.action"):
            try expectTeam(body)
            responseBody = try PortalFixtures.developer()
        case let path where path.hasSuffix("/ios/listDevices.action"):
            try expectTeam(body)
            if mode == .devicePagination {
                let page = body["pageNumber"]?.integer ?? 1
                responseBody = try PortalFixtures.devices(page: page, total: 2)
            } else if mode == .paginationOverflow {
                responseBody = try PortalFixtures.devices(page: .max, total: 2)
            } else if mode == .paginationWithoutProgress {
                responseBody = try PortalFixtures.emptyDevicePage(total: 2)
            } else {
                responseBody = try PortalFixtures.devices()
            }
        case let path where path.hasSuffix("/ios/addDevice.action"):
            try expectTeam(body)
            #expect(body["name"]?.string == "New Phone")
            #expect(body["deviceNumber"]?.string == "UDID-NEW")
            responseBody = try PortalFixtures.device()
        case let path where path.hasSuffix("/ios/listAppIds.action"):
            try expectTeam(body)
            if mode == .appIDPagination {
                let page = body["pageNumber"]?.integer ?? 1
                responseBody = try PortalFixtures.appIDs(
                    page: page,
                    total: 2,
                    maximumQuantity: page == 1 ? 10 : nil,
                    availableQuantity: page == 1 ? 7 : -1
                )
            } else {
                responseBody = try PortalFixtures.appIDs()
            }
        case let path where path.hasSuffix("/ios/addAppId.action"):
            try expectTeam(body)
            #expect(body["name"]?.string == "MyApp")
            #expect(body["identifier"]?.string == PortalFixtures.appIdentifier)
            responseBody = try PortalFixtures.appIDResponse()
        case let path where path.hasSuffix("/ios/deleteAppId.action"):
            try expectTeam(body)
            #expect(body["appIdId"]?.string == PortalFixtures.appIDID)
            responseBody = try PortalFixtures.empty()
        case let path where path.hasSuffix("/ios/updateAppId.action"):
            try expectTeam(body)
            #expect(body["appIdId"]?.string == PortalFixtures.appIDID)
            #expect(body["push"]?.boolean == true)
            #expect(body["APG3427HIY"]?.boolean == true)
            #expect(
                body["futureSettings"]
                    == .dictionary([
                        "mode": .string("beta"),
                        "levels": .array([.integer(1), .integer(2)]),
                    ])
            )
            responseBody = try PortalFixtures.appIDResponse()
        case let path where path.hasSuffix("/ios/listApplicationGroups.action"):
            try expectTeam(body)
            responseBody = try PortalFixtures.appGroups()
        case let path where path.hasSuffix("/ios/addApplicationGroup.action"):
            try expectTeam(body)
            #expect(body["name"]?.string == "MyGroup")
            #expect(body["identifier"]?.string == PortalFixtures.groupIdentifier)
            responseBody = try PortalFixtures.appGroupResponse()
        case let path where path.hasSuffix("/ios/assignApplicationGroupToAppId.action"):
            try expectTeam(body)
            #expect(body["appIdId"]?.string == PortalFixtures.appIDID)
            #expect(
                body["applicationGroups"]?.array?.compactMap(\.string) == [
                    PortalFixtures.appGroupID
                ])
            responseBody = try PortalFixtures.empty()
        case let path where path.hasSuffix("/ios/listAllDevelopmentCerts.action"):
            try expectTeam(body)
            responseBody = try PortalFixtures.certificates()
        case let path where path.hasSuffix("/ios/revokeDevelopmentCert.action"):
            try expectTeam(body)
            #expect(body["serialNumber"]?.string == PortalFixtures.serialNumber)
            responseBody = try PortalFixtures.empty()
        case let path where path.hasSuffix("/ios/submitDevelopmentCSR.action"):
            try expectTeam(body)
            #expect(body["csrContent"]?.string == "fixture-csr")
            #expect(body["machineName"]?.string == "SwiftDunk")
            try expectUppercaseUUID(body["machineId"]?.string)
            responseBody = try PortalFixtures.certificateRequest()
        case let path where path.hasSuffix("/ios/downloadTeamProvisioningProfile.action"):
            try expectTeam(body)
            #expect(body["appIdId"]?.string == PortalFixtures.appIDID)
            responseBody = try PortalFixtures.profile()
        default:
            Issue.record("Unexpected QH endpoint: \(request.url.path)")
            responseBody = try PortalFixtures.empty()
        }
        return HTTPResponse(statusCode: 200, body: responseBody)
    }

    private func v1Response(for request: HTTPRequest) throws -> HTTPResponse {
        #expect(request.header(named: "Content-Type") == "application/vnd.api+json")
        #expect(request.header(named: "Accept") == "application/json, text/plain, */*")
        #expect(request.header(named: "X-Requested-With") == "XMLHttpRequest")
        let responseBody: Data

        switch request.url.path {
        case "/services/v1/capabilities":
            try expectGet(request, query: "filter[platform]=IOS")
            switch mode {
            case .v1Error:
                responseBody = PortalFixtures.v1ErrorJSON
            case .v1NumericStatusError:
                responseBody = PortalFixtures.v1NumericStatusErrorJSON
            default:
                responseBody = PortalFixtures.capabilitiesJSON
            }
        case "/services/v1/bundleIds":
            try expectGet(request, query: "limit=1000")
            responseBody = PortalFixtures.bundleIDsJSON
        case "/services/v1/bundleIds/\(PortalFixtures.appIDID)":
            #expect(request.method == .patch)
            #expect(request.header(named: "X-HTTP-Method-Override") == nil)
            let body = try JSONDecoder().decode(
                TestBundleIDUpdate.self,
                from: try #require(request.body)
            )
            #expect(body.data.id == PortalFixtures.appIDID)
            #expect(body.data.attributes.teamID == PortalFixtures.teamID)
            let capabilityIDs =
                body.data.relationships.capabilities.data.map(\.capabilityID)
            let requestCount = requestCounts[request.url.path, default: 0]
            switch mode {
            case .capabilityDrift where requestCount == 1:
                #expect(capabilityIDs == ["NEW_RESTRICTED_CAPABILITY", "PUSH_NOTIFICATIONS"])
                responseBody = PortalFixtures.capabilityErrorJSON(
                    detail: "Capability NEW_RESTRICTED_CAPABILITY is unavailable"
                )
            case .capabilityDrift:
                #expect(capabilityIDs == ["PUSH_NOTIFICATIONS"])
                responseBody = PortalFixtures.bundleIDJSON
            case .ambiguousCapabilityError:
                #expect(capabilityIDs == ["CAPABILITY_A", "CAPABILITY_B"])
                responseBody = PortalFixtures.capabilityErrorJSON(
                    detail: "CAPABILITY_A and CAPABILITY_B are unavailable"
                )
            default:
                #expect(capabilityIDs == ["PUSH_NOTIFICATIONS"])
                responseBody = PortalFixtures.bundleIDJSON
            }
        case "/services/v1/certificates":
            #expect(request.method == .post)
            #expect(request.header(named: "X-HTTP-Method-Override") == nil)
            let body = try JSONDecoder().decode(
                TestCertificateRequest.self,
                from: try #require(request.body)
            )
            #expect(body.data.attributes.teamID == PortalFixtures.teamID)
            #expect(body.data.attributes.certificateType == "DEVELOPMENT")
            #expect(body.data.attributes.csrContent == "fixture-v1-csr")
            try expectUppercaseUUID(body.data.attributes.machineID)
            responseBody = PortalFixtures.certificateJSON
        default:
            Issue.record("Unexpected v1 endpoint: \(request.url.path)")
            responseBody = Data("{}".utf8)
        }
        return HTTPResponse(statusCode: 200, body: responseBody)
    }

    private func verifyPortalHeaders(_ request: HTTPRequest) throws {
        #expect(request.url.host == "developerservices2.apple.com")
        #expect(request.header(named: "Accept-Language") == "en-us")
        #expect(request.header(named: "User-Agent") == "Xcode")
        #expect(request.header(named: "X-Apple-I-Identity-Id") == "1234567890")
        #expect(
            ["fixture-xcode-token", AppTokenVectors.tokenValue].contains(
                request.header(named: "X-Apple-GS-Token")
            )
        )
        #expect(request.header(named: "X-Apple-Identity-Token") == nil)
        #expect(
            request.header(named: "X-Mme-Client-Info")
                == "<Test> <macOS;0;0> <com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)>"
        )
        #expect(request.header(named: "X-Apple-App-Info") == "com.apple.gs.xcode.auth")
        #expect(request.header(named: "X-Xcode-Version") == "11.2 (11B41)")
    }

    private func expectTeam(_ body: PlistValue) throws {
        #expect(try body.requireString("teamId") == PortalFixtures.teamID)
    }

    private func expectGet(_ request: HTTPRequest, query: String) throws {
        #expect(request.method == .post)
        #expect(request.header(named: "X-HTTP-Method-Override") == "GET")
        let body = try JSONDecoder().decode(
            TestV1GetRequest.self,
            from: try #require(request.body)
        )
        #expect(body.teamID == PortalFixtures.teamID)
        #expect(body.query == query)
    }

    private func expectUppercaseUUID(_ value: String?) throws {
        let value = try #require(value)
        #expect(UUID(uuidString: value) != nil)
        #expect(value == value.uppercased())
    }

    private func plistResponse(_ value: PlistValue) throws -> HTTPResponse {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try HTTPResponse(statusCode: 200, body: encoder.encode(value))
    }
}

private struct TestV1GetRequest: Decodable {
    let teamID: String
    let query: String

    enum CodingKeys: String, CodingKey {
        case teamID = "teamId"
        case query = "urlEncodedQueryParams"
    }
}

private struct TestBundleIDUpdate: Decodable {
    let data: Resource

    struct Resource: Decodable {
        let id: String
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Decodable {
        let teamID: String

        enum CodingKeys: String, CodingKey {
            case teamID = "teamId"
        }
    }

    struct Relationships: Decodable {
        let capabilities: CapabilityData

        enum CodingKeys: String, CodingKey {
            case capabilities = "bundleIdCapabilities"
        }
    }

    struct CapabilityData: Decodable {
        let data: [Capability]
    }

    struct Capability: Decodable {
        let relationships: Relationship

        var capabilityID: String {
            relationships.capability.data.id
        }
    }

    struct Relationship: Decodable {
        let capability: ResourceLink
    }

    struct ResourceLink: Decodable {
        let data: Identifier
    }

    struct Identifier: Decodable {
        let id: String
    }
}

private struct TestCertificateRequest: Decodable {
    let data: Resource

    struct Resource: Decodable {
        let attributes: Attributes
    }

    struct Attributes: Decodable {
        let certificateType: String
        let teamID: String
        let csrContent: String
        let machineID: String

        enum CodingKeys: String, CodingKey {
            case certificateType = "certificatesType"
            case teamID = "teamId"
            case csrContent
            case machineID = "machineId"
        }
    }
}

private extension HTTPRequest {
    func header(named name: String) -> String? {
        headers.first {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }?.value
    }
}
