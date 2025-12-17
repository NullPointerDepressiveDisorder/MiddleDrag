import Cocoa

/// Manages the menu bar UI and user interactions
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
        
        if let button = statusItem.button {
            updateStatusIcon(enabled: multitouchManager?.isEnabled ?? false)
        }
        
        buildMenu()
    }
    
    func updateStatusIcon(enabled: Bool) {
        guard let button = statusItem.button else { return }
        
        let iconName = enabled ? "hand.raised.fingers.spread" : "hand.raised.slash"
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "MiddleDrag")
        button.image?.isTemplate = true
        
        // Animate the change
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            button.animator().alphaValue = 0.7
        } completionHandler: {
            button.animator().alphaValue = 1.0
        }
    }
    
    // MARK: - Menu Building
    
    func buildMenu() {
        let menu = NSMenu()
        
        // Status
        menu.addItem(createStatusItem())
        menu.addItem(NSMenuItem.separator())
        
        // Enable/Disable
        menu.addItem(createEnabledItem())
        menu.addItem(createMiddleDragItem())
        menu.addItem(NSMenuItem.separator())
        
        // Settings
        menu.addItem(createSensitivityMenu())
        menu.addItem(createAdvancedMenu())
        menu.addItem(NSMenuItem.separator())
        
        // App items
        menu.addItem(createMenuItem(title: "About MiddleDrag", action: #selector(showAbout)))
        menu.addItem(createLaunchAtLoginItem())
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
        let item = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
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
    
    private func createLaunchAtLoginItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        item.target = self  // IMPORTANT: Set target
        item.state = preferences.launchAtLogin ? .on : .off
        item.tag = MenuItemTag.launchAtLogin.rawValue
        return item
    }
    
    private func createMenuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
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
            ("Very Fast (2x)", 2.0)
        ]
        
        for (title, value) in sensitivities {
            let menuItem = NSMenuItem(title: title, action: #selector(setSensitivity(_:)), keyEquivalent: "")
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
        
        // Add advanced options
        submenu.addItem(createAdvancedMenuItem(
            title: "Block System Gestures",
            isOn: preferences.blockSystemGestures,
            action: #selector(toggleSystemGestureBlocking)
        ))
        
        submenu.addItem(NSMenuItem.separator())
        
        // Telemetry section header
        let telemetryHeader = NSMenuItem(title: "Help Improve MiddleDrag:", action: nil, keyEquivalent: "")
        telemetryHeader.isEnabled = false
        submenu.addItem(telemetryHeader)
        
        // Crash reporting (only sends on crash)
        submenu.addItem(createAdvancedMenuItem(
            title: "Send Crash Reports",
            isOn: CrashReporter.shared.isEnabled,
            action: #selector(toggleCrashReporting)
        ))
        
        // Performance monitoring (sends during use)
        submenu.addItem(createAdvancedMenuItem(
            title: "Send Performance Data",
            isOn: CrashReporter.shared.performanceMonitoringEnabled,
            action: #selector(togglePerformanceMonitoring)
        ))
        
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
    
    @objc private func toggleEnabled() {
        multitouchManager?.toggleEnabled()
        let isEnabled = multitouchManager?.isEnabled ?? false
        
        if let item = statusItem.menu?.item(withTag: MenuItemTag.enabled.rawValue) {
            item.state = isEnabled ? .on : .off
        }
        
        updateStatusIcon(enabled: isEnabled)
        buildMenu()  // Rebuild to update status text
    }
    
    @objc private func toggleMiddleDrag() {
        preferences.middleDragEnabled.toggle()
        
        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.middleDragEnabled = preferences.middleDragEnabled
        multitouchManager?.updateConfiguration(config)
        
        if let item = statusItem.menu?.item(withTag: MenuItemTag.middleDrag.rawValue) {
            item.state = preferences.middleDragEnabled ? .on : .off
        }
        
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }
    
    @objc private func setSensitivity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Float else { return }
        
        // Update UI
        if let menu = sender.menu {
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
    
    @objc private func toggleSystemGestureBlocking() {
        preferences.blockSystemGestures.toggle()
        
        var config = multitouchManager?.configuration ?? GestureConfiguration()
        config.blockSystemGestures = preferences.blockSystemGestures
        multitouchManager?.updateConfiguration(config)
        
        buildMenu()  // Rebuild to update checkmark
        
        if preferences.blockSystemGestures {
            showSystemGestureWarning()
        }
        
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }
    
    @objc private func toggleLaunchAtLogin() {
        preferences.launchAtLogin.toggle()
        
        if let item = statusItem.menu?.item(withTag: MenuItemTag.launchAtLogin.rawValue) {
            item.state = preferences.launchAtLogin ? .on : .off
        }
        
        NotificationCenter.default.post(name: .launchAtLoginChanged, object: preferences.launchAtLogin)
        NotificationCenter.default.post(name: .preferencesChanged, object: preferences)
    }
    
    @objc private func toggleCrashReporting() {
        CrashReporter.shared.isEnabled.toggle()
        buildMenu()  // Rebuild to update checkmark
    }
    
    @objc private func togglePerformanceMonitoring() {
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
    
    private func showSystemGestureWarning() {
        AlertHelper.showSystemGestureWarning()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let preferencesChanged = Notification.Name("MiddleDragPreferencesChanged")
    static let launchAtLoginChanged = Notification.Name("MiddleDragLaunchAtLoginChanged")
}
