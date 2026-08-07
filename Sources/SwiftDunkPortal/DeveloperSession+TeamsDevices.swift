import SwiftDunkCore

public extension DeveloperSession {
    /// Lists every Developer Program team available to the session.
    ///
    /// All QH pages are followed until Apple reports that every record was received.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, Portal, pagination, or
    ///   malformed-response failures.
    func teams() async throws -> [Team] {
        let teams = try await qh.paginated(
            path: PortalConstants.QHPath.listTeams,
            as: QHTeamsResponse.self,
            values: \.teams
        )
        cache(teams)
        return teams
    }

    /// Fetches developer account information for a team.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, Portal, or malformed-response
    ///   failures.
    func accountInfo(teamID: Team.ID) async throws -> DeveloperInfo {
        record(teamID: teamID)
        return try await qh.send(
            path: PortalConstants.QHPath.accountInfo,
            body: teamBody(teamID),
            as: QHDeveloperResponse.self
        ).value.developer
    }

    /// Lists every device registered with a team.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, Portal, pagination, or
    ///   malformed-response failures.
    func devices(teamID: Team.ID) async throws -> [Device] {
        record(teamID: teamID)
        return try await qh.paginated(
            path: PortalConstants.QHPath.listDevices,
            body: teamBody(teamID),
            as: QHDevicesResponse.self,
            values: \.devices
        )
    }

    /// Registers a device with a Developer Program team.
    ///
    /// Registration consumes one of the team's limited device slots. On free accounts,
    /// that slot generally cannot be reclaimed for a year, even if the device is no
    /// longer used. Call ``devices(teamID:)`` or ``ensureDevice(teamID:name:udid:)``
    /// first when duplicate registration is possible.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, Portal, quota, or
    ///   malformed-response failures.
    func registerDevice(teamID: Team.ID, name: String, udid: String) async throws -> Device {
        record(teamID: teamID)
        var body = teamBody(teamID)
        body[PortalConstants.BodyKey.name] = .string(name)
        body[PortalConstants.BodyKey.deviceNumber] = .string(udid)
        return try await qh.send(
            path: PortalConstants.QHPath.addDevice,
            body: body,
            as: QHDeviceResponse.self
        ).value.device
    }

    /// Returns an existing device with the UDID or registers it once.
    ///
    /// A new registration has the same slot consequences described by
    /// ``registerDevice(teamID:name:udid:)``.
    /// Concurrent calls for the same team and UDID share one operation. If their names
    /// differ, the first operation's name is used if registration is necessary.
    /// - Throws: ``SwiftDunkError`` for listing or registration failures.
    func ensureDevice(teamID: Team.ID, name: String, udid: String) async throws -> Device {
        let operation = deviceTask(teamID: teamID, name: name, udid: udid)
        defer {
            clearDeviceTask(teamID: teamID, udid: udid, generation: operation.generation)
        }
        return try await operation.task.value
    }

    package func performEnsureDevice(
        teamID: Team.ID,
        name: String,
        udid: String
    ) async throws -> Device {
        if let existing = try await devices(teamID: teamID).first(where: { $0.udid == udid }) {
            return existing
        }
        return try await registerDevice(teamID: teamID, name: name, udid: udid)
    }
}

extension DeveloperSession {
    func teamBody(_ teamID: Team.ID) -> [String: PlistValue] {
        [PortalConstants.BodyKey.teamID: .string(teamID.rawValue)]
    }
}
