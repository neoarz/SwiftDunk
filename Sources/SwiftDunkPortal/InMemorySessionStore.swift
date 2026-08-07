/// An in-memory session store for tests and intentionally ephemeral sessions.
public actor InMemorySessionStore: SessionStore {
    private var session: StoredSession?

    /// Creates an in-memory store.
    public init(session: StoredSession? = nil) {
        self.session = session
    }

    /// Loads the current in-memory session.
    /// - Throws: This implementation does not throw.
    public func load() async throws -> StoredSession? {
        session
    }

    /// Replaces the current in-memory session.
    /// - Throws: This implementation does not throw.
    public func save(_ session: StoredSession) async throws {
        self.session = session
    }

    /// Removes the current in-memory session.
    /// - Throws: This implementation does not throw.
    public func clear() async throws {
        session = nil
    }
}
