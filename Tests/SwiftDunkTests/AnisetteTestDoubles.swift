import Foundation
import SwiftDunk
import SwiftDunkTestSupport
import Testing

final class LockedTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func now() -> Date {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            value = value.addingTimeInterval(interval)
        }
    }
}

actor ScriptedAnisetteProvider: AnisetteProvider {
    private var outcomes: [Result<AnisetteHeaders, SwiftDunkError>]
    private(set) var requestCount = 0

    init(outcomes: [Result<AnisetteHeaders, SwiftDunkError>]) {
        self.outcomes = outcomes
    }

    func headers() async throws -> AnisetteHeaders {
        requestCount += 1
        guard !outcomes.isEmpty else {
            throw SwiftDunkError(code: .anisetteUnavailable)
        }
        return try outcomes.removeFirst().get()
    }
}

actor ClockRollingAnisetteProvider: AnisetteProvider {
    private let cached: AnisetteHeaders
    private let clock: LockedTestClock
    private let rollback: TimeInterval
    private(set) var requestCount = 0

    init(
        cached: AnisetteHeaders,
        clock: LockedTestClock,
        rollback: TimeInterval
    ) {
        self.cached = cached
        self.clock = clock
        self.rollback = rollback
    }

    func headers() async throws -> AnisetteHeaders {
        requestCount += 1
        guard requestCount > 1 else {
            return cached
        }
        clock.advance(by: -rollback)
        throw SwiftDunkError(code: .anisetteUnavailable)
    }
}

