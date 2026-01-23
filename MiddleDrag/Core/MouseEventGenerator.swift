import AppKit
import CoreGraphics
import Foundation
import Sentry
@unsafe @preconcurrency import os.log

/// Generates mouse events for middle-click and middle-drag operations
/// Thread-safety: Uses stateLock and positionLock for internal synchronization
final class MouseEventGenerator: @unchecked Sendable {

    // MARK: - Properties

    /// Smoothing factor for movement (0 = no smoothing, 1 = maximum)
    var smoothingFactor: Float = 0.3

    /// Minimum movement threshold in pixels to prevent jitter
    var minimumMovementThreshold: CGFloat = 0.5
    
    /// Timeout in seconds for stuck drag detection (no activity = stuck)
    /// After this many seconds without updateDrag calls, the drag is auto-released
    var stuckDragTimeout: TimeInterval = 10.0

    // State tracking - protected by stateLock for thread safety
    // isMiddleMouseDown is read from multiple threads (updateDrag on gesture queue,
    // written on eventQueue), so it needs synchronization
    private let stateLock = NSLock()
    private var _isMiddleMouseDown = false
    private var isMiddleMouseDown: Bool {
        get { stateLock.withLock { _isMiddleMouseDown } }
        set { stateLock.withLock { _isMiddleMouseDown = newValue } }
    }
    
    private var eventSource: CGEventSource?

    // Event generation queue for thread safety
    private let eventQueue = DispatchQueue(label: "com.middledrag.mouse", qos: .userInitiated)
    
    // Watchdog timer for stuck drag detection
    private var watchdogTimer: DispatchSourceTimer?
    private let watchdogQueue = DispatchQueue(label: "com.middledrag.watchdog", qos: .utility)
    private var lastActivityTime: CFTimeInterval = 0
    private let activityLock = NSLock()

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
        // CRITICAL: If already in a drag state, cancel it first to prevent stuck drags
        // This handles the case where a second MIDDLE_DOWN arrives before the first MIDDLE_UP
        if isMiddleMouseDown {
            Log.warning("startDrag called while already dragging - canceling existing drag first", category: .gesture)
            // Send mouse up for the existing drag immediately (synchronously)
            let currentPos = currentMouseLocationQuartz
            sendMiddleMouseUp(at: currentPos)
        }
        
        // Initialize position synchronously to prevent race conditions with updateDrag
        let quartzPos = currentMouseLocationQuartz
        positionLock.lock()
        lastSentPosition = quartzPos
        positionLock.unlock()

        // Reset smoothing state
        previousDeltaX = 0
        previousDeltaY = 0
        
        // Record activity time for watchdog
        activityLock.lock()
        lastActivityTime = CACurrentMediaTime()
        activityLock.unlock()

        // CRITICAL: Both flag AND mouse-down event must be set/sent SYNCHRONOUSLY.
        // This prevents two race conditions:
        // 1. endDrag() seeing isMiddleMouseDown=false (original sticky bug)
        // 2. updateDrag() sending drag events before mouse-down reaches macOS
        //
        // sendMiddleMouseDown() just creates and posts a CGEvent, which is thread-safe
        // and takes microseconds. No need for async dispatch here.
        isMiddleMouseDown = true
        sendMiddleMouseDown(at: quartzPos)
        
