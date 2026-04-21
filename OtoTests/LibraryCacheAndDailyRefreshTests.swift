import Foundation
import XCTest
@testable import Oto

final class LibraryCacheAndDailyRefreshTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LibraryCacheAndDailyRefreshTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let defaults {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCalendarDayKeyFormatsLikeDailyRecommendationsLegacy() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9))!
        XCTAssertEqual(CalendarDayKey.string(for: date, calendar: calendar), "2026-03-09")
    }

    func testLibraryCacheStoreRoundTrip() {
        XCTAssertNil(LibraryCacheStore.load(from: defaults))

        let profile = UserProfileSummary(id: 42, nickname: "n", signature: "s", avatarURL: "a")
        let pl = UserPlaylistSummary(id: 1, name: "p", trackCount: 3, playCount: 0, coverURL: "c", creatorName: "x")
        let album = AlbumSummary(id: 9, name: "al", artist: "ar", coverURL: "u", trackCount: 10)
        let track = Track(
            id: 100,
            title: "t",
            artist: "a",
            album: "b",
            albumID: nil,
            coverURL: "cu",
            audioURL: "au"
        )

        LibraryCacheStore.save(
            profile: profile,
            playlists: [pl],
            collectedPlaylists: [],
            collectedAlbums: [album],
            likedSongs: [track],
            to: defaults
        )

        let loaded = LibraryCacheStore.load(from: defaults)!
        XCTAssertEqual(loaded.userId, 42)
        XCTAssertEqual(loaded.profile.toModel(), profile)
        XCTAssertEqual(loaded.playlists.map { $0.toModel() }, [pl])
        XCTAssertTrue(loaded.collectedPlaylists.isEmpty)
        XCTAssertEqual(loaded.collectedAlbums, [album])
        XCTAssertEqual(loaded.likedSongs, [track])

        LibraryCacheStore.clear(from: defaults)
        XCTAssertNil(LibraryCacheStore.load(from: defaults))
    }

    func testDiscoverDailyRefreshCoordinatorMarksDayInDefaults() {
        let key = DiscoverDailyRefreshCoordinator.lastRefreshDayStorageKey
        XCTAssertNil(defaults.string(forKey: key))

        DiscoverDailyRefreshCoordinator.markRefreshCompletedForToday(defaults: defaults)
        let marked = defaults.string(forKey: key)
        XCTAssertEqual(marked, CalendarDayKey.string())

        DiscoverDailyRefreshCoordinator.resetForegroundRefreshSchedule(defaults: defaults)
        XCTAssertNil(defaults.string(forKey: key))
    }
}
