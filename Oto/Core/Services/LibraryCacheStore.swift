import Foundation

/// Persisted Library tab payload for instant cold start; `SessionStore.refresh()` overwrites with network truth.
enum LibraryCacheStore {
    private static let storageKey = "storymusic.library.snapshot-v1"

    struct Snapshot: Codable, Equatable {
        var userId: Int
        var profile: CachedUserProfile
        var playlists: [CachedUserPlaylist]
        var collectedPlaylists: [CachedUserPlaylist]
        var collectedAlbums: [AlbumSummary]
        var likedSongs: [Track]
        var savedAt: Date
    }

    struct CachedUserProfile: Codable, Equatable {
        var id: Int
        var nickname: String
        var signature: String
        var avatarURL: String

        func toModel() -> UserProfileSummary {
            UserProfileSummary(id: id, nickname: nickname, signature: signature, avatarURL: avatarURL)
        }

        static func from(_ p: UserProfileSummary) -> CachedUserProfile {
            CachedUserProfile(id: p.id, nickname: p.nickname, signature: p.signature, avatarURL: p.avatarURL)
        }
    }

    struct CachedUserPlaylist: Codable, Equatable {
        var id: Int
        var name: String
        var trackCount: Int
        var playCount: Int
        var coverURL: String
        var creatorName: String?

        func toModel() -> UserPlaylistSummary {
            UserPlaylistSummary(
                id: id,
                name: name,
                trackCount: trackCount,
                playCount: playCount,
                coverURL: coverURL,
                creatorName: creatorName
            )
        }

        static func from(_ p: UserPlaylistSummary) -> CachedUserPlaylist {
            CachedUserPlaylist(
                id: p.id,
                name: p.name,
                trackCount: p.trackCount,
                playCount: p.playCount,
                coverURL: p.coverURL,
                creatorName: p.creatorName
            )
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> Snapshot? {
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    static func save(
        profile: UserProfileSummary,
        playlists: [UserPlaylistSummary],
        collectedPlaylists: [UserPlaylistSummary],
        collectedAlbums: [AlbumSummary],
        likedSongs: [Track],
        to defaults: UserDefaults = .standard
    ) {
        let snapshot = Snapshot(
            userId: profile.id,
            profile: .from(profile),
            playlists: playlists.map(CachedUserPlaylist.from),
            collectedPlaylists: collectedPlaylists.map(CachedUserPlaylist.from),
            collectedAlbums: collectedAlbums,
            likedSongs: likedSongs,
            savedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}
