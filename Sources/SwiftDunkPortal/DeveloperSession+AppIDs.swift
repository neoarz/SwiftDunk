package import SwiftDunkCore

public extension DeveloperSession {
    /// Lists every App ID registered with a team.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, Portal, pagination, or
    ///   malformed-response failures.
    func appIDs(teamID: Team.ID) async throws -> [AppID] {
        try await appIDInventory(teamID: teamID).appIDs
    }

    /// Lists every App ID and the registration quota Apple reports for a team.
    ///
    /// Quota fields are `nil` when Apple omits them. When pagination repeats a quota
    /// value, the latest non-`nil` value is returned.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, Portal, pagination, or
    ///   malformed-response failures.
    func appIDInventory(teamID: Team.ID) async throws -> AppIDInventory {
        record(teamID: teamID)
        let result = try await qh.paginatedWithSummary(
            path: PortalConstants.QHPath.listAppIDs,
            body: teamBody(teamID),
            as: QHAppIDsResponse.self,
            initialSummary: AppIDQuota(),
            values: \.appIDs,
            updateSummary: { quota, response in
                AppIDQuota(
                    maximumQuantity: response.maximumQuantity ?? quota.maximumQuantity,
                    availableQuantity: response.availableQuantity ?? quota.availableQuantity
                )
            }
        )
        return AppIDInventory(
            appIDs: result.values,
            maximumQuantity: result.summary.maximumQuantity,
            availableQuantity: result.summary.availableQuantity
        )
    }

    /// Creates an App ID.
    ///
    /// Apple accepts only ASCII letters in the display name. SwiftDunk removes digits,
    /// whitespace, and punctuation before sending it; the bundle identifier is unchanged.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, Portal, or malformed-response
    ///   failures.
    func createAppID(teamID: Team.ID, name: String, identifier: String) async throws -> AppID {
        record(teamID: teamID)
        var body = teamBody(teamID)
        body[PortalConstants.BodyKey.name] = .string(PortalNameNormalizer().normalize(name))
        body[PortalConstants.BodyKey.identifier] = .string(identifier)
        return try await qh.send(
            path: PortalConstants.QHPath.addAppID,
            body: body,
            as: QHAppIDResponse.self
        ).value.appID
    }

    /// Deletes an App ID from a team.
    ///
    /// Deletion can invalidate workflows and provisioning profiles that refer to the App
    /// ID. SwiftDunk never calls this method implicitly.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, or Portal failures.
    func deleteAppID(teamID: Team.ID, appIDID: AppID.ID) async throws {
        record(teamID: teamID)
        var body = teamBody(teamID)
        body[PortalConstants.BodyKey.appIDID] = .string(appIDID.rawValue)
        let _: QHResult<QHEmptyResponse> = try await qh.send(
            path: PortalConstants.QHPath.deleteAppID,
            body: body
        )
    }

    /// Returns an existing App ID with the bundle identifier or creates it once.
    ///
    /// Concurrent calls for the same team and identifier share one operation. If their
    /// names differ, the first operation's name is used if creation is necessary.
    /// - Throws: ``SwiftDunkError`` for listing or creation failures.
    func ensureAppID(teamID: Team.ID, name: String, identifier: String) async throws -> AppID {
        let operation = appIDTask(teamID: teamID, name: name, identifier: identifier)
        defer {
            clearAppIDTask(
                teamID: teamID,
                identifier: identifier,
                generation: operation.generation
            )
        }
        return try await operation.task.value
    }

    package func performEnsureAppID(
        teamID: Team.ID,
        name: String,
        identifier: String
    ) async throws -> AppID {
        if let existing = try await appIDs(teamID: teamID).first(where: {
            $0.identifier == identifier
        }) {
            return existing
        }
        return try await createAppID(
            teamID: teamID,
            name: name,
            identifier: identifier
        )
    }
}

private struct AppIDQuota: Sendable {
    let maximumQuantity: Int?
    let availableQuantity: Int?

    init(maximumQuantity: Int? = nil, availableQuantity: Int? = nil) {
        self.maximumQuantity = maximumQuantity
        self.availableQuantity = availableQuantity
    }
}

package extension DeveloperSession {
    func updateLegacyFeatures(
        teamID: Team.ID,
        appIDID: AppID.ID,
        features: [String: PlistValue]
    ) async throws -> AppID {
        record(teamID: teamID)
        var body = teamBody(teamID)
        body[PortalConstants.BodyKey.appIDID] = .string(appIDID.rawValue)
        for (key, value) in features {
            body[key] = value
        }
        return try await qh.send(
            path: PortalConstants.QHPath.updateAppID,
            body: body,
            as: QHAppIDResponse.self
        ).value.appID
    }
}
