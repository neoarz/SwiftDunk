import Foundation
import SwiftDunk
import Testing

extension AuthenticationTests {
    @Test("A second login cannot overlap an in-flight login")
    func beginOverlap() async throws {
        let barrier = AuthenticationRequestBarrier()
        let scenario = GrandSlamScenario(
            authenticationTypes: [nil],
            blockedRequest: .grandSlam,
            requestBarrier: barrier
        )
        let session = makeSession(scenario: scenario)
        let firstLogin = Task {
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        }

        await barrier.waitUntilEntered()
        let requestsBeforeOverlap = await scenario.requestCount
        await #expect {
            try await session.begin(password: "another-password")
        } throws: { error in
            (error as? SwiftDunkError)?.code == .operationInProgress("authentication")
        }
        #expect(await scenario.requestCount == requestsBeforeOverlap)

        await barrier.release()
        _ = try authenticated(try await firstLogin.value)
    }

    @Test("SMS fallback cannot interleave with trusted-code validation")
    func trustedCodeSMSOverlap() async throws {
        let barrier = AuthenticationRequestBarrier()
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil],
            blockedRequest: .trustedValidation,
            requestBarrier: barrier
        )
        let session = makeSession(scenario: scenario)
        _ = try await session.begin(password: SRPVectors.passwordDerivation.password)

        let validation = Task {
            try await session.submitTwoFactorCode("123456")
        }
        await barrier.waitUntilEntered()
        let requestsBeforeOverlap = await scenario.requestCount
        await #expect {
            try await session.requestSMSCode(phoneNumberID: 7)
        } throws: { error in
            (error as? SwiftDunkError)?.code == .operationInProgress("authentication")
        }
        #expect(await scenario.requestCount == requestsBeforeOverlap)
        #expect(await scenario.sendSMSCount == 0)

        await barrier.release()
        _ = try authenticated(try await validation.value)
    }

    @Test("Duplicate code submission is rejected and the guard clears after failure")
    func duplicateCodeOverlapAndRetry() async throws {
        let barrier = AuthenticationRequestBarrier()
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth"],
            verificationStatus: 401,
            blockedRequest: .trustedValidation,
            requestBarrier: barrier
        )
        let session = makeSession(scenario: scenario)
        _ = try await session.begin(password: SRPVectors.passwordDerivation.password)

        let firstValidation = Task {
            try await session.submitTwoFactorCode("111111")
        }
        await barrier.waitUntilEntered()
        let requestsBeforeOverlap = await scenario.requestCount
        await #expect {
            try await session.submitTwoFactorCode("222222")
        } throws: { error in
            (error as? SwiftDunkError)?.code == .operationInProgress("authentication")
        }
        #expect(await scenario.requestCount == requestsBeforeOverlap)

        await barrier.release()
        await #expect {
            try await firstValidation.value
        } throws: { error in
            (error as? SwiftDunkError)?.code == .invalidTwoFactorCode
        }
        await #expect {
            try await session.submitTwoFactorCode("333333")
        } throws: { error in
            (error as? SwiftDunkError)?.code == .invalidTwoFactorCode
        }
        #expect(await scenario.trustedValidationCount == 2)
        #expect(await scenario.submittedCodes == ["111111", "333333"])
    }
}
