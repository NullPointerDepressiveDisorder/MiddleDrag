import Foundation
import CoreGraphics

/// Manages mouse event generation and cursor movement
class MouseEventGenerator {
    
    // Configuration
    var smoothingFactor: Float = 0.3
    var minimumMovementThreshold: CGFloat = 0.5
    
    // State tracking
    private var isMiddleMouseDown = false
    private var lastCursorPosition: CGPoint = .zero
    private var smoothedCursorPosition: CGPoint = .zero
    private var initialMousePosition: CGPoint = .zero
    
    // Event generation queue
    private let eventQueue = DispatchQueue(label: "com.middledrag.mouse", qos: .userInitiated)
    
    // MARK: - Public Interface
    
    /// Start a middle mouse drag operation
    func startDrag(at screenPosition: CGPoint) {
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.isMiddleMouseDown = true
            self.initialMousePosition = screenPosition
            self.lastCursorPosition = screenPosition
            self.smoothedCursorPosition = screenPosition
            
            self.sendMiddleMouseDown(at: screenPosition)
        }
    }
    
    /// Update drag position with delta movement
    func updateDrag(deltaX: CGFloat, deltaY: CGFloat) {
        guard isMiddleMouseDown else { return }
        
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Calculate target position
            let targetX = self.initialMousePosition.x + deltaX
            let targetY = self.initialMousePosition.y + deltaY
            
            // Apply smoothing
            self.applySmoothing(targetX: targetX, targetY: targetY)
            
            // Check movement threshold
            let distance = hypot(
                self.smoothedCursorPosition.x - self.lastCursorPosition.x,
                self.smoothedCursorPosition.y - self.lastCursorPosition.y
            )
            
            if distance > self.minimumMovementThreshold {
                self.sendMiddleMouseDrag(at: self.smoothedCursorPosition)
                self.lastCursorPosition = self.smoothedCursorPosition
            }
        }
    }
    
    /// End the drag operation
    func endDrag() {
        guard isMiddleMouseDown else { return }
        
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.isMiddleMouseDown = false
            self.sendMiddleMouseUp(at: self.lastCursorPosition)
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
    
    private func applySmoothing(targetX: CGFloat, targetY: CGFloat) {
        let factor = CGFloat(smoothingFactor)
        smoothedCursorPosition.x += (targetX - smoothedCursorPosition.x) * factor
        smoothedCursorPosition.y += (targetY - smoothedCursorPosition.y) * factor
    }
    
    private func sendMiddleMouseDown(at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        
        event.flags = []  // Clear any modifier flags
        event.post(tap: .cghidEventTap)
    }
    
    private func sendMiddleMouseDrag(at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDragged,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        
        event.flags = []
        event.post(tap: .cghidEventTap)
    }
    
    private func sendMiddleMouseUp(at location: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseUp,
            mouseCursorPosition: location,
            mouseButton: .center
        ) else { return }
        
        event.flags = []
        event.post(tap: .cghidEventTap)
    }
}

// MARK: - Screen Utilities

extension MouseEventGenerator {
    
    /// Convert normalized coordinates to screen space
    static func normalizedToScreen(x: Float, y: Float) -> CGPoint {
        let screenBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        
        return CGPoint(
            x: CGFloat(x) * screenBounds.width,
            y: CGFloat(1.0 - y) * screenBounds.height  // Invert Y for screen coordinates
        )
    }
    
    /// Get current mouse location
    static var currentMouseLocation: CGPoint {
        return NSEvent.mouseLocation
    }
}
