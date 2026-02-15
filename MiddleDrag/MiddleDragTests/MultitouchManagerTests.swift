import XCTest

@testable import MiddleDragCore

final class MultitouchManagerTests: XCTestCase {

    private func requireCGEventTestsEnabled() throws {
        if ProcessInfo.processInfo.environment["RUN_CGEVENT_TESTS"] == "0" {
            throw XCTSkip("Skipping CGEvent-based tests; set RUN_CGEVENT_TESTS=1 to run.")
        }
    }

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
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()

        unsafe XCTAssertTrue(mockDevice.startCalled)
        unsafe XCTAssertEqual(mockDevice.startCallCount, 1)

        manager.stop()
    }

    func testStopCallsDeviceMonitorStop() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        manager.stop()

        unsafe XCTAssertTrue(mockDevice.stopCalled)
        unsafe XCTAssertEqual(mockDevice.stopCallCount, 1)
    }

    func testStartSetsMonitoringToTrue() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        XCTAssertFalse(manager.isMonitoring)

        manager.start()

        XCTAssertTrue(manager.isMonitoring)
        XCTAssertTrue(manager.isEnabled)

        manager.stop()
    }

    func testStartGracefullyHandlesMissingHardware() {
        let mockDevice = unsafe MockDeviceMonitor()
        unsafe mockDevice.startShouldSucceed = false
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()

        XCTAssertFalse(manager.isMonitoring)
        XCTAssertFalse(manager.isEnabled)
        // When no hardware is found, manager should begin polling for late-connecting devices
        XCTAssertTrue(manager.isPollingForDevices)

        manager.stop()  // Clean up polling timer
    }

    func testRestartStopsWhenHardwareUnavailable() {
        var factories: [Bool] = [true, false]
        let manager = MultitouchManager(
            deviceProviderFactory: {
                let monitor = unsafe MockDeviceMonitor()
                unsafe monitor.startShouldSucceed = factories.isEmpty ? true : factories.removeFirst()
                return unsafe monitor
            },
            eventTapSetup: { true }
        )

        manager.start()
        XCTAssertTrue(manager.isMonitoring)

        manager.restart()

        // Wait for async restart to complete
        let expectation = XCTestExpectation(description: "Restart complete")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MultitouchManager.restartCleanupDelay + 0.05
        ) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(manager.isMonitoring)
        XCTAssertFalse(manager.isEnabled)
        // When restart fails to find hardware, manager should poll for device connections
        XCTAssertTrue(manager.isPollingForDevices)

        manager.stop()  // Clean up polling timer
    }

    func testStopSetsMonitoringToFalse() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        XCTAssertTrue(manager.isMonitoring)

        manager.stop()
        XCTAssertFalse(manager.isMonitoring)
        XCTAssertFalse(manager.isEnabled)
    }

    func testDoubleStartOnlyStartsOnce() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        manager.start()  // Second call should be no-op

        unsafe XCTAssertEqual(mockDevice.startCallCount, 1)

        manager.stop()
    }

    func testToggleEnabledResetsState() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

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

    func testRapidRestartDebouncesCalls() {
        // Use a counter to track how many times the device provider factory is called.
        // If debouncing works, we should see fewer creations than restart calls.
        var creationCount = 0
        let manager = MultitouchManager(
            deviceProviderFactory: {
                creationCount += 1
                return unsafe MockDeviceMonitor()
            },
            eventTapSetup: { true }
        )

        manager.start()
        XCTAssertEqual(creationCount, 1)  // Initial start

        // Call restart multiple times rapidly
        for _ in 0..<5 {
            manager.restart()
        }

        // Wait for possible async execution (restart delay is 0.1s)
        let expectation = XCTestExpectation(description: "Debounced restart complete")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MultitouchManager.restartCleanupDelay + 0.1
        ) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // We expect:
        // 1 initial creation
        // + 1 creation for the final coalesced restart
        // = 2 total creations
        // If race condition existed (no debouncing), this would likely be > 2
        XCTAssertEqual(creationCount, 2, "Should have coalesced multiple restarts")

        manager.stop()
    }

    func testStopDuringRestartDelayStopsManager() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        XCTAssertTrue(manager.isMonitoring)

        // Trigger restart - this enters the async delay window
        // internalStop is called, so isMonitoring becomes false temporarily
        manager.restart()
        XCTAssertFalse(manager.isMonitoring)

        // Call stop() immediately (during the delay)
        // This MUST prevent the restart from happening
        manager.stop()

        // Wait for the restart delay to elapse
        let expectation = XCTestExpectation(description: "Wait for restart delay")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MultitouchManager.restartCleanupDelay + 0.1
        ) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Verify manager is still stopped
        XCTAssertFalse(manager.isMonitoring, "Manager should remain stopped")
        XCTAssertFalse(manager.isEnabled, "Manager should be disabled")
    }

    // MARK: - Device Polling Tests

    func testStartBeginsPollingWhenNoDeviceFound() {
        let mockDevice = unsafe MockDeviceMonitor()
        unsafe mockDevice.startShouldSucceed = false
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()

        XCTAssertFalse(manager.isMonitoring)
        XCTAssertTrue(manager.isPollingForDevices, "Should poll when no device at launch")

        manager.stop()
    }

    func testStopCancelsDevicePolling() {
        let mockDevice = unsafe MockDeviceMonitor()
        unsafe mockDevice.startShouldSucceed = false
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        XCTAssertTrue(manager.isPollingForDevices)

        manager.stop()
        XCTAssertFalse(manager.isPollingForDevices, "Polling should stop on explicit stop()")
    }

    func testDoubleStartDoesNotDoublePoll() {
        let mockDevice = unsafe MockDeviceMonitor()
        unsafe mockDevice.startShouldSucceed = false
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        XCTAssertTrue(manager.isPollingForDevices)

        // Second start should be a no-op since we're already polling
        manager.start()
        XCTAssertTrue(manager.isPollingForDevices)

        manager.stop()
    }

    func testToggleEnabledAttemptsStartWhenNotMonitoring() {
        var shouldSucceed = false
        let manager = MultitouchManager(
            deviceProviderFactory: {
                let monitor = unsafe MockDeviceMonitor()
                unsafe monitor.startShouldSucceed = shouldSucceed
                return unsafe monitor
            },
            eventTapSetup: { true }
        )

        // Initial start fails → starts polling
        manager.start()
        XCTAssertFalse(manager.isMonitoring)
        XCTAssertTrue(manager.isPollingForDevices)
        manager.stop()
        XCTAssertFalse(manager.isPollingForDevices)

        // Now make device available and toggle enabled
        shouldSucceed = true
        manager.toggleEnabled()

        XCTAssertTrue(manager.isMonitoring, "toggleEnabled should start monitoring if device now available")
        XCTAssertTrue(manager.isEnabled)

        manager.stop()
    }

    func testToggleEnabledWhilePollingStopsPolling() {
        let mockDevice = unsafe MockDeviceMonitor()
        unsafe mockDevice.startShouldSucceed = false
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        XCTAssertTrue(manager.isPollingForDevices)

        // Toggling while polling should stop polling (user says "stop trying")
        manager.toggleEnabled()
        XCTAssertFalse(manager.isPollingForDevices, "Toggle while polling should stop polling")
        XCTAssertFalse(manager.isEnabled)
        XCTAssertFalse(manager.isMonitoring)
    }

    func testPollingConstants() {
        // Verify backoff and timeout constants are sensible
        XCTAssertEqual(MultitouchManager.devicePollingInterval, 3.0)
        XCTAssertEqual(MultitouchManager.maxDevicePollingInterval, 30.0)
        XCTAssertEqual(MultitouchManager.maxPollingDuration, 300.0)
        XCTAssertGreaterThan(
            MultitouchManager.maxDevicePollingInterval,
            MultitouchManager.devicePollingInterval,
            "Max interval must be greater than initial interval for backoff to work")
    }

    // MARK: - GestureRecognizerDelegate State Transition Tests

    func testGestureRecognizerDidStartSetsThreeFingerGestureState() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        manager.start()
        XCTAssertFalse(manager.isInThreeFingerGesture)

        // Trigger the delegate callback
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        // State updates are dispatched async to main thread
        let expectation = XCTestExpectation(description: "State updated")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isInThreeFingerGesture)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        manager.stop()
    }

    func testGestureRecognizerDidTapResetsGestureState() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        manager.start()

        // First enter gesture state
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        let startExpectation = XCTestExpectation(description: "Start state updated")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isInThreeFingerGesture)
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        // Then trigger tap
        manager.gestureRecognizerDidTap(recognizer)

        let tapExpectation = XCTestExpectation(description: "Tap state updated")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isInThreeFingerGesture)
            tapExpectation.fulfill()
        }
        wait(for: [tapExpectation], timeout: 1.0)

        manager.stop()
    }

    func testGestureRecognizerDidTapWithTapToClickEnabled() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Enable tap to click
        var config = GestureConfiguration()
        config.tapToClickEnabled = true
        manager.updateConfiguration(config)

        manager.start()

        // Enter gesture state
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        // Wait for state
        let startExpectation = XCTestExpectation(description: "Start state updated")
        DispatchQueue.main.async {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        // Trigger tap
        manager.gestureRecognizerDidTap(recognizer)

        // Verify state is reset AND click happened (indirectly via state reset)
        let tapExpectation = XCTestExpectation(description: "Tap handled, state reset")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isInThreeFingerGesture)
            tapExpectation.fulfill()
        }
        wait(for: [tapExpectation], timeout: 1.0)

        manager.stop()
    }

    func testGestureRecognizerDidTapWithTapToClickDisabled() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Disable tap to click
        var config = GestureConfiguration()
        config.tapToClickEnabled = false
        manager.updateConfiguration(config)

        manager.start()

        // Enter gesture state
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        // Wait for state
        let startExpectation = XCTestExpectation(description: "Start state updated")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isInThreeFingerGesture)
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        // Trigger tap
        manager.gestureRecognizerDidTap(recognizer)

        // Verify state is still reset (it must reset state regardless of click)
        let tapExpectation = XCTestExpectation(description: "State reset even when disabled")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isInThreeFingerGesture)
            tapExpectation.fulfill()
        }
        wait(for: [tapExpectation], timeout: 1.0)

        manager.stop()
    }

    func testGestureRecognizerDidBeginDraggingSetsActivelyDragging() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Enable middle drag so the state will be set
        var config = GestureConfiguration()
        config.middleDragEnabled = true
        manager.updateConfiguration(config)

        manager.start()
        XCTAssertFalse(manager.isActivelyDragging)

        // Trigger begin dragging
        manager.gestureRecognizerDidBeginDragging(recognizer)

        let expectation = XCTestExpectation(description: "Dragging state updated")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isActivelyDragging)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        manager.stop()
    }

    func testGestureRecognizerDidEndDraggingResetsAllStates() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        manager.start()

        // Enter gesture and dragging state
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))
        manager.gestureRecognizerDidBeginDragging(recognizer)

        let setupExpectation = XCTestExpectation(description: "Setup state")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isInThreeFingerGesture)
            XCTAssertTrue(manager.isActivelyDragging)
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 1.0)

        // End dragging
        manager.gestureRecognizerDidEndDragging(recognizer)

        let endExpectation = XCTestExpectation(description: "End state updated")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isActivelyDragging)
            XCTAssertFalse(manager.isInThreeFingerGesture)
            endExpectation.fulfill()
        }
        wait(for: [endExpectation], timeout: 1.0)

        manager.stop()
    }

    func testGestureRecognizerDidCancelResetsGestureState() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        manager.start()

        // Enter gesture state
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        let startExpectation = XCTestExpectation(description: "Start state")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isInThreeFingerGesture)
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        // Cancel gesture
        manager.gestureRecognizerDidCancel(recognizer)

        let cancelExpectation = XCTestExpectation(description: "Cancel state updated")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isInThreeFingerGesture)
            cancelExpectation.fulfill()
        }
        wait(for: [cancelExpectation], timeout: 1.0)

        manager.stop()
    }

    func testGestureRecognizerDidCancelDraggingResetsAllStates() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        manager.start()

        // Enter gesture and dragging state
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))
        manager.gestureRecognizerDidBeginDragging(recognizer)

        let setupExpectation = XCTestExpectation(description: "Setup state")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isInThreeFingerGesture)
            XCTAssertTrue(manager.isActivelyDragging)
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 1.0)

        // Cancel dragging (e.g., 4th finger added)
        manager.gestureRecognizerDidCancelDragging(recognizer)

        let cancelExpectation = XCTestExpectation(description: "Cancel dragging state")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isActivelyDragging)
            XCTAssertFalse(manager.isInThreeFingerGesture)
            cancelExpectation.fulfill()
        }
        wait(for: [cancelExpectation], timeout: 1.0)

        manager.stop()
    }

    func testGestureRecognizerDidUpdateDraggingWithMiddleDragDisabled() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Disable middle drag
        var config = GestureConfiguration()
        config.middleDragEnabled = false
        manager.updateConfiguration(config)

        manager.start()
        manager.gestureRecognizerDidBeginDragging(recognizer)

        // Update dragging should not crash when middle drag is disabled
        let gestureData = GestureData(
            centroid: MTPoint(x: 0.5, y: 0.5),
            velocity: MTPoint(x: 0.1, y: 0.1),
            pressure: 1.0,
            fingerCount: 3,
            startPosition: MTPoint(x: 0.4, y: 0.4),
            lastPosition: MTPoint(x: 0.45, y: 0.45)
        )

        XCTAssertNoThrow(manager.gestureRecognizerDidUpdateDragging(recognizer, with: gestureData))

        manager.stop()
    }

    func testGestureRecognizerDidUpdateDraggingWithZeroDelta() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        var config = GestureConfiguration()
        config.middleDragEnabled = true
        manager.updateConfiguration(config)

        manager.start()
        manager.gestureRecognizerDidBeginDragging(recognizer)

        // Update with zero delta should not crash
        let gestureData = GestureData(
            centroid: MTPoint(x: 0.5, y: 0.5),
            velocity: MTPoint(x: 0.0, y: 0.0),
            pressure: 1.0,
            fingerCount: 3,
            startPosition: MTPoint(x: 0.5, y: 0.5),
            lastPosition: MTPoint(x: 0.5, y: 0.5)
        )

        XCTAssertNoThrow(manager.gestureRecognizerDidUpdateDragging(recognizer, with: gestureData))

        manager.stop()
    }

    func testGestureRecognizerDidBeginDraggingWithMiddleDragDisabled() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Disable middle drag
        var config = GestureConfiguration()
        config.middleDragEnabled = false
        manager.updateConfiguration(config)

        manager.start()

        // Begin dragging should NOT update isActivelyDragging state
        // when middleDragEnabled is false (the drag is never actually started)
        manager.gestureRecognizerDidBeginDragging(recognizer)

        let expectation = XCTestExpectation(description: "State should remain false")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isActivelyDragging)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        manager.stop()
    }

    // MARK: - DeviceMonitorDelegate Tests

    func testDeviceMonitorDelegateIgnoresTouchesWhenDisabled() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        manager.toggleEnabled()  // Disable

        XCTAssertFalse(manager.isEnabled)

        // Create mock touch data with all required fields
        var touchData = MTTouch(
            frame: 0,
            timestamp: CACurrentMediaTime(),
            pathIndex: 0,
            state: 4,  // active state
            fingerID: 0,
            handID: 0,
            normalizedVector: MTVector(
                position: MTPoint(x: 0.5, y: 0.5),
                velocity: MTPoint(x: 0, y: 0)
            ),
            zTotal: 1.0,
            field9: 0,
            angle: 0,
            majorAxis: 0,
            minorAxis: 0,
            absoluteVector: MTVector(
                position: MTPoint(x: 0, y: 0),
                velocity: MTPoint(x: 0, y: 0)
            ),
            field14: 0,
            field15: 0,
            zDensity: 0
        )
        unsafe withUnsafeMutablePointer(to: &touchData) { pointer in
            let rawPointer = UnsafeMutableRawPointer(pointer)
            // This should not crash and should be ignored
            let tempMonitor = unsafe DeviceMonitor()
            unsafe manager.deviceMonitor(
                tempMonitor,
                didReceiveTouches: rawPointer,
                count: 1,
                timestamp: CACurrentMediaTime()
            )
        }

        // State should not change when disabled
        XCTAssertFalse(manager.isInThreeFingerGesture)

        manager.stop()
    }

    func testDeviceMonitorDelegateProcessesTouchesWhenEnabled() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()

        XCTAssertTrue(manager.isEnabled)

        // Create mock touch data with 3 touches (to potentially trigger gesture)
        var touchData = [
            MTTouch(
                frame: 0,
                timestamp: CACurrentMediaTime(),
                pathIndex: 0,
                state: 4,  // active state
                fingerID: 0,
                handID: 0,
                normalizedVector: MTVector(
                    position: MTPoint(x: 0.3, y: 0.5),
                    velocity: MTPoint(x: 0, y: 0)
                ),
                zTotal: 1.0,
                field9: 0,
                angle: 0,
                majorAxis: 0,
                minorAxis: 0,
                absoluteVector: MTVector(
                    position: MTPoint(x: 0, y: 0),
                    velocity: MTPoint(x: 0, y: 0)
                ),
                field14: 0,
                field15: 0,
                zDensity: 0
            ),
            MTTouch(
                frame: 0,
                timestamp: CACurrentMediaTime(),
                pathIndex: 1,
                state: 4,
                fingerID: 1,
                handID: 0,
                normalizedVector: MTVector(
                    position: MTPoint(x: 0.5, y: 0.5),
                    velocity: MTPoint(x: 0, y: 0)
                ),
                zTotal: 1.0,
                field9: 0,
                angle: 0,
                majorAxis: 0,
                minorAxis: 0,
                absoluteVector: MTVector(
                    position: MTPoint(x: 0, y: 0),
                    velocity: MTPoint(x: 0, y: 0)
                ),
                field14: 0,
                field15: 0,
                zDensity: 0
            ),
            MTTouch(
                frame: 0,
                timestamp: CACurrentMediaTime(),
                pathIndex: 2,
                state: 4,
                fingerID: 2,
                handID: 0,
                normalizedVector: MTVector(
                    position: MTPoint(x: 0.7, y: 0.5),
                    velocity: MTPoint(x: 0, y: 0)
                ),
                zTotal: 1.0,
                field9: 0,
                angle: 0,
                majorAxis: 0,
                minorAxis: 0,
                absoluteVector: MTVector(
                    position: MTPoint(x: 0, y: 0),
                    velocity: MTPoint(x: 0, y: 0)
                ),
                field14: 0,
                field15: 0,
                zDensity: 0
            ),
        ]
        unsafe touchData.withUnsafeMutableBytes { buffer in
            guard let rawPointer = buffer.baseAddress else { return }
            let tempMonitor = unsafe DeviceMonitor()
            unsafe manager.deviceMonitor(
                tempMonitor,
                didReceiveTouches: rawPointer,
                count: 3,
                timestamp: CACurrentMediaTime()
            )
        }

        // Give async processing time to complete
        let expectation = XCTestExpectation(description: "Processing complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        manager.stop()
    }

    func testGestureRecognizerDidUpdateDraggingWithMovement() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        var config = GestureConfiguration()
        config.middleDragEnabled = true
        config.sensitivity = 1.0
        manager.updateConfiguration(config)

        manager.start()
        manager.gestureRecognizerDidBeginDragging(recognizer)

        // Wait for async state to update
        let setupExpectation = XCTestExpectation(description: "Setup")
        DispatchQueue.main.async {
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 1.0)

        // Update with actual movement (centroid different from lastPosition)
        let gestureData = GestureData(
            centroid: MTPoint(x: 0.55, y: 0.55),
            velocity: MTPoint(x: 0.01, y: 0.01),
            pressure: 1.0,
            fingerCount: 3,
            startPosition: MTPoint(x: 0.5, y: 0.5),
            lastPosition: MTPoint(x: 0.5, y: 0.5)  // 0.05 difference = real movement
        )

        // This should execute the movement code path
        XCTAssertNoThrow(manager.gestureRecognizerDidUpdateDragging(recognizer, with: gestureData))

        manager.stop()
    }

    func testGestureRecognizerDidUpdateDraggingWithSmallMovement() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        var config = GestureConfiguration()
        config.middleDragEnabled = true
        config.sensitivity = 1.0
        manager.updateConfiguration(config)

        manager.start()
        manager.gestureRecognizerDidBeginDragging(recognizer)

        // Wait for async state
        let setupExpectation = XCTestExpectation(description: "Setup")
        DispatchQueue.main.async {
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 1.0)

        // Small but valid movement
        let gestureData = GestureData(
            centroid: MTPoint(x: 0.51, y: 0.51),
            velocity: MTPoint(x: 0.001, y: 0.001),
            pressure: 1.0,
            fingerCount: 3,
            startPosition: MTPoint(x: 0.5, y: 0.5),
            lastPosition: MTPoint(x: 0.5, y: 0.5)
        )

        XCTAssertNoThrow(manager.gestureRecognizerDidUpdateDragging(recognizer, with: gestureData))

        manager.stop()
    }

    func testGestureRecognizerDidUpdateDraggingMultipleUpdates() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        var config = GestureConfiguration()
        config.middleDragEnabled = true
        config.sensitivity = 2.0
        manager.updateConfiguration(config)

        manager.start()
        manager.gestureRecognizerDidBeginDragging(recognizer)

        // Wait for async state
        let setupExpectation = XCTestExpectation(description: "Setup")
        DispatchQueue.main.async {
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 1.0)

        // Simulate multiple movement updates
        for i in 1...5 {
            let offset = Float(i) * 0.01
            let gestureData = GestureData(
                centroid: MTPoint(x: 0.5 + offset, y: 0.5 + offset),
                velocity: MTPoint(x: 0.01, y: 0.01),
                pressure: 1.0,
                fingerCount: 3,
                startPosition: MTPoint(x: 0.5, y: 0.5),
                lastPosition: MTPoint(x: 0.5 + offset - 0.01, y: 0.5 + offset - 0.01)
            )
            XCTAssertNoThrow(
                manager.gestureRecognizerDidUpdateDragging(recognizer, with: gestureData))
        }

        manager.stop()
    }

    // MARK: - Configuration Edge Cases

    func testToggleEnabledWhileDragging() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        manager.start()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))
        manager.gestureRecognizerDidBeginDragging(recognizer)

        // Wait for async state
        let setupExpectation = XCTestExpectation(description: "Setup")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isActivelyDragging)
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 1.0)

        // Toggle enabled while dragging - should reset state
        manager.toggleEnabled()

        XCTAssertFalse(manager.isEnabled)

        manager.stop()
    }

    func testStopWhileDragging() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        manager.start()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))
        manager.gestureRecognizerDidBeginDragging(recognizer)

        // Wait for async state
        let setupExpectation = XCTestExpectation(description: "Setup")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isActivelyDragging)
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 1.0)

        // Stop while dragging should clean up
        XCTAssertNoThrow(manager.stop())
        XCTAssertFalse(manager.isMonitoring)
    }

    // MARK: - Window Size Filter Tests

    func testGestureRecognizerDidBeginDraggingWithWindowSizeFilterEnabled() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Enable window size filter with minimum requirements
        var config = GestureConfiguration()
        config.middleDragEnabled = true
        config.minimumWindowSizeFilterEnabled = true
        config.minimumWindowWidth = 50
        config.minimumWindowHeight = 50
        manager.updateConfiguration(config)

        manager.start()

        // Begin dragging - will check window size filter
        manager.gestureRecognizerDidBeginDragging(recognizer)

        // Wait for async processing
        let expectation = XCTestExpectation(description: "Processing complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        manager.stop()
    }

    func testGestureRecognizerDidTapWithWindowSizeFilterEnabled() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Enable window size filter
        var config = GestureConfiguration()
        config.minimumWindowSizeFilterEnabled = true
        config.minimumWindowWidth = 50
        config.minimumWindowHeight = 50
        manager.updateConfiguration(config)

        manager.start()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        // Wait for start state
        let startExpectation = XCTestExpectation(description: "Start state")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isInThreeFingerGesture)
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        // Tap - will check window size filter
        manager.gestureRecognizerDidTap(recognizer)

        // State should be reset regardless of filter result
        let tapExpectation = XCTestExpectation(description: "Tap complete")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isInThreeFingerGesture)
            tapExpectation.fulfill()
        }
        wait(for: [tapExpectation], timeout: 1.0)

        manager.stop()
    }

    func testGestureRecognizerDidTapWithWindowSizeFilterDisabled() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Ensure window size filter is disabled
        var config = GestureConfiguration()
        config.minimumWindowSizeFilterEnabled = false
        manager.updateConfiguration(config)

        manager.start()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        // Wait for start state
        let startExpectation = XCTestExpectation(description: "Start state")
        DispatchQueue.main.async {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        // Tap without filter
        manager.gestureRecognizerDidTap(recognizer)

        // Should complete without crash
        let tapExpectation = XCTestExpectation(description: "Tap complete")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isInThreeFingerGesture)
            tapExpectation.fulfill()
        }
        wait(for: [tapExpectation], timeout: 1.0)

        manager.stop()
    }

    func testMinimumWindowSizeConfiguration() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        var config = GestureConfiguration()
        config.minimumWindowSizeFilterEnabled = true
        config.minimumWindowWidth = 200
        config.minimumWindowHeight = 150

        manager.updateConfiguration(config)

        XCTAssertTrue(manager.configuration.minimumWindowSizeFilterEnabled)
        XCTAssertEqual(manager.configuration.minimumWindowWidth, 200)
        XCTAssertEqual(manager.configuration.minimumWindowHeight, 150)
    }

    // MARK: - Sleep/Wake Restart Tests

    func testRestartReconnectsDeviceMonitor() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        unsafe XCTAssertEqual(mockDevice.startCallCount, 1)
        XCTAssertTrue(manager.isMonitoring)
        XCTAssertTrue(manager.isEnabled)

        manager.restart()

        // Wait for async restart to complete
        let expectation = XCTestExpectation(description: "Restart complete")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MultitouchManager.restartCleanupDelay + 0.05
        ) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // After restart, monitoring should still be active
        XCTAssertTrue(manager.isMonitoring)
        XCTAssertTrue(manager.isEnabled)
        // Verify device monitor was stopped and started again
        unsafe XCTAssertEqual(mockDevice.stopCallCount, 1)
        unsafe XCTAssertEqual(mockDevice.startCallCount, 2)  // Initial start + restart

        manager.stop()
    }

    func testRestartPreservesEnabledState() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        XCTAssertTrue(manager.isEnabled)

        // Disable monitoring
        manager.toggleEnabled()
        XCTAssertFalse(manager.isEnabled)

        // Restart should preserve the disabled state
        manager.restart()

        // Wait for async restart to complete
        let expectation = XCTestExpectation(description: "Restart complete")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MultitouchManager.restartCleanupDelay + 0.05
        ) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertFalse(manager.isEnabled)
        XCTAssertTrue(manager.isMonitoring)

        manager.stop()
    }

    func testRestartCleansUpActiveGesture() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        var config = GestureConfiguration()
        config.middleDragEnabled = true
        manager.updateConfiguration(config)

        manager.start()

        // Start a drag
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))
        manager.gestureRecognizerDidBeginDragging(recognizer)

        let setupExpectation = XCTestExpectation(description: "Setup")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isActivelyDragging)
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 1.0)

        // Restart should clean up the gesture state immediately (before async delay)
        manager.restart()

        // Gesture state is cleaned up synchronously in internalStop()
        XCTAssertFalse(manager.isActivelyDragging)
        XCTAssertFalse(manager.isInThreeFingerGesture)

        // Wait for async restart to complete
        let restartExpectation = XCTestExpectation(description: "Restart complete")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MultitouchManager.restartCleanupDelay + 0.05
        ) {
            restartExpectation.fulfill()
        }
        wait(for: [restartExpectation], timeout: 1.0)

        XCTAssertTrue(manager.isMonitoring)

        manager.stop()
    }

    // MARK: - Race Condition Prevention Tests (restart delay)
    // These tests verify the fix for CFRelease(NULL) crashes caused by
    // concurrent device operations during wake from sleep.

    func testRestartUsesAsyncDelayForFrameworkCleanup() {
        // Verifies that restart() uses an async delay instead of blocking Thread.sleep.
        // This ensures the main thread is not blocked during wake-from-sleep.
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        unsafe XCTAssertEqual(mockDevice.startCallCount, 1)

        // restart() should return immediately (not block for 100ms)
        let startTime = CACurrentMediaTime()
        manager.restart()
        let elapsed = CACurrentMediaTime() - startTime

        // Should return quickly since delay is async
        XCTAssertLessThan(elapsed, 0.05, "restart() should not block the calling thread")

        // But the actual restart happens after the delay
        unsafe XCTAssertEqual(mockDevice.startCallCount, 1)  // Not yet restarted

        // Wait for async restart to complete
        let expectation = XCTestExpectation(description: "Restart complete")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MultitouchManager.restartCleanupDelay + 0.05
        ) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        unsafe XCTAssertEqual(mockDevice.startCallCount, 2)  // Now restarted

        manager.stop()
    }

    func testRestartCleanupDelayConstantExists() {
        // Verify the delay constant is defined and has a reasonable value
        XCTAssertGreaterThan(
            MultitouchManager.restartCleanupDelay, 0,
            "restartCleanupDelay should be positive")
        XCTAssertLessThanOrEqual(
            MultitouchManager.restartCleanupDelay, 0.5,
            "restartCleanupDelay should not be excessive")
    }

    func testMinimumRestartIntervalConstantExists() {
        // Verify the minimum restart interval constant is defined
        XCTAssertGreaterThan(
            MultitouchManager.minimumRestartInterval, 0,
            "minimumRestartInterval should be positive")
        XCTAssertLessThanOrEqual(
            MultitouchManager.minimumRestartInterval, 1.0,
            "minimumRestartInterval should not be excessive")
    }

    func testRestartThrottlingPreventsRaceCondition() {
        // Verifies that rapid restart calls are throttled to prevent race conditions
        // This specifically tests the fix for EXC_BREAKPOINT crashes from rapid
        // foreground/background toggling
        var creationCount = 0
        let manager = MultitouchManager(
            deviceProviderFactory: {
                creationCount += 1
                return unsafe MockDeviceMonitor()
            },
            eventTapSetup: { true }
        )

        manager.start()
        XCTAssertEqual(creationCount, 1)

        // Simulate rapid foreground/background toggling by calling restart many times
        // in quick succession (faster than minimumRestartInterval)
        for _ in 0..<10 {
            manager.restart()
        }

        // Wait long enough for throttled restarts to complete
        // Should coalesce to fewer actual restarts due to throttling
        let expectation = XCTestExpectation(description: "Throttled restarts complete")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MultitouchManager.minimumRestartInterval + MultitouchManager.restartCleanupDelay + 0.2
        ) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        // We expect far fewer than 10 device creations due to:
        // 1. The first restart being in progress blocks subsequent ones
        // 2. Throttling after restart completes delays subsequent restarts
        // Should be: 1 initial + 1-2 restarts = 2-3 total
        XCTAssertLessThanOrEqual(creationCount, 4, "Rapid restarts should be throttled")
        XCTAssertTrue(manager.isMonitoring, "Should still be monitoring after throttled restarts")

        manager.stop()
    }

    func testRestartInProgressBlocksDuplicateCalls() {
        // Verifies that restart() returns early when a restart is already in progress
        var creationCount = 0
        let manager = MultitouchManager(
            deviceProviderFactory: {
                creationCount += 1
                return unsafe MockDeviceMonitor()
            },
            eventTapSetup: { true }
        )

        manager.start()
        XCTAssertEqual(creationCount, 1)

        // First restart enters the async delay
        manager.restart()

        // Immediately try to restart again - should be blocked
        manager.restart()
        manager.restart()

        // Wait for the single restart to complete
        let expectation = XCTestExpectation(description: "Restart complete")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MultitouchManager.restartCleanupDelay + 0.1
        ) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Only 2 device creations: initial start + one restart
        // The duplicate restart calls while in progress should have been skipped
        XCTAssertEqual(creationCount, 2, "Duplicate restart calls during in-progress restart should be skipped")

        manager.stop()
    }

    func testRapidRestartCyclesDoNotCrash() {
        // Simulates rapid wake-from-sleep scenarios where multiple restart
        // calls could occur in quick succession.
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()

        // Multiple rapid restarts - most will be throttled or blocked
        for _ in 0..<3 {
            XCTAssertNoThrow(manager.restart())
        }

        // Wait for all async restarts to complete (account for throttling delays)
        let expectation = XCTestExpectation(description: "All restarts complete")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MultitouchManager.minimumRestartInterval + MultitouchManager.restartCleanupDelay + 0.2
        ) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)

        // Should still be monitoring after all restarts
        XCTAssertTrue(manager.isMonitoring)

        manager.stop()
    }

    func testRestartDuringActiveGestureDoesNotCrash() {
        // Tests that restarting while a gesture is in progress doesn't crash.
        // This covers the scenario where sleep occurs during active use.
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        var config = GestureConfiguration()
        config.middleDragEnabled = true
        manager.updateConfiguration(config)

        manager.start()

        // Start a gesture
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))
        manager.gestureRecognizerDidBeginDragging(recognizer)

        // Wait for state to settle
        let gestureExpectation = XCTestExpectation(description: "Gesture active")
        DispatchQueue.main.async {
            gestureExpectation.fulfill()
        }
        wait(for: [gestureExpectation], timeout: 1.0)

        // Restart during active gesture should not crash
        XCTAssertNoThrow(manager.restart())

        // Gesture state should be cleaned up immediately (synchronous in internalStop)
        XCTAssertFalse(manager.isActivelyDragging)
        XCTAssertFalse(manager.isInThreeFingerGesture)

        // Wait for async restart to complete
        let restartExpectation = XCTestExpectation(description: "Restart complete")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MultitouchManager.restartCleanupDelay + 0.05
        ) {
            restartExpectation.fulfill()
        }
        wait(for: [restartExpectation], timeout: 1.0)

        XCTAssertTrue(manager.isMonitoring)

        manager.stop()
    }

    func testRestartFromBackgroundThreadDoesNotCrash() {
        // Tests restart being called from a different thread (simulating
        // the wake notification arriving on a background queue).
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()

        let expectation = XCTestExpectation(description: "Background restart complete")
        DispatchQueue.global().async {
            manager.restart()
            // Wait for async restart to complete before fulfilling
            DispatchQueue.main.asyncAfter(
                deadline: .now() + MultitouchManager.restartCleanupDelay + 0.1
            ) {
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 2.0)

        XCTAssertTrue(manager.isMonitoring)

        manager.stop()
    }

    // MARK: - Event Processing Logic Tests

    func testProcessEventPassesThroughTapDisabledEvents() throws {
        try requireCGEventTestsEnabled()
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        // We can't construct tapDisabledByTimeout directly as it is a specific system type
        // but we can verify that a standard event (representing a pass-through) works
        let event = CGEvent(source: nil)!
        let result = unsafe manager.processEvent(event, type: .leftMouseDown)
        unsafe XCTAssertNotNil(result)
    }

    func testProcessEventIdentifiesOurEvents() throws {
        try requireCGEventTestsEnabled()
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        let event = CGEvent(source: nil)!
        event.setIntegerValueField(.eventSourceUserData, value: 0x4D44)
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)  // Middle button

        // Simulate "Our Event" (middle click generated by us)
        let result = unsafe manager.processEvent(event, type: .otherMouseDown)

        // Should pass through
        unsafe XCTAssertNotNil(result)
        // Verify it was NOT suppressed
        if let returnedEvent = unsafe result?.takeUnretainedValue() {
            XCTAssertEqual(returnedEvent, event)
        } else {
            XCTFail("Event should not be suppressed")
        }
    }

    func testProcessEventIntercptsForceClick() throws {
        try requireCGEventTestsEnabled()
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        // Setup state for force click: 3 fingers + left mouse down
        manager.currentFingerCount = 3

        // Create a LEFT mouse down event (physical click)
        let event = CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint.zero,
            mouseButton: .left)!

        // It should be intercepted (return nil) and converted to middle click
        let result = unsafe manager.processEvent(event, type: .leftMouseDown)

        unsafe XCTAssertNil(
            result, "Physical left click with 3 fingers should be suppressed (Force Click)")
    }

    func testProcessEventPassesNormalLeftClick() throws {
        try requireCGEventTestsEnabled()
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        // Setup state: Only 1 finger
        manager.currentFingerCount = 1

        let event = CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint.zero,
            mouseButton: .left)!

        let result = unsafe manager.processEvent(event, type: .leftMouseDown)

        unsafe XCTAssertNotNil(result, "Normal left click should pass through")
    }

    func testProcessEventSuppressesDuringGesture() throws {
        try requireCGEventTestsEnabled()
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        // Setup state: In 3 finger gesture, but 0 fingers currently (e.g. lift off)
        let recognizer = GestureRecognizer()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0, y: 0))

        // Process on main thread to update state
        let expectation = XCTestExpectation(description: "State update")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Left mouse down (not our event)
        let event = CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint.zero,
            mouseButton: .left)!

        let result = unsafe manager.processEvent(event, type: .leftMouseDown)

        // Should be suppressed
        unsafe XCTAssertNil(result)
    }

    // MARK: - Modifier Key Event Suppression Tests
    // Note: Tests for modifier key behavior are removed because CGEventSource.flagsState
    // cannot be easily mocked in unit tests. The modifier key logic is tested through
    // integration testing and manual verification.

    func testProcessEventSuppressesWhenModifierHeldAndGestureActive() throws {
        try requireCGEventTestsEnabled()
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        // Don't require modifier key (so gesture is always considered active when flags are set)
        var config = GestureConfiguration()
        config.requireModifierKey = false
        manager.updateConfiguration(config)

        manager.start()

        // Setup state: In 3 finger gesture
        let recognizer = GestureRecognizer()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0, y: 0))

        // Wait for state update
        let expectation = XCTestExpectation(description: "State update")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isInThreeFingerGesture)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Create a left mouse event
        let event = CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint.zero,
            mouseButton: .left)!

        let result = unsafe manager.processEvent(event, type: .leftMouseDown)

        // Should be suppressed because gesture is active and modifier not required
        unsafe XCTAssertNil(result, "Event should be suppressed during active gesture")

        manager.stop()
    }

    // MARK: - Last Gesture Was Active Flag Tests

    func testCancelledGestureDoesNotSuppressEventsAfterEnd() throws {
        try requireCGEventTestsEnabled()
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()

        // Start a gesture
        let recognizer = GestureRecognizer()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0, y: 0))

        // Wait for state update
        let startExpectation = XCTestExpectation(description: "Start state")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isInThreeFingerGesture)
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        // Cancel the gesture (e.g., modifier key released or 4th finger added)
        manager.gestureRecognizerDidCancel(recognizer)

        // Wait for cancel state update
        let cancelExpectation = XCTestExpectation(description: "Cancel state")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isInThreeFingerGesture)
            cancelExpectation.fulfill()
        }
        wait(for: [cancelExpectation], timeout: 1.0)

        // Create a left mouse event after cancellation
        let event = CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint.zero,
            mouseButton: .left)!

        let result = unsafe manager.processEvent(event, type: .leftMouseDown)

        // Should NOT be suppressed because gesture was cancelled (lastGestureWasActive = false)
        unsafe XCTAssertNotNil(result, "Event should pass through after cancelled gesture")

        manager.stop()
    }

    func testActiveGestureSuppressesEventsAfterEnd() throws {
        try requireCGEventTestsEnabled()
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        var config = GestureConfiguration()
        config.tapToClickEnabled = true
        manager.updateConfiguration(config)

        manager.start()

        // Start a gesture
        let recognizer = GestureRecognizer()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0, y: 0))

        // Wait for state update
        let startExpectation = XCTestExpectation(description: "Start state")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isInThreeFingerGesture)
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        // Complete the gesture with a tap (active gesture)
        manager.gestureRecognizerDidTap(recognizer)

        // Wait for tap state update
        let tapExpectation = XCTestExpectation(description: "Tap state")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isInThreeFingerGesture)
            tapExpectation.fulfill()
        }
        wait(for: [tapExpectation], timeout: 1.0)

        // Immediately create a left mouse event after active gesture ends
        let event = CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint.zero,
            mouseButton: .left)!

        let result = unsafe manager.processEvent(event, type: .leftMouseDown)

        // Should be suppressed because gesture was active (lastGestureWasActive = true)
        // and we're within the 0.15s suppression window
        unsafe XCTAssertNil(result, "Event should be suppressed after active gesture ends")

        manager.stop()
    }

    func testCancelledDragDoesNotSuppressEventsAfterEnd() throws {
        try requireCGEventTestsEnabled()
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        var config = GestureConfiguration()
        config.middleDragEnabled = true
        manager.updateConfiguration(config)

        manager.start()

        // Start a drag
        let recognizer = GestureRecognizer()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0, y: 0))
        manager.gestureRecognizerDidBeginDragging(recognizer)

        // Wait for state update
        let startExpectation = XCTestExpectation(description: "Start state")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isActivelyDragging)
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        // Cancel the drag (e.g., 4th finger added for Mission Control)
        manager.gestureRecognizerDidCancelDragging(recognizer)

        // Wait for cancel state update
        let cancelExpectation = XCTestExpectation(description: "Cancel state")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isActivelyDragging)
            XCTAssertFalse(manager.isInThreeFingerGesture)
            cancelExpectation.fulfill()
        }
        wait(for: [cancelExpectation], timeout: 1.0)

        // Create a left mouse event after cancellation
        let event = CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint.zero,
            mouseButton: .left)!

        let result = unsafe manager.processEvent(event, type: .leftMouseDown)

        // Should NOT be suppressed because drag was cancelled (lastGestureWasActive = false)
        unsafe XCTAssertNotNil(result, "Event should pass through after cancelled drag")

        manager.stop()
    }

    func testActiveDragSuppressesEventsAfterEnd() throws {
        try requireCGEventTestsEnabled()
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        var config = GestureConfiguration()
        config.middleDragEnabled = true
        manager.updateConfiguration(config)

        manager.start()

        // Start a drag
        let recognizer = GestureRecognizer()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0, y: 0))
        manager.gestureRecognizerDidBeginDragging(recognizer)

        // Wait for state update
        let startExpectation = XCTestExpectation(description: "Start state")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isActivelyDragging)
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        // End the drag normally (active gesture)
        manager.gestureRecognizerDidEndDragging(recognizer)

        // Wait for end state update
        let endExpectation = XCTestExpectation(description: "End state")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isActivelyDragging)
            XCTAssertFalse(manager.isInThreeFingerGesture)
            endExpectation.fulfill()
        }
        wait(for: [endExpectation], timeout: 1.0)

        // Immediately create a left mouse event after active drag ends
        let event = CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint.zero,
            mouseButton: .left)!

        let result = unsafe manager.processEvent(event, type: .leftMouseDown)

        // Should be suppressed because drag was active (lastGestureWasActive = true)
        // and we're within the 0.15s suppression window
        unsafe XCTAssertNil(result, "Event should be suppressed after active drag ends")

        manager.stop()
    }

    func testEventSuppressionWindowExpires() throws {
        try requireCGEventTestsEnabled()
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        var config = GestureConfiguration()
        config.tapToClickEnabled = true
        manager.updateConfiguration(config)

        manager.start()

        // Start and complete a gesture
        let recognizer = GestureRecognizer()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0, y: 0))
        manager.gestureRecognizerDidTap(recognizer)

        // Wait for state update
        let expectation = XCTestExpectation(description: "State update")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isInThreeFingerGesture)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Wait for suppression window to expire (0.15s + buffer)
        let waitExpectation = XCTestExpectation(description: "Wait for suppression window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            waitExpectation.fulfill()
        }
        wait(for: [waitExpectation], timeout: 1.0)

        // Create a left mouse event after suppression window expires
        let event = CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint.zero,
            mouseButton: .left)!

        let result = unsafe manager.processEvent(event, type: .leftMouseDown)

        // Should NOT be suppressed because suppression window has expired
        unsafe XCTAssertNotNil(result, "Event should pass through after suppression window expires")

        manager.stop()
    }


    func testToggleEnabledResetsLastGestureWasActive() throws {
        try requireCGEventTestsEnabled()
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()

        // Start and complete a gesture
        let recognizer = GestureRecognizer()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0, y: 0))
        manager.gestureRecognizerDidTap(recognizer)

        // Wait for state update
        let expectation = XCTestExpectation(description: "State update")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Toggle enabled off (should reset lastGestureWasActive)
        manager.toggleEnabled()

        // Create a left mouse event
        let event = CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint.zero,
            mouseButton: .left)!

        let result = unsafe manager.processEvent(event, type: .leftMouseDown)

        // Should NOT be suppressed because toggleEnabled reset the flag
        unsafe XCTAssertNotNil(result, "Event should pass through after toggleEnabled resets state")

        manager.stop()
    }

    // MARK: - Cleanup

    override func tearDown() {
        // Ensure we stop monitoring after each test
        MultitouchManager.shared.stop()

        // Reset configuration to defaults
        MultitouchManager.shared.updateConfiguration(GestureConfiguration())

        super.tearDown()
    }

    // MARK: - Sleep/Wake Observer Tests

    func testAddSleepWakeObservers() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        // Observers should be added when starting
        // We can't directly test the observers, but we can verify start doesn't crash
        XCTAssertTrue(manager.isMonitoring)

        manager.stop()
    }

    func testRemoveSleepWakeObservers() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        manager.stop()
        // Observers should be removed when stopping
        // Verify stop completes without crash
        XCTAssertFalse(manager.isMonitoring)
    }

    func testPerformRestartWithEventTapFailure() {
        // Test performRestart when event tap setup fails (lines 207-213)
        let mockDevice = unsafe MockDeviceMonitor()
        var eventTapSetupCalled = false
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice },
            eventTapSetup: {
                eventTapSetupCalled = true
                return false  // Simulate event tap failure
            })

        manager.start()
        // Simulate wake from sleep by calling restart
        manager.restart()

        // Wait a bit for async operations
        let expectation = XCTestExpectation(description: "Restart completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Manager should handle the failure gracefully
        XCTAssertTrue(eventTapSetupCalled)
        manager.stop()
    }

    func testPerformRestartWithDeviceStartFailure() {
        // Test performRestart when device start fails (lines 218-229)
        let mockDevice = unsafe MockDeviceMonitor()
        unsafe mockDevice.startShouldSucceed = false
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        // Simulate wake from sleep by calling restart
        manager.restart()

        // Wait a bit for async operations
        let expectation = XCTestExpectation(description: "Restart completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Manager should handle the failure gracefully
        manager.stop()
    }

    func testPerformRestartGuardWhenWakeObserverNil() {
        // Test performRestart guard when wakeObserver is nil (line 202)
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        // Start and stop to clear observers
        manager.start()
        manager.stop()

        // Now restart should return early because wakeObserver is nil
        manager.restart()

        // Wait a bit for async operations
        let expectation = XCTestExpectation(description: "Restart completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Should complete without crash
        XCTAssertFalse(manager.isMonitoring)
    }

    // MARK: - Thread-Safety Tests for MainActor.assumeIsolated Calls

    func testIgnoreDesktopCheckFromMainThread() {
        // Test that ignoreDesktop check works from main thread without deadlock
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Enable ignoreDesktop feature
        var config = GestureConfiguration()
        config.ignoreDesktop = true
        config.middleDragEnabled = true
        manager.updateConfiguration(config)

        manager.start()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        // Call from main thread - should complete without deadlock
        let expectation = XCTestExpectation(description: "Main thread check completes")
        DispatchQueue.main.async {
            // This exercises shouldSkipGestureForDesktop from main thread
            manager.gestureRecognizerDidBeginDragging(recognizer)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        manager.stop()
    }

    func testIgnoreDesktopCheckFromBackgroundThread() {
        // Test that ignoreDesktop check works from background thread
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Enable ignoreDesktop feature
        var config = GestureConfiguration()
        config.ignoreDesktop = true
        config.middleDragEnabled = true
        manager.updateConfiguration(config)

        manager.start()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        // Call from background thread - uses DispatchQueue.main.sync
        let expectation = XCTestExpectation(description: "Background thread check completes")
        DispatchQueue.global(qos: .userInitiated).async {
            // This exercises shouldSkipGestureForDesktop from background thread
            manager.gestureRecognizerDidBeginDragging(recognizer)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        manager.stop()
    }

    func testWindowSizeFilterCheckFromMainThread_Drag() {
        // Test that window size filter check works from main thread for drag
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Enable window size filter
        var config = GestureConfiguration()
        config.middleDragEnabled = true
        config.minimumWindowSizeFilterEnabled = true
        config.minimumWindowWidth = 100
        config.minimumWindowHeight = 100
        manager.updateConfiguration(config)

        manager.start()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        // Call from main thread - uses MainActor.assumeIsolated directly
        let expectation = XCTestExpectation(description: "Main thread drag check completes")
        DispatchQueue.main.async {
            manager.gestureRecognizerDidBeginDragging(recognizer)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        manager.stop()
    }

    func testWindowSizeFilterCheckFromBackgroundThread_Drag() {
        // Test that window size filter check works from background thread for drag
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Enable window size filter
        var config = GestureConfiguration()
        config.middleDragEnabled = true
        config.minimumWindowSizeFilterEnabled = true
        config.minimumWindowWidth = 100
        config.minimumWindowHeight = 100
        manager.updateConfiguration(config)

        manager.start()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        // Call from background thread - uses DispatchQueue.main.sync
        let expectation = XCTestExpectation(description: "Background thread drag check completes")
        DispatchQueue.global(qos: .userInitiated).async {
            manager.gestureRecognizerDidBeginDragging(recognizer)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        manager.stop()
    }

    func testWindowSizeFilterCheckFromMainThread_Tap() {
        // Test that window size filter check works from main thread for tap
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Enable window size filter
        var config = GestureConfiguration()
        config.minimumWindowSizeFilterEnabled = true
        config.minimumWindowWidth = 100
        config.minimumWindowHeight = 100
        manager.updateConfiguration(config)

        manager.start()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        // Call from main thread
        let expectation = XCTestExpectation(description: "Main thread tap check completes")
        DispatchQueue.main.async {
            manager.gestureRecognizerDidTap(recognizer)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        manager.stop()
    }

    func testWindowSizeFilterCheckFromBackgroundThread_Tap() {
        // Test that window size filter check works from background thread for tap
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Enable window size filter
        var config = GestureConfiguration()
        config.minimumWindowSizeFilterEnabled = true
        config.minimumWindowWidth = 100
        config.minimumWindowHeight = 100
        manager.updateConfiguration(config)

        manager.start()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        // Call from background thread - uses DispatchQueue.main.sync
        let expectation = XCTestExpectation(description: "Background thread tap check completes")
        DispatchQueue.global(qos: .userInitiated).async {
            manager.gestureRecognizerDidTap(recognizer)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        manager.stop()
    }

    func testCombinedIgnoreDesktopAndWindowSizeFilterFromBackgroundThread() {
        // Test both features enabled - exercises both code paths
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        // Enable both features
        var config = GestureConfiguration()
        config.middleDragEnabled = true
        config.ignoreDesktop = true
        config.minimumWindowSizeFilterEnabled = true
        config.minimumWindowWidth = 100
        config.minimumWindowHeight = 100
        manager.updateConfiguration(config)

        manager.start()
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        // Call from background thread - exercises both MainActor.assumeIsolated paths
        let expectation = XCTestExpectation(description: "Combined check completes")
        DispatchQueue.global(qos: .userInitiated).async {
            manager.gestureRecognizerDidBeginDragging(recognizer)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        manager.stop()
    }

    func testMainActorIsolatedCallsDoNotDeadlock() throws {
        // Stress test to ensure no deadlock from rapid thread switches
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        nonisolated(unsafe) let recognizer = GestureRecognizer()

        var config = GestureConfiguration()
        config.middleDragEnabled = true
        config.ignoreDesktop = true
        config.minimumWindowSizeFilterEnabled = true
        config.minimumWindowWidth = 50
        config.minimumWindowHeight = 50
        manager.updateConfiguration(config)

        manager.start()

        let iterations = 10
        let expectation = XCTestExpectation(description: "All iterations complete")
        expectation.expectedFulfillmentCount = iterations * 2

        for _ in 0..<iterations {
            // Main thread call
            DispatchQueue.main.async {
                unsafe manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))
                unsafe manager.gestureRecognizerDidBeginDragging(recognizer)
                unsafe manager.gestureRecognizerDidEndDragging(recognizer)
                expectation.fulfill()
            }

            // Background thread call
            DispatchQueue.global(qos: .userInitiated).async {
                unsafe manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))
                unsafe manager.gestureRecognizerDidTap(recognizer)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 10.0)
        manager.stop()
    }

    // MARK: - Force Release Stuck Drag Tests

    func testForceReleaseStuckDragResetsGestureState() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        manager.start()

        // Enter gesture state
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))

        let startExpectation = XCTestExpectation(description: "Gesture started")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isInThreeFingerGesture)
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        // Force release
        manager.forceReleaseStuckDrag()

        let releaseExpectation = XCTestExpectation(description: "Force release complete")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isInThreeFingerGesture)
            releaseExpectation.fulfill()
        }
        wait(for: [releaseExpectation], timeout: 1.0)

        manager.stop()
    }

    func testForceReleaseStuckDragResetsDraggingState() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        var config = GestureConfiguration()
        config.middleDragEnabled = true
        manager.updateConfiguration(config)

        manager.start()

        // Enter dragging state
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))
        manager.gestureRecognizerDidBeginDragging(recognizer)

        let startExpectation = XCTestExpectation(description: "Dragging started")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isActivelyDragging)
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1.0)

        // Force release
        manager.forceReleaseStuckDrag()

        let releaseExpectation = XCTestExpectation(description: "Force release complete")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isActivelyDragging)
            XCTAssertFalse(manager.isInThreeFingerGesture)
            releaseExpectation.fulfill()
        }
        wait(for: [releaseExpectation], timeout: 1.0)

        manager.stop()
    }

    func testForceReleaseStuckDragWhenNotDragging() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()

        // Force release when not in any gesture state - should not crash
        XCTAssertFalse(manager.isInThreeFingerGesture)
        XCTAssertFalse(manager.isActivelyDragging)

        XCTAssertNoThrow(manager.forceReleaseStuckDrag())

        // State should still be false
        XCTAssertFalse(manager.isInThreeFingerGesture)
        XCTAssertFalse(manager.isActivelyDragging)

        manager.stop()
    }

    func testForceReleaseStuckDragMultipleTimes() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        manager.start()

        // Enter gesture state
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))
        manager.gestureRecognizerDidBeginDragging(recognizer)

        let setupExpectation = XCTestExpectation(description: "Setup complete")
        DispatchQueue.main.async {
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 1.0)

        // Force release multiple times - should not crash
        for _ in 1...3 {
            XCTAssertNoThrow(manager.forceReleaseStuckDrag())
        }

        manager.stop()
    }

    func testForceReleaseStuckDragResetsGestureRecognizer() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        manager.start()

        // Enter gesture state
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))
        manager.gestureRecognizerDidBeginDragging(recognizer)

        let setupExpectation = XCTestExpectation(description: "Setup complete")
        DispatchQueue.main.async {
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 1.0)

        // Force release
        manager.forceReleaseStuckDrag()

        // Should be able to start a new gesture after force release
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.6, y: 0.6))

        let newGestureExpectation = XCTestExpectation(description: "New gesture started")
        DispatchQueue.main.async {
            XCTAssertTrue(manager.isInThreeFingerGesture)
            newGestureExpectation.fulfill()
        }
        wait(for: [newGestureExpectation], timeout: 1.0)

        manager.stop()
    }

    func testForceReleaseStuckDragWhileDisabled() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        manager.start()
        manager.toggleEnabled()  // Disable

        XCTAssertFalse(manager.isEnabled)

        // Force release when disabled - should not crash
        XCTAssertNoThrow(manager.forceReleaseStuckDrag())

        manager.stop()
    }

    func testForceReleaseStuckDragWhenStopped() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })

        // Don't start the manager

        // Force release when stopped - should not crash
        XCTAssertNoThrow(manager.forceReleaseStuckDrag())
    }

    func testForceReleaseAfterNormalEndDrag() {
        let mockDevice = unsafe MockDeviceMonitor()
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice }, eventTapSetup: { true })
        let recognizer = GestureRecognizer()

        manager.start()

        // Start and end drag normally
        manager.gestureRecognizerDidStart(recognizer, at: MTPoint(x: 0.5, y: 0.5))
        manager.gestureRecognizerDidBeginDragging(recognizer)

        let setupExpectation = XCTestExpectation(description: "Setup")
        DispatchQueue.main.async {
            setupExpectation.fulfill()
        }
        wait(for: [setupExpectation], timeout: 1.0)

        manager.gestureRecognizerDidEndDragging(recognizer)

        let endExpectation = XCTestExpectation(description: "Normal end")
        DispatchQueue.main.async {
            XCTAssertFalse(manager.isActivelyDragging)
            endExpectation.fulfill()
        }
        wait(for: [endExpectation], timeout: 1.0)

        // Force release after normal end - should be no-op but not crash
        XCTAssertNoThrow(manager.forceReleaseStuckDrag())

        manager.stop()
    }
}
