import XCTest

@testable import MiddleDrag

/// Tests for MultitouchManager's HID device watcher integration.
///
/// These tests validate the late-connecting Bluetooth trackpad fix:
/// when MiddleDrag launches at login before a Bluetooth Magic Trackpad
/// has connected, the HID watcher detects the connection and starts
/// monitoring automatically.
///
/// Separated from MultitouchManagerTests to avoid modifying existing
/// test infrastructure.
final class MultitouchManagerHIDTests: XCTestCase {

    // MARK: - Initial Start Failure Path

    func testStartWithNoDevicesDoesNotMonitor() {
        let mockDevice = unsafe MockDeviceMonitor()
        unsafe mockDevice.startShouldSucceed = false

        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe mockDevice },
            eventTapSetup: { true }
        )

        manager.start()

        XCTAssertFalse(manager.isMonitoring)
        XCTAssertFalse(manager.isEnabled)

        manager.stop()
    }

    // MARK: - HID Connection → Fresh Start

    func testHIDConnectionStartsMonitoringWhenPreviouslyFailed() {
        // Simulates: launch with no device → trackpad connects later
        var deviceShouldSucceed = false
        var factoryCallCount = 0

        let manager = MultitouchManager(
            deviceProviderFactory: {
                factoryCallCount += 1
                let mock = unsafe MockDeviceMonitor()
                unsafe mock.startShouldSucceed = deviceShouldSucceed
                return unsafe mock
            },
            eventTapSetup: { true }
        )

        // Initial start fails (no device yet)
        manager.start()
        XCTAssertFalse(manager.isMonitoring)
        XCTAssertEqual(factoryCallCount, 1)

        // Device becomes available
        deviceShouldSucceed = true

        // Simulate HID connection callback
        let watcher = HIDDeviceWatcher()
        manager.hidDeviceWatcherDidDetectDeviceConnection(watcher)

        XCTAssertTrue(manager.isMonitoring)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(factoryCallCount, 2)

        manager.stop()
    }

    func testHIDConnectionWithEventTapFailure() {
        var eventTapShouldSucceed = false

        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe MockDeviceMonitor() },
            eventTapSetup: { eventTapShouldSucceed }
        )

        // Initial start fails (event tap)
        manager.start()
        XCTAssertFalse(manager.isMonitoring)

        // HID connection, but event tap still fails
        let watcher = HIDDeviceWatcher()
        manager.hidDeviceWatcherDidDetectDeviceConnection(watcher)
        XCTAssertFalse(manager.isMonitoring)

        // Now event tap works
        eventTapShouldSucceed = true
        manager.hidDeviceWatcherDidDetectDeviceConnection(watcher)
        XCTAssertTrue(manager.isMonitoring)

        manager.stop()
    }

    func testHIDConnectionWhenDeviceStillUnavailable() {
        // HID fires for a non-trackpad digitizer device
        let manager = MultitouchManager(
            deviceProviderFactory: {
                let mock = unsafe MockDeviceMonitor()
                unsafe mock.startShouldSucceed = false
                return unsafe mock
            },
            eventTapSetup: { true }
        )

        manager.start()
        XCTAssertFalse(manager.isMonitoring)

        let watcher = HIDDeviceWatcher()
        manager.hidDeviceWatcherDidDetectDeviceConnection(watcher)

        XCTAssertFalse(manager.isMonitoring)
        XCTAssertFalse(manager.isEnabled)

        manager.stop()
    }

    // MARK: - HID Connection → Restart (already monitoring)

    func testHIDConnectionRestartsWhenAlreadyMonitoring() {
        var factoryCallCount = 0
        let manager = MultitouchManager(
            deviceProviderFactory: {
                factoryCallCount += 1
                return unsafe MockDeviceMonitor()
            },
            eventTapSetup: { true }
        )

        manager.start()
        XCTAssertTrue(manager.isMonitoring)
        XCTAssertEqual(factoryCallCount, 1)

        // HID connection while already monitoring triggers restart
        let watcher = HIDDeviceWatcher()
        manager.hidDeviceWatcherDidDetectDeviceConnection(watcher)

        // restart() is async — wait for completion
        let expectation = XCTestExpectation(
            description: "Restart complete")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MultitouchManager.restartCleanupDelay + 0.1
        ) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertTrue(manager.isMonitoring)
        XCTAssertEqual(factoryCallCount, 2)

        manager.stop()
    }

    // MARK: - HID Disconnection

    func testHIDDisconnectionRestartsWhenMonitoring() {
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe MockDeviceMonitor() },
            eventTapSetup: { true }
        )

        manager.start()
        XCTAssertTrue(manager.isMonitoring)

        let watcher = HIDDeviceWatcher()
        manager.hidDeviceWatcherDidDetectDeviceDisconnection(watcher)

        // restart() is async
        let expectation = XCTestExpectation(
            description: "Restart complete")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MultitouchManager.restartCleanupDelay + 0.1
        ) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        XCTAssertTrue(manager.isMonitoring)
        manager.stop()
    }

    func testHIDDisconnectionNoOpWhenNotMonitoring() {
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe MockDeviceMonitor() },
            eventTapSetup: { true }
        )

        XCTAssertFalse(manager.isMonitoring)

        let watcher = HIDDeviceWatcher()
        XCTAssertNoThrow(
            manager.hidDeviceWatcherDidDetectDeviceDisconnection(watcher)
        )
        XCTAssertFalse(manager.isMonitoring)
    }

    // MARK: - Notification

    func testDeviceConnectionPostsNotification() {
        var deviceShouldSucceed = false
        let manager = MultitouchManager(
            deviceProviderFactory: {
                let mock = unsafe MockDeviceMonitor()
                unsafe mock.startShouldSucceed = deviceShouldSucceed
                return unsafe mock
            },
            eventTapSetup: { true }
        )

        manager.start()
        XCTAssertFalse(manager.isMonitoring)

        let notificationExpectation = XCTNSNotificationExpectation(
            name: .deviceConnectionStateChanged
        )

        deviceShouldSucceed = true
        let watcher = HIDDeviceWatcher()
        manager.hidDeviceWatcherDidDetectDeviceConnection(watcher)

        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertTrue(manager.isMonitoring)

        manager.stop()
    }

    // MARK: - Rapid Connections

    func testRapidHIDConnectionsCoalesced() {
        var factoryCallCount = 0
        let manager = MultitouchManager(
            deviceProviderFactory: {
                factoryCallCount += 1
                return unsafe MockDeviceMonitor()
            },
            eventTapSetup: { true }
        )

        manager.start()
        XCTAssertEqual(factoryCallCount, 1)

        // Rapid HID connections — restart debouncing coalesces
        let watcher = HIDDeviceWatcher()
        for _ in 0..<5 {
            manager.hidDeviceWatcherDidDetectDeviceConnection(watcher)
        }

        let expectation = XCTestExpectation(
            description: "Restarts settle")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MultitouchManager.restartCleanupDelay
                + MultitouchManager.minimumRestartInterval + 0.2
        ) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)

        XCTAssertTrue(manager.isMonitoring)
        XCTAssertLessThanOrEqual(factoryCallCount, 3,
            "Rapid HID connections should be coalesced by restart debouncing")

        manager.stop()
    }

    // MARK: - Stop Cleanup

    func testStopPreventsLaterHIDRestart() {
        let manager = MultitouchManager(
            deviceProviderFactory: { unsafe MockDeviceMonitor() },
            eventTapSetup: { true }
        )

        manager.start()
        XCTAssertTrue(manager.isMonitoring)

        manager.stop()
        XCTAssertFalse(manager.isMonitoring)

        // After full stop, no spontaneous restart should happen
        let expectation = XCTestExpectation(
            description: "No restart")
        DispatchQueue.main.asyncAfter(
            deadline: .now() + HIDDeviceWatcher.debounceInterval + 0.5
        ) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)

        XCTAssertFalse(manager.isMonitoring,
            "Manager should stay stopped after stop()")
    }
}
