/// The credentials needed to restore an authenticated Developer Portal session.
///
/// This value contains a bearer token. Store it only through a suitably protected
/// ``SessionStore`` and never log or display its contents.
public struct StoredSession: Codable, Sendable {
    /// The Apple ID associated with the session.
    public let appleID: String

    /// Apple's account identifier, named `adsid` by GrandSlam.
    public let adsid: String

    /// The Xcode GrandSlam bearer token used by the Developer Portal.
    public let xcodeGSToken: String

    /// The most recently selected team identifier, when one has been selected.
    public let teamID: String?

    /// Creates persisted Developer Portal session credentials.
    public init(
        appleID: String,
        adsid: String,
        xcodeGSToken: String,
        teamID: String? = nil
    ) {
        self.appleID = appleID
        self.adsid = adsid
        self.xcodeGSToken = xcodeGSToken
        self.teamID = teamID
    }
}

/// Durable storage for authenticated Developer Portal sessions.
///
/// Implementations must treat every field as sensitive and must not log stored values.
public protocol SessionStore: Sendable {
    /// Loads the current session.
    /// - Throws: An error when existing state cannot be read or decoded.
    func load() async throws -> StoredSession?

    /// Replaces the current session.
    /// - Throws: An error when the session cannot be encoded or persisted.
    func save(_ session: StoredSession) async throws

    /// Removes the current session.
    ///
    /// Calling this method when no session exists succeeds without changing state.
    /// - Throws: An error when existing state cannot be removed.
    func clear() async throws
}
