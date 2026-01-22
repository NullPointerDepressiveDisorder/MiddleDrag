import Cocoa

/// Manages the menu bar UI and user interactions
@MainActor
class MenuBarController: NSObject {

    // MARK: - Properties

    private var statusItem: NSStatusItem!
    private weak var multitouchManager: MultitouchManager?
    private var preferences: UserPreferences

    // Menu item tags for easy reference
    private enum MenuItemTag: Int {
        case enabled = 1
        case launchAtLogin = 2
        case middleDrag = 3
        case tapToClick = 4
    }

    // MARK: - Initialization

    init(multitouchManager: MultitouchManager, preferences: UserPreferences) {
        self.multitouchManager = multitouchManager
        self.preferences = preferences
        super.init()

        setupStatusItem()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if statusItem.button != nil {
            updateStatusIcon(enabled: multitouchManager?.isEnabled ?? false)
        }

        buildMenu()
    }

    func updateStatusIcon(enabled: Bool) {
        guard let button = statusItem.button else { return }

        let iconName = enabled ? "hand.raised.fingers.spread" : "hand.raised.slash"
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "MiddleDrag")
        button.image?.isTemplate = true

        // Animate the change and restore alpha when complete
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            button.animator().alphaValue = 0.7
        }, completionHandler: {
            // Ensure mutation happens on the main actor
            Task { @MainActor in
                button.alphaValue = 1.0
            }
        })
    }

    // MARK: - Menu Building

    func buildMenu() {
        let menu = NSMenu()

        // Status
        menu.addItem(createStatusItem())
        menu.addItem(NSMenuItem.separator())

        // Enable/Disable
        menu.addItem(createEnabledItem())
        menu.addItem(createTapToClickItem())
        menu.addItem(createMiddleDragItem())
        menu.addItem(NSMenuItem.separator())

        // Settings
        menu.addItem(createSensitivityMenu())
        menu.addItem(createAdvancedMenu())
        menu.addItem(NSMenuItem.separator())

        // App items
        menu.addItem(createMenuItem(title: "About MiddleDrag", action: #selector(showAbout)))
        menu.addItem(createLaunchAtLoginItem())
        menu.addItem(createCheckForUpdatesItem())
        menu.addItem(createAutoUpdateItem())
        menu.addItem(NSMenuItem.separator())

        // Actions
        menu.addItem(createMenuItem(title: "Quick Setup", action: #selector(showQuickSetup)))
        menu.addItem(createMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func createStatusItem() -> NSMenuItem {
        let isEnabled = multitouchManager?.isEnabled ?? false
        let title = isEnabled ? "MiddleDrag Active" : "MiddleDrag Disabled"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func createEnabledItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
        item.target = self  // IMPORTANT: Set target
        item.state = (multitouchManager?.isEnabled ?? false) ? .on : .off
        item.tag = MenuItemTag.enabled.rawValue
        return item
    }

    private func createMiddleDragItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Drag", action: #selector(toggleMiddleDrag), keyEquivalent: "")
        item.target = self
        let isMainEnabled = multitouchManager?.isEnabled ?? false
        // Only show checkmark and enable if main toggle is on
        item.isEnabled = isMainEnabled
        item.state = (isMainEnabled && preferences.middleDragEnabled) ? .on : .off
        item.tag = MenuItemTag.middleDrag.rawValue
        return item
    }

    private func createTapToClickItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Tap to Click", action: #selector(toggleTapToClick), keyEquivalent: "")
        item.target = self
        let isMainEnabled = multitouchManager?.isEnabled ?? false
        item.isEnabled = isMainEnabled
        item.state = (isMainEnabled && preferences.tapToClickEnabled) ? .on : .off
        item.tag = MenuItemTag.tapToClick.rawValue
        return item
    }

    private func createLaunchAtLoginItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        item.target = self  // IMPORTANT: Set target
        item.state = preferences.launchAtLogin ? .on : .off
        item.tag = MenuItemTag.launchAtLogin.rawValue
        return item
    }

    private func createCheckForUpdatesItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        item.target = self
        return item
    }

    private func createAutoUpdateItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Automatically Check for Updates", action: #selector(toggleAutoUpdate), keyEquivalent: "")
        item.target = self
        item.state = UpdateManager.shared.automaticallyChecksForUpdates ? .on : .off
        return item
    }

    private func createMenuItem(title: String, action: Selector, keyEquivalent: String = "")
        -> NSMenuItem
    {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self  // IMPORTANT: Set target
        return item
    }

    private func createSensitivityMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Drag Sensitivity", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let sensitivities: [(String, Float)] = [
            ("Slow (0.5x)", 0.5),
            ("Precision (0.75x)", 0.75),
            ("Normal (1x)", 1.0),
            ("Fast (1.5x)", 1.5),
            ("Very Fast (2x)", 2.0),
        ]

        for (title, value) in sensitivities {
            let menuItem = NSMenuItem(
                title: title, action: #selector(setSensitivity(_:)), keyEquivalent: "")
            menuItem.target = self  // IMPORTANT: Set target
            menuItem.representedObject = value
            if abs(Float(preferences.dragSensitivity) - value) < 0.01 {
                menuItem.state = .on
            }
            submenu.addItem(menuItem)
        }

        item.submenu = submenu
        return item
    }

    private func createAdvancedMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Advanced", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        // Add system gesture configuration option
        let gestureItem = NSMenuItem(
            title: "Configure System Gestures...",
            action: #selector(configureSystemGestures),
            keyEquivalent: ""
        )
        gestureItem.target = self
        submenu.addItem(gestureItem)

        submenu.addItem(NSMenuItem.separator())

        // Palm Rejection section
        submenu.addItem(createPalmRejectionMenu())

        submenu.addItem(NSMenuItem.separator())

        // Minimum Window Size section (separate from palm rejection as it's window-based)
        let windowSizeItem = createAdvancedMenuItem(
            title: "Ignore Small Windows",
            isOn: preferences.minimumWindowSizeFilterEnabled,
            action: #selector(toggleMinimumWindowSizeFilter)
        )
        submenu.addItem(windowSizeItem)

        // Window size threshold options (only shown when enabled)
        if preferences.minimumWindowSizeFilterEnabled {
            let sizes: [(String, Double)] = [
                ("Very Small (50px)", 50),
                ("Small (100px)", 100),
                ("Medium (200px)", 200),
                ("Large (300px)", 300),
            ]

            for (title, value) in sizes {
                let sizeItem = NSMenuItem(
                    title: "    \(title)", action: #selector(setMinimumWindowSize(_:)),
                    keyEquivalent: "")
                sizeItem.target = self
                sizeItem.representedObject = value
                if abs(preferences.minimumWindowWidth - value) < 0.01 {
                    sizeItem.state = .on
                }
                submenu.addItem(sizeItem)
            }
        }

        // Ignore Desktop option (suppress gestures when cursor is over desktop)
        let ignoreDesktopItem = createAdvancedMenuItem(
            title: "Ignore Desktop",
            isOn: preferences.ignoreDesktop,
            action: #selector(toggleIgnoreDesktop)
        )
        submenu.addItem(ignoreDesktopItem)

        submenu.addItem(NSMenuItem.separator())

        // Relift during drag - Linux-style text selection
        submenu.addItem(
            createAdvancedMenuItem(
                title: "Allow Relift During Drag",
                isOn: preferences.allowReliftDuringDrag,
                action: #selector(toggleAllowReliftDuringDrag)
            ))

        submenu.addItem(NSMenuItem.separator())

        // Telemetry section header
        let telemetryHeader = NSMenuItem(
            title: "Help Improve MiddleDrag:", action: nil, keyEquivalent: "")
        telemetryHeader.isEnabled = false
        submenu.addItem(telemetryHeader)

        // Crash reporting (only sends on crash)
        submenu.addItem(
            createAdvancedMenuItem(
                title: "Send Crash Reports",
                isOn: CrashReporter.shared.isEnabled,
                action: #selector(toggleCrashReporting)
            ))

        // Performance monitoring (sends during use)
        submenu.addItem(
            createAdvancedMenuItem(
                title: "Send Performance Data",
                isOn: CrashReporter.shared.performanceMonitoringEnabled,
                action: #selector(togglePerformanceMonitoring)
            ))

        item.submenu = submenu
        return item
    }

    private func createPalmRejectionMenu() -> NSMenuItem {
        let item = NSMenuItem(title: "Palm Rejection", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        // Exclusion Zone section
        let exclusionItem = createAdvancedMenuItem(
            title: "Exclusion Zone",
            isOn: preferences.exclusionZoneEnabled,
            action: #selector(toggleExclusionZone)
        )
        submenu.addItem(exclusionItem)

        // Exclusion zone size options (only shown when enabled)
        if preferences.exclusionZoneEnabled {
            let sizes: [(String, Double)] = [
                ("10% (Small)", 0.10),
                ("15% (Default)", 0.15),
                ("20% (Medium)", 0.20),
                ("25% (Large)", 0.25),
            ]

            for (title, value) in sizes {
                let sizeItem = NSMenuItem(
                    title: "    \(title)", action: #selector(setExclusionZoneSize(_:)),
                    keyEquivalent: "")
                sizeItem.target = self
                sizeItem.representedObject = value
                if abs(preferences.exclusionZoneSize - value) < 0.01 {
                    sizeItem.state = .on
                }
                submenu.addItem(sizeItem)
            }
        }

        submenu.addItem(NSMenuItem.separator())

        // Modifier Key section
        let modifierItem = createAdvancedMenuItem(
            title: "Require Modifier Key",
            isOn: preferences.requireModifierKey,
            action: #selector(toggleRequireModifierKey)
        )
        submenu.addItem(modifierItem)

        // Modifier key options (only shown when enabled)
        if preferences.requireModifierKey {
            for keyType in ModifierKeyType.allCases {
                let keyItem = NSMenuItem(
                    title: "    \(keyType.displayName)", action: #selector(setModifierKeyType(_:)),
                    keyEquivalent: "")
                keyItem.target = self
                keyItem.representedObject = keyType.rawValue
                if preferences.modifierKeyType == keyType {
                    keyItem.state = .on
                }
                submenu.addItem(keyItem)
            }
        }

        submenu.addItem(NSMenuItem.separator())

        // Contact Size Filter section
        let contactSizeItem = createAdvancedMenuItem(
            title: "Filter Large Contacts",
            isOn: preferences.contactSizeFilterEnabled,
            action: #selector(toggleContactSizeFilter)
        )
        submenu.addItem(contactSizeItem)

        // Contact size threshold options (only shown when enabled)
        if preferences.contactSizeFilterEnabled {
            let thresholds: [(String, Double)] = [
                ("Strict (1.0)", 1.0),
                ("Normal (1.5)", 1.5),
                ("Lenient (2.0)", 2.0),
            ]

            for (title, value) in thresholds {
                let thresholdItem = NSMenuItem(
                    title: "    \(title)", action: #selector(setContactSizeThreshold(_:)),
                    keyEquivalent: "")
                thresholdItem.target = self
                thresholdItem.representedObject = value
                if abs(preferences.maxContactSize - value) < 0.01 {
                    thresholdItem.state = .on
                }
                submenu.addItem(thresholdItem)
            }
        }

        item.submenu = submenu
        return item
    }

    private func createAdvancedMenuItem(title: String, isOn: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self  // IMPORTANT: Set target
        item.state = isOn ? .on : .off
        return item
    }

    // MARK: - Actions

    @objc func toggleEnabled() {
        multitouchManager?.toggleEnabled()
        let isEnabled = multitouchManager?.isEnabled ?? false

        if let item = statusItem.menu?.item(withTag: MenuItemTag.enabled.rawValue) {
            item.state = isEnabled ? .on : .off
        }

        updateStatusIcon(enabled: isEnabled)
        buildMenu()  // Rebuild to update status text
    }

    @objc func toggleMiddleDrag() {
        preferences.middleDragEnabled.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.middleDragEnabled = preferences.middleDragEnabled
        multitouchManager?.updateConfiguration(config)

        if let item = statusItem.menu?.item(withTag: MenuItemTag.middleDrag.rawValue) {
            item.state = preferences.middleDragEnabled ? .on : .off
        }

        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func toggleTapToClick() {
        preferences.tapToClickEnabled.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.tapToClickEnabled = preferences.tapToClickEnabled
        multitouchManager?.updateConfiguration(config)

        if let item = statusItem.menu?.item(withTag: MenuItemTag.tapToClick.rawValue) {
            item.state = preferences.tapToClickEnabled ? .on : .off
        }

        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func setSensitivity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Float else { return }

        // Update UI
        if let menu = unsafe sender.menu {
            for item in menu.items {
                item.state = item == sender ? .on : .off
            }
        }

        // Update preferences and manager
        preferences.dragSensitivity = Double(value)
        multitouchManager?.configuration.sensitivity = value

        // Notify delegate to save preferences
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func configureSystemGestures() {
        // Check if settings are already optimal
        if !SystemGestureHelper.hasConflictingSettings() {
            AlertHelper.showGestureConfigurationAlreadyOptimal()
            return
        }

        // Show prompt and apply if user confirms
        if AlertHelper.showGestureConfigurationPrompt() {
            if SystemGestureHelper.applyRecommendedSettings() {
                AlertHelper.showGestureConfigurationSuccess()
            } else {
                AlertHelper.showGestureConfigurationFailure()
            }
        }
    }

    // MARK: - Palm Rejection Actions

    @objc func toggleExclusionZone() {
        preferences.exclusionZoneEnabled.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.exclusionZoneEnabled = preferences.exclusionZoneEnabled
        config.exclusionZoneSize = Float(preferences.exclusionZoneSize)
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func setExclusionZoneSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }

        preferences.exclusionZoneSize = value

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.exclusionZoneSize = Float(value)
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func toggleRequireModifierKey() {
        preferences.requireModifierKey.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.requireModifierKey = preferences.requireModifierKey
        config.modifierKeyType = preferences.modifierKeyType
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func setModifierKeyType(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
            let keyType = ModifierKeyType(rawValue: rawValue)
        else { return }

        preferences.modifierKeyType = keyType

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.modifierKeyType = keyType
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func toggleContactSizeFilter() {
        preferences.contactSizeFilterEnabled.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.contactSizeFilterEnabled = preferences.contactSizeFilterEnabled
        config.maxContactSize = Float(preferences.maxContactSize)
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func setContactSizeThreshold(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }

        preferences.maxContactSize = value

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.maxContactSize = Float(value)
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func toggleMinimumWindowSizeFilter() {
        preferences.minimumWindowSizeFilterEnabled.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.minimumWindowSizeFilterEnabled = preferences.minimumWindowSizeFilterEnabled
        config.minimumWindowWidth = CGFloat(preferences.minimumWindowWidth)
        config.minimumWindowHeight = CGFloat(preferences.minimumWindowHeight)
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func setMinimumWindowSize(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }

        // Set both width and height to the same value (square threshold)
        preferences.minimumWindowWidth = value
        preferences.minimumWindowHeight = value

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.minimumWindowWidth = CGFloat(value)
        config.minimumWindowHeight = CGFloat(value)
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func toggleIgnoreDesktop() {
        preferences.ignoreDesktop.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.ignoreDesktop = preferences.ignoreDesktop
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func toggleAllowReliftDuringDrag() {
        preferences.allowReliftDuringDrag.toggle()

        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.allowReliftDuringDrag = preferences.allowReliftDuringDrag
        multitouchManager?.updateConfiguration(config)

        buildMenu()
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func toggleLaunchAtLogin() {
        preferences.launchAtLogin.toggle()

        if let item = statusItem.menu?.item(withTag: MenuItemTag.launchAtLogin.rawValue) {
            item.state = preferences.launchAtLogin ? .on : .off
        }

        NotificationCenter.default.post(
            name: .launchAtLoginChanged, object: preferences.launchAtLogin)
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }

    @objc func checkForUpdates() {
        UpdateManager.shared.checkForUpdates()
    }

    @objc func toggleAutoUpdate() {
        UpdateManager.shared.automaticallyChecksForUpdates.toggle()
        buildMenu()  // Rebuild to update checkmark
    }

    @objc func toggleCrashReporting() {
        CrashReporter.shared.isEnabled.toggle()
        buildMenu()  // Rebuild to update checkmark
    }

    @objc func togglePerformanceMonitoring() {
        CrashReporter.shared.performanceMonitoringEnabled.toggle()
        buildMenu()  // Rebuild to update checkmark
    }

    @objc private func showAbout() {
        AlertHelper.showAbout()
    }

    @objc private func showQuickSetup() {
        AlertHelper.showQuickSetup()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let preferencesChanged = Notification.Name("MiddleDragPreferencesChanged")
    static let launchAtLoginChanged = Notification.Name("MiddleDragLaunchAtLoginChanged")
}

