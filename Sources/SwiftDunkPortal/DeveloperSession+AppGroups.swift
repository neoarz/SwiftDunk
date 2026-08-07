import SwiftDunkCore

public extension DeveloperSession {
    /// Lists every application group registered with a team.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, Portal, pagination, or
    ///   malformed-response failures.
    func appGroups(teamID: Team.ID) async throws -> [AppGroup] {
        record(teamID: teamID)
        return try await qh.paginated(
            path: PortalConstants.QHPath.listAppGroups,
            body: teamBody(teamID),
            as: QHAppGroupsResponse.self,
            values: \.appGroups
        )
    }

    /// Creates an application group.
    ///
    /// Apple accepts only ASCII letters in the display name. SwiftDunk removes digits,
    /// whitespace, and punctuation before sending it; the `group.` identifier is unchanged.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, Portal, or malformed-response
    ///   failures.
    func createAppGroup(
        teamID: Team.ID,
        name: String,
        identifier: String
    ) async throws -> AppGroup {
        record(teamID: teamID)
        var body = teamBody(teamID)
        body[PortalConstants.BodyKey.name] = .string(PortalNameNormalizer().normalize(name))
        body[PortalConstants.BodyKey.identifier] = .string(identifier)
        return try await qh.send(
            path: PortalConstants.QHPath.addAppGroup,
            body: body,
            as: QHAppGroupResponse.self
        ).value.appGroup
    }

    /// Returns an existing group with the identifier or creates it once.
    ///
    /// Concurrent calls for the same team and identifier share one operation. If their
    /// names differ, the first operation's name is used if creation is necessary.
    /// - Throws: ``SwiftDunkError`` for listing or creation failures.
    func ensureAppGroup(
        teamID: Team.ID,
        name: String,
        identifier: String
    ) async throws -> AppGroup {
        let operation = appGroupTask(teamID: teamID, name: name, identifier: identifier)
        defer {
            clearAppGroupTask(
                teamID: teamID,
                identifier: identifier,
                generation: operation.generation
            )
        }
        return try await operation.task.value
    }

    package func performEnsureAppGroup(
        teamID: Team.ID,
        name: String,
        identifier: String
    ) async throws -> AppGroup {
        if let existing = try await appGroups(teamID: teamID).first(where: {
            $0.groupIdentifier == identifier
        }) {
            return existing
        }
        return try await createAppGroup(
            teamID: teamID,
            name: name,
            identifier: identifier
        )
    }

    /// Assigns application groups to an App ID.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, or Portal failures.
    func assignAppGroups(
        teamID: Team.ID,
        appIDID: AppID.ID,
        groupIDs: [AppGroup.ID]
    ) async throws {
        record(teamID: teamID)
        var body = teamBody(teamID)
        body[PortalConstants.BodyKey.appIDID] = .string(appIDID.rawValue)
        body[PortalConstants.BodyKey.applicationGroups] =
            .array(groupIDs.map { .string($0.rawValue) })
        let _: QHResult<QHEmptyResponse> = try await qh.send(
            path: PortalConstants.QHPath.assignAppGroups,
            body: body
        )
    }
}
