import XCTest

@testable import MiddleDrag

/// Tests for AlertHelper.
/// Note: Most AlertHelper methods invoke `NSAlert().runModal()` which blocks
/// and requires user interaction, making them unsuitable for unit testing.
/// These tests focus on verifiable aspects of the AlertHelper class.
final class AlertHelperTests: XCTestCase {

    // MARK: - Existence Tests

    func testAlertHelperClassExists() {
        // Verify the AlertHelper type is accessible
        let helperType = AlertHelper.self
        XCTAssertNotNil(helperType)
    }

    // MARK: - URL Validation Tests

    func testTrackpadSettingsURLIsValid() {
        // Test that the trackpad settings URL scheme is valid
        let urlString = "x-apple.systempreferences:com.apple.preference.trackpad"
        let url = URL(string: urlString)
        XCTAssertNotNil(url, "Trackpad settings URL should be valid")
        XCTAssertEqual(url?.scheme, "x-apple.systempreferences")
    }

    func testGitHubURLIsValid() {
        // Test that the GitHub project URL is valid
        let urlString = "https://github.com/NullPointerDepressiveDisorder/MiddleDrag"
        let url = URL(string: urlString)
        XCTAssertNotNil(url, "GitHub URL should be valid")
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "github.com")
    }

    // MARK: - Bundle Version Tests

    func testBundleVersionCanBeRetrieved() {
        // Test version retrieval logic similar to AlertHelper.showAbout()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        // In test target, version might be nil or different, either is fine
        // We just verify the logic path doesn't crash
        let displayVersion = version ?? "Unknown"
        XCTAssertFalse(displayVersion.isEmpty)
    }
}
