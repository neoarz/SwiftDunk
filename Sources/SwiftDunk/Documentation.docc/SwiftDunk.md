# ``SwiftDunk``

Authenticate with Apple's GrandSlam service and work with Developer Portal resources.

## Overview

SwiftDunk provides a typed, concurrency-safe API for SRP authentication, two-factor
authentication, app tokens, session persistence, Developer Portal resources,
certificates, CSRs, and provisioning profiles on iOS and macOS.

SwiftDunk uses undocumented Apple services that may change without notice. It is not
affiliated with Apple. Never log credentials, app tokens, session tokens, or anisette
state.

Start with <doc:GettingStarted>, then read <doc:Anisette> before choosing a Remote v3
service.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Anisette>

### Authentication

- ``Account``
- ``AuthenticationSession``
- ``LoginStep``
- ``TwoFactorChallenge``
- ``TwoFactorDeliveryFailure``
- ``TwoFactorResponse``

### Anisette APIs

- ``AnisetteProvider``
- ``RemoteAnisetteProvider``
- ``StaticAnisetteProvider``
- ``AnisetteStateStore``

### Developer Portal

- ``DeveloperSession``
- ``Team``
- ``Device``
- ``AppID``
- ``AppGroup``
- ``Capability``
- ``ProvisioningProfile``

### Certificates

- ``CertificateManager``
- ``CertificateIdentity``
- ``CertificateSubject``
- ``PrivateKeyStore``
- ``ProvisioningProfileMetadata``

### Persistence and testing seams

- ``SessionStore``
- ``StoredSession``
- ``KeychainSessionStore``
- ``FileSessionStore``
- ``HTTPTransport``
- ``PlistValue``
- ``SwiftDunkError``
