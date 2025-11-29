import Foundation

// MARK: - Touch Data Structures

/// Represents a point in 2D space
struct MTPoint {
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

/// Represents a vector with position and velocity
struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

/// Raw touch data from MultitouchSupport framework
struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var pathIndex: Int32
    var state: UInt32  // 3 = touching down, 4 = active, 5 = lifting
    var fingerID: Int32
    var handID: Int32
    var normalizedVector: MTVector
    var zTotal: Float  // Pressure/size
    var field9: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVector  // Absolute screen coordinates
    var field14: Int32
    var field15: Int32
    var zDensity: Float
}

/// Touch state enumeration
enum TouchState: UInt32 {
    case touchingDown = 3
    case active = 4
    case lifting = 5
    
    var isActive: Bool {
        return self == .active
    }
}

/// Tracked finger with enhanced metadata
struct TrackedFinger {
    let id: Int32
    var position: MTPoint
    var velocity: MTPoint
    var pressure: Float
    var timestamp: Double
    var state: UInt32
    
    var touchState: TouchState? {
        return TouchState(rawValue: state)
    }
    
    var isActive: Bool {
        return touchState?.isActive ?? false
    }
}
