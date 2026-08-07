import Foundation

// these three values identify the same xcode 11.2 build
package enum XcodeIdentityConstants {
    package static let client = "com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)"
    package static let app = "com.apple.gs.xcode.auth"
    package static let version = "11.2 (11B41)"
}

enum AuthConstants {
    static let gsaURL = "https://gsa.apple.com/grandslam/GsService2"
    static let trustedDeviceURL = "https://gsa.apple.com/auth/verify/trusteddevice"
    static let validateURL = "https://gsa.apple.com/grandslam/GsService2/validate"
    static let authURL = "https://gsa.apple.com/auth"
    static let sendSMSURL = "https://gsa.apple.com/auth/verify/phone"
    static let verifySMSURL = "https://gsa.apple.com/auth/verify/phone/securitycode"

    static let gsaVersion = "1.0.1"
    static let gsaUserAgent = "akd/1.0 CFNetwork/978.0.7 Darwin/18.7.0"
    static let xcodeUserAgent = "Xcode"
    static let xcodeClient = XcodeIdentityConstants.client
    static let xcodeApp = XcodeIdentityConstants.app
    static let xcodeVersion = XcodeIdentityConstants.version
    static let acceptLanguage = "en-us"
    // this really is en_GB even though acceptLanguage is en-us
    static let cpdLocale = "en_GB"
    static let personalTokenName = "com.apple.gs.idms.pet"
    static let smsMode = "sms"

    enum CPD {
        static let bootstrap = "bootstrap"
        static let isComplete = "icscrec"
        static let locale = "loc"
        static let passwordEquivalent = "pbe"
        static let generatePrivateKey = "prkgen"
        static let service = "svct"
        static let trueValue = "true"
        static let falseValue = "false"
        static let iCloud = "iCloud"
    }

    enum Operation {
        static let initialize = "init"
        static let complete = "complete"
        static let appTokens = "apptokens"
    }

    enum AuthType {
        static let trustedDevice = "trustedDeviceSecondaryAuth"
        static let sms = "secondaryAuth"
    }

    enum Header {
        static let contentType = "Content-Type"
        static let accept = "Accept"
        static let userAgent = "User-Agent"
        static let gsaClientInfo = "X-MMe-Client-Info"
        static let normalizedClientInfo = "X-Mme-Client-Info"
        static let connection = "Connection"
        static let identityToken = "X-Apple-Identity-Token"
        static let securityCode = "security-code"
        static let acceptLanguage = "Accept-Language"
        static let locale = "Loc"
        static let appleLocale = "X-Apple-Locale"
        static let appInfo = "X-Apple-App-Info"
        static let xcodeVersion = "X-Xcode-Version"
    }

    enum ContentType {
        static let plist = "text/x-xml-plist"
        static let json = "application/json"
        static let any = "*/*"
    }

    enum SessionLabel {
        static let extraDataKey = "extra data key:"
        static let extraDataIV = "extra data iv:"
    }

    enum AppToken {
        static let prefix = "com.apple.gs."
        static let statusCode = "status-code"
        static let successStatusCode = 200
        static let checksumPrefix = Data("apptokens".utf8)
        static let encryptedHeader = Data("XYZ".utf8)
        static let nonceLength = 16
        static let tagLength = 16
        static let millisecondsPerSecond = 1_000.0
    }

    enum SRP {
        static let derivedPasswordLength = 32
        static let s2k = "s2k"
        static let s2kFO = "s2k_fo"
        static let privateKeyLength = 32
    }
}
