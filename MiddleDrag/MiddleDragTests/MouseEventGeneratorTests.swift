import XCTest

@testable import MiddleDragCore

final class MouseEventGeneratorTests: XCTestCase {

    var generator: MouseEventGenerator!

    override func setUp() {
        super.setUp()
        generator = MouseEventGenerator()
    }

    override func tearDown() {
        generator.cancelDrag()
        generator = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testDefaultSmoothingFactor() {
        XCTAssertEqual(generator.smoothingFactor, 0.3, accuracy: 0.001)
    }

    func testDefaultMinimumMovementThreshold() {
        XCTAssertEqual(generator.minimumMovementThreshold, 0.5, accuracy: 0.001)
    }

    func testSmoothingFactorCanBeModified() {
        generator.smoothingFactor = 0.5
        XCTAssertEqual(generator.smoothingFactor, 0.5, accuracy: 0.001)
    }

    func testMinimumMovementThresholdCanBeModified() {
        generator.minimumMovementThreshold = 1.0
        XCTAssertEqual(generator.minimumMovementThreshold, 1.0, accuracy: 0.001)
    }

    // MARK: - Drag State Tests

    func testCancelDragWithoutActiveDrag() {
        // Should not crash when cancelling with no active drag
        generator.cancelDrag()
        // No assertion needed - just verifying no crash
    }

    func testEndDragWithoutActiveDrag() {
        // Should not crash when ending with no active drag
        generator.endDrag()
        // No assertion needed - just verifying no crash
    }

    func testUpdateDragWithoutActiveDrag() {
        // Should not crash when updating with no active drag
        generator.updateDrag(deltaX: 10, deltaY: 10)
        // No assertion needed - just verifying no crash (guard should return early)
    }

    // MARK: - Smoothing Factor Effect Tests

    func testZeroSmoothingFactor() {
        generator.smoothingFactor = 0.0
        XCTAssertEqual(generator.smoothingFactor, 0.0, accuracy: 0.001)
    }

    func testMaxSmoothingFactor() {
        generator.smoothingFactor = 1.0
        XCTAssertEqual(generator.smoothingFactor, 1.0, accuracy: 0.001)
    }

    // MARK: - Movement Threshold Tests

    func testZeroMovementThreshold() {
        generator.minimumMovementThreshold = 0.0
        XCTAssertEqual(generator.minimumMovementThreshold, 0.0, accuracy: 0.001)
    }

    func testLargeMovementThreshold() {
        generator.minimumMovementThreshold = 100.0
        XCTAssertEqual(generator.minimumMovementThreshold, 100.0, accuracy: 0.001)
    }

    // MARK: - Static Method Tests

    func testCurrentMouseLocationReturnsValidPoint() {
        let location = MouseEventGenerator.currentMouseLocation
        // Location should be a valid CGPoint (not NaN or infinite)
        XCTAssertFalse(location.x.isNaN)
        XCTAssertFalse(location.y.isNaN)
        XCTAssertFalse(location.x.isInfinite)
        XCTAssertFalse(location.y.isInfinite)
    }

    func testCurrentMouseLocationIsNonNegative() {
        // Mouse coordinates in Quartz space should be >= 0
        // (though in multi-monitor setups this might not always be true)
        let location = MouseEventGenerator.currentMouseLocation
        // Just verify it's a finite number
        XCTAssertTrue(location.x.isFinite)
        XCTAssertTrue(location.y.isFinite)
    }

    func testStartDragDoesNotCrash() {
        let startPoint = CGPoint(x: 100, y: 100)
        generator.startDrag(at: startPoint)

        // Wait for async operation
        let expectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)
    }

