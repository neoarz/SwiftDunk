import Crypto
import Foundation
import SwiftDunk
import SwiftDunkTestSupport
import Testing

@Suite("GrandSlam application tokens")
struct AppTokenTests {
    @Test("A golden et envelope without status-code remains valid")
    func decryptsGoldenToken() async throws {
        let scenario = AppTokenScenario(
            encryptedToken: try TestData.hex(AppTokenVectors.encryptedToken)
        )
        let account = makeAccount(scenario: scenario)

        let token = try await account.appToken("xcode.auth")

        #expect(token.name == AppTokenVectors.applicationName)
        #expect(token.value == AppTokenVectors.tokenValue)
        #expect(
            token.createdAt
                == Date(
                    timeIntervalSince1970: Double(AppTokenVectors.createdAtMilliseconds) / 1_000
                )
        )
        #expect(
            token.expiry
                == Date(
                    timeIntervalSince1970: Double(AppTokenVectors.expiryMilliseconds) / 1_000
                )
        )
        #expect(await scenario.requestCount == 1)
    }

    @Test("A successful inner status-code is accepted")
    func acceptsSuccessfulStatusCode() async throws {
        let scenario = AppTokenScenario(
            encryptedToken: try encryptedToken(
                statusCode: .integer(200),
                duration: nil,
                expiry: .integer(AppTokenVectors.expiryMilliseconds)
            )
        )

        let token = try await makeAccount(scenario: scenario).appToken("xcode.auth")

        #expect(token.value == AppTokenVectors.tokenValue)
    }

    @Test("A rejected inner status-code is surfaced")
    func rejectsFailedStatusCode() async throws {
        let scenario = AppTokenScenario(
            encryptedToken: try encryptedToken(
                statusCode: .integer(500),
                duration: nil,
                expiry: .integer(AppTokenVectors.expiryMilliseconds)
            )
        )

        await #expect {
            try await makeAccount(scenario: scenario).appToken("xcode.auth")
        } throws: { error in
            (error as? SwiftDunkError)?.code == .appTokenRejected(statusCode: 500)
        }
    }

    @Test("A malformed inner status-code names the wire key")
    func rejectsMalformedStatusCode() async throws {
        let scenario = AppTokenScenario(
            encryptedToken: try encryptedToken(
                statusCode: .string("success"),
                duration: nil,
                expiry: .integer(AppTokenVectors.expiryMilliseconds)
            )
        )

        await #expect {
            try await makeAccount(scenario: scenario).appToken("xcode.auth")
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .malformedResponse(key: "status-code", expected: "an integer")
        }
    }

    @Test("An already-normalized application name is not prefixed twice")
    func preservesNormalizedName() async throws {
        let scenario = AppTokenScenario(
            encryptedToken: try TestData.hex(AppTokenVectors.encryptedToken)
        )

        let token = try await makeAccount(scenario: scenario)
            .appToken(AppTokenVectors.applicationName)

        #expect(token.name == AppTokenVectors.applicationName)
    }

    @Test("A malformed et header is rejected descriptively")
    func rejectsMalformedEnvelope() async {
        let scenario = AppTokenScenario(
            encryptedToken: Data(repeating: 0, count: 35)
        )

        await #expect {
            try await makeAccount(scenario: scenario).appToken("xcode.auth")
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .malformedResponse(
                    key: "et",
                    expected: "an XYZ-prefixed encrypted token"
                )
        }
    }

    @Test("A missing et field identifies the wire key")
    func rejectsMissingEncryptedToken() async {
        let scenario = AppTokenScenario(encryptedToken: nil)

        await #expect {
            try await makeAccount(scenario: scenario).appToken("xcode.auth")
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .malformedResponse(key: "et", expected: "encrypted token data")
        }
    }

    @Test("An explicit expiry does not require a duration")
    func explicitExpiryWithoutDuration() async throws {
        let scenario = AppTokenScenario(
            encryptedToken: try encryptedToken(
                duration: nil,
                expiry: .integer(AppTokenVectors.expiryMilliseconds)
            )
        )

        let token = try await makeAccount(scenario: scenario).appToken("xcode.auth")

        #expect(
            token.expiry
                == Date(
                    timeIntervalSince1970: Double(AppTokenVectors.expiryMilliseconds) / 1_000
                )
        )
    }

    @Test("A token without expiry or duration names the missing duration")
    func missingExpiryAndDuration() async throws {
        let scenario = AppTokenScenario(
            encryptedToken: try encryptedToken(duration: nil, expiry: nil)
        )

        await #expect {
            try await makeAccount(scenario: scenario).appToken("xcode.auth")
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .malformedResponse(key: "duration", expected: "an integer")
        }
    }

    private func makeAccount(scenario: AppTokenScenario) -> Account {
        Account(
            appleID: "user@example.com",
            firstName: "Taylor",
            lastName: "Appleseed",
            dsid: AppTokenVectors.dsid,
            idmsToken: "fixture-idms-token",
            sessionKey: AppTokenVectors.sessionKey,
            context: AppTokenVectors.context,
            anisette: .mock,
            transport: MockTransport { request in
                try await scenario.send(request)
            }
        )
    }

    private func encryptedToken(
        statusCode: PlistValue? = nil,
        duration: PlistValue?,
        expiry: PlistValue?
    ) throws -> Data {
        var token: [String: PlistValue] = [
            "token": .string(AppTokenVectors.tokenValue),
            "cts": .integer(AppTokenVectors.createdAtMilliseconds),
        ]
        token["duration"] = duration
        token["expiry"] = expiry

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        var root: [String: PlistValue] = [
            "t": .dictionary([
                AppTokenVectors.applicationName: .dictionary(token)
            ])
        ]
        root["status-code"] = statusCode
        let plaintext = try encoder.encode(PlistValue.dictionary(root))
        let header = Data("XYZ".utf8)
        let nonceData = Data((0..<16).map(UInt8.init))
        let sealed = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: AppTokenVectors.sessionKey),
            nonce: AES.GCM.Nonce(data: nonceData),
            authenticating: header
        )
        return header + nonceData + sealed.ciphertext + sealed.tag
    }
}

