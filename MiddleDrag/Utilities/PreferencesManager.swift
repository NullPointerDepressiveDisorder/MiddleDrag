import Foundation

/// Manages user preferences persistence
class PreferencesManager {

    static let shared = PreferencesManager()

    private let userDefaults: UserDefaults

    // Keys for UserDefaults
    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let dragSensitivity = "dragSensitivity"
        static let tapThreshold = "tapThreshold"
        static let smoothingFactor = "smoothingFactor"
        static let blockSystemGestures = "blockSystemGestures"
        static let middleDragEnabled = "middleDragEnabled"
        static let tapToClickEnabled = "tapToClickEnabled"
        // Palm rejection keys
        static let exclusionZoneEnabled = "exclusionZoneEnabled"
        static let exclusionZoneSize = "exclusionZoneSize"
        static let requireModifierKey = "requireModifierKey"
        static let modifierKeyType = "modifierKeyType"
        static let contactSizeFilterEnabled = "contactSizeFilterEnabled"
        static let maxContactSize = "maxContactSize"
        // Window size filter keys
        static let minimumWindowSizeFilterEnabled = "minimumWindowSizeFilterEnabled"
        static let minimumWindowWidth = "minimumWindowWidth"
        static let minimumWindowHeight = "minimumWindowHeight"
        // Gesture configuration prompt tracking
        static let hasShownGestureConfigurationPrompt = "hasShownGestureConfigurationPrompt"
    }

    /// Production initializer using UserDefaults.standard
    private init() {
        self.userDefaults = UserDefaults.standard
        registerDefaults()
    }

    /// Test initializer with dependency injection for isolated testing
    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
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
            Keys.middleDragEnabled: true,
            Keys.tapToClickEnabled: true,
            // Palm rejection defaults
            Keys.exclusionZoneEnabled: false,
            Keys.exclusionZoneSize: 0.15,
            Keys.requireModifierKey: false,
            Keys.modifierKeyType: ModifierKeyType.shift.rawValue,
            Keys.contactSizeFilterEnabled: false,
            Keys.maxContactSize: 1.5,
            // Window size filter defaults
            Keys.minimumWindowSizeFilterEnabled: false,
            Keys.minimumWindowWidth: 100.0,
            Keys.minimumWindowHeight: 100.0,
        ])
    }

    /// Load preferences from UserDefaults
    func loadPreferences() -> UserPreferences {
        let modifierKeyRaw =
            userDefaults.string(forKey: Keys.modifierKeyType) ?? ModifierKeyType.shift.rawValue
        let modifierKey = ModifierKeyType(rawValue: modifierKeyRaw) ?? .shift

        // Create with defaults, then override with saved values
        // This handles new keys that don't exist in older UserDefaults
        var prefs = UserPreferences()

        prefs.launchAtLogin = userDefaults.bool(forKey: Keys.launchAtLogin)
        prefs.dragSensitivity = userDefaults.double(forKey: Keys.dragSensitivity)
        prefs.tapThreshold = userDefaults.double(forKey: Keys.tapThreshold)
        prefs.smoothingFactor = userDefaults.double(forKey: Keys.smoothingFactor)
        prefs.blockSystemGestures = userDefaults.bool(forKey: Keys.blockSystemGestures)
        prefs.middleDragEnabled = userDefaults.bool(forKey: Keys.middleDragEnabled)
        prefs.tapToClickEnabled = userDefaults.bool(forKey: Keys.tapToClickEnabled)
        prefs.exclusionZoneEnabled = userDefaults.bool(forKey: Keys.exclusionZoneEnabled)
        prefs.exclusionZoneSize = userDefaults.double(forKey: Keys.exclusionZoneSize)
        prefs.requireModifierKey = userDefaults.bool(forKey: Keys.requireModifierKey)
        prefs.modifierKeyType = modifierKey
        prefs.contactSizeFilterEnabled = userDefaults.bool(forKey: Keys.contactSizeFilterEnabled)
        prefs.maxContactSize = userDefaults.double(forKey: Keys.maxContactSize)
        prefs.minimumWindowSizeFilterEnabled = userDefaults.bool(
            forKey: Keys.minimumWindowSizeFilterEnabled)
        prefs.minimumWindowWidth = userDefaults.double(forKey: Keys.minimumWindowWidth)
        prefs.minimumWindowHeight = userDefaults.double(forKey: Keys.minimumWindowHeight)

        return prefs
    }

    /// Save preferences to UserDefaults
    func savePreferences(_ preferences: UserPreferences) {
        userDefaults.set(preferences.launchAtLogin, forKey: Keys.launchAtLogin)
        userDefaults.set(preferences.dragSensitivity, forKey: Keys.dragSensitivity)
        userDefaults.set(preferences.tapThreshold, forKey: Keys.tapThreshold)
        userDefaults.set(preferences.smoothingFactor, forKey: Keys.smoothingFactor)
        userDefaults.set(preferences.blockSystemGestures, forKey: Keys.blockSystemGestures)
        userDefaults.set(preferences.middleDragEnabled, forKey: Keys.middleDragEnabled)
        userDefaults.set(preferences.tapToClickEnabled, forKey: Keys.tapToClickEnabled)
        // Palm rejection
        userDefaults.set(preferences.exclusionZoneEnabled, forKey: Keys.exclusionZoneEnabled)
        userDefaults.set(preferences.exclusionZoneSize, forKey: Keys.exclusionZoneSize)
        userDefaults.set(preferences.requireModifierKey, forKey: Keys.requireModifierKey)
        userDefaults.set(preferences.modifierKeyType.rawValue, forKey: Keys.modifierKeyType)
        userDefaults.set(
            preferences.contactSizeFilterEnabled, forKey: Keys.contactSizeFilterEnabled)
        userDefaults.set(preferences.maxContactSize, forKey: Keys.maxContactSize)
        // Window size filter
        userDefaults.set(
            preferences.minimumWindowSizeFilterEnabled, forKey: Keys.minimumWindowSizeFilterEnabled)
        userDefaults.set(preferences.minimumWindowWidth, forKey: Keys.minimumWindowWidth)
        userDefaults.set(preferences.minimumWindowHeight, forKey: Keys.minimumWindowHeight)
    }

    // MARK: - Gesture Configuration Prompt Tracking

    /// Check if the gesture configuration prompt has been shown before
    var hasShownGestureConfigurationPrompt: Bool {
        return userDefaults.bool(forKey: Keys.hasShownGestureConfigurationPrompt)
    }

    /// Mark that the gesture configuration prompt has been shown
    func markGestureConfigurationPromptShown() {
        userDefaults.set(true, forKey: Keys.hasShownGestureConfigurationPrompt)
    }
}
