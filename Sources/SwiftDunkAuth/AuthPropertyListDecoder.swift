import Foundation

enum AuthPropertyListDecoder {
    static func decode(
        _ data: Data,
        key: String,
        expected: String
    ) throws -> PlistValue {
        do {
            return try PropertyListDecoder().decode(PlistValue.self, from: data)
        } catch {
            // some gsa responses leave off the xml header
            let prefix =
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
                "http://www.apple.com/DTDs/PropertyList-1.0.dtd">

                """
            do {
                return try PropertyListDecoder().decode(
                    PlistValue.self,
                    from: Data(prefix.utf8) + data
                )
            } catch let prefixedError {
                throw SwiftDunkError(
                    code: .malformedResponse(key: key, expected: expected),
                    underlyingError: prefixedError
                )
            }
        }
    }
}
