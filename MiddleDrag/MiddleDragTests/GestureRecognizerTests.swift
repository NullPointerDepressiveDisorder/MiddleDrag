import CoreGraphics
import XCTest

@testable import MiddleDrag

final class GestureRecognizerTests: XCTestCase {

    var recognizer: GestureRecognizer!
    var mockDelegate: MockGestureRecognizerDelegate!

    override func setUp() {
        super.setUp()
        recognizer = GestureRecognizer()
        mockDelegate = MockGestureRecognizerDelegate()
        recognizer.delegate = mockDelegate
    }

    override func tearDown() {
        recognizer = nil
        mockDelegate = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    /// Creates a valid MTTouch struct with the given position and properties
    private func createTouch(
        x: Float, y: Float, zTotal: Float = 0.5, state: UInt32 = 4
    ) -> MTTouch {
        let position = MTPoint(x: x, y: y)
        let velocity = MTPoint(x: 0, y: 0)
        let normalizedVector = MTVector(position: position, velocity: velocity)
        let absoluteVector = MTVector(position: position, velocity: velocity)

        return MTTouch(
            frame: 0,
            timestamp: 0,
            pathIndex: 0,
            state: state,
            fingerID: 0,
            handID: 0,
            normalizedVector: normalizedVector,
            zTotal: zTotal,
            field9: 0,
            angle: 0,
            majorAxis: 0.1,
            minorAxis: 0.1,
            absoluteVector: absoluteVector,
            field14: 0,
            field15: 0,
            zDensity: 0
        )
    }

    /// Creates touch data in memory and returns pointer + cleanup closure
    private func createTouchData(touches: [MTTouch]) -> (UnsafeMutableRawPointer, Int, () -> Void) {
        let count = touches.count
        let pointer = UnsafeMutablePointer<MTTouch>.allocate(capacity: count)

        for (index, touch) in touches.enumerated() {
            pointer[index] = touch
        }

        let rawPointer = UnsafeMutableRawPointer(pointer)
        let cleanup = { pointer.deallocate() }

        return (rawPointer, count, cleanup)
    }

    // MARK: - Modifier Key Requirement Tests

    func testModifierKeyRequirement_CancelsGestureWhenModifierNotHeld() {
        // Configure to require shift key
        recognizer.configuration.requireModifierKey = true
        recognizer.configuration.modifierKeyType = .shift

        // Create 3 valid touches
        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = createTouchData(touches: touches)
        defer { cleanup() }

        // Process with shift held - gesture should start
        recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: .maskShift)
        XCTAssertTrue(mockDelegate.didStartCalled, "Gesture should start when modifier is held")

        // Reset delegate tracking
        mockDelegate.reset()

        // Now process without shift held - should cancel
        recognizer.processTouches(pointer, count: count, timestamp: 0.1, modifierFlags: [])
        XCTAssertTrue(
            mockDelegate.didCancelCalled || mockDelegate.didCancelDraggingCalled,
            "Gesture should be cancelled when modifier is released")
    }

    func testModifierKeyRequirement_AllowsGestureWhenModifierHeld() {
        recognizer.configuration.requireModifierKey = true
        recognizer.configuration.modifierKeyType = .option

        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = createTouchData(touches: touches)
        defer { cleanup() }

        // Process with option key held (maskAlternate)
        recognizer.processTouches(
            pointer, count: count, timestamp: 0.0, modifierFlags: .maskAlternate)

        XCTAssertTrue(
            mockDelegate.didStartCalled, "Gesture should start when correct modifier is held")
    }

    func testModifierKeyRequirement_AllModifierTypes() {
        let modifierTests: [(ModifierKeyType, CGEventFlags)] = [
            (.shift, .maskShift),
            (.control, .maskControl),
            (.option, .maskAlternate),
            (.command, .maskCommand),
        ]

        for (modifierType, eventFlag) in modifierTests {
            // Reset for each test
            recognizer.reset()
            mockDelegate.reset()

            recognizer.configuration.requireModifierKey = true
            recognizer.configuration.modifierKeyType = modifierType

            let touches = [
                createTouch(x: 0.3, y: 0.5),
                createTouch(x: 0.5, y: 0.5),
                createTouch(x: 0.7, y: 0.5),
            ]
            let (pointer, count, cleanup) = createTouchData(touches: touches)
            defer { cleanup() }

            recognizer.processTouches(
                pointer, count: count, timestamp: 0.0, modifierFlags: eventFlag)

            XCTAssertTrue(
                mockDelegate.didStartCalled,
                "Gesture should start with \(modifierType) modifier held")
        }
    }