actor BlockingAnisetteProvider: AnisetteProvider {
    private let result: AnisetteHeaders
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var requestCount = 0

    init(result: AnisetteHeaders) {
        self.result = result
    }

    func headers() async throws -> AnisetteHeaders {
        requestCount += 1
        let waiting = startContinuations
        startContinuations.removeAll()
        for continuation in waiting {
            continuation.resume()
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return result
    }

    func waitUntilStarted() async {
        if requestCount > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

actor MemoryAnisetteStateStore: AnisetteStateStore {
    private var state: AnisetteState?
    private(set) var savedStates: [AnisetteState] = []

    init(state: AnisetteState?) {
        self.state = state
    }

    func load() async throws -> AnisetteState? {
        state
    }

    func save(_ state: AnisetteState) async throws {
        self.state = state
        savedStates.append(state)
    }

    func current() -> AnisetteState? {
        state
    }
}

struct SaveFailingAnisetteStateStore: AnisetteStateStore {
    let state: AnisetteState
    let status: Int

    func load() async throws -> AnisetteState? {
        state
    }

    func save(_: AnisetteState) async throws {
        throw SwiftDunkError.securityFrameworkError(status: status)
    }
}

actor ScriptedAnisetteWebSocket: AnisetteWebSocket {
    private var incoming: [String]
    private(set) var sent: [String] = []
    private(set) var closeCount = 0

    init(incoming: [String]) {
        self.incoming = incoming
    }

    func receiveText() async throws -> String? {
        guard !incoming.isEmpty else { return nil }
        return incoming.removeFirst()
    }

    func send(text: String) async throws {
        sent.append(text)
    }

    func close() async {
        closeCount += 1
    }
}

actor ScriptedAnisetteWebSocketFactory: AnisetteWebSocketFactory {
    private let socket: ScriptedAnisetteWebSocket
    private(set) var connectedURLs: [URL] = []

    init(socket: ScriptedAnisetteWebSocket) {
        self.socket = socket
    }

    func connect(to url: URL) async throws -> any AnisetteWebSocket {
        connectedURLs.append(url)
        return socket
    }
}

actor RemoteAnisetteHTTPScenario {
    enum HeaderOutcome: Sendable {
        case headers
        case stale
    }

    private var headerOutcomes: [HeaderOutcome]
    private(set) var headerRequestCount = 0
    private(set) var lookupRequestCount = 0
    private(set) var startRequestCount = 0
    private(set) var finishRequestCount = 0
    private(set) var headerPayloads: [(identifier: String, adiPB: String)] = []

    init(headerOutcomes: [HeaderOutcome]) {
        self.headerOutcomes = headerOutcomes
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        switch (request.url.host, request.url.path) {
        case ("anisette.example", "/base/v3/client_info"):
            return jsonResponse(
                ClientInfoResponse(
                    clientInfo: "<MacBookPro13,2> <macOS;13.1;22C65> <RemoteClient>",
                    userAgent: "RemoteAgent/1"
                )
            )

        case ("anisette.example", "/base/v3/get_headers"):
            headerRequestCount += 1
            let body = try #require(request.body)
            let payload = try JSONDecoder().decode(HeaderRequest.self, from: body)
            headerPayloads.append((payload.identifier, payload.adiPB))
            guard !headerOutcomes.isEmpty else {
                throw SwiftDunkError(code: .anisetteUnavailable)
            }
            switch headerOutcomes.removeFirst() {
            case .headers:
                return jsonResponse(
                    HeadersResponse(
                        result: "Headers",
                        message: nil,
                        machineID: "machine-token",
                        oneTimePassword: "one-time-password",
                        routingInfo: "server-routing-value"
                    )
                )
            case .stale:
                return jsonResponse(
                    HeadersResponse(
                        result: "GetHeadersError",
                        message: "ADI rejected with -45061",
                        machineID: nil,
                        oneTimePassword: nil,
                        routingInfo: nil
                    )
                )
            }

        case ("gsa.apple.com", "/grandslam/GsService2/lookup"):
            lookupRequestCount += 1
            return plistResponse(
                .dictionary([
                    "urls": .dictionary([
                        "midFinishProvisioning": .string("https://apple.example/finish"),
                        "midStartProvisioning": .string("https://apple.example/start"),
                    ])
                ])
            )

        case ("apple.example", "/start"):
            startRequestCount += 1
            let body = try #require(request.body)
            let root = try PropertyListDecoder().decode(PlistValue.self, from: body)
            #expect(root["Header"]?.dictionary == [:])
            #expect(root["Request"]?.dictionary == [:])
            return plistResponse(
                .dictionary([
                    "Response": .dictionary(["spim": .string("start-spim")])
                ])
            )

        case ("apple.example", "/finish"):
            finishRequestCount += 1
            let body = try #require(request.body)
            let root = try PropertyListDecoder().decode(PlistValue.self, from: body)
            #expect(root["Header"]?.dictionary == [:])
            #expect(root["Request"]?["cpim"]?.string == "server-cpim")
            return plistResponse(
                .dictionary([
                    "Response": .dictionary([
                        "ptm": .string("finish-ptm"),
                        "tk": .string("finish-tk"),
                    ])
                ])
            )

        default:
            Issue.record("Unexpected anisette request: \(request.url.absoluteString)")
            return HTTPResponse(statusCode: 500)
        }
    }

    private func jsonResponse<Value: Encodable>(_ value: Value) -> HTTPResponse {
        do {
            return HTTPResponse(statusCode: 200, body: try JSONEncoder().encode(value))
        } catch {
            Issue.record(error)
            return HTTPResponse(statusCode: 500)
        }
    }

    private func plistResponse(_ value: PlistValue) -> HTTPResponse {
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            return HTTPResponse(statusCode: 200, body: try encoder.encode(value))
        } catch {
            Issue.record(error)
            return HTTPResponse(statusCode: 500)
        }
    }
}

private struct HeaderRequest: Decodable {
    let identifier: String
    let adiPB: String

    enum CodingKeys: String, CodingKey {
        case identifier
        case adiPB = "adi_pb"
    }
}

private struct ClientInfoResponse: Encodable {
    let clientInfo: String
    let userAgent: String

    enum CodingKeys: String, CodingKey {
        case clientInfo = "client_info"
        case userAgent = "user_agent"
    }
}

private struct HeadersResponse: Encodable {
    let result: String
    let message: String?
    let machineID: String?
    let oneTimePassword: String?
    let routingInfo: String?

    enum CodingKeys: String, CodingKey {
        case result
        case message
        case machineID = "X-Apple-I-MD-M"
        case oneTimePassword = "X-Apple-I-MD"
        case routingInfo = "X-Apple-I-MD-RINFO"
    }
}
