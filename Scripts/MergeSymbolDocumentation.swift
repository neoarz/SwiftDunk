import Foundation

enum MergeError: Error {
    case invalidArguments
    case invalidGraph(URL)
    case undocumentedPublicSymbols([String])
}

func graph(at url: URL) throws -> [String: Any] {
    let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    guard let graph = value as? [String: Any] else {
        throw MergeError.invalidGraph(url)
    }
    return graph
}

func symbols(in graph: [String: Any]) -> [[String: Any]] {
    graph["symbols"] as? [[String: Any]] ?? []
}

func identifier(of symbol: [String: Any]) -> String? {
    (symbol["identifier"] as? [String: Any])?["precise"] as? String
}

do {
    let arguments = CommandLine.arguments.dropFirst()
    guard arguments.count >= 3 else {
        throw MergeError.invalidArguments
    }

    let inputURL = URL(fileURLWithPath: arguments[arguments.startIndex])
    let outputURL = URL(fileURLWithPath: arguments[arguments.index(after: arguments.startIndex)])
    var documentation: [String: Any] = [:]
    var undocumented: [String] = []

    for path in arguments.dropFirst(2) {
        for symbol in symbols(in: try graph(at: URL(fileURLWithPath: path))) {
            if let id = identifier(of: symbol), let comment = symbol["docComment"] {
                documentation[id] = comment
            } else if symbol["accessLevel"] as? String == "public",
                symbol["location"] != nil,
                let names = symbol["names"] as? [String: Any],
                let title = names["title"] as? String
            {
                undocumented.append(title)
            }
        }
    }
    guard undocumented.isEmpty else {
        throw MergeError.undocumentedPublicSymbols(undocumented.sorted())
    }

    var merged = try graph(at: inputURL)
    merged["symbols"] = symbols(in: merged).map { symbol in
        guard
            symbol["docComment"] == nil,
            let id = identifier(of: symbol),
            let comment = documentation[id]
        else {
            return symbol
        }
        var documented = symbol
        documented["docComment"] = comment
        return documented
    }

    let data = try JSONSerialization.data(
        withJSONObject: merged,
        options: [.prettyPrinted, .sortedKeys]
    )
    try data.write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("Symbol graph merge failed: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
