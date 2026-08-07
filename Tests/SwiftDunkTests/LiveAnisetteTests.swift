import Foundation
import SwiftDunk
import Testing

extension Tag {
    @Tag static var integration: Self
}

@Suite(
    "Live Anisette",
    .tags(.integration),
    .enabled(if: ProcessInfo.processInfo.shouldRunSwiftDunkLiveAnisetteTests)
)
struct LiveAnisetteTests {
    @Test("The default Remote v3 provider returns all required headers")
    func fetchesRemoteHeaders() async throws {
        let headers = try await LiveTestServices.anisette.headers()

        #expect(headers.values.count == 10)
        #expect(headers.header("X-Apple-I-MD")?.isEmpty == false)
        #expect(headers.header("X-Apple-I-MD-M")?.isEmpty == false)
        #expect(headers.header("X-Apple-I-MD-RINFO")?.isEmpty == false)
    }
}

extension ProcessInfo {
    fileprivate var shouldRunSwiftDunkLiveAnisetteTests: Bool {
        environment["SWIFTDUNK_RUN_LIVE_TESTS"] == "1"
    }
}
