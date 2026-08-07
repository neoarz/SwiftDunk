import Foundation
import SwiftDunk
import SwiftDunkTestSupport
import Testing

@Suite("GrandSlam authentication")
struct AuthenticationTests {
    @Test("A complete SRP exchange decrypts a typed account")
    func directLogin() async throws {
        let scenario = GrandSlamScenario(authenticationTypes: [nil])
        let session = makeSession(scenario: scenario)

        let account = try authenticated(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )

        #expect(account.appleID == "user@example.com")
        #expect(account.firstName == "Taylor")
        #expect(account.lastName == "Appleseed")
        #expect(account.dsid == "1234567890")
        #expect(await scenario.gsaInitCount == 1)
        #expect(await scenario.gsaCompleteCount == 1)
    }

    @Test("The full exchange honors an s2k_fo server selection")
    func fallbackPasswordProtocol() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: [nil],
            protocolName: "s2k_fo"
        )
        let session = makeSession(scenario: scenario)

        _ = try authenticated(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )
        #expect(await scenario.gsaCompleteCount == 1)
    }

    @Test("Trusted-device 2FA verifies and reruns the full SRP exchange")
    func trustedDeviceFlow() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil]
        )
        let session = makeSession(scenario: scenario)

        let challenge = try twoFactor(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )
        #expect(challenge.method == .trustedDevice)
        #expect(challenge.trustedPhoneNumbers.map(\.id) == [7])
        #expect(challenge.selectedPhoneNumberID == nil)

        _ = try authenticated(try await session.submitTwoFactorCode("012345"))

        #expect(await scenario.trustedPushCount == 1)
        #expect(await scenario.authExtrasCount == 1)
        #expect(await scenario.trustedValidationCount == 1)
        #expect(await scenario.submittedCodes == ["012345"])
        #expect(await scenario.gsaInitCount == 2)
        #expect(await scenario.gsaCompleteCount == 2)
    }

    @Test("SMS 2FA chooses Apple's phone identifier and reruns SRP")
    func smsFlow() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["secondaryAuth", nil]
        )
        let session = makeSession(scenario: scenario)

        let challenge = try twoFactor(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )
        #expect(challenge.method == .sms)
        #expect(challenge.trustedPhoneNumbers.map(\.id) == [7])
        #expect(challenge.selectedPhoneNumberID == 7)
        _ = try authenticated(try await session.submitTwoFactorCode("654321"))

        #expect(await scenario.sendSMSCount == 1)
        #expect(await scenario.smsValidationCount == 1)
        #expect(await scenario.sentPhoneNumberIDs == [7, 7])
        #expect(await scenario.submittedCodes == ["654321"])
        #expect(await scenario.gsaCompleteCount == 2)
    }

    @Test("A trusted-device prompt can fall back to SMS")
    func smsFallback() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil]
        )
        let session = makeSession(scenario: scenario)

        _ = try twoFactor(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )
        let smsChallenge = try twoFactor(
            try await session.requestSMSCode(phoneNumberID: 7)
        )
        #expect(smsChallenge.method == .sms)
        #expect(smsChallenge.selectedPhoneNumberID == 7)
        _ = try authenticated(try await session.submitTwoFactorCode("111222"))

        #expect(await scenario.sendSMSCount == 1)
        #expect(await scenario.smsValidationCount == 1)
        #expect(await scenario.trustedValidationCount == 0)
    }

    @Test("SMS requests encode the exact security-code wire shapes")
    func smsWireBodies() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["secondaryAuth", nil]
        )
        let session = makeSession(scenario: scenario)

        _ = try await session.begin(password: SRPVectors.passwordDerivation.password)
        _ = try await session.submitTwoFactorCode("004200")

        let sendBodies = await scenario.sendSMSBodies
        let sendBody = try #require(sendBodies.first)
        let sendJSON = try #require(
            try JSONSerialization.jsonObject(with: sendBody) as? [String: Any]
        )
        #expect(Set(sendJSON.keys) == ["phoneNumber", "mode", "securityCode"])
        #expect(sendJSON["mode"] as? String == "sms")
        #expect(sendJSON["securityCode"] is NSNull)
        let sendPhoneNumber = try #require(sendJSON["phoneNumber"] as? [String: Any])
        #expect(Set(sendPhoneNumber.keys) == ["id"])
        #expect(sendPhoneNumber["id"] as? Int == 7)

        let verifyBodies = await scenario.verifySMSBodies
        let verifyBody = try #require(verifyBodies.first)
        let verifyJSON = try #require(
            try JSONSerialization.jsonObject(with: verifyBody) as? [String: Any]
        )
        #expect(Set(verifyJSON.keys) == ["phoneNumber", "mode", "securityCode"])
        #expect(verifyJSON["mode"] as? String == "sms")
        let verifyPhoneNumber = try #require(
            verifyJSON["phoneNumber"] as? [String: Any]
        )
        #expect(Set(verifyPhoneNumber.keys) == ["id"])
        #expect(verifyPhoneNumber["id"] as? Int == 7)
        let securityCode = try #require(verifyJSON["securityCode"] as? [String: Any])
        #expect(Set(securityCode.keys) == ["code"])
        #expect(securityCode["code"] as? String == "004200")
    }

    @Test("A rejected SMS code throws the dedicated error")
    func badSMSCode() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["secondaryAuth"],
            verificationStatus: 401
        )
        let session = makeSession(scenario: scenario)
        _ = try await session.begin(password: SRPVectors.passwordDerivation.password)

        await #expect {
            try await session.submitTwoFactorCode("000000")
        } throws: { error in
            (error as? SwiftDunkError)?.code == .invalidTwoFactorCode
        }
    }

    @Test("HTTP 423 is rate limiting, not a bad code")
    func smsRateLimit() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["secondaryAuth"],
            verificationStatus: 423
        )
        let session = makeSession(scenario: scenario)
        _ = try await session.begin(password: SRPVectors.passwordDerivation.password)

        await #expect {
            try await session.submitTwoFactorCode("000000")
        } throws: { error in
            (error as? SwiftDunkError)?.code == .twoFactorRateLimited
        }
    }

    @Test("A failed post-2FA SRP rerun remains retryable without revalidating the code")
    func rerunFailureLeavesUsableState() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil],
            failFirstRerun: true
        )
        let session = makeSession(scenario: scenario)
        _ = try await session.begin(password: SRPVectors.passwordDerivation.password)

        await #expect {
            try await session.submitTwoFactorCode("123456")
        } throws: { error in
            (error as? SwiftDunkError)?.code == .network
        }
        _ = try authenticated(try await session.submitTwoFactorCode("ignored"))

        #expect(await scenario.trustedValidationCount == 1)
        #expect(await scenario.gsaInitCount == 3)
        #expect(await scenario.gsaCompleteCount == 2)
    }

    @Test("Unknown SRP protocol selections fail before complete")
    func unsupportedProtocol() async {
        let scenario = GrandSlamScenario(
            authenticationTypes: [nil],
            protocolName: "s2k_v9"
        )
        let session = makeSession(scenario: scenario)

        await #expect {
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        } throws: { error in
            (error as? SwiftDunkError)?.code == .unsupportedSRPProtocol("s2k_v9")
        }
        #expect(await scenario.gsaCompleteCount == 0)
    }

    @Test("Missing init fields name the exact malformed key")
    func missingSalt() async {
        let scenario = GrandSlamScenario(
            authenticationTypes: [nil],
            omitInitSalt: true
        )
        let session = makeSession(scenario: scenario)

        await #expect {
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .malformedResponse(key: "s", expected: "data")
        }
    }

    @Test(
        "GrandSlam errors are preserved from root and Status dictionaries",
        arguments: [
            TestGSAError.root(code: -20101, message: "root failure"),
            TestGSAError.status(code: -22406, message: "status failure"),
        ]
    )
    func grandSlamErrors(errorFixture: TestGSAError) async {
        let scenario = GrandSlamScenario(
            authenticationTypes: [nil],
            gsaError: errorFixture
        )
        let session = makeSession(scenario: scenario)

        await #expect {
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .grandSlam(
                    code: errorFixture.code,
                    message: errorFixture.message
                )
        }
    }

    @Test("A non-success HTTP response preserves a GrandSlam service error")
    func nonSuccessGrandSlamError() async {
        let errorFixture = TestGSAError.status(code: -22406, message: "account blocked")
        let scenario = GrandSlamScenario(
            authenticationTypes: [nil],
            gsaError: errorFixture,
            gsaStatusCode: 503
        )
        let session = makeSession(scenario: scenario)

        await #expect {
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .grandSlam(code: errorFixture.code, message: errorFixture.message)
        }
    }

    @Test("A non-success HTTP response without a service error preserves its status")
    func nonSuccessGrandSlamStatus() async {
        let scenario = GrandSlamScenario(
            authenticationTypes: [nil],
            gsaStatusCode: 503
        )
        let session = makeSession(scenario: scenario)

        await #expect {
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        } throws: { error in
            (error as? SwiftDunkError)?.code == .unexpectedStatusCode(503)
        }
    }

    @Test("An unknown account step is surfaced without an opaque login failure")
    func additionalAccountStep() async {
        let scenario = GrandSlamScenario(authenticationTypes: ["repairAccount"])
        let session = makeSession(scenario: scenario)

        await #expect {
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        } throws: { error in
            (error as? SwiftDunkError)?.code == .additionalStepRequired("repairAccount")
        }
    }

    @Test("The convenience login drives an SMS fallback without recursion")
    func accountConvenienceLogin() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil]
        )
        let recorder = ChallengeRecorder()

        let account = try await Account.login(
            appleID: "USER@EXAMPLE.COM",
            password: SRPVectors.passwordDerivation.password,
            anisette: anisette,
            transport: transport(for: scenario)
        ) { challenge in
            await recorder.record(challenge.method)
            switch challenge.method {
            case .trustedDevice:
                return .sendSMS(phoneNumberID: 7)
            case .sms:
                return .code("222333")
            }
        }

        #expect(account.appleID == "user@example.com")
        #expect(await recorder.methods == [.trustedDevice, .sms])
    }

    func makeSession(scenario: GrandSlamScenario) -> AuthenticationSession {
        AuthenticationSession(
            appleID: "USER@EXAMPLE.COM",
            anisette: anisette,
            transport: transport(for: scenario),
            privateKey: { Data(repeating: 0xAB, count: 32) }
        )
    }

    var anisette: StaticAnisetteProvider {
        StaticAnisetteProvider(
            values: [
                "X-Apple-I-MD": "test-otp",
                "X-Apple-I-MD-M": "test-machine",
                "X-Apple-I-MD-RINFO": "17106176",
                "X-Mme-Client-Info": "<TestMac> <macOS;1> <Remote>",
                "X-Apple-Locale": "en_US",
            ],
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    func transport(for scenario: GrandSlamScenario) -> MockTransport {
        MockTransport { request in
            try await scenario.send(request)
        }
    }

    func authenticated(_ step: LoginStep) throws -> Account {
        guard case .authenticated(let account) = step else {
            Issue.record("Expected an authenticated account.")
            throw TestFlowError.unexpectedStep
        }
        return account
    }

    func twoFactor(_ step: LoginStep) throws -> TwoFactorChallenge {
        guard case .twoFactorRequired(let challenge) = step else {
            Issue.record("Expected a two-factor challenge.")
            throw TestFlowError.unexpectedStep
        }
        return challenge
    }
}

private actor ChallengeRecorder {
    private(set) var methods: [TwoFactorMethod] = []

    func record(_ method: TwoFactorMethod) {
        methods.append(method)
    }
}

enum TestFlowError: Error {
    case unexpectedStep
}
