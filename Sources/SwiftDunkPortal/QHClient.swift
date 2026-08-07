import Foundation
import SwiftDunkAuth
import SwiftDunkCore

struct QHResponseMeta: Decodable, Sendable {
    let resultCode: Int
    let httpCode: Int?
    let userString: String?
    let resultString: String?
    let pageNumber: Int?
    let pageSize: Int?
    let totalRecords: Int?
}

struct QHResult<Value: Sendable>: Sendable {
    let value: Value
    let meta: QHResponseMeta
}

struct QHClient: Sendable {
    private let anisette: any AnisetteProvider
    private let credentials: PortalCredentials
    private let transport: any HTTPTransport
    private let requestID: @Sendable () -> UUID
    private let headerBuilder = PortalHeaderBuilder()

    init(
        anisette: any AnisetteProvider,
        credentials: PortalCredentials,
        transport: any HTTPTransport,
        requestID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.anisette = anisette
        self.credentials = credentials
        self.transport = transport
        self.requestID = requestID
    }

    func send<Response: Decodable & Sendable>(
        path: String,
        body originalBody: [String: PlistValue] = [:],
        as type: Response.Type = Response.self
    ) async throws -> QHResult<Response> {
        let url = try PortalConstants.url(path: path)
        let anisetteHeaders = try await anisette.headers()
        var body = originalBody
        body[PortalConstants.BodyKey.requestID] =
            .string(requestID().uuidString.uppercased())
        let encoded: Data
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            encoded = try encoder.encode(body)
        } catch {
            throw malformed(
                key: "request",
                expected: "an encodable QH property list",
                underlyingError: error,
                url: url
            )
        }

        var headers = [
            (
                name: PortalConstants.Header.contentType,
                value: PortalConstants.ContentType.plist
            ),
            (
                name: PortalConstants.Header.accept,
                value: PortalConstants.ContentType.plist
            ),
        ]
        headers += try headerBuilder.commonHeaders(
            anisette: anisetteHeaders,
            credentials: credentials
        )
        let response = try await transport.send(
            HTTPRequest(url: url, method: .post, headers: headers, body: encoded)
        )
        let meta: QHResponseMeta
        do {
            meta = try PropertyListDecoder().decode(QHResponseMeta.self, from: response.body)
        } catch {
            if !(200..<300).contains(response.statusCode) {
                throw SwiftDunkError(
                    code: .unexpectedStatusCode(response.statusCode),
                    underlyingError: error,
                    url: url
                )
            }
            throw malformed(
                key: "resultCode",
                expected: "QH response metadata",
                underlyingError: error,
                url: url
            )
        }
        guard meta.resultCode == 0 else {
            throw SwiftDunkError(
                code: .developerAPI(
                    resultCode: meta.resultCode,
                    httpCode: meta.httpCode,
                    message: meta.userString
                        ?? meta.resultString
                        ?? PortalConstants.unknownAPIError
                ),
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
            return try QHResult(
                value: PropertyListDecoder().decode(type, from: response.body),
                meta: meta
            )
        } catch {
            throw malformed(
                key: "response",
                expected: "the QH response for \(path)",
                underlyingError: error,
                url: url
            )
        }
    }

    func paginated<Response: Decodable & Sendable, Element: Sendable>(
        path: String,
        body originalBody: [String: PlistValue] = [:],
        as type: Response.Type = Response.self,
        values: @escaping @Sendable (Response) -> [Element]
    ) async throws -> [Element] {
        let result = try await paginatedWithSummary(
            path: path,
            body: originalBody,
            as: type,
            initialSummary: (),
            values: values,
            updateSummary: { _, _ in () }
        )
        return result.values
    }

    func paginatedWithSummary<
        Response: Decodable & Sendable,
        Element: Sendable,
        Summary: Sendable
    >(
        path: String,
        body originalBody: [String: PlistValue] = [:],
        as type: Response.Type = Response.self,
        initialSummary: Summary,
        values: @escaping @Sendable (Response) -> [Element],
        updateSummary: @escaping @Sendable (Summary, Response) -> Summary
    ) async throws -> (values: [Element], summary: Summary) {
        var body = originalBody
        var collected: [Element] = []
        var summary = initialSummary
        var requestedPage: Int?

        while true {
            let result = try await send(path: path, body: body, as: type)
            let pageValues = values(result.value)
            collected += pageValues
            summary = updateSummary(summary, result.value)
            guard let total = result.meta.totalRecords, collected.count < total else {
                return (collected, summary)
            }
            guard !pageValues.isEmpty else {
                throw malformed(
                    key: "totalRecords",
                    expected: "pagination that makes forward progress",
                    url: try PortalConstants.url(path: path)
                )
            }
            let currentPage = result.meta.pageNumber ?? requestedPage ?? 1
            let (nextPage, overflowed) = currentPage.addingReportingOverflow(1)
            guard !overflowed else {
                throw malformed(
                    key: "pageNumber",
                    expected: "a page number that can be incremented",
                    url: try PortalConstants.url(path: path)
                )
            }
            guard requestedPage.map({ nextPage > $0 }) ?? true else {
                throw malformed(
                    key: "pageNumber",
                    expected: "an increasing page number",
                    url: try PortalConstants.url(path: path)
                )
            }
            requestedPage = nextPage
            body[PortalConstants.BodyKey.pageNumber] = .integer(nextPage)
            if let pageSize = result.meta.pageSize, pageSize > 0 {
                body[PortalConstants.BodyKey.pageSize] = .integer(pageSize)
            }
        }
    }

    private func malformed(
        key: String,
        expected: String,
        underlyingError: (any Error)? = nil,
        url: URL? = nil
    ) -> SwiftDunkError {
        SwiftDunkError(
            code: .malformedResponse(key: key, expected: expected),
            underlyingError: underlyingError,
            url: url
        )
    }
}
