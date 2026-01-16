import AppKit
import CoreGraphics
import Foundation
import Sentry
@preconcurrency import os.log

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

    // Smoothing state for EMA (exponential moving average)
    private var previousDeltaX: CGFloat = 0
    private var previousDeltaY: CGFloat = 0

    // Track the last sent mouse position to build relative movements correctly
    // This prevents jumps from reading stale current mouse positions
    // Using a lock for thread-safe position updates
    private var lastSentPosition: CGPoint?
    private let positionLock = NSLock()

    // MARK: - Initialization

    init() {
        // Create event source with private state to avoid interference with system events
        eventSource = CGEventSource(stateID: .privateState)
    }

    // MARK: - Public Interface

    /// Start a middle mouse drag operation
    /// - Parameter screenPosition: Starting position (used for reference, actual position from current cursor)
    func startDrag(at screenPosition: CGPoint) {
        // Initialize position synchronously to prevent race conditions with updateDrag
        let quartzPos = currentMouseLocationQuartz
        positionLock.lock()
        lastSentPosition = quartzPos
        positionLock.unlock()

        // Reset smoothing state
        previousDeltaX = 0
        previousDeltaY = 0

        // Now do the async part for sending the mouse down event
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            self.isMiddleMouseDown = true
            self.sendMiddleMouseDown(at: quartzPos)
        }
    }

    /// Magic number to identify our own events (0x4D44 = 'MD')
    private let magicUserData: Int64 = 0x4D44

    /// Update drag position with delta movement
    /// - Parameters:
    ///   - deltaX: Horizontal movement delta
    ///   - deltaY: Vertical movement delta
    func updateDrag(deltaX: CGFloat, deltaY: CGFloat) {
        guard isMiddleMouseDown else { return }

        // Apply consistent smoothing to both horizontal and vertical movement
        // Uses the user's configured smoothing factor for both axes
        let factor = CGFloat(smoothingFactor)
        var smoothedDeltaX = deltaX
        var smoothedDeltaY = deltaY
        if smoothingFactor > 0 {
            smoothedDeltaX = previousDeltaX * factor + deltaX * (1 - factor)
            smoothedDeltaY = previousDeltaY * factor + deltaY * (1 - factor)
        }

        // Store for next frame's smoothing
        previousDeltaX = smoothedDeltaX
        previousDeltaY = smoothedDeltaY

        // Skip if movement is too small (but be very lenient for horizontal)
        let horizontalMagnitude = abs(smoothedDeltaX)
        let verticalMagnitude = abs(smoothedDeltaY)
        if horizontalMagnitude < 0.001 && verticalMagnitude < minimumMovementThreshold {
            return
        }

        // CRITICAL: Use tracked position, NOT current system position
        // Reading currentMouseLocationQuartz causes snap-back because:
        // 1. We send an event to move cursor
        // 2. Before macOS processes it, we read current position (still old)
        // 3. We add delta to old position = snap-back effect
        // Solution: Track our own position and build from it sequentially
        positionLock.lock()
        let basePosition: CGPoint
        if let lastPos = lastSentPosition {
            basePosition = lastPos
        } else {
            // First update - initialize from current position
            basePosition = currentMouseLocationQuartz
        }

        let newLocation = CGPoint(
            x: basePosition.x + smoothedDeltaX,
            y: basePosition.y + smoothedDeltaY
        )

        // Update tracked position immediately
        lastSentPosition = newLocation
        positionLock.unlock()

        // Track horizontal movement for debugging snap-back issues
        // Log to console and Sentry breadcrumbs when enabled
        let horizontalChange = abs(smoothedDeltaX)
        let positionChange = abs(newLocation.x - basePosition.x)

        // Detect potential snap-back: large delta but small position change, or vice versa
        let potentialSnapBack =
            (horizontalChange > 5.0 && positionChange < horizontalChange * 0.5)
            || (horizontalChange < 1.0 && positionChange > horizontalChange * 2.0)

        // Log all significant horizontal movements
        // Use os_log for local logging (always works) and Sentry if enabled
        if abs(deltaX) > 1.0 || potentialSnapBack {
            let subsystem = Bundle.main.bundleIdentifier ?? "com.middledrag"
            let log = OSLog(subsystem: subsystem, category: "gesture")
            let message =
                unsafe potentialSnapBack
                ? "Horizontal drag snap-back detected"
                : String(
                    format: "Horizontal drag: delta=%.2f posChange=%.2f", deltaX, positionChange)

            // Log locally first (always works)
            unsafe os_log(.info, log: log, "%{public}@", message)

            // Only log to Sentry if telemetry is enabled (offline by default)
            // App must be offline by default - no network calls unless user opts in
            guard CrashReporter.shared.anyTelemetryEnabled else { return }

            let attributes: [String: Any] = unsafe [
                "category": "gesture",
                "drag_movement": "horizontal",
                "axis": "horizontal",
                "movement_type": potentialSnapBack ? "snap_back" : "normal",
                "deltaX_magnitude": String(format: "%.0f", abs(deltaX)),
                "rawDeltaX": deltaX,
                "smoothedDeltaX": smoothedDeltaX,
                "rawDeltaY": deltaY,
                "smoothedDeltaY": smoothedDeltaY,
                "baseX": basePosition.x,
                "baseY": basePosition.y,
                "newX": newLocation.x,
                "newY": newLocation.y,
                "positionChangeX": positionChange,
                "positionChangeY": abs(newLocation.y - basePosition.y),
                "horizontalChange": horizontalChange,
                "potentialSnapBack": potentialSnapBack,
                "smoothingFactor": smoothingFactor,
                "minMovementThreshold": minimumMovementThreshold,
                "timestamp": Date().timeIntervalSince1970,
                "session_id": Log.sessionID,
            ]

            if potentialSnapBack {
                SentrySDK.logger.warn(message, attributes: attributes)
            } else {
                SentrySDK.logger.info(message, attributes: attributes)
            }
        }

        // Send the mouse event immediately (on current thread) for maximum responsiveness
        // Position is already locked and updated above, so this is safe
        guard
            let event = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .otherMouseDragged,
                mouseCursorPosition: newLocation,
                mouseButton: .center
            )
        else { return }

        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        event.setIntegerValueField(.eventSourceUserData, value: magicUserData)
        event.flags = []
        event.post(tap: .cghidEventTap)
    }

    /// End the drag operation
    func endDrag() {
        guard isMiddleMouseDown else { return }

        eventQueue.async { [weak self] in
            guard let self = self else { return }

            self.isMiddleMouseDown = false
            // Reset smoothing state
            self.previousDeltaX = 0
            self.previousDeltaY = 0
            self.positionLock.lock()
            self.lastSentPosition = nil
            self.positionLock.unlock()
            let currentPos = self.currentMouseLocationQuartz
            self.sendMiddleMouseUp(at: currentPos)
        }
    }

    /// Perform a middle mouse click
    /// Note: cancelDrag() should be called first if there might be an active drag.
    /// This method handles the edge case where rapid taps might leave the button stuck.
    func performClick() {
        eventQueue.async { [weak self] in
            guard let self = self else { return }

            // If mouse is already down, we're either:
            // 1. In an active drag (normal case) - don't interfere, just return
            // 2. In a stuck state (edge case) - cancelDrag() should have handled this
            // Since cancelDrag() and performClick() are both on the same serial queue,
            // cancelDrag() will have already executed by the time this runs if it was called.
            // If isMiddleMouseDown is still true here and cancelDrag() wasn't called,
            // it means we're in an active drag and shouldn't perform a click.
            if self.isMiddleMouseDown {
                // Don't interfere with active drags - just return
                // This prevents glitches during drag operations
                return
            }

            let clickLocation = self.currentMouseLocationQuartz

            // Create mouse down event
            guard
                let downEvent = CGEvent(
                    mouseEventSource: self.eventSource,
                    mouseType: .otherMouseDown,
                    mouseCursorPosition: clickLocation,
                    mouseButton: .center
                )
            else { return }

            downEvent.setIntegerValueField(.mouseEventClickState, value: 1)
            downEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            downEvent.setIntegerValueField(.eventSourceUserData, value: self.magicUserData)
            downEvent.flags = []

            // Create mouse up event
            guard
                let upEvent = CGEvent(
                    mouseEventSource: self.eventSource,
                    mouseType: .otherMouseUp,
                    mouseCursorPosition: clickLocation,
                    mouseButton: .center
                )
            else { return }

            upEvent.setIntegerValueField(.mouseEventClickState, value: 1)
            upEvent.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            upEvent.setIntegerValueField(.eventSourceUserData, value: self.magicUserData)
            upEvent.flags = []

            // Post events with small delay between them
            downEvent.post(tap: .cghidEventTap)
            usleep(10000)  // 10ms delay
            upEvent.post(tap: .cghidEventTap)
        }
    }

    /// Cancel any active drag operation
    func cancelDrag() {
        guard isMiddleMouseDown else { return }

        // Asynchronously end the drag - this won't block the event queue
        // The cleanup will happen on the event queue, ensuring proper sequencing
        // with other operations like performClick()
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            self.isMiddleMouseDown = false
            // Reset smoothing state
            self.previousDeltaX = 0
            self.previousDeltaY = 0
            self.positionLock.lock()
            self.lastSentPosition = nil
            self.positionLock.unlock()
            let currentPos = self.currentMouseLocationQuartz
            self.sendMiddleMouseUp(at: currentPos)
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
        guard
            let event = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .otherMouseDown,
                mouseCursorPosition: location,
                mouseButton: .center
            )
        else { return }

        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        event.setIntegerValueField(.eventSourceUserData, value: magicUserData)
        event.flags = []
        event.post(tap: .cghidEventTap)
    }

    private func sendMiddleMouseUp(at location: CGPoint) {
        guard
            let event = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .otherMouseUp,
                mouseCursorPosition: location,
                mouseButton: .center
            )
        else { return }

        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        event.setIntegerValueField(.eventSourceUserData, value: magicUserData)
        event.flags = []
        event.post(tap: .cghidEventTap)
    }

    private func sendRelativeMouseMove(deltaX: CGFloat, deltaY: CGFloat) {
        // We're already on positionQueue, so we can access lastSentPosition directly
        // Use the last sent position to build relative movements correctly
        // This prevents jumps from reading stale current mouse positions
        let basePosition: CGPoint
        if let lastPos = lastSentPosition {
            basePosition = lastPos
        } else {
            // Fallback to current position if we don't have a last position
            basePosition = currentMouseLocationQuartz
        }

        let newLocation = CGPoint(
            x: basePosition.x + deltaX,
            y: basePosition.y + deltaY
        )

        // Update last sent position (we're already on positionQueue)
        lastSentPosition = newLocation

        guard
            let event = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .otherMouseDragged,
                mouseCursorPosition: newLocation,
                mouseButton: .center
            )
        else { return }

        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
        event.setIntegerValueField(.eventSourceUserData, value: magicUserData)
        event.flags = []
        event.post(tap: .cghidEventTap)
    }
}
