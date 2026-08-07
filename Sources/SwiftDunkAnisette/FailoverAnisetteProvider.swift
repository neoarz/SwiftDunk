package actor FailoverAnisetteProvider: AnisetteProvider {
    private let providers: [any AnisetteProvider]

    package init(providers: [any AnisetteProvider]) {
        self.providers = providers
    }

    package func headers() async throws -> AnisetteHeaders {
        var lastError: (any Error)?

        for provider in providers {
            do {
                return try await provider.headers()
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        throw SwiftDunkError(code: .anisetteUnavailable)
    }
}
