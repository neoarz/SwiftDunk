# Anisette

Choose and persist the device-attestation source used by Apple requests.

## Understand Remote v3

``RemoteAnisetteProvider`` speaks the Remote Anisette v3 HTTP and WebSocket protocol.
It provisions a stable client identity, stores that state through
``AnisetteStateStore``, refreshes short-lived headers, coalesces concurrent refreshes,
and retries once after Apple's stale-ADI response.

The default initializer tries ``AnisetteServer/defaults`` in order:

```swift
let anisette = RemoteAnisetteProvider()
```

It starts with `https://ani.neoarz.com/`, then falls back to the StikStore and
SideStore community services if the primary server is unavailable.

Remote services receive request metadata needed to generate anisette headers. A public
service is therefore a privacy, availability, and trust dependency. Review its operator
and policy, or supply a service you control:

```swift
guard let url = URL(string: "https://anisette.example.com") else { return }
let anisette = RemoteAnisetteProvider(server: AnisetteServer(url: url))
```

## Preserve identity

Do not create a fresh anisette identity on every launch. On Apple platforms, the default
``KeychainAnisetteStore`` persists the stable identifier and ADI data. For command-line
tools or caller-selected protected storage, use ``FileAnisetteStateStore``:

```swift
let state = FileAnisetteStateStore(fileURL: protectedFileURL)
let anisette = RemoteAnisetteProvider(stateStore: state)
```

Anisette state is sensitive device identity material. Do not print it, include it in
diagnostics, or sync it through an unprotected store.

## Use your own implementation

Implement ``AnisetteProvider`` when headers come from an in-process implementation or
another trusted source:

```swift
struct MyAnisette: AnisetteProvider {
    let currentHeaders: AnisetteHeaders

    func headers() async throws -> AnisetteHeaders {
        currentHeaders
    }
}
```

Return every required header and an accurate generation date. SwiftDunk rejects stale or
incomplete data with an anisette-related ``SwiftDunkError``.

For deterministic tests, use ``StaticAnisetteProvider`` or a purpose-built fake and
inject the same mock ``HTTPTransport`` into the client under test.
