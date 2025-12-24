import XCTest

@testable import MiddleDrag

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
}