    func testModifierKeyRequirement_DisabledAllowsAllGestures() {
        recognizer.configuration.requireModifierKey = false  // Disabled

        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = createTouchData(touches: touches)
        defer { cleanup() }

        // Process with no modifiers
        recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        XCTAssertTrue(
            mockDelegate.didStartCalled,
            "Gesture should start without modifier when requirement is disabled")
    }

    // MARK: - Exclusion Zone Tests

    func testExclusionZone_FiltersTouchesInExclusionZone() {
        recognizer.configuration.exclusionZoneEnabled = true
        recognizer.configuration.exclusionZoneSize = 0.2  // Bottom 20%

        // All 3 touches are in the exclusion zone (y < 0.2)
        let touches = [
            createTouch(x: 0.3, y: 0.1),  // y=0.1 < 0.2, filtered
            createTouch(x: 0.5, y: 0.15),  // y=0.15 < 0.2, filtered
            createTouch(x: 0.7, y: 0.05),  // y=0.05 < 0.2, filtered
        ]
        let (pointer, count, cleanup) = createTouchData(touches: touches)
        defer { cleanup() }

        recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        // All touches filtered = no valid 3-finger gesture
        XCTAssertFalse(
            mockDelegate.didStartCalled, "Gesture should not start when all touches are filtered")
    }

