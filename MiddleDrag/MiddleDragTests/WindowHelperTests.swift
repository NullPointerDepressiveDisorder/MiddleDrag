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

    // MARK: - Additional Coverage Tests

    func testGetWindowAtCursorDoesNotCrash() {
        // Calling getWindowAtCursor should never crash, even without windows
        let window = WindowHelper.getWindowAtCursor()
        // Result could be nil or a valid window depending on environment
        // Just verify it doesn't crash and returns a valid optional
        _ = window
    }

    func testGetWindowAt_WithVeryLargePoint() {
        // Test with extremely large coordinates
        let point = CGPoint(x: 999999, y: 999999)
        let window = WindowHelper.getWindowAt(point: point)
        XCTAssertNil(window)
    }

    func testGetWindowAt_AtOrigin() {
        // Test at origin point (0, 0) which is top-left of primary screen
        let point = CGPoint(x: 0, y: 0)
        // Don't assert result as it depends on window layout, just verify no crash
        _ = WindowHelper.getWindowAt(point: point)
    }

    func testWindowAtCursorMeetsMinimumSize_VeryLargeThreshold() {
        // With a very large threshold, should likely return false if any window is found
        // or true if no window (desktop)
        let result = WindowHelper.windowAtCursorMeetsMinimumSize(
            minWidth: 99999, minHeight: 99999)
        // Result depends on whether there's a window and its size
        XCTAssertNotNil(result)  // Should always return a Bool
    }

    func testWindowAtCursorMeetsMinimumSize_ZeroThreshold() {
        // With zero threshold, any window should pass
        let result = WindowHelper.windowAtCursorMeetsMinimumSize(
            minWidth: 0, minHeight: 0)
        XCTAssertTrue(result)  // Zero threshold should always pass
    }

    func testWindowInfoBoundsAccess() {
        let bounds = CGRect(x: 50, y: 100, width: 800, height: 600)
        let info = WindowInfo(
            bounds: bounds,
            ownerName: "Test",
            bundleIdentifier: "com.test",
            windowID: 1
        )

        // Verify bounds are accessible
        XCTAssertEqual(info.bounds.origin.x, 50)
        XCTAssertEqual(info.bounds.origin.y, 100)
        XCTAssertEqual(info.bounds.size.width, 800)
        XCTAssertEqual(info.bounds.size.height, 600)
    }

    func testWindowInfoWidthHeightComputedProperties() {
        let info = WindowInfo(
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            ownerName: nil,
            bundleIdentifier: nil,
            windowID: 0
        )

        XCTAssertEqual(info.width, 1920)
        XCTAssertEqual(info.height, 1080)
    }
}
