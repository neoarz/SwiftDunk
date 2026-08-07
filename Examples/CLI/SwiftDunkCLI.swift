import Darwin
import Foundation
import SwiftDunk

@main
struct SwiftDunkCLI {
    static func main() async {
        do {
            guard let command = try CLICommand.resolve(arguments: CommandLine.arguments) else {
                return
            }

            let sessionStore = KeychainSessionStore()
            if command == .logout {
                try await sessionStore.clear()
                print("Saved session removed.")
                return
            }

            let accountFlow = AccountFlow(
                anisette: RemoteAnisetteProvider(),
                sessionStore: sessionStore
            )
            guard let session = try await accountFlow.session() else { return }

            let portal = PortalFlow(session: session, sessionStore: sessionStore)
            switch command {
            case .inspect:
                try await portal.inspect()
            case .provision:
                try await portal.provision()
            case .logout:
                return
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            exit(EXIT_FAILURE)
        }
    }
}

enum CLICommand: String {
    case inspect
    case provision
    case logout

    static func resolve(arguments: [String]) throws -> CLICommand? {
        let values = Array(arguments.dropFirst())
        guard values.count <= 1 else {
            Console.printUsage()
            throw CLIError("Expected one command.")
        }
        guard let value = values.first else {
            return try Console.chooseCommand()
        }
        if value == "help" || value == "--help" || value == "-h" {
            Console.printUsage()
            return nil
        }
        guard let command = CLICommand(rawValue: value.lowercased()) else {
            Console.printUsage()
            throw CLIError("Unknown command \"\(value)\".")
        }
        return command
    }
}

struct CLIError: LocalizedError {
    let errorDescription: String?

    init(_ description: String) {
        errorDescription = description
    }
}
