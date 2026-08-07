import Foundation
import SwiftDunk
import Testing

@Suite("Session persistence")
struct SessionStoreTests {
    @Test("An in-memory session round-trips and clears idempotently")
    func inMemoryRoundTrip() async throws {
        let store = InMemorySessionStore()

        #expect(try await store.load() == nil)
        try await store.save(fixture)
        expectFixture(try #require(try await store.load()))
        let replacement = StoredSession(
            appleID: fixture.appleID,
            adsid: fixture.adsid,
            xcodeGSToken: "replacement-token"
        )
        try await store.save(replacement)
        let reloaded = try #require(try await store.load())
        #expect(reloaded.xcodeGSToken == "replacement-token")
        #expect(reloaded.teamID == nil)
        try await store.clear()
        try await store.clear()
        #expect(try await store.load() == nil)
    }

    @Test("A file session round-trips with owner-only permissions")
    func fileRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "session.plist")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSessionStore(fileURL: fileURL)

        #expect(try await store.load() == nil)
        try await store.save(fixture)
        expectFixture(try #require(try await store.load()))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: fileURL.path
        )
        try await store.save(fixture)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try await store.clear()
        try await store.clear()
        #expect(try await store.load() == nil)
    }

    @Test("A failed atomic replacement removes its private temporary file")
    func failedReplacementCleansUp() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "session.plist", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: fileURL,
            withIntermediateDirectories: true
        )
        let store = FileSessionStore(fileURL: fileURL)

        await #expect(throws: (any Error).self) {
            try await store.save(fixture)
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        #expect(contents.map(\.lastPathComponent) == ["session.plist"])
        #expect(!contents.contains { $0.lastPathComponent.hasSuffix(".tmp") })
    }

    @Test("Malformed file state throws a typed error")
    func malformedFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "session.plist")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("not a property list".utf8).write(to: fileURL)
        let store = FileSessionStore(fileURL: fileURL)

        await #expect {
            try await store.load()
        } throws: { error in
            (error as? SwiftDunkError)?.code
                == .malformedResponse(
                    key: "stored session",
                    expected: "a valid session property list"
                )
        }
    }

    @Test("A Keychain session round-trips and clears idempotently")
    func keychainRoundTrip() async throws {
        let store = KeychainSessionStore(
            service: "dev.swiftdunk.tests.\(UUID().uuidString)",
            account: "session"
        )

        try await store.clear()
        #expect(try await store.load() == nil)
        try await store.save(fixture)
        expectFixture(try #require(try await store.load()))
        let replacement = StoredSession(
            appleID: fixture.appleID,
            adsid: fixture.adsid,
            xcodeGSToken: "replacement-token"
        )
        try await store.save(replacement)
        let reloaded = try #require(try await store.load())
        #expect(reloaded.xcodeGSToken == "replacement-token")
        #expect(reloaded.teamID == nil)
        try await store.clear()
        try await store.clear()
        #expect(try await store.load() == nil)
    }

    private var fixture: StoredSession {
        StoredSession(
            appleID: "user@example.com",
            adsid: "1234567890",
            xcodeGSToken: "fixture-token",
            teamID: "TEAM123"
        )
    }

    private func expectFixture(_ session: StoredSession) {
        #expect(session.appleID == fixture.appleID)
        #expect(session.adsid == fixture.adsid)
        #expect(session.xcodeGSToken == fixture.xcodeGSToken)
        #expect(session.teamID == fixture.teamID)
    }
}
