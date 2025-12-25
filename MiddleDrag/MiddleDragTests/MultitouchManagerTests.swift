import XCTest

@testable import MiddleDrag

final class MultitouchManagerTests: XCTestCase {

    // MARK: - Singleton Tests

    func testSharedInstanceIsSingleton() {
        let instance1 = MultitouchManager.shared
        let instance2 = MultitouchManager.shared
        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        let manager = MultitouchManager.shared
        XCTAssertNotNil(manager.configuration)
    }

    func testUpdateConfiguration() {
        let manager = MultitouchManager.shared
        var newConfig = GestureConfiguration()
        newConfig.sensitivity = 2.0
        newConfig.tapThreshold = 0.3
        newConfig.smoothingFactor = 0.5

        manager.updateConfiguration(newConfig)

        XCTAssertEqual(manager.configuration.sensitivity, 2.0, accuracy: 0.001)
        XCTAssertEqual(manager.configuration.tapThreshold, 0.3, accuracy: 0.001)
        XCTAssertEqual(manager.configuration.smoothingFactor, 0.5, accuracy: 0.001)
    }

    func testUpdateConfigurationPalmRejection() {
        let manager = MultitouchManager.shared
        var newConfig = GestureConfiguration()
        newConfig.exclusionZoneEnabled = true
        newConfig.exclusionZoneSize = 0.25
        newConfig.requireModifierKey = true
        newConfig.modifierKeyType = .option
        newConfig.contactSizeFilterEnabled = true
        newConfig.maxContactSize = 2.5

        manager.updateConfiguration(newConfig)

        XCTAssertTrue(manager.configuration.exclusionZoneEnabled)
        XCTAssertEqual(manager.configuration.exclusionZoneSize, 0.25, accuracy: 0.001)
        XCTAssertTrue(manager.configuration.requireModifierKey)
        XCTAssertEqual(manager.configuration.modifierKeyType, .option)
        XCTAssertTrue(manager.configuration.contactSizeFilterEnabled)
        XCTAssertEqual(manager.configuration.maxContactSize, 2.5, accuracy: 0.001)
    }

    // MARK: - State Tests

    func testInitialMonitoringStateIsFalse() {
        // Create a fresh instance for isolated testing
        // Note: shared instance may already be monitoring
        let manager = MultitouchManager.shared

        // After stop, should not be monitoring
        manager.stop()
        XCTAssertFalse(manager.isMonitoring)
    }

    func testStopWhenNotMonitoring() {
        let manager = MultitouchManager.shared
        manager.stop()

        // Calling stop again should not crash
        XCTAssertNoThrow(manager.stop())
        XCTAssertFalse(manager.isMonitoring)
    }

    // MARK: - Middle Drag Enable/Disable Tests

    func testMiddleDragEnabledConfiguration() {
        let manager = MultitouchManager.shared
        var config = GestureConfiguration()

        config.middleDragEnabled = true
        manager.updateConfiguration(config)
        XCTAssertTrue(manager.configuration.middleDragEnabled)

        config.middleDragEnabled = false
        manager.updateConfiguration(config)
        XCTAssertFalse(manager.configuration.middleDragEnabled)
    }

    // MARK: - Configuration Propagation Tests

    func testConfigurationPropagatesAllValues() {
        let manager = MultitouchManager.shared

        var config = GestureConfiguration()
        config.sensitivity = 3.0
        config.tapThreshold = 0.4
        config.moveThreshold = 0.05
        config.smoothingFactor = 0.8
        config.minimumMovementThreshold = 1.0
        config.middleDragEnabled = false
        config.exclusionZoneEnabled = true
        config.exclusionZoneSize = 0.3
        config.requireModifierKey = true
        config.modifierKeyType = .command
        config.contactSizeFilterEnabled = true
        config.maxContactSize = 3.0

        manager.updateConfiguration(config)

        // Verify all values propagated
        XCTAssertEqual(manager.configuration.sensitivity, 3.0, accuracy: 0.001)
        XCTAssertEqual(manager.configuration.tapThreshold, 0.4, accuracy: 0.001)
        XCTAssertEqual(manager.configuration.moveThreshold, 0.05, accuracy: 0.001)
        XCTAssertEqual(manager.configuration.smoothingFactor, 0.8, accuracy: 0.001)
        XCTAssertEqual(manager.configuration.minimumMovementThreshold, 1.0, accuracy: 0.001)
        XCTAssertFalse(manager.configuration.middleDragEnabled)
        XCTAssertTrue(manager.configuration.exclusionZoneEnabled)
        XCTAssertEqual(manager.configuration.exclusionZoneSize, 0.3, accuracy: 0.001)
        XCTAssertTrue(manager.configuration.requireModifierKey)
        XCTAssertEqual(manager.configuration.modifierKeyType, .command)
        XCTAssertTrue(manager.configuration.contactSizeFilterEnabled)
        XCTAssertEqual(manager.configuration.maxContactSize, 3.0, accuracy: 0.001)
    }

    // MARK: - Dependency Injection Tests (using mock)

    func testStartCallsDeviceMonitorStart() {
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })

        manager.start()

        XCTAssertTrue(mockDevice.startCalled)
        XCTAssertEqual(mockDevice.startCallCount, 1)

        manager.stop()
    }

    func testStopCallsDeviceMonitorStop() {
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })

        manager.start()
        manager.stop()

        XCTAssertTrue(mockDevice.stopCalled)
        XCTAssertEqual(mockDevice.stopCallCount, 1)
    }

    func testStartSetsMonitoringToTrue() {
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })

        XCTAssertFalse(manager.isMonitoring)

        manager.start()

        XCTAssertTrue(manager.isMonitoring)
        XCTAssertTrue(manager.isEnabled)

        manager.stop()
    }

    func testStopSetsMonitoringToFalse() {
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })

        manager.start()
        XCTAssertTrue(manager.isMonitoring)

        manager.stop()
        XCTAssertFalse(manager.isMonitoring)
        XCTAssertFalse(manager.isEnabled)
    }

    func testDoubleStartOnlyStartsOnce() {
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })

        manager.start()
        manager.start()  // Second call should be no-op

        XCTAssertEqual(mockDevice.startCallCount, 1)

        manager.stop()
    }

    func testToggleEnabledResetsState() {
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })

        manager.start()
        XCTAssertTrue(manager.isEnabled)

        manager.toggleEnabled()
        XCTAssertFalse(manager.isEnabled)

        manager.toggleEnabled()
        XCTAssertTrue(manager.isEnabled)

        manager.stop()
    }

    func testDoubleStopDoesNotCrash() {
        let manager = MultitouchManager.shared

        // Ensure clean state
        manager.stop()

        // Double stop when already stopped should not crash
        XCTAssertNoThrow(manager.stop())
        XCTAssertNoThrow(manager.stop())
    }

    // MARK: - Cleanup

    override func tearDown() {
        // Ensure we stop monitoring after each test
        MultitouchManager.shared.stop()

        // Reset configuration to defaults
        MultitouchManager.shared.updateConfiguration(GestureConfiguration())

        super.tearDown()
    }
}
