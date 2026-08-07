import Foundation

struct AnisetteHeaderBuilder: Sendable {
    func gsaHeaders(from anisette: AnisetteHeaders, closingConnection: Bool) throws
        -> [(name: String, value: String)]
    {
        guard let clientInfo = anisette.header(AuthConstants.Header.gsaClientInfo) else {
            throw missingAnisetteHeader(AuthConstants.Header.gsaClientInfo)
        }
        var headers = [
            (
                name: AuthConstants.Header.contentType,
                value: AuthConstants.ContentType.plist
            ),
            (name: AuthConstants.Header.accept, value: AuthConstants.ContentType.any),
            (name: AuthConstants.Header.userAgent, value: AuthConstants.gsaUserAgent),
            (name: AuthConstants.Header.gsaClientInfo, value: clientInfo),
        ]
        if closingConnection {
            headers.append(
                (name: AuthConstants.Header.connection, value: "close")
            )
        }
        return headers
    }

    // cpd is the anisette set folded into the request body, minus client
    // info. that one goes as an actual header instead of going in here
    func cpd(from anisette: AnisetteHeaders) -> [String: PlistValue] {
        var values = anisette.values.filter { key, _ in
            !matches(key, AuthConstants.Header.gsaClientInfo)
        }.mapValues(PlistValue.string)
        values[AuthConstants.CPD.bootstrap] = .string(AuthConstants.CPD.trueValue)
        values[AuthConstants.CPD.isComplete] = .string(AuthConstants.CPD.trueValue)
        values[AuthConstants.CPD.locale] = .string(AuthConstants.cpdLocale)
        values[AuthConstants.CPD.passwordEquivalent] = .string(AuthConstants.CPD.falseValue)
        values[AuthConstants.CPD.generatePrivateKey] = .string(AuthConstants.CPD.trueValue)
        values[AuthConstants.CPD.service] = .string(AuthConstants.CPD.iCloud)
        return values
    }

    func twoFactorHeaders(
        from anisette: AnisetteHeaders,
        identityToken: String,
        usesJSON: Bool
    ) throws -> [(name: String, value: String)] {
        var values = anisette.values
        guard let rawClientInfo = anisette.header(AuthConstants.Header.normalizedClientInfo),
            var clientInfo = ClientInfo(parsing: rawClientInfo)
        else {
            throw missingAnisetteHeader(AuthConstants.Header.normalizedClientInfo)
        }

        remove(AuthConstants.Header.normalizedClientInfo, from: &values)
        clientInfo.client = AuthConstants.xcodeClient
        values[AuthConstants.Header.normalizedClientInfo] = clientInfo.stringValue
        values[AuthConstants.Header.appInfo] = AuthConstants.xcodeApp
        values[AuthConstants.Header.xcodeVersion] = AuthConstants.xcodeVersion

        var headers = values.map { (name: $0.key, value: $0.value) }
        let contentType =
            usesJSON ? AuthConstants.ContentType.json : AuthConstants.ContentType.plist
        headers.append((name: AuthConstants.Header.contentType, value: contentType))
        headers.append((name: AuthConstants.Header.accept, value: contentType))
        headers.append((name: AuthConstants.Header.userAgent, value: AuthConstants.xcodeUserAgent))
        headers.append(
            (name: AuthConstants.Header.acceptLanguage, value: AuthConstants.acceptLanguage)
        )
        headers.append((name: AuthConstants.Header.identityToken, value: identityToken))
        if let locale = anisette.header(AuthConstants.Header.appleLocale) {
            headers.append((name: AuthConstants.Header.locale, value: locale))
        }
        return headers
    }

    private func remove(_ name: String, from values: inout [String: String]) {
        let matchingKeys = values.keys.filter { matches($0, name) }
        for key in matchingKeys {
            values.removeValue(forKey: key)
        }
    }

    private func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .caseInsensitive) == .orderedSame
    }

    private func missingAnisetteHeader(_ name: String) -> SwiftDunkError {
        SwiftDunkError(
            code: .malformedResponse(key: name, expected: "an anisette header string")
        )
    }
}
