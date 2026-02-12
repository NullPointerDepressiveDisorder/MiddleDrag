import XCTest

@testable import MiddleDragCore

final class MultitouchFrameworkTests: XCTestCase {

    // MARK: - Singleton Tests

    func testMultitouchFrameworkIsSingleton() {
        let instance1 = MultitouchFramework.shared
        let instance2 = MultitouchFramework.shared
        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - Device Availability Tests

    func testIsAvailableDoesNotCrash() {
        let framework = MultitouchFramework.shared
        let isAvailable1 = framework.isAvailable
        let isAvailable2 = framework.isAvailable
        // Verify that calling isAvailable does not crash and returns a consistent value
        XCTAssertEqual(isAvailable1, isAvailable2)
    }

    func testGetDefaultDeviceDoesNotCrash() {
        let framework = MultitouchFramework.shared
        // Just verify that calling getDefaultDevice() does not crash
        // Note: Device handles may differ between calls, so we don't compare equality
        _ = unsafe framework.getDefaultDevice()
        _ = unsafe framework.getDefaultDevice()
    }

    func testGetDefaultDeviceReturnsConsistentValue() {
        let framework = MultitouchFramework.shared
        let device1 = unsafe framework.getDefaultDevice()
        let device2 = unsafe framework.getDefaultDevice()
        // Verify that repeated calls are consistent in availability (both nil or both non-nil),
        // without relying on pointer identity, which may legitimately differ.
        unsafe XCTAssertEqual(device1 != nil, device2 != nil)
    }
}
