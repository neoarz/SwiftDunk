import Foundation

enum TestData {
    static func hex(_ string: String) throws -> Data {
        let characters = Array(string.utf8)
        guard characters.count.isMultiple(of: 2) else {
            throw TestDataError.oddCharacterCount
        }

        var result = Data()
        result.reserveCapacity(characters.count / 2)

        for index in stride(from: 0, to: characters.count, by: 2) {
            guard
                let high = nibble(characters[index]),
                let low = nibble(characters[index + 1])
            else {
                throw TestDataError.invalidHexadecimal
            }
            result.append((high << 4) | low)
        }
        return result
    }

    private static func nibble(_ character: UInt8) -> UInt8? {
        switch character {
        case CharacterCode.zero...CharacterCode.nine:
            character - CharacterCode.zero
        case CharacterCode.lowercaseA...CharacterCode.lowercaseF:
            character - CharacterCode.lowercaseA + 10
        case CharacterCode.uppercaseA...CharacterCode.uppercaseF:
            character - CharacterCode.uppercaseA + 10
        default:
            nil
        }
    }
}

private enum CharacterCode {
    static let zero = Character("0").asciiValue
    static let nine = Character("9").asciiValue
    static let lowercaseA = Character("a").asciiValue
    static let lowercaseF = Character("f").asciiValue
    static let uppercaseA = Character("A").asciiValue
    static let uppercaseF = Character("F").asciiValue
}

private enum TestDataError: Error {
    case oddCharacterCount
    case invalidHexadecimal
}

private extension Character {
    var asciiValue: UInt8 {
        String(self).utf8.first ?? 0
    }
}
