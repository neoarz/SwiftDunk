public import SwiftDunkPortal

/// The caller's explicit response when Apple reports that no certificate slots remain.
public enum CertificateLimitAction: Sendable {
    /// Stop without revoking any certificate.
    case cancel

    /// Revoke exactly the named certificate serial numbers and retry once.
    ///
    /// Revocation invalidates provisioning that depends on those certificates and can
    /// break other people's installed applications. Present the certificate list and
    /// obtain informed confirmation before returning this action.
    case revoke(serialNumbers: [String])
}

/// The certificates available when Apple reports that no certificate slots remain.
///
/// This value is passed to the certificate-limit callback and attached to a
/// ``SwiftDunkError/Code/certificateLimitReached`` failure when the caller cancels.
public struct CertificateLimitDetails: Error, Sendable {
    /// The complete certificate list observed before the failed request.
    public let certificates: [Certificate]

    /// Creates certificate-limit details.
    public init(certificates: [Certificate]) {
        self.certificates = certificates
    }
}
