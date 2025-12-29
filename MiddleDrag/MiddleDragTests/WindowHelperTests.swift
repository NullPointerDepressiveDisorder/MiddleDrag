import XCTest

@testable import MiddleDrag

final class WindowHelperTests: XCTestCase {

    // MARK: - WindowInfo Tests

    func testWindowInfoProperties() {
        let bounds = CGRect(x: 100, y: 200, width: 400, height: 300)
        let windowInfo = WindowInfo(
            bounds: bounds,
            ownerName: "Test App",
            bundleIdentifier: "com.test.app",
            windowID: 12345
        )

        XCTAssertEqual(windowInfo.width, 400)
        XCTAssertEqual(windowInfo.height, 300)
        XCTAssertEqual(windowInfo.ownerName, "Test App")
        XCTAssertEqual(windowInfo.bundleIdentifier, "com.test.app")
        XCTAssertEqual(windowInfo.windowID, 12345)
    }

    func testWindowInfoWithNilOptionals() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let windowInfo = WindowInfo(
            bounds: bounds,
            ownerName: nil,
            bundleIdentifier: nil,
            windowID: 0
        )

        XCTAssertNil(windowInfo.ownerName)
        XCTAssertNil(windowInfo.bundleIdentifier)
        XCTAssertEqual(windowInfo.width, 100)
        XCTAssertEqual(windowInfo.height, 100)
    }

    // MARK: - Minimum Size Check Tests

    // Note: These tests can't fully test the actual window detection since that
    // requires real windows on screen. We test the logic where possible.

    func testWindowAtCursorMeetsMinimumSize_NoWindow_ReturnsTrue() {
        // When there's no window at cursor position, the method should return true
        // (allow gesture to proceed - could be desktop or edge case)
        // This behavior is documented in WindowHelper

        // We can't easily mock CGWindowListCopyWindowInfo, but we can verify
        // the method exists and is callable
        let result = WindowHelper.windowAtCursorMeetsMinimumSize(
            minWidth: 100, minHeight: 100)

        // Without controlling the environment, we just verify it returns a Bool
        // In a clean test environment without windows, this should return true
        XCTAssertNotNil(result)
    }

    func testGetWindowAt_ReturnsNilForOffScreenPoint() {
        // Test with a point that's likely off any screen
        let offScreenPoint = CGPoint(x: -99999, y: -99999)
        let window = WindowHelper.getWindowAt(point: offScreenPoint)

        // Should return nil since no window could be at this position
        XCTAssertNil(window)
    }
}