/// Details Apple returned when it could not deliver a two-factor authentication code.
public struct TwoFactorDeliveryFailure: Sendable, Equatable {
    /// Apple's numeric service-error code.
    public let serviceCode: Int

    /// Apple's short description of the failure, when supplied.
    public let title: String?

    /// Apple's explanation or recovery guidance, when supplied.
    public let message: String?

    /// Creates a two-factor delivery failure.
    public init(serviceCode: Int, title: String? = nil, message: String? = nil) {
        self.serviceCode = serviceCode
        self.title = title
        self.message = message
    }
}
