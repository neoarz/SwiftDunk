public import Foundation
public import SwiftDunk

/// Sanitized model and wire fixtures for consumer test suites.
public enum Fixtures {
    /// Creates a non-secret authenticated-account fixture.
    ///
    /// The fixture transport deliberately fails network operations. Supply a
    /// ``MockTransport`` to the API under test when request behavior matters.
    public static func account(appleID: String = "test@example.com") -> Account {
        Account(
            appleID: appleID,
            firstName: "Test",
            lastName: "User",
            dsid: "1234567890",
            idmsToken: "fixture-idms-token",
            sessionKey: Data(repeating: 0xA5, count: 32),
            context: Data([0xCA, 0xFE]),
            anisette: .mock,
            transport: MockTransport { _ in
                throw SwiftDunkError(code: .network)
            }
        )
    }

    /// Creates a deterministic Developer Program team fixture.
    public static func team(id: String = "ABCDE12345") -> Team {
        Team(
            id: Team.ID(rawValue: id),
            name: "Test Team",
            status: "active",
            type: "Company/Organization",
            provisioningSettings: TeamProvisioningSettings(
                canDeveloperRegisterDevices: true,
                canDeveloperAddAppIDs: true,
                canDeveloperUpdateAppIDs: true
            )
        )
    }

    /// A sanitized successful QH `listTeams.action` property-list response.
    public static let listTeamsResponse = Data(
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>resultCode</key><integer>0</integer>
          <key>teams</key>
          <array>
            <dict>
              <key>teamId</key><string>ABCDE12345</string>
              <key>name</key><string>Test Team</string>
              <key>status</key><string>active</string>
              <key>xcodeFreeOnly</key><false/>
            </dict>
          </array>
        </dict>
        </plist>
        """.utf8
    )
}
