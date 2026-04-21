import Foundation
import XCTest
@testable import Oto

final class DownloadServicePersistenceTests: XCTestCase {
    private struct LegacyDownloadRecord: Encodable {
        let track: Track
        let downloadedAt: Date
        let localFilePath: String
    }

    private struct CurrentDownloadRecord: Encodable {
        let track: Track
        let downloadedAt: Date
        let relativePath: String
    }

    private struct PersistedCatalogRecord: Decodable {
        let relativePath: String
    }

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var rootDirectory: URL!
    private var documentsDirectory: URL!
    private var applicationSupportDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "DownloadServicePersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let appSupport = root.appendingPathComponent("ApplicationSupport", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        rootDirectory = root
        documentsDirectory = documents
        applicationSupportDirectory = appSupport
    }

    override func tearDownWithError() throws {
        if let defaults {
            defaults.removePersistentDomain(forName: suiteName)
        }
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        defaults = nil
        suiteName = nil
        rootDirectory = nil
        documentsDirectory = nil
        applicationSupportDirectory = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testRestoreMigratesLegacyAppSupportDownloadIntoDocuments() throws {
        let track = sampleTrack()
        let legacyDirectory = applicationSupportDirectory.appendingPathComponent("OtoDownloads", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let legacyFile = legacyDirectory.appendingPathComponent("\(track.id).mp3")
        try Data("legacy-audio".utf8).write(to: legacyFile)

        let payload = [LegacyDownloadRecord(track: track, downloadedAt: Date(timeIntervalSince1970: 1), localFilePath: legacyFile.path)]
        defaults.set(try JSONEncoder().encode(payload), forKey: "storymusic.downloads.catalog")

        let service = DownloadService(
            userDefaults: defaults,
            fileManager: .default,
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: applicationSupportDirectory
        )

        XCTAssertEqual(service.downloadedTracks, [track])

        let expectedRelativePath = "OtoDownloads/Artist Name - Track Title [42].mp3"
        let migratedFile = documentsDirectory.appendingPathComponent(expectedRelativePath)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: migratedFile.path),
            "Migrated file missing at \(migratedFile.path)"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyFile.path),
            "Legacy file still exists at \(legacyFile.path)"
        )

        let persistedData = try XCTUnwrap(defaults.data(forKey: "storymusic.downloads.catalog"))
        let persistedCatalog = try JSONDecoder().decode([PersistedCatalogRecord].self, from: persistedData)
        XCTAssertTrue(
            persistedCatalog.contains(where: { $0.relativePath == expectedRelativePath }),
            "Persisted catalog did not contain migrated path: \(persistedCatalog.map { $0.relativePath })"
        )
        XCTAssertFalse(
            String(decoding: persistedData, as: UTF8.self).contains("localFilePath"),
            "Persisted JSON still contains legacy key: \(String(decoding: persistedData, as: UTF8.self))"
        )
    }

    @MainActor
    func testRemoveDownloadDeletesFileAndClearsCatalogEntry() throws {
        let track = sampleTrack()
        let relativePath = "OtoDownloads/Artist Name - Track Title [42].mp3"
        let downloadDirectory = documentsDirectory.appendingPathComponent("OtoDownloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        let fileURL = documentsDirectory.appendingPathComponent(relativePath)
        try Data("downloaded-audio".utf8).write(to: fileURL)

        let payload = [CurrentDownloadRecord(track: track, downloadedAt: Date(timeIntervalSince1970: 2), relativePath: relativePath)]
        defaults.set(try JSONEncoder().encode(payload), forKey: "storymusic.downloads.catalog")

        let service = DownloadService(
            userDefaults: defaults,
            fileManager: .default,
            documentsDirectory: documentsDirectory,
            applicationSupportDirectory: applicationSupportDirectory
        )
        XCTAssertEqual(service.downloadedTracks, [track])

        service.removeDownload(for: track.id)

        XCTAssertEqual(service.downloadedTracks, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        let persistedData = try XCTUnwrap(defaults.data(forKey: "storymusic.downloads.catalog"))
        let persistedJSONArray = try XCTUnwrap(try JSONSerialization.jsonObject(with: persistedData) as? [[String: Any]])
        XCTAssertTrue(persistedJSONArray.isEmpty)
    }

    private func sampleTrack() -> Track {
        Track(
            id: 42,
            title: "Track Title",
            artist: "Artist Name",
            album: "Album Name",
            albumID: 7,
            coverURL: "https://example.com/cover.jpg",
            audioURL: "https://example.com/audio.mp3"
        )
    }
}
