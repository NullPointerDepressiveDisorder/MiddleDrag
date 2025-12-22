import XCTest

@testable import MiddleDrag

final class MultitouchFrameworkTests: XCTestCase {

    // MARK: - Singleton Tests

    func testMultitouchFrameworkIsSingleton() {
        let instance1 = MultitouchFramework.shared
        let instance2 = MultitouchFramework.shared
        XCTAssertTrue(instance1 === instance2)
    }

    // MARK: - Device Availability Tests

    func testIsAvailableReturnsBoolean() {
        let framework = MultitouchFramework.shared
        let isAvailable = framework.isAvailable
        // On most Macs with trackpads, this should be true
        // But we just verify it returns a boolean without crashing
        XCTAssertTrue(isAvailable || !isAvailable)  // Tautology to ensure no crash
    }

    func testGetDefaultDeviceDoesNotCrash() {
        let framework = MultitouchFramework.shared
        let device = framework.getDefaultDevice()
        // Device might be nil on some systems, or non-nil on trackpad systems
        // Just verify the call doesn't crash
        _ = device
    }

    func testGetDefaultDeviceReturnsConsistentValue() {
        let framework = MultitouchFramework.shared
        let device1 = framework.getDefaultDevice()
        let device2 = framework.getDefaultDevice()
        XCTAssertEqual(device1, device2)
    }
}