public import Foundation
#if canImport(FoundationNetworking)
    public import FoundationNetworking
#endif

/// An HTTP method used by SwiftDunk's transport seam.
public enum HTTPMethod: String, Sendable {
    /// Retrieves a resource.
    case get = "GET"

    /// Submits a request body.
    case post = "POST"

    /// Replaces a resource.
    case put = "PUT"

    /// Partially updates a resource.
    case patch = "PATCH"

    /// Deletes a resource.
    case delete = "DELETE"
}

/// A complete HTTP request independent of a particular networking implementation.
public struct HTTPRequest: Sendable {
    /// The destination URL.
    public var url: URL

    /// The HTTP method.
    public var method: HTTPMethod

    /// Ordered header fields whose original name casing is retained.
    public var headers: [(name: String, value: String)]

    /// The request body, or `nil` for a bodyless request.
    public var body: Data?

    /// Creates an HTTP request.
    public init(
        url: URL,
        method: HTTPMethod,
        headers: [(name: String, value: String)] = [],
        body: Data? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

/// An HTTP response returned through ``HTTPTransport``.
public struct HTTPResponse: Sendable {
    /// The numeric HTTP status code.
    public var statusCode: Int

    /// Response header fields.
    public var headers: [String: String]

    /// The response body.
    public var body: Data

    /// Creates an HTTP response.
    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

/// A sendable seam for all HTTP communication performed by SwiftDunk.
///
/// Custom transports can provide proxies, retries, traffic recording, or deterministic
/// responses for tests.
public protocol HTTPTransport: Sendable {
    /// Sends a request and returns its response.
    /// - Throws: ``SwiftDunkError`` with code ``SwiftDunkError/Code/network`` if no usable
    ///   HTTP response is received, or an error from a custom transport.
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// A production HTTP transport backed by an independently configured `URLSession`.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// Creates a transport with its own URL session.
    public init(configuration: URLSessionConfiguration = .default) {
        session = URLSession(configuration: configuration)
    }

    /// Sends a request with its header names supplied in the request's original order.
    /// - Throws: ``SwiftDunkError`` with code ``SwiftDunkError/Code/network`` when the
    ///   operation fails or does not produce an HTTP response.
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body

        for header in request.headers {
            urlRequest.addValue(header.value, forHTTPHeaderField: header.name)
        }

        do {
            let (body, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SwiftDunkError(code: .network, url: request.url)
            }

            var headers: [String: String] = [:]
            for (name, value) in httpResponse.allHeaderFields {
                headers[String(describing: name)] = String(describing: value)
            }

            return HTTPResponse(
                statusCode: httpResponse.statusCode,
                headers: headers,
                body: body
            )
        } catch let error as SwiftDunkError {
            throw error
        } catch {
            throw SwiftDunkError(
                code: .network,
                underlyingError: error,
                url: request.url
            )
        }
    }
}

public extension HTTPTransport where Self == URLSessionTransport {
    /// A transport backed by a newly created default `URLSession`.
    static var urlSession: URLSessionTransport {
        URLSessionTransport()
    }
}
