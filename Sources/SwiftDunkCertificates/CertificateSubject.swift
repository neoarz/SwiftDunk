import X509

/// The distinguished-name fields embedded in generated certificate requests.
public struct CertificateSubject: Sendable {
    /// The two-letter country code.
    public let countryCode: String

    /// The organization name.
    public let organization: String

    /// The organizational-unit name.
    public let organizationalUnit: String

    /// The common name.
    public let commonName: String

    /// Creates a certificate-request subject.
    public init(
        countryCode: String = "US",
        organization: String = "SwiftDunk",
        organizationalUnit: String = "Development",
        commonName: String = "SwiftDunk Development"
    ) {
        self.countryCode = countryCode
        self.organization = organization
        self.organizationalUnit = organizationalUnit
        self.commonName = commonName
    }

    func distinguishedName() throws -> DistinguishedName {
        try DistinguishedName {
            CountryName(countryCode)
            OrganizationName(organization)
            OrganizationalUnitName(organizationalUnit)
            CommonName(commonName)
        }
    }
}
