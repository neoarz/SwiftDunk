import Foundation
import SwiftDunk
import SwiftDunkTestSupport
import Testing

extension AuthenticationTests {
    @Test("Trusted-device codes can be resent")
    func trustedDeviceResend() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil]
        )
        let session = makeSession(scenario: scenario)
        _ = try twoFactor(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )

        let challenge = try twoFactor(try await session.resendTwoFactorCode())
        #expect(challenge.method == .trustedDevice)
        #expect(challenge.selectedPhoneNumberID == nil)
        #expect(await scenario.trustedPushCount == 2)

        _ = try authenticated(try await session.submitTwoFactorCode("112233"))
    }

    @Test("SMS codes can be resent to the selected number")
    func smsResend() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["secondaryAuth", nil]
        )
        let session = makeSession(scenario: scenario)
        _ = try twoFactor(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )

        let challenge = try twoFactor(try await session.resendTwoFactorCode())
        #expect(challenge.method == .sms)
        #expect(challenge.selectedPhoneNumberID == 7)
        #expect(await scenario.sendSMSCount == 2)
        #expect(await scenario.sentPhoneNumberIDs == [7, 7])

        _ = try authenticated(try await session.submitTwoFactorCode("223344"))
    }

    @Test("An SMS challenge can switch back to trusted devices")
    func smsToTrustedDevice() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["secondaryAuth", nil]
        )
        let session = makeSession(scenario: scenario)
        _ = try twoFactor(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )

        let challenge = try twoFactor(try await session.requestTrustedDeviceCode())
        #expect(challenge.method == .trustedDevice)
        #expect(challenge.selectedPhoneNumberID == nil)
        #expect(await scenario.trustedPushCount == 1)

        _ = try authenticated(try await session.submitTwoFactorCode("334455"))
        #expect(await scenario.trustedValidationCount == 1)
        #expect(await scenario.smsValidationCount == 0)
    }

    @Test("SMS delivery can move between Apple's trusted phone numbers")
    func switchSMSNumber() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil],
            phoneNumbers: [
                trustedPhoneNumber(id: 7, suffix: "42"),
                trustedPhoneNumber(id: 9, suffix: "17"),
            ]
        )
        let session = makeSession(scenario: scenario)
        _ = try twoFactor(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )

        let first = try twoFactor(try await session.requestSMSCode(phoneNumberID: 9))
        #expect(first.selectedPhoneNumberID == 9)
        let second = try twoFactor(try await session.requestSMSCode(phoneNumberID: 7))
        #expect(second.selectedPhoneNumberID == 7)
        #expect(await scenario.sentPhoneNumberIDs == [9, 7])

        _ = try authenticated(try await session.submitTwoFactorCode("445566"))
    }

    @Test("An unoffered SMS number is rejected before networking")
    func unknownSMSNumber() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil]
        )
        let session = makeSession(scenario: scenario)
        _ = try twoFactor(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )

        await #expect {
            try await session.requestSMSCode(phoneNumberID: 99)
        } throws: { error in
            (error as? SwiftDunkError)?.code == .trustedPhoneNumberNotFound(99)
        }
        #expect(await scenario.sendSMSCount == 0)

        _ = try twoFactor(try await session.resendTwoFactorCode())
        #expect(await scenario.trustedPushCount == 2)
    }

    @Test("The convenience login supports resend and switching in both directions")
    func accountConvenienceControls() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil]
        )
        let recorder = TwoFactorActionRecorder(
            responses: [
                .resendCode,
                .sendSMS(phoneNumberID: 7),
                .sendToTrustedDevices,
                .code("556677"),
            ]
        )

        _ = try await Account.login(
            appleID: "USER@EXAMPLE.COM",
            password: SRPVectors.passwordDerivation.password,
            anisette: anisette,
            transport: transport(for: scenario)
        ) { challenge in
            try await recorder.response(for: challenge)
        }

        #expect(
            await recorder.methods
                == [.trustedDevice, .trustedDevice, .sms, .trustedDevice]
        )
        #expect(await scenario.trustedPushCount == 3)
        #expect(await scenario.sendSMSCount == 1)
        #expect(await scenario.trustedValidationCount == 1)
    }

    @Test("Known Apple SMS delivery errors retain the trusted-device challenge")
    func knownSMSDeliveryErrors() async throws {
        for serviceCode in [-28_248, -22_979, -22_981] {
            let scenario = GrandSlamScenario(
                authenticationTypes: ["trustedDeviceSecondaryAuth", nil],
                smsDeliveryResponses: [try smsErrorResponse(code: serviceCode)]
            )
            let session = makeSession(scenario: scenario)
            _ = try twoFactor(
                try await session.begin(password: SRPVectors.passwordDerivation.password)
            )

            await #expect {
                try await session.requestSMSCode(phoneNumberID: 7)
            } throws: { error in
                (error as? SwiftDunkError)?.code
                    == .twoFactorDeliveryFailed(
                        TwoFactorDeliveryFailure(
                            serviceCode: serviceCode,
                            title: "Verification Failed",
                            message: "Choose another method."
                        )
                    )
            }

            let challenge = try twoFactor(try await session.resendTwoFactorCode())
            #expect(challenge.method == .trustedDevice)
            #expect(challenge.selectedPhoneNumberID == nil)
            #expect(await scenario.trustedPushCount == 2)
        }
    }

    @Test("Malformed SMS delivery errors are typed and leave recovery available")
    func malformedSMSDeliveryError() async throws {
        let malformed = HTTPResponse(
            statusCode: 400,
            body: Data(#"{"serviceErrors":[]}"#.utf8)
        )
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil],
            smsDeliveryResponses: [malformed]
        )
        let session = makeSession(scenario: scenario)
        _ = try twoFactor(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )

        await #expect {
            try await session.requestSMSCode(phoneNumberID: 7)
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .malformedResponse(
                    key: "serviceErrors",
                    expected: "a nonempty Apple two-factor service-error array"
                )
        }

        let challenge = try twoFactor(try await session.requestTrustedDeviceCode())
        #expect(challenge.method == .trustedDevice)
        #expect(await scenario.trustedPushCount == 2)
    }

    @Test("A failed trusted-device resend retains the challenge and clears the guard")
    func failedTrustedDeviceResend() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil],
            trustedDeliveryResponses: [
                HTTPResponse(statusCode: 200),
                HTTPResponse(statusCode: 503),
            ]
        )
        let session = makeSession(scenario: scenario)
        _ = try twoFactor(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )

        await #expect {
            try await session.resendTwoFactorCode()
        } throws: { error in
            (error as? SwiftDunkError)?.code == .unexpectedStatusCode(503)
        }

        let challenge = try twoFactor(try await session.requestSMSCode(phoneNumberID: 7))
        #expect(challenge.method == .sms)
        #expect(challenge.selectedPhoneNumberID == 7)
    }

    @Test("A failed SMS resend retains its selected number and clears the guard")
    func failedSMSResend() async throws {
        let failure = try smsErrorResponse(code: -22_979)
        let scenario = GrandSlamScenario(
            authenticationTypes: ["secondaryAuth", nil],
            smsDeliveryResponses: [HTTPResponse(statusCode: 200), failure]
        )
        let session = makeSession(scenario: scenario)
        _ = try twoFactor(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )

        await #expect {
            try await session.resendTwoFactorCode()
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .twoFactorDeliveryFailed(
                    TwoFactorDeliveryFailure(
                        serviceCode: -22_979,
                        title: "Verification Failed",
                        message: "Choose another method."
                    )
                )
        }

        _ = try authenticated(try await session.submitTwoFactorCode("667788"))
        #expect(await scenario.sentPhoneNumberIDs == [7, 7, 7])
    }

    @Test("A failed switch to trusted devices retains the SMS challenge")
    func failedSMSToTrustedDeviceSwitch() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["secondaryAuth", nil],
            trustedDeliveryResponses: [HTTPResponse(statusCode: 503)]
        )
        let session = makeSession(scenario: scenario)
        _ = try twoFactor(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )

        await #expect {
            try await session.requestTrustedDeviceCode()
        } throws: { error in
            (error as? SwiftDunkError)?.code == .unexpectedStatusCode(503)
        }

        let challenge = try twoFactor(try await session.resendTwoFactorCode())
        #expect(challenge.method == .sms)
        #expect(challenge.selectedPhoneNumberID == 7)
    }

    @Test("The convenience login re-presents delivery failures for recovery")
    func convenienceLoginDeliveryRecovery() async throws {
        let failure = try smsErrorResponse(code: -28_248)
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil],
            smsDeliveryResponses: [failure]
        )
        let recorder = TwoFactorActionRecorder(
            responses: [
                .sendSMS(phoneNumberID: 7),
                .sendToTrustedDevices,
                .code("778899"),
            ]
        )

        _ = try await Account.login(
            appleID: "USER@EXAMPLE.COM",
            password: SRPVectors.passwordDerivation.password,
            anisette: anisette,
            transport: transport(for: scenario)
        ) { challenge in
            try await recorder.response(for: challenge)
        }

        #expect(await recorder.methods == [.trustedDevice, .trustedDevice, .trustedDevice])
        #expect(
            await recorder.deliveryErrors
                == [
                    nil,
                    .twoFactorDeliveryFailed(
                        TwoFactorDeliveryFailure(
                            serviceCode: -28_248,
                            title: "Verification Failed",
                            message: "Choose another method."
                        )
                    ),
                    nil,
                ]
        )
        #expect(await scenario.trustedPushCount == 2)
        #expect(await scenario.trustedValidationCount == 1)
    }

    @Test("SMS delivery errors preserve optional fields and numeric codes")
    func smsDeliveryErrorFields() async throws {
        let cases: [(Int, Bool, String?, String?)] = [
            (-28_248, false, "Verification Failed", "Choose another method."),
            (-22_979, true, nil, "Enter the last code you received."),
            (-22_981, true, "Too Many Codes", nil),
            (-21_669, true, nil, nil),
        ]

        for (serviceCode, encodesCodeAsString, title, message) in cases {
            let response = try smsErrorResponse(
                code: serviceCode,
                encodesCodeAsString: encodesCodeAsString,
                title: title,
                message: message
            )
            let scenario = GrandSlamScenario(
                authenticationTypes: ["trustedDeviceSecondaryAuth", nil],
                smsDeliveryResponses: [response]
            )
            let session = makeSession(scenario: scenario)
            _ = try twoFactor(
                try await session.begin(password: SRPVectors.passwordDerivation.password)
            )

            await #expect {
                try await session.requestSMSCode(phoneNumberID: 7)
            } throws: { error in
                (error as? SwiftDunkError)?.code
                    == .twoFactorDeliveryFailed(
                        TwoFactorDeliveryFailure(
                            serviceCode: serviceCode,
                            title: title,
                            message: message
                        )
                    )
            }

            let challenge = try twoFactor(try await session.resendTwoFactorCode())
            #expect(challenge.method == .trustedDevice)
        }
    }

    @Test("An invalid SMS service code is malformed and leaves recovery available")
    func invalidSMSServiceCode() async throws {
        let body = try JSONSerialization.data(
            withJSONObject: [
                "serviceErrors": [
                    [
                        "code": "not-a-number",
                        "title": "Verification Failed",
                        "message": "Choose another method.",
                    ]
                ]
            ]
        )
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil],
            smsDeliveryResponses: [HTTPResponse(statusCode: 400, body: body)]
        )
        let session = makeSession(scenario: scenario)
        _ = try twoFactor(
            try await session.begin(password: SRPVectors.passwordDerivation.password)
        )

        await #expect {
            try await session.requestSMSCode(phoneNumberID: 7)
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .malformedResponse(
                    key: "serviceErrors",
                    expected: "a nonempty Apple two-factor service-error array"
                )
        }

        let challenge = try twoFactor(try await session.requestTrustedDeviceCode())
        #expect(challenge.method == .trustedDevice)
    }

    @Test("The convenience login normalizes custom transport delivery failures")
    func convenienceLoginCustomTransportRecovery() async throws {
        let scenario = GrandSlamScenario(
            authenticationTypes: ["trustedDeviceSecondaryAuth", nil]
        )
        let transport = OneShotSMSFailureTransport(scenario: scenario)
        let recorder = TwoFactorActionRecorder(
            responses: [
                .sendSMS(phoneNumberID: 7),
                .sendToTrustedDevices,
                .code("889900"),
            ]
        )

        _ = try await Account.login(
            appleID: "USER@EXAMPLE.COM",
            password: SRPVectors.passwordDerivation.password,
            anisette: anisette,
            transport: MockTransport { request in
                try await transport.send(request)
            }
        ) { challenge in
            try await recorder.response(for: challenge)
        }

        #expect(await recorder.deliveryErrors == [nil, .network, nil])
        #expect(await scenario.trustedPushCount == 2)
        #expect(await scenario.trustedValidationCount == 1)
    }

    private func trustedPhoneNumber(id: Int, suffix: String) -> TrustedPhoneNumber {
        TrustedPhoneNumber(
            id: id,
            numberWithDialCode: "+1 ••• ••• ••\(suffix)",
            lastTwoDigits: suffix,
            pushMode: "sms"
        )
    }

    private func smsErrorResponse(
        code: Int,
        encodesCodeAsString: Bool = true,
        title: String? = "Verification Failed",
        message: String? = "Choose another method."
    ) throws -> HTTPResponse {
        var serviceError: [String: Any] = [:]
        if encodesCodeAsString {
            serviceError["code"] = String(code)
        } else {
            serviceError["code"] = code
        }
        if let title {
            serviceError["title"] = title
        }
        if let message {
            serviceError["message"] = message
        }
        let body = try JSONSerialization.data(
            withJSONObject: [
                "serviceErrors": [serviceError]
            ]
        )
        return HTTPResponse(statusCode: 400, body: body)
    }
}
