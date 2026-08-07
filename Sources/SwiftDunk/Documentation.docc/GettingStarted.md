# Getting Started

Restore a protected session when possible, or authenticate and persist a new one.

## Add SwiftDunk

Add the package to an iOS 17, macOS 14, or newer target and import the umbrella module:

```swift
import SwiftDunk
```

SwiftDunk uses Swift 6 strict concurrency. Its actors perform work away from the main
actor; UI code remains responsible for updating main-actor state.

To try the package from its checkout, run `swift run swiftdunk-cli`. The interactive menu
can inspect Portal resources, provision an App ID, or remove the saved session. The same
workflows are available directly as `inspect`, `provision`, and `logout` commands.

## Create an anisette provider

GrandSlam and Developer Portal requests require device-attestation headers:

```swift
let anisette = RemoteAnisetteProvider()
```

The default provider persists its stable identity in the Keychain and fails over across
the configured Remote v3 services. Read <doc:Anisette> before shipping this default in
an app.

## Restore before logging in

Store bearer tokens only through a ``SessionStore``:

```swift
let sessions = KeychainSessionStore()

if let saved = try await sessions.load() {
    let session = try await DeveloperSession(
        restoring: saved,
        anisette: anisette
    )
}
```

Restoration throws when the token is expired, revoked, malformed, or rejected by the
Portal. Decide in your app whether to clear it and present login again.

## Authenticate

Collect passwords with `SecureField` or another non-logging secret input:

```swift
let account = try await Account.login(
    appleID: appleID,
    password: password,
    anisette: anisette
) { challenge in
    let response = try await askUserForTwoFactorResponse(challenge)
    return response
}

let session = try await DeveloperSession(
    account: account,
    anisette: anisette
)
try await sessions.save(await session.stored)
```

For a trusted-device or SMS code, return ``TwoFactorResponse/code(_:)``. Every challenge
carries the account's masked phone numbers. An SMS challenge identifies its current
number through ``TwoFactorChallenge/selectedPhoneNumberID``.

Return ``TwoFactorResponse/sendSMS(phoneNumberID:)`` to send an SMS to one of those
numbers, ``TwoFactorResponse/sendToTrustedDevices`` to switch back to Apple's
trusted-device broadcast, or ``TwoFactorResponse/resendCode`` to repeat the current
delivery method. The callback is invoked again after each delivery request.

If delivery fails, `Account.login` invokes the callback again with
``TwoFactorChallenge/previousDeliveryError`` set. It does not retry or switch methods on
its own. The callback can submit the last code, select another number, choose trusted
devices, or throw an error to cancel the login. Apple service errors retain their numeric
code, title, and message in ``TwoFactorDeliveryFailure`` through
``SwiftDunkError/Code/twoFactorDeliveryFailed(_:)``.

```swift
if let error = challenge.previousDeliveryError,
    case .twoFactorDeliveryFailed(let failure) = error
{
    showDeliveryError(
        code: failure.serviceCode,
        title: failure.title,
        message: failure.message
    )
}
```

For a UI that needs to retain a challenge after a failed request, drive
``AuthenticationSession`` directly. Its ``AuthenticationSession/requestSMSCode(phoneNumberID:)``,
``AuthenticationSession/requestTrustedDeviceCode()``, and
``AuthenticationSession/resendTwoFactorCode()`` methods leave the active challenge usable
when delivery throws.

`Account.login` can throw for transport failures, unsupported SRP variants, failed
server proof verification, invalid codes, rate limiting, anisette failures, malformed
responses, or additional account steps that need Apple's website. Inspect
``SwiftDunkError/code`` rather than matching error text.

## Work with a team

```swift
let teams = try await session.teams()
guard let team = teams.first else { return }

let inventory = try await session.appIDInventory(teamID: team.id)
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

``DeveloperSession/appIDInventory(teamID:)`` includes each App ID's expiration date and
the maximum and remaining registration quota Apple reports for the team. Quota values are
optional because Apple does not include them for every account.

Team-scoped operations remember the selected team in ``DeveloperSession/stored``.
Save that updated value after the operation.

Creating an App ID changes the team's Portal state. Registering a device consumes a
limited device slot and can be effectively irreversible for a year on free accounts.
Revoking a certificate immediately invalidates that certificate and can break installed
apps and other people's workflows. SwiftDunk never registers, deletes, or revokes as a
side effect of an unrelated operation.

## Handle profiles and identities

``ProvisioningProfile/data`` contains Apple's CMS-encoded profile. Call
``ProvisioningProfile/metadata()`` to decode its typed property-list fields:

```swift
let metadata = try profile.metadata()
print("\(metadata.name) expires \(metadata.expirationDate)")
```

The profile itself also includes the summary Apple returned from the Developer Portal:

```swift
print(profile.type ?? "Unknown profile type")
print(profile.distributionMethod ?? "Unknown distribution method")
print(profile.platform ?? "Unknown platform")
```

``ProvisioningProfile/managingApp``, ``ProvisioningProfile/isTemplateProfile``, and
``ProvisioningProfile/isTeamProfile`` are optional because Apple does not include these
values in every response. The Portal's platform summary is separate from the platforms
embedded in ``ProvisioningProfileMetadata/platforms``.

Metadata parsing validates the CMS structure and property-list types but does not make a
general-purpose trust decision about the CMS signer.

``CertificateIdentity/exportPKCS12(password:)`` exports a password-protected identity
on macOS only. On iOS, use the identity's certificate and private-key representations
with an appropriate protected store. Never log or synchronize private-key material
through an unprotected channel.

## Test without Apple

Inject an ``HTTPTransport`` and ``AnisetteProvider`` into each public initializer.
Add the `SwiftDunkTestSupport` product only to your test target, then:

```swift
import SwiftDunk
import SwiftDunkTestSupport
import Testing

@Test
func listsTeamsOffline() async throws {
    let transport = MockTransport { _ in
        HTTPResponse(statusCode: 200, body: Fixtures.listTeamsResponse)
    }
    let session = try await DeveloperSession(
        restoring: StoredSession(
            appleID: "test@example.com",
            adsid: "non-secret-test-account",
            xcodeGSToken: "non-secret-test-token"
        ),
        anisette: .mock,
        transport: transport
    )

    #expect(try await session.teams().map(\.name) == ["Test Team"])
}
```

`MockTransport`, `StaticAnisetteProvider.mock`, and the bundled fixtures keep this test
fully offline. Do not make network access a requirement of a unit test.
