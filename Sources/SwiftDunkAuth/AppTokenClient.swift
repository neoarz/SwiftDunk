import Foundation

struct AppTokenClient: Sendable {
    private let account: Account
    private let now: @Sendable () -> Date
    private let headerBuilder = AnisetteHeaderBuilder()
    private let requestClient: GSARequestClient

    init(account: Account, now: @escaping @Sendable () -> Date) {
        self.account = account
        self.now = now
        requestClient = GSARequestClient(transport: account.transport)
    }

    func token(named inputName: String) async throws -> AppToken {
        let name = normalizedName(inputName)
        let anisetteHeaders = try await account.anisette.headers()
        // checksum order is "apptokens", dsid, then app name
        let checksum = SwiftDunkCrypto.hmacSHA256(
            key: account.sessionKey,
            AuthConstants.AppToken.checksumPrefix
                + Data(account.dsid.utf8)
                + Data(name.utf8)
        )
        guard let url = URL(string: AuthConstants.gsaURL) else {
            throw SwiftDunkError(code: .network)
        }

        let response: GSAAppTokenResponse = try await requestClient.send(
            GSAAppTokenRequest(
                header: GSARequestHeader(version: AuthConstants.gsaVersion),
                request: .init(
                    apps: [name],
                    context: account.context,
                    checksum: checksum,
                    cpd: headerBuilder.cpd(from: anisetteHeaders),
                    operation: AuthConstants.Operation.appTokens,
                    token: account.idmsToken,
                    dsid: account.dsid
                )
            ),
            to: url,
            headers: try headerBuilder.gsaHeaders(
                from: anisetteHeaders,
                closingConnection: false
            )
        )
        try requestClient.checkError(response)
        let encryptedToken = try require(
            response.encryptedToken,
            key: "et",
            expected: "encrypted token data"
        )
        return try decrypt(encryptedToken, name: name)
    }

    // et is "XYZ" | nonce | ciphertext | tag, with "XYZ" used as the gcm aad
    private func decrypt(_ encryptedToken: Data, name: String) throws -> AppToken {
        let headerLength = AuthConstants.AppToken.encryptedHeader.count
        let minimumLength =
            headerLength
            + AuthConstants.AppToken.nonceLength
            + AuthConstants.AppToken.tagLength
        guard encryptedToken.count >= minimumLength else {
            throw malformedEncryptedToken("at least \(minimumLength) bytes")
        }

        let headerEnd = encryptedToken.index(
            encryptedToken.startIndex,
            offsetBy: headerLength
        )
        let nonceEnd = encryptedToken.index(
            headerEnd,
            offsetBy: AuthConstants.AppToken.nonceLength
        )
        let tagStart = encryptedToken.index(
            encryptedToken.endIndex,
            offsetBy: -AuthConstants.AppToken.tagLength
        )
        let header = encryptedToken[encryptedToken.startIndex..<headerEnd]
        guard Data(header) == AuthConstants.AppToken.encryptedHeader else {
            throw malformedEncryptedToken("an XYZ-prefixed encrypted token")
        }

        let plaintext = try SwiftDunkCrypto.aesGCMDecrypt(
            ciphertext: Data(encryptedToken[nonceEnd..<tagStart]),
            tag: Data(encryptedToken[tagStart..<encryptedToken.endIndex]),
            key: account.sessionKey,
            nonce: Data(encryptedToken[headerEnd..<nonceEnd]),
            aad: Data(header)
        )
        let root = try AuthPropertyListDecoder.decode(
            plaintext,
            key: "et",
            expected: "a decrypted token property list"
        )
        if let statusValue = root[AuthConstants.AppToken.statusCode] {
            let statusCode = try requireInteger(
                statusValue,
                key: AuthConstants.AppToken.statusCode
            )
            guard statusCode == AuthConstants.AppToken.successStatusCode else {
                throw SwiftDunkError(code: .appTokenRejected(statusCode: statusCode))
            }
        }
        let tokens = try root.requireDictionary("t")
        guard let tokenValues = tokens[name]?.dictionary else {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: name,
                    expected: "an application-token dictionary"
                )
            )
        }
        let token = PlistValue.dictionary(tokenValues)
        let value = try token.requireString("token")
        let createdAt =
            try optionalDate(token["cts"], key: "cts")
            ?? now()
        let expiry: Date
        if let explicitExpiry = try optionalDate(token["expiry"], key: "expiry") {
            expiry = explicitExpiry
        } else {
            let duration = try requireInteger(token["duration"], key: "duration")
            expiry = createdAt.addingTimeInterval(TimeInterval(duration))
        }
        return AppToken(
            name: name,
            value: value,
            expiry: expiry,
            createdAt: createdAt
        )
    }

    private func normalizedName(_ name: String) -> String {
        guard !name.hasPrefix(AuthConstants.AppToken.prefix) else {
            return name
        }
        return AuthConstants.AppToken.prefix + name
    }

    private func optionalDate(_ value: PlistValue?, key: String) throws -> Date? {
        guard let value else { return nil }
        guard let milliseconds = value.integer else {
            throw SwiftDunkError(
                code: .malformedResponse(key: key, expected: "milliseconds since 1970")
            )
        }
        return Date(
            timeIntervalSince1970: Double(milliseconds)
                / AuthConstants.AppToken.millisecondsPerSecond
        )
    }

    private func requireInteger(_ value: PlistValue?, key: String) throws -> Int {
        guard let integer = value?.integer else {
            throw SwiftDunkError(
                code: .malformedResponse(key: key, expected: "an integer")
            )
        }
        return integer
    }

    private func require<Value>(
        _ value: Value?,
        key: String,
        expected: String
    ) throws -> Value {
        guard let value else {
            throw SwiftDunkError(code: .malformedResponse(key: key, expected: expected))
        }
        return value
    }

    private func malformedEncryptedToken(_ expected: String) -> SwiftDunkError {
        SwiftDunkError(code: .malformedResponse(key: "et", expected: expected))
    }
}
