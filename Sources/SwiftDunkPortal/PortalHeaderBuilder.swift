import Foundation
import SwiftDunkAuth

struct PortalCredentials: Sendable {
    let adsid: String
    let token: String
}

struct PortalHeaderBuilder: Sendable {
    func commonHeaders(
        anisette: AnisetteHeaders,
        credentials: PortalCredentials
    ) throws -> [(name: String, value: String)] {
        guard
            let rawClientInfo = anisette.header(PortalConstants.Header.clientInfo),
            var clientInfo = ClientInfo(parsing: rawClientInfo)
        else {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: PortalConstants.Header.clientInfo,
                    expected: "a three-component anisette client-info header"
                )
            )
        }
        clientInfo.client = PortalConstants.xcodeClient

        var headers: [(name: String, value: String)] = [
            (
                name: PortalConstants.Header.acceptLanguage,
                value: PortalConstants.acceptLanguage
            ),
            (name: PortalConstants.Header.userAgent, value: PortalConstants.userAgent),
            (name: PortalConstants.Header.identityID, value: credentials.adsid),
            (name: PortalConstants.Header.gsToken, value: credentials.token),
        ]
        for (name, value) in anisette.values.sorted(by: { $0.key < $1.key })
        where !replacedHeaderNames.contains(where: { matches(name, $0) }) {
            headers.append((name: name, value: value))
        }
        headers.append(
            (name: PortalConstants.Header.clientInfo, value: clientInfo.stringValue)
        )
        headers.append(
            (name: PortalConstants.Header.appInfo, value: PortalConstants.xcodeApp)
        )
        headers.append(
            (name: PortalConstants.Header.xcodeVersion, value: PortalConstants.xcodeVersion)
        )
        if let locale = anisette.header(PortalConstants.Header.appleLocale) {
            headers.append((name: PortalConstants.Header.appleLocale, value: locale))
        }
        return headers
    }

    private var replacedHeaderNames: [String] {
        [
            PortalConstants.Header.clientInfo,
            PortalConstants.Header.appleLocale,
            PortalConstants.Header.appInfo,
            PortalConstants.Header.xcodeVersion,
        ]
    }

    private func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .caseInsensitive) == .orderedSame
    }
}
