package import Foundation

struct RemoteAnisetteProvisioner: Sendable {
    private let server: AnisetteServer
    private let transport: any HTTPTransport
    private let webSockets: any AnisetteWebSocketFactory
    private let now: @Sendable () -> Date

    init(
        server: AnisetteServer,
        transport: any HTTPTransport,
        webSockets: any AnisetteWebSocketFactory,
        now: @escaping @Sendable () -> Date
    ) {
        self.server = server
        self.transport = transport
        self.webSockets = webSockets
        self.now = now
    }

    func provision(
        state: AnisetteState,
        clientInfo: RemoteClientInfo
    ) async throws -> AnisetteState {
        let urls = try await provisioningURLs(state: state, clientInfo: clientInfo)
        let socketURL = try server.endpoint(
            path: AnisetteConstants.Path.provisioning,
            webSocket: true
        )
        let socket = try await webSockets.connect(to: socketURL)

        do {
            let provisioned = try await runStateMachine(
                socket: socket,
                state: state,
                clientInfo: clientInfo,
                urls: urls
            )
            await socket.close()
            return provisioned
        } catch {
            await socket.close()
            throw error
        }
    }

    private func runStateMachine(
        socket: any AnisetteWebSocket,
        state: AnisetteState,
        clientInfo: RemoteClientInfo,
        urls: ProvisioningURLs
    ) async throws -> AnisetteState {
        var phase = ProvisioningPhase.identifier

        for _ in 0..<AnisetteConstants.maximumProvisioningMessages {
            guard let text = try await socket.receiveText() else {
                throw provisioningError("The provisioning WebSocket closed before success.")
            }
            let message: ProvisioningMessage
            do {
                message = try JSONDecoder().decode(
                    ProvisioningMessage.self,
                    from: Data(text.utf8)
                )
            } catch {
                throw SwiftDunkError(
                    code: .malformedResponse(
                        key: "result",
                        expected: "a provisioning WebSocket message"
                    ),
                    underlyingError: error,
                    url: try? server.endpoint(
                        path: AnisetteConstants.Path.provisioning,
                        webSocket: true
                    )
                )
            }

            switch (message.result, phase) {
            case (AnisetteConstants.ProvisioningResult.giveIdentifier, .identifier):
                try await send(
                    IdentifierMessage(
                        identifier: state.keychainIdentifier.base64EncodedString()
                    ),
                    through: socket
                )
                phase = .start

            case (AnisetteConstants.ProvisioningResult.giveStartData, .start):
                let spim = try await startProvisioning(
                    url: urls.start,
                    state: state,
                    clientInfo: clientInfo
                )
                try await send(StartProvisioningMessage(spim: spim), through: socket)
                phase = .end

            case (AnisetteConstants.ProvisioningResult.giveEndData, .end):
                guard let cpim = message.cpim else {
                    throw SwiftDunkError(
                        code: .malformedResponse(key: "cpim", expected: "a string")
                    )
                }
                let response = try await finishProvisioning(
                    url: urls.finish,
                    cpim: cpim,
                    state: state,
                    clientInfo: clientInfo
                )
                try await send(response, through: socket)
                phase = .success

            case (AnisetteConstants.ProvisioningResult.success, .success):
                guard let encodedADI = message.adiPB else {
                    throw SwiftDunkError(
                        code: .malformedResponse(key: "adi_pb", expected: "base64 data")
                    )
                }
                guard let adiPB = Data(base64Encoded: encodedADI) else {
                    throw SwiftDunkError(
                        code: .malformedResponse(key: "adi_pb", expected: "base64 data")
                    )
                }
                var provisioned = state
                provisioned.adiPB = adiPB
                return provisioned

            default:
                throw provisioningError(
                    "The anisette server sent an out-of-order provisioning message."
                )
            }
        }

        throw provisioningError("The provisioning session exceeded its message limit.")
    }

