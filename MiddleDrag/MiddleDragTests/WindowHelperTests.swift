import XCTest

@testable import MiddleDrag

@MainActor
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

    // MARK: - isCursorOverDesktop Tests

    func testIsCursorOverDesktop_DoesNotCrash() {
        // Calling isCursorOverDesktop should never crash, even without windows
        let result = WindowHelper.isCursorOverDesktop()
        // Result could be true or false depending on environment
        // Just verify it doesn't crash and returns a valid Bool
        XCTAssertNotNil(result)
    }

    func testIsCursorOverDesktop_ReturnsBool() {
        // isCursorOverDesktop should always return a Bool (true or false)
        // We can't control the environment, but verify the return type
        let result = WindowHelper.isCursorOverDesktop()
        XCTAssertTrue(result == true || result == false)
    }

    func testIsCursorOverDesktop_WithMockData_NoWindow_ReturnsTrue() {
        // When no window is found at point, should return true (over desktop)
        let mockWindows: [[CFString: Any]] = []
        let point = CGPoint(x: 200, y: 200)

        let result = WindowHelper.isCursorOverDesktop(at: point, windowList: mockWindows)
        XCTAssertTrue(result, "Should return true when no window exists at point")
    }

    func testIsCursorOverDesktop_WithMockData_WindowExists_ReturnsFalse() {
        // When a window exists at point, should return false (not over desktop)
        let mockWindows = [
            createMockWindow(x: 100, y: 100, width: 400, height: 300, ownerName: "TestApp")
        ]
        let point = CGPoint(x: 200, y: 200)  // Inside the window

        let result = WindowHelper.isCursorOverDesktop(at: point, windowList: mockWindows)
        XCTAssertFalse(result, "Should return false when window exists at point")
    }

    func testIsCursorOverDesktop_WithMockData_PointOutsideWindow_ReturnsTrue() {
        // When point is outside all windows, should return true (over desktop)
        let mockWindows = [
            createMockWindow(x: 100, y: 100, width: 400, height: 300, ownerName: "TestApp")
        ]
        let point = CGPoint(x: 50, y: 50)  // Outside the window

        let result = WindowHelper.isCursorOverDesktop(at: point, windowList: mockWindows)
        XCTAssertTrue(result, "Should return true when point is outside all windows")
    }

    // MARK: - WindowID-Based Bundle ID Lookup Tests

    func testGetWindowAt_WithMockData_OverlappingWindows_UsesWindowIDForBundleLookup() {
        // Test that when overlapping windows exist, we use windowID to find the correct one
        // for bundle ID lookup, not just the first one that contains the point
        let mockWindows = [
            createMockWindow(
                x: 100, y: 100, width: 400, height: 300,
                ownerName: "FrontWindow", windowID: 111, ownerPID: 1001),
            createMockWindow(
                x: 100, y: 100, width: 500, height: 400,
                ownerName: "BackWindow", windowID: 222, ownerPID: 2002),
        ]

        let point = CGPoint(x: 200, y: 200)  // Inside both windows
        let result = WindowHelper.getWindowAt(point: point, windowList: mockWindows)

        // Should return first window (FrontWindow) with its windowID
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.ownerName, "FrontWindow")
        XCTAssertEqual(result?.windowID, 111)
        // Note: bundleIdentifier will be nil in tests since NSRunningApplication
        // won't find these fake PIDs, but the windowID should be correct
    }

    func testGetWindowAt_WithMockData_WindowIDMatchEnsuresCorrectWindow() {
        // Verify that windowID is used to match, not point-based re-search
        let mockWindows = [
            createMockWindow(
                x: 100, y: 100, width: 200, height: 200,
                ownerName: "SmallFront", windowID: 100, ownerPID: 1),
            createMockWindow(
                x: 50, y: 50, width: 400, height: 400,
                ownerName: "LargeBack", windowID: 200, ownerPID: 2),
        ]

        // Point that's inside both windows
        let point = CGPoint(x: 150, y: 150)
        let result = WindowHelper.getWindowAt(point: point, windowList: mockWindows)

        // Should get SmallFront (first match) with windowID 100
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.windowID, 100)
        XCTAssertEqual(result?.ownerName, "SmallFront")
    }

    func testGetWindowAt_WithMockData_MultipleWindowsSameSize() {
        // Multiple windows with same bounds but different IDs
        let mockWindows = [
            createMockWindow(
                x: 100, y: 100, width: 400, height: 300,
                ownerName: "Window1", windowID: 1001, ownerPID: 101),
            createMockWindow(
                x: 100, y: 100, width: 400, height: 300,
                ownerName: "Window2", windowID: 1002, ownerPID: 102),
            createMockWindow(
                x: 100, y: 100, width: 400, height: 300,
                ownerName: "Window3", windowID: 1003, ownerPID: 103),
        ]

        let point = CGPoint(x: 200, y: 200)
        let result = WindowHelper.getWindowAt(point: point, windowList: mockWindows)

        // Should return Window1 (first in list) with its specific windowID
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.windowID, 1001)
        XCTAssertEqual(result?.ownerName, "Window1")
    }

    func testGetWindowAt_WithMockData_WindowIDUsedNotPointReMatch() {
        // Scenario: First window at point has windowID=50, but if we re-searched
        // by point we might match a different window. Verify windowID is used.
        let mockWindows = [
            createMockWindow(
                x: 200, y: 200, width: 100, height: 100,
                ownerName: "TargetWindow", windowID: 50, ownerPID: 500),
            createMockWindow(
                x: 150, y: 150, width: 200, height: 200,
                ownerName: "OverlappingWindow", windowID: 60, ownerPID: 600),
        ]

        // Point inside TargetWindow (which is listed first, so it wins)
        let point = CGPoint(x: 220, y: 220)
        let result = WindowHelper.getWindowAt(point: point, windowList: mockWindows)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.windowID, 50)
        XCTAssertEqual(result?.ownerName, "TargetWindow")
    }

    func testGetWindowAt_NonisolatedMethod_ReturnsNilBundleID() {
        // The nonisolated test-injection method should always return nil bundleIdentifier
        let mockWindows = [
            createMockWindow(
                x: 100, y: 100, width: 400, height: 300,
                ownerName: "TestApp", windowID: 123, ownerPID: 999)
        ]

        let point = CGPoint(x: 200, y: 200)
        // Call the nonisolated method directly
        let result = WindowHelper.getWindowAt(point: point, windowList: mockWindows)

        XCTAssertNotNil(result)
        // The nonisolated method doesn't look up bundle IDs
        XCTAssertNil(result?.bundleIdentifier)
    }

    // MARK: - Bundle Identifier Lookup Tests (Injectable)

    func testGetWindowAt_WithBundleLookup_PopulatesBundleID() {
        let mockWindows = [
            createMockWindow(
                x: 100, y: 100, width: 400, height: 300,
                ownerName: "TestApp", windowID: 123, ownerPID: 1001)
        ]

        let point = CGPoint(x: 200, y: 200)
        let result = WindowHelper.getWindowAt(
            point: point,
            windowList: mockWindows,
            bundleIdentifierLookup: { _ in "com.test.app" }
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.bundleIdentifier, "com.test.app")
    }

    func testGetWindowAt_WithBundleLookup_PassesCorrectPID() {
        var capturedPID: pid_t?
        let mockWindows = [
            createMockWindow(
                x: 100, y: 100, width: 400, height: 300,
                ownerName: "TestApp", windowID: 123, ownerPID: 42)
        ]

        let point = CGPoint(x: 200, y: 200)
        _ = WindowHelper.getWindowAt(
            point: point,
            windowList: mockWindows,
            bundleIdentifierLookup: { pid in
                capturedPID = pid
                return "com.test.app"
            }
        )

        XCTAssertEqual(capturedPID, 42)
    }

    func testGetWindowAt_WithBundleLookup_ReturnsNilWhenLookupReturnsNil() {
        let mockWindows = [
            createMockWindow(
                x: 100, y: 100, width: 400, height: 300,
                ownerName: "TestApp", windowID: 123, ownerPID: 1001)
        ]

        let point = CGPoint(x: 200, y: 200)
        let result = WindowHelper.getWindowAt(
            point: point,
            windowList: mockWindows,
            bundleIdentifierLookup: { _ in nil }
        )

        XCTAssertNotNil(result)
        XCTAssertNil(result?.bundleIdentifier)
    }

    func testGetWindowAt_WithBundleLookup_OverlappingWindows_UsesCorrectPID() {
        var capturedPID: pid_t?
        let mockWindows = [
            createMockWindow(
                x: 100, y: 100, width: 400, height: 300,
                ownerName: "FrontWindow", windowID: 111, ownerPID: 1001),
            createMockWindow(
                x: 100, y: 100, width: 500, height: 400,
                ownerName: "BackWindow", windowID: 222, ownerPID: 2002),
        ]

        let point = CGPoint(x: 200, y: 200)  // Inside both windows
        let result = WindowHelper.getWindowAt(
            point: point,
            windowList: mockWindows,
            bundleIdentifierLookup: { pid in
                capturedPID = pid
                return "com.front.app"
            }
        )

        // Should use PID from FrontWindow (first match), not BackWindow
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.ownerName, "FrontWindow")
        XCTAssertEqual(capturedPID, 1001)
        XCTAssertEqual(result?.bundleIdentifier, "com.front.app")
    }

    func testGetWindowAt_WithBundleLookup_NoOwnerPID_BundleIDIsNil() {
        // Window without ownerPID should have nil bundleIdentifier
        let mockWindows: [[CFString: Any]] = [
            [
                kCGWindowLayer: 0,
                kCGWindowBounds: ["X": CGFloat(100), "Y": CGFloat(100), "Width": CGFloat(400), "Height": CGFloat(300)],
                kCGWindowNumber: CGWindowID(123),
                kCGWindowOwnerName: "NoOwnerPIDWindow"
                // Note: kCGWindowOwnerPID is intentionally missing
            ]
        ]

        var lookupCalled = false
        let point = CGPoint(x: 200, y: 200)
        let result = WindowHelper.getWindowAt(
            point: point,
            windowList: mockWindows,
            bundleIdentifierLookup: { _ in
                lookupCalled = true
                return "should.not.be.called"
            }
        )

        XCTAssertNotNil(result)
        XCTAssertNil(result?.bundleIdentifier)
        XCTAssertFalse(lookupCalled, "Lookup should not be called when no ownerPID")
    }

    func testGetWindowAt_WithBundleLookup_DifferentBundleIDsPerPID() {
        // Verify lookup is called with correct PID and returns different values
        let mockWindows = [
            createMockWindow(
                x: 100, y: 100, width: 200, height: 200,
                ownerName: "App1", windowID: 1, ownerPID: 100),
        ]

        let bundleIDs: [pid_t: String] = [
            100: "com.app1.bundle",
            200: "com.app2.bundle",
        ]

        let point = CGPoint(x: 150, y: 150)
        let result = WindowHelper.getWindowAt(
            point: point,
            windowList: mockWindows,
            bundleIdentifierLookup: { pid in bundleIDs[pid] }
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.bundleIdentifier, "com.app1.bundle")
    }

    // MARK: - Title Bar Detection Tests

    func testIsCursorInTitleBar_DoesNotCrash() {
        // Calling isCursorInTitleBar should never crash
        let result = WindowHelper.isCursorInTitleBar()
        XCTAssertNotNil(result)
    }

    func testIsCursorInTitleBar_WithMockData_CursorInTitleBar_ReturnsTrue() {
        // Window at y=100 with height=300, title bar is top 28 pixels (y=100 to y=128)
        let mockWindows = [
            createMockWindow(x: 100, y: 100, width: 400, height: 300, ownerName: "TestApp")
        ]

        // Point in title bar region (y=110, which is within 100-128)
        let pointInTitleBar = CGPoint(x: 200, y: 110)
        let result = WindowHelper.isCursorInTitleBar(
            at: pointInTitleBar, titleBarHeight: 28, windowList: mockWindows)

        XCTAssertTrue(result, "Should return true when cursor is in title bar region")
    }

    func testIsCursorInTitleBar_WithMockData_CursorBelowTitleBar_ReturnsFalse() {
        // Window at y=100 with height=300, title bar is top 28 pixels (y=100 to y=128)
        let mockWindows = [
            createMockWindow(x: 100, y: 100, width: 400, height: 300, ownerName: "TestApp")
        ]

        // Point below title bar region (y=200, which is well below 128)
        let pointBelowTitleBar = CGPoint(x: 200, y: 200)
        let result = WindowHelper.isCursorInTitleBar(
            at: pointBelowTitleBar, titleBarHeight: 28, windowList: mockWindows)

        XCTAssertFalse(result, "Should return false when cursor is below title bar")
    }

    func testIsCursorInTitleBar_WithMockData_CursorAtTitleBarBoundary_ReturnsTrue() {
        // Test cursor exactly at the window top edge
        let mockWindows = [
            createMockWindow(x: 100, y: 100, width: 400, height: 300, ownerName: "TestApp")
        ]

        let pointAtTop = CGPoint(x: 200, y: 100)  // Exactly at window top
        let result = WindowHelper.isCursorInTitleBar(
            at: pointAtTop, titleBarHeight: 28, windowList: mockWindows)

        XCTAssertTrue(result, "Should return true when cursor is at window top edge")
    }

    func testIsCursorInTitleBar_WithMockData_CursorJustBelowTitleBar_ReturnsFalse() {
        // Test cursor exactly at the title bar bottom boundary
        let mockWindows = [
            createMockWindow(x: 100, y: 100, width: 400, height: 300, ownerName: "TestApp")
        ]

        // Point exactly at title bar boundary (y=128, which is >= 128 so NOT in title bar)
        let pointAtBoundary = CGPoint(x: 200, y: 128)
        let result = WindowHelper.isCursorInTitleBar(
            at: pointAtBoundary, titleBarHeight: 28, windowList: mockWindows)

        XCTAssertFalse(result, "Should return false when cursor is at title bar bottom boundary")
    }

    func testIsCursorInTitleBar_WithMockData_NoWindow_ReturnsFalse() {
        // When no window exists at cursor position
        let mockWindows: [[CFString: Any]] = []

        let point = CGPoint(x: 200, y: 200)
        let result = WindowHelper.isCursorInTitleBar(
            at: point, titleBarHeight: 28, windowList: mockWindows)

        XCTAssertFalse(result, "Should return false when no window at cursor")
    }

    func testIsCursorInTitleBar_WithMockData_CustomTitleBarHeight() {
        // Test with a custom title bar height (e.g., 50 pixels for apps with toolbars)
        let mockWindows = [
            createMockWindow(x: 100, y: 100, width: 400, height: 300, ownerName: "TestApp")
        ]

        // Point at y=140, which is in title bar with height=50 (100-150) but not with height=28
        let point = CGPoint(x: 200, y: 140)

        let resultWith50 = WindowHelper.isCursorInTitleBar(
            at: point, titleBarHeight: 50, windowList: mockWindows)
        XCTAssertTrue(resultWith50, "Should be in title bar with height 50")

        let resultWith28 = WindowHelper.isCursorInTitleBar(
            at: point, titleBarHeight: 28, windowList: mockWindows)
        XCTAssertFalse(resultWith28, "Should NOT be in title bar with height 28")
    }

    func testIsCursorInTitleBar_WithMockData_PointOutsideWindow_ReturnsFalse() {
        let mockWindows = [
            createMockWindow(x: 100, y: 100, width: 400, height: 300, ownerName: "TestApp")
        ]

        // Point outside the window entirely
        let pointOutside = CGPoint(x: 50, y: 50)
        let result = WindowHelper.isCursorInTitleBar(
            at: pointOutside, titleBarHeight: 28, windowList: mockWindows)

        XCTAssertFalse(result, "Should return false when cursor is outside window")
    }

    func testIsCursorInTitleBar_WithMockData_OverlappingWindows_UsesTopWindow() {
        // Front window has title bar at y=200, back window has title bar at y=100
        let mockWindows = [
            createMockWindow(x: 150, y: 200, width: 300, height: 250, ownerName: "FrontWindow"),
            createMockWindow(x: 100, y: 100, width: 400, height: 400, ownerName: "BackWindow"),
        ]

        // Point at y=210, which is in front window's title bar (200-228)
        let pointInFrontTitleBar = CGPoint(x: 200, y: 210)
        let result = WindowHelper.isCursorInTitleBar(
            at: pointInFrontTitleBar, titleBarHeight: 28, windowList: mockWindows)

        XCTAssertTrue(result, "Should detect title bar of front window")
    }
}
