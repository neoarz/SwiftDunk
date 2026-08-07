import Foundation
import SwiftDunk
import SwiftDunkTestSupport
import Testing

@Suite("Anisette values")
struct AnisetteValueTests {
    @Test("Header lookup changes only key casing")
    func headerLookupPreservesValue() {
        let headers = AnisetteHeaders(
            values: ["X-Mme-Client-Info": "Case-Sensitive VALUE"],
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(headers.header("x-mme-client-info") == "Case-Sensitive VALUE")
        #expect(headers.header("missing") == nil)
    }

    @Test("Client info parses and rebuilds all three components")
    func clientInfoRoundTrip() throws {
        let raw =
            "<MacBookPro13,2> <macOS;13.1;22C65> "
            + "<com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)>"
        let parsed = try #require(ClientInfo(parsing: raw))

        #expect(parsed.hardware == "MacBookPro13,2")
        #expect(parsed.os == "macOS;13.1;22C65")
        #expect(parsed.client == "com.apple.AuthKit/1 (com.apple.dt.Xcode/3594.4.19)")
        #expect(parsed.stringValue == raw)
        #expect(ClientInfo(parsing: "<one> <two>") == nil)
        #expect(ClientInfo(parsing: "<one> <two> <three> trailing") == nil)
    }

    @Test("Remote v3 identity derivations are lowercase and stable")
    func remoteIdentityDerivations() throws {
        let state = try AnisetteState(
            keychainIdentifier: Data(UInt8(0)...UInt8(15))
        )

        #expect(state.deviceID == "00010203-0405-0607-0809-0a0b0c0d0e0f")
        #expect(
            state.localUserID
                == "be45cb2605bf36bebde684841a28f0fd43c69850a3dce5fedba69928ee3a8991"
        )
    }

    @Test("The default server list starts with ani.neoarz.com")
    func defaultServerOrder() throws {
        let expectedURL = try #require(
            URL(string: "https://ani.neoarz.com/v3/get_headers")
        )

        #expect(AnisetteServer.defaults == [.default, .stikStore, .sideStore])
        #expect(
            try AnisetteServer.default.endpoint(path: "v3/get_headers")
                == expectedURL
        )
    }
}

@Suite("Anisette cache")
struct AnisetteCacheTests {
    @Test("A stale refresh failure falls back only until hard expiry")
    func staleFallbackAndHardExpiry() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = LockedTestClock(start)
        let cached = AnisetteHeaders(values: ["value": "initial"], generatedAt: start)
        let provider = ScriptedAnisetteProvider(outcomes: [
            .success(cached),
            .failure(SwiftDunkError(code: .anisetteUnavailable)),
            .failure(SwiftDunkError(code: .anisetteUnavailable)),
        ])
        let cache = AnisetteCache(provider: provider, now: clock.now)

