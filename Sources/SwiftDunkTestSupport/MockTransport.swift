public import SwiftDunk

/// An HTTP transport whose behavior is supplied by a test closure.
public struct MockTransport: HTTPTransport {
    private let handler: @Sendable (HTTPRequest) async throws -> HTTPResponse

    /// Creates a mock transport.
    public init(
        handler: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse
    ) {
        self.handler = handler
    }

    /// Passes a request to the configured test closure.
    /// - Throws: Any error produced by the test closure.
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await handler(request)
    }
}
