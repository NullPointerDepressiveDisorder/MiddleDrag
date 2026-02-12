import XCTest

@testable import MiddleDragCore

@MainActor @unsafe final class MenuBarControllerTests: XCTestCase {

    var mockDevice: MockDeviceMonitor!
    var manager: MultitouchManager!
    var preferences: UserPreferences!
    var controller: MenuBarController!
    var notificationExpectation: XCTestExpectation?
    var receivedNotificationObject: Any?

    override func setUpWithError() throws {
        try super.setUpWithError()
        unsafe mockDevice = unsafe MockDeviceMonitor()
        unsafe manager = MultitouchManager(
            deviceProviderFactory: { unsafe self.mockDevice }, eventTapSetup: { true })
        unsafe preferences = UserPreferences()
        unsafe controller = unsafe MenuBarController(multitouchManager: manager, preferences: preferences)
    }

    override func tearDown() {
        unsafe NotificationCenter.default.removeObserver(self)
        unsafe manager.stop()
        unsafe controller = nil
        unsafe manager = nil
        unsafe mockDevice = nil
        unsafe preferences = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitializationCreatesController() {
        unsafe XCTAssertNotNil(controller)
    }

    func testInitializationWithDefaultPreferences() {
        let defaultPrefs = UserPreferences()
        let ctrl = unsafe MenuBarController(multitouchManager: manager, preferences: defaultPrefs)
        XCTAssertNotNil(ctrl)
    }

    func testInitializationWithCustomPreferences() {
        var customPrefs = UserPreferences()
        customPrefs.launchAtLogin = true
        customPrefs.dragSensitivity = 2.0
        customPrefs.blockSystemGestures = true

        let ctrl = unsafe MenuBarController(multitouchManager: manager, preferences: customPrefs)
        XCTAssertNotNil(ctrl)
    }

    // MARK: - Build Menu Tests

    func testBuildMenuDoesNotCrash() {
        unsafe XCTAssertNoThrow(controller.buildMenu())
    }

    func testBuildMenuMultipleTimes() {
        // Should be safe to rebuild menu multiple times
        for _ in 1...5 {
            unsafe XCTAssertNoThrow(controller.buildMenu())
        }
    }

    // MARK: - Update Status Icon Tests

    func testUpdateStatusIconEnabledDoesNotCrash() {
        unsafe XCTAssertNoThrow(controller.updateStatusIcon(enabled: true))
    }

    func testUpdateStatusIconDisabledDoesNotCrash() {
        unsafe XCTAssertNoThrow(controller.updateStatusIcon(enabled: false))
    }

    func testUpdateStatusIconMultipleTimes() {
        // Toggle status icon multiple times
        for i in 0..<10 {
            unsafe XCTAssertNoThrow(controller.updateStatusIcon(enabled: i % 2 == 0))
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
        unsafe manager.start()
        unsafe XCTAssertTrue(manager.isEnabled)

        // Rebuild menu while manager is running
        unsafe XCTAssertNoThrow(controller.buildMenu())
        unsafe XCTAssertNoThrow(controller.updateStatusIcon(enabled: true))

        unsafe manager.stop()
    }

    func testControllerWithStoppedManager() {
        unsafe manager.stop()
        unsafe XCTAssertFalse(manager.isEnabled)

        // Operations should still work
        unsafe XCTAssertNoThrow(controller.buildMenu())
        unsafe XCTAssertNoThrow(controller.updateStatusIcon(enabled: false))
    }

    func testControllerWithToggleEnabled() {
        unsafe manager.start()
        unsafe XCTAssertTrue(manager.isEnabled)

        unsafe manager.toggleEnabled()
        unsafe XCTAssertFalse(manager.isEnabled)

        // Rebuild menu after toggle
        unsafe XCTAssertNoThrow(controller.buildMenu())

        unsafe manager.stop()
    }

    // MARK: - Preferences State Tests

    func testPreferencesMiddleDragEnabled() {
        var prefs = UserPreferences()
        prefs.middleDragEnabled = true
        let ctrl = unsafe MenuBarController(multitouchManager: manager, preferences: prefs)
        XCTAssertNotNil(ctrl)
    }

    func testPreferencesMiddleDragDisabled() {
        var prefs = UserPreferences()
        prefs.middleDragEnabled = false
        let ctrl = unsafe MenuBarController(multitouchManager: manager, preferences: prefs)
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

        let ctrl = unsafe MenuBarController(multitouchManager: manager, preferences: prefs)
        XCTAssertNotNil(ctrl)
        ctrl.buildMenu()  // Should create palm rejection submenu
    }

    func testPreferencesWithAllSensitivityLevels() {
        let sensitivities: [Double] = [0.5, 0.75, 1.0, 1.5, 2.0]

        for sensitivity in sensitivities {
            var prefs = UserPreferences()
            prefs.dragSensitivity = sensitivity
            let ctrl = unsafe MenuBarController(multitouchManager: manager, preferences: prefs)
            XCTAssertNotNil(ctrl)
        }
    }

    // MARK: - Configuration Sync Tests

    func testManagerConfigurationUpdate() {
        var config = GestureConfiguration()
        config.sensitivity = 1.5
        config.tapThreshold = 0.2
        config.middleDragEnabled = false

        unsafe manager.updateConfiguration(config)

        unsafe XCTAssertEqual(manager.configuration.sensitivity, 1.5, accuracy: 0.001)
        unsafe XCTAssertEqual(manager.configuration.tapThreshold, 0.2, accuracy: 0.001)
        unsafe XCTAssertFalse(manager.configuration.middleDragEnabled)
    }

    func testManagerConfigurationWithPalmRejection() {
        var config = GestureConfiguration()
        config.exclusionZoneEnabled = true
        config.exclusionZoneSize = 0.25
        config.requireModifierKey = true
        config.modifierKeyType = .command
        config.contactSizeFilterEnabled = true
        config.maxContactSize = 1.0

        unsafe manager.updateConfiguration(config)

        unsafe XCTAssertTrue(manager.configuration.exclusionZoneEnabled)
        unsafe XCTAssertEqual(manager.configuration.exclusionZoneSize, 0.25, accuracy: 0.001)
        unsafe XCTAssertTrue(manager.configuration.requireModifierKey)
        unsafe XCTAssertEqual(manager.configuration.modifierKeyType, .command)
        unsafe XCTAssertTrue(manager.configuration.contactSizeFilterEnabled)
        unsafe XCTAssertEqual(manager.configuration.maxContactSize, 1.0, accuracy: 0.001)
    }

    // MARK: - Edge Case Tests

    func testControllerWithNilManagerState() {
        // Test with manager that hasn't been started
        let freshMock = unsafe MockDeviceMonitor()
        let freshManager = MultitouchManager(
            deviceProviderFactory: { unsafe freshMock }, eventTapSetup: { true })
        let ctrl = MenuBarController(
            multitouchManager: freshManager, preferences: UserPreferences())

        XCTAssertNotNil(ctrl)
        XCTAssertNoThrow(ctrl.buildMenu())
    }

    func testRebuildMenuAfterPreferencesChange() {
        unsafe preferences.launchAtLogin = true
        unsafe controller.buildMenu()

        unsafe preferences.launchAtLogin = false
        unsafe controller.buildMenu()

        unsafe preferences.blockSystemGestures = true
        unsafe controller.buildMenu()

        // Should not crash
        unsafe XCTAssertNotNil(controller)
    }

    func testModifierKeyTypeAllCases() {
        for keyType in ModifierKeyType.allCases {
            var prefs = UserPreferences()
            prefs.requireModifierKey = true
            prefs.modifierKeyType = keyType

            let ctrl = unsafe MenuBarController(multitouchManager: manager, preferences: prefs)
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

            let ctrl = unsafe MenuBarController(multitouchManager: manager, preferences: prefs)
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

            let ctrl = unsafe MenuBarController(multitouchManager: manager, preferences: prefs)
            XCTAssertNotNil(ctrl)
            ctrl.buildMenu()
        }
    }

    // MARK: - Action Method Tests (using perform(_:))
    // Note: UserPreferences is a struct (value type), so the controller's internal
    // copy is modified, not the test's copy. We verify methods execute without crash.

    func testToggleEnabledViaSelector() {
        unsafe manager.start()
        unsafe XCTAssertTrue(manager.isEnabled)

        // Invoke the private @objc method via selector
        unsafe controller.perform(#selector(MenuBarController.toggleEnabled))

        // The toggle should have been called
        unsafe XCTAssertFalse(manager.isEnabled)

        // Toggle back
        unsafe controller.perform(#selector(MenuBarController.toggleEnabled))
        unsafe XCTAssertTrue(manager.isEnabled)

        unsafe manager.stop()
    }

    func testToggleTapToClickViaSelector() {
        // Initial state of manager
        let initialManagerState = unsafe manager.configuration.tapToClickEnabled

        // Invoke private @objc method
        unsafe XCTAssertNoThrow(controller.perform(#selector(MenuBarController.toggleTapToClick)))

        // Should have updated the manager's configuration
        unsafe XCTAssertNotEqual(manager.configuration.tapToClickEnabled, initialManagerState)
        unsafe XCTAssertEqual(manager.configuration.tapToClickEnabled, !initialManagerState)
    }

    func testToggleMiddleDragViaSelector() {
        unsafe manager.start()

        // Invoke the private @objc method via selector - should not throw
        unsafe XCTAssertNoThrow(controller.perform(#selector(MenuBarController.toggleMiddleDrag)))

        unsafe manager.stop()
    }

    func testToggleLaunchAtLoginViaSelector() {
        // Invoke the private @objc method via selector - should not throw
        unsafe XCTAssertNoThrow(controller.perform(#selector(MenuBarController.toggleLaunchAtLogin)))
    }

    // NOTE: testToggleSystemGestureBlockingViaSelector removed because
    // toggleSystemGestureBlocking() calls AlertHelper.showSystemGestureWarning()
    // which invokes NSAlert().runModal() and blocks indefinitely.

    func testToggleExclusionZoneViaSelector() {
        // Invoke the private @objc method via selector - should not throw
        unsafe XCTAssertNoThrow(controller.perform(#selector(MenuBarController.toggleExclusionZone)))
    }

    func testToggleRequireModifierKeyViaSelector() {
        // Invoke the private @objc method via selector - should not throw
        unsafe XCTAssertNoThrow(controller.perform(#selector(MenuBarController.toggleRequireModifierKey)))
    }

    func testToggleContactSizeFilterViaSelector() {
        // Invoke the private @objc method via selector - should not throw
        unsafe XCTAssertNoThrow(controller.perform(#selector(MenuBarController.toggleContactSizeFilter)))
    }

    func testToggleCrashReportingViaSelector() {
        // Store initial state
        let initialState = CrashReporter.shared.isEnabled

        // Invoke the private @objc method via selector
        unsafe controller.perform(#selector(MenuBarController.toggleCrashReporting))

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
        unsafe controller.perform(#selector(MenuBarController.togglePerformanceMonitoring))

        // Should have toggled
        XCTAssertNotEqual(CrashReporter.shared.performanceMonitoringEnabled, initialState)

        // Restore original state
        if CrashReporter.shared.performanceMonitoringEnabled != initialState {
            CrashReporter.shared.performanceMonitoringEnabled = initialState
        }
    }

    // MARK: - Notification Posting Tests

    func testPreferencesChangedNotificationPosted() {
        unsafe manager.start()
        let expectation = XCTestExpectation(description: "Preferences changed notification")

        let observer = NotificationCenter.default.addObserver(
            forName: .preferencesChanged,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        // Trigger action that posts notification
        unsafe controller.perform(#selector(MenuBarController.toggleMiddleDrag))

        unsafe wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)

        unsafe manager.stop()
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
        unsafe controller.perform(#selector(MenuBarController.toggleLaunchAtLogin))

        unsafe wait(for: [expectation], timeout: 1.0)
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
        unsafe XCTAssertNoThrow(controller.perform(#selector(MenuBarController.setSensitivity(_:)), with: menuItem))
    }

    func testSetExclusionZoneSizeWithMenuItem() {
        let menuItem = NSMenuItem(title: "Test", action: nil, keyEquivalent: "")
        menuItem.representedObject = Double(0.25)

        // Invoke via selector - should not crash
        unsafe XCTAssertNoThrow(controller.perform(#selector(MenuBarController.setExclusionZoneSize(_:)), with: menuItem))
    }

    func testSetModifierKeyTypeWithMenuItem() {
        let menuItem = NSMenuItem(title: "Test", action: nil, keyEquivalent: "")
        menuItem.representedObject = ModifierKeyType.command.rawValue

        // Invoke via selector - should not crash
        unsafe XCTAssertNoThrow(controller.perform(#selector(MenuBarController.setModifierKeyType(_:)), with: menuItem))
    }

    func testSetContactSizeThresholdWithMenuItem() {
        let menuItem = NSMenuItem(title: "Test", action: nil, keyEquivalent: "")
        menuItem.representedObject = Double(2.0)

        // Invoke via selector - should not crash
        unsafe XCTAssertNoThrow(controller.perform(#selector(MenuBarController.setContactSizeThreshold(_:)), with: menuItem))
    }

    func testToggleMinimumWindowSizeFilterViaSelector() {
        // Invoke the private @objc method via selector - should not throw
        unsafe XCTAssertNoThrow(controller.perform(#selector(MenuBarController.toggleMinimumWindowSizeFilter)))
    }

    func testSetMinimumWindowSizeWithMenuItem() {
        let menuItem = NSMenuItem(title: "Test", action: nil, keyEquivalent: "")
        menuItem.representedObject = Double(200)

        // Invoke via selector - should not crash
        unsafe XCTAssertNoThrow(controller.perform(#selector(MenuBarController.setMinimumWindowSize(_:)), with: menuItem))
    }

    func testBuildMenuWithMinimumWindowSizeFilterEnabled() {
        var prefs = UserPreferences()
        prefs.minimumWindowSizeFilterEnabled = true
        prefs.minimumWindowWidth = 100
        prefs.minimumWindowHeight = 100

        let ctrl = unsafe MenuBarController(multitouchManager: manager, preferences: prefs)
        XCTAssertNotNil(ctrl)
        ctrl.buildMenu()  // Should create window size submenu items
    }

    func testBuildMenuWithAllPalmRejectionOptionsEnabled() {
        var prefs = UserPreferences()
        prefs.exclusionZoneEnabled = true
        prefs.requireModifierKey = true
        prefs.contactSizeFilterEnabled = true
        prefs.minimumWindowSizeFilterEnabled = true

        let ctrl = unsafe MenuBarController(multitouchManager: manager, preferences: prefs)
        XCTAssertNotNil(ctrl)
        ctrl.buildMenu()  // Should create all submenu items
    }

    // MARK: - Multiple Toggle Cycles

    func testMultipleToggleCycles() {
        unsafe manager.start()

        // Toggle enabled multiple times
        for _ in 0..<5 {
            unsafe controller.perform(#selector(MenuBarController.toggleEnabled))
        }

        // Toggle preferences multiple times
        for _ in 0..<3 {
            unsafe controller.perform(#selector(MenuBarController.toggleMiddleDrag))
            unsafe controller.perform(#selector(MenuBarController.toggleExclusionZone))
            unsafe controller.perform(#selector(MenuBarController.toggleRequireModifierKey))
            unsafe controller.perform(#selector(MenuBarController.toggleContactSizeFilter))
        }

        // Should not crash
        unsafe XCTAssertNotNil(controller)

        unsafe manager.stop()
    }

    // MARK: - Allow Relift During Drag Tests

    func testToggleAllowReliftDuringDragViaSelector() {
        // Invoke the private @objc method via selector - should not throw
        unsafe XCTAssertNoThrow(controller.perform(#selector(MenuBarController.toggleAllowReliftDuringDrag)))
    }

    func testToggleAllowReliftDuringDragPostsNotification() {
        let expectation = XCTestExpectation(description: "Preferences changed notification")

        let observer = NotificationCenter.default.addObserver(
            forName: .preferencesChanged,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        unsafe controller.perform(#selector(MenuBarController.toggleAllowReliftDuringDrag))

        unsafe wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }

    func testBuildMenuWithAllowReliftEnabled() {
        var prefs = UserPreferences()
        prefs.allowReliftDuringDrag = true

        let ctrl = unsafe MenuBarController(multitouchManager: manager, preferences: prefs)
        XCTAssertNotNil(ctrl)
        ctrl.buildMenu()  // Should include relift option
    }

    // MARK: - Configure System Gestures Tests

    // Note: We cannot directly test configureSystemGestures as it calls AlertHelper
    // methods. However, we CAN verify the method exists and is callable with proper mocking.

    func testConfigureSystemGesturesMethodExists() {
        // Verify the selector exists
        let selector = #selector(MenuBarController.configureSystemGestures)
        unsafe XCTAssertTrue(controller.responds(to: selector))
    }

    // MARK: - Comprehensive Preferences Toggle Tests

    func testAllPreferenceTogglesInSequence() {
        unsafe manager.start()

        // Test all toggle methods in sequence
        unsafe controller.perform(#selector(MenuBarController.toggleMiddleDrag))
        unsafe controller.perform(#selector(MenuBarController.toggleExclusionZone))
        unsafe controller.perform(#selector(MenuBarController.toggleRequireModifierKey))
        unsafe controller.perform(#selector(MenuBarController.toggleContactSizeFilter))
        unsafe controller.perform(#selector(MenuBarController.toggleMinimumWindowSizeFilter))
        unsafe controller.perform(#selector(MenuBarController.toggleAllowReliftDuringDrag))
        unsafe controller.perform(#selector(MenuBarController.toggleCrashReporting))
        unsafe controller.perform(#selector(MenuBarController.togglePerformanceMonitoring))

        // All toggles should complete without crash
        unsafe XCTAssertNotNil(controller)

        unsafe manager.stop()
    }
    
    // MARK: - Force Release Stuck Drag Tests
    
    func testForceReleaseStuckDragDoesNotCrash() {
        unsafe manager.start()
        
        // Calling force release when not dragging should be safe
        unsafe XCTAssertNoThrow(controller.forceReleaseStuckDrag())
        
        unsafe manager.stop()
    }
    
    func testForceReleaseStuckDragMultipleTimes() {
        unsafe manager.start()
        
        // Calling force release multiple times rapidly should be safe
        for _ in 0..<5 {
            unsafe XCTAssertNoThrow(controller.forceReleaseStuckDrag())
        }
        
        unsafe manager.stop()
    }
    
    func testForceReleaseStuckDragWhenStopped() {
        // Controller should handle force release even when manager is stopped
        unsafe XCTAssertNoThrow(controller.forceReleaseStuckDrag())
    }
    
    func testForceReleaseStuckDragSelectorExists() {
        let selector = #selector(MenuBarController.forceReleaseStuckDrag)
        unsafe XCTAssertTrue(controller.responds(to: selector))
    }
}
