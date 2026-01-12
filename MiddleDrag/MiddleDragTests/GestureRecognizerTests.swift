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
            unsafe pointer[index] = touch
        }

        let rawPointer = UnsafeMutableRawPointer(pointer)
        let cleanup = { unsafe pointer.deallocate() }

        return unsafe (rawPointer, count, cleanup)
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
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        // Process with shift held - gesture should start
        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: .maskShift)
        XCTAssertTrue(mockDelegate.didStartCalled, "Gesture should start when modifier is held")

        // Reset delegate tracking
        mockDelegate.reset()

        // Now process without shift held - should cancel
        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.1, modifierFlags: [])
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
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        // Process with option key held (maskAlternate)
        unsafe recognizer.processTouches(
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
            let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
            defer { cleanup() }

            unsafe recognizer.processTouches(
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
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        // Process with no modifiers
        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

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
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

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
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

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
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

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
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

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
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

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
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

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
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

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
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

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
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

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
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

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
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        // Process with shift held
        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: .maskShift)

        XCTAssertTrue(
            mockDelegate.didStartCalled, "Gesture should start when all filters pass")
    }

    // MARK: - State Transition Tests

    func testInitialStateIsIdle() {
        XCTAssertEqual(recognizer.state, .idle, "Initial state should be idle")
    }

    func testStateTransitionToTap() {
        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        // Start gesture
        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        XCTAssertEqual(
            recognizer.state, .possibleTap, "State should be possibleTap after initial touch")
    }

    func testStateTransitionToDragging() {
        // Set low move threshold for easier testing
        recognizer.configuration.moveThreshold = 0.01

        let touches1 = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer1, count1, cleanup1) = unsafe createTouchData(touches: touches1)
        defer { cleanup1() }

        // Start gesture
        unsafe recognizer.processTouches(pointer1, count: count1, timestamp: 0.0, modifierFlags: [])
        XCTAssertEqual(recognizer.state, .possibleTap)

        // Move fingers (small delta to avoid centroid jump rejection > 0.03)
        let touches2 = [
            createTouch(x: 0.32, y: 0.52),
            createTouch(x: 0.52, y: 0.52),
            createTouch(x: 0.72, y: 0.52),
        ]
        let (pointer2, count2, cleanup2) = unsafe createTouchData(touches: touches2)
        defer { cleanup2() }

        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.1, modifierFlags: [])

        XCTAssertEqual(
            recognizer.state, .dragging, "State should transition to dragging after movement")
    }

    func testStateTransitionFromDragToIdle() {
        recognizer.configuration.moveThreshold = 0.01

        // Start with 3 fingers
        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        // Move to trigger drag (small delta to avoid centroid jump rejection > 0.03)
        let touches2 = [
            createTouch(x: 0.32, y: 0.52),
            createTouch(x: 0.52, y: 0.52),
            createTouch(x: 0.72, y: 0.52),
        ]
        let (pointer2, count2, cleanup2) = unsafe createTouchData(touches: touches2)
        defer { cleanup2() }

        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.1, modifierFlags: [])
        XCTAssertEqual(recognizer.state, .dragging)

        // Lift all fingers (empty touch array) - need 2 frames for stable state
        let emptyTouches: [MTTouch] = []
        let (emptyPointer, _, emptyCleanup) = unsafe createTouchData(touches: emptyTouches)
        defer { emptyCleanup() }

        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.2, modifierFlags: [])
        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.3, modifierFlags: [])

        XCTAssertEqual(recognizer.state, .idle, "State should return to idle after lifting fingers")
    }

    // MARK: - Tap Gesture Tests

    func testTapDetectedWithQuickRelease() {
        recognizer.configuration.tapThreshold = 0.3  // 300ms

        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        // Start gesture
        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        // Lift fingers quickly (before tap threshold)
        let emptyTouches: [MTTouch] = []
        let (emptyPointer, _, emptyCleanup) = unsafe createTouchData(touches: emptyTouches)
        defer { emptyCleanup() }

        // Two frames to trigger stable state
        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.1, modifierFlags: [])
        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.15, modifierFlags: [])

        XCTAssertTrue(mockDelegate.didTapCalled, "Tap should be detected for quick release")
    }

    func testTapNotDetectedWhenHeldTooLong() {
        recognizer.configuration.tapThreshold = 0.2  // 200ms

        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        // Start gesture
        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        // Lift fingers after tap threshold exceeded
        let emptyTouches: [MTTouch] = []
        let (emptyPointer, _, emptyCleanup) = unsafe createTouchData(touches: emptyTouches)
        defer { emptyCleanup() }

        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.5, modifierFlags: [])
        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.6, modifierFlags: [])

        XCTAssertFalse(mockDelegate.didTapCalled, "Tap should not be detected when held too long")
    }

    func testTapNotDetectedWhenHeldBeyondMaxDuration() {
        // Configure tap threshold high, but max hold duration low
        recognizer.configuration.tapThreshold = 1.0  // 1 second
        recognizer.configuration.maxTapHoldDuration = 0.3  // 300ms max hold

        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        // Start gesture
        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        // Lift fingers after max hold duration exceeded but within tap threshold
        let emptyTouches: [MTTouch] = []
        let (emptyPointer, _, emptyCleanup) = unsafe createTouchData(touches: emptyTouches)
        defer { emptyCleanup() }

        // 0.5 seconds is within tap threshold (1.0s) but exceeds max hold (0.3s)
        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.5, modifierFlags: [])
        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.6, modifierFlags: [])

        XCTAssertFalse(
            mockDelegate.didTapCalled,
            "Tap should not be detected when held beyond max hold duration")
    }

    func testTapDetectedWhenWithinMaxDuration() {
        // Configure both tap threshold and max hold duration
        recognizer.configuration.tapThreshold = 0.5  // 500ms
        recognizer.configuration.maxTapHoldDuration = 0.5  // 500ms max hold

        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        // Start gesture
        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        // Lift fingers within both thresholds
        let emptyTouches: [MTTouch] = []
        let (emptyPointer, _, emptyCleanup) = unsafe createTouchData(touches: emptyTouches)
        defer { emptyCleanup() }

        // 0.1 seconds is within both tap threshold and max hold
        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.1, modifierFlags: [])
        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.15, modifierFlags: [])

        XCTAssertTrue(
            mockDelegate.didTapCalled, "Tap should be detected when within max hold duration")
    }

    func testTapNotDetectedWhenMovingTooMuch() {
        recognizer.configuration.tapThreshold = 0.5
        recognizer.configuration.moveThreshold = 0.01  // Very low threshold

        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        // Start gesture
        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        // Move with small delta (exceeds move threshold of 0.01 but avoids centroid jump > 0.03)
        // Centroid move: from 0.5 to 0.52 = 0.02 (below 0.03 jump threshold)
        let touches2 = [
            createTouch(x: 0.32, y: 0.52),
            createTouch(x: 0.52, y: 0.52),
            createTouch(x: 0.72, y: 0.52),
        ]
        let (pointer2, count2, cleanup2) = unsafe createTouchData(touches: touches2)
        defer { cleanup2() }

        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.1, modifierFlags: [])

        // Verify we're in dragging state
        XCTAssertEqual(recognizer.state, .dragging, "Should have transitioned to dragging")

        // Lift fingers
        let emptyTouches: [MTTouch] = []
        let (emptyPointer, _, emptyCleanup) = unsafe createTouchData(touches: emptyTouches)
        defer { emptyCleanup() }

        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.2, modifierFlags: [])
        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.25, modifierFlags: [])

        // Tap should NOT be called because we transitioned to drag
        XCTAssertFalse(
            mockDelegate.didTapCalled, "Tap should not be detected when movement exceeds threshold")
        XCTAssertTrue(mockDelegate.didBeginDraggingCalled, "Should have called begin dragging")
    }

    // MARK: - Drag Gesture Tests

    func testDragBeginsAfterMovementThreshold() {
        recognizer.configuration.moveThreshold = 0.02

        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])
        XCTAssertFalse(mockDelegate.didBeginDraggingCalled)

        // Move past threshold
        let touches2 = [
            createTouch(x: 0.32, y: 0.52),
            createTouch(x: 0.52, y: 0.52),
            createTouch(x: 0.72, y: 0.52),
        ]
        let (pointer2, count2, cleanup2) = unsafe createTouchData(touches: touches2)
        defer { cleanup2() }

        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.1, modifierFlags: [])

        XCTAssertTrue(
            mockDelegate.didBeginDraggingCalled, "Drag should begin after movement threshold")
    }

    func testDragDoesNotBeginAfterTimeThresholdWithoutMovement() {
        // With the new behavior, resting fingers should NOT trigger a drag
        // Drag only starts when there is actual movement
        recognizer.configuration.tapThreshold = 0.2
        recognizer.configuration.moveThreshold = 1.0  // Very high to prevent movement-based trigger

        let touches = [
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.51, y: 0.5),
            createTouch(x: 0.52, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        // Same position but after time threshold - should NOT start drag
        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.3, modifierFlags: [])

        XCTAssertFalse(
            mockDelegate.didBeginDraggingCalled,
            "Drag should NOT begin just from time elapsed without movement")
    }

    func testDragUpdatesWithMovement() {
        recognizer.configuration.moveThreshold = 0.01

        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        // First movement to trigger drag
        let touches2 = [
            createTouch(x: 0.32, y: 0.52),
            createTouch(x: 0.52, y: 0.52),
            createTouch(x: 0.72, y: 0.52),
        ]
        let (pointer2, count2, cleanup2) = unsafe createTouchData(touches: touches2)
        defer { cleanup2() }

        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.1, modifierFlags: [])
        XCTAssertTrue(mockDelegate.didBeginDraggingCalled)

        // Additional movement - should trigger update (small delta 0.01 to avoid large jump rejection)
        let touches3 = [
            createTouch(x: 0.33, y: 0.53),
            createTouch(x: 0.53, y: 0.53),
            createTouch(x: 0.73, y: 0.53),
        ]
        let (pointer3, count3, cleanup3) = unsafe createTouchData(touches: touches3)
        defer { cleanup3() }

        unsafe recognizer.processTouches(pointer3, count: count3, timestamp: 0.2, modifierFlags: [])

        XCTAssertTrue(
            mockDelegate.didUpdateDraggingCalled, "Drag updates should be sent during movement")
        XCTAssertNotNil(mockDelegate.lastGestureData, "Gesture data should be provided")
    }

    func testDragEndsWithFingerLiftoff() {
        recognizer.configuration.moveThreshold = 0.01

        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        // Move to start dragging
        let touches2 = [
            createTouch(x: 0.32, y: 0.52),
            createTouch(x: 0.52, y: 0.52),
            createTouch(x: 0.72, y: 0.52),
        ]
        let (pointer2, count2, cleanup2) = unsafe createTouchData(touches: touches2)
        defer { cleanup2() }

        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.1, modifierFlags: [])
        XCTAssertTrue(mockDelegate.didBeginDraggingCalled)

        // Lift fingers
        let emptyTouches: [MTTouch] = []
        let (emptyPointer, _, emptyCleanup) = unsafe createTouchData(touches: emptyTouches)
        defer { emptyCleanup() }

        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.2, modifierFlags: [])
        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.3, modifierFlags: [])

        XCTAssertTrue(mockDelegate.didEndDraggingCalled, "Drag should end when fingers lift")
    }

    // MARK: - Cancellation and Cooldown Tests

    func testFourFingersCancelActiveGesture() {
        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])
        XCTAssertTrue(mockDelegate.didStartCalled)

        // Add 4th finger
        let touches4 = [
            createTouch(x: 0.2, y: 0.5),
            createTouch(x: 0.4, y: 0.5),
            createTouch(x: 0.6, y: 0.5),
            createTouch(x: 0.8, y: 0.5),
        ]
        let (pointer4, count4, cleanup4) = unsafe createTouchData(touches: touches4)
        defer { cleanup4() }

        unsafe recognizer.processTouches(pointer4, count: count4, timestamp: 0.1, modifierFlags: [])

        XCTAssertTrue(
            mockDelegate.didCancelCalled || mockDelegate.didCancelDraggingCalled,
            "4 fingers should cancel active gesture")
        XCTAssertEqual(recognizer.state, .idle, "State should be idle after cancel")
    }

    func testFourFingersCancelDragging() {
        recognizer.configuration.moveThreshold = 0.01

        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        // Start dragging
        let touches2 = [
            createTouch(x: 0.32, y: 0.52),
            createTouch(x: 0.52, y: 0.52),
            createTouch(x: 0.72, y: 0.52),
        ]
        let (pointer2, count2, cleanup2) = unsafe createTouchData(touches: touches2)
        defer { cleanup2() }

        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.1, modifierFlags: [])
        XCTAssertEqual(recognizer.state, .dragging)

        // Add 4th finger
        let touches4 = [
            createTouch(x: 0.2, y: 0.5),
            createTouch(x: 0.4, y: 0.5),
            createTouch(x: 0.6, y: 0.5),
            createTouch(x: 0.8, y: 0.5),
        ]
        let (pointer4, count4, cleanup4) = unsafe createTouchData(touches: touches4)
        defer { cleanup4() }

        unsafe recognizer.processTouches(pointer4, count: count4, timestamp: 0.2, modifierFlags: [])

        XCTAssertTrue(mockDelegate.didCancelDraggingCalled, "4 fingers should cancel dragging")
    }

    func testCooldownDuringActiveDragPreventsImmediateRestart() {
        // This test verifies that the cooldown mechanism works during an ACTIVE drag
        // When 4 fingers are detected during dragging, it cancels and sets cooldown
        // The cooldown should NOT block when going back to 3 fingers from idle state
        // (that's intentional - see comment in code "so user can start a new gesture")

        recognizer.configuration.moveThreshold = 0.01

        let touches3 = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer3, count3, cleanup3) = unsafe createTouchData(touches: touches3)
        defer { cleanup3() }

        unsafe recognizer.processTouches(pointer3, count: count3, timestamp: 0.0, modifierFlags: [])

        // Move to start dragging
        let touches3b = [
            createTouch(x: 0.32, y: 0.52),
            createTouch(x: 0.52, y: 0.52),
            createTouch(x: 0.72, y: 0.52),
        ]
        let (pointer3b, count3b, cleanup3b) = unsafe createTouchData(touches: touches3b)
        defer { cleanup3b() }

        unsafe recognizer.processTouches(pointer3b, count: count3b, timestamp: 0.1, modifierFlags: [])
        XCTAssertEqual(recognizer.state, .dragging)
        mockDelegate.reset()

        // 4 fingers trigger cancellation
        let touches4 = [
            createTouch(x: 0.2, y: 0.5),
            createTouch(x: 0.4, y: 0.5),
            createTouch(x: 0.6, y: 0.5),
            createTouch(x: 0.8, y: 0.5),
        ]
        let (pointer4, count4, cleanup4) = unsafe createTouchData(touches: touches4)
        defer { cleanup4() }

        unsafe recognizer.processTouches(pointer4, count: count4, timestamp: 0.2, modifierFlags: [])
        XCTAssertTrue(mockDelegate.didCancelDraggingCalled, "4 fingers should cancel dragging")
        XCTAssertEqual(recognizer.state, .idle, "State should be idle after cancel")

        // Now try 3 fingers again - since state is idle, cooldown should clear
        // and gesture should be allowed (this is the intended behavior)
        mockDelegate.reset()
        unsafe recognizer.processTouches(pointer3, count: count3, timestamp: 0.3, modifierFlags: [])

        // Gesture SHOULD start because cooldown clears when (state == .idle && fingerCount == 3)
        XCTAssertTrue(
            mockDelegate.didStartCalled, "Gesture should start from idle state even after cancel")
    }

    func testCooldownClearsWhenFingersDropBelowThree() {
        let touches3 = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer3, count3, cleanup3) = unsafe createTouchData(touches: touches3)
        defer { cleanup3() }

        unsafe recognizer.processTouches(pointer3, count: count3, timestamp: 0.0, modifierFlags: [])

        // 4 fingers trigger cancellation
        let touches4 = [
            createTouch(x: 0.2, y: 0.5),
            createTouch(x: 0.4, y: 0.5),
            createTouch(x: 0.6, y: 0.5),
            createTouch(x: 0.8, y: 0.5),
        ]
        let (pointer4, count4, cleanup4) = unsafe createTouchData(touches: touches4)
        defer { cleanup4() }

        unsafe recognizer.processTouches(pointer4, count: count4, timestamp: 0.1, modifierFlags: [])

        // Drop to 2 fingers to clear cooldown
        let touches2 = [
            createTouch(x: 0.4, y: 0.5),
            createTouch(x: 0.6, y: 0.5),
        ]
        let (pointer2, count2, cleanup2) = unsafe createTouchData(touches: touches2)
        defer { cleanup2() }

        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.2, modifierFlags: [])

        // Now 3 fingers should work again
        mockDelegate.reset()
        unsafe recognizer.processTouches(pointer3, count: count3, timestamp: 0.3, modifierFlags: [])

        XCTAssertTrue(mockDelegate.didStartCalled, "Gesture should start after cooldown clears")
    }

    // MARK: - Edge Case Tests

    func testResetClearsAllState() {
        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])
        XCTAssertNotEqual(recognizer.state, .idle)

        recognizer.reset()

        XCTAssertEqual(recognizer.state, .idle, "State should be idle after reset")
    }

    func testTouchStateFiltering_OnlyAcceptsState3And4() {
        // State 5 = lifting, should be ignored
        let touches = [
            createTouch(x: 0.3, y: 0.5, zTotal: 0.5, state: 5),  // Lifting - ignored
            createTouch(x: 0.5, y: 0.5, zTotal: 0.5, state: 4),  // Active - counted
            createTouch(x: 0.7, y: 0.5, zTotal: 0.5, state: 4),  // Active - counted
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        // Only 2 valid touches, should not start gesture
        XCTAssertFalse(mockDelegate.didStartCalled, "Should not start with only 2 valid touches")
    }

    func testTouchStateFiltering_State3Accepted() {
        // State 3 = touching down
        let touches = [
            createTouch(x: 0.3, y: 0.5, zTotal: 0.5, state: 3),
            createTouch(x: 0.5, y: 0.5, zTotal: 0.5, state: 3),
            createTouch(x: 0.7, y: 0.5, zTotal: 0.5, state: 3),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        XCTAssertTrue(mockDelegate.didStartCalled, "State 3 touches should be accepted")
    }

    func testZeroTouchesEndsActiveGesture() {
        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])
        XCTAssertNotEqual(recognizer.state, .idle)

        // Empty touch array
        let emptyTouches: [MTTouch] = []
        let (emptyPointer, _, emptyCleanup) = unsafe createTouchData(touches: emptyTouches)
        defer { emptyCleanup() }

        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.1, modifierFlags: [])
        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.2, modifierFlags: [])

        XCTAssertEqual(recognizer.state, .idle, "State should be idle after zero touches")
    }

    func testTwoTouchesDoNotStartGesture() {
        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])

        XCTAssertFalse(mockDelegate.didStartCalled, "2 fingers should not start gesture")
        XCTAssertEqual(recognizer.state, .idle, "State should remain idle with 2 fingers")
    }

    func testCentroidJumpResetsReferencePoint() {
        recognizer.configuration.moveThreshold = 0.01

        let touches1 = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer1, count1, cleanup1) = unsafe createTouchData(touches: touches1)
        defer { cleanup1() }

        unsafe recognizer.processTouches(pointer1, count: count1, timestamp: 0.0, modifierFlags: [])

        // Move enough to start dragging
        let touches2 = [
            createTouch(x: 0.32, y: 0.52),
            createTouch(x: 0.52, y: 0.52),
            createTouch(x: 0.72, y: 0.52),
        ]
        let (pointer2, count2, cleanup2) = unsafe createTouchData(touches: touches2)
        defer { cleanup2() }

        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.1, modifierFlags: [])
        XCTAssertTrue(mockDelegate.didBeginDraggingCalled)

        mockDelegate.reset()

        // Large jump (simulating finger replacement) - centroid jumps > 0.03
        let touches3 = [
            createTouch(x: 0.1, y: 0.1),
            createTouch(x: 0.2, y: 0.1),
            createTouch(x: 0.3, y: 0.1),
        ]
        let (pointer3, count3, cleanup3) = unsafe createTouchData(touches: touches3)
        defer { cleanup3() }

        unsafe recognizer.processTouches(pointer3, count: count3, timestamp: 0.2, modifierFlags: [])

        // Large centroid jump should NOT trigger an update (it resets reference)
        XCTAssertFalse(
            mockDelegate.didUpdateDraggingCalled,
            "Large centroid jump should reset reference, not trigger update")
    }

    func testStableFrameCountRequiresTwoFrames() {
        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])
        XCTAssertNotEqual(recognizer.state, .idle)

        // Only one frame with fewer fingers
        let touches2 = [
            createTouch(x: 0.4, y: 0.5),
            createTouch(x: 0.6, y: 0.5),
        ]
        let (pointer2, count2, cleanup2) = unsafe createTouchData(touches: touches2)
        defer { cleanup2() }

        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.1, modifierFlags: [])

        // Should NOT have ended yet (needs 2 stable frames)
        XCTAssertNotEqual(
            recognizer.state, .idle, "Should not end after only 1 frame of fewer fingers")

        // Second frame with fewer fingers
        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.2, modifierFlags: [])

        XCTAssertEqual(recognizer.state, .idle, "Should end after 2 stable frames")
    }

    func testFiveFingersAlsoCancels() {
        let touches = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer, count, cleanup) = unsafe createTouchData(touches: touches)
        defer { cleanup() }

        unsafe recognizer.processTouches(pointer, count: count, timestamp: 0.0, modifierFlags: [])
        XCTAssertTrue(mockDelegate.didStartCalled)

        mockDelegate.reset()

        // 5 fingers
        let touches5 = [
            createTouch(x: 0.1, y: 0.5),
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
            createTouch(x: 0.9, y: 0.5),
        ]
        let (pointer5, count5, cleanup5) = unsafe createTouchData(touches: touches5)
        defer { cleanup5() }

        unsafe recognizer.processTouches(pointer5, count: count5, timestamp: 0.1, modifierFlags: [])

        XCTAssertTrue(
            mockDelegate.didCancelCalled || mockDelegate.didCancelDraggingCalled,
            "5 fingers should also cancel")
    }

    // MARK: - GestureData Tests

    func testGestureDataFrameDelta() {
        // Use small delta that's below the 0.03 large jump rejection threshold
        let centroid = MTPoint(x: 0.52, y: 0.52)  // Delta of 0.02 from lastPosition
        let lastPosition = MTPoint(x: 0.5, y: 0.5)

        let gestureData = GestureData(
            centroid: centroid,
            velocity: MTPoint(x: 0, y: 0),
            pressure: 0,
            fingerCount: 3,
            startPosition: MTPoint(x: 0.5, y: 0.5),
            lastPosition: lastPosition
        )

        let config = GestureConfiguration()
        let delta = gestureData.frameDelta(from: config)

        // Delta should be non-zero and reflect the movement
        XCTAssertNotEqual(delta.x, 0, "Delta X should be non-zero")
        XCTAssertNotEqual(delta.y, 0, "Delta Y should be non-zero")
    }

    func testGestureDataFrameDeltaRejectsLargeJumps() {
        let centroid = MTPoint(x: 0.8, y: 0.8)  // Large jump from last
        let lastPosition = MTPoint(x: 0.5, y: 0.5)

        let gestureData = GestureData(
            centroid: centroid,
            velocity: MTPoint(x: 0, y: 0),
            pressure: 0,
            fingerCount: 3,
            startPosition: MTPoint(x: 0.5, y: 0.5),
            lastPosition: lastPosition
        )

        let config = GestureConfiguration()
        let delta = gestureData.frameDelta(from: config)

        // Large jumps should return (0, 0)
        XCTAssertEqual(delta.x, 0, "Large jump should return zero delta X")
        XCTAssertEqual(delta.y, 0, "Large jump should return zero delta Y")
    }

    func testGestureDataFrameDeltaAppliesSensitivity() {
        let centroid = MTPoint(x: 0.51, y: 0.51)
        let lastPosition = MTPoint(x: 0.5, y: 0.5)

        let gestureData = GestureData(
            centroid: centroid,
            velocity: MTPoint(x: 0, y: 0),
            pressure: 0,
            fingerCount: 3,
            startPosition: MTPoint(x: 0.5, y: 0.5),
            lastPosition: lastPosition
        )

        var config = GestureConfiguration()
        config.sensitivity = 1000

        let delta = gestureData.frameDelta(from: config)

        // With sensitivity applied, delta should be scaled
        XCTAssertGreaterThan(abs(delta.x), 0.01, "Sensitivity should scale delta")
        XCTAssertGreaterThan(abs(delta.y), 0.01, "Sensitivity should scale delta")
    }

    // MARK: - Relift During Drag Tests

    func testReliftDuringDrag_DisabledByDefault() {
        // Verify default behavior: drag ends when dropping to 2 fingers
        recognizer.configuration.moveThreshold = 0.01
        recognizer.configuration.allowReliftDuringDrag = false  // Default

        // Start with 3 fingers
        let touches3 = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer3, count3, cleanup3) = unsafe createTouchData(touches: touches3)
        defer { cleanup3() }

        unsafe recognizer.processTouches(pointer3, count: count3, timestamp: 0.0, modifierFlags: [])

        // Move to start dragging
        let touches3b = [
            createTouch(x: 0.32, y: 0.52),
            createTouch(x: 0.52, y: 0.52),
            createTouch(x: 0.72, y: 0.52),
        ]
        let (pointer3b, count3b, cleanup3b) = unsafe createTouchData(touches: touches3b)
        defer { cleanup3b() }

        unsafe recognizer.processTouches(pointer3b, count: count3b, timestamp: 0.1, modifierFlags: [])
        XCTAssertEqual(recognizer.state, .dragging)

        // Drop to 2 fingers - should end after stable frames
        let touches2 = [
            createTouch(x: 0.4, y: 0.5),
            createTouch(x: 0.6, y: 0.5),
        ]
        let (pointer2, count2, cleanup2) = unsafe createTouchData(touches: touches2)
        defer { cleanup2() }

        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.2, modifierFlags: [])
        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.3, modifierFlags: [])

        XCTAssertEqual(
            recognizer.state, .idle, "Drag should end with 2 fingers when relift is disabled")
        XCTAssertTrue(mockDelegate.didEndDraggingCalled)
    }

    func testReliftDuringDrag_ContinuesWithTwoFingers() {
        // With allowReliftDuringDrag enabled, drag continues with 2 fingers
        recognizer.configuration.moveThreshold = 0.01
        recognizer.configuration.allowReliftDuringDrag = true

        // Start with 3 fingers
        let touches3 = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer3, count3, cleanup3) = unsafe createTouchData(touches: touches3)
        defer { cleanup3() }

        unsafe recognizer.processTouches(pointer3, count: count3, timestamp: 0.0, modifierFlags: [])

        // Move to start dragging
        let touches3b = [
            createTouch(x: 0.32, y: 0.52),
            createTouch(x: 0.52, y: 0.52),
            createTouch(x: 0.72, y: 0.52),
        ]
        let (pointer3b, count3b, cleanup3b) = unsafe createTouchData(touches: touches3b)
        defer { cleanup3b() }

        unsafe recognizer.processTouches(pointer3b, count: count3b, timestamp: 0.1, modifierFlags: [])
        XCTAssertEqual(recognizer.state, .dragging)

        // Drop to 2 fingers - should NOT end
        let touches2 = [
            createTouch(x: 0.35, y: 0.55),
            createTouch(x: 0.55, y: 0.55),
        ]
        let (pointer2, count2, cleanup2) = unsafe createTouchData(touches: touches2)
        defer { cleanup2() }

        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.2, modifierFlags: [])
        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.3, modifierFlags: [])

        XCTAssertEqual(
            recognizer.state, .dragging,
            "Drag should continue with 2 fingers when relift is enabled")
        XCTAssertFalse(mockDelegate.didEndDraggingCalled)
    }

    func testReliftDuringDrag_RequiresThreeToStart() {
        // Even with relift enabled, still requires 3 fingers to START
        recognizer.configuration.allowReliftDuringDrag = true

        // Try to start with 2 fingers
        let touches2 = [
            createTouch(x: 0.4, y: 0.5),
            createTouch(x: 0.6, y: 0.5),
        ]
        let (pointer2, count2, cleanup2) = unsafe createTouchData(touches: touches2)
        defer { cleanup2() }

        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.0, modifierFlags: [])

        XCTAssertEqual(recognizer.state, .idle, "Should not start gesture with 2 fingers")
        XCTAssertFalse(mockDelegate.didStartCalled)
    }

    func testReliftDuringDrag_EndsWithOneFinger() {
        // Drag ends when dropping to 1 finger, even with relift enabled
        recognizer.configuration.moveThreshold = 0.01
        recognizer.configuration.allowReliftDuringDrag = true

        // Start with 3 fingers and begin dragging
        let touches3 = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer3, count3, cleanup3) = unsafe createTouchData(touches: touches3)
        defer { cleanup3() }

        unsafe recognizer.processTouches(pointer3, count: count3, timestamp: 0.0, modifierFlags: [])

        let touches3b = [
            createTouch(x: 0.32, y: 0.52),
            createTouch(x: 0.52, y: 0.52),
            createTouch(x: 0.72, y: 0.52),
        ]
        let (pointer3b, count3b, cleanup3b) = unsafe createTouchData(touches: touches3b)
        defer { cleanup3b() }

        unsafe recognizer.processTouches(pointer3b, count: count3b, timestamp: 0.1, modifierFlags: [])
        XCTAssertEqual(recognizer.state, .dragging)

        // Drop to 1 finger
        let touches1 = [
            createTouch(x: 0.5, y: 0.5)
        ]
        let (pointer1, count1, cleanup1) = unsafe createTouchData(touches: touches1)
        defer { cleanup1() }

        unsafe recognizer.processTouches(pointer1, count: count1, timestamp: 0.2, modifierFlags: [])
        unsafe recognizer.processTouches(pointer1, count: count1, timestamp: 0.3, modifierFlags: [])

        XCTAssertEqual(recognizer.state, .idle, "Drag should end with 1 finger")
        XCTAssertTrue(mockDelegate.didEndDraggingCalled)
    }

    func testReliftDuringDrag_EndsWithZeroFingers() {
        // Drag ends when all fingers lift
        recognizer.configuration.moveThreshold = 0.01
        recognizer.configuration.allowReliftDuringDrag = true

        // Start dragging
        let touches3 = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer3, count3, cleanup3) = unsafe createTouchData(touches: touches3)
        defer { cleanup3() }

        unsafe recognizer.processTouches(pointer3, count: count3, timestamp: 0.0, modifierFlags: [])

        let touches3b = [
            createTouch(x: 0.32, y: 0.52),
            createTouch(x: 0.52, y: 0.52),
            createTouch(x: 0.72, y: 0.52),
        ]
        let (pointer3b, count3b, cleanup3b) = unsafe createTouchData(touches: touches3b)
        defer { cleanup3b() }

        unsafe recognizer.processTouches(pointer3b, count: count3b, timestamp: 0.1, modifierFlags: [])
        XCTAssertEqual(recognizer.state, .dragging)

        // Lift all fingers
        let emptyTouches: [MTTouch] = []
        let (emptyPointer, _, emptyCleanup) = unsafe createTouchData(touches: emptyTouches)
        defer { emptyCleanup() }

        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.2, modifierFlags: [])
        unsafe recognizer.processTouches(emptyPointer, count: 0, timestamp: 0.3, modifierFlags: [])

        XCTAssertEqual(recognizer.state, .idle, "Drag should end when all fingers lift")
        XCTAssertTrue(mockDelegate.didEndDraggingCalled)
    }

    func testReliftDuringDrag_OnlyAppliesToDraggingState() {
        // Relift only works in dragging state, not possibleTap
        recognizer.configuration.allowReliftDuringDrag = true
        recognizer.configuration.tapThreshold = 0.5  // Long enough to stay in possibleTap

        // Start with 3 fingers (enters possibleTap)
        let touches3 = [
            createTouch(x: 0.3, y: 0.5),
            createTouch(x: 0.5, y: 0.5),
            createTouch(x: 0.7, y: 0.5),
        ]
        let (pointer3, count3, cleanup3) = unsafe createTouchData(touches: touches3)
        defer { cleanup3() }

        unsafe recognizer.processTouches(pointer3, count: count3, timestamp: 0.0, modifierFlags: [])
        XCTAssertEqual(recognizer.state, .possibleTap)

        // Drop to 2 fingers while still in possibleTap - should end
        let touches2 = [
            createTouch(x: 0.4, y: 0.5),
            createTouch(x: 0.6, y: 0.5),
        ]
        let (pointer2, count2, cleanup2) = unsafe createTouchData(touches: touches2)
        defer { cleanup2() }

        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.05, modifierFlags: [])
        unsafe recognizer.processTouches(pointer2, count: count2, timestamp: 0.08, modifierFlags: [])

        XCTAssertEqual(
            recognizer.state, .idle,
            "possibleTap should end with 2 fingers even with relift enabled")
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
