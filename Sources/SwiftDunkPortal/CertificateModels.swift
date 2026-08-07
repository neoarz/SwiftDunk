public import Foundation

/// A development certificate registered with an Apple Developer Program team.
public struct Certificate: Sendable, Identifiable, Codable {
    /// A strongly typed Developer Portal certificate identifier.
    public struct ID: Hashable, Sendable, Codable, RawRepresentable {
        /// The wire-format `certificateId` value.
        public let rawValue: String

        /// Creates a certificate identifier from its wire value.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// Apple's internal certificate identifier.
    public let id: ID

    /// The certificate's display name.
    public let name: String?

    /// The certificate's hexadecimal serial number.
    public let serialNumber: String

    /// Apple's current certificate status.
    public let status: String?

    /// Apple's numeric certificate status.
    public let statusCode: Int?

    /// The certificate expiration date.
    public let expirationDate: Date

    /// The certificate's Apple platform, when supplied.
    public let platform: String?

    /// Certificate-type metadata. Decoding also accepts `certificateType`; encoding uses `certType`.
    public let type: CertificateType?

    /// The DER-encoded X.509 certificate, when supplied.
    public let content: Data?

    /// The machine identifier used when requesting the certificate.
    public let machineID: String?

    /// The machine name used when requesting the certificate.
    public let machineName: String?

    enum CodingKeys: String, CodingKey {
        case id = "certificateId"
        case name
        case serialNumber
        case status
        case statusCode
        case expirationDate
        case platform = "certificatePlatform"
        case type = "certType"
        case content = "certContent"
        case machineID = "machineId"
        case machineName
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case type = "certificateType"
    }

    /// Creates a certificate value.
    public init(
        id: ID,
        name: String? = nil,
        serialNumber: String,
        status: String? = nil,
        statusCode: Int? = nil,
        expirationDate: Date,
        platform: String? = nil,
        type: CertificateType? = nil,
        content: Data? = nil,
        machineID: String? = nil,
        machineName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.serialNumber = serialNumber
        self.status = status
        self.statusCode = statusCode
        self.expirationDate = expirationDate
        self.platform = platform
        self.type = type
        self.content = content
        self.machineID = machineID
        self.machineName = machineName
    }

    /// Decodes a certificate while accepting either metadata key used by Apple.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        serialNumber = try container.decode(String.self, forKey: .serialNumber)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        statusCode = try container.decodeIfPresent(Int.self, forKey: .statusCode)
        expirationDate = try container.decode(Date.self, forKey: .expirationDate)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        if container.contains(.type) {
            type = try container.decodeIfPresent(CertificateType.self, forKey: .type)
        } else {
            let alternate = try decoder.container(keyedBy: AlternateCodingKeys.self)
            type = try alternate.decodeIfPresent(CertificateType.self, forKey: .type)
        }
        content = try container.decodeIfPresent(Data.self, forKey: .content)
        machineID = try container.decodeIfPresent(String.self, forKey: .machineID)
        machineName = try container.decodeIfPresent(String.self, forKey: .machineName)
    }
}

/// Metadata describing an Apple certificate type.
///
/// Decoding accepts `maxActive` and `maxActiveCerts`; encoding uses `maxActive`.
public struct CertificateType: Codable, Sendable {
    /// Apple's certificate-type display identifier.
    public let displayID: String?

    /// The certificate type's display name.
    public let name: String?

    /// The supported platform.
    public let platform: String?

    /// The permission category associated with the type.
    public let permissionType: String?

    /// Apple's distribution type, reported separately from `distributionMethod`.
    public let distributionType: String?

    /// The certificate's distribution method.
    public let distributionMethod: String?

    /// The owner category for issued certificates.
    public let ownerType: String?

    /// The number of overlap days Apple allows during renewal.
    public let overlapDays: Int?

    /// Apple's limit for active certificates of this type.
    public let maximumActive: Int?

    enum CodingKeys: String, CodingKey {
        case displayID = "certificateTypeDisplayId"
        case name
        case platform
        case permissionType
        case distributionType
        case distributionMethod
        case ownerType
        case overlapDays = "daysOverlap"
        case maximumActive = "maxActive"
    }

    private enum AlternateCodingKeys: String, CodingKey {
        case maximumActive = "maxActiveCerts"
    }

    /// Creates certificate-type metadata.
    public init(
        displayID: String? = nil,
        name: String? = nil,
        platform: String? = nil,
        permissionType: String? = nil,
        distributionType: String? = nil,
        distributionMethod: String? = nil,
        ownerType: String? = nil,
        overlapDays: Int? = nil,
        maximumActive: Int? = nil
    ) {
        self.displayID = displayID
        self.name = name
        self.platform = platform
        self.permissionType = permissionType
        self.distributionType = distributionType
        self.distributionMethod = distributionMethod
        self.ownerType = ownerType
        self.overlapDays = overlapDays
        self.maximumActive = maximumActive
    }

    /// Decodes certificate-type metadata while accepting either maximum-count key.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayID = try container.decodeIfPresent(String.self, forKey: .displayID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        permissionType = try container.decodeIfPresent(String.self, forKey: .permissionType)
        distributionType = try container.decodeIfPresent(String.self, forKey: .distributionType)
        distributionMethod = try container.decodeIfPresent(String.self, forKey: .distributionMethod)
        ownerType = try container.decodeIfPresent(String.self, forKey: .ownerType)
        overlapDays = try container.decodeIfPresent(Int.self, forKey: .overlapDays)
        if container.contains(.maximumActive) {
            maximumActive = try container.decodeIfPresent(Int.self, forKey: .maximumActive)
        } else {
            let alternate = try decoder.container(keyedBy: AlternateCodingKeys.self)
            maximumActive = try alternate.decodeIfPresent(Int.self, forKey: .maximumActive)
        }
    }
}

