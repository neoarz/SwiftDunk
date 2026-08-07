import Foundation
import Security
import SwiftDunk
import SwiftDunkTestSupport
import Testing

@Suite("Remote Anisette v3")
struct RemoteAnisetteTests {
    @Test("Unprovisioned state completes the scripted v3 state machine")
    func provisionsAndFetchesHeaders() async throws {
        let identifier = Data(UInt8(0)...UInt8(15))
        let state = try AnisetteState(keychainIdentifier: identifier)
        let store = MemoryAnisetteStateStore(state: state)
        let scenario = RemoteAnisetteHTTPScenario(headerOutcomes: [.headers])
        let socket = ScriptedAnisetteWebSocket(incoming: provisioningMessages)
        let factory = ScriptedAnisetteWebSocketFactory(socket: socket)
        let now = Date(timeIntervalSince1970: 1_000)
        let provider = try makeProvider(
            store: store,
            scenario: scenario,
            factory: factory,
            now: now
        )

        let headers = try await provider.headers()
        let cached = try await provider.headers()

        #expect(headers == cached)
        #expect(headers.values.count == 10)
        #expect(headers.header("X-Apple-I-MD") == "one-time-password")
        #expect(headers.header("X-Apple-I-MD-M") == "machine-token")
        #expect(headers.header("X-Apple-I-MD-RINFO") == "server-routing-value")
        #expect(headers.header("X-Mme-Device-Id") == "00010203-0405-0607-0809-0a0b0c0d0e0f")
        #expect(
            headers.header("X-Apple-I-MD-LU")
                == "be45cb2605bf36bebde684841a28f0fd43c69850a3dce5fedba69928ee3a8991"
        )
        #expect(headers.header("X-Apple-I-Client-Time") == "1970-01-01T00:16:40Z")
        #expect(headers.header("X-Apple-I-TimeZone") == "UTC")
        #expect(headers.header("X-Apple-Locale") == "en_US")
        #expect(headers.header("X-Apple-I-SRL-NO") == "0")

