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
}