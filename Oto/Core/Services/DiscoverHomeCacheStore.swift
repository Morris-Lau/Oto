import Foundation

/// Persisted Discover tab payload for instant cold start; network refresh runs afterward.
enum DiscoverHomeCacheStore {
    private static let storageKey = "storymusic.discover.home-snapshot-v2"

    struct Snapshot: Codable {
        var dailyRecommendations: [Track]
        var recommendedPlaylists: [PlaylistSummary]
        var dailyPlaylistRecommendations: [PlaylistSummary]
        var personalFMTracks: [Track]
        var likedSimilarTracks: [Track]
        var recommendedArtists: [ArtistSummary]
        var savedAt: Date
    }

    static func load() -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    static func save(
        dailyRecommendations: [Track],
        recommendedPlaylists: [PlaylistSummary],
        dailyPlaylistRecommendations: [PlaylistSummary],
        personalFMTracks: [Track],
        likedSimilarTracks: [Track],
        recommendedArtists: [ArtistSummary]
    ) {
        let snapshot = Snapshot(
            dailyRecommendations: dailyRecommendations,
            recommendedPlaylists: recommendedPlaylists,
            dailyPlaylistRecommendations: dailyPlaylistRecommendations,
            personalFMTracks: personalFMTracks,
            likedSimilarTracks: likedSimilarTracks,
            recommendedArtists: recommendedArtists,
            savedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: "storymusic.discover.home-snapshot-v1")
    }
}
