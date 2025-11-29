import Foundation
import CoreGraphics

/// Manages mouse event generation and cursor movement
class MouseEventGenerator {
    
    // Configuration
    var smoothingFactor: Float = 0.3
    var minimumMovementThreshold: CGFloat = 0.5
    
    // State tracking
    private var isMiddleMouseDown = false
    private var eventSource: CGEventSource?
    
    // Event generation queue
    private let eventQueue = DispatchQueue(label: "com.middledrag.mouse", qos: .userInitiated)
    
    // MARK: - Initialization
    
    init() {
        // Create a reusable event source
        eventSource = CGEventSource(stateID: .hidSystemState)
    }
    
    // MARK: - Public Interface
    
    /// Start a middle mouse drag operation
    func startDrag(at screenPosition: CGPoint) {
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.isMiddleMouseDown = true
            
            // Send middle mouse down at current position (don't move cursor)
            self.sendMiddleMouseDown(at: screenPosition)
        }
    }
    
    /// Update drag position with delta movement (relative movement)
    func updateDrag(deltaX: CGFloat, deltaY: CGFloat) {
        guard isMiddleMouseDown else { return }
        
        // Skip tiny movements to prevent jitter
        let magnitude = sqrt(deltaX * deltaX + deltaY * deltaY)
        if magnitude < minimumMovementThreshold {
            return
        }
        
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Apply smoothing to delta
            var smoothedDeltaX = deltaX
            var smoothedDeltaY = deltaY
            
            if self.smoothingFactor > 0 {
                let factor = CGFloat(self.smoothingFactor)
                smoothedDeltaX *= factor
                smoothedDeltaY *= factor
            }
            
            // Create a relative mouse move event (this moves the cursor relatively)
            self.sendRelativeMouseMove(deltaX: smoothedDeltaX, deltaY: smoothedDeltaY)
        }
    }
    
    /// End the drag operation
    func endDrag() {
        guard isMiddleMouseDown else { return }
        
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.isMiddleMouseDown = false
            
            // Send middle mouse up at current cursor location
            let currentLocation = NSEvent.mouseLocation
            self.sendMiddleMouseUp(at: currentLocation)
        }
    }
    
    /// Perform a middle mouse click
    func performClick() {
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            
            let clickLocation = NSEvent.mouseLocation
            self.sendMiddleMouseDown(at: clickLocation)
            
            // Short delay for click
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) {
                self.sendMiddleMouseUp(at: clickLocation)
            }
        }
    }
    
    /// Cancel any active drag operation
    func cancelDrag() {
        if isMiddleMouseDown {
            endDrag()
        }
    }
    
    // MARK: - Private Methods
    
    private func sendMiddleMouseDown(at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .otherMouseDown,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        
        event.flags = []  // Clear any modifier flags
        event.post(tap: .cghidEventTap)
    }
    
    private func sendMiddleMouseUp(at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .otherMouseUp,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        
        event.flags = []
        event.post(tap: .cghidEventTap)
    }
    
    private func sendRelativeMouseMove(deltaX: CGFloat, deltaY: CGFloat) {
        // Get current mouse location
        let currentLocation = NSEvent.mouseLocation
        
        // Calculate new position
        let newLocation = CGPoint(
            x: currentLocation.x + deltaX,
            y: currentLocation.y + deltaY
        )
        
        // Send drag event with middle button held
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .otherMouseDragged,
            mouseCursorPosition: newLocation,
            mouseButton: .center
        ) else { return }
        
        event.flags = []
        
        // Post the event
        event.post(tap: .cghidEventTap)
    }
}

// MARK: - Screen Utilities

extension MouseEventGenerator {
    
    /// Get current mouse location
    static var currentMouseLocation: CGPoint {
        return NSEvent.mouseLocation
    }
}