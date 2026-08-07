# SwiftDunk

SwiftDunk does Apple ID login and Developer Portal work from Swift. SRP login, 2FA over trusted devices or SMS, app tokens, Remote Anisette v3, saved sessions. On the portal side: teams, devices, App IDs, app groups, capabilities, certificates and provisioning profiles. It'll also generate RSA keys, CSRs, and matched signing identities.

> [!WARNING]
> None of this is documented by Apple, and it can break without warning. Saved sessions and anisette state are credentials. Treat them like the password, and keep them out of logs, analytics, and crash reports.

SwiftDunk doesn't sign IPAs or touch Mach-O.

## Requirements

- Swift 6.2 or newer
- iOS 17 or newer
- macOS 14 or newer

## Install

In Xcode, **File → Add Package Dependencies**, then:

```text
https://github.com/neoarz/SwiftDunk.git
```

No tagged release yet, so point at `main`:

```swift
dependencies: [
    .package(
        url: "https://github.com/neoarz/SwiftDunk.git",
        branch: "main"
    )
]
```

Pin a commit if you need reproducible builds. Add the `SwiftDunk` product to your target and import it:

```swift
import SwiftDunk
```

## Sign in

Try the saved session first and only ask for a password when there's nothing to restore:

```swift
func developerSession(
    appleID: String,
    password: String,
    codeProvider: @escaping @Sendable (TwoFactorChallenge) async throws
        -> TwoFactorResponse
) async throws -> DeveloperSession {
    let anisette = RemoteAnisetteProvider()
    let sessions = KeychainSessionStore()

    if let saved = try await sessions.load(),
        saved.appleID.lowercased() == appleID.lowercased()
    {
        return try await DeveloperSession(restoring: saved, anisette: anisette)
    }

    let account = try await Account.login(
        appleID: appleID,
        password: password,
        anisette: anisette,
        onTwoFactor: codeProvider
    )
    let session = try await DeveloperSession(account: account, anisette: anisette)
    try await sessions.save(await session.stored)
    return session
}
```

The 2FA callback gets the current challenge. Return `.code(code)` for a trusted-device or SMS code. To move from a trusted device to SMS, pick one of the phone numbers Apple gave you and return `.sendSMS(phoneNumberID:)` — the callback fires again once the text is out.

Read passwords through `SecureField` or something else that doesn't echo them.

SwiftDunk doesn't use `@MainActor`. If a result needs to touch your UI, make that hop yourself.

## Developer Portal

Once you have a `DeveloperSession`, the portal calls hang off it:

```swift
let teams = try await session.teams()
guard let team = teams.first else { return }

let devices = try await session.devices(teamID: team.id)
let appIDInventory = try await session.appIDInventory(teamID: team.id)
let appID = try await session.ensureAppID(
    teamID: team.id,
    name: "My App",
    identifier: "com.example.my-app"
)
let profile = try await session.provisioningProfile(
    teamID: team.id,
    appIDID: appID.id
)
```

`ensureAppID` reuses an existing App ID with the same bundle identifier. `appIDInventory` also hands back each App ID's expiration date, plus Apple's reported maximum and remaining registration quota when those values are present.

Watch out for the calls that change account state. Registering a device eats one of the team's device slots and free accounts generally can't get it back for a year. Revoking a certificate can break installed apps and other people's signing setups, so SwiftDunk never picks one to revoke on its own.

## Try the CLI

There's a command-line example with three workflows:

```sh
swift run swiftdunk-cli inspect
swift run swiftdunk-cli provision
swift run swiftdunk-cli logout
```

`inspect` reads account, team, device, App ID and certificate info without changing anything. `provision` ensures an App ID and fetches its provisioning profile. `logout` drops the saved session. Run it with no argument for an interactive menu.

Passwords are read without echoing. After a successful login the later commands restore from Keychain instead of asking again. During 2FA the CLI can resend the current code, switch between trusted-device and SMS delivery, and pick among the phone numbers Apple returns.

A free Apple account works fine, but Apple won't create a provisioning profile until the team has at least one registered device.

## Tests

The normal suite is fully offline:

```sh
swift test
```

Apps using SwiftDunk can add the `SwiftDunkTestSupport` product to their test target. It ships `MockTransport`, fixtures, and `StaticAnisetteProvider.mock`, so your tests never have to talk to Apple.

The live checks are opt-in:

```sh
SWIFTDUNK_RUN_LIVE_TESTS=1 swift test --filter Live
```

That'll test anisette without an Apple ID. For live authentication too, set `SWIFTDUNK_APPLE_ID` and `SWIFTDUNK_PASSWORD` in your shell without echoing them or leaving them in history. The test opens a native prompt if Apple asks for a 2FA code.

## Documentation

Full API reference and longer setup notes live in [SwiftDunk's DocC documentation](https://neoarz.github.io/SwiftDunk/).
