public import Foundation
import SwiftDunkCore
public import SwiftDunkPortal
import SwiftASN1

/// Typed metadata extracted from an Apple provisioning profile.
public struct ProvisioningProfileMetadata: Sendable {
    /// The profile's display name.
    public let name: String

    /// The profile UUID.
    public let uuid: String

    /// The App ID's display name.
    public let appIDName: String?

    /// The teams authorized by the profile.
    public let teamIdentifiers: [String]

    /// The application-identifier prefixes authorized by the profile.
    public let applicationIdentifierPrefixes: [String]

    /// The profile creation date.
    public let creationDate: Date

    /// The profile expiration date.
    public let expirationDate: Date

    /// The platforms authorized by the profile.
    public let platforms: [String]

    /// The provisioned device identifiers.
    public let provisionedDevices: [String]

    /// Whether the profile is valid for every device.
    public let provisionsAllDevices: Bool

    /// Selected, typed entitlements carried by the profile.
    public let entitlements: ProvisioningProfileEntitlements
}

/// Common entitlements extracted from a provisioning profile.
public struct ProvisioningProfileEntitlements: Sendable {
    /// The fully qualified application identifier.
    public let applicationIdentifier: String?

    /// The developer team identifier.
    public let teamIdentifier: String?

    /// The Keychain access groups authorized by the profile.
    public let keychainAccessGroups: [String]

    /// Whether the profile permits a debugger to attach.
    public let getTaskAllow: Bool?
}

public extension ProvisioningProfile {
    /// Extracts the typed property-list payload from the CMS profile.
    ///
    /// This parses the CMS envelope but does not establish trust in its signer. Use the
    /// result as Apple-issued provisioning metadata, not as a general-purpose CMS trust
    /// decision.
    /// - Throws: ``SwiftDunkError`` when the CMS envelope or property-list payload is
    ///   malformed or omits a required field.
    func metadata() throws -> ProvisioningProfileMetadata {
        let payload = try ProvisioningProfileParser.payload(from: data)
        let wire: ProvisioningProfileWireMetadata
        do {
            wire = try PropertyListDecoder().decode(
                ProvisioningProfileWireMetadata.self,
                from: payload
            )
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "provisioningProfile",
                    expected: "a CMS envelope containing a valid profile property list"
                ),
                underlyingError: error
            )
        }
        return ProvisioningProfileMetadata(
            name: wire.name,
            uuid: wire.uuid,
            appIDName: wire.appIDName,
            teamIdentifiers: wire.teamIdentifiers,
            applicationIdentifierPrefixes: wire.applicationIdentifierPrefixes,
            creationDate: wire.creationDate,
            expirationDate: wire.expirationDate,
            platforms: wire.platforms,
            provisionedDevices: wire.provisionedDevices,
            provisionsAllDevices: wire.provisionsAllDevices,
            entitlements: ProvisioningProfileEntitlements(
                applicationIdentifier: wire.entitlements.applicationIdentifier,
                teamIdentifier: wire.entitlements.teamIdentifier,
                keychainAccessGroups: wire.entitlements.keychainAccessGroups,
                getTaskAllow: wire.entitlements.getTaskAllow
            )
        )
    }
}

private enum ProvisioningProfileParser {
    static func payload(from data: Data) throws -> Data {
        if (try? PropertyListSerialization.propertyList(from: data, format: nil)) != nil {
            return data
        }

        do {
            let contentInfo = try DER.parse(Array(data))
            let contentInfoChildren = try children(of: contentInfo)
            let signedDataWrapper = try element(at: 1, in: contentInfoChildren)
            let signedDataWrapperChildren = try children(of: signedDataWrapper)
            let signedData = try element(at: 0, in: signedDataWrapperChildren)
            let signedDataChildren = try children(of: signedData)
            let encapsulatedContentInfo = try element(at: 2, in: signedDataChildren)
            let encapsulatedChildren = try children(of: encapsulatedContentInfo)
            let contentWrapper = try element(at: 1, in: encapsulatedChildren)
            let contentWrapperChildren = try children(of: contentWrapper)
            let octetStringNode = try element(at: 0, in: contentWrapperChildren)
            let octetString = try ASN1OctetString(derEncoded: octetStringNode)
            return Data(octetString.bytes)
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "encodedProfile",
                    expected: "a valid CMS provisioning profile"
                ),
                underlyingError: error
            )
        }
    }

    private static func children(of node: ASN1Node) throws -> [ASN1Node] {
        guard case .constructed(let children) = node.content else {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "encodedProfile",
                    expected: "the expected constructed CMS node"
                )
            )
        }
        return Array(children)
    }

    private static func element(at index: Int, in nodes: [ASN1Node]) throws -> ASN1Node {
        guard nodes.indices.contains(index) else {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "encodedProfile",
                    expected: "the complete CMS SignedData structure"
                )
            )
        }
        return nodes[index]
    }
}

private struct ProvisioningProfileWireMetadata: Decodable {
    let name: String
    let uuid: String
    let appIDName: String?
    let teamIdentifiers: [String]
    let applicationIdentifierPrefixes: [String]
    let creationDate: Date
    let expirationDate: Date
    let platforms: [String]
    let provisionedDevices: [String]
    let provisionsAllDevices: Bool
    let entitlements: Entitlements

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case uuid = "UUID"
        case appIDName = "AppIDName"
        case teamIdentifiers = "TeamIdentifier"
        case applicationIdentifierPrefixes = "ApplicationIdentifierPrefix"
        case creationDate = "CreationDate"
        case expirationDate = "ExpirationDate"
        case platforms = "Platform"
        case provisionedDevices = "ProvisionedDevices"
        case provisionsAllDevices = "ProvisionsAllDevices"
        case entitlements = "Entitlements"
    }

    struct Entitlements: Decodable {
        let applicationIdentifier: String?
        let teamIdentifier: String?
        let keychainAccessGroups: [String]
        let getTaskAllow: Bool?

        enum CodingKeys: String, CodingKey {
            case applicationIdentifier = "application-identifier"
            case teamIdentifier = "com.apple.developer.team-identifier"
            case keychainAccessGroups = "keychain-access-groups"
            case getTaskAllow = "get-task-allow"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            applicationIdentifier =
                try container.decodeIfPresent(String.self, forKey: .applicationIdentifier)
            teamIdentifier =
                try container.decodeIfPresent(String.self, forKey: .teamIdentifier)
            keychainAccessGroups =
                try container.decodeIfPresent([String].self, forKey: .keychainAccessGroups) ?? []
            getTaskAllow =
                try container.decodeIfPresent(Bool.self, forKey: .getTaskAllow)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        uuid = try container.decode(String.self, forKey: .uuid)
        appIDName = try container.decodeIfPresent(String.self, forKey: .appIDName)
        teamIdentifiers =
            try container.decodeIfPresent([String].self, forKey: .teamIdentifiers) ?? []
        applicationIdentifierPrefixes =
            try container.decodeIfPresent(
                [String].self,
                forKey: .applicationIdentifierPrefixes
            ) ?? []
        creationDate = try container.decode(Date.self, forKey: .creationDate)
        expirationDate = try container.decode(Date.self, forKey: .expirationDate)
        platforms = try container.decodeIfPresent([String].self, forKey: .platforms) ?? []
        provisionedDevices =
            try container.decodeIfPresent([String].self, forKey: .provisionedDevices) ?? []
        provisionsAllDevices =
            try container.decodeIfPresent(Bool.self, forKey: .provisionsAllDevices) ?? false
        entitlements = try container.decode(Entitlements.self, forKey: .entitlements)
    }
}
