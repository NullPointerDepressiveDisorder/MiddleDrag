import Foundation

// MARK: - Touch Data Structures

/// Represents a point in 2D space
struct MTPoint: Sendable {
    var x: Float
    var y: Float
    
    /// Calculate distance to another point
    func distance(to other: MTPoint) -> Float {
        let dx = x - other.x
        let dy = y - other.y
        return sqrt(dx * dx + dy * dy)
    }
    
    /// Calculate midpoint between two points
    func midpoint(with other: MTPoint) -> MTPoint {
        return MTPoint(x: (x + other.x) / 2, y: (y + other.y) / 2)
    }
}

/// Represents a vector with position and velocity components
struct MTVector: Sendable {
    var position: MTPoint
    var velocity: MTPoint
}

/// Raw touch data structure from MultitouchSupport framework
/// This structure must match the memory layout expected by the framework
struct MTTouch: Sendable {
    var frame: Int32
    var timestamp: Double
    var pathIndex: Int32
    var state: UInt32           // Touch state (see TouchState enum)
    var fingerID: Int32
    var handID: Int32
    var normalizedVector: MTVector  // Position/velocity in 0-1 normalized coordinates
    var zTotal: Float           // Pressure/contact size
    var field9: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVector    // Absolute screen coordinates
    var field14: Int32
    var field15: Int32
    var zDensity: Float
}

/// Touch state values from MultitouchSupport framework
enum TouchState: UInt32, Sendable {
    case notTracking = 0
    case starting = 1
    case hovering = 2
    case touching = 3      // Finger just made contact
    case active = 4        // Finger is actively touching
    case lifting = 5       // Finger is lifting off
    case lingering = 6     // Brief state after lift
    case outOfRange = 7
    
    /// Whether this state represents a finger physically on the trackpad
    var isTouching: Bool {
        return self == .touching || self == .active
    }
    
    /// Whether this finger should be included in gesture calculations
    var shouldTrack: Bool {
        return self == .touching || self == .active
    }
}

/// Tracked finger with enhanced metadata
struct TrackedFinger: Sendable {
    let id: Int32
    var position: MTPoint
    var velocity: MTPoint
    var pressure: Float
    var timestamp: Double
    var state: UInt32
    
    var touchState: TouchState? {
        return TouchState(rawValue: state)
    }
    
    /// Whether this finger should be included in gesture calculations
    var isActive: Bool {
        return touchState?.shouldTrack ?? false
    }
}
