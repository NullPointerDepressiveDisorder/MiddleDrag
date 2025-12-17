import Foundation

/// Manages user preferences persistence
class PreferencesManager {
    
    static let shared = PreferencesManager()
    
    private let userDefaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let dragSensitivity = "dragSensitivity"
        static let tapThreshold = "tapThreshold"
        static let smoothingFactor = "smoothingFactor"
        static let blockSystemGestures = "blockSystemGestures"
        static let middleDragEnabled = "middleDragEnabled"
    }
    
    private init() {
        registerDefaults()
    }
    
    /// Register default values
    private func registerDefaults() {
        userDefaults.register(defaults: [
            Keys.launchAtLogin: false,
            Keys.dragSensitivity: 1.0,
            Keys.tapThreshold: 0.15,
            Keys.smoothingFactor: 0.3,
            Keys.blockSystemGestures: false,
            Keys.middleDragEnabled: true
        ])
    }
    
    /// Load preferences from UserDefaults
    func loadPreferences() -> UserPreferences {
        return UserPreferences(
            launchAtLogin: userDefaults.bool(forKey: Keys.launchAtLogin),
            dragSensitivity: userDefaults.double(forKey: Keys.dragSensitivity),
            tapThreshold: userDefaults.double(forKey: Keys.tapThreshold),
            smoothingFactor: userDefaults.double(forKey: Keys.smoothingFactor),
            blockSystemGestures: userDefaults.bool(forKey: Keys.blockSystemGestures),
            middleDragEnabled: userDefaults.bool(forKey: Keys.middleDragEnabled)
        )
    }
    
    /// Save preferences to UserDefaults
    func savePreferences(_ preferences: UserPreferences) {
        userDefaults.set(preferences.launchAtLogin, forKey: Keys.launchAtLogin)
        userDefaults.set(preferences.dragSensitivity, forKey: Keys.dragSensitivity)
        userDefaults.set(preferences.tapThreshold, forKey: Keys.tapThreshold)
        userDefaults.set(preferences.smoothingFactor, forKey: Keys.smoothingFactor)
        userDefaults.set(preferences.blockSystemGestures, forKey: Keys.blockSystemGestures)
        userDefaults.set(preferences.middleDragEnabled, forKey: Keys.middleDragEnabled)
    }
}
