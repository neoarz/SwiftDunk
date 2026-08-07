import Foundation

struct GSARequestClient: Sendable {
    private let transport: any HTTPTransport

    init(transport: any HTTPTransport) {
        self.transport = transport
    }

    func send<Request: Encodable, Response: Decodable & GSAErrorResponse>(
        _ body: Request,
        to url: URL,
        headers: [(name: String, value: String)]
    ) async throws -> Response {
        let encoded: Data
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            encoded = try encoder.encode(body)
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "Request",
                    expected: "an encodable GrandSlam property list"
                ),
                underlyingError: error,
                url: url
            )
        }

        let response = try await transport.send(
            HTTPRequest(url: url, method: .post, headers: headers, body: encoded)
        )
        do {
            let decoded = try PropertyListDecoder().decode(
                GSAResponseEnvelope<Response>.self,
                from: response.body
            ).response
            guard (200..<300).contains(response.statusCode) else {
                if let code = grandSlamError(from: decoded) {
                    throw SwiftDunkError(code: code, url: url)
                }
                throw SwiftDunkError(
                    code: .unexpectedStatusCode(response.statusCode),
                    url: url
                )
            }
            return decoded
        } catch let error as SwiftDunkError {
            throw error
        } catch {
            if !(200..<300).contains(response.statusCode) {
                throw SwiftDunkError(
                    code: .unexpectedStatusCode(response.statusCode),
                    underlyingError: error,
                    url: url
                )
            }
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "Response",
                    expected: "a GrandSlam property-list dictionary"
                ),
                underlyingError: error,
                url: url
            )
        }
    }

    // http 200 can still carry ec under Status or at the root
    func checkError(_ response: some GSAErrorResponse) throws {
        guard (response.status?.errorCode ?? response.errorCode) != nil else {
            throw SwiftDunkError(
                code: .malformedResponse(key: "ec", expected: "an integer")
            )
        }
        if let code = grandSlamError(from: response) {
            throw SwiftDunkError(code: code)
        }
    }

    private func grandSlamError(
        from response: some GSAErrorResponse
    ) -> SwiftDunkError.Code? {
        guard let errorCode = response.status?.errorCode ?? response.errorCode,
            errorCode != 0
        else {
            return nil
        }
        return .grandSlam(
            code: errorCode,
            message: response.status?.errorMessage
                ?? response.errorMessage
                ?? "Unknown GrandSlam error"
        )
    }
}
