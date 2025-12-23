import ServiceManagement
import XCTest

@testable import MiddleDrag

final class LaunchAtLoginManagerTests: XCTestCase {

    var manager: LaunchAtLoginManager!

    override func setUp() {
        super.setUp()
        manager = LaunchAtLoginManager.shared
    }

    override func tearDown() {
        // Clean up - disable launch at login after tests
        manager.setLaunchAtLogin(false)
        manager = nil
        super.tearDown()
    }

    // MARK: - Singleton Tests

    func testSharedInstanceIsSingleton() {
        let instance1 = LaunchAtLoginManager.shared
        let instance2 = LaunchAtLoginManager.shared

        XCTAssertTrue(
            instance1 === instance2, "LaunchAtLoginManager.shared should return the same instance")
    }

    // MARK: - Configuration Tests

    func testSetLaunchAtLoginEnable() {
        // Should not crash when enabling
        XCTAssertNoThrow(manager.setLaunchAtLogin(true))
    }

    func testSetLaunchAtLoginDisable() {
        // Should not crash when disabling
        XCTAssertNoThrow(manager.setLaunchAtLogin(false))
    }

    func testSetLaunchAtLoginToggle() {
        // Should handle toggling
        XCTAssertNoThrow(manager.setLaunchAtLogin(true))
        XCTAssertNoThrow(manager.setLaunchAtLogin(false))
        XCTAssertNoThrow(manager.setLaunchAtLogin(true))
    }

    // MARK: - Status Tests

    func testIsEnabledProperty() {
        // Should be able to read isEnabled without crashing
        XCTAssertNoThrow(_ = manager.isEnabled)
    }

    @available(macOS 13.0, *)
    func testIsEnabledAfterEnable() {
        manager.setLaunchAtLogin(true)

        // Give time for the system to process
        let expectation = XCTestExpectation(description: "Status updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Note: In test environment, SMAppService might not actually enable,
        // so we just verify it doesn't crash
        XCTAssertNoThrow(_ = self.manager.isEnabled)
    }

    @available(macOS 13.0, *)
    func testIsEnabledAfterDisable() {
        manager.setLaunchAtLogin(false)

        // Give time for the system to process
        let expectation = XCTestExpectation(description: "Status updated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertNoThrow(_ = self.manager.isEnabled)
    }

    // MARK: - Legacy System Tests

    func testLegacySystemHandling() {
        // On older macOS versions, should log warning but not crash
        XCTAssertNoThrow(manager.setLaunchAtLogin(true))
    }

    // MARK: - Multiple Calls Tests

    func testMultipleEnableCalls() {
        // Should handle multiple enable calls
        manager.setLaunchAtLogin(true)
        manager.setLaunchAtLogin(true)
        manager.setLaunchAtLogin(true)

        XCTAssertNoThrow(manager.setLaunchAtLogin(true))
    }

    func testMultipleDisableCalls() {
        // Should handle multiple disable calls
        manager.setLaunchAtLogin(false)
        manager.setLaunchAtLogin(false)
        manager.setLaunchAtLogin(false)

        XCTAssertNoThrow(manager.setLaunchAtLogin(false))
    }

    // MARK: - Thread Safety Tests

    func testConcurrentAccess() {
        let expectation = XCTestExpectation(description: "Concurrent operations completed")
        expectation.expectedFulfillmentCount = 10

        for i in 0..<10 {
            DispatchQueue.global().async {
                self.manager.setLaunchAtLogin(i % 2 == 0)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }
}
