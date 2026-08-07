import SwiftDunkCore

public extension DeveloperSession {
    /// Lists the iOS capabilities Apple currently offers to a team.
    ///
    /// This uses Apple's v1 JSON:API transport and sends its logical GET as a POST with
    /// `X-HTTP-Method-Override: GET`.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, v1 API, or malformed-response
    ///   failures.
    func capabilities(teamID: Team.ID) async throws -> [Capability] {
        record(teamID: teamID)
        return try await v1.send(
            path: PortalConstants.V1Path.capabilities,
            method: .get,
            body: V1GetRequest(
                teamID: teamID.rawValue,
                query: PortalConstants.V1.capabilityPlatformQuery
            ),
            as: V1CapabilitiesResponse.self
        ).data
    }

    /// Replaces the enabled capabilities on an App ID.
    ///
    /// Capability IDs come from ``capabilities(teamID:)``. Apple rejects capabilities
    /// unavailable to the selected team; free accounts have additional restrictions.
    /// When Apple's structured error unambiguously names one refused capability, SwiftDunk
    /// retries the update without that capability. Ambiguous errors are not guessed at and
    /// are surfaced unchanged.
    /// - Throws: ``SwiftDunkError`` for a missing App ID, anisette, transport, v1 API, or
    ///   malformed-response failures.
    func updateCapabilities(
        teamID: Team.ID,
        appIDID: AppID.ID,
        capabilityIDs: [String]
    ) async throws {
        record(teamID: teamID)
        // apple rejects the whole update if a free team asks for one of these
        let allowedCapabilityIDs =
            isFreeAccount(teamID: teamID)
            ? capabilityIDs.filter {
                !PortalConstants.freeAccountDisallowedCapabilities.contains($0)
            }
            : capabilityIDs
        let appIDs = try await v1.send(
            path: PortalConstants.V1Path.bundleIDs,
            method: .get,
            body: V1GetRequest(
                teamID: teamID.rawValue,
                query: PortalConstants.V1.bundleIDLimitQuery
            ),
            as: V1BundleIDsResponse.self
        ).data
        guard let appID = appIDs.first(where: { $0.id == appIDID.rawValue }) else {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: appIDID.rawValue,
                    expected: "an App ID in the v1 bundleIds response"
                )
            )
        }
        var pendingCapabilityIDs = allowedCapabilityIDs
        while true {
            let request = capabilityUpdateRequest(
                appID: appID,
                teamID: teamID,
                capabilityIDs: pendingCapabilityIDs
            )
            do {
                let _: V1BundleIDResponse = try await v1.send(
                    path: PortalConstants.V1Path.bundleIDs + "/\(appID.id)",
                    method: .patch,
                    body: request
                )
                return
            } catch let error as SwiftDunkError {
                guard
                    let rejectedCapabilityID = rejectedCapabilityID(
                        from: error,
                        candidates: pendingCapabilityIDs
                    )
                else {
                    throw error
                }
                pendingCapabilityIDs.removeAll { $0 == rejectedCapabilityID }
            }
        }
    }
}

private extension DeveloperSession {
    func capabilityUpdateRequest(
        appID: V1BundleID,
        teamID: Team.ID,
        capabilityIDs: [String]
    ) -> V1BundleIDUpdateRequest {
        let capabilityResources = capabilityIDs.map { capabilityID in
            V1BundleIDUpdateRequest.CapabilityResource(
                type: PortalConstants.V1.bundleIDCapabilityType,
                attributes: .init(),
                relationships: .init(
                    capability: .init(
                        data: .init(
                            type: PortalConstants.V1.capabilityType,
                            id: capabilityID
                        )
                    )
                )
            )
        }
        return V1BundleIDUpdateRequest(
            data: .init(
                type: PortalConstants.V1.bundleIDType,
                id: appID.id,
                attributes: .init(
                    identifier: appID.attributes.identifier,
                    seedID: appID.attributes.seedID,
                    teamID: teamID.rawValue,
                    name: appID.attributes.name,
                    wildcard: appID.attributes.wildcard
                ),
                relationships: .init(
                    capabilities: .init(data: capabilityResources)
                )
            )
        )
    }

    func rejectedCapabilityID(
        from error: SwiftDunkError,
        candidates: [String]
    ) -> String? {
        guard case .developerAPI = error.code,
            let v1Error = error.underlyingError as? V1Error,
            let message = v1Error.detail ?? v1Error.title
        else {
            return nil
        }
        let tokens = Set(
            message.split { character in
                !character.isLetter && !character.isNumber && character != "_"
            }.map(String.init)
        )
        let matches = Set(candidates).intersection(tokens)
        guard matches.count == 1 else {
            return nil
        }
        return matches.first
    }
}
