public import Foundation

/// A sendable, strongly typed value supported by Apple's property-list format.
///
/// This type represents GrandSlam's dynamic property-list payloads without exposing
/// non-sendable `[String: Any]` values.
public enum PlistValue: Sendable, Hashable {
    /// A UTF-8 string value.
    case string(String)

    /// A signed integer value.
    case integer(Int)

    /// A floating-point value.
    case real(Double)

    /// A Boolean value.
    case boolean(Bool)

    /// An opaque byte sequence.
    case data(Data)

    /// An absolute date.
    case date(Date)

    /// An ordered collection of property-list values.
    case array([PlistValue])

    /// A string-keyed collection of property-list values.
    case dictionary([String: PlistValue])
}

extension PlistValue: Codable {
    /// Creates a property-list value by decoding one supported scalar or container type.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode([String: PlistValue].self) {
            self = .dictionary(value)
        } else if let value = try? container.decode([PlistValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(Data.self) {
            self = .data(value)
        } else if let value = try? container.decode(Date.self) {
            self = .date(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .real(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.typeMismatch(
                PlistValue.self,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a property-list value."
                )
            )
        }
    }

    /// Encodes the represented value using its native property-list type.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .real(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .data(let value):
            try container.encode(value)
        case .date(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        }
    }
}

public extension PlistValue {
    /// The associated string, or `nil` when this is another kind of value.
    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    /// The associated integer, or `nil` when this is another kind of value.
    var integer: Int? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    /// The associated floating-point number, or `nil` when this is another kind of value.
    var real: Double? {
        guard case .real(let value) = self else { return nil }
        return value
    }

    /// The associated Boolean, or `nil` when this is another kind of value.
    var boolean: Bool? {
        guard case .boolean(let value) = self else { return nil }
        return value
    }

    /// The associated data, or `nil` when this is another kind of value.
    var data: Data? {
        guard case .data(let value) = self else { return nil }
        return value
    }

    /// The associated date, or `nil` when this is another kind of value.
    var date: Date? {
        guard case .date(let value) = self else { return nil }
        return value
    }

    /// The associated array, or `nil` when this is another kind of value.
    var array: [PlistValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    /// The associated dictionary, or `nil` when this is another kind of value.
    var dictionary: [String: PlistValue]? {
        guard case .dictionary(let value) = self else { return nil }
        return value
    }

    /// Returns a dictionary member, or `nil` when this is not a dictionary or the key is absent.
    subscript(key: String) -> PlistValue? {
        dictionary?[key]
    }
}

package extension PlistValue {
    func requireString(_ key: String) throws -> String {
        guard let value = self[key]?.string else {
            throw SwiftDunkError(code: .malformedResponse(key: key, expected: "a string"))
        }
        return value
    }

    func requireData(_ key: String) throws -> Data {
        guard let value = self[key]?.data else {
            throw SwiftDunkError(code: .malformedResponse(key: key, expected: "data"))
        }
        return value
    }

    func requireDictionary(_ key: String) throws -> [String: PlistValue] {
        guard let value = self[key]?.dictionary else {
            throw SwiftDunkError(code: .malformedResponse(key: key, expected: "a dictionary"))
        }
        return value
    }
}
