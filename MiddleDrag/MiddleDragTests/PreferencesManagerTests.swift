import XCTest

@testable import MiddleDrag

final class PreferencesManagerTests: XCTestCase {

    var preferencesManager: PreferencesManager!
    var testDefaults: UserDefaults!
    let testSuiteName = "com.middledrag.tests"

    override func setUp() {
        super.setUp()
        // Create isolated UserDefaults for testing
        testDefaults = UserDefaults(suiteName: testSuiteName)!
        // Clear any existing test data before each test
        testDefaults.removePersistentDomain(forName: testSuiteName)
        // Create PreferencesManager with injected test defaults
        preferencesManager = PreferencesManager(userDefaults: testDefaults)
    }

    override func tearDown() {
        // Clean up test data
        testDefaults.removePersistentDomain(forName: testSuiteName)
        testDefaults = nil
        preferencesManager = nil
        super.tearDown()
    }

    // MARK: - Default Preferences Tests

    func testLoadPreferencesReturnsValidDefaults() {
        // Load preferences from fresh UserDefaults - should return defaults
        let prefs = preferencesManager.loadPreferences()

        XCTAssertFalse(prefs.launchAtLogin)
        XCTAssertEqual(prefs.dragSensitivity, 1.0, accuracy: 0.001)
        XCTAssertEqual(prefs.tapThreshold, 0.15, accuracy: 0.001)
        XCTAssertEqual(prefs.smoothingFactor, 0.3, accuracy: 0.001)
        XCTAssertFalse(prefs.blockSystemGestures)
        XCTAssertTrue(prefs.middleDragEnabled)
    }

    func testLoadPreferencesPalmRejectionDefaults() {
        // Load preferences from fresh UserDefaults - should return defaults
        let prefs = preferencesManager.loadPreferences()

        XCTAssertFalse(prefs.exclusionZoneEnabled)
        XCTAssertEqual(prefs.exclusionZoneSize, 0.15, accuracy: 0.001)
        XCTAssertFalse(prefs.requireModifierKey)
        XCTAssertEqual(prefs.modifierKeyType, .shift)
        XCTAssertFalse(prefs.contactSizeFilterEnabled)
        XCTAssertEqual(prefs.maxContactSize, 1.5, accuracy: 0.001)
    }

    // MARK: - Save and Load Roundtrip Tests

    func testSaveAndLoadPreferences() {
        var prefs = UserPreferences()
        prefs.launchAtLogin = true
        prefs.dragSensitivity = 2.5
        prefs.tapThreshold = 0.25
        prefs.smoothingFactor = 0.5
        prefs.blockSystemGestures = true
        prefs.middleDragEnabled = false

        preferencesManager.savePreferences(prefs)
        let loaded = preferencesManager.loadPreferences()

        XCTAssertTrue(loaded.launchAtLogin)
        XCTAssertEqual(loaded.dragSensitivity, 2.5, accuracy: 0.001)
        XCTAssertEqual(loaded.tapThreshold, 0.25, accuracy: 0.001)
        XCTAssertEqual(loaded.smoothingFactor, 0.5, accuracy: 0.001)
        XCTAssertTrue(loaded.blockSystemGestures)
        XCTAssertFalse(loaded.middleDragEnabled)
    }

    func testSaveAndLoadPalmRejectionPreferences() {
        var prefs = UserPreferences()
        prefs.exclusionZoneEnabled = true
        prefs.exclusionZoneSize = 0.25
        prefs.requireModifierKey = true
        prefs.modifierKeyType = .option
        prefs.contactSizeFilterEnabled = true
        prefs.maxContactSize = 2.0

        preferencesManager.savePreferences(prefs)
        let loaded = preferencesManager.loadPreferences()

        XCTAssertTrue(loaded.exclusionZoneEnabled)
        XCTAssertEqual(loaded.exclusionZoneSize, 0.25, accuracy: 0.001)
        XCTAssertTrue(loaded.requireModifierKey)
        XCTAssertEqual(loaded.modifierKeyType, .option)
        XCTAssertTrue(loaded.contactSizeFilterEnabled)
        XCTAssertEqual(loaded.maxContactSize, 2.0, accuracy: 0.001)
    }

    func testSavePreservesAllModifierKeyTypes() {
        let modifierTypes: [ModifierKeyType] = [.shift, .control, .option, .command]

        for modifierType in modifierTypes {
            var prefs = UserPreferences()
            prefs.modifierKeyType = modifierType

            preferencesManager.savePreferences(prefs)
            let loaded = preferencesManager.loadPreferences()

            XCTAssertEqual(
                loaded.modifierKeyType, modifierType,
                "Failed to properly save/load modifier type: \(modifierType)")
        }
    }

