import SwiftDunk

struct PortalFlow {
    let session: DeveloperSession
    let sessionStore: any SessionStore

    func inspect() async throws {
        guard let team = try await selectedTeam() else { return }

        async let account = session.accountInfo(teamID: team.id)
        async let devices = session.devices(teamID: team.id)
        async let inventory = session.appIDInventory(teamID: team.id)
        async let certificates = session.certificates(teamID: team.id)

        Output.printInspection(
            account: try await account,
            team: team,
            devices: try await devices,
            inventory: try await inventory,
            certificates: try await certificates
        )
    }

    func provision() async throws {
        guard let team = try await selectedTeam() else { return }

        async let devicesRequest = session.devices(teamID: team.id)
        async let inventoryRequest = session.appIDInventory(teamID: team.id)
        let devices = try await devicesRequest
        let inventory = try await inventoryRequest

        Output.printAppIDs(inventory)
        Output.printDevices(devices)
        guard !devices.isEmpty else {
            print("\nRegister a device with Xcode before requesting a provisioning profile.")
            return
        }

        guard let name = Console.requiredPrompt("\nApp ID name: ") else { return }
        guard let bundleID = Console.requiredPrompt("Bundle identifier: ") else { return }
        let appID = try await session.ensureAppID(
            teamID: team.id,
            name: name,
            identifier: bundleID
        )
        let profile = try await session.provisioningProfile(
            teamID: team.id,
            appIDID: appID.id
        )

        Output.printProfile(profile)
        print("\nFetched \(profile.filename); session saved securely.")
    }

    private func selectedTeam() async throws -> Team? {
        let teams = try await session.teams()
        let rememberedID = await session.stored.teamID
        guard let team = Console.chooseTeam(from: teams, rememberedID: rememberedID) else {
            return nil
        }

        let current = await session.stored
        try await sessionStore.save(
            StoredSession(
                appleID: current.appleID,
                adsid: current.adsid,
                xcodeGSToken: current.xcodeGSToken,
                teamID: team.id.rawValue
            )
        )
        return team
    }
}
