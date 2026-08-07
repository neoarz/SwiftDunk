import Foundation
import SwiftDunk

struct AccountFlow {
    let anisette: any AnisetteProvider
    let sessionStore: any SessionStore

    func session() async throws -> DeveloperSession? {
        guard let saved = try await sessionStore.load() else {
            return try await signInAndSave()
        }

        do {
            let session = try await DeveloperSession(restoring: saved, anisette: anisette)
            print("Restored the session for \(saved.appleID).")
            return session
        } catch {
            let restorationError = error
            print("Saved session could not be restored: \(error.localizedDescription)")
            guard Console.confirm("Sign in again and replace it?") else {
                throw restorationError
            }
            return try await signInAndSave()
        }
    }

    private func signInAndSave() async throws -> DeveloperSession? {
        guard let session = try await signIn() else { return nil }
        try await sessionStore.save(await session.stored)
        return session
    }

    private func signIn() async throws -> DeveloperSession? {
        guard let appleID = Console.requiredPrompt("Apple ID: ") else { return nil }
        guard let password = Console.readPassword(), !password.isEmpty else { return nil }

        let account = try await Account.login(
            appleID: appleID,
            password: password,
            anisette: anisette,
            onTwoFactor: Console.twoFactorResponse
        )
        let session = try await DeveloperSession(account: account, anisette: anisette)
        print("Logged in as \(account.firstName) \(account.lastName).")
        return session
    }
}
