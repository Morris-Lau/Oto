import XCTest
@testable import Oto

final class SessionPersistenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SessionPersistenceTests.\(UUID().uuidString)"
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

    func testSaveLoadAndClearCookieString() {
        XCTAssertNil(SessionPersistence.loadCookieString(from: defaults))

        SessionPersistence.saveCookieString("MUSIC_U=abc123", to: defaults)
        XCTAssertEqual(SessionPersistence.loadCookieString(from: defaults), "MUSIC_U=abc123")

        SessionPersistence.clearCookieString(from: defaults)
        XCTAssertNil(SessionPersistence.loadCookieString(from: defaults))
    }
}
