import AppKit
import CoreGraphics
import Foundation

/// Information about a window at a specific screen location
struct WindowInfo {
    let bounds: CGRect
    let ownerName: String?
    let bundleIdentifier: String?
    let windowID: CGWindowID

    var width: CGFloat { bounds.width }
    var height: CGFloat { bounds.height }
}

/// Utility for detecting window information under the cursor
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

        return getWindowAt(point: point, windowList: windowList)
    }

    /// Internal method for testing - allows injecting mock window data
    /// - Parameters:
    ///   - point: Screen point to check
    ///   - windowList: Array of window info dictionaries (from CGWindowListCopyWindowInfo or mock)
    /// - Returns: WindowInfo for the topmost window at point, or nil if none found
    static func getWindowAt(point: CGPoint, windowList: [[CFString: Any]]) -> WindowInfo? {
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

                // Try to get bundle identifier from the owning process
                var bundleID: String?
                if let ownerPID = windowInfo[kCGWindowOwnerPID] as? pid_t {
                    bundleID = getBundleIdentifier(for: ownerPID)
                }

                return WindowInfo(
                    bounds: bounds,
                    ownerName: ownerName,
                    bundleIdentifier: bundleID,
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
    static func windowAtCursorMeetsMinimumSize(minWidth: CGFloat, minHeight: CGFloat) -> Bool {
        guard let window = getWindowAtCursor() else {
            // No window found - allow gesture (could be desktop or edge case)
            return true
        }

        return window.width >= minWidth && window.height >= minHeight
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
