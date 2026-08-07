package import Foundation

package actor RemoteAnisetteBackend: AnisetteProvider {
    private let server: AnisetteServer
    private let stateStore: any AnisetteStateStore
    private let transport: any HTTPTransport
    private let webSockets: any AnisetteWebSocketFactory
    private let now: @Sendable () -> Date

    private var state: AnisetteState?
    private var clientInfo: RemoteClientInfo?

    package init(
        server: AnisetteServer,
        stateStore: any AnisetteStateStore,
        transport: any HTTPTransport,
        webSockets: any AnisetteWebSocketFactory,
        now: @escaping @Sendable () -> Date
    ) {
        self.server = server
        self.stateStore = stateStore
        self.transport = transport
        self.webSockets = webSockets
        self.now = now
    }

    package func headers() async throws -> AnisetteHeaders {
        var currentState = try await loadState()
        let info = try await loadClientInfo()

        if currentState.adiPB == nil {
            currentState = try await provision(currentState, clientInfo: info)
        }

        do {
            return try await fetchHeaders(state: currentState, clientInfo: info)
        } catch RemoteAnisetteProtocolError.staleProvisioning {
            currentState.adiPB = nil
            state = currentState
            currentState = try await provision(currentState, clientInfo: info)
            do {
                return try await fetchHeaders(state: currentState, clientInfo: info)
            } catch RemoteAnisetteProtocolError.staleProvisioning {
                throw SwiftDunkError(
                    code: .anisetteProvisioningFailed(
                        "The anisette server rejected freshly provisioned state."
                    )
                )
            }
        }
    }

    private func loadState() async throws -> AnisetteState {
        if let state {
            return state
        }
        if let stored = try await stateStore.load() {
            if let state {
                return state
            }
            state = stored
            return stored
        }

        let generated = try AnisetteState.generated()
        try await stateStore.save(generated)
        if let state {
            return state
        }
        state = generated
        return generated
    }

    private func provision(
        _ inputState: AnisetteState,
        clientInfo: RemoteClientInfo
    ) async throws -> AnisetteState {
        let provisioner = RemoteAnisetteProvisioner(
            server: server,
            transport: transport,
            webSockets: webSockets,
            now: now
        )

        do {
            let provisioned = try await provisioner.provision(
                state: inputState,
                clientInfo: clientInfo
            )
            if let state, state.keychainIdentifier == inputState.keychainIdentifier,
                state.adiPB != inputState.adiPB, state.adiPB != nil
            {
                return state
            }
            try await stateStore.save(provisioned)
            if let state, state.keychainIdentifier == inputState.keychainIdentifier,
                state.adiPB != inputState.adiPB, state.adiPB != nil
            {
                return state
            }
            state = provisioned
            return provisioned
        } catch let error as SwiftDunkError {
            switch error.code {
            case .anisetteProvisioningFailed, .malformedResponse, .securityFramework:
                throw error
            default:
                throw SwiftDunkError(
                    code: .anisetteProvisioningFailed(
                        "Remote anisette provisioning failed."
                    ),
                    underlyingError: error,
                    url: error.url
                )
            }
        } catch {
            throw SwiftDunkError(
                code: .anisetteProvisioningFailed("Remote anisette provisioning failed."),
                underlyingError: error
            )
        }
    }

    private func loadClientInfo() async throws -> RemoteClientInfo {
        if let clientInfo {
            return clientInfo
        }

        let url = try server.endpoint(path: AnisetteConstants.Path.clientInfo)
        let response: HTTPResponse
        do {
            response = try await transport.send(HTTPRequest(url: url, method: .get))
        } catch {
            throw SwiftDunkError(
                code: .anisetteUnavailable,
                underlyingError: error,
                url: url
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SwiftDunkError(code: .anisetteUnavailable, url: url)
        }

        do {
            let decoded = try JSONDecoder().decode(RemoteClientInfo.self, from: response.body)
            if let clientInfo {
                return clientInfo
            }
            clientInfo = decoded
            return decoded
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "client_info",
                    expected: "a Remote Anisette v3 client-info response"
                ),
                underlyingError: error,
                url: url
            )
        }
    }

    private func fetchHeaders(
        state: AnisetteState,
        clientInfo: RemoteClientInfo
    ) async throws -> AnisetteHeaders {
        guard let adiPB = state.adiPB else {
            throw RemoteAnisetteProtocolError.staleProvisioning
        }
        let url = try server.endpoint(path: AnisetteConstants.Path.headers)
        let body = try JSONEncoder().encode(
            GetHeadersRequest(
                identifier: state.keychainIdentifier.base64EncodedString(),
                adiPB: adiPB.base64EncodedString()
            )
        )
        let response: HTTPResponse
        do {
            response = try await transport.send(
                HTTPRequest(
                    url: url,
                    method: .post,
                    headers: [
                        (
                            name: AnisetteConstants.Header.contentType,
                            value: AnisetteConstants.Header.jsonContentType
                        )
                    ],
                    body: body
                )
            )
        } catch {
            throw SwiftDunkError(
                code: .anisetteUnavailable,
                underlyingError: error,
                url: url
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SwiftDunkError(code: .anisetteUnavailable, url: url)
        }

        let decoded: GetHeadersResponse
        do {
            decoded = try JSONDecoder().decode(GetHeadersResponse.self, from: response.body)
        } catch {
            throw SwiftDunkError(
                code: .malformedResponse(
                    key: "result",
                    expected: "a Remote Anisette v3 header response"
                ),
                underlyingError: error,
                url: url
            )
        }

        if decoded.result == "GetHeadersError" {
            if decoded.message?.contains(AnisetteConstants.staleProvisioningCode) == true {
                throw RemoteAnisetteProtocolError.staleProvisioning
            }
            throw SwiftDunkError(code: .anisetteUnavailable, url: url)
        }
        guard decoded.result == "Headers" else {
            throw SwiftDunkError(
                code: .malformedResponse(key: "result", expected: "'Headers'"),
                url: url
            )
        }
        guard let machineID = decoded.machineID else {
            throw missingHeader(AnisetteConstants.Header.machineID, url: url)
        }
        guard let oneTimePassword = decoded.oneTimePassword else {
            throw missingHeader(AnisetteConstants.Header.oneTimePassword, url: url)
        }
        guard let routingInfo = decoded.routingInfo else {
            throw missingHeader(AnisetteConstants.Header.routingInfo, url: url)
        }

        let generatedAt = now()
        return AnisetteHeaders(
            values: [
                AnisetteConstants.Header.clientTime: formattedTime(generatedAt),
                AnisetteConstants.Header.serialNumber: AnisetteConstants.serialNumber,
                AnisetteConstants.Header.timeZone: AnisetteConstants.timeZone,
                AnisetteConstants.Header.locale: AnisetteConstants.locale,
                AnisetteConstants.Header.routingInfo: routingInfo,
                AnisetteConstants.Header.localUserID: state.localUserID,
                AnisetteConstants.Header.deviceID: state.deviceID,
                AnisetteConstants.Header.oneTimePassword: oneTimePassword,
                AnisetteConstants.Header.machineID: machineID,
                AnisetteConstants.Header.clientInfo: clientInfo.clientInfo,
            ],
            generatedAt: generatedAt
        )
    }

    private func missingHeader(_ name: String, url: URL) -> SwiftDunkError {
        SwiftDunkError(
            code: .malformedResponse(key: name, expected: "a string"),
            url: url
        )
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
