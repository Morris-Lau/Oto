import Foundation
import SwiftUI

extension Notification.Name {
    /// Posted on the main thread after Discover home caches are updated from the network.
    static let otoDiscoverHomeCacheDidUpdate = Notification.Name("oto.discoverHomeCacheDidUpdate")
}

/// Runs the same Discover home network fetch as `DiscoverView.loadDiscoverContent`, dedupes concurrent callers, and persists caches.
actor DiscoverHomeRefreshService {
    static let shared = DiscoverHomeRefreshService()

    /// Set to `true` to include 私人 FM fetch (must match `DiscoverView` hero configuration).
    private static let isPersonalFMEnabled = true

    private var inFlight: Task<Void, Never>?

    func refreshDiscoverHome() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { await self.performRefresh() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performRefresh() async {
        let seedDaily = await MainActor.run { DailyRecommendationsStore.loadValidCache() }
        if let seedDaily {
            await MainActor.run {
                RemoteImageView.prefetch(urlStrings: seedDaily.map(\.coverURL))
            }
        }

        async let fetchedDaily: [Track]? = {
            try? await NetEaseService.shared.fetchDailyRecommendations()
        }()

        async let recommendedPlaylistsTask: [PlaylistSummary] = {
            (try? await NetEaseService.shared.fetchRecommendedPlaylists(limit: 6)) ?? []
        }()

        async let dailyPlaylistRecommendationsTask: [PlaylistSummary] = {
            (try? await NetEaseService.shared.fetchDailyRecommendedPlaylists(limit: 6)) ?? []
        }()

        async let personalFMTracksTask: [Track] = {
            guard Self.isPersonalFMEnabled else { return [] }
            return (try? await NetEaseService.shared.fetchPersonalFM(limit: 3)) ?? []
        }()

        async let recommendedArtistsTask: [ArtistSummary] = {
            (try? await NetEaseService.shared.fetchRecommendedArtists(limit: 6)) ?? []
        }()

        let dailyFetched = await fetchedDaily
        var dailyRecommendations = seedDaily ?? []
        if let dailyFetched {
            dailyRecommendations = dailyFetched
            await MainActor.run {
                DailyRecommendationsStore.save(tracks: dailyFetched)
                RemoteImageView.prefetch(urlStrings: dailyFetched.map(\.coverURL))
            }
        }

        let recommendedPlaylists = await recommendedPlaylistsTask
        let dailyPlaylistRecommendations = await dailyPlaylistRecommendationsTask

        // Run after other fetches so `AppRootView` has usually finished `applyLibraryCacheIfAvailable()`,
        // and read `profile` here (not from a parallel `async let` started at launch) to avoid wiping为你推荐.
        let userID = await MainActor.run { SessionStore.shared.profile?.id }
        let likedSimilarRaw: [Track]
        if let userID {
            likedSimilarRaw = (try? await NetEaseService.shared.fetchDiscoverLikedSimilarTracks(userID: userID, limit: 24)) ?? []
        } else {
            likedSimilarRaw = []
        }
        var likedSimilarTracks = Self.evenedLikedSimilarTracksForDisplay(likedSimilarRaw)
        let hasSessionCookie = await MainActor.run { SessionPersistence.loadCookieString() != nil }
        if likedSimilarTracks.isEmpty, userID == nil, hasSessionCookie,
           let previous = DiscoverHomeCacheStore.load()?.likedSimilarTracks, !previous.isEmpty {
            likedSimilarTracks = Self.evenedLikedSimilarTracksForDisplay(previous)
        }
        if !likedSimilarTracks.isEmpty {
            await MainActor.run {
                RemoteImageView.prefetch(urlStrings: likedSimilarTracks.map(\.coverURL))
            }
        }

        let personalFMTracks = await personalFMTracksTask
        let recommendedArtists = await recommendedArtistsTask

        if !recommendedArtists.isEmpty {
            await MainActor.run {
                RemoteImageView.prefetch(urlStrings: recommendedArtists.map(\.avatarURL))
            }
        }

        await MainActor.run {
            DiscoverHomeCacheStore.save(
                dailyRecommendations: dailyRecommendations,
                recommendedPlaylists: recommendedPlaylists,
                dailyPlaylistRecommendations: dailyPlaylistRecommendations,
                personalFMTracks: personalFMTracks,
                likedSimilarTracks: likedSimilarTracks,
                recommendedArtists: recommendedArtists
            )
            NotificationCenter.default.post(name: .otoDiscoverHomeCacheDidUpdate, object: nil)
        }

        let hasValidDaily = await MainActor.run { DailyRecommendationsStore.loadValidCache() != nil }
        if hasValidDaily {
            DiscoverDailyRefreshCoordinator.markRefreshCompletedForToday()
        }
    }

    /// 与 `DiscoverView` 一致：两排卡片时总数为偶数；仅 1 首时保留。
    private static func evenedLikedSimilarTracksForDisplay(_ tracks: [Track]) -> [Track] {
        guard tracks.count > 1, !tracks.count.isMultiple(of: 2) else { return tracks }
        return Array(tracks.dropLast())
    }
}

/// Triggers a Discover home refresh on the first `ScenePhase.active` of a new local calendar day until today's data is cached.
enum DiscoverDailyRefreshCoordinator {
    static let lastRefreshDayStorageKey = "storymusic.discover.last-daily-foreground-refresh-day"

    static func handleSceneBecameActive(defaults: UserDefaults = .standard) {
        let today = CalendarDayKey.string()
        if defaults.string(forKey: lastRefreshDayStorageKey) == today { return }
        Task {
            await DiscoverHomeRefreshService.shared.refreshDiscoverHome()
        }
    }

    static func markRefreshCompletedForToday(defaults: UserDefaults = .standard) {
        defaults.set(CalendarDayKey.string(), forKey: lastRefreshDayStorageKey)
    }

    static func resetForegroundRefreshSchedule(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lastRefreshDayStorageKey)
    }
}
