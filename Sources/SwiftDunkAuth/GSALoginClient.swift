import Foundation

struct GSALoginResult: Sendable {
    let material: AccountMaterial
    let authenticationType: String?
}

struct GSALoginClient: Sendable {
    private let anisette: any AnisetteProvider
    private let privateKey: @Sendable () throws -> Data
    private let headerBuilder = AnisetteHeaderBuilder()
    private let requestClient: GSARequestClient

    init(
        anisette: any AnisetteProvider,
        transport: any HTTPTransport,
        privateKey: @escaping @Sendable () throws -> Data
    ) {
        self.anisette = anisette
        self.privateKey = privateKey
        requestClient = GSARequestClient(transport: transport)
    }

    func login(appleID: String, password: String) async throws -> GSALoginResult {
        let normalizedAppleID = appleID.lowercased()
        let keys = AppleSRP.deriveKeys(privateKey: try privateKey())
        let anisetteHeaders = try await anisette.headers()
        let cpd = headerBuilder.cpd(from: anisetteHeaders)
        let endpoint = try authURL(AuthConstants.gsaURL)

        let initResponse: GSAInitResponse = try await requestClient.send(
            GSAInitRequest(
                header: GSARequestHeader(version: AuthConstants.gsaVersion),
                request: .init(
                    publicKey: keys.publicKey,
                    cpd: cpd,
                    operation: AuthConstants.Operation.initialize,
                    protocols: [AuthConstants.SRP.s2k, AuthConstants.SRP.s2kFO],
                    username: normalizedAppleID
                )
            ),
            to: endpoint,
            headers: try headerBuilder.gsaHeaders(
                from: anisetteHeaders,
                closingConnection: false
            )
        )
        try requestClient.checkError(initResponse)

        let salt = try require(initResponse.salt, key: "s", expected: "data")
        let serverPublicKey = try require(
            initResponse.serverPublicKey,
            key: "B",
            expected: "data"
        )
        let iterations = try require(
            initResponse.iterations,
            key: "i",
            expected: "an integer"
        )
        let cookie = try require(initResponse.cookie, key: "c", expected: "a string")
        let protocolName = try require(
            initResponse.protocolName,
            key: "sp",
            expected: "a string"
        )
        let derivedPassword = try AppleSRP.derivePassword(
            password,
            protocolName: protocolName,
            salt: salt,
            iterations: iterations
        )
        let proof = try AppleSRP.calculateProof(
            username: normalizedAppleID,
            salt: salt,
            derivedPassword: derivedPassword,
            serverPublicKey: serverPublicKey,
            keys: keys
        )

        let completeResponse: GSACompleteResponse = try await requestClient.send(
            GSACompleteRequest(
                header: GSARequestHeader(version: AuthConstants.gsaVersion),
                request: .init(
                    proof: proof.clientProof,
                    cookie: cookie,
                    cpd: cpd,
                    operation: AuthConstants.Operation.complete,
                    username: normalizedAppleID
                )
            ),
            to: endpoint,
            headers: try headerBuilder.gsaHeaders(
                from: anisetteHeaders,
                closingConnection: true
            )
        )
        try requestClient.checkError(completeResponse)

        let serverProof = try require(
            completeResponse.serverProof,
            key: "M2",
            expected: "data"
        )
        try AppleSRP.verifyServerProof(serverProof, for: proof)
        let encryptedSPD = try require(
            completeResponse.encryptedSPD,
            key: "spd",
            expected: "encrypted data"
        )
        // both hmac labels include the trailing colon
        let extraDataKey = SwiftDunkCrypto.hmacSHA256(
            key: proof.sessionKey,
            Data(AuthConstants.SessionLabel.extraDataKey.utf8)
        )
        let extraDataIV = SwiftDunkCrypto.hmacSHA256(
            key: proof.sessionKey,
            Data(AuthConstants.SessionLabel.extraDataIV.utf8)
        ).prefix(16)
        let decryptedSPD = try SwiftDunkCrypto.aesCBCDecrypt(
            encryptedSPD,
            key: extraDataKey,
            iv: Data(extraDataIV)
        )
        return try GSALoginResult(
            material: AccountMaterial(
                decryptedSPD: decryptedSPD,
                fallbackAppleID: normalizedAppleID
            ),
            authenticationType: completeResponse.status?.authenticationType
        )
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

    private func authURL(_ value: String) throws -> URL {
        guard let url = URL(string: value) else {
            throw SwiftDunkError(code: .network)
        }
        return url
    }
}
