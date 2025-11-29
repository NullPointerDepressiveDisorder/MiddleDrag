import Foundation

// MARK: - Gesture State

/// Represents the current state of gesture recognition
enum GestureState {
    case idle
    case possibleTap
    case dragging
    case waitingForRelease
    
    var isActive: Bool {
        switch self {
        case .dragging, .possibleTap:
            return true
        case .idle, .waitingForRelease:
            return false
        }
    }
}

// MARK: - Configuration

/// Configuration for gesture detection and mouse behavior
struct GestureConfiguration {
    // Sensitivity and smoothing
    var sensitivity: Float = 1.0
    var smoothingFactor: Float = 0.3
    
    // Timing thresholds
    var tapThreshold: Double = 0.15  // 150ms for tap detection
    var moveThreshold: Float = 0.015  // Movement threshold for tap vs drag
    
    // Finger requirements
    var requiresExactlyThreeFingers: Bool = true
    var blockSystemGestures: Bool = false
    
    // Velocity scaling
    var enableVelocityBoost: Bool = true
    var maxVelocityBoost: Float = 2.0
    
    // Performance
    var minimumMovementThreshold: Float = 0.5  // pixels
    
    /// Calculate effective sensitivity based on velocity
    func effectiveSensitivity(for velocity: MTPoint) -> Float {
        guard enableVelocityBoost else { return sensitivity }
        
        let velocityMagnitude = abs(velocity.x) + abs(velocity.y)
        let velocityBoost = 1.0 + min(velocityMagnitude, maxVelocityBoost) * 0.5
        return sensitivity * velocityBoost
    }
}

// MARK: - User Preferences

/// User preferences that persist across app launches
struct UserPreferences: Codable {
    var launchAtLogin: Bool = false
    var dragSensitivity: Double = 1.0
    var tapThreshold: Double = 0.15
    var smoothingFactor: Double = 0.3
    var requiresExactlyThreeFingers: Bool = true
    var blockSystemGestures: Bool = false
    
    /// Convert to GestureConfiguration
    var gestureConfig: GestureConfiguration {
        return GestureConfiguration(
            sensitivity: Float(dragSensitivity),
            smoothingFactor: Float(smoothingFactor),
            tapThreshold: tapThreshold,
            requiresExactlyThreeFingers: requiresExactlyThreeFingers,
            blockSystemGestures: blockSystemGestures
        )
    }
}
