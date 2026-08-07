import Foundation
import SwiftDunk
import SwiftDunkTestSupport
import Testing

@Suite("HTTP transport")
struct HTTPTransportTests {
    @Test("MockTransport preserves request method, body, header order, and casing")
    func mockTransportPreservesRequest() async throws {
        let url = try #require(URL(string: "https://example.test/resource"))
        let body = Data("payload".utf8)
        let request = HTTPRequest(
            url: url,
            method: .post,
            headers: [
                (name: "X-Mme-Client-Info", value: "client"),
                (name: "X-Apple-I-FD-Client-Info", value: "device"),
            ],
            body: body
        )
        let transport = MockTransport { captured in
            #expect(captured.url == url)
            #expect(captured.method == .post)
            #expect(captured.headers.map(\.name) == request.headers.map(\.name))
            #expect(captured.headers.map(\.value) == request.headers.map(\.value))
            #expect(captured.body == body)
            return HTTPResponse(statusCode: 204)
        }

        let response = try await transport.send(request)

        #expect(response.statusCode == 204)
        #expect(response.body.isEmpty)
    }
}
