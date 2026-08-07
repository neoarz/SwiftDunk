import BigNum
import Crypto
import Foundation
import SRP
import SwiftDunk
import SwiftDunkTestSupport
import Testing
import _CryptoExtras

actor GrandSlamScenario {
    private let password: String
    private let authenticationTypes: [String?]
    private let protocolName: String
    private let phoneNumbers: [TrustedPhoneNumber]
    private let verificationStatus: Int
    private let failFirstRerun: Bool
    private let omitInitSalt: Bool
    private let omitGSAErrorCode: Bool
    private let gsaError: TestGSAError?
    private let gsaStatusCode: Int
    private let blockedRequest: AuthenticationRequestKind?
    private let requestBarrier: AuthenticationRequestBarrier?
    private var trustedDeliveryResponses: [HTTPResponse]
    private var smsDeliveryResponses: [HTTPResponse]
    private let salt = Data([
        0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77,
        0x88, 0x99, 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF,
    ])
    private let iterations = 1_000
    private let serverPrivateKey = Data(repeating: 0x5E, count: 32)
    private let cookie = "test-cookie"

    private var roundIndex = 0
    private var currentClientPublicKey: Data?
    private var failedRerun = false

    private(set) var requestCount = 0
    private(set) var gsaInitCount = 0
    private(set) var gsaCompleteCount = 0
    private(set) var trustedPushCount = 0
    private(set) var authExtrasCount = 0
    private(set) var sendSMSCount = 0
    private(set) var trustedValidationCount = 0
    private(set) var smsValidationCount = 0
    private(set) var sentPhoneNumberIDs: [Int] = []
    private(set) var submittedCodes: [String] = []
    private(set) var sendSMSBodies: [Data] = []
    private(set) var verifySMSBodies: [Data] = []

    init(
        password: String = SRPVectors.passwordDerivation.password,
        authenticationTypes: [String?],
        protocolName: String = "s2k",
        verificationStatus: Int = 200,
        failFirstRerun: Bool = false,
        omitInitSalt: Bool = false,
        omitGSAErrorCode: Bool = false,
        gsaError: TestGSAError? = nil,
        gsaStatusCode: Int = 200,
        blockedRequest: AuthenticationRequestKind? = nil,
        requestBarrier: AuthenticationRequestBarrier? = nil,
        trustedDeliveryResponses: [HTTPResponse] = [],
        smsDeliveryResponses: [HTTPResponse] = [],
        phoneNumbers: [TrustedPhoneNumber] = [
            .init(
                id: 7,
                numberWithDialCode: "+1 ••• ••• ••42",
                lastTwoDigits: "42",
                pushMode: "sms"
            )
        ]
    ) {
        self.password = password
        self.authenticationTypes = authenticationTypes
        self.protocolName = protocolName
        self.verificationStatus = verificationStatus
        self.failFirstRerun = failFirstRerun
        self.omitInitSalt = omitInitSalt
        self.omitGSAErrorCode = omitGSAErrorCode
        self.gsaError = gsaError
        self.gsaStatusCode = gsaStatusCode
        self.blockedRequest = blockedRequest
        self.requestBarrier = requestBarrier
        self.trustedDeliveryResponses = trustedDeliveryResponses
        self.smsDeliveryResponses = smsDeliveryResponses
        self.phoneNumbers = phoneNumbers
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requestCount += 1
        if requestKind(for: request) == blockedRequest, let requestBarrier {
            await requestBarrier.blockNextRequest()
            try Task.checkCancellation()
        }

        switch (request.url.path, request.method) {
        case ("/grandslam/GsService2", .post):
            return try gsaResponse(for: request)
        case ("/auth/verify/trusteddevice", .get):
            trustedPushCount += 1
            try verifyTwoFactorHeaders(request, usesJSON: false)
            if !trustedDeliveryResponses.isEmpty {
                return trustedDeliveryResponses.removeFirst()
            }
            return HTTPResponse(statusCode: 200)
        case ("/auth", .get):
            authExtrasCount += 1
            try verifyTwoFactorHeaders(request, usesJSON: true)
            return try jsonResponse(AuthenticationExtrasFixture(trustedPhoneNumbers: phoneNumbers))
        case ("/auth/verify/phone", .put):
            sendSMSCount += 1
            try verifyTwoFactorHeaders(request, usesJSON: true)
            sendSMSBodies.append(try #require(request.body))
            let body = try decodeSMSBody(request)
            sentPhoneNumberIDs.append(body.phoneNumber.id)
            #expect(body.mode == "sms")
            #expect(body.securityCode == nil)
            if !smsDeliveryResponses.isEmpty {
                return smsDeliveryResponses.removeFirst()
            }
            return HTTPResponse(statusCode: 200)
        case ("/grandslam/GsService2/validate", .get):
            trustedValidationCount += 1
            try verifyTwoFactorHeaders(request, usesJSON: false)
            let code = try #require(request.header("security-code"))
            submittedCodes.append(code)
            return try plistResponse(
                .dictionary([
                    "Status": .dictionary([
                        "ec": .integer(verificationStatus == 200 ? 0 : -1),
                        "em": .string("verification failed"),
                    ])
                ]),
                statusCode: verificationStatus
            )
        case ("/auth/verify/phone/securitycode", .post):
            smsValidationCount += 1
            try verifyTwoFactorHeaders(request, usesJSON: true)
            verifySMSBodies.append(try #require(request.body))
            let body = try decodeSMSBody(request)
            sentPhoneNumberIDs.append(body.phoneNumber.id)
            submittedCodes.append(try #require(body.securityCode?.code))
            return HTTPResponse(statusCode: verificationStatus)
        default:
            Issue.record("Unexpected authentication request: \(request.method) \(request.url)")
            return HTTPResponse(statusCode: 500)
        }
    }

    private func gsaResponse(for request: HTTPRequest) throws -> HTTPResponse {
        let body = try #require(request.body)
        let root = try PropertyListDecoder().decode(PlistValue.self, from: body)
        let requestBody = try root.requireDictionary("Request")
        let operation = try PlistValue.dictionary(requestBody).requireString("o")

        switch operation {
        case "init":
            gsaInitCount += 1
            if failFirstRerun, roundIndex == 1, !failedRerun {
                failedRerun = true
                throw SwiftDunkError(code: .network)
            }
            try verifyGSARequest(request, root: root, closesConnection: false)
            #expect(
                requestBody["ps"]?.array?.compactMap(\.string) == ["s2k", "s2k_fo"]
            )
            if let gsaError {
                let values: [String: PlistValue] = [
                    "ec": .integer(gsaError.code),
                    "em": .string(gsaError.message),
                ]
                let response =
                    gsaError.isNested
                    ? ["Status": PlistValue.dictionary(values)]
                    : values
                return try plistResponse(
                    .dictionary(["Response": .dictionary(response)]),
                    statusCode: gsaStatusCode
                )
            }
            let publicKey = try PlistValue.dictionary(requestBody).requireData("A2k")
            currentClientPublicKey = publicKey
            let server = try makeServer()
            var response: [String: PlistValue] = [
                "B": .data(Data(server.keys.public.bytes)),
                "i": .integer(iterations),
                "c": .string(cookie),
                "sp": .string(protocolName),
                "Status": successStatus(authenticationTypes[safe: roundIndex] ?? nil),
            ]
            if !omitInitSalt {
                response["s"] = .data(salt)
            }
            return try plistResponse(
                .dictionary(["Response": .dictionary(response)]),
                statusCode: gsaStatusCode
            )

        case "complete":
            gsaCompleteCount += 1
            try verifyGSARequest(request, root: root, closesConnection: true)
            #expect(try PlistValue.dictionary(requestBody).requireString("c") == cookie)
            let clientProof = try PlistValue.dictionary(requestBody).requireData("M1")
            let clientPublicKey = try #require(currentClientPublicKey)
            let server = try makeServer()
            let publicKey = SRPKey(clientPublicKey, padding: server.configuration.sizeN)
            let sharedSecret = try server.server.calculateSharedSecret(
                clientPublicKey: publicKey,
                serverKeys: server.keys,
                verifier: server.verifier
            )
            let serverProof = try server.server.verifyClientProof(
                proof: [UInt8](clientProof),
                username: "user@example.com",
                salt: [UInt8](salt),
                clientPublicKey: publicKey,
                serverPublicKey: server.keys.public,
                sharedSecret: sharedSecret
            )
            let sessionKey = Data(SHA256.hash(data: sharedSecret.bytes))
            let encryptedSPD = try encryptedSPD(sessionKey: sessionKey)
            let authenticationType = authenticationTypes[safe: roundIndex] ?? nil
            roundIndex += 1
            return try plistResponse(
                .dictionary([
                    "Response": .dictionary([
                        "M2": .data(Data(serverProof)),
                        "spd": .data(encryptedSPD),
                        "Status": successStatus(authenticationType),
                    ])
                ]),
                statusCode: gsaStatusCode
            )

        default:
            Issue.record("Unexpected GSA operation: \(operation)")
            return HTTPResponse(statusCode: 500)
        }
    }

    private func makeServer() throws -> TestSRPServer {
        let configuration = SRPConfiguration<SHA256>(.N2048)
        let derivationProtocol =
            protocolName == "s2k_fo" ? protocolName : "s2k"
        let derived = try AppleSRP.derivePassword(
            password,
            protocolName: derivationProtocol,
            salt: salt,
            iterations: iterations
        )
        let passwordHash = Data(SHA256.hash(data: Data([0x3A]) + derived))
        let x = BigNum(bytes: SHA256.hash(data: salt + passwordHash))
        let verifierNumber = configuration.g.power(x, modulus: configuration.N)
        let verifier = SRPKey(verifierNumber.bytes, padding: configuration.sizeN)
        let privateKey = SRPKey(serverPrivateKey)
        let publicNumber =
            (configuration.k * verifierNumber
                + configuration.g.power(privateKey.number, modulus: configuration.N))
            % configuration.N
        let keys = SRPKeyPair(
            public: SRPKey(publicNumber.bytes, padding: configuration.sizeN),
            private: privateKey
        )
        return TestSRPServer(
            configuration: configuration,
            server: SRPServer(configuration: configuration),
            verifier: verifier,
            keys: keys
        )
    }

    private func encryptedSPD(sessionKey: Data) throws -> Data {
        let value = PlistValue.dictionary([
            "adsid": .string("1234567890"),
            "GsIdmsToken": .string("idms-token"),
            "sk": .data(Data(repeating: 0xA5, count: 32)),
            "c": .data(Data([0xCA, 0xFE])),
            "fn": .string("Taylor"),
            "ln": .string("Appleseed"),
        ])
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let plaintext = try encoder.encode(value)
        let key = Data(
            HMAC<SHA256>.authenticationCode(
                for: Data("extra data key:".utf8),
                using: SymmetricKey(data: sessionKey)
            )
        )
        let ivData = Data(
            HMAC<SHA256>.authenticationCode(
                for: Data("extra data iv:".utf8),
                using: SymmetricKey(data: sessionKey)
            )
        ).prefix(16)
        return try AES._CBC.encrypt(
            plaintext,
            using: SymmetricKey(data: key),
            iv: AES._CBC.IV(ivBytes: ivData)
        )
    }

    private func verifyGSARequest(
        _ request: HTTPRequest,
        root: PlistValue,
        closesConnection: Bool
    ) throws {
        #expect(request.header("Content-Type") == "text/x-xml-plist")
        #expect(request.header("Accept") == "*/*")
        #expect(request.header("User-Agent") == "akd/1.0 CFNetwork/978.0.7 Darwin/18.7.0")
        #expect(request.header("X-MMe-Client-Info") == "<TestMac> <macOS;1> <Remote>")
        let clientInfoHeaders = request.headers.filter {
            $0.name.compare("X-MMe-Client-Info", options: .caseInsensitive) == .orderedSame
        }
        #expect(clientInfoHeaders.count == 1)
        #expect(clientInfoHeaders.first?.name == "X-MMe-Client-Info")
        #expect(clientInfoHeaders.first?.value == "<TestMac> <macOS;1> <Remote>")
        #expect((request.header("Connection") == "close") == closesConnection)
        #expect(root["Header"]?["Version"]?.string == "1.0.1")
        let requestBody = try root.requireDictionary("Request")
        #expect(try PlistValue.dictionary(requestBody).requireString("u") == "user@example.com")
        let cpd = try PlistValue.dictionary(requestBody).requireDictionary("cpd")
        #expect(cpd["bootstrap"]?.string == "true")
        #expect(cpd["loc"]?.string == "en_GB")
        #expect(cpd["X-Mme-Client-Info"] == nil)
    }

    private func verifyTwoFactorHeaders(_ request: HTTPRequest, usesJSON: Bool) throws {
        let contentType = usesJSON ? "application/json" : "text/x-xml-plist"
        #expect(request.header("Content-Type") == contentType)
        #expect(request.header("Accept") == contentType)
        #expect(request.header("User-Agent") == "Xcode")
        #expect(request.header("Accept-Language") == "en-us")
        #expect(request.header("Loc") == "en_US")
        #expect(request.header("X-Apple-App-Info") == "com.apple.gs.xcode.auth")
        #expect(request.header("X-Xcode-Version") == "11.2 (11B41)")
        #expect(request.header("X-Apple-I-MD-RINFO") == "17106176")
        #expect(
            request.header("X-Mme-Client-Info")
                == "<TestMac> <macOS;1> <com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)>"
        )
        let clientInfoHeaders = request.headers.filter {
            $0.name.compare("X-Mme-Client-Info", options: .caseInsensitive) == .orderedSame
        }
        #expect(clientInfoHeaders.count == 1)
        #expect(clientInfoHeaders.first?.name == "X-Mme-Client-Info")
        #expect(
            clientInfoHeaders.first?.value
                == "<TestMac> <macOS;1> "
                + "<com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)>"
        )
        #expect(
            request.header("X-Apple-Identity-Token")
                == Data("1234567890:idms-token".utf8).base64EncodedString()
        )
    }

    private func decodeSMSBody(_ request: HTTPRequest) throws -> SMSBodyFixture {
        try JSONDecoder().decode(SMSBodyFixture.self, from: try #require(request.body))
    }

    private func requestKind(for request: HTTPRequest) -> AuthenticationRequestKind? {
        switch (request.url.path, request.method) {
        case ("/grandslam/GsService2", .post):
            .grandSlam
        case ("/grandslam/GsService2/validate", .get):
            .trustedValidation
        case ("/auth/verify/phone", .put):
            .smsRequest
        case ("/auth/verify/phone/securitycode", .post):
            .smsValidation
        default:
            nil
        }
    }

    private func successStatus(_ authenticationType: String?) -> PlistValue {
        var status: [String: PlistValue] = ["em": .string("OK")]
        if !omitGSAErrorCode {
            status["ec"] = .integer(0)
        }
        if let authenticationType {
            status["au"] = .string(authenticationType)
        }
        return .dictionary(status)
    }

    private func plistResponse(
        _ value: PlistValue,
        statusCode: Int = 200
    ) throws -> HTTPResponse {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return HTTPResponse(statusCode: statusCode, body: try encoder.encode(value))
    }

    private func jsonResponse<Value: Encodable>(_ value: Value) throws -> HTTPResponse {
        HTTPResponse(statusCode: 200, body: try JSONEncoder().encode(value))
    }
}
