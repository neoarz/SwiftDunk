import OSLog

struct PortalNameNormalizer: Sendable {
    private let logger = Logger(subsystem: "dev.swiftdunk", category: "portal")

    func normalize(_ name: String) -> String {
        let normalized = String(name.unicodeScalars.filter(\.isASCIIAlphabetic))
        if normalized != name {
            logger.notice("Removed unsupported characters from a Developer Portal resource name.")
        }
        return normalized
    }
}

private extension Unicode.Scalar {
    var isASCIIAlphabetic: Bool {
        switch value {
        case 65...90, 97...122:
            true
        default:
            false
        }
    }
}
