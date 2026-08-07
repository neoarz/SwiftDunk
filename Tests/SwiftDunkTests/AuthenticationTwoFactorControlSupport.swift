import Foundation
import SwiftDunk

actor TwoFactorActionRecorder {
    private var responses: [TwoFactorResponse]
    private(set) var methods: [TwoFactorMethod] = []
    private(set) var deliveryErrors: [SwiftDunkError.Code?] = []

    init(responses: [TwoFactorResponse]) {
        self.responses = responses
    }

    func response(for challenge: TwoFactorChallenge) throws -> TwoFactorResponse {
        methods.append(challenge.method)
        deliveryErrors.append(challenge.previousDeliveryError)
        guard !responses.isEmpty else { throw TestFlowError.unexpectedStep }
        return responses.removeFirst()
    }
}

actor OneShotSMSFailureTransport {
    let scenario: GrandSlamScenario
    private var hasFailed = false

    init(scenario: GrandSlamScenario) {
        self.scenario = scenario
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url.path == "/auth/verify/phone", !hasFailed {
            hasFailed = true
            throw CustomTransportError.disconnected
        }
        return try await scenario.send(request)
    }
}

actor OneShotSMSCancellationTransport {
    let scenario: GrandSlamScenario
    private var hasCancelled = false

    init(scenario: GrandSlamScenario) {
        self.scenario = scenario
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url.path == "/auth/verify/phone", !hasCancelled {
            hasCancelled = true
            throw CancellationError()
        }
        return try await scenario.send(request)
    }
}

private enum CustomTransportError: Error {
    case disconnected
}
