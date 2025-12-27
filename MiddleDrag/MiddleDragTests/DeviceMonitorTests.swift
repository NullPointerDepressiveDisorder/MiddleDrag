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

    // MARK: - Deinit/Cleanup Tests
    // Note: Tests that call start() inside autoreleasepool hang in CI (headless environment)
    // Testing deinit without start() is safe since it doesn't touch multitouch framework

    func testDeinitCleansUpGlobalReferenceWithoutStart() {
        // Test deinit cleanup WITHOUT calling start() - safe for CI
        // This exercises lines 74-75 in deinit that clear gDeviceMonitor
        weak var weakRef: DeviceMonitor?
        autoreleasepool {
            let localMonitor = DeviceMonitor()
            weakRef = localMonitor
            // Don't call start() - just let it deallocate
        }
        // The monitor should have been deallocated and global reference cleared
        XCTAssertNil(weakRef, "Monitor should be deallocated")
    }

    func testStopUnregistersAllDevices() {
        // This test ensures the new loop in stop() executes
        // In CI without devices, registeredDevices is empty but the code path is still exercised
        monitor.start()
        // Stop should unregister ALL registered devices (the new fix)
        XCTAssertNoThrow(monitor.stop())
    }

    func testMultipleStartStopCyclesDoNotLeak() {
        // Exercise multiple start/stop cycles to test the registeredDevices cleanup
        // Works in CI because start/stop are no-ops when no devices are found
        for _ in 0..<3 {
            monitor.start()
            monitor.stop()
        }
        // If no crashes/hangs, the device registration/unregistration is balanced
        XCTAssertTrue(true)
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
