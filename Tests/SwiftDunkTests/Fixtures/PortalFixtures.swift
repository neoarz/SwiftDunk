import Foundation
import SwiftDunk

enum PortalFixtures {
    static let teamID = "TEAM123"
    static let deviceID = "DEVICE123"
    static let appIDID = "APP123"
    static let appIdentifier = "com.example.app"
    static let appGroupID = "GROUP123"
    static let groupIdentifier = "group.com.example.app"
    static let certificateID = "CERT123"
    static let serialNumber = "0123456789ABCDEF"
    static let certificateDistributionType = "development"
    static let certificateDistributionMethod = "limited"
    static let certificateTypeMaximumActive = 3
    static let profileID = "PROFILE123"
    static let profileUUID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    static let expirationDate = Date(timeIntervalSince1970: 1_900_000_000)

    static func teams(
        page: Int = 1,
        total: Int = 1,
        isFreeAccount: Bool = false
    ) throws -> Data {
        try qh(
            [
                "teams": .array([
                    .dictionary([
                        "teamId": .string(page == 1 ? teamID : "TEAM456"),
                        "name": .string(page == 1 ? "Fixture Team" : "Second Team"),
                        "status": .string("active"),
                        "type": .string("Company/Organization"),
                        "xcodeFreeOnly": .boolean(isFreeAccount),
                        "memberships": .array([]),
                        "currentTeamMember": .dictionary([
                            "teamMemberId": .string("MEMBER123"),
                            "email": .string("test@example.com"),
                            "roles": .array([.string("Admin")]),
                        ]),
                        "teamProvisioningSettings": .dictionary([
                            "canDeveloperRoleRegisterDevices": .boolean(true),
                            "canDeveloperRoleAddAppIds": .boolean(true),
                            "canDeveloperRoleUpdateAppIds": .boolean(true),
                        ]),
                    ])
                ])
            ],
            page: page,
            pageSize: 1,
            total: total
        )
    }

    static func duplicateTeams() throws -> Data {
        try qh(
            [
                "teams": .array([
                    team(
                        name: "Earlier Paid Team",
                        isFreeAccount: false
                    ),
                    team(
                        name: "Later Free Team",
                        isFreeAccount: true
                    ),
                ])
            ],
            page: 1,
            pageSize: 2,
            total: 2
        )
    }

    static func developer() throws -> Data {
        try qh([
            "developer": .dictionary([
                "firstName": .string("Test"),
                "lastName": .string("User"),
                "dsFirstName": .string("Test"),
                "dsLastName": .string("User"),
                "email": .string("test@example.com"),
                "developerStatus": .string("active"),
            ])
        ])
    }

    static func devices(page: Int = 1, total: Int = 1) throws -> Data {
        try qh(
            [
                "devices": .array([
                    .dictionary([
                        "deviceId": .string(page == 1 ? deviceID : "DEVICE456"),
                        "name": .string(page == 1 ? "Fixture Phone" : "Fixture Tablet"),
                        "deviceNumber": .string(page == 1 ? "UDID-1" : "UDID-2"),
                        "devicePlatform": .string("ios"),
                        "status": .string("enabled"),
                        "deviceClass": .string("iphone"),
                        "expirationDate": .date(expirationDate),
                    ])
                ])
            ],
            page: page,
            pageSize: 1,
            total: total
        )
    }

    static func noDevices() throws -> Data {
        try qh(["devices": .array([])])
    }

    static func emptyDevicePage(total: Int) throws -> Data {
        try qh(
            ["devices": .array([])],
            page: 1,
            pageSize: 1,
            total: total
        )
    }

    static func device() throws -> Data {
        try qh([
            "device": .dictionary([
                "deviceId": .string("DEVICE-NEW"),
                "name": .string("New Phone"),
                "deviceNumber": .string("UDID-NEW"),
            ])
        ])
    }

