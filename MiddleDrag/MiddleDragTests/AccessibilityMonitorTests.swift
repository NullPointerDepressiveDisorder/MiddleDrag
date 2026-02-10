import XCTest

@testable import MiddleDragCore

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
        // Re-init to capture "false" state
        monitor = AccessibilityMonitor(
            initialState: false, permissionChecker: mockPermissionChecker,
            appController: mockAppController)
        monitor.startMonitoring(interval: 0.1)

        // Setup expectation
        let grantExpectation = XCTestExpectation(description: "Grant callback called")
        monitor.onGrant = {
            grantExpectation.fulfill()
        }

        // When permission becomes true
        mockPermissionChecker.isTrusted = true

        // Wait for timer to fire
        wait(for: [grantExpectation], timeout: 2.0)
    }

    func testRevocationCallback() {
        // Given permission is initially true
        mockPermissionChecker.isTrusted = true
        // Re-init to capture "true" state
        monitor = AccessibilityMonitor(
            initialState: true, permissionChecker: mockPermissionChecker,
            appController: mockAppController)
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

    func testRaceConditionDetection() {
        // Scenario: App thinks permission is true (was true at launch), but system now says false (revoked quickly)
        mockPermissionChecker.isTrusted = false

        // Initialize with state = true (what app saw)
        monitor = AccessibilityMonitor(
            initialState: true,
            permissionChecker: mockPermissionChecker,
            appController: mockAppController
        )

        let revocationExpectation = XCTestExpectation(
            description: "Revocation detected immediately due to state mismatch")
        monitor.onRevocation = {
            revocationExpectation.fulfill()
        }

        monitor.startMonitoring(interval: 0.1)

        wait(for: [revocationExpectation], timeout: 1.0)
    }

    func testDefaultInit() {
        // Ensure that default initialization works (covers default argument paths)
        // This instantiates the real System classes, so we can't test behavior,
        // but we verify no crash on init.
        let monitor = AccessibilityMonitor()
        XCTAssertNotNil(monitor)
    }

    func testTriggerRelaunch() {
        monitor.triggerRelaunch()
        XCTAssertTrue(mockAppController.relaunchCalled)
    }
}

class MockAppLifecycleProcessRunner: AppLifecycleProcessRunner {
    var executableURL: URL?
    var arguments: [String]?
    var runCalled = false

    func run() throws {
        runCalled = true
    }
}

class TestableSystemAppLifecycleController: SystemAppLifecycleController, @unchecked Sendable {
    var terminateCalled = false
    var terminateExpectation: XCTestExpectation?

    override func terminate() {
        terminateCalled = true
        terminateExpectation?.fulfill()
    }
}

class MockFailingProcessRunner: AppLifecycleProcessRunner {
    var executableURL: URL?
    var arguments: [String]?

    func run() throws {
        throw NSError(domain: "Test", code: 1, userInfo: nil)
    }
}

class SystemAppLifecycleControllerTests: XCTestCase {
    func testRelaunchConfiguresProcessCorrectly() {
        let controller = TestableSystemAppLifecycleController()
        let mockProcess = MockAppLifecycleProcessRunner()

        // Inject mock factory
        controller.processFactory = { mockProcess }

        controller.relaunch()

        XCTAssertTrue(mockProcess.runCalled)
        XCTAssertEqual(mockProcess.executableURL?.path, "/bin/sh")
        XCTAssertNotNil(mockProcess.arguments)
        if let args = mockProcess.arguments {
            XCTAssertEqual(args.count, 3)
            XCTAssertEqual(args[0], "-c")
            XCTAssertTrue(args[1].contains("sleep 0.5 && open -n \"$0\""))
            // Verify bundle path is passed as $0 (last arg)
            XCTAssertEqual(args[2], Bundle.main.bundlePath)
        }
    }

    func testRelaunchTerminatesAfterDelay() {
        let controller = TestableSystemAppLifecycleController()
        let mockProcess = MockAppLifecycleProcessRunner()
        controller.processFactory = { mockProcess }

        let expectation = XCTestExpectation(description: "Wait for termination")
        controller.terminateExpectation = expectation

        controller.relaunch()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(controller.terminateCalled)
    }

    func testFallbackRelaunchConfiguresNewInstance() {
        let controller = TestableSystemAppLifecycleController()
        // Use a process runner that throws to trigger fallback
        controller.processFactory = { MockFailingProcessRunner() }

        let expectation = XCTestExpectation(description: "Fallback opener called")
        // Use a class wrapper to safely capture in @Sendable closure
        final class ConfigCapture: @unchecked Sendable {
            var config: NSWorkspace.OpenConfiguration?
        }
        let capture = ConfigCapture()

        controller.workspaceAppOpener = { url, config, completion in
            capture.config = config
            expectation.fulfill()
            // Simulate success
            completion(nil, nil)
        }

        controller.relaunch()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertNotNil(capture.config)
        XCTAssertTrue(capture.config?.createsNewApplicationInstance ?? false)
    }
}
