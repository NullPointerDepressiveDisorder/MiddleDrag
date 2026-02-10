import XCTest

@testable import MiddleDragCore

final class TouchModelsTests: XCTestCase {

    // MARK: - MTPoint Tests

    func testMTPointDistance() {
        let point1 = MTPoint(x: 0.0, y: 0.0)
        let point2 = MTPoint(x: 3.0, y: 4.0)

        let distance = point1.distance(to: point2)

        XCTAssertEqual(
            distance, 5.0, accuracy: 0.001, "Should calculate Euclidean distance (3-4-5 triangle)")
    }

    func testMTPointDistanceToSelf() {
        let point = MTPoint(x: 5.0, y: 10.0)

        let distance = point.distance(to: point)

        XCTAssertEqual(distance, 0.0, accuracy: 0.001, "Distance to self should be zero")
    }

    func testMTPointMidpoint() {
        let point1 = MTPoint(x: 0.0, y: 0.0)
        let point2 = MTPoint(x: 10.0, y: 20.0)

        let mid = point1.midpoint(with: point2)

        XCTAssertEqual(mid.x, 5.0, accuracy: 0.001)
        XCTAssertEqual(mid.y, 10.0, accuracy: 0.001)
    }

    func testMTPointMidpointWithSamePoint() {
        let point = MTPoint(x: 5.0, y: 10.0)

        let mid = point.midpoint(with: point)

        XCTAssertEqual(mid.x, point.x, accuracy: 0.001)
        XCTAssertEqual(mid.y, point.y, accuracy: 0.001)
    }

    func testMTPointMidpointWithNegativeCoordinates() {
        let point1 = MTPoint(x: -10.0, y: -20.0)
        let point2 = MTPoint(x: 10.0, y: 20.0)

        let mid = point1.midpoint(with: point2)

        XCTAssertEqual(mid.x, 0.0, accuracy: 0.001)
        XCTAssertEqual(mid.y, 0.0, accuracy: 0.001)
    }

    // MARK: - TouchState Tests

    func testTouchStateIsTouching() {
        XCTAssertFalse(TouchState.notTracking.isTouching)
        XCTAssertFalse(TouchState.starting.isTouching)
        XCTAssertFalse(TouchState.hovering.isTouching)
        XCTAssertTrue(TouchState.touching.isTouching)
        XCTAssertTrue(TouchState.active.isTouching)
        XCTAssertFalse(TouchState.lifting.isTouching)
        XCTAssertFalse(TouchState.lingering.isTouching)
        XCTAssertFalse(TouchState.outOfRange.isTouching)
    }

    func testTouchStateShouldTrack() {
        XCTAssertFalse(TouchState.notTracking.shouldTrack)
        XCTAssertFalse(TouchState.starting.shouldTrack)
        XCTAssertFalse(TouchState.hovering.shouldTrack)
        XCTAssertTrue(TouchState.touching.shouldTrack)
        XCTAssertTrue(TouchState.active.shouldTrack)
        XCTAssertFalse(TouchState.lifting.shouldTrack)
        XCTAssertFalse(TouchState.lingering.shouldTrack)
        XCTAssertFalse(TouchState.outOfRange.shouldTrack)
    }

    func testTouchStateRawValues() {
        XCTAssertEqual(TouchState.notTracking.rawValue, 0)
        XCTAssertEqual(TouchState.starting.rawValue, 1)
        XCTAssertEqual(TouchState.hovering.rawValue, 2)
        XCTAssertEqual(TouchState.touching.rawValue, 3)
        XCTAssertEqual(TouchState.active.rawValue, 4)
        XCTAssertEqual(TouchState.lifting.rawValue, 5)
        XCTAssertEqual(TouchState.lingering.rawValue, 6)
        XCTAssertEqual(TouchState.outOfRange.rawValue, 7)
    }

    // MARK: - TrackedFinger Tests

    func testTrackedFingerIsActiveWhenTouching() {
        let finger = TrackedFinger(
            id: 1,
            position: MTPoint(x: 0.5, y: 0.5),
            velocity: MTPoint(x: 0.0, y: 0.0),
            pressure: 1.0,
            timestamp: Date().timeIntervalSince1970,
            state: TouchState.touching.rawValue
        )

        XCTAssertTrue(finger.isActive)
        XCTAssertEqual(finger.touchState, .touching)
    }

    func testTrackedFingerIsActiveWhenActive() {
        let finger = TrackedFinger(
            id: 1,
            position: MTPoint(x: 0.5, y: 0.5),
            velocity: MTPoint(x: 0.0, y: 0.0),
            pressure: 1.0,
            timestamp: Date().timeIntervalSince1970,
            state: TouchState.active.rawValue
        )

        XCTAssertTrue(finger.isActive)
        XCTAssertEqual(finger.touchState, .active)
    }

    func testTrackedFingerIsNotActiveWhenLifting() {
        let finger = TrackedFinger(
            id: 1,
            position: MTPoint(x: 0.5, y: 0.5),
            velocity: MTPoint(x: 0.0, y: 0.0),
            pressure: 0.0,
            timestamp: Date().timeIntervalSince1970,
            state: TouchState.lifting.rawValue
        )

        XCTAssertFalse(finger.isActive)
        XCTAssertEqual(finger.touchState, .lifting)
    }

    func testTrackedFingerWithUnknownState() {
        let finger = TrackedFinger(
            id: 1,
            position: MTPoint(x: 0.5, y: 0.5),
            velocity: MTPoint(x: 0.0, y: 0.0),
            pressure: 1.0,
            timestamp: Date().timeIntervalSince1970,
            state: 99  // Unknown state
        )

        XCTAssertNil(finger.touchState)
        XCTAssertFalse(finger.isActive)
    }
}