    static func appIDs(
        page: Int = 1,
        total: Int = 1,
        maximumQuantity: Int? = 10,
        availableQuantity: Int? = 7
    ) throws -> Data {
        var values: [String: PlistValue] = [
            "appIds": .array([appID(page: page)])
        ]
        if let maximumQuantity {
            values["maxQuantity"] = .integer(maximumQuantity)
        }
        if let availableQuantity {
            values["availableQuantity"] = .integer(availableQuantity)
        }
        return try qh(values, page: page, pageSize: 1, total: total)
    }

    static func noAppIDs() throws -> Data {
        try qh(["appIds": .array([])])
    }

    static func appIDResponse() throws -> Data {
        try qh(["appId": appID()])
    }

    static func appGroups() throws -> Data {
        try qh([
            "applicationGroupList": .array([appGroup()])
        ])
    }

    static func noAppGroups() throws -> Data {
        try qh(["applicationGroupList": .array([])])
    }

    static func appGroupResponse() throws -> Data {
        try qh(["applicationGroup": appGroup()])
    }

    static func certificates() throws -> Data {
        try qh([
            "certificates": .array([
                .dictionary([
                    "certificateId": .string(certificateID),
                    "name": .string("Development"),
                    "serialNumber": .string(serialNumber),
                    "status": .string("Issued"),
                    "statusCode": .integer(1),
                    "expirationDate": .date(expirationDate),
                    "certType": certificateType(maximumKey: "maxActive"),
                    "certContent": .data(Data([0x30, 0x01])),
                    "machineId": .string("MACHINE123"),
                    "machineName": .string("SwiftDunk"),
                ])
            ])
        ])
    }

    static func certificateRequest() throws -> Data {
        try qh([
            "certRequest": .dictionary([
                "certRequestId": .string("REQUEST123"),
                "certificateId": .string(certificateID),
                "serialNum": .string(serialNumber),
                "statusString": .string("Issued"),
                "dateRequested": .date(expirationDate.addingTimeInterval(-60)),
                "dateCreated": .date(expirationDate.addingTimeInterval(-30)),
                "machineId": .string("MACHINE123"),
                "machineName": .string("SwiftDunk"),
                "certificateType": certificateType(maximumKey: "maxActiveCerts"),
            ])
        ])
    }

    static func profile() throws -> Data {
        try qh([
            "provisioningProfile": .dictionary([
                "provisioningProfileId": .string(profileID),
                "UUID": .string(profileUUID),
                "filename": .string("Fixture.mobileprovision"),
                "encodedProfile": .data(Data("fixture-profile".utf8)),
                "dateExpire": .date(expirationDate),
                "appIdId": .string(appIDID),
                "isFreeProvisioningProfile": .boolean(true),
                "name": .string("Fixture Profile"),
                "status": .string("Active"),
                "type": .string("iOS Development"),
                "distributionMethod": .string("limited"),
                "proProPlatform": .string("ios"),
                "managingApp": .string("Xcode"),
                "isTemplateProfile": .boolean(false),
                "isTeamProfile": .boolean(true),
            ])
        ])
    }

    static func empty() throws -> Data {
        try qh([:])
    }

    static func qhError() throws -> Data {
        try qh(
            [
                "userString": .string("Fixture portal failure"),
                "httpCode": .integer(403),
            ],
            resultCode: 7460
        )
    }

    static let capabilitiesJSON = Data(
        """
        {"data":[{"id":"PUSH_NOTIFICATIONS","attributes":{"entitlements":[\
        {"profileKey":"aps-environment"}],"supportsWildcard":false}}]}
        """.utf8
    )

    static let bundleIDsJSON = Data(
        """
        {"data":[{"id":"APP123","attributes":{"identifier":"com.example.app",\
        "seedId":"TEAM123","name":"FixtureApp","wildcard":false}}]}
        """.utf8
    )

    static let bundleIDJSON = Data(
        """
        {"data":{"id":"APP123","attributes":{"identifier":"com.example.app",\
        "seedId":"TEAM123","name":"FixtureApp","wildcard":false}}}
        """.utf8
    )

