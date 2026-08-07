import Foundation
import SwiftDunk
import Testing

@Suite(
    "Live Authentication",
    .tags(.integration),
    .enabled(if: LiveAuthenticationEnvironment.isEnabled)
)
struct LiveAuthenticationTests {
    @Test("A real Apple ID logs in and reads App ID lifecycle data")
    func realLogin() async throws {
        guard
            let appleID = LiveAuthenticationEnvironment.value("SWIFTDUNK_APPLE_ID"),
            let password = LiveAuthenticationEnvironment.value("SWIFTDUNK_PASSWORD")
        else {
            Issue.record("Live authentication environment was incomplete.")
            return
        }

        let anisette = LiveTestServices.anisette

        let account = try await Account.login(
            appleID: appleID,
            password: password,
            anisette: anisette
        ) { _ in
            .code(try LiveTwoFactorInput.readCode())
        }

        #expect(!account.appleID.isEmpty)
        #expect(!account.dsid.isEmpty)
        let session = try await DeveloperSession(account: account, anisette: anisette)
        let teams = try await session.teams()
        #expect(!teams.isEmpty)

        for (index, team) in teams.enumerated() {
            let inventory = try await session.appIDInventory(teamID: team.id)
            let expirationCount = inventory.appIDs.count(where: { $0.expirationDate != nil })
            let registered =
                inventory.maximumQuantity.map {
                    "\(inventory.appIDs.count) of \($0)"
                } ?? String(inventory.appIDs.count)
            print(
                """
                App IDs for team \(index + 1)
                    Registered         \(registered)
                    Available          \(display(inventory.availableQuantity))
                    Expiration dates   \(expirationCount)
                """
            )
        }
    }

    private func display(_ value: Int?) -> String {
        value.map(String.init) ?? "not supplied"
    }
}

private enum LiveTwoFactorInput {
    static func readCode() throws -> String {
        #if os(macOS)
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e",
                """
                text returned of (display dialog "Enter the newest code shown on your trusted Apple device." \
                default answer "" with title "SwiftDunk Live Test" buttons {"Cancel", "Continue"} \
                default button "Continue" cancel button "Cancel")
                """,
            ]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                throw LiveTestInputError(
                    "The two-factor dialog could not be opened: \(error.localizedDescription)"
                )
            }
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw LiveTestInputError("The two-factor dialog was cancelled.")
            }
            let data = try output.fileHandleForReading.readToEnd() ?? Data()
            guard
                let code = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !code.isEmpty
            else {
                throw SwiftDunkError(code: .invalidTwoFactorCode)
            }
            return code
        #else
            throw LiveTestInputError("Interactive live authentication requires macOS.")
        #endif
    }
}

private struct LiveTestInputError: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }

    init(_ message: String) {
        self.message = message
    }
}

private enum LiveAuthenticationEnvironment {
    static var isEnabled: Bool {
        value("SWIFTDUNK_RUN_LIVE_TESTS") == "1"
            && value("SWIFTDUNK_APPLE_ID") != nil
            && value("SWIFTDUNK_PASSWORD") != nil
    }

    static func value(_ name: String) -> String? {
        guard
            let value = ProcessInfo.processInfo.environment[name]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
