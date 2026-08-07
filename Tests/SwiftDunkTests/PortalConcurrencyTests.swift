import Foundation
import SwiftDunk
import SwiftDunkTestSupport
import Testing

@Suite("Developer Portal concurrency")
struct PortalConcurrencyTests {
    @Test("Concurrent identical device ensures register once")
    func deviceEnsureCoalesces() async throws {
        let scenario = EnsureScenario(resource: .device)
        let session = try await makeSession(scenario)
        let teamID = Team.ID(rawValue: PortalFixtures.teamID)

        let first = Task {
            try await session.ensureDevice(
                teamID: teamID,
                name: "New Phone",
                udid: "UDID-NEW"
            )
        }
        let second = Task {
            try await session.ensureDevice(
                teamID: teamID,
                name: "New Phone",
                udid: "UDID-NEW"
            )
        }

        await scenario.waitUntilListIsBlocked()
        await scenario.releaseLists()

        let firstDevice = try await first.value
        let secondDevice = try await second.value
        #expect(firstDevice.id == secondDevice.id)
        #expect(await scenario.listCount == 1)
        #expect(await scenario.createCount == 1)
    }

    @Test("Concurrent identical App ID ensures create once")
    func appIDEnsureCoalesces() async throws {
        let scenario = EnsureScenario(resource: .appID)
        let session = try await makeSession(scenario)
        let teamID = Team.ID(rawValue: PortalFixtures.teamID)

        let first = Task {
            try await session.ensureAppID(
                teamID: teamID,
                name: "My App",
                identifier: PortalFixtures.appIdentifier
            )
        }
        let second = Task {
            try await session.ensureAppID(
                teamID: teamID,
                name: "My App",
                identifier: PortalFixtures.appIdentifier
            )
        }

        await scenario.waitUntilListIsBlocked()
        await scenario.releaseLists()

        let firstAppID = try await first.value
        let secondAppID = try await second.value
        #expect(firstAppID.id == secondAppID.id)
        #expect(await scenario.listCount == 1)
        #expect(await scenario.createCount == 1)
    }

    @Test("Concurrent identical App Group ensures create once")
    func appGroupEnsureCoalesces() async throws {
        let scenario = EnsureScenario(resource: .appGroup)
        let session = try await makeSession(scenario)
        let teamID = Team.ID(rawValue: PortalFixtures.teamID)

        let first = Task {
            try await session.ensureAppGroup(
                teamID: teamID,
                name: "My Group",
                identifier: PortalFixtures.groupIdentifier
            )
        }
        let second = Task {
            try await session.ensureAppGroup(
                teamID: teamID,
                name: "My Group",
                identifier: PortalFixtures.groupIdentifier
            )
        }

        await scenario.waitUntilListIsBlocked()
        await scenario.releaseLists()

        let firstGroup = try await first.value
        let secondGroup = try await second.value
        #expect(firstGroup.id == secondGroup.id)
        #expect(await scenario.listCount == 1)
        #expect(await scenario.createCount == 1)
    }

    @Test("Different resource identifiers remain independent")
    func differentIdentifiersDoNotCoalesce() async throws {
        let scenario = EnsureScenario(resource: .device)
        let session = try await makeSession(scenario)
        let teamID = Team.ID(rawValue: PortalFixtures.teamID)

        let first = Task {
            try await session.ensureDevice(
                teamID: teamID,
                name: "First Phone",
                udid: "UDID-FIRST"
            )
        }
        let second = Task {
            try await session.ensureDevice(
                teamID: teamID,
                name: "Second Phone",
                udid: "UDID-SECOND"
            )
        }

        await scenario.waitUntilListCount(2)
        await scenario.releaseLists()

        _ = try await first.value
        _ = try await second.value
        #expect(await scenario.createCount == 2)
    }

    @Test("A failed ensure clears its in-flight entry", arguments: EnsureResource.allCases)
    func failedEnsureCanBeRetried(resource: EnsureResource) async throws {
        let scenario = EnsureScenario(resource: resource, failingCreations: 1)
        let session = try await makeSession(scenario)
        let teamID = Team.ID(rawValue: PortalFixtures.teamID)

        let first = Task {
            try await ensure(resource, in: session, teamID: teamID)
        }
        await scenario.waitUntilListIsBlocked()
        await scenario.releaseLists()

        await #expect {
            try await first.value
        } throws: { error in
            error is ExpectedCreationFailure
        }

        let retriedID = try await ensure(resource, in: session, teamID: teamID)