    static let certificateJSON = Data(
        """
        {"data":{"type":"certificates","id":"V1CERT123"}}
        """.utf8
    )

    static let v1ErrorJSON = Data(
        """
        {"errors":[{"detail":"Fixture v1 failure","resultCode":7461,"status":"403"}]}
        """.utf8
    )

    static let v1NumericStatusErrorJSON = Data(
        """
        {"errors":[{"detail":"Fixture numeric-status failure","resultCode":7462,"status":429}]}
        """.utf8
    )

    static func capabilityErrorJSON(detail: String) -> Data {
        Data(
            """
            {"errors":[{"code":"FORBIDDEN","detail":"\(detail)","id":"ERROR123",\
            "resultCode":7461,"status":"403"}]}
            """.utf8
        )
    }

    private static func appID(page: Int = 1) -> PlistValue {
        .dictionary([
            "appIdId": .string(page == 1 ? appIDID : "APP456"),
            "name": .string(page == 1 ? "FixtureApp" : "SecondApp"),
            "identifier": .string(page == 1 ? appIdentifier : "com.example.second"),
            "appIdPlatform": .string("ios"),
            "prefix": .string(teamID),
            "isWildCard": .boolean(false),
            "features": .dictionary([
                "push": .boolean(true),
                "gameCenter": .boolean(false),
                "dataProtection": .string("complete"),
                "cloudKitVersion": .integer(1),
                "APG3427HIY": .boolean(true),
            ]),
            "enabledFeatures": .array([.string("PUSH_NOTIFICATIONS")]),
            "expirationDate": .date(expirationDate),
        ])
    }

    private static func team(
        name: String,
        isFreeAccount: Bool
    ) -> PlistValue {
        .dictionary([
            "teamId": .string(teamID),
            "name": .string(name),
            "status": .string("active"),
            "type": .string("Company/Organization"),
            "xcodeFreeOnly": .boolean(isFreeAccount),
            "memberships": .array([]),
            "currentTeamMember": .dictionary([
                "teamMemberId": .string("MEMBER123"),
                "email": .string("test@example.com"),
                "roles": .array([.string("Admin")]),
            ]),
            "teamProvisioningSettings": .dictionary([
                "canDeveloperRoleRegisterDevices": .boolean(true),
                "canDeveloperRoleAddAppIds": .boolean(true),
                "canDeveloperRoleUpdateAppIds": .boolean(true),
            ]),
        ])
    }

    private static func appGroup() -> PlistValue {
        .dictionary([
            "applicationGroup": .string(appGroupID),
            "name": .string("FixtureGroup"),
            "identifier": .string(groupIdentifier),
            "status": .string("active"),
            "prefix": .string(teamID),
        ])
    }

    private static func certificateType(maximumKey: String) -> PlistValue {
        .dictionary([
            "certificateTypeDisplayId": .string("DEVELOPMENT"),
            "name": .string("Apple Development"),
            "platform": .string("ios"),
            "permissionType": .string("development"),
            "distributionType": .string(certificateDistributionType),
            "distributionMethod": .string(certificateDistributionMethod),
            "ownerType": .string("team"),
            "daysOverlap": .integer(30),
            maximumKey: .integer(certificateTypeMaximumActive),
        ])
    }

    private static func qh(
        _ values: [String: PlistValue],
        resultCode: Int = 0,
        page: Int? = nil,
        pageSize: Int? = nil,
        total: Int? = nil
    ) throws -> Data {
        var root = values
        root["resultCode"] = .integer(resultCode)
        root["creationTimestamp"] = .string("2026-01-01T00:00:00Z")
        root["userLocale"] = .string("en_US")
        root["protocolVersion"] = .string("QH65B2")
        root["responseId"] = .string("RESPONSE123")
        if let page {
            root["pageNumber"] = .integer(page)
        }
        if let pageSize {
            root["pageSize"] = .integer(pageSize)
        }
        if let total {
            root["totalRecords"] = .integer(total)
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try encoder.encode(PlistValue.dictionary(root))
    }
}
