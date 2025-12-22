import XCTest

@testable import MiddleDrag

final class LaunchAtLoginManagerTests: XCTestCase {

    var manager: LaunchAtLoginManager!
    var mockService: MockLoginItemService!

    override func setUp() {
        super.setUp()
        mockService = MockLoginItemService()
        manager = LaunchAtLoginManager(service: mockService)
    }

    override func tearDown() {
        manager = nil
        mockService = nil
        super.tearDown()
    }

    // MARK: - Tests

    func testSetLaunchAtLogin_Enable() {
        // macOS 13+ check simulated by availability in code, but tests run on host OS.
        // Assuming test environment allows running this code path or we can force it.
        // The manager uses #available checks. If running on older OS, this test might skip logic.
        // However, we injected the service.

        if #available(macOS 13.0, *) {
            manager.setLaunchAtLogin(true)
            XCTAssertTrue(mockService.registerCalled)
            XCTAssertFalse(mockService.unregisterCalled)
        }
    }

    func testSetLaunchAtLogin_Disable() {
        if #available(macOS 13.0, *) {
            manager.setLaunchAtLogin(false)
            XCTAssertFalse(mockService.registerCalled)
            XCTAssertTrue(mockService.unregisterCalled)
        }
    }

    func testIsEnabled_ReturnsServiceStatus() {
        if #available(macOS 13.0, *) {
            mockService.isEnabledMock = true
            XCTAssertTrue(manager.isEnabled)

            mockService.isEnabledMock = false
            XCTAssertFalse(manager.isEnabled)
        }
    }

    func testErrorHandling_DoesNotCrash() {
        if #available(macOS 13.0, *) {
            mockService.shouldThrow = true

            // Should catch error and log it, not crash
            manager.setLaunchAtLogin(true)
            XCTAssertTrue(mockService.registerCalled)
        }
    }
}

// MARK: - Mock

class MockLoginItemService: LoginItemServiceProtocol {

    var isEnabledMock = false
    var registerCalled = false
    var unregisterCalled = false
    var shouldThrow = false

    var isEnabled: Bool {
        return isEnabledMock
    }

    func register() throws {
        registerCalled = true
        if shouldThrow {
            throw NSError(domain: "Test", code: 1, userInfo: nil)
        }
    }

    func unregister() throws {
        unregisterCalled = true
        if shouldThrow {
            throw NSError(domain: "Test", code: 1, userInfo: nil)
        }
    }
}
