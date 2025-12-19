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
}
