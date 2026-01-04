import XCTest

@testable import MiddleDrag

final class MenuBarControllerTests: XCTestCase {

    var mockDevice: MockDeviceMonitor!
    var manager: MultitouchManager!
    var preferences: UserPreferences!
    var controller: MenuBarController!
    var notificationExpectation: XCTestExpectation?
    var receivedNotificationObject: Any?

    override func setUp() {
        super.setUp()
        mockDevice = MockDeviceMonitor()
        manager = MultitouchManager(
            deviceProviderFactory: { self.mockDevice }, eventTapSetup: { true })
        preferences = UserPreferences()
        controller = MenuBarController(multitouchManager: manager, preferences: preferences)
    }

    override func tearDown() {
        NotificationCenter.default.removeObserver(self)
        manager.stop()
        controller = nil
        manager = nil
        mockDevice = nil
        preferences = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitializationCreatesController() {
        XCTAssertNotNil(controller)
    }

    func testInitializationWithDefaultPreferences() {
        let defaultPrefs = UserPreferences()
        let ctrl = MenuBarController(multitouchManager: manager, preferences: defaultPrefs)
        XCTAssertNotNil(ctrl)
    }

    func testInitializationWithCustomPreferences() {
        var customPrefs = UserPreferences()
        customPrefs.launchAtLogin = true
        customPrefs.dragSensitivity = 2.0
        customPrefs.blockSystemGestures = true

        let ctrl = MenuBarController(multitouchManager: manager, preferences: customPrefs)
        XCTAssertNotNil(ctrl)
    }

    // MARK: - Build Menu Tests

    func testBuildMenuDoesNotCrash() {
        XCTAssertNoThrow(controller.buildMenu())
    }

    func testBuildMenuMultipleTimes() {
        // Should be safe to rebuild menu multiple times
        for _ in 1...5 {
            XCTAssertNoThrow(controller.buildMenu())
        }
    }

    // MARK: - Update Status Icon Tests

    func testUpdateStatusIconEnabledDoesNotCrash() {
        XCTAssertNoThrow(controller.updateStatusIcon(enabled: true))
    }

    func testUpdateStatusIconDisabledDoesNotCrash() {
        XCTAssertNoThrow(controller.updateStatusIcon(enabled: false))
    }

    func testUpdateStatusIconMultipleTimes() {
        // Toggle status icon multiple times
        for i in 0..<10 {
            XCTAssertNoThrow(controller.updateStatusIcon(enabled: i % 2 == 0))
        }
    }

    // MARK: - Notification Tests

    func testPreferencesChangedNotificationName() {
        // Verify notification name is defined correctly
        XCTAssertEqual(
            Notification.Name.preferencesChanged.rawValue,
            "MiddleDragPreferencesChanged"
        )
    }

    func testLaunchAtLoginChangedNotificationName() {
        // Verify notification name is defined correctly
        XCTAssertEqual(
            Notification.Name.launchAtLoginChanged.rawValue,
            "MiddleDragLaunchAtLoginChanged"
        )
    }

    // MARK: - Manager Integration Tests

    func testControllerWithStartedManager() {
        manager.start()
        XCTAssertTrue(manager.isEnabled)

        // Rebuild menu while manager is running
        XCTAssertNoThrow(controller.buildMenu())
        XCTAssertNoThrow(controller.updateStatusIcon(enabled: true))

        manager.stop()
    }

    func testControllerWithStoppedManager() {
        manager.stop()
        XCTAssertFalse(manager.isEnabled)

        // Operations should still work
        XCTAssertNoThrow(controller.buildMenu())
        XCTAssertNoThrow(controller.updateStatusIcon(enabled: false))
    }

    func testControllerWithToggleEnabled() {
        manager.start()
        XCTAssertTrue(manager.isEnabled)

        manager.toggleEnabled()
        XCTAssertFalse(manager.isEnabled)

        // Rebuild menu after toggle
        XCTAssertNoThrow(controller.buildMenu())

        manager.stop()
    }

    // MARK: - Preferences State Tests

    func testPreferencesMiddleDragEnabled() {
        var prefs = UserPreferences()
        prefs.middleDragEnabled = true
        let ctrl = MenuBarController(multitouchManager: manager, preferences: prefs)
        XCTAssertNotNil(ctrl)
    }

    func testPreferencesMiddleDragDisabled() {
        var prefs = UserPreferences()
        prefs.middleDragEnabled = false
        let ctrl = MenuBarController(multitouchManager: manager, preferences: prefs)
        XCTAssertNotNil(ctrl)
    }

    func testPreferencesWithPalmRejectionEnabled() {
        var prefs = UserPreferences()
        prefs.exclusionZoneEnabled = true
        prefs.exclusionZoneSize = 0.20
        prefs.requireModifierKey = true
        prefs.modifierKeyType = .option
        prefs.contactSizeFilterEnabled = true
        prefs.maxContactSize = 2.0

        let ctrl = MenuBarController(multitouchManager: manager, preferences: prefs)
        XCTAssertNotNil(ctrl)
        ctrl.buildMenu()  // Should create palm rejection submenu
    }

    func testPreferencesWithAllSensitivityLevels() {
        let sensitivities: [Double] = [0.5, 0.75, 1.0, 1.5, 2.0]

        for sensitivity in sensitivities {
            var prefs = UserPreferences()
            prefs.dragSensitivity = sensitivity
            let ctrl = MenuBarController(multitouchManager: manager, preferences: prefs)
            XCTAssertNotNil(ctrl)
        }
    }

    // MARK: - Configuration Sync Tests

    func testManagerConfigurationUpdate() {
        var config = GestureConfiguration()
        config.sensitivity = 1.5
        config.tapThreshold = 0.2
        config.middleDragEnabled = false

        manager.updateConfiguration(config)

        XCTAssertEqual(manager.configuration.sensitivity, 1.5, accuracy: 0.001)
        XCTAssertEqual(manager.configuration.tapThreshold, 0.2, accuracy: 0.001)
        XCTAssertFalse(manager.configuration.middleDragEnabled)
    }

    func testManagerConfigurationWithPalmRejection() {
        var config = GestureConfiguration()
        config.exclusionZoneEnabled = true
        config.exclusionZoneSize = 0.25
        config.requireModifierKey = true
        config.modifierKeyType = .command
        config.contactSizeFilterEnabled = true
        config.maxContactSize = 1.0

        manager.updateConfiguration(config)

        XCTAssertTrue(manager.configuration.exclusionZoneEnabled)
        XCTAssertEqual(manager.configuration.exclusionZoneSize, 0.25, accuracy: 0.001)
        XCTAssertTrue(manager.configuration.requireModifierKey)
        XCTAssertEqual(manager.configuration.modifierKeyType, .command)
        XCTAssertTrue(manager.configuration.contactSizeFilterEnabled)
        XCTAssertEqual(manager.configuration.maxContactSize, 1.0, accuracy: 0.001)
    }

    // MARK: - Edge Case Tests

    func testControllerWithNilManagerState() {
        // Test with manager that hasn't been started
        let freshMock = MockDeviceMonitor()
        let freshManager = MultitouchManager(
            deviceProviderFactory: { freshMock }, eventTapSetup: { true })
        let ctrl = MenuBarController(
            multitouchManager: freshManager, preferences: UserPreferences())

        XCTAssertNotNil(ctrl)
        XCTAssertNoThrow(ctrl.buildMenu())
    }

    func testRebuildMenuAfterPreferencesChange() {
        preferences.launchAtLogin = true
        controller.buildMenu()

        preferences.launchAtLogin = false
        controller.buildMenu()

        preferences.blockSystemGestures = true
        controller.buildMenu()

        // Should not crash
        XCTAssertNotNil(controller)
    }

    func testModifierKeyTypeAllCases() {
        for keyType in ModifierKeyType.allCases {
            var prefs = UserPreferences()
            prefs.requireModifierKey = true
            prefs.modifierKeyType = keyType

            let ctrl = MenuBarController(multitouchManager: manager, preferences: prefs)
            XCTAssertNotNil(ctrl)
            ctrl.buildMenu()
        }
    }

    func testExclusionZoneSizeOptions() {
        let sizes: [Double] = [0.10, 0.15, 0.20, 0.25]

        for size in sizes {
            var prefs = UserPreferences()
            prefs.exclusionZoneEnabled = true
            prefs.exclusionZoneSize = size

            let ctrl = MenuBarController(multitouchManager: manager, preferences: prefs)
            XCTAssertNotNil(ctrl)
            ctrl.buildMenu()
        }
    }

    func testContactSizeThresholdOptions() {
        let thresholds: [Double] = [1.0, 1.5, 2.0]

        for threshold in thresholds {
            var prefs = UserPreferences()
            prefs.contactSizeFilterEnabled = true
            prefs.maxContactSize = threshold

            let ctrl = MenuBarController(multitouchManager: manager, preferences: prefs)
            XCTAssertNotNil(ctrl)
            ctrl.buildMenu()
        }
    }

    // MARK: - Action Method Tests (using perform(_:))
    // Note: UserPreferences is a struct (value type), so the controller's internal
    // copy is modified, not the test's copy. We verify methods execute without crash.

    func testToggleEnabledViaSelector() {
        manager.start()
        XCTAssertTrue(manager.isEnabled)

        // Invoke the private @objc method via selector
        controller.perform(Selector(("toggleEnabled")))

        // The toggle should have been called
        XCTAssertFalse(manager.isEnabled)

        // Toggle back
        controller.perform(Selector(("toggleEnabled")))
        XCTAssertTrue(manager.isEnabled)

        manager.stop()
    }

    func testToggleTapToClickViaSelector() {
        // Initial state
        let initialState = preferences.tapToClickEnabled

        // Invoke private @objc method
        XCTAssertNoThrow(controller.perform(Selector(("toggleTapToClick"))))

        // Should have toggled locally
        XCTAssertNotEqual(preferences.tapToClickEnabled, initialState)

        // Configuration update propagation is tested in sync tests, but we verify no crash here
    }

    func testToggleMiddleDragViaSelector() {
        manager.start()

        // Invoke the private @objc method via selector - should not throw
        XCTAssertNoThrow(controller.perform(Selector(("toggleMiddleDrag"))))

        manager.stop()
    }

    func testToggleLaunchAtLoginViaSelector() {
        // Invoke the private @objc method via selector - should not throw
        XCTAssertNoThrow(controller.perform(Selector(("toggleLaunchAtLogin"))))
    }

    // NOTE: testToggleSystemGestureBlockingViaSelector removed because
    // toggleSystemGestureBlocking() calls AlertHelper.showSystemGestureWarning()
    // which invokes NSAlert().runModal() and blocks indefinitely.

    func testToggleExclusionZoneViaSelector() {
        // Invoke the private @objc method via selector - should not throw
        XCTAssertNoThrow(controller.perform(Selector(("toggleExclusionZone"))))
    }

    func testToggleRequireModifierKeyViaSelector() {
        // Invoke the private @objc method via selector - should not throw
        XCTAssertNoThrow(controller.perform(Selector(("toggleRequireModifierKey"))))
    }

    func testToggleContactSizeFilterViaSelector() {
        // Invoke the private @objc method via selector - should not throw
        XCTAssertNoThrow(controller.perform(Selector(("toggleContactSizeFilter"))))
    }

    func testToggleCrashReportingViaSelector() {
        // Store initial state
        let initialState = CrashReporter.shared.isEnabled

        // Invoke the private @objc method via selector
        controller.perform(Selector(("toggleCrashReporting")))

        // Should have toggled (CrashReporter is a singleton, so state persists)
        XCTAssertNotEqual(CrashReporter.shared.isEnabled, initialState)

        // Restore original state
        if CrashReporter.shared.isEnabled != initialState {
            CrashReporter.shared.isEnabled = initialState
        }
    }

    func testTogglePerformanceMonitoringViaSelector() {
        // Store initial state
        let initialState = CrashReporter.shared.performanceMonitoringEnabled

        // Invoke the private @objc method via selector
        controller.perform(Selector(("togglePerformanceMonitoring")))

        // Should have toggled
        XCTAssertNotEqual(CrashReporter.shared.performanceMonitoringEnabled, initialState)

        // Restore original state
        if CrashReporter.shared.performanceMonitoringEnabled != initialState {
            CrashReporter.shared.performanceMonitoringEnabled = initialState
        }
    }

    // MARK: - Notification Posting Tests

    func testPreferencesChangedNotificationPosted() {
        manager.start()
        let expectation = XCTestExpectation(description: "Preferences changed notification")

        let observer = NotificationCenter.default.addObserver(
            forName: .preferencesChanged,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        // Trigger action that posts notification
        controller.perform(Selector(("toggleMiddleDrag")))

        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)

        manager.stop()
    }

    func testLaunchAtLoginNotificationPosted() {
        let expectation = XCTestExpectation(description: "Launch at login changed notification")

        let observer = NotificationCenter.default.addObserver(
            forName: .launchAtLoginChanged,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        // Trigger action that posts notification
        controller.perform(Selector(("toggleLaunchAtLogin")))

        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - Menu Item Action Tests
    // These test the action methods with menu items (no assertion on preferences
    // since UserPreferences is a value type copied into the controller)

    func testSetSensitivityWithMenuItem() {
        // Create a menu item with represented object
        let menuItem = NSMenuItem(title: "Test", action: nil, keyEquivalent: "")
        menuItem.representedObject = Float(1.5)

        // Invoke setSensitivity via selector with the menu item - should not crash
        XCTAssertNoThrow(controller.perform(Selector(("setSensitivity:")), with: menuItem))
    }

    func testSetExclusionZoneSizeWithMenuItem() {
        let menuItem = NSMenuItem(title: "Test", action: nil, keyEquivalent: "")
        menuItem.representedObject = Double(0.25)

        // Invoke via selector - should not crash
        XCTAssertNoThrow(controller.perform(Selector(("setExclusionZoneSize:")), with: menuItem))
    }

    func testSetModifierKeyTypeWithMenuItem() {
        let menuItem = NSMenuItem(title: "Test", action: nil, keyEquivalent: "")
        menuItem.representedObject = ModifierKeyType.command.rawValue

        // Invoke via selector - should not crash
        XCTAssertNoThrow(controller.perform(Selector(("setModifierKeyType:")), with: menuItem))
    }

    func testSetContactSizeThresholdWithMenuItem() {
        let menuItem = NSMenuItem(title: "Test", action: nil, keyEquivalent: "")
        menuItem.representedObject = Double(2.0)

        // Invoke via selector - should not crash
        XCTAssertNoThrow(controller.perform(Selector(("setContactSizeThreshold:")), with: menuItem))
    }

    func testToggleMinimumWindowSizeFilterViaSelector() {
        // Invoke the private @objc method via selector - should not throw
        XCTAssertNoThrow(controller.perform(Selector(("toggleMinimumWindowSizeFilter"))))
    }

    func testSetMinimumWindowSizeWithMenuItem() {
        let menuItem = NSMenuItem(title: "Test", action: nil, keyEquivalent: "")
        menuItem.representedObject = Double(200)

        // Invoke via selector - should not crash
        XCTAssertNoThrow(controller.perform(Selector(("setMinimumWindowSize:")), with: menuItem))
    }

    func testBuildMenuWithMinimumWindowSizeFilterEnabled() {
        var prefs = UserPreferences()
        prefs.minimumWindowSizeFilterEnabled = true
        prefs.minimumWindowWidth = 100
        prefs.minimumWindowHeight = 100

        let ctrl = MenuBarController(multitouchManager: manager, preferences: prefs)
        XCTAssertNotNil(ctrl)
        ctrl.buildMenu()  // Should create window size submenu items
    }

    func testBuildMenuWithAllPalmRejectionOptionsEnabled() {
        var prefs = UserPreferences()
        prefs.exclusionZoneEnabled = true
        prefs.requireModifierKey = true
        prefs.contactSizeFilterEnabled = true
        prefs.minimumWindowSizeFilterEnabled = true

        let ctrl = MenuBarController(multitouchManager: manager, preferences: prefs)
        XCTAssertNotNil(ctrl)
        ctrl.buildMenu()  // Should create all submenu items
    }

    // MARK: - Multiple Toggle Cycles

    func testMultipleToggleCycles() {
        manager.start()

        // Toggle enabled multiple times
        for _ in 0..<5 {
            controller.perform(Selector(("toggleEnabled")))
        }

        // Toggle preferences multiple times
        for _ in 0..<3 {
            controller.perform(Selector(("toggleMiddleDrag")))
            controller.perform(Selector(("toggleExclusionZone")))
            controller.perform(Selector(("toggleRequireModifierKey")))
            controller.perform(Selector(("toggleContactSizeFilter")))
        }

        // Should not crash
        XCTAssertNotNil(controller)

        manager.stop()
    }
}
