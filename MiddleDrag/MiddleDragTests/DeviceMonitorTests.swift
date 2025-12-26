import XCTest

@testable import MiddleDrag

final class DeviceMonitorTests: XCTestCase {

    // Note: DeviceMonitor uses a global variable (gDeviceMonitor) for C callback compatibility
    // This limits testing options since only one instance can be active at a time
    // Tests are run serially to avoid race conditions with the global state

    /// Instance under test - created fresh for each test
    private var monitor: DeviceMonitor!

    override func setUp() {
        super.setUp()
        // Create a fresh monitor for each test
        monitor = DeviceMonitor()
    }

    override func tearDown() {
        // Ensure monitor is stopped and cleaned up after each test
        monitor?.stop()
        monitor = nil
        // Small delay to ensure cleanup completes before next test
        // This helps prevent race conditions with the global gDeviceMonitor variable
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        super.tearDown()
    }

    // MARK: - Start/Stop Tests

    func testStartDoesNotCrash() {
        // Note: In test environment without a trackpad, this may log warnings
        XCTAssertNoThrow(monitor.start())
        // stop() is called in tearDown
    }

    func testStopWithoutStartDoesNotCrash() {
        // Calling stop on a monitor that was never started should not crash
        // The monitor is created in setUp, so we just call stop directly
        XCTAssertNoThrow(monitor.stop())
    }

    func testDoubleStopDoesNotCrash() {
        // Should handle calling stop multiple times gracefully
        monitor.start()
        XCTAssertNoThrow(monitor.stop())
        XCTAssertNoThrow(monitor.stop())
    }

    func testStartStopStartDoesNotCrash() {
        // Should be able to restart the monitor
        XCTAssertNoThrow(monitor.start())
        XCTAssertNoThrow(monitor.stop())
        XCTAssertNoThrow(monitor.start())
    }

    // MARK: - Delegate Tests

    func testDelegateIsSetCorrectly() {
        let delegate = MockDeviceMonitorDelegate()
        monitor.delegate = delegate

        XCTAssertNotNil(monitor.delegate)
        XCTAssertTrue(monitor.delegate === delegate)
    }

    func testDelegateCanBeCleared() {
        let delegate = MockDeviceMonitorDelegate()
        monitor.delegate = delegate
        XCTAssertNotNil(monitor.delegate)

        monitor.delegate = nil
        XCTAssertNil(monitor.delegate)
    }

    func testDelegateIsWeakReference() {
        var delegate: MockDeviceMonitorDelegate? = MockDeviceMonitorDelegate()
        monitor.delegate = delegate

        XCTAssertNotNil(monitor.delegate)

        // Release the delegate
        delegate = nil

        // Delegate should be nil since it's a weak reference
        XCTAssertNil(monitor.delegate)
    }

    // MARK: - Multiple Instance Tests

    func testMultipleInstancesDoNotCrash() {
        // Create multiple monitors - only first should own global reference
        let monitor2 = DeviceMonitor()
        let monitor3 = DeviceMonitor()

        // Starting/stopping multiple instances should not crash
        XCTAssertNoThrow(monitor.start())
        XCTAssertNoThrow(monitor2.start())

        XCTAssertNoThrow(monitor.stop())
        XCTAssertNoThrow(monitor2.stop())
        // monitor3 never started, just deallocates
        _ = monitor3
    }

    func testSecondInstanceCanStartAfterFirstStops() {
        monitor.start()
        monitor.stop()

        let monitor2 = DeviceMonitor()
        XCTAssertNoThrow(monitor2.start())
        monitor2.stop()
    }
}

// MARK: - Mock Delegate

/// Mock delegate for testing DeviceMonitor delegate callbacks
class MockDeviceMonitorDelegate: DeviceMonitorDelegate {
    var didReceiveTouchesCalled = false
    var receivedTouchCount: Int32 = 0
    var receivedTimestamp: Double = 0

    func deviceMonitor(
        _ monitor: DeviceMonitor,
        didReceiveTouches touches: UnsafeMutableRawPointer,
        count: Int32,
        timestamp: Double
    ) {
        didReceiveTouchesCalled = true
        receivedTouchCount = count
        receivedTimestamp = timestamp
    }
}
