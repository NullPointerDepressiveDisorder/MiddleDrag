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
        monitor.stopMonitoring()
        monitor = nil
        mockPermissionChecker = nil
        mockAppController = nil
        super.tearDown()
    }

    func testGrantCallback() {
        // Given permission is initially false
        mockPermissionChecker.isTrusted = false
        monitor.startMonitoring(interval: 0.1)

        // Setup expectation
        let grantExpectation = XCTestExpectation(description: "Grant callback called")
        monitor.onGrant = {
            grantExpectation.fulfill()
        }

        // When permission becomes true
        mockPermissionChecker.isTrusted = true

        // Wait for timer to fire
        wait(for: [grantExpectation], timeout: 1.0)
    }

    func testRevocationCallback() {
        // Given permission is initially true
        mockPermissionChecker.isTrusted = true
        monitor.startMonitoring(interval: 0.1)

        // Setup expectation
        let revocationExpectation = XCTestExpectation(description: "Revocation callback called")
        monitor.onRevocation = {
            revocationExpectation.fulfill()
        }

        // When permission becomes false
        mockPermissionChecker.isTrusted = false

        // Wait for timer to fire
        wait(for: [revocationExpectation], timeout: 1.0)
    }

    func testStopMonitoringStopsChecks() {
        // Given monitoring is started
        monitor.startMonitoring(interval: 0.1)

        // When monitoring is stopped
        monitor.stopMonitoring()

        var called = false
        monitor.onGrant = { called = true }

        // And permission changes
        mockPermissionChecker.isTrusted = !mockPermissionChecker.isTrusted

        // Wait for timer to have potentially fired
        let expectation = XCTestExpectation(description: "Wait for poll")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then callback should NOT be called
        XCTAssertFalse(called)
    }

    func testIsGrantedDelegatesToChecker() {
        mockPermissionChecker.isTrusted = true
        XCTAssertTrue(monitor.isGranted)

        mockPermissionChecker.isTrusted = false
        XCTAssertFalse(monitor.isGranted)
    }
    func testDefaultInit() {
        // Ensure that default initialization works (covers default argument paths)
        // This instantiates the real System classes, so we can't test behavior,
        // but we verify no crash on init.
        let monitor = AccessibilityMonitor()
        XCTAssertNotNil(monitor)
    }
}
