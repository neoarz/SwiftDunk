package import Foundation

/// A complete Remote Anisette v3 provider with durable device identity and freshness caching.
public actor RemoteAnisetteProvider: AnisetteProvider {
    private let cache: AnisetteCache

    /// Creates a Remote v3 provider with ordered server failover.
    ///
    /// An empty server list reports ``SwiftDunkError/Code/anisetteUnavailable`` when
    /// headers are requested.
    public init(
        servers: [AnisetteServer] = AnisetteServer.defaults,
        stateStore: any AnisetteStateStore = KeychainAnisetteStore(),
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        let webSockets = URLSessionAnisetteWebSocketFactory()
        let backend = FailoverAnisetteProvider(
            providers: servers.map { server in
                RemoteAnisetteBackend(
                    server: server,
                    stateStore: stateStore,
                    transport: transport,
                    webSockets: webSockets,
                    now: Date.init
                )
            }
        )
        cache = AnisetteCache(provider: backend, now: Date.init)
    }

    /// Creates a Remote v3 provider pinned to one server.
    public init(
        server: AnisetteServer,
        stateStore: any AnisetteStateStore = KeychainAnisetteStore(),
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        let backend = RemoteAnisetteBackend(
            server: server,
            stateStore: stateStore,
            transport: transport,
            webSockets: URLSessionAnisetteWebSocketFactory(),
            now: Date.init
        )
        cache = AnisetteCache(provider: backend, now: Date.init)
    }

    package init(
        server: AnisetteServer,
        stateStore: any AnisetteStateStore,
        transport: any HTTPTransport,
        webSockets: any AnisetteWebSocketFactory,
        refreshAfter: TimeInterval,
        hardExpiry: TimeInterval,
        now: @escaping @Sendable () -> Date
    ) {
        let backend = RemoteAnisetteBackend(
            server: server,
            stateStore: stateStore,
            transport: transport,
            webSockets: webSockets,
            now: now
        )
        cache = AnisetteCache(
            provider: backend,
            refreshAfter: refreshAfter,
            hardExpiry: hardExpiry,
            now: now
        )
    }

    /// Returns fresh Remote v3 headers, coalescing concurrent refreshes.
    ///
    /// A stale `adi_pb` is re-provisioned and retried once.
    /// - Throws: ``SwiftDunkError`` when the service is unavailable, provisioning fails,
    ///   persisted state is invalid, or the Security framework rejects Keychain access.
    public func headers() async throws -> AnisetteHeaders {
        try await cache.current()
    }
}
