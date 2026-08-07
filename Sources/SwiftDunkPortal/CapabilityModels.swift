/// A capability that can be enabled on an App ID.
public struct Capability: Codable, Sendable, Identifiable {
    /// Apple's stable capability identifier.
    public let id: String

    /// Capability metadata from Apple's JSON:API response.
    public let attributes: Attributes

    /// Creates a capability value.
    public init(id: String, attributes: Attributes) {
        self.id = id
        self.attributes = attributes
    }

    /// Metadata describing where a capability can be used.
    public struct Attributes: Codable, Sendable {
        /// Entitlement keys associated with the capability.
        public let entitlements: [Entitlement]

        /// Whether Apple allows the capability on wildcard App IDs.
        public let supportsWildcard: Bool

        enum CodingKeys: String, CodingKey {
            case entitlements
            case supportsWildcard
        }

        /// Creates capability metadata.
        public init(entitlements: [Entitlement] = [], supportsWildcard: Bool) {
            self.entitlements = entitlements
            self.supportsWildcard = supportsWildcard
        }

        /// Decodes capability metadata while tolerating omitted entitlements.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            entitlements =
                try container.decodeIfPresent([Entitlement].self, forKey: .entitlements) ?? []
            supportsWildcard =
                try container.decodeIfPresent(Bool.self, forKey: .supportsWildcard) ?? false
        }
    }

    /// An entitlement associated with a Developer Portal capability.
    public struct Entitlement: Codable, Sendable {
        /// The entitlement key Apple expects in a provisioning profile.
        public let profileKey: String

        /// Creates a capability entitlement.
        public init(profileKey: String) {
            self.profileKey = profileKey
        }
    }
}
