import Foundation

struct TwoFactorClient: Sendable {
    private let anisette: any AnisetteProvider
    private let transport: any HTTPTransport
    private let headerBuilder = AnisetteHeaderBuilder()

    init(anisette: any AnisetteProvider, transport: any HTTPTransport) {
        self.anisette = anisette
        self.transport = transport
    }

    func sendTrustedDevicePush(material: AccountMaterial) async throws {
        let request = try await request(
            url: AuthConstants.trustedDeviceURL,
            method: .get,
            material: material,
            usesJSON: false
        )
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw SwiftDunkError(
                code: .unexpectedStatusCode(response.statusCode),
                url: request.url
            )
        }
    }

    func trustedPhoneNumbers(material: AccountMaterial) async throws
        -> (numbers: [TrustedPhoneNumber], smsAlreadyPending: Bool)
    {
        var request = try await request(
            url: AuthConstants.authURL,
            method: .get,
            material: material,
            usesJSON: true
        )
        replaceHeader(
            AuthConstants.Header.accept,
            value: AuthConstants.ContentType.json,
            in: &request.headers
        )
        let response = try await transport.send(request)
        guard response.statusCode == 200 || response.statusCode == 201 else {
            throw SwiftDunkError(
                code: .unexpectedStatusCode(response.statusCode),
                url: request.url
            )
        }
        do {
            // 201 means an sms is already on the way
            let extras = try JSONDecoder().decode(AuthenticationExtras.self, from: response.body)
            return (extras.trustedPhoneNumbers, response.statusCode == 201)
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "trustedPhoneNumbers",
                    expected: "an array of trusted phone numbers"
                ),
                underlyingError: error,
                url: request.url
            )
        }
    }

    func sendSMS(phoneNumberID: Int, material: AccountMaterial) async throws {
        let body = SMSVerificationBody(
            phoneNumber: .init(id: phoneNumberID),
            mode: AuthConstants.smsMode,
            securityCode: nil
        )
        var request = try await request(
            url: AuthConstants.sendSMSURL,
            method: .put,
            material: material,
            usesJSON: true
        )
        request.body = try encodeJSON(body, url: request.url)
        let response = try await transport.send(request)
        try checkSMSDeliveryResponse(response, url: request.url)
    }

    func verifyTrustedDeviceCode(_ code: String, material: AccountMaterial) async throws {
        var request = try await request(
            url: AuthConstants.validateURL,
            method: .get,
            material: material,
            usesJSON: false
        )
        request.headers.append((name: AuthConstants.Header.securityCode, value: code))
        let response = try await transport.send(request)
        try checkVerificationResponse(response, url: request.url, decodesPlist: true)
    }

    func verifySMSCode(
        _ code: String,
        phoneNumberID: Int,
        material: AccountMaterial
    ) async throws {
        let body = SMSVerificationBody(
            phoneNumber: .init(id: phoneNumberID),
            mode: AuthConstants.smsMode,
            securityCode: .init(code: code)
        )
        var request = try await request(
            url: AuthConstants.verifySMSURL,
            method: .post,
            material: material,
            usesJSON: true
        )
        request.body = try encodeJSON(body, url: request.url)
        let response = try await transport.send(request)
        try checkVerificationResponse(response, url: request.url, decodesPlist: false)
    }

    private func request(
        url value: String,
        method: HTTPMethod,
        material: AccountMaterial,
        usesJSON: Bool
    ) async throws -> HTTPRequest {
        guard let url = URL(string: value) else {
            throw SwiftDunkError(code: .network)
        }
        let headers = try await anisette.headers()
        return try HTTPRequest(
            url: url,
            method: method,
            headers: headerBuilder.twoFactorHeaders(
                from: headers,
                identityToken: material.identityToken,
                usesJSON: usesJSON
            )
        )
    }

    private func checkVerificationResponse(
        _ response: HTTPResponse,
        url: URL,
        decodesPlist: Bool
    ) throws {
        if response.statusCode == 423 {
            throw SwiftDunkError(code: .twoFactorRateLimited, url: url)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SwiftDunkError(code: .invalidTwoFactorCode, url: url)
        }
        guard decodesPlist else { return }

        let root: PlistValue
        do {
            root = try PropertyListDecoder().decode(PlistValue.self, from: response.body)
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "ec",
                    expected: "a two-factor validation property list"
                ),
                underlyingError: error,
                url: url
            )
        }
        // apple sends this plist both wrapped and bare
        let responseRoot = root["Response"] ?? root
        let errorRoot = responseRoot["Status"] ?? responseRoot
        // 2xx can still carry a nonzero ec
        guard let errorCode = errorRoot["ec"]?.integer else {
            throw SwiftDunkError(
                code: .malformedResponse(key: "ec", expected: "an integer"),
                url: url
            )
        }
        guard errorCode == 0 else {
            throw SwiftDunkError(code: .invalidTwoFactorCode, url: url)
        }
    }

    private func checkSMSDeliveryResponse(_ response: HTTPResponse, url: URL) throws {
        guard !(200..<300).contains(response.statusCode) else { return }

        do {
            let envelope = try JSONDecoder().decode(
                SMSServiceErrorEnvelope.self,
                from: response.body
            )
            guard let error = envelope.serviceErrors.first else {
                throw SMSServiceErrorEnvelopeError.empty
            }
            throw SwiftDunkError(
                code: .twoFactorDeliveryFailed(
                    TwoFactorDeliveryFailure(
                        serviceCode: error.code,
                        title: error.title,
                        message: error.message
                    )
                ),
                url: url
            )
        } catch let error as SwiftDunkError {
            throw error
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "serviceErrors",
                    expected: "a nonempty Apple two-factor service-error array"
                ),
                underlyingError: error,
                url: url
            )
        }
    }

    private func encodeJSON<Value: Encodable>(_ value: Value, url: URL) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(key: "request", expected: "encodable JSON"),
                underlyingError: error,
                url: url
            )
        }
    }

    private func replaceHeader(
        _ name: String,
        value: String,
        in headers: inout [(name: String, value: String)]
    ) {
        headers.removeAll {
            $0.name.compare(name, options: .caseInsensitive) == .orderedSame
        }
        headers.append((name: name, value: value))
    }
}

private enum SMSServiceErrorEnvelopeError: Error {
    case empty
}
