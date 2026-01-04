import XCTest

@testable import MiddleDrag

class MockAccessibilityPermissionChecker: AccessibilityPermissionChecking {
    var isTrusted: Bool = false
}

class MockAppLifecycleController: AppLifecycleControlling {
    var relaunchCalled = false
    var terminateCalled = false

    func relaunch() {
        relaunchCalled = true
    }

    func terminate() {
        terminateCalled = true
    }
}

class AccessibilityMonitorTests: XCTestCase {

    var monitor: AccessibilityMonitor!
    var mockPermissionChecker: MockAccessibilityPermissionChecker!
    var mockAppController: MockAppLifecycleController!

    override func setUp() {
        super.setUp()
        mockPermissionChecker = MockAccessibilityPermissionChecker()
        mockAppController = MockAppLifecycleController()
        monitor = AccessibilityMonitor(
            permissionChecker: mockPermissionChecker,
            appController: mockAppController
        )
    }

    override func tearDown() {
        monitor.stopPolling()
        monitor = nil
        mockPermissionChecker = nil
        mockAppController = nil
        super.tearDown()
    }

    func testStartPollingCheckPermission() {
        // Given permission is initially false
        mockPermissionChecker.isTrusted = false

        // When polling starts
        monitor.startPolling(interval: 0.1)

        // Then relaunch should not be called immediately
        XCTAssertFalse(mockAppController.relaunchCalled)

        // When permission becomes true
        mockPermissionChecker.isTrusted = true

        // Wait for timer to fire
        let expectation = XCTestExpectation(description: "Wait for poll")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then relaunch should be called
        XCTAssertTrue(mockAppController.relaunchCalled)
    }

    func testStopPollingStopsChecks() {
        // Given polling is started
        monitor.startPolling(interval: 0.1)

        // When polling is stopped
        monitor.stopPolling()

        // And permission becomes true
        mockPermissionChecker.isTrusted = true

        // Wait for timer to have potentially fired
        let expectation = XCTestExpectation(description: "Wait for poll")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then relaunch should NOT be called
        XCTAssertFalse(mockAppController.relaunchCalled)
    }

    func testIsGrantedDelegatesToChecker() {
        mockPermissionChecker.isTrusted = true
        XCTAssertTrue(monitor.isGranted)

        mockPermissionChecker.isTrusted = false
        XCTAssertFalse(monitor.isGranted)
    }
}