        #expect(try await cache.current() == cached)
        clock.advance(by: 61)
        #expect(try await cache.current() == cached)
        clock.advance(by: 30)
        await #expect(throws: SwiftDunkError.self) {
            try await cache.current()
        }
        #expect(await provider.requestCount == 3)
    }

    @Test("Concurrent stale reads coalesce onto one provider refresh")
    func concurrentRefreshesCoalesce() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let expected = AnisetteHeaders(values: ["value": "fresh"], generatedAt: now)
        let provider = BlockingAnisetteProvider(result: expected)
        let cache = AnisetteCache(provider: provider, now: { now })

        let reads = Task {
            try await withThrowingTaskGroup(of: AnisetteHeaders.self) { group in
                for _ in 0..<12 {
                    group.addTask {
                        try await cache.current()
                    }
                }
                var values: [AnisetteHeaders] = []
                for try await value in group {
                    values.append(value)
                }
                return values
            }
        }

        await provider.waitUntilStarted()
        await provider.release()
        let values = try await reads.value

        #expect(values.count == 12)
        #expect(values.allSatisfy { $0 == expected })
        #expect(await provider.requestCount == 1)
    }

    @Test("A provider returning headers outside the clock window throws clock skew")
    func staleProviderResultThrowsClockSkew() async {
        let now = Date(timeIntervalSince1970: 5_000)
        let provider = StaticAnisetteProvider(
            values: [:],
            generatedAt: now.addingTimeInterval(-91)
        )
        let cache = AnisetteCache(provider: provider, now: { now })

        await #expect {
            try await cache.current()
        } throws: { error in
            guard let error = error as? SwiftDunkError else { return false }
            return error.code == .anisetteClockSkew
        }
    }

    @Test("A clock rollback beyond the allowed window rejects cached headers")
    func clockRollbackRejectsCachedHeaders() async throws {
        let start = Date(timeIntervalSince1970: 5_000)
        let clock = LockedTestClock(start)
        let cached = AnisetteHeaders(values: ["value": "initial"], generatedAt: start)
        let provider = ScriptedAnisetteProvider(outcomes: [.success(cached)])
        let cache = AnisetteCache(provider: provider, now: clock.now)

        #expect(try await cache.current() == cached)
        clock.advance(by: -91)

        await #expect {
            try await cache.current()
        } throws: { error in
            (error as? SwiftDunkError)?.code == .anisetteClockSkew
        }
        #expect(await provider.requestCount == 1)
    }

    @Test("A clock rollback during a failed refresh does not return cached headers")
    func clockRollbackRejectsStaleFallback() async throws {
        let start = Date(timeIntervalSince1970: 6_000)
        let clock = LockedTestClock(start)
        let cached = AnisetteHeaders(values: ["value": "initial"], generatedAt: start)
        let provider = ClockRollingAnisetteProvider(
            cached: cached,
            clock: clock,
            rollback: 152
        )
        let cache = AnisetteCache(provider: provider, now: clock.now)

        #expect(try await cache.current() == cached)
        clock.advance(by: 61)

        await #expect {
            try await cache.current()
        } throws: { error in
            (error as? SwiftDunkError)?.code == .anisetteClockSkew
        }
        #expect(await provider.requestCount == 2)
    }
}

@Suite("Anisette server failover")
struct AnisetteFailoverTests {
    @Test("The next configured provider is used after an unavailable server")
    func triesProvidersInOrder() async throws {
        let expected = AnisetteHeaders(
            values: ["X-Apple-I-MD": "fresh"],
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let first = ScriptedAnisetteProvider(
            outcomes: [.failure(SwiftDunkError(code: .anisetteUnavailable))]
        )
        let second = ScriptedAnisetteProvider(outcomes: [.success(expected)])
        let provider = FailoverAnisetteProvider(providers: [first, second])

        #expect(try await provider.headers() == expected)
        #expect(await first.requestCount == 1)
        #expect(await second.requestCount == 1)
    }

    @Test("An empty server list fails descriptively")
    func emptyListFails() async {
        let provider = FailoverAnisetteProvider(providers: [])

        await #expect {
            try await provider.headers()
        } throws: { error in
            (error as? SwiftDunkError)?.code == .anisetteUnavailable
        }
    }
}

@Suite("Anisette state stores")
struct AnisetteStateStoreTests {
    @Test("File state round-trips without changing the stable identifier")
    func fileRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftDunk-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("state.plist")
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let expected = try AnisetteState(
            keychainIdentifier: Data(UInt8(0)...UInt8(15)),
            adiPB: Data([0xAA, 0xBB])
        )
        let store = FileAnisetteStateStore(fileURL: fileURL)

        #expect(try await store.load() == nil)
        try await store.save(expected)
        #expect(try await store.load() == expected)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: fileURL.path
        )
        try await store.save(expected)
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
    }

    @Test("Malformed persisted identifiers throw instead of regenerating")
    func malformedIdentifierThrows() throws {
        let encoder = PropertyListEncoder()
        let malformed = try encoder.encode([
            "keychain_identifier": Data([0x01]),
            "adi_pb": Data(),
        ])

        #expect {
            try PropertyListDecoder().decode(AnisetteState.self, from: malformed)
        } throws: { error in
            guard let error = error as? SwiftDunkError else { return false }
            return error.code
                == .malformedResponse(
                    key: "keychainIdentifier",
                    expected: "exactly 16 bytes"
                )
        }
    }
}
