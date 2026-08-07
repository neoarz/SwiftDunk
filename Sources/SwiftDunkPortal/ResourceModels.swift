public import Foundation

/// A device registered with an Apple Developer Program team.
public struct Device: Sendable, Identifiable, Codable {
    /// A strongly typed registered-device identifier.
    public struct ID: Hashable, Sendable, Codable, RawRepresentable {
        /// The wire-format `deviceId` value.
        public let rawValue: String

        /// Creates a device identifier from its wire value.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// Apple's internal device identifier.
    public let id: ID

    /// The caller-visible device name.
    public let name: String

    /// The device UDID, named `deviceNumber` by Apple's QH API.
    public let udid: String

    /// The Apple platform associated with the device.
    public let platform: String?

    /// Apple's current registration status.
    public let status: String?

    /// Apple's device-class value.
    public let deviceClass: String?

    /// The registration expiration date, when supplied.
    public let expirationDate: Date?

    enum CodingKeys: String, CodingKey {
        case id = "deviceId"
        case name
        case udid = "deviceNumber"
        case platform = "devicePlatform"
        case status
        case deviceClass
        case expirationDate
    }

    /// Creates a registered-device value.
    public init(
        id: ID,
        name: String,
        udid: String,
        platform: String? = nil,
        status: String? = nil,
        deviceClass: String? = nil,
        expirationDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.udid = udid
        self.platform = platform
        self.status = status
        self.deviceClass = deviceClass
        self.expirationDate = expirationDate
    }
}

/// An App ID registered with an Apple Developer Program team.
public struct AppID: Sendable, Identifiable, Codable {
    /// A strongly typed `appIdId` value.
    public struct ID: Hashable, Sendable, Codable, RawRepresentable {
        /// The wire-format identifier used for App ID mutations.
        public let rawValue: String

        /// Creates an App ID identifier from its wire value.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// Apple's internal App ID identifier.
    public let id: ID

    /// The App ID's display name.
    public let name: String?

    /// The registered bundle identifier.
    public let identifier: String

    /// Apple's App ID platform value.
    public let platform: String?

    /// The bundle-seed prefix.
    public let prefix: String?

    /// Whether the identifier contains a wildcard.
    public let isWildcard: Bool

    /// Whether Apple reports this entry as a duplicate.
    public let isDuplicate: Bool?

    /// Legacy QH capability state.
    public let features: AppIDFeatures?

    /// Apple's enabled feature identifiers, when supplied.
    public let enabledFeatures: [String]

    /// The registration expiration date, when supplied by Apple.
    public let expirationDate: Date?

    enum CodingKeys: String, CodingKey {
        case id = "appIdId"
        case name
        case identifier
        case platform = "appIdPlatform"
        case prefix
        case isWildcard = "isWildCard"
        case isDuplicate
        case features
        case enabledFeatures
        case expirationDate
    }

    /// Creates an App ID value.
    public init(
        id: ID,
        name: String? = nil,
        identifier: String,
        platform: String? = nil,
        prefix: String? = nil,
        isWildcard: Bool = false,
        isDuplicate: Bool? = nil,
        features: AppIDFeatures? = nil,
        enabledFeatures: [String] = [],
        expirationDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.identifier = identifier
        self.platform = platform
        self.prefix = prefix
        self.isWildcard = isWildcard
        self.isDuplicate = isDuplicate
        self.features = features
        self.enabledFeatures = enabledFeatures
        self.expirationDate = expirationDate
    }

    /// Decodes an App ID while tolerating omitted optional feature fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        identifier = try container.decode(String.self, forKey: .identifier)
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        prefix = try container.decodeIfPresent(String.self, forKey: .prefix)
        isWildcard = try container.decodeIfPresent(Bool.self, forKey: .isWildcard) ?? false
        isDuplicate = try container.decodeIfPresent(Bool.self, forKey: .isDuplicate)
        features = try container.decodeIfPresent(AppIDFeatures.self, forKey: .features)
        enabledFeatures =
            try container.decodeIfPresent([String].self, forKey: .enabledFeatures) ?? []
        expirationDate = try container.decodeIfPresent(Date.self, forKey: .expirationDate)
    }
}

/// App IDs and the registration quota Apple reports for a team.
public struct AppIDInventory: Sendable {
    /// Every App ID returned across all response pages.
    public let appIDs: [AppID]