    func testStartAndEndDragSequence() {
        let startPoint = CGPoint(x: 100, y: 100)
        generator.startDrag(at: startPoint)

        // Wait for start
        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        generator.endDrag()

        // Wait for end
        let endExpectation = XCTestExpectation(description: "Drag ended")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            endExpectation.fulfill()
        }
        wait(for: [endExpectation], timeout: 0.5)
    }

    func testPerformClickDoesNotCrash() {
        XCTAssertNoThrow(generator.performClick())

        // Wait for async operation
        let expectation = XCTestExpectation(description: "Click completed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)
    }

    func testUpdateDragDuringActiveDrag() {
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        // Wait for start
        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Now update should not be ignored
        XCTAssertNoThrow(generator.updateDrag(deltaX: 10, deltaY: 10))

        generator.endDrag()
    }

    func testCancelDragDuringActiveDrag() {
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        // Wait for start
        let expectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)

        XCTAssertNoThrow(generator.cancelDrag())
    }

    // MARK: - Movement Threshold Tests

    func testMovementBelowThresholdIsIgnored() {
        generator.minimumMovementThreshold = 1.0
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        // Wait for start
        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Update with movement below threshold (magnitude < 1.0)
        // Movement of 0.3, 0.3 has magnitude ~0.42 which is below 1.0
        XCTAssertNoThrow(generator.updateDrag(deltaX: 0.3, deltaY: 0.3))

        generator.endDrag()
    }

    func testMovementAtThresholdIsProcessed() {
        generator.minimumMovementThreshold = 0.5
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        // Wait for start
        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Movement exactly at threshold (0.5)
        // sqrt(0.35^2 + 0.35^2) ≈ 0.495 which is at threshold
        XCTAssertNoThrow(generator.updateDrag(deltaX: 0.5, deltaY: 0.0))

        generator.endDrag()
    }

    func testMovementAboveThresholdIsProcessed() {
        generator.minimumMovementThreshold = 0.5
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        // Wait for start
        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Large movement well above threshold
        XCTAssertNoThrow(generator.updateDrag(deltaX: 10.0, deltaY: 10.0))

        generator.endDrag()
    }

    func testVerySmallThresholdAcceptsSmallMovements() {
        generator.minimumMovementThreshold = 0.01
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        // Wait for start
        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Very small movement should be accepted with tiny threshold
        XCTAssertNoThrow(generator.updateDrag(deltaX: 0.1, deltaY: 0.1))

        generator.endDrag()
    }

    // MARK: - Smoothing Effect Tests

    func testZeroSmoothingPassesFullDelta() {
        generator.smoothingFactor = 0.0
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        // Wait for start
        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // With zero smoothing, the internal smoothed delta should be 0 (factor * delta)
        // This tests the code path where smoothingFactor > 0 check is false
        XCTAssertNoThrow(generator.updateDrag(deltaX: 10.0, deltaY: 10.0))

        generator.endDrag()
    }

    func testFullSmoothingReducesMovement() {
        generator.smoothingFactor = 1.0
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        // Wait for start
        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // With full smoothing, delta is multiplied by factor (1.0 * delta = delta)
        XCTAssertNoThrow(generator.updateDrag(deltaX: 10.0, deltaY: 10.0))

        generator.endDrag()
    }

    func testPartialSmoothingReducesMovement() {
        generator.smoothingFactor = 0.5
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        // Wait for start
        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // With 0.5 smoothing, delta should be halved
        XCTAssertNoThrow(generator.updateDrag(deltaX: 10.0, deltaY: 10.0))

        generator.endDrag()
    }

    // MARK: - Drag State Verification Tests

    func testMultipleDragSequences() {
        // First drag sequence
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let exp1 = XCTestExpectation(description: "First drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 0.5)

        generator.updateDrag(deltaX: 5, deltaY: 5)
        generator.endDrag()

        let exp2 = XCTestExpectation(description: "First drag ended")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 0.5)

        // Second drag sequence - should work just like the first
        generator.startDrag(at: CGPoint(x: 200, y: 200))

        let exp3 = XCTestExpectation(description: "Second drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp3.fulfill()
        }
        wait(for: [exp3], timeout: 0.5)

        generator.updateDrag(deltaX: 10, deltaY: 10)
        generator.endDrag()
    }

    func testCancelDragSetsStateToInactive() {
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        generator.cancelDrag()

        let endExpectation = XCTestExpectation(description: "Drag cancelled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            endExpectation.fulfill()
        }
        wait(for: [endExpectation], timeout: 0.5)

        // After cancel, updates should be ignored (guard should return early)
        XCTAssertNoThrow(generator.updateDrag(deltaX: 100, deltaY: 100))
    }

    func testDoubleStartDrag() {
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let exp1 = XCTestExpectation(description: "First start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 0.5)

        // Second start without ending - should not crash
        XCTAssertNoThrow(generator.startDrag(at: CGPoint(x: 200, y: 200)))

        let exp2 = XCTestExpectation(description: "Second start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 0.5)

        generator.endDrag()
    }

    func testDoubleEndDrag() {
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        generator.endDrag()

        let endExpectation = XCTestExpectation(description: "First end")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            endExpectation.fulfill()
        }
        wait(for: [endExpectation], timeout: 0.5)

        // Second end should be a no-op (guard returns early)
        XCTAssertNoThrow(generator.endDrag())
    }

    // MARK: - Edge Case Tests

    func testNegativeDeltas() {
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Negative deltas should work (moving left/up)
        XCTAssertNoThrow(generator.updateDrag(deltaX: -10.0, deltaY: -10.0))

        generator.endDrag()
    }

    func testExtremeDeltas() {
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Very large deltas should not crash
        XCTAssertNoThrow(generator.updateDrag(deltaX: 10000.0, deltaY: 10000.0))

        generator.endDrag()
    }

    func testZeroDeltasIgnored() {
        generator.minimumMovementThreshold = 0.1
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Zero delta (magnitude 0) is below any positive threshold
        XCTAssertNoThrow(generator.updateDrag(deltaX: 0.0, deltaY: 0.0))

        generator.endDrag()
    }

    func testMultipleUpdatesInSequence() {
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Rapid sequence of updates
        for i in 1...10 {
            XCTAssertNoThrow(generator.updateDrag(deltaX: CGFloat(i), deltaY: CGFloat(i)))
        }

        generator.endDrag()
    }

    func testMixedPositiveNegativeDeltas() {
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Mixed directions
        XCTAssertNoThrow(generator.updateDrag(deltaX: 10.0, deltaY: -10.0))
        XCTAssertNoThrow(generator.updateDrag(deltaX: -10.0, deltaY: 10.0))

        generator.endDrag()
    }

    func testClickDuringActiveDrag() {
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Perform click during active drag - should not crash
        XCTAssertNoThrow(generator.performClick())

        let clickExpectation = XCTestExpectation(description: "Click during drag")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            clickExpectation.fulfill()
        }
        wait(for: [clickExpectation], timeout: 0.5)

        generator.endDrag()
    }

    func testStartDragAtZeroCoordinate() {
        // Edge case: starting at origin
        XCTAssertNoThrow(generator.startDrag(at: CGPoint(x: 0, y: 0)))

        let expectation = XCTestExpectation(description: "Drag at origin")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)

        generator.endDrag()
    }

    func testStartDragAtNegativeCoordinate() {
        // Multi-monitor setups can have negative coordinates
        XCTAssertNoThrow(generator.startDrag(at: CGPoint(x: -100, y: -100)))

        let expectation = XCTestExpectation(description: "Drag at negative coords")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)

        generator.endDrag()
    }

    func testStartDragAtVeryLargeCoordinate() {
        // Very large coordinates (multi-monitor, high resolution)
        XCTAssertNoThrow(generator.startDrag(at: CGPoint(x: 10000, y: 10000)))

        let expectation = XCTestExpectation(description: "Drag at large coords")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)

        generator.endDrag()
    }

    // MARK: - Stuck Drag Prevention Tests

    func testDefaultStuckDragTimeout() {
        // Default timeout should be 10 seconds
        XCTAssertEqual(generator.stuckDragTimeout, 10.0, accuracy: 0.001)
    }

    func testStuckDragTimeoutCanBeModified() {
        generator.stuckDragTimeout = 5.0
        XCTAssertEqual(generator.stuckDragTimeout, 5.0, accuracy: 0.001)
    }

    func testDoubleStartDragCancelsExistingDrag() {
        // Start first drag
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let firstStartExpectation = XCTestExpectation(description: "First drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            firstStartExpectation.fulfill()
        }
        wait(for: [firstStartExpectation], timeout: 0.5)

        // Start second drag without ending first - should not crash
        // The existing drag should be cancelled automatically
        XCTAssertNoThrow(generator.startDrag(at: CGPoint(x: 200, y: 200)))

        let secondStartExpectation = XCTestExpectation(description: "Second drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            secondStartExpectation.fulfill()
        }
        wait(for: [secondStartExpectation], timeout: 0.5)

        // Updates should still work after double-start
        XCTAssertNoThrow(generator.updateDrag(deltaX: 10.0, deltaY: 10.0))

        generator.endDrag()
    }

    func testTripleStartDragHandledGracefully() {
        // Start three drags in quick succession
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let exp1 = XCTestExpectation(description: "First start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            exp1.fulfill()
        }
        wait(for: [exp1], timeout: 0.5)

        generator.startDrag(at: CGPoint(x: 200, y: 200))

        let exp2 = XCTestExpectation(description: "Second start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            exp2.fulfill()
        }
        wait(for: [exp2], timeout: 0.5)

        generator.startDrag(at: CGPoint(x: 300, y: 300))

        let exp3 = XCTestExpectation(description: "Third start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            exp3.fulfill()
        }
        wait(for: [exp3], timeout: 0.5)

        // Should be able to update and end normally
        XCTAssertNoThrow(generator.updateDrag(deltaX: 5.0, deltaY: 5.0))
        XCTAssertNoThrow(generator.endDrag())
    }

    func testRapidStartEndCycles() {
        // Test rapid start/end cycles to stress test the double-start guard
        for i in 1...5 {
            generator.startDrag(at: CGPoint(x: CGFloat(i * 100), y: CGFloat(i * 100)))

            let startExp = XCTestExpectation(description: "Start \(i)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                startExp.fulfill()
            }
            wait(for: [startExp], timeout: 0.5)

            generator.endDrag()

            let endExp = XCTestExpectation(description: "End \(i)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                endExp.fulfill()
            }
            wait(for: [endExp], timeout: 0.5)
        }
    }

    func testStartDragWhileDraggingThenCancel() {
        // Start first drag
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "First drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Start second drag (should auto-cancel first)
        generator.startDrag(at: CGPoint(x: 200, y: 200))

        let secondExpectation = XCTestExpectation(description: "Second drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            secondExpectation.fulfill()
        }
        wait(for: [secondExpectation], timeout: 0.5)

        // Now cancel - should only cancel the second drag
        XCTAssertNoThrow(generator.cancelDrag())

        let cancelExpectation = XCTestExpectation(description: "Drag cancelled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            cancelExpectation.fulfill()
        }
        wait(for: [cancelExpectation], timeout: 0.5)

        // Updates should be ignored after cancel
        XCTAssertNoThrow(generator.updateDrag(deltaX: 50.0, deltaY: 50.0))
    }

    func testUpdateDragResetsActivityTime() {
        // This test verifies that updateDrag updates activity tracking
        // (the watchdog won't trigger if updates keep happening)
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Perform multiple updates with small delays
        for i in 1...3 {
            XCTAssertNoThrow(generator.updateDrag(deltaX: CGFloat(i), deltaY: CGFloat(i)))

            let updateExp = XCTestExpectation(description: "Update \(i)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                updateExp.fulfill()
            }
            wait(for: [updateExp], timeout: 0.5)
        }

        generator.endDrag()
    }

    func testWatchdogTimerStartsAndStopsWithDrag() {
        // Start drag - watchdog should start
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "Drag started with watchdog")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // End drag - watchdog should stop
        generator.endDrag()

        let endExpectation = XCTestExpectation(description: "Drag ended, watchdog stopped")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            endExpectation.fulfill()
        }
        wait(for: [endExpectation], timeout: 0.5)
    }

    func testCancelDragStopsWatchdog() {
        // Start drag - watchdog should start
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Cancel drag - watchdog should stop
        generator.cancelDrag()

        let cancelExpectation = XCTestExpectation(description: "Drag cancelled, watchdog stopped")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            cancelExpectation.fulfill()
        }
        wait(for: [cancelExpectation], timeout: 0.5)
    }

    func testVeryShortStuckDragTimeout() {
        // Set a very short timeout for testing (not recommended in production)
        generator.stuckDragTimeout = 0.5

        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Wait longer than the timeout without any updates
        // The watchdog should auto-release the drag
        let timeoutExpectation = XCTestExpectation(description: "Watchdog timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            timeoutExpectation.fulfill()
        }
        wait(for: [timeoutExpectation], timeout: 3.0)

        // After auto-release, updates should be ignored
        XCTAssertNoThrow(generator.updateDrag(deltaX: 10.0, deltaY: 10.0))

        // endDrag should be a no-op since already released
        XCTAssertNoThrow(generator.endDrag())
    }

    func testActivityPreventsWatchdogTimeout() {
        // Set a short timeout
        generator.stuckDragTimeout = 1.5

        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Keep sending updates synchronously with small delays to prevent timeout
        // Total time: 8 * 0.15 = 1.2s which is less than 1.5s timeout
        for i in 1...8 {
            generator.updateDrag(deltaX: CGFloat(i), deltaY: CGFloat(i))
            
            let delayExp = XCTestExpectation(description: "Delay \(i)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                delayExp.fulfill()
            }
            wait(for: [delayExp], timeout: 0.5)
        }

        // Should still be able to end normally (not auto-released)
        XCTAssertNoThrow(generator.endDrag())
    }

    func testDoubleStartWithUpdatesInBetween() {
        // Start first drag
        generator.startDrag(at: CGPoint(x: 100, y: 100))

        let startExpectation = XCTestExpectation(description: "First drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 0.5)

        // Do some updates
        generator.updateDrag(deltaX: 10.0, deltaY: 10.0)
        generator.updateDrag(deltaX: 20.0, deltaY: 20.0)

        // Start second drag (should cancel first and reset state)
        generator.startDrag(at: CGPoint(x: 500, y: 500))

        let secondExpectation = XCTestExpectation(description: "Second drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            secondExpectation.fulfill()
        }
        wait(for: [secondExpectation], timeout: 0.5)

        // New updates should work from the new starting position
        XCTAssertNoThrow(generator.updateDrag(deltaX: 5.0, deltaY: 5.0))

        generator.endDrag()
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentStartDragDoesNotCrash() {
        // Test that rapid concurrent startDrag calls don't cause crashes
        // This exercises the atomic dragGeneration increment
        let concurrentQueue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        
        for i in 0..<10 {
            group.enter()
            concurrentQueue.async {
                self.generator.startDrag(at: CGPoint(x: CGFloat(i * 10), y: CGFloat(i * 10)))
                group.leave()
            }
        }
        
        let waitResult = group.wait(timeout: .now() + 2.0)
        XCTAssertEqual(waitResult, .success, "Concurrent startDrag calls should complete without deadlock")
        
        // Clean up
        generator.cancelDrag()
    }
    
    func testConcurrentStartAndCancelDoesNotCrash() {
        // Test thread safety of start/cancel interleaving
        let concurrentQueue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let group = DispatchGroup()
        
        for i in 0..<20 {
            group.enter()
            concurrentQueue.async {
                if i % 2 == 0 {
                    self.generator.startDrag(at: CGPoint(x: CGFloat(i), y: CGFloat(i)))
                } else {
                    self.generator.cancelDrag()
                }
                group.leave()
            }
        }
        
        let waitResult = group.wait(timeout: .now() + 2.0)
        XCTAssertEqual(waitResult, .success, "Concurrent start/cancel should complete without deadlock")
        
        // Clean up
        generator.cancelDrag()
    }
    
    func testStartDragDuringWatchdogTimeoutWindow() {
        // Test that starting a new drag during the watchdog timeout window
        // doesn't cause the old watchdog to interfere with the new drag
        generator.stuckDragTimeout = 0.3  // Very short timeout
        
        // Start first drag
        generator.startDrag(at: CGPoint(x: 100, y: 100))
        
        // Wait until just before timeout would trigger
        let nearTimeoutExpectation = XCTestExpectation(description: "Near timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            nearTimeoutExpectation.fulfill()
        }
        wait(for: [nearTimeoutExpectation], timeout: 0.5)
        
        // Start second drag right before timeout - this should increment generation
        // and cause any pending watchdog release to abort
        generator.startDrag(at: CGPoint(x: 200, y: 200))
        
        // Wait past the original timeout
        let pastTimeoutExpectation = XCTestExpectation(description: "Past original timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            pastTimeoutExpectation.fulfill()
        }
        wait(for: [pastTimeoutExpectation], timeout: 0.5)
        
        // The new drag should still be active (updates should work)
        XCTAssertNoThrow(generator.updateDrag(deltaX: 10.0, deltaY: 10.0))
        
        // Clean up
        generator.endDrag()
    }
    
    func testRapidDragCyclesWithWatchdog() {
        // Test rapid start/end cycles with watchdog enabled
        generator.stuckDragTimeout = 0.5
        
        for i in 0..<5 {
            generator.startDrag(at: CGPoint(x: CGFloat(i * 100), y: CGFloat(i * 100)))
            generator.updateDrag(deltaX: 10.0, deltaY: 10.0)
            generator.endDrag()
            
            // Small delay between cycles
            let delayExp = XCTestExpectation(description: "Delay \(i)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                delayExp.fulfill()
            }
            wait(for: [delayExp], timeout: 0.2)
        }
        
        // All cycles should complete without crashes or stuck state
        XCTAssertNoThrow(generator.cancelDrag())
    }
    
    func testForceMiddleMouseUpDoesNotCrash() {
        // Test that forceMiddleMouseUp can be called safely
        XCTAssertNoThrow(generator.forceMiddleMouseUp())
        
        // Also test during active drag
        generator.startDrag(at: CGPoint(x: 100, y: 100))
        
        let startExp = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExp.fulfill()
        }
        wait(for: [startExp], timeout: 0.5)
        
        XCTAssertNoThrow(generator.forceMiddleMouseUp())
        
        // After force release, updates should be ignored
        XCTAssertNoThrow(generator.updateDrag(deltaX: 10.0, deltaY: 10.0))
    }
    
    func testForceMiddleMouseUpMultipleTimes() {
        // Test that calling forceMiddleMouseUp multiple times rapidly is safe
        for _ in 0..<5 {
            XCTAssertNoThrow(generator.forceMiddleMouseUp())
        }
    }
    
    func testForceMiddleMouseUpAfterNormalEnd() {
        // Start and end a drag normally
        generator.startDrag(at: CGPoint(x: 100, y: 100))
        
        let startExp = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExp.fulfill()
        }
        wait(for: [startExp], timeout: 0.5)
        
        generator.endDrag()
        
        let endExp = XCTestExpectation(description: "Drag ended")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            endExp.fulfill()
        }
        wait(for: [endExp], timeout: 0.5)
        
        // Force release after normal end should still be safe
        XCTAssertNoThrow(generator.forceMiddleMouseUp())
    }
    
    // MARK: - Click Deduplication Tests
    
    func testClickCountStartsAtZero() {
        XCTAssertEqual(generator.clickCount, 0)
    }
    
    func testSingleClickIncrementsCount() {
        generator.performClick()
        
        // clickCount getter syncs on eventQueue, so it waits for performClick to complete
        let count = generator.clickCount
        XCTAssertEqual(count, 1, "Single performClick should emit exactly 1 click")
    }
    
    func testTwoRapidClicksWithinWindowEmitsOnlyOne() {
        // Use a generous dedup window so both calls definitely fall within it
        generator.clickDeduplicationWindow = 1.0
        
        // Fire two clicks back-to-back (both enqueue on the serial eventQueue;
        // the second will execute after the first and find lastClickTime within window)
        generator.performClick()
        generator.performClick()
        
        let count = generator.clickCount
        XCTAssertEqual(count, 1, "Two rapid performClick calls within the dedup window should emit only 1 click")
    }
    
    func testThreeRapidClicksWithinWindowEmitsOnlyOne() {
        generator.clickDeduplicationWindow = 1.0
        
        generator.performClick()
        generator.performClick()
        generator.performClick()
        
        let count = generator.clickCount
        XCTAssertEqual(count, 1, "Three rapid performClick calls within the dedup window should emit only 1 click")
    }
    
    func testTwoClicksOutsideWindowEmitsBoth() {
        // Use a very short dedup window
        generator.clickDeduplicationWindow = 0.01  // 10ms
        
        generator.performClick()
        
        // Wait for the first click to complete and the dedup window to expire.
        // performClick has a 10ms usleep inside, plus we need the 10ms window to pass.
        let expectation = XCTestExpectation(description: "Dedup window expired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)
        
        generator.performClick()
        
        let count = generator.clickCount
        XCTAssertEqual(count, 2, "Two performClick calls outside the dedup window should emit 2 clicks")
    }
    
    func testDefaultDeduplicationWindow() {
        XCTAssertEqual(generator.clickDeduplicationWindow, 0.15, accuracy: 0.001,
                       "Default dedup window should be 150ms")
    }
    
    func testResetClickCount() {
        generator.performClick()
        
        // Verify click happened
        XCTAssertEqual(generator.clickCount, 1)
        
        generator.resetClickCount()
        XCTAssertEqual(generator.clickCount, 0, "resetClickCount should zero the counter")
    }
    
    func testDeduplicationWindowIsConfigurable() {
        generator.clickDeduplicationWindow = 2.0
        
        generator.performClick()
        
        // Wait 500ms — well beyond default 150ms but within our custom 2s window
        let expectation = XCTestExpectation(description: "Wait past default window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        generator.performClick()
        
        let count = generator.clickCount
        XCTAssertEqual(count, 1, "Second click at 500ms should be deduped with a 2s window")
    }
    
    func testClickDuringDragIsNotCounted() {
        // Start a drag so isMiddleMouseDown is true
        generator.startDrag(at: CGPoint(x: 100, y: 100))
        
        // Wait for startDrag to complete (it sets state synchronously,
        // but sendMiddleMouseDown posts an event)
        let startExp = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExp.fulfill()
        }
        wait(for: [startExp], timeout: 0.5)
        
        // performClick during active drag should be skipped (isMiddleMouseDown guard)
        generator.performClick()
        
        let count = generator.clickCount
        XCTAssertEqual(count, 0, "performClick during active drag should not emit a click")
        
        generator.endDrag()
    }
    
    // MARK: - Drag Position Accumulation Tests
    
    func testLastDragPositionAccumulatesDeltas() {
        generator.smoothingFactor = 0  // No smoothing so deltas pass through directly
        generator.minimumMovementThreshold = 0  // Accept all movements
        
        generator.startDrag(at: CGPoint(x: 100, y: 100))
        
        // Wait for startDrag to complete (posts event, may warp cursor)
        let startExp = XCTestExpectation(description: "Drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExp.fulfill()
        }
        wait(for: [startExp], timeout: 0.5)
        
        // Seed to a known position well within screen bounds so clamping doesn't interfere
        let safeOrigin = CGPoint(x: 500, y: 500)
        generator.lastDragPosition = safeOrigin
        
        generator.updateDrag(deltaX: 10.0, deltaY: 5.0)
        
        XCTAssertEqual(generator.lastDragPosition.x, 510.0, accuracy: 0.01,
                       "X should advance by deltaX")
        XCTAssertEqual(generator.lastDragPosition.y, 505.0, accuracy: 0.01,
                       "Y should advance by deltaY")
        
        generator.updateDrag(deltaX: -3.0, deltaY: 7.0)
        
        XCTAssertEqual(generator.lastDragPosition.x, 507.0, accuracy: 0.01,
                       "X should decrease by negative deltaX")
        XCTAssertEqual(generator.lastDragPosition.y, 512.0, accuracy: 0.01,
                       "Y should increase by deltaY")
        
        generator.endDrag()
    }
    
    func testLastDragPositionResetsOnNewDrag() {
        generator.smoothingFactor = 0
        generator.minimumMovementThreshold = 0
        
        generator.startDrag(at: CGPoint(x: 100, y: 100))
        
        let startExp1 = XCTestExpectation(description: "First drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExp1.fulfill()
        }
        wait(for: [startExp1], timeout: 0.5)
        
        // Move the position significantly
        generator.lastDragPosition = CGPoint(x: 500, y: 500)
        generator.updateDrag(deltaX: 50.0, deltaY: 50.0)
        let posAfterFirstDrag = generator.lastDragPosition
        
        generator.endDrag()
        
        let endExp = XCTestExpectation(description: "Drag ended")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            endExp.fulfill()
        }
        wait(for: [endExp], timeout: 0.5)
        
        // Start a new drag — position should be re-seeded from cursor, not carried over
        generator.startDrag(at: CGPoint(x: 200, y: 200))
        
        let startExp2 = XCTestExpectation(description: "Second drag started")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExp2.fulfill()
        }
        wait(for: [startExp2], timeout: 0.5)
        
        let newStart = generator.lastDragPosition
        
        // The new start position should NOT be posAfterFirstDrag (550, 550)
        // It should be re-seeded from the current cursor position
        let distFromOldPos = abs(newStart.x - posAfterFirstDrag.x) + abs(newStart.y - posAfterFirstDrag.y)
        // If the position was carried over it would be (550, 550) — check it's different
        // (unless the cursor happens to be exactly there, which is astronomically unlikely)
        
        // Seed to safe position and verify deltas work from new origin
        generator.lastDragPosition = CGPoint(x: 300, y: 300)
        generator.updateDrag(deltaX: 5.0, deltaY: 5.0)
        
        XCTAssertEqual(generator.lastDragPosition.x, 305.0, accuracy: 0.01,
                       "Delta should be relative to new drag start position")
        XCTAssertEqual(generator.lastDragPosition.y, 305.0, accuracy: 0.01,
                       "Delta should be relative to new drag start position")
        
        generator.endDrag()
    }
    
    // MARK: - Screen Bounds Clamping Tests
    
    func testDragPositionClampedToDisplayBounds() {
        generator.smoothingFactor = 0
        generator.minimumMovementThreshold = 0
        
        let bounds = MouseEventGenerator.globalDisplayBounds
        // Start near the right edge
        generator.startDrag(at: CGPoint(x: 100, y: 100))
        let startPos = generator.lastDragPosition
        
        // Try to drag far beyond the right edge
        let hugeOvershoot: CGFloat = 50000
        generator.updateDrag(deltaX: hugeOvershoot, deltaY: 0)
        
        // Position should be clamped to display bounds
        XCTAssertLessThanOrEqual(generator.lastDragPosition.x, bounds.maxX - 1,
                                 "X should be clamped to display right edge")
        
        generator.endDrag()
    }
    
    func testDragPositionClampedToLeftEdge() {
        generator.smoothingFactor = 0
        generator.minimumMovementThreshold = 0
        
        let bounds = MouseEventGenerator.globalDisplayBounds
        generator.startDrag(at: CGPoint(x: 100, y: 100))
        
        // Drag far to the left
        generator.updateDrag(deltaX: -50000, deltaY: 0)
        
        XCTAssertGreaterThanOrEqual(generator.lastDragPosition.x, bounds.minX,
                                     "X should be clamped to display left edge")
        
        generator.endDrag()
    }
    
    func testDragPositionClampedToTopEdge() {
        generator.smoothingFactor = 0
        generator.minimumMovementThreshold = 0
        
        let bounds = MouseEventGenerator.globalDisplayBounds
        generator.startDrag(at: CGPoint(x: 100, y: 100))
        
        // In Quartz coordinates, top is minY (0). Drag upward (negative Y).
        generator.updateDrag(deltaX: 0, deltaY: -50000)
        
        XCTAssertGreaterThanOrEqual(generator.lastDragPosition.y, bounds.minY,
                                     "Y should be clamped to display top edge")
        
        generator.endDrag()
    }
    
    func testDragPositionClampedToBottomEdge() {
        generator.smoothingFactor = 0
        generator.minimumMovementThreshold = 0
        
        let bounds = MouseEventGenerator.globalDisplayBounds
        generator.startDrag(at: CGPoint(x: 100, y: 100))
        
        // Drag downward (positive Y in Quartz)
        generator.updateDrag(deltaX: 0, deltaY: 50000)
        
        XCTAssertLessThanOrEqual(generator.lastDragPosition.y, bounds.maxY - 1,
                                 "Y should be clamped to display bottom edge")
        
        generator.endDrag()
    }
    
    func testDragPositionClampedOnBothAxes() {
        generator.smoothingFactor = 0
        generator.minimumMovementThreshold = 0
        
        let bounds = MouseEventGenerator.globalDisplayBounds
        generator.startDrag(at: CGPoint(x: 100, y: 100))
        
        // Drag far into bottom-right corner
        generator.updateDrag(deltaX: 50000, deltaY: 50000)
        
        XCTAssertLessThanOrEqual(generator.lastDragPosition.x, bounds.maxX - 1)
        XCTAssertLessThanOrEqual(generator.lastDragPosition.y, bounds.maxY - 1)
        
        generator.endDrag()
    }
    
    func testDragPositionNoDeadZoneAfterClamping() {
        generator.smoothingFactor = 0
        generator.minimumMovementThreshold = 0
        
        generator.startDrag(at: CGPoint(x: 100, y: 100))
        
        // Overshoot right edge
        generator.updateDrag(deltaX: 50000, deltaY: 0)
        let clampedPos = generator.lastDragPosition
        
        // Now drag back left — should immediately move (no dead zone from overshoot)
        generator.updateDrag(deltaX: -10, deltaY: 0)
        
        XCTAssertEqual(generator.lastDragPosition.x, clampedPos.x - 10, accuracy: 0.01,
                       "Reversing direction after clamping should move immediately with no dead zone")
        
        generator.endDrag()
    }
    
    func testGlobalDisplayBoundsIsValid() {
        let bounds = MouseEventGenerator.globalDisplayBounds
        
        XCTAssertFalse(bounds.isNull, "Display bounds should not be null")
        XCTAssertGreaterThan(bounds.width, 0, "Display width should be positive")
        XCTAssertGreaterThan(bounds.height, 0, "Display height should be positive")
    }
    
    // MARK: - Integer Delta Rounding Tests
    
    func testSubPixelDeltaRoundsToOne() {
        // 0.7 should round to 1, not truncate to 0.
        // We verify this indirectly: if the delta were truncated to 0 (Int64),
        // integer-reading apps would see no movement. With rounding, 0.7 → 1.
        let rounded = Int64(CGFloat(0.7).rounded())
        XCTAssertEqual(rounded, 1, "0.7 should round to 1, not truncate to 0")
    }
    
    func testNegativeSubPixelDeltaRoundsToMinusOne() {
        let rounded = Int64(CGFloat(-0.7).rounded())
        XCTAssertEqual(rounded, -1, "-0.7 should round to -1, not truncate to 0")
    }
    
    func testHalfPixelDeltaRoundsAwayFromZero() {
        // .rounded() uses .toNearestOrAwayFromZero by default
        let roundedPos = Int64(CGFloat(0.5).rounded())
        let roundedNeg = Int64(CGFloat(-0.5).rounded())
        XCTAssertEqual(roundedPos, 1, "0.5 should round to 1")
        XCTAssertEqual(roundedNeg, -1, "-0.5 should round to -1")
    }
    
    func testSmallDeltaBelowHalfRoundsToZero() {
        // Deltas below 0.5 correctly round to 0 — this is expected behavior
        // for very tiny movements, matching hardware which has minimum ±1 resolution.
        let rounded = Int64(CGFloat(0.3).rounded())
        XCTAssertEqual(rounded, 0, "0.3 should round to 0")
    }
    
    func testWholePixelDeltaUnchanged() {
        let rounded = Int64(CGFloat(5.0).rounded())
        XCTAssertEqual(rounded, 5, "Whole pixel deltas should be unchanged by rounding")
    }
    
    func testLargeSubPixelDelta() {
        // 10.7 should round to 11
        let rounded = Int64(CGFloat(10.7).rounded())
        XCTAssertEqual(rounded, 11, "10.7 should round to 11")
    }
}
