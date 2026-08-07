import Foundation

enum AnisetteConstants {
    static let identifierLength = 16
    // refresh at 60 seconds so a failed fetch can use the cache until 90
    static let refreshAfter: TimeInterval = 60
    static let hardExpiry: TimeInterval = 90
    static let serialNumber = "0"
    static let timeZone = "UTC"
    static let locale = "en_US"
    static let staleProvisioningCode = "-45061"
    static let maximumProvisioningMessages = 16

    enum Path {
        static let clientInfo = "v3/client_info"
        static let headers = "v3/get_headers"
        static let provisioning = "v3/provisioning_session"
        static let lookup = "https://gsa.apple.com/grandslam/GsService2/lookup"
    }

    enum Header {
        static let clientInfo = "X-Mme-Client-Info"
        static let userAgent = "User-Agent"
        static let contentType = "Content-Type"
        static let localUserID = "X-Apple-I-MD-LU"
        static let deviceID = "X-Mme-Device-Id"
        static let clientTime = "X-Apple-I-Client-Time"
        static let timeZone = "X-Apple-I-TimeZone"
        static let locale = "X-Apple-Locale"
        static let serialNumber = "X-Apple-I-SRL-NO"
        static let machineID = "X-Apple-I-MD-M"
        static let oneTimePassword = "X-Apple-I-MD"
        static let routingInfo = "X-Apple-I-MD-RINFO"
        static let plistContentType = "text/x-xml-plist"
        static let jsonContentType = "application/json"
    }

    enum ProvisioningResult {
        static let giveIdentifier = "GiveIdentifier"
        static let giveStartData = "GiveStartProvisioningData"
        static let giveEndData = "GiveEndProvisioningData"
        static let success = "ProvisioningSuccess"
    }
}
