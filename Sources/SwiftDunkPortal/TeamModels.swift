public import Foundation

/// An Apple Developer Program team available to the authenticated account.
public struct Team: Sendable, Identifiable, Codable {
    /// A strongly typed Developer Portal team identifier.
    public struct ID: Hashable, Sendable, Codable, RawRepresentable {
        /// The wire-format `teamId` value.
        public let rawValue: String

        /// Creates a team identifier from its wire value.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// The team's stable identifier.
    public let id: ID

    /// The team's display name.
    public let name: String

    /// Apple's current team status, when supplied.
    public let status: String?

    /// Apple's team membership type, when supplied.
    public let type: String?

    /// Whether Apple identifies this as an Xcode free-provisioning team.
    public let isXcodeFreeOnly: Bool

    /// Program memberships attached to the team.
    public let memberships: [TeamMembership]

    /// The authenticated person's membership in this team, when supplied.
    public let currentMember: TeamMember?

    /// Permissions Apple grants to Developer-role members.
    public let provisioningSettings: TeamProvisioningSettings?

    /// The date Apple created the team, when supplied.
    public let creationDate: Date?

    enum CodingKeys: String, CodingKey {
        case id = "teamId"
        case name
        case status
        case type
        case isXcodeFreeOnly = "xcodeFreeOnly"
        case memberships
        case currentMember = "currentTeamMember"
        case provisioningSettings = "teamProvisioningSettings"
        case creationDate = "dateCreated"
    }

    /// Creates a team value.
    public init(
        id: ID,
        name: String,
        status: String? = nil,
        type: String? = nil,
        isXcodeFreeOnly: Bool = false,
        memberships: [TeamMembership] = [],
        currentMember: TeamMember? = nil,
        provisioningSettings: TeamProvisioningSettings? = nil,
        creationDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.type = type
        self.isXcodeFreeOnly = isXcodeFreeOnly
        self.memberships = memberships
        self.currentMember = currentMember
        self.provisioningSettings = provisioningSettings
        self.creationDate = creationDate
    }

    /// Decodes a team from Apple's QH property-list representation.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        isXcodeFreeOnly =
            try container.decodeIfPresent(Bool.self, forKey: .isXcodeFreeOnly) ?? false
        memberships =
            try container.decodeIfPresent([TeamMembership].self, forKey: .memberships) ?? []
        currentMember = try container.decodeIfPresent(TeamMember.self, forKey: .currentMember)
        provisioningSettings = try container.decodeIfPresent(
            TeamProvisioningSettings.self,
            forKey: .provisioningSettings
        )
        creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate)
    }
}

/// A Developer Program product membership belonging to a team.
public struct TeamMembership: Codable, Sendable {
    /// Apple's membership identifier.
    public let id: String?

    /// Apple's product identifier for the membership.
    public let productID: String?

    /// The membership status.
    public let status: String?

    /// The platform covered by the membership.
    public let platform: String?

    /// Whether the membership is in Apple's renewal window.
    public let isInRenewalWindow: Bool?

    /// Whether the membership is in the iOS device-reset window.
    public let isInIOSResetWindow: Bool?

    /// The membership start date, when supplied.
    public let startDate: Date?

    /// Whether Apple removes registered devices when the membership expires.
    public let deletesDevicesOnExpiry: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "membershipId"
        case productID = "membershipProductId"
        case status
        case platform
        case isInRenewalWindow = "inRenewalWindow"
        case isInIOSResetWindow = "inIosResetWindow"
        case startDate = "dateStart"
        case deletesDevicesOnExpiry = "deleteDevicesOnExpiry"
    }

    /// Creates a team-membership value.
    public init(
        id: String? = nil,
        productID: String? = nil,
        status: String? = nil,
        platform: String? = nil,
        isInRenewalWindow: Bool? = nil,
        isInIOSResetWindow: Bool? = nil,
        startDate: Date? = nil,
        deletesDevicesOnExpiry: Bool? = nil
    ) {
        self.id = id
        self.productID = productID
        self.status = status
        self.platform = platform
        self.isInRenewalWindow = isInRenewalWindow
        self.isInIOSResetWindow = isInIOSResetWindow
        self.startDate = startDate
        self.deletesDevicesOnExpiry = deletesDevicesOnExpiry
    }
}