/// The result of submitting a PKCS#10 certificate-signing request.
public struct CertificateRequest: Codable, Sendable {
    /// Apple's certificate-request identifier.
    public let id: String?

    /// The identifier of the issued certificate.
    public let certificateID: Certificate.ID

    /// The issued certificate's hexadecimal serial number.
    public let serialNumber: String

    /// The machine identifier Apple associated with the request.
    public let machineID: String?

    /// The machine name Apple associated with the request.
    public let machineName: String?

    /// Certificate-type metadata returned with the request.
    public let certificateType: CertificateType?

    /// Apple's textual request status.
    public let status: String?

    /// The date Apple received the request.
    public let requestedAt: Date?

    /// The date Apple created the request record.
    public let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "certRequestId"
        case certificateID = "certificateId"
        case serialNumber = "serialNum"
        case machineID = "machineId"
        case machineName
        case certificateType
        case status = "statusString"
        case requestedAt = "dateRequested"
        case createdAt = "dateCreated"
    }

    /// Creates a certificate-request result.
    public init(
        id: String? = nil,
        certificateID: Certificate.ID,
        serialNumber: String,
        machineID: String? = nil,
        machineName: String? = nil,
        certificateType: CertificateType? = nil,
        status: String? = nil,
        requestedAt: Date? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.certificateID = certificateID
        self.serialNumber = serialNumber
        self.machineID = machineID
        self.machineName = machineName
        self.certificateType = certificateType
        self.status = status
        self.requestedAt = requestedAt
        self.createdAt = createdAt
    }
}

/// A provisioning profile returned by Apple's QH Developer Portal API.
public struct ProvisioningProfile: Sendable, Identifiable, Codable {
    /// A strongly typed provisioning-profile identifier.
    public struct ID: Hashable, Sendable, Codable, RawRepresentable {
        /// The wire-format `provisioningProfileId` value.
        public let rawValue: String

        /// Creates a provisioning-profile identifier from its wire value.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// Apple's internal provisioning-profile identifier.
    public let id: ID

    /// The profile UUID.
    public let uuid: String

    /// The suggested profile filename.
    public let filename: String

    /// The encoded CMS provisioning profile.
    public let data: Data

    /// The profile expiration date.
    public let expirationDate: Date

    /// The App ID associated with the profile.
    public let appID: AppID.ID?

    /// Whether Apple identifies this as a free-provisioning profile.
    public let isFreeProvisioningProfile: Bool

    /// The profile's display name.
    public let name: String?

    /// Apple's current profile status.
    public let status: String?

    /// Apple's display label for the profile type, such as `iOS Development`.
    public let type: String?

    /// Apple's distribution method, such as `limited`, `store`, or `adhoc`.
    public let distributionMethod: String?

    /// The platform Apple associates with the profile in the Portal response.
    public let platform: String?

    /// The application Apple reports as managing the profile, such as `Xcode`.
    public let managingApp: String?

    /// Whether Apple reports that the profile uses a provisioning template.
    public let isTemplateProfile: Bool?

    /// Whether Apple reports that the profile is a team provisioning profile.
    public let isTeamProfile: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "provisioningProfileId"
        case uuid = "UUID"
        case filename
        case data = "encodedProfile"
        case expirationDate = "dateExpire"
        case appID = "appIdId"
        case isFreeProvisioningProfile
        case name
        case status
        case type
        case distributionMethod
        case platform = "proProPlatform"
        case managingApp
        case isTemplateProfile
        case isTeamProfile
    }

    /// Creates a provisioning-profile value.
    public init(
        id: ID,
        uuid: String,
        filename: String,
        data: Data,
        expirationDate: Date,
        appID: AppID.ID? = nil,
        isFreeProvisioningProfile: Bool = false,
        name: String? = nil,
        status: String? = nil,
        type: String? = nil,
        distributionMethod: String? = nil,
        platform: String? = nil,
        managingApp: String? = nil,
        isTemplateProfile: Bool? = nil,
        isTeamProfile: Bool? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.filename = filename
        self.data = data
        self.expirationDate = expirationDate
        self.appID = appID
        self.isFreeProvisioningProfile = isFreeProvisioningProfile
        self.name = name
        self.status = status
        self.type = type
        self.distributionMethod = distributionMethod
        self.platform = platform
        self.managingApp = managingApp
        self.isTemplateProfile = isTemplateProfile
        self.isTeamProfile = isTeamProfile
    }

    /// Decodes a profile while tolerating an omitted free-provisioning flag.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ID.self, forKey: .id)
        uuid = try container.decode(String.self, forKey: .uuid)
        filename = try container.decode(String.self, forKey: .filename)
        data = try container.decode(Data.self, forKey: .data)
        expirationDate = try container.decode(Date.self, forKey: .expirationDate)
        appID = try container.decodeIfPresent(AppID.ID.self, forKey: .appID)
        isFreeProvisioningProfile =
            try container.decodeIfPresent(Bool.self, forKey: .isFreeProvisioningProfile) ?? false
        name = try container.decodeIfPresent(String.self, forKey: .name)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        distributionMethod = try container.decodeIfPresent(String.self, forKey: .distributionMethod)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        managingApp = try container.decodeIfPresent(String.self, forKey: .managingApp)
        isTemplateProfile = try container.decodeIfPresent(Bool.self, forKey: .isTemplateProfile)
        isTeamProfile = try container.decodeIfPresent(Bool.self, forKey: .isTeamProfile)
    }
}
