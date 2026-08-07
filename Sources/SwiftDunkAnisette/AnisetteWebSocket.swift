package import Foundation

package protocol AnisetteWebSocket: Sendable {
    func receiveText() async throws -> String?
    func send(text: String) async throws
    func close() async
}

package protocol AnisetteWebSocketFactory: Sendable {
    func connect(to url: URL) async throws -> any AnisetteWebSocket
}

package struct URLSessionAnisetteWebSocketFactory: AnisetteWebSocketFactory {
    private let session: URLSession

    package init(configuration: URLSessionConfiguration = .default) {
        session = URLSession(configuration: configuration)
    }

    package func connect(to url: URL) async throws -> any AnisetteWebSocket {
        let task = session.webSocketTask(with: url)
        task.resume()
        return URLSessionAnisetteWebSocket(task: task)
    }
}

private actor URLSessionAnisetteWebSocket: AnisetteWebSocket {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func receiveText() async throws -> String? {
        switch try await task.receive() {
        case .string(let text):
            return text
        case .data:
            throw SwiftDunkError(
                code: .anisetteProvisioningFailed(
                    "The anisette server sent a binary WebSocket frame."
                )
            )
        @unknown default:
            throw SwiftDunkError(
                code: .anisetteProvisioningFailed(
                    "The anisette server sent an unknown WebSocket frame."
                )
            )
        }
    }

    func send(text: String) async throws {
        try await task.send(.string(text))
    }

    func close() async {
        task.cancel(with: .normalClosure, reason: nil)
    }
}