    /// The maximum number of App IDs the team may register, when supplied by Apple.
    public let maximumQuantity: Int?

    /// The remaining App ID registrations reported by Apple, when supplied.
    ///
    /// Apple may temporarily report a negative value when its account state is inconsistent.
    /// SwiftDunk preserves that value rather than silently changing server data.
    public let availableQuantity: Int?

    /// Creates an App ID inventory value.
    public init(
        appIDs: [AppID],
        maximumQuantity: Int? = nil,
        availableQuantity: Int? = nil
    ) {
        self.appIDs = appIDs
        self.maximumQuantity = maximumQuantity
        self.availableQuantity = availableQuantity
    }
}

/// Legacy QH feature state attached to an App ID.
public struct AppIDFeatures: Codable, Sendable {
    /// Whether push notifications are enabled.
    public let pushNotifications: Bool?

    /// Whether iCloud is enabled.
    public let iCloud: Bool?

    /// Whether in-app purchase is enabled.
    public let inAppPurchase: Bool?

    /// Whether Game Center is enabled.
    public let gameCenter: Bool?

    /// Whether Wallet passes are enabled.
    public let wallet: Bool?

    /// Apple's default data-protection mode.
    public let dataProtection: String?

    /// Whether HomeKit is enabled.
    public let homeKit: Bool?

    /// Apple's CloudKit version value.
    public let cloudKitVersion: Int?

    enum CodingKeys: String, CodingKey {
        case pushNotifications = "push"
        case iCloud
        case inAppPurchase
        case gameCenter
        case wallet = "passbook"
        case dataProtection
        case homeKit
        case cloudKitVersion
    }

    /// Creates legacy QH feature state.
    public init(
        pushNotifications: Bool? = nil,
        iCloud: Bool? = nil,
        inAppPurchase: Bool? = nil,
        gameCenter: Bool? = nil,
        wallet: Bool? = nil,
        dataProtection: String? = nil,
        homeKit: Bool? = nil,
        cloudKitVersion: Int? = nil
    ) {
        self.pushNotifications = pushNotifications
        self.iCloud = iCloud
        self.inAppPurchase = inAppPurchase
        self.gameCenter = gameCenter
        self.wallet = wallet
        self.dataProtection = dataProtection
        self.homeKit = homeKit
        self.cloudKitVersion = cloudKitVersion
    }
}

/// An application group registered with an Apple Developer Program team.
public struct AppGroup: Sendable, Identifiable, Codable {
    /// A strongly typed application-group resource identifier.
    public struct ID: Hashable, Sendable, Codable, RawRepresentable {
        /// Apple's `applicationGroup` wire value.
        public let rawValue: String

        /// Creates an application-group identifier from its wire value.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// Apple's internal application-group resource identifier.
    ///
    /// Apple confusingly names this field `applicationGroup` on the wire.
    public let id: ID

    /// The application group's display name.
    public let name: String

    /// The registered `group.` identifier.
    ///
    /// Apple names this separate field `identifier` on the wire.
    public let groupIdentifier: String

    /// Apple's current application-group status.
    public let status: String?

    /// The account prefix associated with the group.
    public let prefix: String?

    enum CodingKeys: String, CodingKey {
        case id = "applicationGroup"
        case name
        case groupIdentifier = "identifier"
        case status
        case prefix
    }

    /// Creates an application-group value.
    public init(
        id: ID,
        name: String,
        groupIdentifier: String,
        status: String? = nil,
        prefix: String? = nil
    ) {
        self.id = id
        self.name = name
        self.groupIdentifier = groupIdentifier
        self.status = status
        self.prefix = prefix
    }
}
