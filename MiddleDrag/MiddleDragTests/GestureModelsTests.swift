import XCTest

@testable import MiddleDrag

final class GestureModelsTests: XCTestCase {

    // MARK: - GestureState Tests

    func testGestureStateIdleIsNotActive() {
        let state = GestureState.idle
        XCTAssertFalse(state.isActive)
    }

    func testGestureStatePossibleTapIsActive() {
        let state = GestureState.possibleTap
        XCTAssertTrue(state.isActive)
    }

    func testGestureStateDraggingIsActive() {
        let state = GestureState.dragging
        XCTAssertTrue(state.isActive)
    }

    func testGestureStateWaitingForReleaseIsNotActive() {
        let state = GestureState.waitingForRelease
        XCTAssertFalse(state.isActive)
    }

    // MARK: - GestureConfiguration Tests

    func testDefaultGestureConfiguration() {
        let config = GestureConfiguration()

        XCTAssertEqual(config.sensitivity, 1.0)
        XCTAssertEqual(config.smoothingFactor, 0.3)
        XCTAssertEqual(config.tapThreshold, 0.15)
        XCTAssertEqual(config.moveThreshold, 0.015)
        XCTAssertTrue(config.middleDragEnabled)
        XCTAssertFalse(config.blockSystemGestures)
    }

    func testEffectiveSensitivityWithoutVelocityBoost() {
        var config = GestureConfiguration()
        config.enableVelocityBoost = false
        config.sensitivity = 2.0

        let velocity = MTPoint(x: 10.0, y: 10.0)
        let effective = config.effectiveSensitivity(for: velocity)

        XCTAssertEqual(effective, 2.0, "Should return base sensitivity when boost disabled")
    }

    func testEffectiveSensitivityWithVelocityBoost() {
        var config = GestureConfiguration()
        config.enableVelocityBoost = true
        config.sensitivity = 1.0
        config.maxVelocityBoost = 2.0

        let velocity = MTPoint(x: 1.0, y: 1.0)
        let effective = config.effectiveSensitivity(for: velocity)

        XCTAssertGreaterThan(effective, 1.0, "Should boost sensitivity with velocity")
    }

    func testEffectiveSensitivityCapsAtMaxBoost() {
        var config = GestureConfiguration()
        config.enableVelocityBoost = true
        config.sensitivity = 1.0
        config.maxVelocityBoost = 2.0

        // Very high velocity
        let velocity = MTPoint(x: 100.0, y: 100.0)
        let effective = config.effectiveSensitivity(for: velocity)

        // maxBoost of 2.0 => boost factor = 1 + 2.0 * 0.5 = 2.0
        XCTAssertEqual(effective, 2.0, "Should cap at max velocity boost")
    }

    // MARK: - UserPreferences Tests

    func testDefaultUserPreferences() {
        let prefs = UserPreferences()

        XCTAssertFalse(prefs.launchAtLogin)
        XCTAssertEqual(prefs.dragSensitivity, 1.0)
        XCTAssertEqual(prefs.tapThreshold, 0.15)
        XCTAssertEqual(prefs.smoothingFactor, 0.3)
        XCTAssertFalse(prefs.blockSystemGestures)
        XCTAssertTrue(prefs.middleDragEnabled)
    }

    func testUserPreferencesToGestureConfig() {
        var prefs = UserPreferences()
        prefs.dragSensitivity = 2.5
        prefs.smoothingFactor = 0.5
        prefs.tapThreshold = 0.2
        prefs.blockSystemGestures = true
        prefs.middleDragEnabled = false

        let config = prefs.gestureConfig

        XCTAssertEqual(config.sensitivity, 2.5)
        XCTAssertEqual(config.smoothingFactor, 0.5)
        XCTAssertEqual(config.tapThreshold, 0.2)
        XCTAssertTrue(config.blockSystemGestures)
        XCTAssertFalse(config.middleDragEnabled)
    }

    // MARK: - Palm Rejection Configuration Tests

    func testDefaultGestureConfigurationPalmRejectionFields() {
        let config = GestureConfiguration()

        // Exclusion zone defaults
        XCTAssertFalse(config.exclusionZoneEnabled)
        XCTAssertEqual(config.exclusionZoneSize, 0.15, accuracy: 0.001)

        // Modifier key defaults
        XCTAssertFalse(config.requireModifierKey)
        XCTAssertEqual(config.modifierKeyType, .shift)

        // Contact size filter defaults
        XCTAssertFalse(config.contactSizeFilterEnabled)
        XCTAssertEqual(config.maxContactSize, 1.5, accuracy: 0.001)
    }

    func testDefaultUserPreferencesPalmRejectionFields() {
        let prefs = UserPreferences()

        // Exclusion zone defaults
        XCTAssertFalse(prefs.exclusionZoneEnabled)
        XCTAssertEqual(prefs.exclusionZoneSize, 0.15, accuracy: 0.001)

        // Modifier key defaults
        XCTAssertFalse(prefs.requireModifierKey)
        XCTAssertEqual(prefs.modifierKeyType, .shift)

        // Contact size filter defaults
        XCTAssertFalse(prefs.contactSizeFilterEnabled)
        XCTAssertEqual(prefs.maxContactSize, 1.5, accuracy: 0.001)
    }

