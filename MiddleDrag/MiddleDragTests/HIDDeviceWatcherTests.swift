import XCTest

@testable import MiddleDrag

/// Tests for HIDDeviceWatcher
///
/// ## Coverage Notes
///
/// IOHIDManager requires real hardware to fire matching/removal callbacks,
/// so we test lifecycle, delegate wiring, debouncing constants, and crash-safety.
/// The actual IOKit event flow is validated implicitly by the
/// MultitouchManager integration tests.
final class HIDDeviceWatcherTests: XCTestCase {

    private var watcher: HIDDeviceWatcher!

    override func setUp() {
        super.setUp()
        watcher = HIDDeviceWatcher()
    }

    override func tearDown() {
        watcher?.stop()
        watcher = nil
        super.tearDown()
    }

    // MARK: - Lifecycle Tests

    func testStartDoesNotCrash() {
        XCTAssertNoThrow(watcher.start())
    }

    func testStopWithoutStartDoesNotCrash() {
        XCTAssertNoThrow(watcher.stop())
    }

    func testDoubleStartDoesNotCrash() {
        watcher.start()
        XCTAssertNoThrow(watcher.start())
    }

    func testDoubleStopDoesNotCrash() {
        watcher.start()
        XCTAssertNoThrow(watcher.stop())
        XCTAssertNoThrow(watcher.stop())
    }

    func testStartStopStartCycle() {
        watcher.start()
        watcher.stop()
        XCTAssertNoThrow(watcher.start())
    }

    func testMultipleStartStopCycles() {
        for _ in 0..<5 {
            watcher.start()
            watcher.stop()
        }
    }

    // MARK: - Delegate Tests

    func testDelegateIsSetCorrectly() {
        let delegate = MockHIDDelegate()
        watcher.delegate = delegate
        XCTAssertNotNil(watcher.delegate)
        XCTAssertTrue(watcher.delegate === delegate)
    }

    func testDelegateCanBeCleared() {
        let delegate = MockHIDDelegate()
        watcher.delegate = delegate
        watcher.delegate = nil
        XCTAssertNil(watcher.delegate)
    }

    func testDelegateIsWeakReference() {
        var delegate: MockHIDDelegate? = MockHIDDelegate()
        watcher.delegate = delegate
        XCTAssertNotNil(watcher.delegate)
        delegate = nil
        XCTAssertNil(watcher.delegate)
    }

    // MARK: - Debounce Constant Tests

    func testDebounceIntervalIsPositive() {
        XCTAssertGreaterThan(HIDDeviceWatcher.debounceInterval, 0)
    }

    func testDebounceIntervalIsReasonable() {
        XCTAssertGreaterThanOrEqual(HIDDeviceWatcher.debounceInterval, 0.5)
        XCTAssertLessThanOrEqual(HIDDeviceWatcher.debounceInterval, 5.0)
    }

    // MARK: - Multiple Instance Tests

    func testMultipleWatcherInstances() {
        let watcher2 = HIDDeviceWatcher()
        let watcher3 = HIDDeviceWatcher()

        watcher.start()
        watcher2.start()
        watcher3.start()

        watcher.stop()
        watcher2.stop()
        watcher3.stop()
    }

    // MARK: - Deinit Tests

    func testDeinitAfterStartCleansUp() {
        weak var weakRef: HIDDeviceWatcher?
        autoreleasepool {
            let local = HIDDeviceWatcher()
            weakRef = local
            local.start()
        }
        XCTAssertNil(weakRef)
    }

    func testDeinitWithoutStartDoesNotCrash() {
        weak var weakRef: HIDDeviceWatcher?
        autoreleasepool {
            let local = HIDDeviceWatcher()
            weakRef = local
        }
        XCTAssertNil(weakRef)
    }
}

// MARK: - Mock

private class MockHIDDelegate: HIDDeviceWatcher.Delegate {
    var connectionCount = 0
    var disconnectionCount = 0

    func hidDeviceWatcherDidDetectDeviceConnection(_ watcher: HIDDeviceWatcher) {
        connectionCount += 1
    }

    func hidDeviceWatcherDidDetectDeviceDisconnection(_ watcher: HIDDeviceWatcher) {
        disconnectionCount += 1
    }
}
