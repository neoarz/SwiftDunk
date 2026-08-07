import Foundation

struct GSARequestHeader: Codable, Sendable {
    let version: String

    enum CodingKeys: String, CodingKey {
        case version = "Version"
    }
}

struct GSAInitRequest: Codable, Sendable {
    let header: GSARequestHeader
    let request: Body

    struct Body: Codable, Sendable {
        let publicKey: Data
        let cpd: [String: PlistValue]
        let operation: String
        let protocols: [String]
        let username: String

        enum CodingKeys: String, CodingKey {
            case publicKey = "A2k"
            case cpd
            case operation = "o"
            case protocols = "ps"
            case username = "u"
        }
    }

    enum CodingKeys: String, CodingKey {
        case header = "Header"
        case request = "Request"
    }
}

struct GSACompleteRequest: Codable, Sendable {
    let header: GSARequestHeader
    let request: Body

    struct Body: Codable, Sendable {
        let proof: Data
        let cookie: String
        let cpd: [String: PlistValue]
        let operation: String
        let username: String

        enum CodingKeys: String, CodingKey {
            case proof = "M1"
            case cookie = "c"
            case cpd
            case operation = "o"
            case username = "u"
        }
    }

    enum CodingKeys: String, CodingKey {
        case header = "Header"
        case request = "Request"
    }
}

struct GSAResponseEnvelope<Body: Decodable & Sendable>: Decodable, Sendable {
    let response: Body

    enum CodingKeys: String, CodingKey {
        case response = "Response"
    }
}

struct GSAStatus: Decodable, Sendable {
    let errorCode: Int?
    let errorMessage: String?
    let authenticationType: String?

    enum CodingKeys: String, CodingKey {
        case errorCode = "ec"
        case errorMessage = "em"
        case authenticationType = "au"
    }
}

protocol GSAErrorResponse: Sendable {
    var status: GSAStatus? { get }
    var errorCode: Int? { get }
    var errorMessage: String? { get }
}

struct GSAInitResponse: Decodable, Sendable, GSAErrorResponse {
    let salt: Data?
    let serverPublicKey: Data?
    let iterations: Int?
    let cookie: String?
    let protocolName: String?
    let status: GSAStatus?
    let errorCode: Int?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case salt = "s"
        case serverPublicKey = "B"
        case iterations = "i"
        case cookie = "c"
        case protocolName = "sp"
        case status = "Status"
        case errorCode = "ec"
        case errorMessage = "em"
    }
}

struct GSACompleteResponse: Decodable, Sendable, GSAErrorResponse {
    let serverProof: Data?
    let encryptedSPD: Data?
    let status: GSAStatus?
    let errorCode: Int?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case serverProof = "M2"
        case encryptedSPD = "spd"
        case status = "Status"
        case errorCode = "ec"
        case errorMessage = "em"
    }
}

struct GSAAppTokenRequest: Codable, Sendable {
    let header: GSARequestHeader
    let request: Body

    struct Body: Codable, Sendable {
        let apps: [String]
        let context: Data
        let checksum: Data
        let cpd: [String: PlistValue]
        let operation: String
        let token: String
        let dsid: String

        enum CodingKeys: String, CodingKey {
            case apps = "app"
            case context = "c"
            case checksum
            case cpd
            case operation = "o"
            case token = "t"
            case dsid = "u"
        }
    }

    enum CodingKeys: String, CodingKey {
        case header = "Header"
        case request = "Request"
    }
}

struct GSAAppTokenResponse: Decodable, Sendable, GSAErrorResponse {
    let encryptedToken: Data?
    let status: GSAStatus?
    let errorCode: Int?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case encryptedToken = "et"
        case status = "Status"
        case errorCode = "ec"
        case errorMessage = "em"
    }
}

struct AuthenticationExtras: Decodable, Sendable {
    let trustedPhoneNumbers: [TrustedPhoneNumber]
}

struct SMSServiceErrorEnvelope: Decodable, Sendable {
    let serviceErrors: [SMSServiceError]
}

struct SMSServiceError: Decodable, Sendable {
    let code: Int
    let title: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case code
        case title
        case message
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(Int.self, forKey: .code) {
            code = value
        } else {
            let value = try container.decode(String.self, forKey: .code)
            guard let parsed = Int(value) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .code,
                    in: container,
                    debugDescription: "Expected a decimal Apple service-error code."
                )
            }
            code = parsed
        }
        title = try container.decodeIfPresent(String.self, forKey: .title)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

struct SMSVerificationBody: Encodable, Sendable {
    let phoneNumber: PhoneNumber
    let mode: String
    let securityCode: SecurityCode?

    enum CodingKeys: String, CodingKey {
        case phoneNumber
        case mode
        case securityCode
    }

    // synthesized Encodable drops nil, but this request needs "securityCode": null
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(phoneNumber, forKey: .phoneNumber)
        try container.encode(mode, forKey: .mode)
        try container.encode(securityCode, forKey: .securityCode)
    }

    struct PhoneNumber: Encodable, Sendable {
        let id: Int
    }

    struct SecurityCode: Encodable, Sendable {
        let code: String
    }
}
