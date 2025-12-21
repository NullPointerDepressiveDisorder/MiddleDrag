import XCTest

@testable import MiddleDrag

final class PreferencesManagerTests: XCTestCase {

    var preferencesManager: PreferencesManager!
    let testSuite = UserDefaults(suiteName: "com.middledrag.tests")!

    override func setUp() {
        super.setUp()
        // Clear test defaults before each test
        testSuite.removePersistentDomain(forName: "com.middledrag.tests")
    }

    override func tearDown() {
        testSuite.removePersistentDomain(forName: "com.middledrag.tests")
        super.tearDown()
    }

    // MARK: - Default Preferences Tests

    func testLoadPreferencesReturnsValidDefaults() {
        // Reset to default preferences first to ensure consistent test
        let defaultPrefs = UserPreferences()
        PreferencesManager.shared.savePreferences(defaultPrefs)
        let prefs = PreferencesManager.shared.loadPreferences()

        XCTAssertFalse(prefs.launchAtLogin)
        XCTAssertEqual(prefs.dragSensitivity, 1.0, accuracy: 0.001)
        XCTAssertEqual(prefs.tapThreshold, 0.15, accuracy: 0.001)
        XCTAssertEqual(prefs.smoothingFactor, 0.3, accuracy: 0.001)
        XCTAssertFalse(prefs.blockSystemGestures)
        XCTAssertTrue(prefs.middleDragEnabled)
    }

    func testLoadPreferencesPalmRejectionDefaults() {
        // Reset to default preferences first before checking defaults
        let defaultPrefs = UserPreferences()
        PreferencesManager.shared.savePreferences(defaultPrefs)
        let prefs = PreferencesManager.shared.loadPreferences()

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

        PreferencesManager.shared.savePreferences(prefs)
        let loaded = PreferencesManager.shared.loadPreferences()

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

        PreferencesManager.shared.savePreferences(prefs)
        let loaded = PreferencesManager.shared.loadPreferences()

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

            PreferencesManager.shared.savePreferences(prefs)
            let loaded = PreferencesManager.shared.loadPreferences()

            XCTAssertEqual(
                loaded.modifierKeyType, modifierType,
                "Failed to properly save/load modifier type: \(modifierType)")
        }
    }

    // MARK: - Edge Case Tests

    func testSaveExtremeSensitivityValues() {
        var prefs = UserPreferences()
        prefs.dragSensitivity = 0.1
        PreferencesManager.shared.savePreferences(prefs)
        var loaded = PreferencesManager.shared.loadPreferences()
        XCTAssertEqual(loaded.dragSensitivity, 0.1, accuracy: 0.001)

        prefs.dragSensitivity = 10.0
        PreferencesManager.shared.savePreferences(prefs)
        loaded = PreferencesManager.shared.loadPreferences()
        XCTAssertEqual(loaded.dragSensitivity, 10.0, accuracy: 0.001)
    }

    func testSaveZeroExclusionZoneSize() {
        var prefs = UserPreferences()
        prefs.exclusionZoneSize = 0.0
        PreferencesManager.shared.savePreferences(prefs)
        let loaded = PreferencesManager.shared.loadPreferences()
        XCTAssertEqual(loaded.exclusionZoneSize, 0.0, accuracy: 0.001)
    }

    func testSaveMaxExclusionZoneSize() {
        var prefs = UserPreferences()
        prefs.exclusionZoneSize = 0.5
        PreferencesManager.shared.savePreferences(prefs)
        let loaded = PreferencesManager.shared.loadPreferences()
        XCTAssertEqual(loaded.exclusionZoneSize, 0.5, accuracy: 0.001)
    }

    // MARK: - Singleton Tests

    func testSharedInstanceIsSingleton() {
        let instance1 = PreferencesManager.shared
        let instance2 = PreferencesManager.shared
        XCTAssertTrue(instance1 === instance2)
    }
}
