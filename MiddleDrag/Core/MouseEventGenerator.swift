import AppKit
import CoreGraphics
import Foundation
import Sentry
@unsafe @preconcurrency import os.log

/// Generates mouse events for middle-click and middle-drag operations
/// Thread-safety: Uses stateLock for internal synchronization
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
    
    /// Drag session generation counter - protected by stateLock
    /// Must be accessed atomically with isMiddleMouseDown to prevent race conditions
    private var _dragGeneration: UInt64 = 0
    
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
        
        let quartzPos = currentMouseLocationQuartz

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
        //
        // CRITICAL: isMiddleMouseDown and dragGeneration must be set ATOMICALLY
        // to prevent race with forceReleaseDrag() on watchdogQueue
        stateLock.withLock {
            _isMiddleMouseDown = true
            _dragGeneration &+= 1
        }
        sendMiddleMouseDown(at: quartzPos)
        
        // Start watchdog timer to detect stuck drags
        startWatchdog()
    }

    /// Magic number to identify our own events (0x4D44 = 'MD')
    private let magicUserData: Int64 = 0x4D44

    /// Update drag position with delta movement
    /// - Parameters:
    ///   - deltaX: Horizontal movement delta (in pixels)
    ///   - deltaY: Vertical movement delta (in pixels)
    func updateDrag(deltaX: CGFloat, deltaY: CGFloat) {
        guard isMiddleMouseDown else { return }
        
        activityLock.lock()
        lastActivityTime = CACurrentMediaTime()
        activityLock.unlock()

        // Apply EMA smoothing
        let factor = CGFloat(smoothingFactor)
        var smoothedDeltaX = deltaX
        var smoothedDeltaY = deltaY
        if smoothingFactor > 0 {
            smoothedDeltaX = previousDeltaX * factor + deltaX * (1 - factor)
            smoothedDeltaY = previousDeltaY * factor + deltaY * (1 - factor)
        }

        previousDeltaX = smoothedDeltaX
        previousDeltaY = smoothedDeltaY

        let horizontalMagnitude = abs(smoothedDeltaX)
        let verticalMagnitude = abs(smoothedDeltaY)
        if horizontalMagnitude < 0.001 && verticalMagnitude < minimumMovementThreshold {
            return
        }

        let currentPos = currentMouseLocationQuartz
        let targetPos = CGPoint(
            x: currentPos.x + smoothedDeltaX,
            y: currentPos.y + smoothedDeltaY
        )
        
        guard
            let event = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .otherMouseDragged,
                mouseCursorPosition: targetPos,
                mouseButton: .center
            )
        else { return }

        // Set deltas for macOS cursor movement; position field for apps that read it
        event.setDoubleValueField(.mouseEventDeltaX, value: Double(smoothedDeltaX))
        event.setDoubleValueField(.mouseEventDeltaY, value: Double(smoothedDeltaY))
        
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

            self.previousDeltaX = 0
            self.previousDeltaY = 0
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
            self.previousDeltaX = 0
            self.previousDeltaY = 0
            let currentPos = self.currentMouseLocationQuartz
            self.sendMiddleMouseUp(at: currentPos)
        }
    }
    
    /// Force send a MIDDLE_UP event regardless of internal state
    /// Used for manual recovery when system state may be out of sync with our tracking
    /// Unlike cancelDrag(), this ALWAYS sends an UP event even if isMiddleMouseDown is false
    func forceMiddleMouseUp() {
        Log.warning("Force sending MIDDLE_UP (unconditional)", category: .gesture)
        
        // Stop watchdog if running
        stopWatchdog()
        
        // Atomically reset state and capture generation
        let currentGeneration: UInt64 = stateLock.withLock {
            _isMiddleMouseDown = false
            return _dragGeneration
        }
        
        // Always send the UP event synchronously
        let pos = currentMouseLocationQuartz
        sendMiddleMouseUp(at: pos)
        
        // Also send async as fallback (in case sync was swallowed)
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Only proceed if no new drag started
            let newGeneration = self.stateLock.withLock { self._dragGeneration }
            guard newGeneration == currentGeneration else { return }
            
            self.previousDeltaX = 0
            self.previousDeltaY = 0
            
            let pos = self.currentMouseLocationQuartz
            self.sendMiddleMouseUp(at: pos)
        }
    }

    // MARK: - Coordinate Conversion

    /// Get current mouse position in Quartz coordinates
    private var currentMouseLocationQuartz: CGPoint {
        if let event = CGEvent(source: nil) {
            return event.location
        }
        
        // Fallback: use primary screen height for multi-monitor support
        let cocoaLocation = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: cocoaLocation.x, y: screenHeight - cocoaLocation.y)
    }

    /// Get current mouse location in Quartz coordinates (public)
    static var currentMouseLocation: CGPoint {
        if let event = CGEvent(source: nil) {
            return event.location
        }
        let cocoaLocation = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
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
    
    // MARK: - Watchdog Timer
    
    /// Start the watchdog timer to detect stuck drags
    /// All watchdogTimer access is synchronized on watchdogQueue to prevent data races
    private func startWatchdog() {
        watchdogQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Cancel any existing timer first
            self.stopWatchdogLocked()
            
            let timer = DispatchSource.makeTimerSource(queue: self.watchdogQueue)
            timer.schedule(deadline: .now() + 1.0, repeating: 1.0)  // Check every second
            
            timer.setEventHandler { [weak self] in
                self?.checkForStuckDrag()
            }
            
            self.watchdogTimer = timer
            timer.resume()
        }
    }
    
    /// Stop the watchdog timer (thread-safe wrapper)
    private func stopWatchdog() {
        watchdogQueue.async { [weak self] in
            self?.stopWatchdogLocked()
        }
    }
    
    /// Stop the watchdog timer - must be called only on watchdogQueue
    private func stopWatchdogLocked() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }
    
    /// Check if the drag has become stuck (no activity for too long)
    /// Called on watchdogQueue
    private func checkForStuckDrag() {
        // CRITICAL: Atomically read both isMiddleMouseDown AND generation
        // This captures which drag session we're checking, preventing race with startDrag()
        let (isDragging, capturedGeneration): (Bool, UInt64) = stateLock.withLock {
            (_isMiddleMouseDown, _dragGeneration)
        }
        
        guard isDragging else {
            // Drag already ended, stop checking
            stopWatchdogLocked()
            return
        }
        
        activityLock.lock()
        let lastActivity = lastActivityTime
        activityLock.unlock()
        
        let timeSinceActivity = CACurrentMediaTime() - lastActivity
        
        if timeSinceActivity > stuckDragTimeout {
            // Drag appears to be stuck - auto-release
            Log.warning(
                unsafe "Stuck drag detected - no activity for \(String(format: "%.1f", timeSinceActivity))s, auto-releasing",
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
            
            // Force release the stuck drag, passing the generation we captured
            // This ensures we don't interfere with a new drag that started since our check
            forceReleaseDrag(forGeneration: capturedGeneration)
        }
    }
    
    /// Force release a stuck drag without normal cleanup flow
    /// This is called by the watchdog when a drag appears stuck
    /// Called on watchdogQueue
    /// - Parameter forGeneration: The generation that was captured when deciding to release.
    ///                           If current generation doesn't match, a new drag has started and we abort.
    private func forceReleaseDrag(forGeneration expectedGeneration: UInt64) {
        stopWatchdogLocked()
        
        // CRITICAL: Verify generation still matches before clearing state
        // This prevents race where a new drag started between checkForStuckDrag() and now
        let releasedGeneration: UInt64? = stateLock.withLock {
            guard _dragGeneration == expectedGeneration else {
                // A new drag has started - don't interfere with it!
                Log.info("forceReleaseDrag aborted - new drag session started (expected gen \(expectedGeneration), current \(_dragGeneration))", category: .gesture)
                return nil
            }
            _isMiddleMouseDown = false
            return _dragGeneration
        }
        
        // If generation didn't match, abort without sending any events
        guard let releasedGeneration = releasedGeneration else {
            return
        }
        
        // Send mouse up event synchronously to ensure it gets through
        let currentPos = currentMouseLocationQuartz
        sendMiddleMouseUp(at: currentPos)
        
        // Also try sending via async queue in case the sync one gets swallowed
        // Only proceeds if no new drag has started (same generation)
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check if a new drag started - don't interfere with it
            let currentGeneration = self.stateLock.withLock { self._dragGeneration }
            guard currentGeneration == releasedGeneration else {
                Log.info("Skipping async force-release cleanup - new drag session started", category: .gesture)
                return
            }
            
            self.previousDeltaX = 0
            self.previousDeltaY = 0
            
            let pos = self.currentMouseLocationQuartz
            self.sendMiddleMouseUp(at: pos)
        }
    }
}