        // Start watchdog timer to detect stuck drags
        startWatchdog()
    }

    /// Magic number to identify our own events (0x4D44 = 'MD')
    private let magicUserData: Int64 = 0x4D44

    /// Update drag position with delta movement
    /// - Parameters:
    ///   - deltaX: Horizontal movement delta
    ///   - deltaY: Vertical movement delta
    func updateDrag(deltaX: CGFloat, deltaY: CGFloat) {
        guard isMiddleMouseDown else { return }
        
        // Record activity time for watchdog (drag is still active)
        activityLock.lock()
        lastActivityTime = CACurrentMediaTime()
        activityLock.unlock()

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
        
        // Read current position before acquiring lock to avoid blocking other threads
        // This is only used as fallback if lastSentPosition is nil
        let fallbackPosition = currentMouseLocationQuartz
        
        positionLock.lock()
        let basePosition: CGPoint
        if let lastPos = lastSentPosition {
            basePosition = lastPos
        } else {
            // First update - initialize from current position
            basePosition = fallbackPosition
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
            if CrashReporter.shared.anyTelemetryEnabled {
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
        
        // Stop watchdog since drag is ending normally
        stopWatchdog()

        // CRITICAL: Set isMiddleMouseDown = false SYNCHRONOUSLY to match startDrag
        // This prevents race conditions with rapid start/end cycles and ensures
        // updateDrag() stops processing immediately
        isMiddleMouseDown = false

        eventQueue.async { [weak self] in
            guard let self = self else { return }

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
        
        // Stop watchdog since drag is being cancelled
        stopWatchdog()

        // CRITICAL: Set isMiddleMouseDown = false SYNCHRONOUSLY to match startDrag
        // This prevents race conditions with rapid cancel/start cycles and ensures
        // updateDrag() stops processing immediately
        isMiddleMouseDown = false

        // Asynchronously send the mouse up event and clean up state
        // The cleanup will happen on the event queue, ensuring proper sequencing
        // with other operations like performClick()
        eventQueue.async { [weak self] in
            guard let self = self else { return }
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
        // Use the last sent position to build relative movements correctly
        // This prevents jumps from reading stale current mouse positions
        // Note: This function appears to be unused but kept for potential future use
        positionLock.lock()
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

        // Update last sent position
        lastSentPosition = newLocation
        positionLock.unlock()

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
    
    // MARK: - Watchdog Timer
    
    /// Start the watchdog timer to detect stuck drags
    private func startWatchdog() {
        stopWatchdog()  // Cancel any existing timer
        
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)  // Check every second
        
        timer.setEventHandler { [weak self] in
            self?.checkForStuckDrag()
        }
        
        watchdogTimer = timer
        timer.resume()
    }
    
    /// Stop the watchdog timer
    private func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }
    
    /// Check if the drag has become stuck (no activity for too long)
    private func checkForStuckDrag() {
        guard isMiddleMouseDown else {
            // Drag already ended, stop checking
            stopWatchdog()
            return
        }
        
        activityLock.lock()
        let lastActivity = lastActivityTime
        activityLock.unlock()
        
        let timeSinceActivity = CACurrentMediaTime() - lastActivity
        
        if timeSinceActivity > stuckDragTimeout {
            // Drag appears to be stuck - auto-release
            Log.warning(
                "Stuck drag detected - no activity for \(String(format: "%.1f", timeSinceActivity))s, auto-releasing",
                category: .gesture
            )
            
            // Log to Sentry if telemetry is enabled
            if CrashReporter.shared.anyTelemetryEnabled {
                let attributes: [String: Any] = [
                    "category": "gesture",
                    "event": "stuck_drag_auto_release",
                    "time_since_activity": timeSinceActivity,
                    "timeout_threshold": stuckDragTimeout,
                    "session_id": Log.sessionID,
                ]
                SentrySDK.logger.warn("Stuck drag auto-released after timeout", attributes: attributes)
            }
            
            // Force release the stuck drag
            forceReleaseDrag()
        }
    }
    
    /// Force release a stuck drag without normal cleanup flow
    /// This is called by the watchdog when a drag appears stuck
    private func forceReleaseDrag() {
        stopWatchdog()
        
        // Set flag to false immediately to stop any further processing
        isMiddleMouseDown = false
        
        // Send mouse up event synchronously to ensure it gets through
        let currentPos = currentMouseLocationQuartz
        sendMiddleMouseUp(at: currentPos)
        
        // Also try sending via async queue in case the sync one gets swallowed
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            // Reset smoothing state
            self.previousDeltaX = 0
            self.previousDeltaY = 0
            self.positionLock.lock()
            self.lastSentPosition = nil
            self.positionLock.unlock()
            
            // Send another mouse up as a fallback
            let pos = self.currentMouseLocationQuartz
            self.sendMiddleMouseUp(at: pos)
        }
    }
}
