import AppKit
import CoreGraphics
import Foundation

/// Utility for multi-monitor screen coordinate handling
///
/// - Cocoa: Origin at bottom-left of primary screen, Y increases upward
/// - Quartz: Origin at top-left of primary screen, Y increases downward
///
/// Uses `NSScreen.screens.first` (primary screen), not `NSScreen.main` (focused window's screen).
class ScreenHelper {
    
    // MARK: - Primary Screen Access
    
    /// Primary screen (menu bar screen)
    @MainActor
    static var primaryScreen: NSScreen? {
        return NSScreen.screens.first
    }
    
    /// Height of the primary screen
    @MainActor
    static var primaryScreenHeight: CGFloat {
        return primaryScreen?.frame.height ?? 0
    }
    
    /// Height of the primary screen (thread-safe)
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
    
    /// Convert Cocoa coordinates to Quartz coordinates
    @MainActor
    static func cocoaToQuartz(_ cocoaPoint: CGPoint) -> CGPoint {
        let height = primaryScreenHeight
        return CGPoint(x: cocoaPoint.x, y: height - cocoaPoint.y)
    }
    
    /// Convert Quartz coordinates to Cocoa coordinates
    @MainActor
    static func quartzToCocoa(_ quartzPoint: CGPoint) -> CGPoint {
        let height = primaryScreenHeight
        return CGPoint(x: quartzPoint.x, y: height - quartzPoint.y)
    }
    
    /// Convert Y coordinate from Cocoa to Quartz
    @MainActor
    static func cocoaYToQuartzY(_ cocoaY: CGFloat) -> CGFloat {
        return primaryScreenHeight - cocoaY
    }
    
    /// Convert Y coordinate from Cocoa to Quartz (thread-safe)
    nonisolated static func cocoaYToQuartzYSync(_ cocoaY: CGFloat) -> CGFloat {
        let height = getPrimaryScreenHeightSync()
        return height - cocoaY
    }
    
    // MARK: - Screen Detection
    
    /// Get the screen containing a point (Quartz coordinates)
    @MainActor
    static func screenContaining(quartzPoint: CGPoint) -> NSScreen? {
        let cocoaPoint = quartzToCocoa(quartzPoint)
        return screenContaining(cocoaPoint: cocoaPoint)
    }
    
    /// Get the screen containing a point (Cocoa coordinates)
    @MainActor
    static func screenContaining(cocoaPoint: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            if screen.frame.contains(cocoaPoint) {
                return screen
            }
        }
        return nil
    }
    
    // MARK: - Mouse Position
    
    /// Current mouse position in Quartz coordinates
    nonisolated static func currentMousePositionQuartz() -> CGPoint {
        if let event = CGEvent(source: nil) {
            return event.location
        }
        
        let cocoaLocation = NSEvent.mouseLocation
        let primaryHeight = getPrimaryScreenHeightSync()
        return CGPoint(x: cocoaLocation.x, y: primaryHeight - cocoaLocation.y)
    }
    
    // MARK: - Multi-Monitor Info
    
    /// Whether the system has multiple monitors
    @MainActor
    static var hasMultipleMonitors: Bool {
        return NSScreen.screens.count > 1
    }
    
    /// Total bounds of all screens in Quartz coordinates
    @MainActor
    static var totalScreenBounds: CGRect {
        var minX: CGFloat = 0
        var minY: CGFloat = 0
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        
        for screen in NSScreen.screens {
            let frame = screen.frame
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
