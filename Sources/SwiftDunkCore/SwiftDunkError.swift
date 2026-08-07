public import Foundation

/// An error reported by SwiftDunk.
///
/// Inspect ``code`` to handle a failure programmatically. The remaining properties provide
/// diagnostic context and may be absent when it is not applicable.
public struct SwiftDunkError: Error, Sendable {
    /// The stable category and protocol-specific details of a SwiftDunk failure.
    public enum Code: Sendable, Equatable {
        /// A network operation failed before a usable HTTP response was received.
        case network

        /// A server returned an HTTP status code that the operation did not accept.
        case unexpectedStatusCode(Int)

        /// A response omitted a key or supplied a value of the wrong type.
        case malformedResponse(key: String, expected: String)

        /// GrandSlam selected an SRP password protocol that SwiftDunk does not implement.
        case unsupportedSRPProtocol(String)

        /// GrandSlam returned its `ec` error code and accompanying `em` message.
        case grandSlam(code: Int, message: String)

        /// Apple rejected an application-token request inside the decrypted response.
        case appTokenRejected(statusCode: Int)

        /// The GrandSlam server proof did not match the locally computed proof.
        case srpVerificationFailed

        /// Apple rejected a submitted two-factor authentication code.
        case invalidTwoFactorCode

        /// Apple rate-limited two-factor authentication attempts with HTTP status 423.
        case twoFactorRateLimited

        /// The selected phone-number identifier was not present in Apple's challenge.
        case trustedPhoneNumberNotFound(Int)

        /// Apple rejected delivery of a two-factor code with a service error.
        case twoFactorDeliveryFailed(TwoFactorDeliveryFailure)

        /// Apple requires an account step that SwiftDunk cannot complete automatically.
        case additionalStepRequired(String)

        /// Another operation that mutates the same resource is already running.
        case operationInProgress(String)

        /// Apple's Security framework returned a non-success status.
        case securityFramework(status: Int)

        /// The configured anisette service could not provide attestation headers.
        case anisetteUnavailable

        /// Anisette device provisioning failed.
        case anisetteProvisioningFailed(String)

        /// Anisette headers were rejected because their timestamp was outside Apple's window.
        case anisetteClockSkew

        /// The Developer Portal returned a nonzero result code.
        case developerAPI(resultCode: Int, httpCode: Int?, message: String)

        /// The account has no remaining certificate slots.
        case certificateLimitReached

        /// A requested certificate could not be found.
        case certificateNotFound

        /// A private key or certificate-signing request could not be generated.
        case keyGenerationFailed
    }

    /// The machine-readable category of the failure.
    public let code: Code

    /// The error that caused this failure, when one is available.
    public let underlyingError: (any Error)?

    /// The URL involved in the failure, when applicable.
    public let url: URL?

    /// A textual response body useful for diagnosis, when safe and available.
    ///
    /// Never place passwords, tokens, or other secrets in this field.
    public let responseBody: String?

    /// Creates an error with optional diagnostic context.
    public init(
        code: Code,
        underlyingError: (any Error)? = nil,
        url: URL? = nil,
        responseBody: String? = nil
    ) {
        self.code = code
        self.underlyingError = underlyingError
        self.url = url
        self.responseBody = responseBody
    }
}

extension SwiftDunkError: LocalizedError {
    /// A human-readable description of the failure.
    public var errorDescription: String? {
        switch code {
        case .network:
            "The network request failed."
        case .unexpectedStatusCode(let statusCode):
            "The server returned unexpected HTTP status \(statusCode)."
        case .malformedResponse(let key, let expected):
            "The response key '\(key)' was missing or was not \(expected)."
        case .unsupportedSRPProtocol(let protocolName):
            "The server selected unsupported SRP protocol '\(protocolName)'."
        case .grandSlam(let code, let message):
            "GrandSlam error \(code): \(message)"
        case .appTokenRejected(let statusCode):
            "Apple rejected the application-token request with status \(statusCode)."
        case .srpVerificationFailed:
            "The GrandSlam server proof could not be verified."
        case .invalidTwoFactorCode:
            "Apple rejected the two-factor authentication code."
        case .twoFactorRateLimited:
            "Apple temporarily rate-limited two-factor authentication attempts."
        case .trustedPhoneNumberNotFound(let identifier):
            "Apple did not offer trusted phone number identifier \(identifier)."
        case .twoFactorDeliveryFailed(let failure):
            twoFactorDeliveryDescription(failure)
        case .additionalStepRequired(let step):
            "Apple requires an additional account step: \(step)"
        case .operationInProgress(let operation):
            "Another \(operation) operation is already in progress."
        case .securityFramework(let status):
            "The Security framework operation failed with status \(status)."
        case .anisetteUnavailable:
            "Anisette headers are unavailable."
        case .anisetteProvisioningFailed(let message):
            "Anisette provisioning failed: \(message)"
        case .anisetteClockSkew:
            "Anisette headers were rejected because the clock is out of sync."
        case .developerAPI(let resultCode, let httpCode, let message):
            if let httpCode {
                "Developer Portal error \(resultCode) (HTTP \(httpCode)): \(message)"
            } else {
                "Developer Portal error \(resultCode): \(message)"
            }
        case .certificateLimitReached:
            "The account has no remaining certificate slots."
        case .certificateNotFound:
            "The requested certificate could not be found."
        case .keyGenerationFailed:
            "The private key or certificate-signing request could not be generated."
        }
    }

    private func twoFactorDeliveryDescription(_ failure: TwoFactorDeliveryFailure) -> String {
        let summary = [failure.title, failure.message]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ": ")
        let prefix = "Apple could not deliver the two-factor code (\(failure.serviceCode))"
        return summary.isEmpty ? "\(prefix)." : "\(prefix): \(summary)"
    }
}

package extension SwiftDunkError {
    static func securityFrameworkError(status: Int) -> SwiftDunkError {
        SwiftDunkError(
            code: .securityFramework(status: status),
            underlyingError: NSError(
                domain: NSOSStatusErrorDomain,
                code: status
            )
        )
    }
}
