import Foundation
import SwiftDunkAuth

enum V1Method: Sendable, Equatable {
    case get
    case post
    case patch

    var transportMethod: HTTPMethod {
        switch self {
        case .get, .post:
            .post
        case .patch:
            .patch
        }
    }
}

struct V1Client: Sendable {
    private let anisette: any AnisetteProvider
    private let credentials: PortalCredentials
    private let transport: any HTTPTransport
    private let headerBuilder = PortalHeaderBuilder()

    init(
        anisette: any AnisetteProvider,
        credentials: PortalCredentials,
        transport: any HTTPTransport
    ) {
        self.anisette = anisette
        self.credentials = credentials
        self.transport = transport
    }

    func send<Request: Encodable & Sendable, Response: Decodable & Sendable>(
        path: String,
        method: V1Method,
        body: Request,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let url = try PortalConstants.url(path: path)
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(body)
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "request",
                    expected: "an encodable v1 JSON document"
                ),
                underlyingError: error,
                url: url
            )
        }
        var headers = [
            (
                name: PortalConstants.Header.contentType,
                value: PortalConstants.ContentType.jsonAPI
            ),
            (
                name: PortalConstants.Header.accept,
                value: PortalConstants.ContentType.jsonAccept
            ),
            (
                name: PortalConstants.Header.requestedWith,
                value: PortalConstants.ContentType.xmlHTTPRequest
            ),
        ]
        if method == .get {
            headers.append(
                (
                    name: PortalConstants.Header.methodOverride,
                    value: PortalConstants.V1.get
                )
            )
        }
        headers += try headerBuilder.commonHeaders(
            anisette: try await anisette.headers(),
            credentials: credentials
        )
        let response = try await transport.send(
            HTTPRequest(
                url: url,
                method: method.transportMethod,
                headers: headers,
                body: encoded
            )
        )

        if let errorResponse = try? JSONDecoder().decode(V1ErrorResponse.self, from: response.body),
            let error = errorResponse.errors.first
        {
            throw SwiftDunkError(
                code: .developerAPI(
                    resultCode: error.resultCode,
                    httpCode: Int(error.status),
                    message: error.detail
                        ?? error.title
                        ?? PortalConstants.unknownAPIError
                ),
                underlyingError: error,
                url: url
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SwiftDunkError(
                code: .unexpectedStatusCode(response.statusCode),
                url: url
            )
        }
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "data",
                    expected: "the v1 JSON response for \(path)"
                ),
                underlyingError: error,
                url: url
            )
        }
    }
}

private struct V1ErrorResponse: Decodable {
    let errors: [V1Error]
}

struct V1Error: Decodable, Error, Sendable {
    let code: String?
    let detail: String?
    let id: String?
    let resultCode: Int
    let status: String
    let title: String?

    private enum CodingKeys: String, CodingKey {
        case code
        case detail
        case id
        case resultCode
        case status
        case title
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        resultCode = try container.decode(Int.self, forKey: .resultCode)
        title = try container.decodeIfPresent(String.self, forKey: .title)

        if let stringStatus = try? container.decode(String.self, forKey: .status) {
            status = stringStatus
        } else {
            status = String(try container.decode(Int.self, forKey: .status))
        }
    }
}