    func testExclusionZone_AcceptsTouchesAboveZone() {
        recognizer.configuration.exclusionZoneEnabled = true
        recognizer.configuration.exclusionZoneSize = 0.2

        // All 3 touches are above the exclusion zone (y >= 0.2)
        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.6),
            createTouch(x: 0.7, y: 0.7),
        ]
        let (pointer, count, cleanup) = createTouchData(touches: touches)
        defer { cleanup() }

        recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        XCTAssertTrue(
            mockDelegate.didStartCalled,
            "Gesture should start when touches are above exclusion zone"
        )
    }

    func testExclusionZone_DisabledAcceptsAllTouches() {
        recognizer.configuration.exclusionZoneEnabled = false  // Disabled

        // Touches in what would be the exclusion zone
        let touches = [
            createTouch(x: 0.3, y: 0.1),
            createTouch(x: 0.5, y: 0.1),
            createTouch(x: 0.7, y: 0.1),
        ]
        let (pointer, count, cleanup) = createTouchData(touches: touches)
        defer { cleanup() }

        recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        XCTAssertTrue(
            mockDelegate.didStartCalled,
            "Gesture should start with low Y touches when exclusion zone is disabled")
    }

    // MARK: - Contact Size Filter Tests

    func testContactSizeFilter_FiltersLargeContacts() {
        recognizer.configuration.contactSizeFilterEnabled = true
        recognizer.configuration.maxContactSize = 1.0

        // All contacts are too large (zTotal > 1.0)
        let touches = [
            createTouch(x: 0.3, y: 0.5, zTotal: 2.0),  // Too large
            createTouch(x: 0.5, y: 0.5, zTotal: 1.5),  // Too large
            createTouch(x: 0.7, y: 0.5, zTotal: 3.0),  // Too large
        ]
        let (pointer, count, cleanup) = createTouchData(touches: touches)
        defer { cleanup() }

        recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        XCTAssertFalse(
            mockDelegate.didStartCalled,
            "Gesture should not start when all contacts are too large (palm rejection)")
    }

    func testContactSizeFilter_AcceptsNormalContacts() {
        recognizer.configuration.contactSizeFilterEnabled = true
        recognizer.configuration.maxContactSize = 1.5

        // All contacts are within acceptable range
        let touches = [
            createTouch(x: 0.3, y: 0.5, zTotal: 0.5),
            createTouch(x: 0.5, y: 0.5, zTotal: 0.8),
            createTouch(x: 0.7, y: 0.5, zTotal: 1.0),
        ]
        let (pointer, count, cleanup) = createTouchData(touches: touches)
        defer { cleanup() }

        recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        XCTAssertTrue(
            mockDelegate.didStartCalled,
            "Gesture should start when all contacts are within size limit")
    }

    func testContactSizeFilter_DisabledAcceptsAllContacts() {
        recognizer.configuration.contactSizeFilterEnabled = false  // Disabled

        // Very large contacts that would normally be filtered
        let touches = [
            createTouch(x: 0.3, y: 0.5, zTotal: 10.0),
            createTouch(x: 0.5, y: 0.5, zTotal: 15.0),
            createTouch(x: 0.7, y: 0.5, zTotal: 20.0),
        ]
        let (pointer, count, cleanup) = createTouchData(touches: touches)
        defer { cleanup() }

        recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        XCTAssertTrue(
            mockDelegate.didStartCalled,
            "Gesture should start with large contacts when filter is disabled")
    }

    // MARK: - Partial Filter Tests (Some touches filtered, some pass)

    func testExclusionZone_PartialFiltering_FiveTouchesThreePass() {
        recognizer.configuration.exclusionZoneEnabled = true
        recognizer.configuration.exclusionZoneSize = 0.2  // Bottom 20%

        // 5 touches: 2 in exclusion zone, 3 above - should activate gesture
        let touches = [
            createTouch(x: 0.2, y: 0.1),  // Filtered (y < 0.2)
            createTouch(x: 0.3, y: 0.5),  // Passes
            createTouch(x: 0.5, y: 0.6),  // Passes
            createTouch(x: 0.7, y: 0.5),  // Passes
            createTouch(x: 0.8, y: 0.05),  // Filtered (y < 0.2)
        ]
        let (pointer, count, cleanup) = createTouchData(touches: touches)
        defer { cleanup() }

        recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        XCTAssertTrue(
            mockDelegate.didStartCalled,
            "Gesture should start when 5 touches detected but only 3 pass exclusion zone filter")
    }

    func testContactSizeFilter_PartialFiltering_FiveTouchesThreePass() {
        recognizer.configuration.contactSizeFilterEnabled = true
        recognizer.configuration.maxContactSize = 1.5

        // 5 touches: 2 too large (palm), 3 normal - should activate gesture
        let touches = [
            createTouch(x: 0.2, y: 0.5, zTotal: 3.0),  // Filtered (too large)
            createTouch(x: 0.3, y: 0.5, zTotal: 0.5),  // Passes
            createTouch(x: 0.5, y: 0.5, zTotal: 0.8),  // Passes
            createTouch(x: 0.7, y: 0.5, zTotal: 1.0),  // Passes
            createTouch(x: 0.8, y: 0.5, zTotal: 5.0),  // Filtered (too large)
        ]
        let (pointer, count, cleanup) = createTouchData(touches: touches)
        defer { cleanup() }

        recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        XCTAssertTrue(
            mockDelegate.didStartCalled,
            "Gesture should start when 5 touches detected but only 3 pass contact size filter")
    }

    func testCombinedFilters_PartialFiltering_SixTouchesThreePass() {
        recognizer.configuration.exclusionZoneEnabled = true
        recognizer.configuration.exclusionZoneSize = 0.2
        recognizer.configuration.contactSizeFilterEnabled = true
        recognizer.configuration.maxContactSize = 1.5

        // 6 touches: 2 in exclusion zone, 1 too large, 3 pass both - should activate
        let touches = [
            createTouch(x: 0.1, y: 0.1, zTotal: 0.5),  // Filtered (exclusion zone)
            createTouch(x: 0.2, y: 0.5, zTotal: 3.0),  // Filtered (too large)
            createTouch(x: 0.3, y: 0.5, zTotal: 0.5),  // Passes both
            createTouch(x: 0.5, y: 0.6, zTotal: 0.8),  // Passes both
            createTouch(x: 0.7, y: 0.5, zTotal: 1.0),  // Passes both
            createTouch(x: 0.9, y: 0.05, zTotal: 0.5),  // Filtered (exclusion zone)
        ]
        let (pointer, count, cleanup) = createTouchData(touches: touches)
        defer { cleanup() }

        recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        XCTAssertTrue(
            mockDelegate.didStartCalled,
            "Gesture should start when 6 touches detected but only 3 pass all filters")
    }

    func testPartialFiltering_InsufficientRemainingTouches() {
        recognizer.configuration.exclusionZoneEnabled = true
        recognizer.configuration.exclusionZoneSize = 0.2

        // 4 touches: 2 filtered, only 2 remain - should NOT activate (need exactly 3)
        let touches = [
            createTouch(x: 0.2, y: 0.1),  // Filtered (exclusion zone)
            createTouch(x: 0.3, y: 0.5),  // Passes
            createTouch(x: 0.7, y: 0.5),  // Passes
            createTouch(x: 0.8, y: 0.05),  // Filtered (exclusion zone)
        ]
        let (pointer, count, cleanup) = createTouchData(touches: touches)
        defer { cleanup() }

        recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        XCTAssertFalse(
            mockDelegate.didStartCalled,
            "Gesture should not start when only 2 touches remain after filtering")
    }

    // MARK: - Combined Filter Tests

    func testCombinedFilters_AllFiltersWorking() {
        recognizer.configuration.exclusionZoneEnabled = true
        recognizer.configuration.exclusionZoneSize = 0.2
        recognizer.configuration.contactSizeFilterEnabled = true
        recognizer.configuration.maxContactSize = 1.5
        recognizer.configuration.requireModifierKey = true
        recognizer.configuration.modifierKeyType = .shift

        // Valid touches: above exclusion zone, normal size
        let touches = [
            createTouch(x: 0.3, y: 0.5, zTotal: 0.5),
            createTouch(x: 0.5, y: 0.5, zTotal: 0.8),
            createTouch(x: 0.7, y: 0.5, zTotal: 1.0),
        ]
        let (pointer, count, cleanup) = createTouchData(touches: touches)
        defer { cleanup() }

        // Process with shift held
        recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: .maskShift)

        XCTAssertTrue(
            mockDelegate.didStartCalled, "Gesture should start when all filters pass")
    }
}

