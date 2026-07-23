import Foundation
import AppKit
import Carbon.HIToolbox

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
public struct GestureConfiguration: Sendable {
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

    // Palm rejection - Modifier key
    var requireModifierKey: Bool = false
    var modifierKeyType: ModifierKeyType = .shift

    // Window size filter - ignore small windows (menus, popups)
    var minimumWindowSizeFilterEnabled: Bool = false
    var minimumWindowWidth: CGFloat = 100  // Minimum window width in pixels
    var minimumWindowHeight: CGFloat = 100  // Minimum window height in pixels

    // Desktop filter - ignore gestures when cursor is over desktop (no window)
    var ignoreDesktop: Bool = false

    // Relift during drag - allow continuing drag with 2 fingers after lifting one
    var allowReliftDuringDrag: Bool = false

    // Title bar passthrough - pass gesture to system when cursor is over window title bar
    // This allows macOS native three-finger drag to work for window dragging
    var passThroughTitleBar: Bool = false
    var titleBarHeight: CGFloat = 28  // Height of title bar region in pixels (accounts for toolbar)

    // Incidental contact filtering - classifier-based thumb/palm rejection
    var incidentalFilterEnabled: Bool = true

    // Mouse button behavior during a middle-drag
    // Forward live keyboard modifiers on synthetic middle-button events instead
    // of always reporting none (some apps switch behavior on modifier+middle-drag)
    var preserveModifierKeysDuringDrag: Bool = false
    // Pass a real left click (e.g. a thumb pressing the trackpad) through to the
    // target app while a middle-drag is active, instead of suppressing it
    var allowLeftClickDuringDrag: Bool = false

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

// MARK: - Hot Key Binding

/// Persistable hotkey binding (virtual key code + modifier flags)
public struct HotKeyBinding: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    
    // Human-readable strings
    var displayString: String {
        var parts: [String] = []
        if carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘ Command") }
        if carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥ Option") }
        if carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃ Control") }
        if carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧ Shift") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }
    
    private static func keyName(for keyCode: UInt32) -> String {
        let source = CGEventSource(stateID: .hidSystemState)
        if let cgEvent = CGEvent(keyboardEventSource: source, virtualKey: UInt16(keyCode), keyDown: true),
           let nsEvent = NSEvent(cgEvent: cgEvent) {
            let chars = nsEvent.charactersIgnoringModifiers?.uppercased() ?? ""
            if !chars.isEmpty && chars.rangeOfCharacter(from: .controlCharacters) == nil {
                return chars
            }
        }
    
        // Fallback for non-pritable keys
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_Space: return "Space"
        case kVK_Tab: return "Tab"
        case kVK_Return: return "Return"
        case kVK_Delete: return "Delete"
        case kVK_Escape: return "Esc"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return unsafe String(format: "0x%02X", keyCode)
        }
    }
}

// MARK: - User Preferences

/// User preferences that persist across app launches
public struct UserPreferences: Codable, Sendable {
    public var launchAtLogin: Bool = false
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

    // Palm rejection - Modifier key
    var requireModifierKey: Bool = false
    var modifierKeyType: ModifierKeyType = .shift

    // Window size filter - ignore small windows
    var minimumWindowSizeFilterEnabled: Bool = false
    var minimumWindowWidth: Double = 100
    var minimumWindowHeight: Double = 100

    // Desktop filter - ignore gestures when cursor is over desktop (no window)
    var ignoreDesktop: Bool = false

    // Relift during drag - allow continuing drag with 2 fingers after lifting one
    var allowReliftDuringDrag: Bool = false

    // Title bar passthrough - pass gesture to system when cursor is over window title bar
    var passThroughTitleBar: Bool = false
    var titleBarHeight: Double = 28  // Height of title bar region in pixels
    
    // Incidental contact filtering - classifier-based thumb/palm rejection
    var incidentalFilterEnabled: Bool = true

    // Mouse button behavior during a middle-drag
    var preserveModifierKeysDuringDrag: Bool = false
    var allowLeftClickDuringDrag: Bool = false

    // Hotkey bindings
    public var toggleHotKey: HotKeyBinding = HotKeyBinding(
        keyCode: UInt32(kVK_ANSI_E),
        carbonModifiers: UInt32(cmdKey) | UInt32(optionKey)
    )
    public var menuBarHotKey: HotKeyBinding = HotKeyBinding(
        keyCode: UInt32(kVK_ANSI_M),
        carbonModifiers: UInt32(cmdKey) | UInt32(shiftKey)
    )

    /// Convert to GestureConfiguration
    public var gestureConfig: GestureConfiguration {
        return GestureConfiguration(
            sensitivity: Float(dragSensitivity),
            smoothingFactor: Float(smoothingFactor),
            tapThreshold: tapThreshold,
            maxTapHoldDuration: maxTapHoldDuration,
            requiresExactlyThreeFingers: true,  // Always true now
            blockSystemGestures: blockSystemGestures,
            middleDragEnabled: middleDragEnabled,
            tapToClickEnabled: tapToClickEnabled,
            requireModifierKey: requireModifierKey,
            modifierKeyType: modifierKeyType,
            minimumWindowSizeFilterEnabled: minimumWindowSizeFilterEnabled,
            minimumWindowWidth: CGFloat(minimumWindowWidth),
            minimumWindowHeight: CGFloat(minimumWindowHeight),
            ignoreDesktop: ignoreDesktop,
            allowReliftDuringDrag: allowReliftDuringDrag,
            passThroughTitleBar: passThroughTitleBar,
            titleBarHeight: CGFloat(titleBarHeight),
            incidentalFilterEnabled: incidentalFilterEnabled,
            preserveModifierKeysDuringDrag: preserveModifierKeysDuringDrag,
            allowLeftClickDuringDrag: allowLeftClickDuringDrag
        )
    }
}
