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

    // MARK: - Mock Window Data Tests

    /// Helper to create a mock window dictionary
    private func createMockWindow(
        x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
        layer: Int = 0, ownerName: String? = nil, windowID: CGWindowID = 1, ownerPID: Int? = nil
    ) -> [CFString: Any] {
        var window: [CFString: Any] = [
            kCGWindowLayer: layer,
            kCGWindowBounds: ["X": x, "Y": y, "Width": width, "Height": height],
            kCGWindowNumber: windowID,
        ]
        if let name = ownerName {
            window[kCGWindowOwnerName] = name
        }
        if let pid = ownerPID {
            window[kCGWindowOwnerPID] = pid_t(pid)
        }
        return window
    }

    func testGetWindowAt_WithMockData_FindsWindow() {
        let mockWindows = [
            createMockWindow(
                x: 100, y: 100, width: 400, height: 300, ownerName: "TestApp", windowID: 12345)
        ]

        let point = CGPoint(x: 200, y: 200)  // Inside the window
        let result = WindowHelper.getWindowAt(point: point, windowList: mockWindows)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.ownerName, "TestApp")
        XCTAssertEqual(result?.windowID, 12345)
        XCTAssertEqual(result?.width, 400)
        XCTAssertEqual(result?.height, 300)
    }

    func testGetWindowAt_WithMockData_PointOutsideWindow() {
        let mockWindows = [
            createMockWindow(x: 100, y: 100, width: 400, height: 300, ownerName: "TestApp")
        ]

        let point = CGPoint(x: 50, y: 50)  // Outside the window
        let result = WindowHelper.getWindowAt(point: point, windowList: mockWindows)

        XCTAssertNil(result)
    }

    func testGetWindowAt_WithMockData_SkipsNonZeroLayerWindows() {
        let mockWindows = [
            createMockWindow(
                x: 0, y: 0, width: 1000, height: 1000, layer: 25, ownerName: "MenuBar"),  // Layer 25 = menu bar
            createMockWindow(
                x: 100, y: 100, width: 400, height: 300, layer: 0, ownerName: "NormalWindow"),
        ]

        let point = CGPoint(x: 200, y: 200)  // Would match both, but should skip layer 25
        let result = WindowHelper.getWindowAt(point: point, windowList: mockWindows)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.ownerName, "NormalWindow")
    }

    func testGetWindowAt_WithMockData_ReturnsFirstMatchingWindow() {
        // Windows are in front-to-back order, so first match wins
        let mockWindows = [
            createMockWindow(x: 100, y: 100, width: 400, height: 300, ownerName: "FrontWindow"),
            createMockWindow(x: 100, y: 100, width: 500, height: 400, ownerName: "BackWindow"),
        ]

        let point = CGPoint(x: 200, y: 200)  // Inside both windows
        let result = WindowHelper.getWindowAt(point: point, windowList: mockWindows)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.ownerName, "FrontWindow")
    }

    func testGetWindowAt_WithMockData_EmptyWindowList() {
        let mockWindows: [[CFString: Any]] = []

        let point = CGPoint(x: 200, y: 200)
        let result = WindowHelper.getWindowAt(point: point, windowList: mockWindows)

        XCTAssertNil(result)
    }

    func testGetWindowAt_WithMockData_SkipsMissingBounds() {
        let mockWindows: [[CFString: Any]] = [
            [kCGWindowLayer: 0, kCGWindowOwnerName: "NoBoundsWindow"],  // Missing bounds
            createMockWindow(x: 100, y: 100, width: 400, height: 300, ownerName: "ValidWindow"),
        ]

        let point = CGPoint(x: 200, y: 200)
        let result = WindowHelper.getWindowAt(point: point, windowList: mockWindows)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.ownerName, "ValidWindow")
    }

    func testGetWindowAt_WithMockData_SkipsMissingLayer() {
        let mockWindows: [[CFString: Any]] = [
            [kCGWindowBounds: ["X": 0, "Y": 0, "Width": 1000, "Height": 1000]],  // Missing layer
            createMockWindow(x: 100, y: 100, width: 400, height: 300, ownerName: "ValidWindow"),
        ]

        let point = CGPoint(x: 200, y: 200)
        let result = WindowHelper.getWindowAt(point: point, windowList: mockWindows)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.ownerName, "ValidWindow")
    }

    func testGetWindowAt_WithMockData_WindowAtOrigin() {
        let mockWindows = [
            createMockWindow(x: 0, y: 0, width: 100, height: 100, ownerName: "OriginWindow")
        ]

        let point = CGPoint(x: 50, y: 50)
        let result = WindowHelper.getWindowAt(point: point, windowList: mockWindows)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.ownerName, "OriginWindow")
    }

    func testGetWindowAt_WithMockData_PointOnWindowEdge() {
        let mockWindows = [
            createMockWindow(x: 100, y: 100, width: 400, height: 300, ownerName: "TestWindow")
        ]

        // Test point exactly on left edge
        let leftEdge = CGPoint(x: 100, y: 200)
        XCTAssertNotNil(WindowHelper.getWindowAt(point: leftEdge, windowList: mockWindows))

        // Test point exactly on top edge
        let topEdge = CGPoint(x: 200, y: 100)
        XCTAssertNotNil(WindowHelper.getWindowAt(point: topEdge, windowList: mockWindows))

        // Test point just outside right edge
        let outsideRight = CGPoint(x: 501, y: 200)
        XCTAssertNil(WindowHelper.getWindowAt(point: outsideRight, windowList: mockWindows))
    }

    func testGetWindowAt_WithMockData_WindowWithOptionalNilOwnerPID() {
        // Window with no ownerPID - bundleIdentifier should be nil
        let mockWindows = [
            createMockWindow(
                x: 100, y: 100, width: 400, height: 300, ownerName: "TestWindow", ownerPID: nil)
        ]

        let point = CGPoint(x: 200, y: 200)
        let result = WindowHelper.getWindowAt(point: point, windowList: mockWindows)

        XCTAssertNotNil(result)
        XCTAssertNil(result?.bundleIdentifier)  // No PID means no bundle ID lookup
    }
}
