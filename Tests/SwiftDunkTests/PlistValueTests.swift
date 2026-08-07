import Foundation
import SwiftDunkCore
import Testing

@Suite("Property-list values")
struct PlistValueTests {
    @Test("Every supported value round-trips through an XML property list")
    func xmlRoundTrip() throws {
        let date = Date(timeIntervalSinceReferenceDate: 123_456)
        let expected = PlistValue.dictionary([
            "array": .array([.string("value"), .integer(-7), .boolean(true)]),
            "data": .data(Data([0x00, 0x80, 0xFF])),
            "date": .date(date),
            "dictionary": .dictionary(["nested": .real(1.25)]),
            "false": .boolean(false),
            "integer": .integer(42),
            "real": .real(-3.5),
            "string": .string("SwiftDunk"),
        ])

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let encoded = try encoder.encode(expected)
        let decoded = try PropertyListDecoder().decode(PlistValue.self, from: encoded)

        #expect(decoded == expected)
        #expect(String(data: encoded, encoding: .utf8)?.contains("<data>") == true)
        #expect(String(data: encoded, encoding: .utf8)?.contains("<date>") == true)
    }

    @Test("Optional accessors never coerce or trap")
    func accessorsPreserveTypes() {
        let value = PlistValue.dictionary([
            "integer": .integer(1),
            "string": .string("one"),
        ])

        #expect(value["integer"]?.integer == 1)
        #expect(value["integer"]?.string == nil)
        #expect(value["string"]?.string == "one")
        #expect(value["missing"] == nil)
        #expect(PlistValue.array([])["key"] == nil)
    }

    @Test("Required accessors name malformed keys")
    func requiredAccessorError() {
        let value = PlistValue.dictionary(["answer": .integer(42)])

        #expect {
            try value.requireString("answer")
        } throws: { error in
            guard let error = error as? SwiftDunkError else { return false }
            return error.code == .malformedResponse(key: "answer", expected: "a string")
        }
    }
}
