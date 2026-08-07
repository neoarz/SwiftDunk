import Foundation
public import SwiftDunkAuth

/// An authenticated, validated Apple Developer Portal session.
///
/// Both initializers validate credentials by listing teams before returning. The actor
/// does not run on the main actor and may be called from any isolation domain.
public actor DeveloperSession {
    let qh: QHClient
    let v1: V1Client
    let makeUUID: @Sendable () -> UUID
    private var knownTeams: [Team.ID: Team]
    private var ensureGeneration = 0
    private var deviceTasks: [DeviceEnsureKey: InFlightOperation<Device>] = [:]
    private var appIDTasks: [AppIDEnsureKey: InFlightOperation<AppID>] = [:]
    private var appGroupTasks: [AppGroupEnsureKey: InFlightOperation<AppGroup>] = [:]

    /// The serializable credentials needed to restore this session.
    ///
    /// The selected team is updated after a team-scoped operation. This value contains
    /// a bearer token and must be persisted only through a protected ``SessionStore``.
    public private(set) var stored: StoredSession

    /// Creates and validates a Developer Portal session from a GrandSlam account.
    ///
    /// This requests the `com.apple.gs.xcode.auth` token and then lists teams to prove
    /// that the resulting Portal credentials work.
    /// - Throws: ``SwiftDunkError`` for app-token, anisette, transport, malformed
    ///   response, or Developer Portal failures.
    public init(
        account: Account,
        anisette: any AnisetteProvider,
        transport: any HTTPTransport = URLSessionTransport()
    ) async throws {
        let token = try await account.appToken(PortalConstants.xcodeApp)
        let stored = StoredSession(
            appleID: account.appleID,
            adsid: account.dsid,
            xcodeGSToken: token.value
        )
        let credentials = PortalCredentials(
            adsid: stored.adsid,
            token: stored.xcodeGSToken
        )
        let qh = QHClient(
            anisette: anisette,
            credentials: credentials,
            transport: transport
        )
        let teams = try await qh.paginated(
            path: PortalConstants.QHPath.listTeams,
            as: QHTeamsResponse.self,
            values: \.teams
        )
        self.stored = stored
        self.qh = qh
        v1 = V1Client(
            anisette: anisette,
            credentials: credentials,
            transport: transport
        )
        makeUUID = UUID.init
        knownTeams = Self.teamIndex(teams)
    }

    /// Restores and validates a previously saved Developer Portal session.
    ///
    /// No password or GrandSlam login is needed. Listing teams still occurs before the
    /// initializer returns, so an expired or revoked token fails immediately.
    /// - Throws: ``SwiftDunkError`` for anisette, transport, malformed response, expired
    ///   credentials, or other Developer Portal failures.
    public init(
        restoring session: StoredSession,
        anisette: any AnisetteProvider,
        transport: any HTTPTransport = URLSessionTransport()
    ) async throws {
        let credentials = PortalCredentials(
            adsid: session.adsid,
            token: session.xcodeGSToken
        )
        let qh = QHClient(
            anisette: anisette,
            credentials: credentials,
            transport: transport
        )
        let teams = try await qh.paginated(
            path: PortalConstants.QHPath.listTeams,
            as: QHTeamsResponse.self,
            values: \.teams
        )
        stored = session
        self.qh = qh
        v1 = V1Client(
            anisette: anisette,
            credentials: credentials,
            transport: transport
        )
        makeUUID = UUID.init
        knownTeams = Self.teamIndex(teams)
    }

    init(
        stored: StoredSession,
        qh: QHClient,
        v1: V1Client,
        makeUUID: @escaping @Sendable () -> UUID,
        knownTeams: [Team] = []
    ) {
        self.stored = stored
        self.qh = qh
        self.v1 = v1
        self.makeUUID = makeUUID
        self.knownTeams = Self.teamIndex(knownTeams)
    }

    func record(teamID: Team.ID) {
        guard stored.teamID != teamID.rawValue else { return }
        stored = StoredSession(
            appleID: stored.appleID,
            adsid: stored.adsid,
            xcodeGSToken: stored.xcodeGSToken,
            teamID: teamID.rawValue
        )
    }

    func cache(_ teams: [Team]) {
        knownTeams = Self.teamIndex(teams)
    }

    func isFreeAccount(teamID: Team.ID) -> Bool {
        knownTeams[teamID]?.isXcodeFreeOnly == true
    }

    private static func teamIndex(_ teams: [Team]) -> [Team.ID: Team] {
        teams.reduce(into: [:]) { index, team in
            index[team.id] = team
        }
    }

    func deviceTask(
        teamID: Team.ID,
        name: String,
        udid: String
    ) -> InFlightOperation<Device> {
        let key = DeviceEnsureKey(teamID: teamID, udid: udid)
        if let operation = deviceTasks[key] {
            return operation
        }

        let operation = inFlightOperation {
            try await self.performEnsureDevice(teamID: teamID, name: name, udid: udid)
        }
        deviceTasks[key] = operation
        return operation
    }

    func appIDTask(
        teamID: Team.ID,
        name: String,
        identifier: String
    ) -> InFlightOperation<AppID> {
        let key = AppIDEnsureKey(teamID: teamID, identifier: identifier)
        if let operation = appIDTasks[key] {
            return operation
        }

        let operation = inFlightOperation {
            try await self.performEnsureAppID(
                teamID: teamID,
                name: name,
                identifier: identifier
            )
        }
        appIDTasks[key] = operation
        return operation
    }

    func appGroupTask(
        teamID: Team.ID,
        name: String,
        identifier: String
    ) -> InFlightOperation<AppGroup> {
        let key = AppGroupEnsureKey(teamID: teamID, identifier: identifier)
        if let operation = appGroupTasks[key] {
            return operation
        }

        let operation = inFlightOperation {
            try await self.performEnsureAppGroup(
                teamID: teamID,
                name: name,
                identifier: identifier
            )
        }
        appGroupTasks[key] = operation
        return operation
    }

    func clearDeviceTask(
        teamID: Team.ID,
        udid: String,
        generation: Int
    ) {
        let key = DeviceEnsureKey(teamID: teamID, udid: udid)
        if deviceTasks[key]?.generation == generation {
            deviceTasks[key] = nil
        }
    }

    func clearAppIDTask(
        teamID: Team.ID,
        identifier: String,
        generation: Int
    ) {
        let key = AppIDEnsureKey(teamID: teamID, identifier: identifier)
        if appIDTasks[key]?.generation == generation {
            appIDTasks[key] = nil
        }
    }

    func clearAppGroupTask(
        teamID: Team.ID,
        identifier: String,
        generation: Int
    ) {
        let key = AppGroupEnsureKey(teamID: teamID, identifier: identifier)
        if appGroupTasks[key]?.generation == generation {
            appGroupTasks[key] = nil
        }
    }

    private func inFlightOperation<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) -> InFlightOperation<Value> {
        ensureGeneration &+= 1
        return InFlightOperation(
            generation: ensureGeneration,
            task: Task {
                try await operation()
            }
        )
    }
}

private struct DeviceEnsureKey: Hashable {
    let teamID: Team.ID
    let udid: String
}

private struct AppIDEnsureKey: Hashable {
    let teamID: Team.ID
    let identifier: String
}

private struct AppGroupEnsureKey: Hashable {
    let teamID: Team.ID
    let identifier: String
}

struct InFlightOperation<Value: Sendable>: Sendable {
    let generation: Int
    let task: Task<Value, any Error>
}
