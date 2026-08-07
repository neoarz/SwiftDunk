public import _CryptoExtras
public import Foundation
#if os(macOS)
    import CSwiftDunkSecurity
#endif
import Security
import SwiftDunkCore
public import X509

/// A matched Apple development certificate and RSA private key.
public struct CertificateIdentity: Sendable {
    /// The parsed X.509 certificate returned by Apple.
    public let certificate: X509.Certificate

    /// The RSA private key corresponding to ``certificate``.
    public let privateKey: _RSA.Signing.PrivateKey

    /// The certificate's hexadecimal serial number.
    public let serialNumber: String

    /// Apple's machine identifier associated with the certificate.
    public let machineID: String?

    /// Whether this identity's certificate was minted during the current manager call.
    public let isNewlyCreated: Bool

    private let encodedCertificate: Data

    /// The certificate's DER representation.
    public var certificateDER: Data {
        encodedCertificate
    }

    /// The private key's PKCS#8 PEM representation.
    public var privateKeyPEM: String {
        privateKey.pkcs8PEMRepresentation
    }

    init(
        certificate: X509.Certificate,
        certificateDER: Data,
        privateKey: _RSA.Signing.PrivateKey,
        serialNumber: String,
        machineID: String?,
        isNewlyCreated: Bool
    ) {
        self.certificate = certificate
        encodedCertificate = certificateDER
        self.privateKey = privateKey
        self.serialNumber = serialNumber
        self.machineID = machineID
        self.isNewlyCreated = isNewlyCreated
    }

    #if os(macOS)
        /// Exports this identity as a password-protected PKCS#12 archive.
        ///
        /// PKCS#12 creation is unavailable on iOS. The private key and certificate are
        /// always available separately through ``privateKeyPEM`` and ``certificateDER``.
        /// SwiftDunk uses the archive password only for the returned data and never
        /// persists it.
        /// - Throws: ``SwiftDunkError`` if either item cannot be represented or exported.
        @available(macOS 14, *)
        public func exportPKCS12(password: String) throws -> Data {
            let keychainPassword = UUID().uuidString
            let keychainURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "SwiftDunk-\(UUID().uuidString).keychain-db",
                    isDirectory: false
                )
            var opaqueKeychain: UnsafeMutableRawPointer?
            let createStatus = keychainURL.path.withCString { path in
                keychainPassword.withCString { passwordBytes in
                    swiftdunk_temporary_keychain_create(
                        path,
                        UInt32(keychainPassword.utf8.count),
                        passwordBytes,
                        &opaqueKeychain
                    )
                }
            }
            guard createStatus == errSecSuccess else {
                throw SwiftDunkError.securityFrameworkError(status: Int(createStatus))
            }
            guard let opaqueKeychain else {
                throw SwiftDunkError(
                    code: .malformedResponse(
                        key: "temporary Keychain",
                        expected: "a created Keychain reference"
                    )
                )
            }
            let keychain = Unmanaged<SecKeychain>.fromOpaque(opaqueKeychain)
                .takeRetainedValue()
            var keychainWasDeleted = false
            defer {
                if !keychainWasDeleted {
                    _ = swiftdunk_temporary_keychain_delete(
                        Unmanaged.passUnretained(keychain).toOpaque()
                    )
                }
            }

            var inputFormat = SecExternalFormat.formatOpenSSL
            var inputType = SecExternalItemType.itemTypePrivateKey
            var importedItems: CFArray?
            let importStatus = SecItemImport(
                privateKey.derRepresentation as CFData,
                nil,
                &inputFormat,
                &inputType,
                [],
                nil,
                keychain,
                &importedItems
            )
            guard importStatus == errSecSuccess else {
                throw SwiftDunkError.securityFrameworkError(status: Int(importStatus))
            }
            guard
                let importedItems,
                !(importedItems as [AnyObject]).isEmpty
            else {
                throw SwiftDunkError(
                    code: .malformedResponse(
                        key: "imported private key",
                        expected: "at least one Security framework item"
                    )
                )
            }
            guard
                let securityCertificate = SecCertificateCreateWithData(
                    nil,
                    certificateDER as CFData
                )
            else {
                throw SwiftDunkError(
                    code: .malformedResponse(
                        key: "certificateDER",
                        expected: "a Security framework certificate"
                    )
                )
            }

            let certificateStatus = SecCertificateAddToKeychain(
                securityCertificate,
                keychain
            )
            guard certificateStatus == errSecSuccess else {
                throw SwiftDunkError.securityFrameworkError(
                    status: Int(certificateStatus)
                )
            }

            var securityIdentity: SecIdentity?
            let identityStatus = SecIdentityCreateWithCertificate(
                keychain,
                securityCertificate,
                &securityIdentity
            )
            guard identityStatus == errSecSuccess else {
                throw SwiftDunkError.securityFrameworkError(status: Int(identityStatus))
            }
            guard let securityIdentity else {
                throw SwiftDunkError(
                    code: .malformedResponse(
                        key: "Security identity",
                        expected: "a certificate and matching private key"
                    )
                )
            }
            var parameters = SecItemImportExportKeyParameters()
            parameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
            let passphrase = password as CFString
            parameters.passphrase = Unmanaged.passUnretained(passphrase)
            var exported: CFData?
            let status = SecItemExport(
                securityIdentity,
                .formatPKCS12,
                [],
                &parameters,
                &exported
            )
            guard status == errSecSuccess else {
                throw SwiftDunkError.securityFrameworkError(status: Int(status))
            }
            guard let exported else {
                throw SwiftDunkError(
                    code: .malformedResponse(
                        key: "PKCS#12 export",
                        expected: "exported archive data"
                    )
                )
            }
            let deleteStatus = swiftdunk_temporary_keychain_delete(
                Unmanaged.passUnretained(keychain).toOpaque()
            )
            guard deleteStatus == errSecSuccess else {
                throw SwiftDunkError.securityFrameworkError(status: Int(deleteStatus))
            }
            keychainWasDeleted = true
            return exported as Data
        }
    #endif
}
