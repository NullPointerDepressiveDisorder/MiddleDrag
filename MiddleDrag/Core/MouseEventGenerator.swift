import Foundation
import CoreGraphics
import AppKit

/// Generates mouse events for middle-click and middle-drag operations
class MouseEventGenerator {
    
    // MARK: - Properties
    
    /// Smoothing factor for movement (0 = no smoothing, 1 = maximum)
    var smoothingFactor: Float = 0.3
    
    /// Minimum movement threshold in pixels to prevent jitter
    var minimumMovementThreshold: CGFloat = 0.5
    
    // State tracking
    private var isMiddleMouseDown = false
    private var eventSource: CGEventSource?
    
    // Event generation queue for thread safety
    private let eventQueue = DispatchQueue(label: "com.middledrag.mouse", qos: .userInitiated)
    
    // MARK: - Initialization
    
    init() {
        // Create event source with private state to avoid interference with system events
        eventSource = CGEventSource(stateID: .privateState)
    }
    
    // MARK: - Public Interface
    
    /// Start a middle mouse drag operation
    /// - Parameter screenPosition: Starting position (used for reference, actual position from current cursor)
    func startDrag(at screenPosition: CGPoint) {
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.isMiddleMouseDown = true
            let quartzPos = self.currentMouseLocationQuartz
            self.sendMiddleMouseDown(at: quartzPos)
        }
    }
    
    /// Update drag position with delta movement
    /// - Parameters:
    ///   - deltaX: Horizontal movement delta
    ///   - deltaY: Vertical movement delta
    func updateDrag(deltaX: CGFloat, deltaY: CGFloat) {
        guard isMiddleMouseDown else { return }
        
        // Skip tiny movements to prevent jitter
        let magnitude = sqrt(deltaX * deltaX + deltaY * deltaY)
        if magnitude < minimumMovementThreshold {
            return
        }
        
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Apply smoothing
            var smoothedDeltaX = deltaX
            var smoothedDeltaY = deltaY
            
            if self.smoothingFactor > 0 {
                let factor = CGFloat(self.smoothingFactor)
                smoothedDeltaX *= factor
                smoothedDeltaY *= factor
            }
            
            self.sendRelativeMouseMove(deltaX: smoothedDeltaX, deltaY: smoothedDeltaY)
        }
    }
    
    /// End the drag operation
    func endDrag() {
        guard isMiddleMouseDown else { return }
        
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.isMiddleMouseDown = false
            let currentPos = self.currentMouseLocationQuartz
            self.sendMiddleMouseUp(at: currentPos)
        }
    }
    
    /// Perform a middle mouse click
    func performClick() {
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            
            let clickLocation = self.currentMouseLocationQuartz
            
            // Create mouse down event
            guard let downEvent = CGEvent(
                mouseEventSource: self.eventSource,
                mouseType: .otherMouseDown,
                mouseCursorPosition: clickLocation,
                mouseButton: .center
            ) else { return }
            
            downEvent.setIntegerValueField(.mouseEventClickState, value: 1)
            downEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            downEvent.flags = []
            
            // Create mouse up event
            guard let upEvent = CGEvent(
                mouseEventSource: self.eventSource,
                mouseType: .otherMouseUp,
                mouseCursorPosition: clickLocation,
                mouseButton: .center
            ) else { return }
            
            upEvent.setIntegerValueField(.mouseEventClickState, value: 1)
            upEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            upEvent.flags = []
            
            // Post events with small delay between them
            downEvent.post(tap: .cghidEventTap)
            usleep(10000)  // 10ms delay
            upEvent.post(tap: .cghidEventTap)
        }
    }
    
    /// Cancel any active drag operation
    func cancelDrag() {
        if isMiddleMouseDown {
            endDrag()
        }
    }
    
    // MARK: - Coordinate Conversion
    
    /// Get current mouse position in Quartz coordinates (origin at top-left)
    private var currentMouseLocationQuartz: CGPoint {
        if let event = CGEvent(source: nil) {
            return event.location
        }
        
        // Fallback: convert from Cocoa coordinates (origin at bottom-left)
        let cocoaLocation = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        return CGPoint(x: cocoaLocation.x, y: screenHeight - cocoaLocation.y)
    }
    
    /// Get current mouse location in Quartz coordinates (public access)
    static var currentMouseLocation: CGPoint {
        if let event = CGEvent(source: nil) {
            return event.location
        }
        let cocoaLocation = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        return CGPoint(x: cocoaLocation.x, y: screenHeight - cocoaLocation.y)
    }
    
    // MARK: - Private Methods
    
    private func sendMiddleMouseDown(at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .otherMouseDown,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        event.flags = []
        event.post(tap: .cghidEventTap)
    }
    
    private func sendMiddleMouseUp(at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .otherMouseUp,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        event.flags = []
        event.post(tap: .cghidEventTap)
    }
    
    private func sendRelativeMouseMove(deltaX: CGFloat, deltaY: CGFloat) {
        let currentPos = currentMouseLocationQuartz
        
        let newLocation = CGPoint(
            x: currentPos.x + deltaX,
            y: currentPos.y + deltaY
        )
        
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .otherMouseDragged,
            mouseCursorPosition: newLocation,
            mouseButton: .center
        ) else { return }
        
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        event.flags = []
        event.post(tap: .cghidEventTap)
    }
}
