public import Foundation

/// A Remote Anisette v3 server location.
public struct AnisetteServer: Sendable, Hashable {
    private let rawValue: String

    /// The ordered public-server list used by the default provider.
    public static let defaults: [AnisetteServer] = [.default, .stikStore, .sideStore]

    /// The primary Remote v3 service used by the default provider.
    public static let `default` = AnisetteServer(
        rawValue: "https://ani.neoarz.com/"
    )

    /// The StikStore community Remote v3 service.
    public static let stikStore = AnisetteServer(
        rawValue: "https://ani.stikstore.app"
    )

    /// The SideStore community Remote v3 service.
    public static let sideStore = AnisetteServer(
        rawValue: "https://ani.sidestore.io"
    )

    /// Creates a custom server location.
    ///
    /// The URL is validated when a request is made. HTTPS becomes WSS for provisioning,
    /// and HTTP becomes WS for explicitly configured local test servers.
    public init(url: URL) {
        rawValue = url.absoluteString
    }

    private init(rawValue: String) {
        self.rawValue = rawValue
    }

    package func endpoint(path: String, webSocket: Bool = false) throws -> URL {
        guard var components = URLComponents(string: rawValue) else {
            throw invalidServerError
        }

        switch (components.scheme?.lowercased(), webSocket) {
        case ("https", true):
            components.scheme = "wss"
        case ("http", true):
            components.scheme = "ws"
        case ("https", false), ("http", false):
            break
        default:
            throw invalidServerError
        }

        guard components.host != nil else {
            throw invalidServerError
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, path].filter { !$0.isEmpty }.joined(separator: "/")
        guard let url = components.url else {
            throw invalidServerError
        }
        return url
    }

    private var invalidServerError: SwiftDunkError {
        SwiftDunkError(code: .anisetteUnavailable)
    }
}
