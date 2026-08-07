/// The three components of Apple's `X-Mme-Client-Info` device description.
public struct ClientInfo: Sendable, Equatable {
    /// The Apple hardware model, such as `MacBookPro13,2`.
    public var hardware: String

    /// The operating-system descriptor, such as `macOS;13.1;22C65`.
    public var os: String

    /// The requesting client descriptor.
    public var client: String

    /// Creates a client-info value from its three unwrapped components.
    public init(hardware: String, os: String, client: String) {
        self.hardware = hardware
        self.os = os
        self.client = client
    }

    /// Parses exactly three angle-bracketed components.
    public init?(parsing raw: String) {
        var remainder = raw[...]
        var components: [String] = []

        for _ in 0..<3 {
            remainder = remainder.drop(while: \.isWhitespace)
            guard remainder.first == "<" else { return nil }
            remainder = remainder.dropFirst()
            guard let closingIndex = remainder.firstIndex(of: ">") else { return nil }
            components.append(String(remainder[..<closingIndex]))
            remainder = remainder[remainder.index(after: closingIndex)...]
        }

        guard remainder.allSatisfy(\.isWhitespace), components.count == 3 else { return nil }
        self.init(
            hardware: components[0],
            os: components[1],
            client: components[2]
        )
    }

    /// The canonical `<hardware> <os> <client>` representation.
    public var stringValue: String {
        "<\(hardware)> <\(os)> <\(client)>"
    }
}