/// A person associated with an Apple Developer Program team.
public struct TeamMember: Codable, Sendable {
    /// Apple's team-member identifier.
    public let id: String?

    /// The member's Apple person identifier.
    public let personID: Int?

    /// The member's first name.
    public let firstName: String?

    /// The member's last name.
    public let lastName: String?

    /// The member's email address.
    public let email: String?

    /// Apple's developer status for the member.
    public let developerStatus: String?

    /// Roles assigned to the member.
    public let roles: [String]

    enum CodingKeys: String, CodingKey {
        case id = "teamMemberId"
        case personID = "personId"
        case firstName
        case lastName
        case email
        case developerStatus
        case roles
    }

    /// Creates a team-member value.
    public init(
        id: String? = nil,
        personID: Int? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        developerStatus: String? = nil,
        roles: [String] = []
    ) {
        self.id = id
        self.personID = personID
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.developerStatus = developerStatus
        self.roles = roles
    }

    /// Decodes a team member while tolerating an omitted roles array.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        personID = try container.decodeIfPresent(Int.self, forKey: .personID)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        developerStatus = try container.decodeIfPresent(String.self, forKey: .developerStatus)
        roles = try container.decodeIfPresent([String].self, forKey: .roles) ?? []
    }
}

/// Team-level permissions Apple reports for Developer-role members.
public struct TeamProvisioningSettings: Codable, Sendable {
    /// Whether a Developer-role member may register devices.
    public let canDeveloperRegisterDevices: Bool

    /// Whether a Developer-role member may create App IDs.
    public let canDeveloperAddAppIDs: Bool

    /// Whether a Developer-role member may update App IDs.
    public let canDeveloperUpdateAppIDs: Bool

    enum CodingKeys: String, CodingKey {
        case canDeveloperRegisterDevices = "canDeveloperRoleRegisterDevices"
        case canDeveloperAddAppIDs = "canDeveloperRoleAddAppIds"
        case canDeveloperUpdateAppIDs = "canDeveloperRoleUpdateAppIds"
    }

    /// Creates team provisioning settings.
    public init(
        canDeveloperRegisterDevices: Bool,
        canDeveloperAddAppIDs: Bool,
        canDeveloperUpdateAppIDs: Bool
    ) {
        self.canDeveloperRegisterDevices = canDeveloperRegisterDevices
        self.canDeveloperAddAppIDs = canDeveloperAddAppIDs
        self.canDeveloperUpdateAppIDs = canDeveloperUpdateAppIDs
    }

    /// Decodes provisioning settings while treating omitted permissions as denied.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canDeveloperRegisterDevices =
            try container.decodeIfPresent(Bool.self, forKey: .canDeveloperRegisterDevices) ?? false
        canDeveloperAddAppIDs =
            try container.decodeIfPresent(Bool.self, forKey: .canDeveloperAddAppIDs) ?? false
        canDeveloperUpdateAppIDs =
            try container.decodeIfPresent(Bool.self, forKey: .canDeveloperUpdateAppIDs) ?? false
    }
}

/// Developer account information returned for a selected team.
public struct DeveloperInfo: Codable, Sendable {
    /// The developer's first name.
    public let firstName: String?

    /// The developer's last name.
    public let lastName: String?

    /// The first name from Apple's directory service.
    public let directoryFirstName: String?

    /// The last name from Apple's directory service.
    public let directoryLastName: String?

    /// The developer's email address.
    public let email: String?

    /// Apple's current developer status.
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case firstName
        case lastName
        case directoryFirstName = "dsFirstName"
        case directoryLastName = "dsLastName"
        case email
        case status = "developerStatus"
    }

    /// Creates developer account information.
    public init(
        firstName: String? = nil,
        lastName: String? = nil,
        directoryFirstName: String? = nil,
        directoryLastName: String? = nil,
        email: String? = nil,
        status: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.directoryFirstName = directoryFirstName
        self.directoryLastName = directoryLastName
        self.email = email
        self.status = status
    }
}
