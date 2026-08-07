import Crypto
import Foundation
import SRP
import SwiftDunk

enum AuthenticationRequestKind: Sendable, Equatable {
    case grandSlam
    case trustedValidation
    case smsRequest
    case smsValidation
}

actor AuthenticationRequestBarrier {
    private var hasBlockedRequest = false
    private var isReleased = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var entryContinuations: [CheckedContinuation<Void, Never>] = []

    func blockNextRequest() async {
        guard !hasBlockedRequest else { return }
        hasBlockedRequest = true

        let continuations = entryContinuations
        entryContinuations.removeAll()
        for continuation in continuations {
            continuation.resume()
        }

        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        if hasBlockedRequest {
            return
        }
        await withCheckedContinuation { continuation in
            entryContinuations.append(continuation)
        }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

enum TestGSAError: Sendable {
    case root(code: Int, message: String)
    case status(code: Int, message: String)

    var code: Int {
        switch self {
        case .root(let code, _), .status(let code, _):
            code
        }
    }

    var message: String {
        switch self {
        case .root(_, let message), .status(_, let message):
            message
        }
    }

    var isNested: Bool {
        if case .status = self { return true }
        return false
    }
}

struct TestSRPServer {
    let configuration: SRPConfiguration<SHA256>
    let server: SRPServer<SHA256>
    let verifier: SRPKey
    let keys: SRPKeyPair
}

struct AuthenticationExtrasFixture: Encodable {
    let trustedPhoneNumbers: [TrustedPhoneNumber]
}

struct SMSBodyFixture: Decodable {
    let phoneNumber: PhoneNumber
    let mode: String
    let securityCode: SecurityCode?

    struct PhoneNumber: Decodable {
        let id: Int
    }

    struct SecurityCode: Decodable {
        let code: String
    }
}

extension HTTPRequest {
    func header(_ name: String) -> String? {
        headers.first {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }?.value
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
