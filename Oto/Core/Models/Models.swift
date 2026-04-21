import Foundation

struct Track: Identifiable, Codable, Equatable {
    let id: Int
    let title: String
    let artist: String
    let album: String
    let albumID: Int?
    let artistID: Int?
    let coverURL: String
    let audioURL: String
    let audioType: String?

    init(
        id: Int,
        title: String,
        artist: String,
        album: String,
        albumID: Int?,
        artistID: Int? = nil,
        coverURL: String,
        audioURL: String,
        audioType: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.albumID = albumID
        self.artistID = artistID
        self.coverURL = coverURL
        self.audioURL = audioURL
        self.audioType = audioType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.artist = try c.decode(String.self, forKey: .artist)
        self.album = try c.decode(String.self, forKey: .album)
        self.albumID = try c.decodeIfPresent(Int.self, forKey: .albumID)
        self.artistID = try c.decodeIfPresent(Int.self, forKey: .artistID)
        self.coverURL = try c.decode(String.self, forKey: .coverURL)
        self.audioURL = try c.decode(String.self, forKey: .audioURL)
        self.audioType = try c.decodeIfPresent(String.self, forKey: .audioType)
    }
}

enum PlaybackMode: String, Codable, CaseIterable {
    case listLoop
    case singleLoop
    case shuffle
}

enum PlaybackSourceKind: String, Codable, Equatable {
    case playlist
    case album
    case artist
    case liked
    case singleTrack
    case search
    case recommendation
}

/// Built-in Discover recommendation rows (stable across locales and persistence).
enum SystemRecommendationKind: String, Codable, Equatable {
    case dailyRecommendations
    case personalFM
    case likedSimilar
}

struct PlaybackSource: Codable, Equatable {
    let kind: PlaybackSourceKind
    let label: String
    let title: String
    let id: Int?
    let systemRecommendationKind: SystemRecommendationKind?

    init(
        kind: PlaybackSourceKind,
        label: String,
        title: String,
        id: Int?,
        systemRecommendationKind: SystemRecommendationKind? = nil
    ) {
        self.kind = kind
        self.label = label
        self.title = title
        self.id = id
        self.systemRecommendationKind = systemRecommendationKind
    }
}

extension PlaybackSource {
    static let discoverDailyRecommendations = PlaybackSource(
        kind: .recommendation,
        label: String(localized: String.LocalizationValue("playing_from_daily")),
        title: String(localized: String.LocalizationValue("source_title_daily")),
        id: nil,
        systemRecommendationKind: .dailyRecommendations
    )

    static let discoverPersonalFM = PlaybackSource(
        kind: .recommendation,
        label: String(localized: String.LocalizationValue("playing_from_personal_fm")),
        title: String(localized: String.LocalizationValue("source_title_personal_fm")),
        id: nil,
        systemRecommendationKind: .personalFM
    )

    static let discoverLikedSimilar = PlaybackSource(
        kind: .recommendation,
        label: String(localized: String.LocalizationValue("playing_from_for_you")),
        title: String(localized: String.LocalizationValue("source_title_for_you")),
        id: nil,
        systemRecommendationKind: .likedSimilar
    )

    /// Maps discover recommendation playback to navigation targets (includes legacy persisted titles).
    func pendingNavigationForRecommendationSource() -> PendingNavigation? {
        guard kind == .recommendation else { return nil }
        if let systemRecommendationKind {
            switch systemRecommendationKind {
            case .dailyRecommendations: return .dailyRecommendations
            case .personalFM: return .personalFM
            case .likedSimilar: return .likedSimilar
            }
        }
        if title == "每日推荐" { return .dailyRecommendations }
        if title == "私人 FM" { return .personalFM }
        if title == "为你推荐" { return .likedSimilar }
        return nil
    }
}

enum PendingNavigation: Equatable, Hashable {
    case playlist(id: Int)
    case album(id: Int)
    case artist(id: Int)
    /// Full list is rebuilt from the current player queue when presented.
    case dailyRecommendations
    case personalFM
    case likedSimilar
}

/// Inline full-screen lists opened from Discover hero strips (not used for recommended playlist tiles).
enum DiscoverInlineList: Hashable, Sendable {
    case dailyRecommendations
    case personalFM
    case likedSimilar
}

