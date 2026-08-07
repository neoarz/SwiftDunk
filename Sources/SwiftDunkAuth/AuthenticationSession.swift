package import Foundation

/// A resumable GrandSlam login and two-factor authentication state machine.
///
/// The actor keeps mutable login material isolated from callers. A failed network or
/// parsing operation leaves a state that can be retried with `begin(password:)` and,
/// after accepted 2FA, by calling `submitTwoFactorCode(_:)` again to retry the SRP round.
public actor AuthenticationSession {
    private let appleID: String
    private let anisette: any AnisetteProvider
    private let transport: any HTTPTransport
    private let loginClient: GSALoginClient
    private let twoFactorClient: TwoFactorClient

    private var state: State = .idle
    private var operationIsInProgress = false

    /// Creates an authentication session.
    public init(
        appleID: String,
        anisette: any AnisetteProvider,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.appleID = appleID.lowercased()
        self.anisette = anisette
        self.transport = transport
        loginClient = GSALoginClient(
            anisette: anisette,
            transport: transport,
            privateKey: AuthRandom.privateKey
        )
        twoFactorClient = TwoFactorClient(anisette: anisette, transport: transport)
    }

    package init(
        appleID: String,
        anisette: any AnisetteProvider,
        transport: any HTTPTransport,
        privateKey: @escaping @Sendable () throws -> Data
    ) {
        self.appleID = appleID.lowercased()
        self.anisette = anisette
        self.transport = transport
        loginClient = GSALoginClient(
            anisette: anisette,
            transport: transport,
            privateKey: privateKey
        )
        twoFactorClient = TwoFactorClient(anisette: anisette, transport: transport)
    }

    /// Starts a full SRP login.
    ///
    /// Calling this method again deliberately abandons any earlier challenge and starts
    /// over. The password remains only in actor-isolated memory while 2FA is pending.
    /// - Throws: ``SwiftDunkError`` for transport, protocol, SRP, account-step, or
    ///   concurrent-operation failures.
    public func begin(password: String) async throws -> LoginStep {
        try beginExclusiveOperation()
        defer { endExclusiveOperation() }

        state = .idle
        let credentials = Credentials(password: password)
        let result = try await loginClient.login(appleID: appleID, password: password)
        return try await handle(result, credentials: credentials)
    }

    /// Submits a code for the current challenge.
    ///
    /// The code is transmitted verbatim, including leading zeroes.
    ///
    /// After Apple accepts the code, SwiftDunk reruns the full SRP exchange. If that
    /// rerun fails, calling this method again retries the SRP exchange without
    /// re-submitting the already accepted code.
    /// - Throws: ``SwiftDunkError/Code/invalidTwoFactorCode``,
    ///   ``SwiftDunkError/Code/twoFactorRateLimited``,
    ///   ``SwiftDunkError/Code/operationInProgress(_:)``, or another authentication error.
    public func submitTwoFactorCode(_ code: String) async throws -> LoginStep {
        try beginExclusiveOperation()
        defer { endExclusiveOperation() }

        switch state {
        case .awaitingTrustedCode(let pending):
            try await twoFactorClient.verifyTrustedDeviceCode(
                code,
                material: pending.material
            )
            state = .needsLogin(pending.credentials)
            return try await retryLogin(credentials: pending.credentials)

        case .awaitingSMSCode(let pending):
            try await twoFactorClient.verifySMSCode(
                code,
                phoneNumberID: pending.phoneNumberID,
                material: pending.material
            )
            state = .needsLogin(pending.credentials)
            return try await retryLogin(credentials: pending.credentials)

        // the code worked, only the srp retry failed
        case .needsLogin(let credentials):
            return try await retryLogin(credentials: credentials)

        case .idle:
            throw invalidTransition("No two-factor challenge is active.")
        }
    }

    /// Requests SMS delivery to a trusted phone number.
    ///
    /// This may be called from either a trusted-device prompt or an SMS prompt to select
    /// another number.
    /// - Throws: ``SwiftDunkError`` if no challenge is active, delivery fails, or another
    ///   authentication operation is already running.
    public func requestSMSCode(phoneNumberID: Int) async throws -> LoginStep {
        try beginExclusiveOperation()
        defer { endExclusiveOperation() }

        let pending: PendingChallenge
        let currentPhoneNumberID: Int?
        switch state {
        case .awaitingTrustedCode(let value):
            pending = value
            currentPhoneNumberID = nil
        case .awaitingSMSCode(let value):
            pending = value.challenge
            currentPhoneNumberID = value.phoneNumberID
        case .idle, .needsLogin:
            throw invalidTransition("No two-factor challenge can switch to SMS.")
        }

        guard
            currentPhoneNumberID == phoneNumberID
                || pending.phoneNumbers.contains(where: { $0.id == phoneNumberID })
        else {
            throw SwiftDunkError(code: .trustedPhoneNumberNotFound(phoneNumberID))
        }

        try await twoFactorClient.sendSMS(
            phoneNumberID: phoneNumberID,
            material: pending.material
        )
        let smsChallenge = SMSChallenge(challenge: pending, phoneNumberID: phoneNumberID)
        state = .awaitingSMSCode(smsChallenge)
        return smsStep(for: smsChallenge)
    }

    /// Requests a new code from Apple's trusted-device channel.
    ///
    /// Apple broadcasts this request to the account's trusted devices; individual devices
    /// cannot be selected. This may be called from either an SMS or trusted-device prompt.
    /// - Throws: ``SwiftDunkError`` if no challenge is active, delivery fails, or another
    ///   authentication operation is already running.
    public func requestTrustedDeviceCode() async throws -> LoginStep {
        try beginExclusiveOperation()
        defer { endExclusiveOperation() }

        let pending = try activeChallenge()
        try await twoFactorClient.sendTrustedDevicePush(material: pending.material)
        state = .awaitingTrustedCode(pending)
        return trustedDeviceStep(for: pending)
    }

    /// Resends a code through the active challenge's current delivery method.
    ///
    /// Trusted-device challenges are broadcast again. SMS challenges reuse the selected
    /// phone number.
    /// - Throws: ``SwiftDunkError`` if no challenge is active, delivery fails, or another
    ///   authentication operation is already running.
    public func resendTwoFactorCode() async throws -> LoginStep {
        try beginExclusiveOperation()
        defer { endExclusiveOperation() }

        switch state {
        case .awaitingTrustedCode(let pending):
            try await twoFactorClient.sendTrustedDevicePush(material: pending.material)
            return trustedDeviceStep(for: pending)

        case .awaitingSMSCode(let pending):
            try await twoFactorClient.sendSMS(
                phoneNumberID: pending.phoneNumberID,
                material: pending.material
            )
            return smsStep(for: pending)

        case .idle, .needsLogin:
            throw invalidTransition("No two-factor challenge can be resent.")
        }
    }

    private func retryLogin(credentials: Credentials) async throws -> LoginStep {
        let result = try await loginClient.login(
            appleID: appleID,
            password: credentials.password
        )
        return try await handle(result, credentials: credentials)
    }

    private func handle(
        _ result: GSALoginResult,
        credentials: Credentials
    ) async throws -> LoginStep {
        switch result.authenticationType {
        case nil:
            state = .idle
            return .authenticated(
                result.material.account(anisette: anisette, transport: transport)
            )

        case AuthConstants.AuthType.trustedDevice:
            try await twoFactorClient.sendTrustedDevicePush(material: result.material)
            let phoneNumbers =
                (try? await twoFactorClient.trustedPhoneNumbers(material: result.material).numbers)
                ?? []
            let pending = PendingChallenge(
                credentials: credentials,
                material: result.material,
                phoneNumbers: phoneNumbers
            )
            state = .awaitingTrustedCode(pending)
            return trustedDeviceStep(for: pending)

        case AuthConstants.AuthType.sms:
            let extras =
                try? await twoFactorClient.trustedPhoneNumbers(material: result.material)
            let phoneNumbers = extras?.numbers ?? []
            let phoneNumberID = phoneNumbers.first?.id ?? 1
            if extras?.smsAlreadyPending != true {
                try await twoFactorClient.sendSMS(
                    phoneNumberID: phoneNumberID,
                    material: result.material
                )
            }
            let pending = PendingChallenge(
                credentials: credentials,
                material: result.material,
                phoneNumbers: phoneNumbers
            )
            let smsChallenge = SMSChallenge(challenge: pending, phoneNumberID: phoneNumberID)
            state = .awaitingSMSCode(smsChallenge)
            return smsStep(for: smsChallenge)

        case .some(let authenticationType):
            state = .idle
            if result.material.hasPersonalToken {
                return .authenticated(
                    result.material.account(anisette: anisette, transport: transport)
                )
            }
            throw SwiftDunkError(code: .additionalStepRequired(authenticationType))
        }
    }

    private func invalidTransition(_ message: String) -> SwiftDunkError {
        SwiftDunkError(
            code: .malformedResponse(key: "authentication state", expected: message)
        )
    }

    private func activeChallenge() throws -> PendingChallenge {
        switch state {
        case .awaitingTrustedCode(let pending):
            pending
        case .awaitingSMSCode(let pending):
            pending.challenge
        case .idle, .needsLogin:
            throw invalidTransition("No two-factor challenge is active.")
        }
    }

    private func trustedDeviceStep(for pending: PendingChallenge) -> LoginStep {
        .twoFactorRequired(
            TwoFactorChallenge(
                method: .trustedDevice,
                trustedPhoneNumbers: pending.phoneNumbers
            )
        )
    }

    private func smsStep(for pending: SMSChallenge) -> LoginStep {
        .twoFactorRequired(
            TwoFactorChallenge(
                method: .sms,
                trustedPhoneNumbers: pending.challenge.phoneNumbers,
                selectedPhoneNumberID: pending.phoneNumberID
            )
        )
    }

    // actor isolation does not stop reentrancy during network calls
    private func beginExclusiveOperation() throws {
        guard !operationIsInProgress else {
            throw SwiftDunkError(code: .operationInProgress("authentication"))
        }
        operationIsInProgress = true
    }

    private func endExclusiveOperation() {
        operationIsInProgress = false
    }
}

private extension AuthenticationSession {
    struct Credentials: Sendable {
        let password: String
    }

    struct PendingChallenge: Sendable {
        let credentials: Credentials
        let material: AccountMaterial
        let phoneNumbers: [TrustedPhoneNumber]
    }

    struct SMSChallenge: Sendable {
        let challenge: PendingChallenge
        let phoneNumberID: Int

        var credentials: Credentials { challenge.credentials }
        var material: AccountMaterial { challenge.material }
    }

    enum State: Sendable {
        case idle
        case awaitingTrustedCode(PendingChallenge)
        case awaitingSMSCode(SMSChallenge)
        case needsLogin(Credentials)
    }
}
