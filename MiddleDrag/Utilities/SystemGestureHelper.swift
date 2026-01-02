import Foundation

// MARK: - Protocols for Dependency Injection

/// Protocol for reading trackpad settings, enabling testability
protocol TrackpadSettingsProvider {
    func getSetting(forKey key: String, domain: String) -> Int?
}

/// Protocol for running shell processes, enabling testability
protocol ProcessRunner {
    func run(executable: String, arguments: [String]) -> Bool
}

// MARK: - Default Implementations

/// Default implementation using UserDefaults
class DefaultTrackpadSettingsProvider: TrackpadSettingsProvider {
    func getSetting(forKey key: String, domain: String) -> Int? {
        let defaults = UserDefaults(suiteName: domain)
        return defaults?.object(forKey: key) as? Int
    }
}

/// Default implementation using Process
class DefaultProcessRunner: ProcessRunner {
    func run(executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

/// Helper for detecting and configuring macOS system gesture settings
/// to prevent conflicts with MiddleDrag's three-finger gestures.
class SystemGestureHelper {

    // MARK: - Dependency Injection

    /// Injectable settings provider for testing
    static var settingsProvider: TrackpadSettingsProvider = DefaultTrackpadSettingsProvider()

    /// Injectable process runner for testing
    static var processRunner: ProcessRunner = DefaultProcessRunner()

    // MARK: - Constants

    /// Trackpad settings domain
    static let trackpadDomain = "com.apple.AppleMultitouchTrackpad"

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
        return settingsProvider.getSetting(forKey: key.rawValue, domain: trackpadDomain)
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
        return processRunner.run(
            executable: "/usr/bin/defaults",
            arguments: ["write", trackpadDomain, key.rawValue, "-int", String(value)]
        )
    }

    /// Restart the Dock process to apply trackpad setting changes
    static func restartDock() {
        _ = processRunner.run(executable: "/usr/bin/killall", arguments: ["Dock"])
    }

    // MARK: - Description

    /// Returns a human-readable description of only conflicting (3-finger) settings
    /// Use this when displaying which settings conflict with MiddleDrag
    static func describeConflictingSettings() -> String {
        let threeVert = getTrackpadSetting(.threeFingerVertSwipe) ?? 0
        let threeHoriz = getTrackpadSetting(.threeFingerHorizSwipe) ?? 0

        var lines: [String] = []

        if threeVert != 0 {
            lines.append("• 3-finger vertical swipe (Mission Control): Enabled")
        }
        if threeHoriz != 0 {
            lines.append("• 3-finger horizontal swipe (Spaces): Enabled")
        }

        if lines.isEmpty {
            return "No conflicting gestures detected"
        }

        return lines.joined(separator: "\n")
    }

    /// Returns a human-readable description of all current gesture settings
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