/// Pairs Discover hero / shelf artwork with pushed screens via `matchedTransitionSource` + `navigationTransition(.zoom)` (iOS 18+).
enum DiscoverNavigationTransitionSource: Hashable, Sendable {
    case dailyRecommendations
    case personalFM
    case likedSimilar
    case recommendedPlaylist(id: Int)
}

struct PlaybackContext: Codable, Equatable {
    let queue: [Track]
    let currentIndex: Int
    let currentTime: Double
    let duration: Double
    let isPlaying: Bool
    let timestamp: Date
    let playbackMode: PlaybackMode
    let playbackSource: PlaybackSource?

    init(
        queue: [Track],
        currentIndex: Int,
        currentTime: Double,
        duration: Double = 0,
        isPlaying: Bool,
        timestamp: Date,
        playbackMode: PlaybackMode = .listLoop,
        playbackSource: PlaybackSource? = nil
    ) {
        self.queue = queue
        self.currentIndex = currentIndex
        self.currentTime = currentTime
        self.duration = duration
        self.isPlaying = isPlaying
        self.timestamp = timestamp
        self.playbackMode = playbackMode
        self.playbackSource = playbackSource
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queue = try container.decode([Track].self, forKey: .queue)
        self.currentIndex = try container.decode(Int.self, forKey: .currentIndex)
        self.currentTime = try container.decode(Double.self, forKey: .currentTime)
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        self.isPlaying = try container.decode(Bool.self, forKey: .isPlaying)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.playbackMode = try container.decodeIfPresent(PlaybackMode.self, forKey: .playbackMode) ?? .listLoop
        self.playbackSource = try container.decodeIfPresent(PlaybackSource.self, forKey: .playbackSource)
    }

    var validCurrentTrack: Track? {
        guard currentIndex >= 0 && currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }
}

struct MusicStory: Identifiable, Codable, Equatable {
    let id: Int
    let title: String
    let body: String
    let coverImageURL: String
}

struct QRLoginSession: Equatable {
    let key: String
    let qrURL: String
}

enum QRLoginState: Equatable {
    case idle
    case waitingScan
    case waitingConfirm
    case expired
    case success
    case failed(String)
}

struct UserProfileSummary: Identifiable, Equatable {
    let id: Int
    let nickname: String
    let signature: String
    let avatarURL: String
}

struct UserPlaylistSummary: Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let trackCount: Int
    let playCount: Int
    let coverURL: String
    /// 收藏的歌单展示创建者昵称；自建歌单为 `nil`
    let creatorName: String?

    init(
        id: Int,
        name: String,
        trackCount: Int,
        playCount: Int,
        coverURL: String,
        creatorName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.trackCount = trackCount
        self.playCount = playCount
        self.coverURL = coverURL
        self.creatorName = creatorName
    }
}

struct ArtistSummary: Identifiable, Equatable, Hashable, Codable {
    let id: Int
    let name: String
    let alias: String
    let avatarURL: String
}

struct AlbumSummary: Identifiable, Equatable, Hashable, Codable {
    let id: Int
    let name: String
    let artist: String
    let coverURL: String
    let trackCount: Int
}

struct PlaylistSummary: Identifiable, Equatable, Hashable, Codable {
    let id: Int
    let name: String
    let creatorName: String
    let coverURL: String
    let trackCount: Int
}

struct PlaylistDetailModel: Identifiable, Equatable, Codable {
    let id: Int
    let name: String
    let description: String
    let coverURL: String
    let playCount: Int
    let trackCount: Int
    let tracks: [Track]
}

struct AlbumDetailModel: Identifiable, Equatable, Codable {
    let id: Int
    let name: String
    let artist: String
    let coverURL: String
    let publishInfo: String
    let tracks: [Track]
}

struct ArtistDetailModel: Identifiable, Equatable, Codable {
    let id: Int
    let name: String
    let alias: String
    let avatarURL: String
    let fansCount: Int
    let topTracks: [Track]
    let featuredAlbums: [AlbumSummary]
}

struct LyricLine: Identifiable, Equatable {
    let time: Double
    let text: String
    let translation: String?

    init(time: Double, text: String, translation: String? = nil) {
        self.time = time
        self.text = text
        self.translation = translation
    }

    var id: String {
        "\(time)-\(text)"
    }
}