    private func provisioningURLs(
        state: AnisetteState,
        clientInfo: RemoteClientInfo
    ) async throws -> ProvisioningURLs {
        guard let lookupURL = URL(string: AnisetteConstants.Path.lookup) else {
            throw provisioningError("The Apple provisioning lookup URL is invalid.")
        }
        let response = try await transport.send(
            appleRequest(
                url: lookupURL,
                method: .get,
                body: nil,
                state: state,
                clientInfo: clientInfo
            )
        )
        try requireSuccess(response, url: lookupURL)

        let root: PlistValue
        do {
            root = try PropertyListDecoder().decode(PlistValue.self, from: response.body)
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "urls",
                    expected: "an Apple provisioning URL dictionary"
                ),
                underlyingError: error,
                url: lookupURL
            )
        }
        let urls = try root.requireDictionary("urls")
        guard let startString = urls["midStartProvisioning"]?.string else {
            throw missingURL("midStartProvisioning", lookupURL: lookupURL)
        }
        guard let finishString = urls["midFinishProvisioning"]?.string else {
            throw missingURL("midFinishProvisioning", lookupURL: lookupURL)
        }
        guard let startURL = URL(string: startString) else {
            throw missingURL("midStartProvisioning", lookupURL: lookupURL)
        }
        guard let finishURL = URL(string: finishString) else {
            throw missingURL("midFinishProvisioning", lookupURL: lookupURL)
        }
        return ProvisioningURLs(start: startURL, finish: finishURL)
    }

    private func startProvisioning(
        url: URL,
        state: AnisetteState,
        clientInfo: RemoteClientInfo
    ) async throws -> String {
        let body = try plistBody(request: [:])
        let response = try await transport.send(
            appleRequest(
                url: url,
                method: .post,
                body: body,
                state: state,
                clientInfo: clientInfo
            )
        )
        try requireSuccess(response, url: url)
        return try responseDictionary(response.body, url: url).requireString("spim")
    }

    private func finishProvisioning(
        url: URL,
        cpim: String,
        state: AnisetteState,
        clientInfo: RemoteClientInfo
    ) async throws -> EndProvisioningMessage {
        let body = try plistBody(request: ["cpim": .string(cpim)])
        let response = try await transport.send(
            appleRequest(
                url: url,
                method: .post,
                body: body,
                state: state,
                clientInfo: clientInfo
            )
        )
        try requireSuccess(response, url: url)
        let values = try responseDictionary(response.body, url: url)
        return EndProvisioningMessage(
            ptm: try values.requireString("ptm"),
            tk: try values.requireString("tk")
        )
    }

    private func plistBody(request: [String: PlistValue]) throws -> Data {
        let root = PlistValue.dictionary([
            "Header": .dictionary([:]),
            "Request": .dictionary(request),
        ])
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        return try encoder.encode(root)
    }

    private func responseDictionary(_ data: Data, url: URL) throws -> PlistValue {
        do {
            let root = try PropertyListDecoder().decode(PlistValue.self, from: data)
            return .dictionary(try root.requireDictionary("Response"))
        } catch let error as SwiftDunkError {
            throw error
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "Response",
                    expected: "an Apple provisioning response dictionary"
                ),
                underlyingError: error,
                url: url
            )
        }
    }

    private func appleRequest(
        url: URL,
        method: HTTPMethod,
        body: Data?,
        state: AnisetteState,
        clientInfo: RemoteClientInfo
    ) -> HTTPRequest {
        HTTPRequest(
            url: url,
            method: method,
            headers: [
                (
                    name: AnisetteConstants.Header.clientInfo,
                    value: clientInfo.clientInfo
                ),
                (name: AnisetteConstants.Header.userAgent, value: clientInfo.userAgent),
                (
                    name: AnisetteConstants.Header.contentType,
                    value: AnisetteConstants.Header.plistContentType
                ),
                (name: AnisetteConstants.Header.localUserID, value: state.localUserID),
                (name: AnisetteConstants.Header.deviceID, value: state.deviceID),
                (
                    name: AnisetteConstants.Header.clientTime,
                    value: formattedTime(now())
                ),
                (name: AnisetteConstants.Header.timeZone, value: AnisetteConstants.timeZone),
                (name: AnisetteConstants.Header.locale, value: AnisetteConstants.locale),
            ],
            body: body
        )
    }

    private func send<Message: Encodable>(
        _ message: Message,
        through socket: any AnisetteWebSocket
    ) async throws {
        let data = try JSONEncoder().encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw provisioningError("A provisioning response could not be encoded.")
        }
        try await socket.send(text: text)
    }

    private func requireSuccess(_ response: HTTPResponse, url: URL) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw SwiftDunkError(
                code: .unexpectedStatusCode(response.statusCode),
                url: url
            )
        }
    }

    private func missingURL(_ key: String, lookupURL: URL) -> SwiftDunkError {
        SwiftDunkError(
            code: .malformedResponse(key: key, expected: "an absolute URL string"),
            url: lookupURL
        )
    }

    private func provisioningError(_ message: String) -> SwiftDunkError {
        SwiftDunkError(code: .anisetteProvisioningFailed(message))
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

private struct ProvisioningURLs: Sendable {
    let start: URL
    let finish: URL
}

private enum ProvisioningPhase {
    case identifier
    case start
    case end
    case success
}
