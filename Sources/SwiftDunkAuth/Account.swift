public import Foundation

/// An authenticated Apple account and its GrandSlam session material.
public struct Account: Sendable {
    /// The normalized Apple ID used for authentication.
    public let appleID: String

    /// The account holder's first name, or an empty string when Apple omits it.
    public let firstName: String

    /// The account holder's last name, or an empty string when Apple omits it.
    public let lastName: String

    /// Apple's account identifier, serialized as `adsid` on the wire.
    public let dsid: String

    package let idmsToken: String
    package let sessionKey: Data
    package let context: Data
    package let anisette: any AnisetteProvider
    package let transport: any HTTPTransport

    package init(
        appleID: String,
        firstName: String,
        lastName: String,
        dsid: String,
        idmsToken: String,
        sessionKey: Data,
        context: Data,
        anisette: any AnisetteProvider,
        transport: any HTTPTransport
    ) {
        self.appleID = appleID
        self.firstName = firstName
        self.lastName = lastName
        self.dsid = dsid
        self.idmsToken = idmsToken
        self.sessionKey = sessionKey
        self.context = context
        self.anisette = anisette
        self.transport = transport
    }
}

public extension Account {
    /// Authenticates an Apple ID, invoking a callback whenever two-factor input is needed.
    ///
    /// The callback may submit the current code, resend it, or switch between trusted-device
    /// and SMS delivery. Passwords and session tokens are retained only in memory and are
    /// never logged by SwiftDunk.
    /// - Throws: ``SwiftDunkError`` for SRP, response, network, 2FA, or account-step
    ///   failures, or an error thrown by `onTwoFactor`.
    static func login(
        appleID: String,
        password: String,
        anisette: any AnisetteProvider,
        transport: any HTTPTransport = URLSessionTransport(),
        onTwoFactor: @Sendable (TwoFactorChallenge) async throws -> TwoFactorResponse
    ) async throws -> Account {
        let session = AuthenticationSession(
            appleID: appleID,
            anisette: anisette,
            transport: transport
        )
        var step = try await session.begin(password: password)

        while true {
            switch step {
            case .authenticated(let account):
                return account
            case .twoFactorRequired(let challenge):
                switch try await onTwoFactor(challenge) {
                case .code(let code):
                    step = try await session.submitTwoFactorCode(code)
                case .sendSMS(let phoneNumberID):
                    step = try await recoverDeliveryFailure(for: challenge) {
                        try await session.requestSMSCode(phoneNumberID: phoneNumberID)
                    }
                case .sendToTrustedDevices:
                    step = try await recoverDeliveryFailure(for: challenge) {
                        try await session.requestTrustedDeviceCode()
                    }
                case .resendCode:
                    step = try await recoverDeliveryFailure(for: challenge) {
                        try await session.resendTwoFactorCode()
                    }
                }
            }
        }
    }
}

private func recoverDeliveryFailure(
    for challenge: TwoFactorChallenge,
    operation: () async throws -> LoginStep
) async throws -> LoginStep {
    do {
        return try await operation()
    } catch {
        try Task.checkCancellation()
        if error is CancellationError {
            throw error
        }
        let code = (error as? SwiftDunkError)?.code ?? .network
        return .twoFactorRequired(
            TwoFactorChallenge(
                method: challenge.method,
                trustedPhoneNumbers: challenge.trustedPhoneNumbers,
                selectedPhoneNumberID: challenge.selectedPhoneNumberID,
                previousDeliveryError: code
            )
        )
    }
}
