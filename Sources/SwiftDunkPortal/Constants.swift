import Foundation
import SwiftDunkAuth

enum PortalConstants {
    static let baseURL = "https://developerservices2.apple.com/services"
    static let acceptLanguage = "en-us"
    static let userAgent = "Xcode"
    static let xcodeClient = XcodeIdentityConstants.client
    static let xcodeApp = XcodeIdentityConstants.app
    static let xcodeVersion = XcodeIdentityConstants.version
    static let unknownAPIError = "Unknown API error"

    enum Header {
        static let contentType = "Content-Type"
        static let accept = "Accept"
        static let acceptLanguage = "Accept-Language"
        static let userAgent = "User-Agent"
        static let identityID = "X-Apple-I-Identity-Id"
        static let gsToken = "X-Apple-GS-Token"
        static let clientInfo = "X-Mme-Client-Info"
        static let appleLocale = "X-Apple-Locale"
        static let appInfo = "X-Apple-App-Info"
        static let xcodeVersion = "X-Xcode-Version"
        static let requestedWith = "X-Requested-With"
        static let methodOverride = "X-HTTP-Method-Override"
    }

    enum ContentType {
        static let plist = "text/x-xml-plist"
        static let jsonAPI = "application/vnd.api+json"
        static let jsonAccept = "application/json, text/plain, */*"
        static let xmlHTTPRequest = "XMLHttpRequest"
    }

    enum QHPath {
        static let listTeams = "/QH65B2/listTeams.action"
        static let accountInfo = "/QH65B2/viewDeveloper.action"
        static let listDevices = "/QH65B2/ios/listDevices.action"
        static let addDevice = "/QH65B2/ios/addDevice.action"
        static let listCertificates = "/QH65B2/ios/listAllDevelopmentCerts.action"
        static let revokeCertificate = "/QH65B2/ios/revokeDevelopmentCert.action"
        static let submitCSR = "/QH65B2/ios/submitDevelopmentCSR.action"
        static let listAppIDs = "/QH65B2/ios/listAppIds.action"
        static let addAppID = "/QH65B2/ios/addAppId.action"
        static let deleteAppID = "/QH65B2/ios/deleteAppId.action"
        static let updateAppID = "/QH65B2/ios/updateAppId.action"
        static let listAppGroups = "/QH65B2/ios/listApplicationGroups.action"
        static let addAppGroup = "/QH65B2/ios/addApplicationGroup.action"
        static let assignAppGroups = "/QH65B2/ios/assignApplicationGroupToAppId.action"
        static let provisioningProfile = "/QH65B2/ios/downloadTeamProvisioningProfile.action"
    }

    enum V1Path {
        static let bundleIDs = "/v1/bundleIds"
        static let capabilities = "/v1/capabilities"
        static let certificates = "/v1/certificates"
    }

    enum BodyKey {
        static let requestID = "requestId"
        static let teamID = "teamId"
        static let pageNumber = "pageNumber"
        static let pageSize = "pageSize"
        static let name = "name"
        static let deviceNumber = "deviceNumber"
        static let identifier = "identifier"
        static let appIDID = "appIdId"
        static let applicationGroups = "applicationGroups"
        static let serialNumber = "serialNumber"
        static let csrContent = "csrContent"
        static let machineID = "machineId"
        static let machineName = "machineName"
    }

    enum V1 {
        static let get = "GET"
        static let bundleIDType = "bundleIds"
        static let bundleIDCapabilityType = "bundleIdCapabilities"
        static let capabilityType = "capabilities"
        static let certificateType = "certificates"
        static let developmentCertificateType = "DEVELOPMENT"
        static let capabilityPlatformQuery = "filter[platform]=IOS"
        static let bundleIDLimitQuery = "limit=1000"
    }

    static let freeAccountDisallowedCapabilities: Set<String> = [
        "AUTOFILL_CREDENTIAL_PROVIDER",
        "APPLE_ID_AUTH",
        "NETWORK_SLICING",
        "MERCHANT_ACCESSIBILITY_CONTROL",
        "ICLOUD",
        "ICLOUD_EXTENDED_SHARE_ACCESS",
        "IN_APP_PURCHASE",
        "JOURNALING_SUGGESTIONS",
        "MDM_MANAGED_ASSOCIATED_DOMAINS",
    ]

    static func url(path: String) throws -> URL {
        guard let url = URL(string: baseURL + path) else {
            throw SwiftDunkError(code: .network)
        }
        return url
    }
}
