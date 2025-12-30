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

    // MARK: - GestureRecognizerDelegate State Transition Tests

    func testGestureRecognizerDidStartSetsThreeFingerGestureState() {
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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

    func testGestureRecognizerDidBeginDraggingSetsActivelyDragging() {
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })

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
        withUnsafeMutablePointer(to: &touchData) { pointer in
            let rawPointer = UnsafeMutableRawPointer(pointer)
            // This should not crash and should be ignored
            let tempMonitor = DeviceMonitor()
            manager.deviceMonitor(
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })

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
        touchData.withUnsafeMutableBytes { buffer in
            guard let rawPointer = buffer.baseAddress else { return }
            let tempMonitor = DeviceMonitor()
            manager.deviceMonitor(
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })

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
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })

        manager.start()
        XCTAssertEqual(mockDevice.startCallCount, 1)
        XCTAssertTrue(manager.isMonitoring)
        XCTAssertTrue(manager.isEnabled)

        manager.restart()

        // After restart, monitoring should still be active
        XCTAssertTrue(manager.isMonitoring)
        XCTAssertTrue(manager.isEnabled)
        // Note: stopCount includes the stop during restart
        XCTAssertEqual(mockDevice.stopCallCount, 1)

        manager.stop()
    }

    func testRestartPreservesEnabledState() {
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })

        manager.start()
        XCTAssertTrue(manager.isEnabled)

        // Disable monitoring
        manager.toggleEnabled()
        XCTAssertFalse(manager.isEnabled)

        // Restart should preserve the disabled state
        manager.restart()
        XCTAssertFalse(manager.isEnabled)
        XCTAssertTrue(manager.isMonitoring)

        manager.stop()
    }

    func testRestartCleansUpActiveGesture() {
        let mockDevice = MockDeviceMonitor()
        let manager = MultitouchManager(deviceProviderFactory: { mockDevice })
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

        // Restart should clean up the gesture state
        manager.restart()

        XCTAssertTrue(manager.isMonitoring)

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
}