        let saved = try #require(await store.current())
        #expect(saved.keychainIdentifier == identifier)
        #expect(saved.adiPB == Data("new-adi".utf8))
        #expect(await store.savedStates.count == 1)
        #expect(await scenario.headerRequestCount == 1)
        #expect(await scenario.lookupRequestCount == 1)
        #expect(await scenario.startRequestCount == 1)
        #expect(await scenario.finishRequestCount == 1)
        try await assertWebSocketExchange(socket: socket, factory: factory, identifier: identifier)
    }

    @Test("A -45061 response reprovisions and retries exactly once")
    func staleStateReprovisionsOnce() async throws {
        let identifier = Data(UInt8(0)...UInt8(15))
        let state = try AnisetteState(
            keychainIdentifier: identifier,
            adiPB: Data("old-adi".utf8)
        )
        let store = MemoryAnisetteStateStore(state: state)
        let scenario = RemoteAnisetteHTTPScenario(headerOutcomes: [.stale, .headers])
        let socket = ScriptedAnisetteWebSocket(incoming: provisioningMessages)
        let factory = ScriptedAnisetteWebSocketFactory(socket: socket)
        let provider = try makeProvider(
            store: store,
            scenario: scenario,
            factory: factory,
            now: Date(timeIntervalSince1970: 2_000)
        )

        let headers = try await provider.headers()

        #expect(headers.header("X-Apple-I-MD") == "one-time-password")
        #expect(await scenario.headerRequestCount == 2)
        #expect(await scenario.lookupRequestCount == 1)
        #expect(await factory.connectedURLs.count == 1)
        #expect(await store.savedStates.count == 1)
        #expect(await store.current()?.adiPB == Data("new-adi".utf8))
        let payloads = await scenario.headerPayloads
        #expect(
            payloads.map(\.adiPB) == [
                Data("old-adi".utf8).base64EncodedString(),
                Data("new-adi".utf8).base64EncodedString(),
            ])
    }

    @Test("A second -45061 response fails without a provisioning loop")
    func freshStateRejectionDoesNotLoop() async throws {
        let state = try AnisetteState(
            keychainIdentifier: Data(UInt8(0)...UInt8(15)),
            adiPB: Data("old-adi".utf8)
        )
        let store = MemoryAnisetteStateStore(state: state)
        let scenario = RemoteAnisetteHTTPScenario(headerOutcomes: [.stale, .stale])
        let socket = ScriptedAnisetteWebSocket(incoming: provisioningMessages)
        let factory = ScriptedAnisetteWebSocketFactory(socket: socket)
        let provider = try makeProvider(
            store: store,
            scenario: scenario,
            factory: factory,
            now: Date(timeIntervalSince1970: 3_000)
        )

        await #expect {
            try await provider.headers()
        } throws: { error in
            guard let error = error as? SwiftDunkError else { return false }
            return error.code
                == .anisetteProvisioningFailed(
                    "The anisette server rejected freshly provisioned state."
                )
        }
        #expect(await scenario.headerRequestCount == 2)
        #expect(await scenario.lookupRequestCount == 1)
        #expect(await factory.connectedURLs.count == 1)
        #expect(await socket.closeCount == 1)
    }

    @Test("A new device identifier is saved before provisioning and remains unchanged")
    func newIdentifierIsPersistedOnce() async throws {
        let store = MemoryAnisetteStateStore(state: nil)
        let scenario = RemoteAnisetteHTTPScenario(headerOutcomes: [.headers])
        let socket = ScriptedAnisetteWebSocket(incoming: provisioningMessages)
        let factory = ScriptedAnisetteWebSocketFactory(socket: socket)
        let provider = try makeProvider(
            store: store,
            scenario: scenario,
            factory: factory,
            now: Date(timeIntervalSince1970: 4_000)
        )

        _ = try await provider.headers()

        let states = await store.savedStates
        #expect(states.count == 2)
        let first = try #require(states.first)
        let last = try #require(states.last)
        #expect(first.keychainIdentifier.count == 16)
        #expect(first.keychainIdentifier == last.keychainIdentifier)
        #expect(first.adiPB == nil)
        #expect(last.adiPB == Data("new-adi".utf8))
    }

    @Test("A provisioning save preserves its Security framework failure")
    func provisioningSavePreservesSecurityFailure() async throws {
        let status = Int(errSecInteractionNotAllowed)
        let state = try AnisetteState(
            keychainIdentifier: Data(UInt8(0)...UInt8(15))
        )
        let store = SaveFailingAnisetteStateStore(state: state, status: status)
        let scenario = RemoteAnisetteHTTPScenario(headerOutcomes: [.headers])
        let socket = ScriptedAnisetteWebSocket(incoming: provisioningMessages)
        let provider = try makeProvider(
            store: store,
            scenario: scenario,
            factory: ScriptedAnisetteWebSocketFactory(socket: socket),
            now: Date(timeIntervalSince1970: 5_000)
        )

        await #expect {
            try await provider.headers()
        } throws: { error in
            (error as? SwiftDunkError)?.code == .securityFramework(status: status)
        }
    }

    private var provisioningMessages: [String] {
        [
            #"{"result":"GiveIdentifier"}"#,
            #"{"result":"GiveStartProvisioningData"}"#,
            #"{"result":"GiveEndProvisioningData","cpim":"server-cpim"}"#,
            #"{"result":"ProvisioningSuccess","adi_pb":"bmV3LWFkaQ=="}"#,
        ]
    }

    private func makeProvider(
        store: any AnisetteStateStore,
        scenario: RemoteAnisetteHTTPScenario,
        factory: ScriptedAnisetteWebSocketFactory,
        now: Date
    ) throws -> RemoteAnisetteProvider {
        let serverURL = try #require(URL(string: "https://anisette.example/base"))
        let server = AnisetteServer(url: serverURL)
        return RemoteAnisetteProvider(
            server: server,
            stateStore: store,
            transport: MockTransport { request in
                try await scenario.send(request)
            },
            webSockets: factory,
            refreshAfter: 60,
            hardExpiry: 90,
            now: { now }
        )
    }

    private func assertWebSocketExchange(
        socket: ScriptedAnisetteWebSocket,
        factory: ScriptedAnisetteWebSocketFactory,
        identifier: Data
    ) async throws {
        let connectedURL = try #require(await factory.connectedURLs.first)
        #expect(connectedURL.scheme == "wss")
        #expect(connectedURL.path == "/base/v3/provisioning_session")
        #expect(await socket.closeCount == 1)

        let messages = await socket.sent
        try #require(messages.count == 3)
        let identifierMessage = try decodeDictionary(messages[0])
        let startMessage = try decodeDictionary(messages[1])
        let finishMessage = try decodeDictionary(messages[2])
        #expect(identifierMessage["identifier"] == identifier.base64EncodedString())
        #expect(startMessage["spim"] == "start-spim")
        #expect(finishMessage["ptm"] == "finish-ptm")
        #expect(finishMessage["tk"] == "finish-tk")
    }

    private func decodeDictionary(_ text: String) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: Data(text.utf8))
    }
}
