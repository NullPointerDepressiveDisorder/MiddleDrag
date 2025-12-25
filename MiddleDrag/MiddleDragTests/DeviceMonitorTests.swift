import XCTest

@testable import MiddleDrag

final class DeviceMonitorTests: XCTestCase {

    // Note: DeviceMonitor uses a global variable (gDeviceMonitor) for C callback compatibility
    // This limits testing options since only one instance can be active at a time

    // MARK: - Start/Stop Tests

    func testStartDoesNotCrash() {
        let monitor = DeviceMonitor()
        // Note: In test environment without a trackpad, this may log warnings
        XCTAssertNoThrow(monitor.start())
        monitor.stop()
    }

    func testStopWithoutStartDoesNotCrash() {
        let monitor = DeviceMonitor()
        // Calling stop on a monitor that was never started should not crash
        XCTAssertNoThrow(monitor.stop())
    }
}
