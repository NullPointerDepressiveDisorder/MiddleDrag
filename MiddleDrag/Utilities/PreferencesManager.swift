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
        // Palm rejection keys
        static let exclusionZoneEnabled = "exclusionZoneEnabled"
        static let exclusionZoneSize = "exclusionZoneSize"
        static let requireModifierKey = "requireModifierKey"
        static let modifierKeyType = "modifierKeyType"
        static let contactSizeFilterEnabled = "contactSizeFilterEnabled"
        static let maxContactSize = "maxContactSize"
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
            // Palm rejection defaults
            Keys.exclusionZoneEnabled: false,
            Keys.exclusionZoneSize: 0.15,
            Keys.requireModifierKey: false,
            Keys.modifierKeyType: ModifierKeyType.shift.rawValue,
            Keys.contactSizeFilterEnabled: false,
            Keys.maxContactSize: 1.5,
        ])
    }

    /// Load preferences from UserDefaults
    func loadPreferences() -> UserPreferences {
        let modifierKeyRaw =
            userDefaults.string(forKey: Keys.modifierKeyType) ?? ModifierKeyType.shift.rawValue
        let modifierKey = ModifierKeyType(rawValue: modifierKeyRaw) ?? .shift

        return UserPreferences(
            launchAtLogin: userDefaults.bool(forKey: Keys.launchAtLogin),
            dragSensitivity: userDefaults.double(forKey: Keys.dragSensitivity),
            tapThreshold: userDefaults.double(forKey: Keys.tapThreshold),
            smoothingFactor: userDefaults.double(forKey: Keys.smoothingFactor),
            blockSystemGestures: userDefaults.bool(forKey: Keys.blockSystemGestures),
            middleDragEnabled: userDefaults.bool(forKey: Keys.middleDragEnabled),
            exclusionZoneEnabled: userDefaults.bool(forKey: Keys.exclusionZoneEnabled),
            exclusionZoneSize: userDefaults.double(forKey: Keys.exclusionZoneSize),
            requireModifierKey: userDefaults.bool(forKey: Keys.requireModifierKey),
            modifierKeyType: modifierKey,
            contactSizeFilterEnabled: userDefaults.bool(forKey: Keys.contactSizeFilterEnabled),
            maxContactSize: userDefaults.double(forKey: Keys.maxContactSize)
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
        // Palm rejection
        userDefaults.set(preferences.exclusionZoneEnabled, forKey: Keys.exclusionZoneEnabled)
        userDefaults.set(preferences.exclusionZoneSize, forKey: Keys.exclusionZoneSize)
        userDefaults.set(preferences.requireModifierKey, forKey: Keys.requireModifierKey)
        userDefaults.set(preferences.modifierKeyType.rawValue, forKey: Keys.modifierKeyType)
        userDefaults.set(
            preferences.contactSizeFilterEnabled, forKey: Keys.contactSizeFilterEnabled)
        userDefaults.set(preferences.maxContactSize, forKey: Keys.maxContactSize)
    }
}
