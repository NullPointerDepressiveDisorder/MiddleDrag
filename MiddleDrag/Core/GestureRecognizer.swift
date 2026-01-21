import Cocoa
import CoreGraphics
import Foundation

/// Manages gesture recognition from touch input
class GestureRecognizer {

    // MARK: - Properties

    /// Configuration for gesture detection
    var configuration = GestureConfiguration()

    /// Current gesture state
    private(set) var state: GestureState = .idle

    /// Delegate for gesture events
    weak var delegate: GestureRecognizerDelegate?

    // Position tracking
    private var lastFingerPositions: [MTPoint] = []
    private var gestureStartTime: Double = 0
    private var gestureStartPosition: MTPoint?
    private var lastCentroid: MTPoint?
    private var frameCount: Int = 0

    // Stability tracking - prevents false gesture ends during brief state transitions
    private var stableFrameCount: Int = 0

    // Cooldown after 4-finger cancellation
    // Prevents accidental gesture triggers when lifting one finger during Mission Control
    private var isInCancellationCooldown: Bool = false

    // MARK: - Public Interface

    /// Process new touch data from the multitouch device
    /// - Parameters:
    ///   - touches: Raw pointer to touch data array
    ///   - count: Number of touches in the array
    ///   - timestamp: Timestamp of the touch frame
    ///   - modifierFlags: Current modifier key flags (captured on main thread by caller)
    func processTouches(
        _ touches: UnsafeMutableRawPointer, count: Int, timestamp: Double,
        modifierFlags: CGEventFlags
    ) {
        let touchArray = unsafe touches.bindMemory(to: MTTouch.self, capacity: count)

        // Check modifier key requirement first (if enabled)
        if configuration.requireModifierKey {
            let requiredFlagPresent: Bool
            switch configuration.modifierKeyType {
            case .shift:
                requiredFlagPresent = modifierFlags.contains(.maskShift)
            case .control:
                requiredFlagPresent = modifierFlags.contains(.maskControl)
            case .option:
                requiredFlagPresent = modifierFlags.contains(.maskAlternate)
            case .command:
                requiredFlagPresent = modifierFlags.contains(.maskCommand)
            }

            if !requiredFlagPresent {
                // Required modifier not held - cancel any active gesture and return
                if state != .idle {
                    handleGestureCancel()
                }
                return
            }
        }

        // Collect only valid touching fingers (state 3 = touching down, state 4 = active)
        // Skip state 5 (lifting), 6 (lingering), 7 (gone)
        // Apply palm rejection filters
        var validFingers: [MTPoint] = []

        for i in 0..<count {
            let touch = unsafe touchArray[i]
            if touch.state == 3 || touch.state == 4 {
                let position = touch.normalizedVector.position

                // Palm rejection: Exclusion zone filter
                // Skip touches in the bottom portion of trackpad (where palm rests)
                if configuration.exclusionZoneEnabled {
                    if position.y < configuration.exclusionZoneSize {
                        continue  // Skip this touch
                    }
                }

                // Palm rejection: Contact size filter
                // Skip touches that are too large (palms have larger contact area)
                if configuration.contactSizeFilterEnabled {
                    if touch.zTotal > configuration.maxContactSize {
                        continue  // Skip this touch - likely a palm
                    }
                }

                validFingers.append(position)
            }
        }

        let fingerCount = validFingers.count

        // ALWAYS cancel on 4+ fingers regardless of configuration
        // This ensures Mission Control and other system gestures always work
        if fingerCount >= 4 {
            if state != .idle {
                handleGestureCancel()
            }
            // Enter cooldown to prevent restart when finger is briefly lifted
            isInCancellationCooldown = true
            return
        }

        // Clear cooldown when finger count drops to 0-2,
        // or when finger count is 3 and we're idle (so user can start a new gesture)
        if fingerCount <= 2 || (fingerCount == 3 && state == .idle) {
            isInCancellationCooldown = false
        }

        // Process gesture based on finger count
        // - 4+ fingers: cancelled above
        // - 3 fingers: always valid for starting/continuing gesture
        // - 2 fingers: valid for continuing drag if allowReliftDuringDrag is enabled
        // - 0-1 fingers: ends the gesture
        let canReliftDuringDrag =
            configuration.allowReliftDuringDrag
            && state == .dragging
            && fingerCount >= 2
        let isValidGesture =
            !isInCancellationCooldown
            && (fingerCount == 3 || canReliftDuringDrag)

        if isValidGesture {
            handleValidGesture(fingers: validFingers, timestamp: timestamp)
        } else if state != .idle {
            // Gesture no longer valid for current finger count
            // (needs 3 to start, or 2+ if allowReliftDuringDrag is on during drag)
            // Use stable frame count to prevent false ends during brief transitions
            stableFrameCount += 1
            if stableFrameCount >= 2 {
                handleGestureEnd(timestamp: timestamp)
            }
        }

        frameCount += 1
    }

    /// Reset gesture recognition state
    func reset() {
        state = .idle
        lastFingerPositions = []
        gestureStartPosition = nil
        lastCentroid = nil
        gestureStartTime = 0
        frameCount = 0
        stableFrameCount = 0
        isInCancellationCooldown = false  // Clear cooldown on reset
    }

    // MARK: - Private Methods