private actor AppTokenScenario {
    private let encryptedToken: Data?
    private(set) var requestCount = 0

    init(encryptedToken: Data?) {
        self.encryptedToken = encryptedToken
    }

    func send(_ request: HTTPRequest) throws -> HTTPResponse {
        requestCount += 1
        #expect(request.url.absoluteString == "https://gsa.apple.com/grandslam/GsService2")
        #expect(request.method == .post)
        #expect(request.header(named: "Content-Type") == "text/x-xml-plist")
        #expect(request.header(named: "Accept") == "*/*")
        #expect(request.header(named: "X-MMe-Client-Info") == "<Test> <macOS;0;0> <SwiftDunkTests>")

        let body = try #require(request.body)
        let root = try PropertyListDecoder().decode(PlistValue.self, from: body)
        #expect(root["Header"]?["Version"]?.string == "1.0.1")
        let values = try root.requireDictionary("Request")
        let requestBody = PlistValue.dictionary(values)
        #expect(
            requestBody["app"]?.array?.compactMap(\.string) == [AppTokenVectors.applicationName])
        #expect(try requestBody.requireData("c") == AppTokenVectors.context)
        #expect(try requestBody.requireData("checksum") == TestData.hex(AppTokenVectors.checksum))
        #expect(try requestBody.requireString("o") == "apptokens")
        #expect(try requestBody.requireString("t") == "fixture-idms-token")
        #expect(try requestBody.requireString("u") == AppTokenVectors.dsid)
        #expect(try requestBody.requireDictionary("cpd")["bootstrap"]?.string == "true")

        var response: [String: PlistValue] = [
            "Status": .dictionary(["ec": .integer(0)])
        ]
        if let encryptedToken {
            response["et"] = .data(encryptedToken)
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try HTTPResponse(
            statusCode: 200,
            body: encoder.encode(
                PlistValue.dictionary(["Response": .dictionary(response)])
            )
        )
    }
}

private extension HTTPRequest {
    func header(named name: String) -> String? {
        headers.first {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }?.value
    }
}