        #expect(retriedID == resource.createdID)
        #expect(await scenario.listCount == 2)
        #expect(await scenario.createCount == 2)
    }

    private func makeSession(_ scenario: EnsureScenario) async throws -> DeveloperSession {
        try await DeveloperSession(
            restoring: StoredSession(
                appleID: "test@example.com",
                adsid: "1234567890",
                xcodeGSToken: "fixture-xcode-token"
            ),
            anisette: .mock,
            transport: MockTransport { request in
                try await scenario.send(request)
            }
        )
    }

    private func ensure(
        _ resource: EnsureResource,
        in session: DeveloperSession,
        teamID: Team.ID
    ) async throws -> String {
        switch resource {
        case .device:
            try await session.ensureDevice(
                teamID: teamID,
                name: "New Phone",
                udid: "UDID-NEW"
            ).id.rawValue
        case .appID:
            try await session.ensureAppID(
                teamID: teamID,
                name: "My App",
                identifier: PortalFixtures.appIdentifier
            ).id.rawValue
        case .appGroup:
            try await session.ensureAppGroup(
                teamID: teamID,
                name: "My Group",
                identifier: PortalFixtures.groupIdentifier
            ).id.rawValue
        }
    }
}

enum EnsureResource: CaseIterable, Sendable {
    case device
    case appID
    case appGroup

    var listPathSuffix: String {
        switch self {
        case .device:
            "/ios/listDevices.action"
        case .appID:
            "/ios/listAppIds.action"
        case .appGroup:
            "/ios/listApplicationGroups.action"
        }
    }

    var createPathSuffix: String {
        switch self {
        case .device:
            "/ios/addDevice.action"
        case .appID:
            "/ios/addAppId.action"
        case .appGroup:
            "/ios/addApplicationGroup.action"
        }
    }

    var createdID: String {
        switch self {
        case .device:
            "DEVICE-NEW"
        case .appID:
            PortalFixtures.appIDID
        case .appGroup:
            PortalFixtures.appGroupID
        }
    }

    func emptyListResponse() throws -> Data {
        switch self {
        case .device:
            try PortalFixtures.noDevices()
        case .appID:
            try PortalFixtures.noAppIDs()
        case .appGroup:
            try PortalFixtures.noAppGroups()
        }
    }

    func creationResponse() throws -> Data {
        switch self {
        case .device:
            try PortalFixtures.device()
        case .appID:
            try PortalFixtures.appIDResponse()
        case .appGroup:
            try PortalFixtures.appGroupResponse()
        }
    }
}

private actor EnsureScenario {
    private let resource: EnsureResource
    private let listGate = AsyncTestGate()
    private var failingCreations: Int
    private(set) var listCount = 0
    private(set) var createCount = 0
    private var listCountObservers: [ListCountObserver] = []

    init(resource: EnsureResource, failingCreations: Int = 0) {
        self.resource = resource
        self.failingCreations = failingCreations
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url.path.hasSuffix("/listTeams.action") {
            return HTTPResponse(statusCode: 200, body: try PortalFixtures.teams())
        }
        if request.url.path.hasSuffix(resource.listPathSuffix) {
            listCount += 1
            resumeListCountObservers()
            await listGate.wait()
            return HTTPResponse(statusCode: 200, body: try resource.emptyListResponse())
        }
        if request.url.path.hasSuffix(resource.createPathSuffix) {
            createCount += 1
            if failingCreations > 0 {
                failingCreations -= 1
                throw ExpectedCreationFailure()
            }
            return HTTPResponse(statusCode: 200, body: try resource.creationResponse())
        }

        Issue.record("Unexpected ensure endpoint: \(request.url.path)")
        return HTTPResponse(statusCode: 200, body: try PortalFixtures.empty())
    }

    func waitUntilListIsBlocked() async {
        await listGate.waitUntilBlocked()
    }

    func waitUntilListCount(_ expectedCount: Int) async {
        guard listCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            listCountObservers.append(
                ListCountObserver(
                    expectedCount: expectedCount,
                    continuation: continuation
                )
            )
        }
    }

    func releaseLists() async {
        await listGate.open()
    }

    private func resumeListCountObservers() {
        let ready = listCountObservers.filter { listCount >= $0.expectedCount }
        listCountObservers.removeAll { listCount >= $0.expectedCount }
        ready.forEach { $0.continuation.resume() }
    }
}

private struct ExpectedCreationFailure: Error {}

private struct ListCountObserver {
    let expectedCount: Int
    let continuation: CheckedContinuation<Void, Never>
}

private actor AsyncTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var observers: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            let currentObservers = observers
            observers.removeAll()
            currentObservers.forEach { $0.resume() }
        }
    }

    func waitUntilBlocked() async {
        guard waiters.isEmpty else { return }
        await withCheckedContinuation { continuation in
            observers.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let currentWaiters = waiters
        waiters.removeAll()
        currentWaiters.forEach { $0.resume() }
    }
}
