import Foundation

/// File-backed cache for playlist / album / artist detail screens (offline-friendly, survives cold start).
enum MusicDetailCacheStore {
    private static let folderName = "detail-cache-v1"

    private static var cacheDirectory: URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Oto: application-support directory unavailable — MusicDetailCacheStore")
        }
        return base.appendingPathComponent("Oto", isDirectory: true).appendingPathComponent(folderName, isDirectory: true)
    }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private static func fileURL(kind: String, id: Int) -> URL {
        cacheDirectory.appendingPathComponent("\(kind)-\(id).json")
    }

    // MARK: - Playlist

    static func loadPlaylist(id: Int) -> PlaylistDetailModel? {
        load(PlaylistDetailModel.self, from: fileURL(kind: "playlist", id: id))
    }

    static func savePlaylist(_ detail: PlaylistDetailModel) {
        save(detail, to: fileURL(kind: "playlist", id: detail.id))
    }

    // MARK: - Album

    static func loadAlbum(id: Int) -> AlbumDetailModel? {
        load(AlbumDetailModel.self, from: fileURL(kind: "album", id: id))
    }

    static func saveAlbum(_ detail: AlbumDetailModel) {
        save(detail, to: fileURL(kind: "album", id: detail.id))
    }

    // MARK: - Artist

    static func loadArtist(id: Int) -> ArtistDetailModel? {
        load(ArtistDetailModel.self, from: fileURL(kind: "artist", id: id))
    }

    static func saveArtist(_ detail: ArtistDetailModel) {
        save(detail, to: fileURL(kind: "artist", id: detail.id))
    }

    // MARK: - Session

    static func clearAll() {
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try? FileManager.default.removeItem(at: cacheDirectory)
        }
    }

    // MARK: - Private

    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        return value
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        ensureDirectory()
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
