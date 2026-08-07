public import SwiftDunkCore

/// The channel Apple uses to deliver a two-factor authentication code.
public enum TwoFactorMethod: Sendable, Equatable {
    /// A code displayed on the account's trusted Apple devices.
    case trustedDevice

    /// A code delivered to a trusted phone number by SMS.
    case sms
}

/// A trusted phone number returned by Apple's authentication service.
public struct TrustedPhoneNumber: Sendable, Equatable, Codable {
    /// Apple's identifier for selecting this phone number.
    public let id: Int

    /// The masked or formatted number including its dialing code.
    public let numberWithDialCode: String

    /// The last two visible digits.
    public let lastTwoDigits: String

    /// Apple's delivery-mode description.
    public let pushMode: String

    /// Creates a trusted-phone-number value.
    public init(
        id: Int,
        numberWithDialCode: String,
        lastTwoDigits: String,
        pushMode: String
    ) {
        self.id = id
        self.numberWithDialCode = numberWithDialCode
        self.lastTwoDigits = lastTwoDigits
        self.pushMode = pushMode
    }
}

/// A paused login that requires user interaction.
public struct TwoFactorChallenge: Sendable, Equatable {
    /// The channel on which Apple delivered or will deliver the code.
    public let method: TwoFactorMethod

    /// Phone numbers available for SMS delivery or fallback.
    public let trustedPhoneNumbers: [TrustedPhoneNumber]

    /// The phone number currently receiving SMS codes, or `nil` for trusted-device
    /// delivery.
    public let selectedPhoneNumberID: Int?

    /// The error from the most recent delivery request, or `nil` before delivery fails.
    ///
    /// The convenience login API supplies the same challenge again with this value set,
    /// allowing the caller to choose another method without restarting authentication.
    public let previousDeliveryError: SwiftDunkError.Code?

    /// Creates a two-factor challenge.
    public init(
        method: TwoFactorMethod,
        trustedPhoneNumbers: [TrustedPhoneNumber],
        selectedPhoneNumberID: Int? = nil,
        previousDeliveryError: SwiftDunkError.Code? = nil
    ) {
        self.method = method
        self.trustedPhoneNumbers = trustedPhoneNumbers
        self.selectedPhoneNumberID = selectedPhoneNumberID
        self.previousDeliveryError = previousDeliveryError
    }
}

/// The result of advancing an ``AuthenticationSession``.
public enum LoginStep: Sendable {
    /// Authentication completed successfully.
    case authenticated(Account)

    /// Login paused until the caller supplies a two-factor response.
    case twoFactorRequired(TwoFactorChallenge)
}

/// A response supplied by an interactive login callback.
public enum TwoFactorResponse: Sendable, Equatable {
    /// Submit a code received through the challenge's current channel.
    case code(String)

    /// Switch to SMS and send a code to the selected trusted phone number.
    case sendSMS(phoneNumberID: Int)

    /// Switch to trusted-device delivery and send a new code.
    case sendToTrustedDevices

    /// Send a new code through the challenge's current delivery method.
    case resendCode
}