    func testUserPreferencesToGestureConfigPalmRejectionMapping() {
        var prefs = UserPreferences()

        // Set palm rejection values
        prefs.exclusionZoneEnabled = true
        prefs.exclusionZoneSize = 0.25
        prefs.requireModifierKey = true
        prefs.modifierKeyType = .option
        prefs.contactSizeFilterEnabled = true
        prefs.maxContactSize = 2.5

        let config = prefs.gestureConfig

        // Verify mapping (Double to Float conversion)
        XCTAssertTrue(config.exclusionZoneEnabled)
        XCTAssertEqual(config.exclusionZoneSize, 0.25, accuracy: 0.001)
        XCTAssertTrue(config.requireModifierKey)
        XCTAssertEqual(config.modifierKeyType, .option)
        XCTAssertTrue(config.contactSizeFilterEnabled)
        XCTAssertEqual(config.maxContactSize, 2.5, accuracy: 0.001)
    }

    // MARK: - ModifierKeyType Tests

    func testModifierKeyTypeDisplayNames() {
        XCTAssertEqual(ModifierKeyType.shift.displayName, "⇧ Shift")
        XCTAssertEqual(ModifierKeyType.control.displayName, "⌃ Control")
        XCTAssertEqual(ModifierKeyType.option.displayName, "⌥ Option")
        XCTAssertEqual(ModifierKeyType.command.displayName, "⌘ Command")
    }

    func testModifierKeyTypeAllCases() {
        let allCases = ModifierKeyType.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.shift))
        XCTAssertTrue(allCases.contains(.control))
        XCTAssertTrue(allCases.contains(.option))
        XCTAssertTrue(allCases.contains(.command))
    }

    func testModifierKeyTypeRawValues() {
        XCTAssertEqual(ModifierKeyType.shift.rawValue, "shift")
        XCTAssertEqual(ModifierKeyType.control.rawValue, "control")
        XCTAssertEqual(ModifierKeyType.option.rawValue, "option")
        XCTAssertEqual(ModifierKeyType.command.rawValue, "command")
    }

    // MARK: - Minimum Window Size Filter Tests

    func testDefaultGestureConfigurationWindowSizeFilterFields() {
        let config = GestureConfiguration()

        XCTAssertFalse(config.minimumWindowSizeFilterEnabled)
        XCTAssertEqual(config.minimumWindowWidth, 100)
        XCTAssertEqual(config.minimumWindowHeight, 100)
    }

    func testDefaultUserPreferencesWindowSizeFilterFields() {
        let prefs = UserPreferences()

        XCTAssertFalse(prefs.minimumWindowSizeFilterEnabled)
        XCTAssertEqual(prefs.minimumWindowWidth, 100)
        XCTAssertEqual(prefs.minimumWindowHeight, 100)
    }

    func testUserPreferencesToGestureConfigWindowSizeFilterMapping() {
        var prefs = UserPreferences()

        prefs.minimumWindowSizeFilterEnabled = true
        prefs.minimumWindowWidth = 200
        prefs.minimumWindowHeight = 150

        let config = prefs.gestureConfig

        XCTAssertTrue(config.minimumWindowSizeFilterEnabled)
        XCTAssertEqual(config.minimumWindowWidth, 200)
        XCTAssertEqual(config.minimumWindowHeight, 150)
    }

    // MARK: - Allow Relift During Drag Tests

    func testDefaultGestureConfigurationReliftField() {
        let config = GestureConfiguration()
        XCTAssertFalse(config.allowReliftDuringDrag)
    }

    func testDefaultUserPreferencesReliftField() {
        let prefs = UserPreferences()
        XCTAssertFalse(prefs.allowReliftDuringDrag)
    }

    func testUserPreferencesToGestureConfigReliftMapping() {
        var prefs = UserPreferences()
        prefs.allowReliftDuringDrag = true

        let config = prefs.gestureConfig

        XCTAssertTrue(config.allowReliftDuringDrag)
    }

    // MARK: - Ignore Desktop Filter Tests

    func testDefaultGestureConfigurationIgnoreDesktopField() {
        let config = GestureConfiguration()
        XCTAssertFalse(config.ignoreDesktop)
    }

    func testDefaultUserPreferencesIgnoreDesktopField() {
        let prefs = UserPreferences()
        XCTAssertFalse(prefs.ignoreDesktop)
    }

    func testUserPreferencesToGestureConfigIgnoreDesktopMapping() {
        var prefs = UserPreferences()
        prefs.ignoreDesktop = true

        let config = prefs.gestureConfig

        XCTAssertTrue(config.ignoreDesktop)
    }
}
