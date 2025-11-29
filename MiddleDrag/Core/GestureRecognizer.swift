import Foundation
import CoreGraphics

/// Manages gesture recognition from touch input
class GestureRecognizer {
    
    // Configuration
    var configuration = GestureConfiguration()
    
    // State management
    private(set) var state: GestureState = .idle
    private var trackedFingers: [Int32: TrackedFinger] = [:]
    
    // Timing and position tracking
    private var gestureStartTime: Double = 0
    private var gestureStartPosition: MTPoint?
    private var lastGesturePosition: MTPoint?  // Track last position for frame-to-frame delta
    
    // Delegate for gesture events
    weak var delegate: GestureRecognizerDelegate?
    
    // MARK: - Public Interface
    
    /// Process new touch data
    func processTouches(_ touches: UnsafeMutableRawPointer, count: Int, timestamp: Double) {
        let touchArray = touches.bindMemory(to: MTTouch.self, capacity: count)
        // Update tracked fingers
        updateTrackedFingers(touches: touchArray, count: count, timestamp: timestamp)
        
        // Analyze gesture based on finger count
        let activeFingers = trackedFingers.values.filter { $0.isActive }
        let fingerCount = activeFingers.count
        
        if shouldProcessGesture(fingerCount: fingerCount) {
            handleMultiFingerGesture(fingers: Array(activeFingers), timestamp: timestamp)
        } else if state != .idle {
            handleGestureEnd(timestamp: timestamp)
        }
    }
    
    /// Reset gesture recognition
    func reset() {
        state = .idle
        trackedFingers.removeAll()
        gestureStartPosition = nil
        lastGesturePosition = nil
        gestureStartTime = 0
    }
    
    // MARK: - Private Methods
    
    private func shouldProcessGesture(fingerCount: Int) -> Bool {
        if configuration.requiresExactlyThreeFingers {
            return fingerCount == 3
        } else {
            return fingerCount >= 3
        }
    }
    
    private func updateTrackedFingers(touches: UnsafeMutablePointer<MTTouch>, count: Int, timestamp: Double) {
        var currentFingerIDs = Set<Int32>()
        
        for i in 0..<count {
            let touch = touches[i]
            currentFingerIDs.insert(touch.fingerID)
            
            // Update or add tracked finger
            trackedFingers[touch.fingerID] = TrackedFinger(
                id: touch.fingerID,
                position: touch.normalizedVector.position,
                velocity: touch.normalizedVector.velocity,
                pressure: touch.zTotal,
                timestamp: timestamp,
                state: touch.state
            )
        }
        
        // Remove fingers that are no longer present
        trackedFingers = trackedFingers.filter { currentFingerIDs.contains($0.key) }
    }
    
    private func handleMultiFingerGesture(fingers: [TrackedFinger], timestamp: Double) {
        let gestureData = calculateGestureData(from: fingers)
        
        switch state {
        case .idle:
            // Starting a new gesture
            startGesture(at: gestureData.centroid, timestamp: timestamp)
            
        case .possibleTap:
            // Check if we should transition to dragging
            checkTapTransition(
                currentPosition: gestureData.centroid,
                timestamp: timestamp
            )
            
        case .dragging:
            // Continue dragging - only process if we have a previous position
            if lastGesturePosition != nil {
                continueGesture(with: gestureData)
            } else {
                // First drag update - initialize last position
                lastGesturePosition = gestureData.centroid
            }
            
        case .waitingForRelease:
            // Wait for all fingers to lift
            break
        }
    }
    
    private func startGesture(at position: MTPoint, timestamp: Double) {
        state = .possibleTap
        gestureStartTime = timestamp
        gestureStartPosition = position
        lastGesturePosition = position  // Initialize last position
        
        delegate?.gestureRecognizerDidStart(self, at: position)
    }
    
