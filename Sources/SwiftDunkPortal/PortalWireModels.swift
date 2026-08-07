struct QHTeamsResponse: Decodable, Sendable {
    let teams: [Team]
}

struct QHDeveloperResponse: Decodable, Sendable {
    let developer: DeveloperInfo
}

struct QHDevicesResponse: Decodable, Sendable {
    let devices: [Device]
}

struct QHDeviceResponse: Decodable, Sendable {
    let device: Device
}

struct QHAppIDsResponse: Decodable, Sendable {
    let appIDs: [AppID]
    let maximumQuantity: Int?
    let availableQuantity: Int?

    enum CodingKeys: String, CodingKey {
        case appIDs = "appIds"
        case maximumQuantity = "maxQuantity"
        case availableQuantity
    }
}

struct QHAppIDResponse: Decodable, Sendable {
    let appID: AppID

    enum CodingKeys: String, CodingKey {
        case appID = "appId"
    }
}

struct QHAppGroupsResponse: Decodable, Sendable {
    let appGroups: [AppGroup]

    enum CodingKeys: String, CodingKey {
        case appGroups = "applicationGroupList"
    }
}

struct QHAppGroupResponse: Decodable, Sendable {
    let appGroup: AppGroup

    enum CodingKeys: String, CodingKey {
        case appGroup = "applicationGroup"
    }
}

struct QHCertificatesResponse: Decodable, Sendable {
    let certificates: [Certificate]
}

struct QHCertificateRequestResponse: Decodable, Sendable {
    let request: CertificateRequest

    enum CodingKeys: String, CodingKey {
        case request = "certRequest"
    }
}

struct QHProvisioningProfileResponse: Decodable, Sendable {
    let profile: ProvisioningProfile

    enum CodingKeys: String, CodingKey {
        case profile = "provisioningProfile"
    }
}

struct QHEmptyResponse: Decodable, Sendable {}

struct V1GetRequest: Encodable, Sendable {
    let teamID: String
    let query: String

    enum CodingKeys: String, CodingKey {
        case teamID = "teamId"
        case query = "urlEncodedQueryParams"
    }
}

struct V1CapabilitiesResponse: Decodable, Sendable {
    let data: [Capability]
}

struct V1BundleIDsResponse: Decodable, Sendable {
    let data: [V1BundleID]
}

struct V1BundleIDResponse: Decodable, Sendable {
    let data: V1BundleID
}

struct V1BundleID: Codable, Sendable {
    let id: String
    let attributes: Attributes

    struct Attributes: Codable, Sendable {
        let identifier: String
        let seedID: String
        let name: String
        let wildcard: Bool

        enum CodingKeys: String, CodingKey {
            case identifier
            case seedID = "seedId"
            case name
            case wildcard
        }
    }
}

struct V1BundleIDUpdateRequest: Encodable, Sendable {
    let data: Resource

    struct Resource: Encodable, Sendable {
        let type: String
        let id: String
        let attributes: Attributes
        let relationships: Relationships
    }

    struct Attributes: Encodable, Sendable {
        let identifier: String
        let seedID: String
        let teamID: String
        let name: String
        let wildcard: Bool

        enum CodingKeys: String, CodingKey {
            case identifier
            case seedID = "seedId"
            case teamID = "teamId"
            case name
            case wildcard
        }
    }

    struct Relationships: Encodable, Sendable {
        let capabilities: CapabilityData

        enum CodingKeys: String, CodingKey {
            case capabilities = "bundleIdCapabilities"
        }
    }

    struct CapabilityData: Encodable, Sendable {
        let data: [CapabilityResource]
    }

    struct CapabilityResource: Encodable, Sendable {
        let type: String
        let attributes: CapabilityAttributes
        let relationships: CapabilityRelationships
    }

    struct CapabilityAttributes: Encodable, Sendable {
        let enabled = true
        let settings: [String] = []
    }

    struct CapabilityRelationships: Encodable, Sendable {
        let capability: CapabilityRelationship
    }

    struct CapabilityRelationship: Encodable, Sendable {
        let data: CapabilityIdentifier
    }

    struct CapabilityIdentifier: Encodable, Sendable {
        let type: String
        let id: String
    }
}

struct V1CertificateRequest: Encodable, Sendable {
    let data: Resource

    struct Resource: Encodable, Sendable {
        let type: String
        let attributes: Attributes
    }

    struct Attributes: Encodable, Sendable {
        let certificateType: String
        let teamID: String
        let csrContent: String
        let machineName: String
        let machineID: String

        enum CodingKeys: String, CodingKey {
            case certificateType = "certificatesType"
            case teamID = "teamId"
            case csrContent
            case machineName
            case machineID = "machineId"
        }
    }
}

struct V1CertificateResponse: Decodable, Sendable {
    let data: Resource

    struct Resource: Decodable, Sendable {
        let type: String
        let id: String
    }
}
