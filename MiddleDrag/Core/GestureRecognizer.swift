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

    private let touchClassifier = TouchClassifier()

    // Confirmation counter for 4-finger cancellation during an active drag
    private var consecutiveFourFingerFrames: Int = 0

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

        let frame = touchClassifier.classify(
            touches: touches,
            count: count,
            timestamp: timestamp,
            configuration: configuration
        )
        processClassifiedFrame(frame, timestamp: timestamp, modifierFlags: modifierFlags)
    }

    func processClassifiedFrame(
        _ frame: ClassifiedTouchFrame,
        timestamp: Double,
        modifierFlags: CGEventFlags
    ) {
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
                if state != .idle {
                    handleGestureCancel()
                }
                return
            }
        }

        let countedTouches = countableTouches(in: frame)
        let validFingers = countedTouches.map { $0.sample.position }
        let fingerCount = validFingers.count

        // ALWAYS cancel on 4+ fingers regardless of configuration
        // This ensures Mission Control and other system gestures always work
        if fingerCount >= 4 {
            // During an active drag, require a few consecutive frames before
            // cancelling so a single-frame classification flicker (a thumb
            // momentarily reading as a digit) cannot kill the drag. ~24ms is
            // imperceptible for a real four-finger swipe.
            if state == .dragging {
                consecutiveFourFingerFrames += 1
                guard consecutiveFourFingerFrames >= 3 else { return }
            }
            if state != .idle {
                handleGestureCancel()
            }
            // Enter cooldown to prevent restart when finger is briefly lifted
            isInCancellationCooldown = true
            return
        }
        consecutiveFourFingerFrames = 0

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

    /// The contacts that count toward the finger total for gesture decisions.
    ///
    /// Normally that is every digit-role and uncertain-role contact, but a thumb
    /// resting, landing to click, or adjusting position must not read as a fourth
    /// finger. On real hardware a thumb's size/shape flags it `uncertain` while a
    /// fingertip never is (size evidence 0.000 at p95), so uncertain-role extras
    /// beyond the three established digits are always forgiven. During an active
    /// drag even digit-role extras are forgiven while stationary — the classifier
    /// needs a few hundred milliseconds of differential motion before it can mark
    /// a newcomer incidental. A genuine system gesture still cancels: its four
    /// contacts are digit-role fingertips sweeping together.
    private func countableTouches(in frame: ClassifiedTouchFrame) -> [ClassifiedTouch] {
        let digits = frame.digitTouches
        guard digits.count > 3 else { return digits }

        // Digit-role contacts first, then older before younger, so the ambiguous
        // newcomers (or a long-resting thumb) end up in the extras.
        let ranked = digits.sorted { first, second in
            let firstIsDigit = first.role == .digit
            let secondIsDigit = second.role == .digit
            if firstIsDigit != secondIsDigit { return firstIsDigit }
            return first.features.age > second.features.age
        }
        let core = Array(ranked.prefix(3))
        let extras = ranked.dropFirst(3)

        let hasGenuineFourthDigit = extras.contains { extra in
            extra.role == .digit && (state != .dragging || extra.features.speed >= 0.25)
        }
        return hasGenuineFourthDigit ? digits : core
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
        consecutiveFourFingerFrames = 0
        touchClassifier.reset()
    }

    // MARK: - Private Methods

    private func handleValidGesture(fingers: [MTPoint], timestamp: Double) {
        stableFrameCount = 0

        let centroid = calculateCentroid(fingers: fingers)

        // Filter large centroid jumps from finger add/remove (not fast movement)
        if let last = lastCentroid {
            let jump = centroid.distance(to: last)
            if jump > 0.15 {
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
            if let last = lastCentroid {
                let deltaX = centroid.x - last.x
                let deltaY = centroid.y - last.y

                // Filter jumps from finger changes
                let maxDelta: Float = 0.15
                if abs(deltaX) < maxDelta && abs(deltaY) < maxDelta {
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

        // Filter jumps from finger changes
        if abs(deltaX) > 0.15 || abs(deltaY) > 0.15 {
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
