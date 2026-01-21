import Foundation

// MARK: - Gesture State

/// Represents the current state of gesture recognition
enum GestureState: Sendable {
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
struct GestureConfiguration: Sendable {
    // Sensitivity and smoothing
    var sensitivity: Float = 1.0
    var smoothingFactor: Float = 0.3

    // Timing thresholds
    var tapThreshold: Double = 0.15  // 150ms for tap detection
    var maxTapHoldDuration: Double = 0.5  // 500ms max hold for tap (safety check)
    var moveThreshold: Float = 0.015  // Movement threshold for tap vs drag

    // Finger requirements
    @available(
        *, deprecated, message: "Always requires exactly 3 fingers now to support Mission Control"
    )
    var requiresExactlyThreeFingers: Bool = true
    var blockSystemGestures: Bool = false

    // Feature toggles
    var middleDragEnabled: Bool = true  // Allow disabling drag while keeping tap
    var tapToClickEnabled: Bool = true  // Allow disabling tap while keeping drag

    // Velocity scaling
    var enableVelocityBoost: Bool = true
    var maxVelocityBoost: Float = 2.0

    // Performance
    var minimumMovementThreshold: Float = 0.5  // pixels

    // Palm rejection - Exclusion zone
    var exclusionZoneEnabled: Bool = false
    var exclusionZoneSize: Float = 0.15  // Bottom 15% of trackpad (normalized 0-1)

    // Palm rejection - Modifier key
    var requireModifierKey: Bool = false
    var modifierKeyType: ModifierKeyType = .shift

    // Palm rejection - Contact size filter
    var contactSizeFilterEnabled: Bool = false
    var maxContactSize: Float = 1.5  // Maximum zTotal value to include (larger = palm)

    // Window size filter - ignore small windows (menus, popups)
    var minimumWindowSizeFilterEnabled: Bool = false
    var minimumWindowWidth: CGFloat = 100  // Minimum window width in pixels
    var minimumWindowHeight: CGFloat = 100  // Minimum window height in pixels

    // Desktop filter - ignore gestures when cursor is over desktop (no window)
    var ignoreDesktop: Bool = false

    // Relift during drag - allow continuing drag with 2 fingers after lifting one
    var allowReliftDuringDrag: Bool = false

    /// Calculate effective sensitivity based on velocity
    func effectiveSensitivity(for velocity: MTPoint) -> Float {
        guard enableVelocityBoost else { return sensitivity }

        let velocityMagnitude = abs(velocity.x) + abs(velocity.y)
        let velocityBoost = 1.0 + min(velocityMagnitude, maxVelocityBoost) * 0.5
        return sensitivity * velocityBoost
    }
}

// MARK: - Modifier Key Type

/// Types of modifier keys that can be required for gesture activation
enum ModifierKeyType: String, Codable, CaseIterable, Sendable {
    case shift
    case control
    case option
    case command

    var displayName: String {
        switch self {
        case .shift: return "⇧ Shift"
        case .control: return "⌃ Control"
        case .option: return "⌥ Option"
        case .command: return "⌘ Command"
        }
    }
}

// MARK: - User Preferences

/// User preferences that persist across app launches
struct UserPreferences: Codable, Sendable {
    var launchAtLogin: Bool = false
    var dragSensitivity: Double = 1.0
    var tapThreshold: Double = 0.15
    var maxTapHoldDuration: Double = 0.5  // 500ms max hold for tap
    var smoothingFactor: Double = 0.3
    @available(
        *, deprecated, message: "Always requires exactly 3 fingers now to support Mission Control"
    )
    var requiresExactlyThreeFingers: Bool = true
    var blockSystemGestures: Bool = false
    var middleDragEnabled: Bool = true  // Allow disabling drag while keeping tap
    var tapToClickEnabled: Bool = true  // Allow disabling tap while keeping drag

    // Palm rejection - Exclusion zone
    var exclusionZoneEnabled: Bool = false
    var exclusionZoneSize: Double = 0.15  // Bottom 15% of trackpad

    // Palm rejection - Modifier key
    var requireModifierKey: Bool = false
    var modifierKeyType: ModifierKeyType = .shift

    // Palm rejection - Contact size filter
    var contactSizeFilterEnabled: Bool = false
    var maxContactSize: Double = 1.5  // Maximum contact size to include

    // Window size filter - ignore small windows
    var minimumWindowSizeFilterEnabled: Bool = false
    var minimumWindowWidth: Double = 100
    var minimumWindowHeight: Double = 100

    // Desktop filter - ignore gestures when cursor is over desktop (no window)
    var ignoreDesktop: Bool = false

    // Relift during drag - allow continuing drag with 2 fingers after lifting one
    var allowReliftDuringDrag: Bool = false

    /// Convert to GestureConfiguration
    var gestureConfig: GestureConfiguration {
        return GestureConfiguration(
            sensitivity: Float(dragSensitivity),
            smoothingFactor: Float(smoothingFactor),
            tapThreshold: tapThreshold,
            maxTapHoldDuration: maxTapHoldDuration,
            requiresExactlyThreeFingers: true,  // Always true now
            blockSystemGestures: blockSystemGestures,
            middleDragEnabled: middleDragEnabled,
            tapToClickEnabled: tapToClickEnabled,
            exclusionZoneEnabled: exclusionZoneEnabled,
            exclusionZoneSize: Float(exclusionZoneSize),
            requireModifierKey: requireModifierKey,
            modifierKeyType: modifierKeyType,
            contactSizeFilterEnabled: contactSizeFilterEnabled,
            maxContactSize: Float(maxContactSize),
            minimumWindowSizeFilterEnabled: minimumWindowSizeFilterEnabled,
            minimumWindowWidth: CGFloat(minimumWindowWidth),
            minimumWindowHeight: CGFloat(minimumWindowHeight),
            ignoreDesktop: ignoreDesktop,
            allowReliftDuringDrag: allowReliftDuringDrag
        )
    }
}
