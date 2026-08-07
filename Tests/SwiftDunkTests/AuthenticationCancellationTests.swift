import SwiftDunk
import SwiftDunkTestSupport
import Testing

extension AuthenticationTests {
    @Test("The convenience login propagates a custom transport cancellation")
    func convenienceLoginCustomTransportCancellation() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil]
        )
        let transport = OneShotSMSCancellationTransport(scenario: scenario)
        let recorder = TwoFactorActionRecorder(
            responses: [
                .sendSMS(phoneNumberID: 7),
                .sendToTrustedDevices,
            ]
        )

        await #expect {
            try await Account.login(
                appleID: "USER@EXAMPLE.COM",
                password: SRPVectors.passwordDerivation.password,
                anisette: anisette,
                transport: MockTransport { request in
                    try await transport.send(request)
                }
            ) { challenge in
                try await recorder.response(for: challenge)
            }
        } throws: { error in
            error is CancellationError
        }

        #expect(await recorder.methods == [.trustedDevice])
    }

    @Test("Cancelling in-flight delivery does not re-present the challenge")
    func convenienceLoginInFlightCancellation() async throws {
        let barrier = AuthenticationRequestBarrier()
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil],
            blockedRequest: .smsRequest,
            requestBarrier: barrier
        )
        let recorder = TwoFactorActionRecorder(
            responses: [
                .sendSMS(phoneNumberID: 7),
                .sendToTrustedDevices,
            ]
        )
        let login = Task {
            try await Account.login(
                appleID: "USER@EXAMPLE.COM",
                password: SRPVectors.passwordDerivation.password,
                anisette: anisette,
                transport: transport(for: scenario)
            ) { challenge in
                try await recorder.response(for: challenge)
            }
        }

        await barrier.waitUntilEntered()
        login.cancel()
        await barrier.release()

        await #expect {
            try await login.value
        } throws: { error in
            error is CancellationError
        }
        #expect(await recorder.methods == [.trustedDevice])
    }
}
