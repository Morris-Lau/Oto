import XCTest
@testable import Oto

final class RemoteURLNormalizerTests: XCTestCase {
    func testSanitizeTrimsWhitespace() {
        XCTAssertEqual(
            RemoteURLNormalizer.sanitize("  https://example.com/image.jpg  "),
            "https://example.com/image.jpg"
        )
    }

    func testSanitizePromotesHttpToHttps() {
        XCTAssertEqual(
            RemoteURLNormalizer.sanitize("http://example.com/image.jpg"),
            "https://example.com/image.jpg"
        )
    }

    func testSanitizePromotesProtocolRelativeURL() {
        XCTAssertEqual(
            RemoteURLNormalizer.sanitize("//example.com/image.jpg"),
            "https://example.com/image.jpg"
        )
    }

    func testURLReturnsNilForBlankInput() {
        XCTAssertNil(RemoteURLNormalizer.url(from: "   "))
    }

    func testURLCanonicalizesProtocolRelativeURL() {
        XCTAssertEqual(
            RemoteURLNormalizer.url(from: "//example.com/image.jpg")?.absoluteString,
            "https://example.com/image.jpg"
        )
    }

    func testURLCanonicalizesHttpURL() {
        XCTAssertEqual(
            RemoteURLNormalizer.url(from: "http://example.com/image.jpg")?.absoluteString,
            "https://example.com/image.jpg"
        )
    }
}