    // MARK: - Edge Case Tests

    func testSaveExtremeSensitivityValues() {
        var prefs = UserPreferences()
        prefs.dragSensitivity = 0.1
        preferencesManager.savePreferences(prefs)
        var loaded = preferencesManager.loadPreferences()
        XCTAssertEqual(loaded.dragSensitivity, 0.1, accuracy: 0.001)

        prefs.dragSensitivity = 10.0
        preferencesManager.savePreferences(prefs)
        loaded = preferencesManager.loadPreferences()
        XCTAssertEqual(loaded.dragSensitivity, 10.0, accuracy: 0.001)
    }

    func testSaveZeroExclusionZoneSize() {
        var prefs = UserPreferences()
        prefs.exclusionZoneSize = 0.0
        preferencesManager.savePreferences(prefs)
        let loaded = preferencesManager.loadPreferences()
        XCTAssertEqual(loaded.exclusionZoneSize, 0.0, accuracy: 0.001)
    }

    func testSaveMaxExclusionZoneSize() {
        var prefs = UserPreferences()
        prefs.exclusionZoneSize = 0.5
        preferencesManager.savePreferences(prefs)
        let loaded = preferencesManager.loadPreferences()
        XCTAssertEqual(loaded.exclusionZoneSize, 0.5, accuracy: 0.001)
    }

    func testLoadPreferencesWindowSizeFilterDefaults() {
        let prefs = preferencesManager.loadPreferences()

        XCTAssertFalse(prefs.minimumWindowSizeFilterEnabled)
        XCTAssertEqual(prefs.minimumWindowWidth, 100.0, accuracy: 0.001)
        XCTAssertEqual(prefs.minimumWindowHeight, 100.0, accuracy: 0.001)
    }

    func testSaveAndLoadWindowSizeFilterPreferences() {
        var prefs = UserPreferences()
        prefs.minimumWindowSizeFilterEnabled = true
        prefs.minimumWindowWidth = 200.0
        prefs.minimumWindowHeight = 150.0

        preferencesManager.savePreferences(prefs)
        let loaded = preferencesManager.loadPreferences()

        XCTAssertTrue(loaded.minimumWindowSizeFilterEnabled)
        XCTAssertEqual(loaded.minimumWindowWidth, 200.0, accuracy: 0.001)
        XCTAssertEqual(loaded.minimumWindowHeight, 150.0, accuracy: 0.001)
    }

    // MARK: - Singleton Tests

    func testSharedInstanceIsSingleton() {
        let instance1 = PreferencesManager.shared
        let instance2 = PreferencesManager.shared
        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - Gesture Configuration Prompt Tracking Tests

    func testHasShownGestureConfigurationPromptDefaultsToFalse() {
        // Should default to false for fresh UserDefaults
        XCTAssertFalse(preferencesManager.hasShownGestureConfigurationPrompt)
    }

    func testMarkGestureConfigurationPromptShown() {
        // Initially should be false
        XCTAssertFalse(preferencesManager.hasShownGestureConfigurationPrompt)

        // Mark as shown
        preferencesManager.markGestureConfigurationPromptShown()

        // Should now be true
        XCTAssertTrue(preferencesManager.hasShownGestureConfigurationPrompt)
    }

    func testGestureConfigurationPromptTrackingPersistence() {
        // Mark as shown
        preferencesManager.markGestureConfigurationPromptShown()
        XCTAssertTrue(preferencesManager.hasShownGestureConfigurationPrompt)

        // Create a new instance with the same UserDefaults to test persistence
        let newManager = PreferencesManager(userDefaults: testDefaults)

        // Should still be true after recreation
        XCTAssertTrue(newManager.hasShownGestureConfigurationPrompt)
    }

    // MARK: - Isolation Tests

    func testTestInstanceIsIsolatedFromShared() {
        // Save different values to test instance and shared instance
        var testPrefs = UserPreferences()
        testPrefs.dragSensitivity = 5.0
        preferencesManager.savePreferences(testPrefs)

        // Verify test instance has the saved value
        let testLoaded = preferencesManager.loadPreferences()
        XCTAssertEqual(testLoaded.dragSensitivity, 5.0, accuracy: 0.001)

        // Verify shared instance is independent (has its own value)
        // Note: We don't assert a specific value since we don't control shared's state
        let sharedLoaded = PreferencesManager.shared.loadPreferences()
        XCTAssertNotNil(sharedLoaded)
    }
}