// MARK: - Mock Delegate

/// Mock delegate to track gesture recognizer callbacks
class MockGestureRecognizerDelegate: GestureRecognizerDelegate {
    var didStartCalled = false
    var didTapCalled = false
    var didBeginDraggingCalled = false
    var didUpdateDraggingCalled = false
    var didEndDraggingCalled = false
    var didCancelCalled = false
    var didCancelDraggingCalled = false

    var lastStartPosition: MTPoint?
    var lastGestureData: GestureData?

    func reset() {
        didStartCalled = false
        didTapCalled = false
        didBeginDraggingCalled = false
        didUpdateDraggingCalled = false
        didEndDraggingCalled = false
        didCancelCalled = false
        didCancelDraggingCalled = false
        lastStartPosition = nil
        lastGestureData = nil
    }

    func gestureRecognizerDidStart(_ recognizer: GestureRecognizer, at position: MTPoint) {
        didStartCalled = true
        lastStartPosition = position
    }

    func gestureRecognizerDidTap(_ recognizer: GestureRecognizer) {
        didTapCalled = true
    }

    func gestureRecognizerDidBeginDragging(_ recognizer: GestureRecognizer) {
        didBeginDraggingCalled = true
    }

    func gestureRecognizerDidUpdateDragging(_ recognizer: GestureRecognizer, with data: GestureData)
    {
        didUpdateDraggingCalled = true
        lastGestureData = data
    }

    func gestureRecognizerDidEndDragging(_ recognizer: GestureRecognizer) {
        didEndDraggingCalled = true
    }

    func gestureRecognizerDidCancel(_ recognizer: GestureRecognizer) {
        didCancelCalled = true
    }

    func gestureRecognizerDidCancelDragging(_ recognizer: GestureRecognizer) {
        didCancelDraggingCalled = true
    }
}