    private func handleValidGesture(fingers: [MTPoint], timestamp: Double) {
        stableFrameCount = 0  // Reset since we have valid fingers

        let centroid = calculateCentroid(fingers: fingers)

        // Check for large centroid jumps (finger added/removed causing position shift)
        if let last = lastCentroid {
            let jump = centroid.distance(to: last)
            if jump > 0.03 {
                // Large jump detected - reset reference point
                lastCentroid = centroid
                lastFingerPositions = fingers
                return
            }
        }

        switch state {
        case .idle:
            // Start new gesture
            state = .possibleTap
            gestureStartTime = timestamp
            gestureStartPosition = centroid
            lastCentroid = centroid
            lastFingerPositions = fingers
            delegate?.gestureRecognizerDidStart(self, at: centroid)

        case .possibleTap:
            // Check if we should transition to drag
            guard let startPos = gestureStartPosition else { return }
            let movement = startPos.distance(to: centroid)
            // Only transition to drag if there is actual movement
            // Resting fingers (no movement) should NOT trigger a drag
            if movement > configuration.moveThreshold {
                state = .dragging
                lastCentroid = centroid
                delegate?.gestureRecognizerDidBeginDragging(self)
            } else {
                lastCentroid = centroid
            }

        case .dragging:
            // Calculate delta from last frame
            if let last = lastCentroid {
                let deltaX = centroid.x - last.x
                let deltaY = centroid.y - last.y

                // Only process small deltas (real movement, not jumps)
                if abs(deltaX) < 0.03 && abs(deltaY) < 0.03 {
                    if abs(deltaX) > 0.0001 || abs(deltaY) > 0.0001 {
                        let gestureData = GestureData(
                            centroid: centroid,
                            velocity: MTPoint(x: 0, y: 0),
                            pressure: 0,
                            fingerCount: fingers.count,
                            startPosition: gestureStartPosition,
                            lastPosition: last
                        )
                        delegate?.gestureRecognizerDidUpdateDragging(self, with: gestureData)
                    }
                }
            }
            lastCentroid = centroid

        case .waitingForRelease:
            break
        }

        lastFingerPositions = fingers
    }

    private func handleGestureEnd(timestamp: Double) {
        let elapsed = timestamp - gestureStartTime

        switch state {
        case .possibleTap:
            // Only trigger tap if:
            // 1. Duration is less than tap threshold (quick tap)
            // 2. Duration doesn't exceed max hold duration (safety check for edge cases)
            if elapsed < configuration.tapThreshold && elapsed <= configuration.maxTapHoldDuration {
                delegate?.gestureRecognizerDidTap(self)
            } else {
                // Gesture ended without a tap - notify delegate to reset state
                delegate?.gestureRecognizerDidCancel(self)
            }
        case .dragging:
            delegate?.gestureRecognizerDidEndDragging(self)
        default:
            break
        }

        reset()
    }

    /// Cancel gesture without completing it (e.g., when 4th finger detected)
    private func handleGestureCancel() {
        switch state {
        case .possibleTap:
            // Cancel the possible tap - notify delegate so it can reset state
            delegate?.gestureRecognizerDidCancel(self)
        case .dragging:
            // Cancel the drag - don't complete it normally
            delegate?.gestureRecognizerDidCancelDragging(self)
        default:
            break
        }

        reset()
    }

    private func calculateCentroid(fingers: [MTPoint]) -> MTPoint {
        let sumX = fingers.reduce(0) { $0 + $1.x }
        let sumY = fingers.reduce(0) { $0 + $1.y }
        return MTPoint(x: sumX / Float(fingers.count), y: sumY / Float(fingers.count))
    }
}

// MARK: - Gesture Data

/// Data representing the current state of a gesture
struct GestureData: Sendable {
    let centroid: MTPoint
    let velocity: MTPoint
    let pressure: Float
    let fingerCount: Int
    let startPosition: MTPoint?
    let lastPosition: MTPoint

    /// Calculate frame-to-frame delta with sensitivity applied
    func frameDelta(from configuration: GestureConfiguration) -> (x: CGFloat, y: CGFloat) {
        let deltaX = CGFloat(centroid.x - lastPosition.x)
        let deltaY = CGFloat(centroid.y - lastPosition.y)

        // Reject large deltas (likely jumps from finger changes)
        if abs(deltaX) > 0.03 || abs(deltaY) > 0.03 {
            return (0, 0)
        }

        let sensitivity = CGFloat(configuration.effectiveSensitivity(for: velocity))
        return (deltaX * sensitivity, deltaY * sensitivity)
    }
}

// MARK: - Delegate Protocol

/// Protocol for receiving gesture recognition events
protocol GestureRecognizerDelegate: AnyObject {
    /// Called when a gesture starts (3 fingers detected)
    func gestureRecognizerDidStart(_ recognizer: GestureRecognizer, at position: MTPoint)

    /// Called when a tap gesture is recognized (quick tap)
    func gestureRecognizerDidTap(_ recognizer: GestureRecognizer)

    /// Called when dragging begins
    func gestureRecognizerDidBeginDragging(_ recognizer: GestureRecognizer)

    /// Called during drag with movement data
    func gestureRecognizerDidUpdateDragging(_ recognizer: GestureRecognizer, with data: GestureData)

    /// Called when dragging ends normally (user lifted fingers)
    func gestureRecognizerDidEndDragging(_ recognizer: GestureRecognizer)

    /// Called when gesture is cancelled from early state (e.g., possibleTap when 4th finger added)
    func gestureRecognizerDidCancel(_ recognizer: GestureRecognizer)

    /// Called when dragging is cancelled (e.g., 4th finger added for Mission Control)
    func gestureRecognizerDidCancelDragging(_ recognizer: GestureRecognizer)
}
