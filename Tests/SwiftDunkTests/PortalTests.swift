import Foundation
import SwiftDunk
import SwiftDunkTestSupport
import Testing

@Suite("Developer Portal")
struct PortalTests {
    @Test("Restoration validates immediately and retains a selected team")
    func restoringValidates() async throws {
        let scenario = PortalScenario()

        let session = try await makeSession(scenario: scenario, selectedTeam: PortalFixtures.teamID)

        #expect(
            await scenario.count(path: "/services/QH65B2/listTeams.action") == 1
        )
        #expect(await session.stored.teamID == PortalFixtures.teamID)
    }

    @Test("A fresh account requests an Xcode token and validates immediately")
    func accountInitializationValidates() async throws {
        let scenario = PortalScenario()
        let account = Account(
            appleID: "test@example.com",
            firstName: "Test",
            lastName: "User",
            dsid: "1234567890",
            idmsToken: "fixture-idms-token",
            sessionKey: AppTokenVectors.sessionKey,
            context: AppTokenVectors.context,
            anisette: .mock,
            transport: transport(for: scenario)
        )

        let session = try await DeveloperSession(
            account: account,
            anisette: .mock,
            transport: transport(for: scenario)
        )

        #expect(await scenario.count(path: "/grandslam/GsService2") == 1)
        #expect(
            await scenario.count(path: "/services/QH65B2/listTeams.action") == 1
        )
        #expect(await session.stored.appleID == "test@example.com")
        #expect(await session.stored.xcodeGSToken == AppTokenVectors.tokenValue)
    }

    @Test("Restoration tolerates duplicate team IDs and caches the later value")
    func restorationToleratesDuplicateTeams() async throws {
        let scenario = PortalScenario(mode: .duplicateTeams)
        let session = try await makeSession(scenario: scenario)

        let teams = try await session.teams()

        #expect(teams.map(\.name) == ["Earlier Paid Team", "Later Free Team"])
        try await expectFreeTeamCapabilityFiltering(session)
    }

    @Test("Account initialization tolerates duplicate team IDs and caches the later value")
    func accountInitializationToleratesDuplicateTeams() async throws {
        let scenario = PortalScenario(mode: .duplicateTeams)
        let account = Account(
            appleID: "test@example.com",
            firstName: "Test",
            lastName: "User",
            dsid: "1234567890",
            idmsToken: "fixture-idms-token",
            sessionKey: AppTokenVectors.sessionKey,
            context: AppTokenVectors.context,
            anisette: .mock,
            transport: transport(for: scenario)
        )

        let session = try await DeveloperSession(
            account: account,
            anisette: .mock,
            transport: transport(for: scenario)
        )

        try await expectFreeTeamCapabilityFiltering(session)
    }

    @Test("Every QH and v1 endpoint decodes its golden response")
    func everyEndpoint() async throws {
        let scenario = PortalScenario()
        let session = try await makeSession(scenario: scenario)
        let teamID = Team.ID(rawValue: PortalFixtures.teamID)
        let appIDID = AppID.ID(rawValue: PortalFixtures.appIDID)
        let groupID = AppGroup.ID(rawValue: PortalFixtures.appGroupID)

        let teams = try await session.teams()
        #expect(teams.first?.id == teamID)
        #expect(teams.first?.provisioningSettings?.canDeveloperRegisterDevices == true)

        let developer = try await session.accountInfo(teamID: teamID)
        #expect(developer.email == "test@example.com")

        let devices = try await session.devices(teamID: teamID)
        #expect(devices.first?.udid == "UDID-1")
        let registered = try await session.registerDevice(
            teamID: teamID,
            name: "New Phone",
            udid: "UDID-NEW"
        )
        #expect(registered.id.rawValue == "DEVICE-NEW")
        let ensuredDevice = try await session.ensureDevice(
            teamID: teamID,
            name: "Unused",
            udid: "UDID-1"
        )
        #expect(ensuredDevice.id.rawValue == PortalFixtures.deviceID)

        let appIDs = try await session.appIDs(teamID: teamID)
        #expect(appIDs.first?.identifier == PortalFixtures.appIdentifier)
        #expect(appIDs.first?.features?.pushNotifications == true)
        #expect(appIDs.first?.features?.gameCenter == false)
        #expect(appIDs.first?.features?.dataProtection == "complete")
        #expect(appIDs.first?.features?.cloudKitVersion == 1)
        #expect(appIDs.first?.features?["APG3427HIY"]?.boolean == true)
        #expect(appIDs.first?.expirationDate == PortalFixtures.expirationDate)
        let inventory = try await session.appIDInventory(teamID: teamID)
        #expect(inventory.maximumQuantity == 10)
        #expect(inventory.availableQuantity == 7)
        let createdAppID = try await session.createAppID(
            teamID: teamID,
            name: "My App 42!",
            identifier: PortalFixtures.appIdentifier
        )
        #expect(createdAppID.id == appIDID)
        let ensuredAppID = try await session.ensureAppID(
            teamID: teamID,
            name: "Unused",
            identifier: PortalFixtures.appIdentifier
        )
        #expect(ensuredAppID.id == appIDID)
        _ = try await session.updateLegacyFeatures(
            teamID: teamID,
            appIDID: appIDID,
            features: [
                "push": .boolean(true),
                "APG3427HIY": .boolean(true),
                "futureSettings": .dictionary([
                    "mode": .string("beta"),
                    "levels": .array([.integer(1), .integer(2)]),
                ]),
            ]
        )
        try await session.deleteAppID(teamID: teamID, appIDID: appIDID)

        let groups = try await session.appGroups(teamID: teamID)
        #expect(groups.first?.groupIdentifier == PortalFixtures.groupIdentifier)
        let createdGroup = try await session.createAppGroup(
            teamID: teamID,
            name: "My Group 42!",
            identifier: PortalFixtures.groupIdentifier
        )
        #expect(createdGroup.id == groupID)
        let ensuredGroup = try await session.ensureAppGroup(
            teamID: teamID,
            name: "Unused",
            identifier: PortalFixtures.groupIdentifier
        )
        #expect(ensuredGroup.id == groupID)
        try await session.assignAppGroups(
            teamID: teamID,
            appIDID: appIDID,
            groupIDs: [groupID]
        )

        let certificates = try await session.certificates(teamID: teamID)
        #expect(certificates.first?.serialNumber == PortalFixtures.serialNumber)
        #expect(certificates.first?.content == Data([0x30, 0x01]))
        let certificateType = try #require(certificates.first?.type)
        #expect(certificateType.displayID == "DEVELOPMENT")
        #expect(certificateType.name == "Apple Development")
        #expect(certificateType.platform == "ios")
        #expect(certificateType.permissionType == "development")
        #expect(certificateType.distributionType == PortalFixtures.certificateDistributionType)
        #expect(certificateType.distributionMethod == PortalFixtures.certificateDistributionMethod)
        #expect(certificateType.ownerType == "team")
        #expect(certificateType.overlapDays == 30)
        #expect(certificateType.maximumActive == PortalFixtures.certificateTypeMaximumActive)
        try await session.revokeCertificate(
            teamID: teamID,
            serialNumber: PortalFixtures.serialNumber
        )
        let certificateRequest = try await session.submitCSR(
            teamID: teamID,
            csr: "fixture-csr",
            machineName: "SwiftDunk"
        )
        #expect(certificateRequest.certificateID.rawValue == PortalFixtures.certificateID)
        #expect(certificateRequest.serialNumber == PortalFixtures.serialNumber)
        let requestedType = try #require(certificateRequest.certificateType)
        #expect(requestedType.distributionType == PortalFixtures.certificateDistributionType)
        #expect(requestedType.distributionMethod == PortalFixtures.certificateDistributionMethod)
        #expect(requestedType.maximumActive == PortalFixtures.certificateTypeMaximumActive)

        let capabilities = try await session.capabilities(teamID: teamID)
        #expect(capabilities.first?.id == "PUSH_NOTIFICATIONS")
        #expect(capabilities.first?.attributes.entitlements.first?.profileKey == "aps-environment")
        try await session.updateCapabilities(
            teamID: teamID,
            appIDID: appIDID,
            capabilityIDs: ["PUSH_NOTIFICATIONS"]
        )
        let v1CertificateID = try await session.submitV1CSR(
            teamID: teamID,
            csr: "fixture-v1-csr",
            machineName: "SwiftDunk"
        )
        #expect(v1CertificateID == "V1CERT123")

        let profile = try await session.provisioningProfile(
            teamID: teamID,
            appIDID: appIDID
        )
        #expect(profile.id.rawValue == PortalFixtures.profileID)
        #expect(profile.uuid == PortalFixtures.profileUUID)
        #expect(profile.expirationDate == PortalFixtures.expirationDate)
        #expect(profile.isFreeProvisioningProfile)
        #expect(profile.type == "iOS Development")
        #expect(profile.distributionMethod == "limited")
        #expect(profile.platform == "ios")
        #expect(profile.managingApp == "Xcode")
        #expect(profile.isTemplateProfile == false)
        #expect(profile.isTeamProfile == true)
        #expect(await session.stored.teamID == PortalFixtures.teamID)
    }

    @Test("Provisioning profiles tolerate omitted optional Portal details")
    func provisioningProfileOptionalDetails() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "provisioningProfileId": PortalFixtures.profileID,
                "UUID": PortalFixtures.profileUUID,
                "filename": "Fixture.mobileprovision",
                "encodedProfile": Data("fixture-profile".utf8),
                "dateExpire": PortalFixtures.expirationDate,
            ],
            format: .xml,
            options: 0
        )

        let profile = try PropertyListDecoder().decode(ProvisioningProfile.self, from: data)

        #expect(profile.type == nil)
        #expect(profile.distributionMethod == nil)
        #expect(profile.platform == nil)
        #expect(profile.managingApp == nil)
        #expect(profile.isTemplateProfile == nil)
        #expect(profile.isTeamProfile == nil)
    }

    @Test("QH pagination follows every page to completion")
    func pagination() async throws {
        let scenario = PortalScenario(mode: .devicePagination)
        let session = try await makeSession(scenario: scenario)

        let devices = try await session.devices(
            teamID: Team.ID(rawValue: PortalFixtures.teamID)
        )

        #expect(devices.map(\.udid) == ["UDID-1", "UDID-2"])
        #expect(
            await scenario.count(path: "/services/QH65B2/ios/listDevices.action") == 2
        )
    }

    @Test("App ID inventory preserves lifecycle metadata across pagination")
    func appIDInventoryPagination() async throws {
        let scenario = PortalScenario(mode: .appIDPagination)
        let session = try await makeSession(scenario: scenario)

        let inventory = try await session.appIDInventory(
            teamID: Team.ID(rawValue: PortalFixtures.teamID)
        )

        #expect(
            inventory.appIDs.map(\.identifier) == [
                PortalFixtures.appIdentifier,
                "com.example.second",
            ])
        #expect(inventory.appIDs.allSatisfy { $0.expirationDate == PortalFixtures.expirationDate })
        #expect(inventory.maximumQuantity == 10)
        #expect(inventory.availableQuantity == -1)
        #expect(
            await scenario.count(path: "/services/QH65B2/ios/listAppIds.action") == 2
        )
    }

    @Test("App ID lifecycle fields are optional")
    func optionalAppIDLifecycleFields() async throws {
        let response = try PropertyListEncoder().encode(
            PlistValue.dictionary([
                "resultCode": .integer(0),
                "appIds": .array([
                    .dictionary([
                        "appIdId": .string("APP-NO-LIFECYCLE"),
                        "identifier": .string("com.example.no-lifecycle"),
                    ])
                ]),
            ])
        )
        let transport = MockTransport { request in
            if request.url.path.hasSuffix("/listTeams.action") {
                return HTTPResponse(statusCode: 200, body: try PortalFixtures.teams())
            }
            return HTTPResponse(statusCode: 200, body: response)
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

        let inventory = try await session.appIDInventory(
            teamID: Team.ID(rawValue: PortalFixtures.teamID)
        )

        #expect(inventory.appIDs.first?.expirationDate == nil)
        #expect(inventory.maximumQuantity == nil)
        #expect(inventory.availableQuantity == nil)
    }

    @Test("App ID features preserve unknown fields losslessly")
    func appIDFeaturePreservation() async throws {
        let features: [String: PlistValue] = [
            "push": .boolean(true),
            "dataProtection": .string("complete"),
            "cloudKitVersion": .integer(2),
            "HK421J6T7P": .boolean(true),
            "unknownMode": .string("beta"),
            "unknownLimit": .integer(42),
            "unknownList": .array([.string("a"), .integer(1)]),
            "unknownSettings": .dictionary([
                "enabled": .boolean(true),
                "thresholds": .array([.real(0.5)]),
            ]),
            "unknownBlob": .data(Data([0x01, 0x02])),
            "unknownDate": .date(PortalFixtures.expirationDate),
            "FEATURE_SWIFTDUNK_HAS_NEVER_SEEN": .boolean(false),
        ]
        let session = try await appIDListSession(features: .dictionary(features))

        let decoded = try await session.appIDs(
            teamID: Team.ID(rawValue: PortalFixtures.teamID)
        )
        let decodedFeatures = try #require(decoded.first?.features)

        #expect(decodedFeatures.pushNotifications == true)
        #expect(decodedFeatures.dataProtection == "complete")
        #expect(decodedFeatures.cloudKitVersion == 2)
        #expect(decodedFeatures.values == features)

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let reencoded = try PropertyListDecoder().decode(
            AppIDFeatures.self,
            from: encoder.encode(decodedFeatures)
        )
        #expect(reencoded.values == features)
    }

    @Test("Every typed feature accessor maps to its wire key")
    func typedFeatureAccessorCompatibility() throws {
        let features = AppIDFeatures(
            pushNotifications: true,
            iCloud: false,
            inAppPurchase: true,
            gameCenter: false,
            wallet: true,
            dataProtection: "complete",
            homeKit: true,
            cloudKitVersion: 2
        )

        #expect(features.pushNotifications == true)
        #expect(features.iCloud == false)
        #expect(features.inAppPurchase == true)
        #expect(features.gameCenter == false)
        #expect(features.wallet == true)
        #expect(features.dataProtection == "complete")
        #expect(features.homeKit == true)
        #expect(features.cloudKitVersion == 2)
        #expect(
            features.values == [
                "push": .boolean(true),
                "iCloud": .boolean(false),
                "inAppPurchase": .boolean(true),
                "gameCenter": .boolean(false),
                "passbook": .boolean(true),
                "dataProtection": .string("complete"),
                "homeKit": .boolean(true),
                "cloudKitVersion": .integer(2),
            ])

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let decoded = try PropertyListDecoder().decode(
            AppIDFeatures.self,
            from: encoder.encode(features)
        )
        #expect(decoded.values == features.values)
    }

    @Test("Empty and missing App ID feature dictionaries decode distinctly")
    func emptyAndMissingAppIDFeatures() async throws {
        let session = try await appIDListSession(
            appIDs: [
                .dictionary([
                    "appIdId": .string("APP-NO-FEATURES"),
                    "identifier": .string("com.example.none"),
                ]),
                .dictionary([
                    "appIdId": .string("APP-EMPTY-FEATURES"),
                    "identifier": .string("com.example.empty"),
                    "features": .dictionary([:]),
                ]),
            ]
        )

        let decoded = try await session.appIDs(
            teamID: Team.ID(rawValue: PortalFixtures.teamID)
        )

        #expect(decoded.count == 2)
        #expect(decoded.first?.features == nil)
        let empty = try #require(decoded.last?.features)
        #expect(empty.values.isEmpty)
    }

    @Test("A malformed App ID feature container is a typed error")
    func malformedAppIDFeatures() async throws {
        let session = try await appIDListSession(features: .string("not-a-dictionary"))

        await #expect {
            try await session.appIDs(teamID: Team.ID(rawValue: PortalFixtures.teamID))
        } throws: { error in
            guard let error = error as? SwiftDunkError,
                error.code
                    == .malformedResponse(
                        key: "response",
                        expected: "the QH response for /QH65B2/ios/listAppIds.action"
                    ),
                let decodingError = error.underlyingError as? DecodingError
            else {
                return false
            }
            return decodingErrorPath(decodingError).contains("features")
        }
    }

    @Test("QH pagination rejects a page number that cannot be incremented")
    func paginationOverflow() async throws {
        let scenario = PortalScenario(mode: .paginationOverflow)
        let session = try await makeSession(scenario: scenario)

        await #expect {
            try await session.devices(
                teamID: Team.ID(rawValue: PortalFixtures.teamID)
            )
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .malformedResponse(
                    key: "pageNumber",
                    expected: "a page number that can be incremented"
                )
        }
    }

    @Test("QH pagination rejects a page that makes no forward progress")
    func paginationWithoutProgress() async throws {
        let scenario = PortalScenario(mode: .paginationWithoutProgress)
        let session = try await makeSession(scenario: scenario)

        await #expect {
            try await session.devices(
                teamID: Team.ID(rawValue: PortalFixtures.teamID)
            )
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .malformedResponse(
                    key: "totalRecords",
                    expected: "pagination that makes forward progress"
                )
        }
    }

    @Test("A nonzero QH result code becomes a typed Developer API error")
    func qhError() async {
        let scenario = PortalScenario(mode: .qhError)

        await #expect {
            try await makeSession(scenario: scenario)
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .developerAPI(
                    resultCode: 7460,
                    httpCode: 403,
                    message: "Fixture portal failure"
                )
        }
    }

    @Test("The first sparse v1 JSON:API error is surfaced")
    func v1Error() async throws {
        let scenario = PortalScenario(mode: .v1Error)
        let session = try await makeSession(scenario: scenario)

        await #expect {
            try await session.capabilities(
                teamID: Team.ID(rawValue: PortalFixtures.teamID)
            )
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .developerAPI(
                    resultCode: 7461,
                    httpCode: 403,
                    message: "Fixture v1 failure"
                )
        }
    }

    @Test("A numeric v1 status is decoded into the Developer API HTTP code")
    func v1NumericStatusError() async throws {
        let scenario = PortalScenario(mode: .v1NumericStatusError)
        let session = try await makeSession(scenario: scenario)

        await #expect {
            try await session.capabilities(
                teamID: Team.ID(rawValue: PortalFixtures.teamID)
            )
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .developerAPI(
                    resultCode: 7462,
                    httpCode: 429,
                    message: "Fixture numeric-status failure"
                )
        }
    }

    @Test("Free teams omit capabilities Apple disallows")
    func freeAccountCapabilityGating() async throws {
        let scenario = PortalScenario(mode: .freeAccount)
        let session = try await makeSession(scenario: scenario)

        try await session.updateCapabilities(
            teamID: Team.ID(rawValue: PortalFixtures.teamID),
            appIDID: AppID.ID(rawValue: PortalFixtures.appIDID),
            capabilityIDs: ["APPLE_ID_AUTH", "PUSH_NOTIFICATIONS"]
        )
    }

    @Test("A capability named by Apple's error is omitted on retry")
    func capabilityDriftRecovery() async throws {
        let scenario = PortalScenario(mode: .capabilityDrift)
        let session = try await makeSession(scenario: scenario)

        try await session.updateCapabilities(
            teamID: Team.ID(rawValue: PortalFixtures.teamID),
            appIDID: AppID.ID(rawValue: PortalFixtures.appIDID),
            capabilityIDs: ["NEW_RESTRICTED_CAPABILITY", "PUSH_NOTIFICATIONS"]
        )

        #expect(
            await scenario.count(
                path: "/services/v1/bundleIds/\(PortalFixtures.appIDID)"
            ) == 2
        )
    }

    @Test("An ambiguous capability error is surfaced without retrying")
    func ambiguousCapabilityError() async throws {
        let scenario = PortalScenario(mode: .ambiguousCapabilityError)
        let session = try await makeSession(scenario: scenario)

        await #expect {
            try await session.updateCapabilities(
                teamID: Team.ID(rawValue: PortalFixtures.teamID),
                appIDID: AppID.ID(rawValue: PortalFixtures.appIDID),
                capabilityIDs: ["CAPABILITY_A", "CAPABILITY_B"]
            )
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .developerAPI(
                    resultCode: 7461,
                    httpCode: 403,
                    message: "CAPABILITY_A and CAPABILITY_B are unavailable"
                )
        }
        #expect(
            await scenario.count(
                path: "/services/v1/bundleIds/\(PortalFixtures.appIDID)"
            ) == 1
        )
    }

    @Test("The public test-support team response is usable offline")
    func publicFixture() async throws {
        let transport = MockTransport { request in
            #expect(request.url.path.hasSuffix("/listTeams.action"))
            return HTTPResponse(statusCode: 200, body: Fixtures.listTeamsResponse)
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

        #expect(try await session.teams().first?.id == Fixtures.team().id)
        #expect(Fixtures.account().appleID == "test@example.com")
    }

    private func makeSession(
        scenario: PortalScenario,
        selectedTeam: String? = nil
    ) async throws -> DeveloperSession {
        try await DeveloperSession(
            restoring: StoredSession(
                appleID: "test@example.com",
                adsid: "1234567890",
                xcodeGSToken: "fixture-xcode-token",
                teamID: selectedTeam
            ),
            anisette: .mock,
            transport: transport(for: scenario)
        )
    }

    private func decodingErrorPath(_ error: DecodingError) -> [String] {
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context),
            .keyNotFound(_, let context), .dataCorrupted(let context):
            return context.codingPath.map(\.stringValue)
        @unknown default:
            return []
        }
    }

    private func appIDListSession(features: PlistValue) async throws -> DeveloperSession {
        try await appIDListSession(
            appIDs: [
                .dictionary([
                    "appIdId": .string(PortalFixtures.appIDID),
                    "identifier": .string(PortalFixtures.appIdentifier),
                    "features": features,
                ])
            ]
        )
    }

    private func appIDListSession(appIDs: [PlistValue]) async throws -> DeveloperSession {
        let response = try PropertyListEncoder().encode(
            PlistValue.dictionary([
                "resultCode": .integer(0),
                "appIds": .array(appIDs),
            ])
        )
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

    private func transport(for scenario: PortalScenario) -> MockTransport {
        MockTransport { request in
            try await scenario.send(request)
        }
    }

    private func expectFreeTeamCapabilityFiltering(_ session: DeveloperSession) async throws {
        try await session.updateCapabilities(
            teamID: Team.ID(rawValue: PortalFixtures.teamID),
            appIDID: AppID.ID(rawValue: PortalFixtures.appIDID),
            capabilityIDs: ["APPLE_ID_AUTH", "PUSH_NOTIFICATIONS"]
        )
    }
}
