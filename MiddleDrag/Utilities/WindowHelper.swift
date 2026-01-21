import AppKit
import CoreGraphics
import Foundation

/// Information about a window at a specific screen location
struct WindowInfo: Sendable {
    let bounds: CGRect
    let ownerName: String?
    let bundleIdentifier: String?
    let windowID: CGWindowID

    var width: CGFloat { bounds.width }
    var height: CGFloat { bounds.height }
}

/// Utility for detecting window information under the cursor
/// All methods use AppKit APIs (NSEvent, NSScreen, NSRunningApplication) that require main thread
@MainActor
class WindowHelper {

    /// Get the window under the current cursor position
    /// - Returns: WindowInfo for the topmost window at cursor, or nil if none found
    static func getWindowAtCursor() -> WindowInfo? {
        let mouseLocation = NSEvent.mouseLocation

        // Convert from Cocoa coordinates (origin bottom-left) to Quartz (origin top-left)
        guard let screenHeight = NSScreen.main?.frame.height else { return nil }
        let quartzY = screenHeight - mouseLocation.y
        let cursorPoint = CGPoint(x: mouseLocation.x, y: quartzY)

        return getWindowAt(point: cursorPoint)
    }

    /// Get the window at a specific screen point (in Quartz coordinates)
    /// - Parameter point: Screen point in Quartz coordinates (origin top-left)
    /// - Returns: WindowInfo for the topmost window at point, or nil if none found
    static func getWindowAt(point: CGPoint) -> WindowInfo? {
        // Get list of all on-screen windows excluding desktop elements
        let options: CGWindowListOption = [.excludeDesktopElements, .optionOnScreenOnly]

        guard
            let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[CFString: Any]]
        else {
            return nil
        }

        return getWindowAt(point: point, windowList: windowList, bundleIdentifierLookup: getBundleIdentifier)
    }

    /// Internal method for testing - allows injecting mock window data and bundle ID lookup
    /// - Parameters:
    ///   - point: Screen point to check
    ///   - windowList: Array of window info dictionaries (from CGWindowListCopyWindowInfo or mock)
    ///   - bundleIdentifierLookup: Function to look up bundle ID from PID (injectable for testing)
    /// - Returns: WindowInfo for the topmost window at point, or nil if none found
    static func getWindowAt(
        point: CGPoint,
        windowList: [[CFString: Any]],
        bundleIdentifierLookup: (pid_t) -> String?
    ) -> WindowInfo? {
        // Use nonisolated helper to find the window
        guard let basicInfo = getWindowAt(point: point, windowList: windowList) else {
            return nil
        }
        
        // Look up bundle identifier
        // Find the exact window by windowID to avoid issues with overlapping windows
        for windowInfo in windowList {
            guard let windowID = windowInfo[kCGWindowNumber] as? CGWindowID,
                  windowID == basicInfo.windowID else {
                continue
            }
            
            var bundleID: String?
            if let ownerPID = windowInfo[kCGWindowOwnerPID] as? pid_t {
                bundleID = bundleIdentifierLookup(ownerPID)
            }
            
            return WindowInfo(
                bounds: basicInfo.bounds,
                ownerName: basicInfo.ownerName,
                bundleIdentifier: bundleID,
                windowID: basicInfo.windowID
            )
        }
        
        return basicInfo
    }

    /// Internal method for testing - allows injecting mock window data
    /// - Parameters:
    ///   - point: Screen point to check
    ///   - windowList: Array of window info dictionaries (from CGWindowListCopyWindowInfo or mock)
    /// - Returns: WindowInfo for the topmost window at point, or nil if none found
    /// - Note: This nonisolated method does NOT look up bundle identifiers (which requires MainActor).
    ///         Use `getWindowAt(point:)` for production code that needs bundle IDs.
    nonisolated static func getWindowAt(point: CGPoint, windowList: [[CFString: Any]]) -> WindowInfo? {
        // Iterate through windows (front to back order)
        for windowInfo in windowList {
            // Only consider regular windows (layer 0)
            guard let layer = windowInfo[kCGWindowLayer] as? Int, layer == 0 else {
                continue
            }

            // Get window bounds
            guard let boundsDict = windowInfo[kCGWindowBounds] as? [String: CGFloat],
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else {
                continue
            }

            // Check if point is within this window
            if bounds.contains(point) {
                let ownerName = windowInfo[kCGWindowOwnerName] as? String
                let windowID = windowInfo[kCGWindowNumber] as? CGWindowID ?? 0

                // Note: Bundle ID lookup requires MainActor (NSRunningApplication)
                // This nonisolated test-injection method skips it - use getWindowAt(point:) for production
                return WindowInfo(
                    bounds: bounds,
                    ownerName: ownerName,
                    bundleIdentifier: nil,
                    windowID: windowID
                )
            }
        }

        return nil
    }

    /// Check if the window at cursor meets minimum size requirements
    /// - Parameters:
    ///   - minWidth: Minimum window width in pixels
    ///   - minHeight: Minimum window height in pixels
    /// - Returns: true if window meets minimum size or no window found, false if too small
    /// - Note: When no window is found (cursor over desktop), this returns true to allow gestures.
    ///         However, if `ignoreDesktop` is enabled in MultitouchManager, the desktop check
    ///         takes precedence and blocks gestures before this method is called. This method
    ///         returning true for desktop is intentional to handle edge cases where desktop
    ///         detection might fail, but the primary desktop filtering should use `ignoreDesktop`.
    static func windowAtCursorMeetsMinimumSize(minWidth: CGFloat, minHeight: CGFloat) -> Bool {
        guard let window = getWindowAtCursor() else {
            // No window found - allow gesture (could be desktop or edge case)
            return true
        }

        return window.width >= minWidth && window.height >= minHeight
    }

    /// Check if the cursor is currently over the desktop (no window underneath)
    /// - Returns: true if cursor is over desktop (no window found), false if over a window
    static func isCursorOverDesktop() -> Bool {
        return getWindowAtCursor() == nil
    }

    /// Internal method for testing - allows injecting mock window data and point
    /// - Parameters:
    ///   - point: Screen point in Quartz coordinates (origin top-left) to check
    ///   - windowList: Array of window info dictionaries (from CGWindowListCopyWindowInfo or mock)
    /// - Returns: true if no window found at point (over desktop), false if window exists
    nonisolated static func isCursorOverDesktop(at point: CGPoint, windowList: [[CFString: Any]]) -> Bool {
        return getWindowAt(point: point, windowList: windowList) == nil
    }

    /// Get the bundle identifier for a process
    /// - Parameter pid: Process ID
    /// - Returns: Bundle identifier string, or nil if not found
    private static func getBundleIdentifier(for pid: pid_t) -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return nil
        }
        return app.bundleIdentifier
    }
}
