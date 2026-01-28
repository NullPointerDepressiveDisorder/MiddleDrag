import AppKit
import CoreGraphics
import Foundation

/// Utility for multi-monitor screen coordinate handling
/// 
/// macOS uses two coordinate systems:
/// - Cocoa (AppKit): Origin at **bottom-left** of primary screen, Y increases upward
/// - Quartz (CoreGraphics): Origin at **top-left** of primary screen, Y increases downward
/// 
/// Both systems use a unified coordinate space spanning all monitors.
/// The **primary screen** (containing the menu bar) defines the coordinate origin.
/// 
/// IMPORTANT: `NSScreen.main` returns the screen with the focused window, NOT the primary screen.
/// For coordinate conversion, we must use `NSScreen.screens.first` which is always the primary screen.
class ScreenHelper {
    
    // MARK: - Primary Screen Access
    
    /// Get the primary screen (the one with the menu bar)
    /// 
    /// - Note: `NSScreen.screens.first` is always the primary screen per Apple documentation.
    ///         Do NOT use `NSScreen.main` which returns the screen with the focused window.
    @MainActor
    static var primaryScreen: NSScreen? {
        return NSScreen.screens.first
    }
    
    /// Get the height of the primary screen
    /// 
    /// This is required for Cocoa-to-Quartz coordinate conversion in multi-monitor setups.
    /// Using the wrong screen height will cause incorrect cursor positioning on secondary monitors.
    @MainActor
    static var primaryScreenHeight: CGFloat {
        return primaryScreen?.frame.height ?? 0
    }
    
    /// Get the height of the primary screen (thread-safe, nonisolated)
    /// 
    /// - Note: Must be called from main thread. For off-main-thread usage, 
    ///         prefer CGEvent-based coordinate retrieval which is already in Quartz coordinates.
    nonisolated static func getPrimaryScreenHeightSync() -> CGFloat {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { primaryScreenHeight }
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated { primaryScreenHeight }
            }
        }
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert a point from Cocoa coordinates to Quartz coordinates
    /// 
    /// - Parameter cocoaPoint: Point in Cocoa coordinates (origin at bottom-left of primary screen)
    /// - Returns: Point in Quartz coordinates (origin at top-left of primary screen)
    /// 
    /// - Note: This conversion is correct for ANY monitor in a multi-monitor setup because:
    ///         1. Both coordinate systems share the same X axis
    ///         2. Both coordinate systems use the primary screen as the origin reference
    ///         3. Only the Y axis needs flipping, using the primary screen height
    @MainActor
    static func cocoaToQuartz(_ cocoaPoint: CGPoint) -> CGPoint {
        let height = primaryScreenHeight
        return CGPoint(x: cocoaPoint.x, y: height - cocoaPoint.y)
    }
    
    /// Convert a point from Quartz coordinates to Cocoa coordinates
    /// 
    /// - Parameter quartzPoint: Point in Quartz coordinates (origin at top-left of primary screen)
    /// - Returns: Point in Cocoa coordinates (origin at bottom-left of primary screen)
    @MainActor
    static func quartzToCocoa(_ quartzPoint: CGPoint) -> CGPoint {
        let height = primaryScreenHeight
        return CGPoint(x: quartzPoint.x, y: height - quartzPoint.y)
    }
    
    /// Convert Y coordinate from Cocoa to Quartz
    /// 
    /// - Parameter cocoaY: Y coordinate in Cocoa coordinate system
    /// - Returns: Y coordinate in Quartz coordinate system
    @MainActor
    static func cocoaYToQuartzY(_ cocoaY: CGFloat) -> CGFloat {
        return primaryScreenHeight - cocoaY
    }
    
    /// Convert Y coordinate from Cocoa to Quartz (thread-safe, nonisolated)
    /// 
    /// - Parameter cocoaY: Y coordinate in Cocoa coordinate system
    /// - Returns: Y coordinate in Quartz coordinate system
    nonisolated static func cocoaYToQuartzYSync(_ cocoaY: CGFloat) -> CGFloat {
        let height = getPrimaryScreenHeightSync()
        return height - cocoaY
    }
    
    // MARK: - Screen Detection
    
    /// Get the screen containing a point (in Quartz coordinates)
    /// 
    /// - Parameter quartzPoint: Point in Quartz coordinates
    /// - Returns: The screen containing the point, or nil if no screen contains it
    @MainActor
    static func screenContaining(quartzPoint: CGPoint) -> NSScreen? {
        // Convert to Cocoa for NSScreen.frame comparison
        let cocoaPoint = quartzToCocoa(quartzPoint)
        return screenContaining(cocoaPoint: cocoaPoint)
    }
    
    /// Get the screen containing a point (in Cocoa coordinates)
    /// 
    /// - Parameter cocoaPoint: Point in Cocoa coordinates
    /// - Returns: The screen containing the point, or nil if no screen contains it
    @MainActor
    static func screenContaining(cocoaPoint: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.frame.contains(cocoaPoint) {
                return screen
            }
        }
        return nil
    }
    
    // MARK: - Mouse Position Utilities
    
    /// Get current mouse position in Quartz coordinates
    /// 
    /// Uses CGEvent for thread-safe coordinate retrieval (preferred).
    /// Falls back to NSEvent.mouseLocation with proper multi-monitor conversion.
    /// 
    /// - Returns: Current mouse position in Quartz coordinates
    nonisolated static func currentMousePositionQuartz() -> CGPoint {
        // CGEvent.location is already in Quartz coordinates and is thread-safe
        if let event = CGEvent(source: nil) {
            return event.location
        }
        
        // Fallback: convert from Cocoa coordinates using PRIMARY screen height
        // This is the critical fix for multi-monitor support
        let cocoaLocation = NSEvent.mouseLocation
        let primaryHeight = getPrimaryScreenHeightSync()
        return CGPoint(x: cocoaLocation.x, y: primaryHeight - cocoaLocation.y)
    }
    
    // MARK: - Multi-Monitor Information
    
    /// Check if the system has multiple monitors
    @MainActor
    static var hasMultipleMonitors: Bool {
        return NSScreen.screens.count > 1
    }
    
    /// Get the total bounds of all screens in Quartz coordinates
    @MainActor
    static var totalScreenBounds: CGRect {
        var minX: CGFloat = 0
        var minY: CGFloat = 0
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        
        for screen in NSScreen.screens {
            let frame = screen.frame
            // Convert to Quartz coordinates for each corner
            let topLeft = cocoaToQuartz(CGPoint(x: frame.minX, y: frame.maxY))
            let bottomRight = cocoaToQuartz(CGPoint(x: frame.maxX, y: frame.minY))
            
            minX = min(minX, topLeft.x)
            minY = min(minY, topLeft.y)
            maxX = max(maxX, bottomRight.x)
            maxY = max(maxY, bottomRight.y)
        }
        
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
