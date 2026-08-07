package import Foundation

package actor AnisetteCache {
    private let provider: any AnisetteProvider
    private let now: @Sendable () -> Date
    private let refreshAfter: TimeInterval
    private let hardExpiry: TimeInterval

    private var cached: AnisetteHeaders?
    private var refreshTask: Task<AnisetteHeaders, any Error>?
    private var refreshGeneration = 0

    package init(
        provider: any AnisetteProvider,
        refreshAfter: TimeInterval = AnisetteConstants.refreshAfter,
        hardExpiry: TimeInterval = AnisetteConstants.hardExpiry,
        now: @escaping @Sendable () -> Date
    ) {
        self.provider = provider
        self.refreshAfter = refreshAfter
        self.hardExpiry = hardExpiry
        self.now = now
    }

    package func current() async throws -> AnisetteHeaders {
        let currentDate = now()
        if let cached {
            let cachedAge = age(of: cached, at: currentDate)
            guard cachedAge >= -hardExpiry else {
                throw SwiftDunkError(code: .anisetteClockSkew)
            }
            if cachedAge < refreshAfter {
                return cached
            }
        }

        if let refreshTask {
            return try await value(
                from: refreshTask,
                generation: refreshGeneration
            )
        }

        refreshGeneration += 1
        let generation = refreshGeneration
        let provider = self.provider
        let task = Task {
            try await provider.headers()
        }
        refreshTask = task
        return try await value(from: task, generation: generation)
    }

    private func value(
        from task: Task<AnisetteHeaders, any Error>,
        generation: Int
    ) async throws -> AnisetteHeaders {
        do {
            let refreshed = try await task.value
            let refreshedAge = age(of: refreshed, at: now())
            guard refreshedAge <= hardExpiry, refreshedAge >= -hardExpiry else {
                throw SwiftDunkError(code: .anisetteClockSkew)
            }
            // task.value suspends, so only this generation can update the cache
            if refreshGeneration == generation {
                cached = refreshed
                refreshTask = nil
            }
            return refreshed
        } catch {
            if refreshGeneration == generation {
                refreshTask = nil
            }
            if let cached {
                let cachedAge = age(of: cached, at: now())
                guard cachedAge >= -hardExpiry else {
                    throw SwiftDunkError(code: .anisetteClockSkew)
                }
                if cachedAge <= hardExpiry {
                    return cached
                }
            }
            throw error
        }
    }

    private func age(of headers: AnisetteHeaders, at date: Date) -> TimeInterval {
        date.timeIntervalSince(headers.generatedAt)
    }
}