    private func checkTapTransition(currentPosition: MTPoint, timestamp: Double) {
        guard let startPos = gestureStartPosition else { return }
        
        let timeSinceStart = timestamp - gestureStartTime
        let movement = startPos.distance(to: currentPosition)
        
        if movement > configuration.moveThreshold || timeSinceStart > configuration.tapThreshold {
            // Transition to drag
            state = .dragging
            // Initialize last position for drag tracking
            lastGesturePosition = currentPosition
            delegate?.gestureRecognizerDidBeginDragging(self)
        }
    }
    
    private func continueGesture(with data: GestureData) {
        // Update last position for next frame's delta calculation
        lastGesturePosition = data.centroid
        delegate?.gestureRecognizerDidUpdateDragging(self, with: data)
    }
    
    private func handleGestureEnd(timestamp: Double) {
        let timeSinceStart = timestamp - gestureStartTime
        
        switch state {
        case .possibleTap:
            if timeSinceStart < configuration.tapThreshold {
                delegate?.gestureRecognizerDidTap(self)
            }
            
        case .dragging:
            delegate?.gestureRecognizerDidEndDragging(self)
            
        default:
            break
        }
        
        reset()
    }
    
    private func calculateGestureData(from fingers: [TrackedFinger]) -> GestureData {
        let centroid = calculateCentroid(fingers: fingers)
        let averagePressure = fingers.reduce(0) { $0 + $1.pressure } / Float(fingers.count)
        let averageVelocity = calculateAverageVelocity(fingers: fingers)
        
        return GestureData(
            centroid: centroid,
            velocity: averageVelocity,
            pressure: averagePressure,
            fingerCount: fingers.count,
            startPosition: gestureStartPosition,
            lastPosition: lastGesturePosition
        )
    }
    
    private func calculateCentroid(fingers: [TrackedFinger]) -> MTPoint {
        let sumX = fingers.reduce(0) { $0 + $1.position.x }
        let sumY = fingers.reduce(0) { $0 + $1.position.y }
        return MTPoint(x: sumX / Float(fingers.count), y: sumY / Float(fingers.count))
    }
    
    private func calculateAverageVelocity(fingers: [TrackedFinger]) -> MTPoint {
        let sumVX = fingers.reduce(0) { $0 + $1.velocity.x }
        let sumVY = fingers.reduce(0) { $0 + $1.velocity.y }
        return MTPoint(x: sumVX / Float(fingers.count), y: sumVY / Float(fingers.count))
    }
}

// MARK: - Gesture Data

struct GestureData {
    let centroid: MTPoint
    let velocity: MTPoint
    let pressure: Float
    let fingerCount: Int
    let startPosition: MTPoint?
    let lastPosition: MTPoint?
    
    /// Calculate frame-to-frame delta movement
    func frameDelta(from configuration: GestureConfiguration) -> (x: CGFloat, y: CGFloat) {
        guard let last = lastPosition else { return (0, 0) }
        
        // Calculate movement since last frame
        let deltaX = CGFloat(centroid.x - last.x)
        let deltaY = CGFloat(centroid.y - last.y)
        let sensitivity = CGFloat(configuration.effectiveSensitivity(for: velocity))
        
        return (deltaX * sensitivity, deltaY * sensitivity)
    }
    
    /// Calculate total delta from start (for tap detection)
    func totalDelta(from configuration: GestureConfiguration) -> (x: CGFloat, y: CGFloat) {
        guard let start = startPosition else { return (0, 0) }
        
        let deltaX = CGFloat(centroid.x - start.x)
        let deltaY = CGFloat(centroid.y - start.y)
        let sensitivity = CGFloat(configuration.effectiveSensitivity(for: velocity))
        
        return (deltaX * sensitivity, deltaY * sensitivity)
    }
}

// MARK: - Delegate Protocol

protocol GestureRecognizerDelegate: AnyObject {
    func gestureRecognizerDidStart(_ recognizer: GestureRecognizer, at position: MTPoint)
    func gestureRecognizerDidTap(_ recognizer: GestureRecognizer)
    func gestureRecognizerDidBeginDragging(_ recognizer: GestureRecognizer)
    func gestureRecognizerDidUpdateDragging(_ recognizer: GestureRecognizer, with data: GestureData)
    func gestureRecognizerDidEndDragging(_ recognizer: GestureRecognizer)
}
