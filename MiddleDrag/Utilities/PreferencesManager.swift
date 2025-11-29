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
        static let requiresExactlyThreeFingers = "requiresExactlyThreeFingers"
        static let blockSystemGestures = "blockSystemGestures"
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
            Keys.requiresExactlyThreeFingers: true,
            Keys.blockSystemGestures: false
        ])
    }
    
    /// Load preferences from UserDefaults
    func loadPreferences() -> UserPreferences {
        return UserPreferences(
            launchAtLogin: userDefaults.bool(forKey: Keys.launchAtLogin),
            dragSensitivity: userDefaults.double(forKey: Keys.dragSensitivity),
            tapThreshold: userDefaults.double(forKey: Keys.tapThreshold),
            smoothingFactor: userDefaults.double(forKey: Keys.smoothingFactor),
            requiresExactlyThreeFingers: userDefaults.bool(forKey: Keys.requiresExactlyThreeFingers),
            blockSystemGestures: userDefaults.bool(forKey: Keys.blockSystemGestures)
        )
    }
    
    /// Save preferences to UserDefaults
    func savePreferences(_ preferences: UserPreferences) {
        userDefaults.set(preferences.launchAtLogin, forKey: Keys.launchAtLogin)
        userDefaults.set(preferences.dragSensitivity, forKey: Keys.dragSensitivity)
        userDefaults.set(preferences.tapThreshold, forKey: Keys.tapThreshold)
        userDefaults.set(preferences.smoothingFactor, forKey: Keys.smoothingFactor)
        userDefaults.set(preferences.requiresExactlyThreeFingers, forKey: Keys.requiresExactlyThreeFingers)
        userDefaults.set(preferences.blockSystemGestures, forKey: Keys.blockSystemGestures)
    }
}
