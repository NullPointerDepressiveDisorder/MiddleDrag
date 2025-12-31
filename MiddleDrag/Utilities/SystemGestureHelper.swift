import Foundation

/// Helper for detecting and configuring macOS system gesture settings
/// to prevent conflicts with MiddleDrag's three-finger gestures.
class SystemGestureHelper {

    // MARK: - Constants

    /// Trackpad settings domain
    private static let trackpadDomain = "com.apple.AppleMultitouchTrackpad"

    /// Trackpad gesture setting keys
    enum TrackpadKey: String, CaseIterable {
        case threeFingerVertSwipe = "TrackpadThreeFingerVertSwipeGesture"
        case threeFingerHorizSwipe = "TrackpadThreeFingerHorizSwipeGesture"
        case fourFingerVertSwipe = "TrackpadFourFingerVertSwipeGesture"
        case fourFingerHorizSwipe = "TrackpadFourFingerHorizSwipeGesture"
    }

    /// Values for gesture settings
    enum GestureValue: Int {
        case disabled = 0
        case enabled = 2
    }

    // MARK: - Detection

    /// Returns true if 3-finger gestures are enabled that could conflict with MiddleDrag
    static func hasConflictingSettings() -> Bool {
        let threeFingerVert = getTrackpadSetting(.threeFingerVertSwipe) ?? 0
        let threeFingerHoriz = getTrackpadSetting(.threeFingerHorizSwipe) ?? 0

        // Any non-zero value means the gesture is enabled
        return threeFingerVert != 0 || threeFingerHoriz != 0
    }

    /// Returns the current value for a trackpad setting
    /// - Parameter key: The trackpad setting key to read
    /// - Returns: The integer value, or nil if not found
    static func getTrackpadSetting(_ key: TrackpadKey) -> Int? {
        let defaults = UserDefaults(suiteName: trackpadDomain)
        let value = defaults?.object(forKey: key.rawValue)

        if let intValue = value as? Int {
            return intValue
        }
        return nil
    }

    /// Returns a dictionary of all current trackpad gesture settings
    static func getAllSettings() -> [TrackpadKey: Int] {
        var settings: [TrackpadKey: Int] = [:]
        for key in TrackpadKey.allCases {
            if let value = getTrackpadSetting(key) {
                settings[key] = value
            }
        }
        return settings
    }

    // MARK: - Configuration

    /// Settings to apply for optimal MiddleDrag compatibility
    static var recommendedSettings: [(TrackpadKey, GestureValue)] {
        return [
            // Disable 3-finger gestures
            (.threeFingerVertSwipe, .disabled),
            (.threeFingerHorizSwipe, .disabled),
            // Enable 4-finger gestures instead
            (.fourFingerVertSwipe, .enabled),
            (.fourFingerHorizSwipe, .enabled),
        ]
    }

    /// Apply recommended settings (disable 3-finger, enable 4-finger gestures)
    /// - Returns: true if all settings were applied successfully
    @discardableResult
    static func applyRecommendedSettings() -> Bool {
        var success = true

        for (key, value) in recommendedSettings {
            if !writeTrackpadSetting(key, value: value.rawValue) {
                success = false
            }
        }

        if success {
            // Restart Dock to apply changes
            restartDock()
        }

        return success
    }

    /// Write a trackpad setting using defaults command
    /// - Parameters:
    ///   - key: The setting key to write
    ///   - value: The integer value to set
    /// - Returns: true if the command succeeded
    private static func writeTrackpadSetting(_ key: TrackpadKey, value: Int) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", trackpadDomain, key.rawValue, "-int", String(value)]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            Log.error("Failed to write trackpad setting: \(error)", category: .app)
            return false
        }
    }

    /// Restart the Dock process to apply trackpad setting changes
    static func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.error("Failed to restart Dock: \(error)", category: .app)
        }
    }

    // MARK: - Description

    /// Returns a human-readable description of current settings
    static func describeCurrentSettings() -> String {
        let threeVert = getTrackpadSetting(.threeFingerVertSwipe) ?? 0
        let threeHoriz = getTrackpadSetting(.threeFingerHorizSwipe) ?? 0
        let fourVert = getTrackpadSetting(.fourFingerVertSwipe) ?? 0
        let fourHoriz = getTrackpadSetting(.fourFingerHorizSwipe) ?? 0

        var lines: [String] = []

        if threeVert != 0 {
            lines.append("• 3-finger vertical swipe (Mission Control): Enabled")
        }
        if threeHoriz != 0 {
            lines.append("• 3-finger horizontal swipe (Spaces): Enabled")
        }
        if fourVert != 0 {
            lines.append("• 4-finger vertical swipe (Mission Control): Enabled")
        }
        if fourHoriz != 0 {
            lines.append("• 4-finger horizontal swipe (Spaces): Enabled")
        }

        if lines.isEmpty {
            return "All system gestures are disabled"
        }

        return lines.joined(separator: "\n")
    }
}
