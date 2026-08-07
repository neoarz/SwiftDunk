struct RemoteClientInfo: Decodable, Sendable {
    let clientInfo: String
    let userAgent: String

    enum CodingKeys: String, CodingKey {
        case clientInfo = "client_info"
        case userAgent = "user_agent"
    }
}

struct GetHeadersRequest: Encodable, Sendable {
    let identifier: String
    let adiPB: String

    enum CodingKeys: String, CodingKey {
        case identifier
        case adiPB = "adi_pb"
    }
}

struct GetHeadersResponse: Decodable, Sendable {
    let result: String
    let message: String?
    let machineID: String?
    let oneTimePassword: String?
    let routingInfo: String?

    enum CodingKeys: String, CodingKey {
        case result
        case message
        case machineID = "X-Apple-I-MD-M"
        case oneTimePassword = "X-Apple-I-MD"
        case routingInfo = "X-Apple-I-MD-RINFO"
    }
}

struct ProvisioningMessage: Decodable, Sendable {
    let result: String
    let cpim: String?
    let adiPB: String?

    enum CodingKeys: String, CodingKey {
        case result
        case cpim
        case adiPB = "adi_pb"
    }
}

struct IdentifierMessage: Encodable, Sendable {
    let identifier: String
}

struct StartProvisioningMessage: Encodable, Sendable {
    let spim: String
}

struct EndProvisioningMessage: Encodable, Sendable {
    let ptm: String
    let tk: String
}

enum RemoteAnisetteProtocolError: Error {
    case staleProvisioning
}
