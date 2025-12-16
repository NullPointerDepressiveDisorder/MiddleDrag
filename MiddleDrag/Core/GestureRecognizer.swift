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

    // MARK: - Public Interface

    /// Process new touch data from the multitouch device
    /// - Parameters:
    ///   - touches: Raw pointer to touch data array
    ///   - count: Number of touches in the array
    ///   - timestamp: Timestamp of the touch frame
    func processTouches(_ touches: UnsafeMutableRawPointer, count: Int, timestamp: Double) {
        let touchArray = touches.bindMemory(to: MTTouch.self, capacity: count)

        // Collect only valid touching fingers (state 3 = touching down, state 4 = active)
        // Skip state 5 (lifting), 6 (lingering), 7 (gone)
        var validFingers: [MTPoint] = []

        for i in 0..<count {
            let touch = touchArray[i]
            if touch.state == 3 || touch.state == 4 {
                validFingers.append(touch.normalizedVector.position)
            }
        }

        let fingerCount = validFingers.count

        // When requiresExactlyThreeFingers is enabled (default):
        // - 4+ fingers = immediate cancel (user doing Mission Control)
        // - 3 fingers = process gesture
        // - 0-2 fingers = end gesture normally (user lifted fingers)
        if configuration.requiresExactlyThreeFingers && fingerCount >= 4 {
            // IMMEDIATELY cancel any in-progress gesture when 4+ fingers detected
            // This allows Mission Control to work without interference
            if state != .idle {
                handleGestureCancel()
            }
            return
        }

        // Determine if we should process this as a three-finger gesture
        let isValidThreeFingerGesture: Bool
        if configuration.requiresExactlyThreeFingers {
            isValidThreeFingerGesture = fingerCount == 3
        } else {
            isValidThreeFingerGesture = fingerCount >= 3
        }

        if isValidThreeFingerGesture {
            handleThreeFingerGesture(fingers: validFingers, timestamp: timestamp)
        } else if state != .idle {
            // End gesture normally when finger count drops below 3
            // (user lifted fingers to end the gesture)
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
    }

    // MARK: - Private Methods

    private func handleThreeFingerGesture(fingers: [MTPoint], timestamp: Double) {
        stableFrameCount = 0  // Reset since we have 3 fingers

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
            let elapsed = timestamp - gestureStartTime

            if movement > configuration.moveThreshold || elapsed > configuration.tapThreshold {
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
            if elapsed < configuration.tapThreshold {
                delegate?.gestureRecognizerDidTap(self)
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
struct GestureData {
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

    /// Called when a tap gesture is recognized
    func gestureRecognizerDidTap(_ recognizer: GestureRecognizer)

    /// Called when dragging begins
    func gestureRecognizerDidBeginDragging(_ recognizer: GestureRecognizer)

    /// Called during drag with movement data
    func gestureRecognizerDidUpdateDragging(_ recognizer: GestureRecognizer, with data: GestureData)

    /// Called when dragging ends normally (user lifted fingers)
    func gestureRecognizerDidEndDragging(_ recognizer: GestureRecognizer)

    /// Called when dragging is cancelled (e.g., 4th finger added for Mission Control)
    func gestureRecognizerDidCancelDragging(_ recognizer: GestureRecognizer)
}
