import SwiftUI
import Cocoa
import ServiceManagement

@main
struct MiddleDragApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Menu bar only app
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var multitouchManager: MultitouchManager?
    private var preferencesWindow: NSWindow?
    
    // User preferences
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("dragSensitivity") private var dragSensitivity = 1.0
    @AppStorage("tapThreshold") private var tapThreshold = 0.15
    @AppStorage("smoothingFactor") private var smoothingFactor = 0.3
    @AppStorage("requiresExactlyThreeFingers") private var requiresExactlyThreeFingers = true
    @AppStorage("blockSystemGestures") private var blockSystemGestures = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon since this is a menu bar app
        NSApp.setActivationPolicy(.accessory)
        
        // Create menu bar item
        setupStatusItem()
        
        // Check and request permissions
        if !checkAccessibilityPermissions() {
            return  // App will quit after showing permission dialog
        }
        
        // Initialize and configure multitouch manager
        initializeMultitouchManager()
        
        // Set up launch at login if enabled
        if launchAtLogin {
            configureLaunchAtLogin(enabled: true)
        }
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            updateStatusIcon(enabled: true)
        }
        
        setupMenu()
    }
    
    private func updateStatusIcon(enabled: Bool) {
        guard let button = statusItem.button else { return }
        
        let iconName = enabled ? "hand.raised.fingers.spread" : "hand.raised.slash"
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "MiddleDrag")
        button.image?.isTemplate = true
        
        // Add a subtle animation when toggling
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            button.animator().alphaValue = 0.7
        } completionHandler: {
            button.animator().alphaValue = 1.0
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Status indicator
        let statusItem = NSMenuItem(title: "MiddleDrag Active", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Enable/Disable toggle
        let enableItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
        enableItem.state = multitouchManager?.isEnabled ?? true ? .on : .off
        enableItem.tag = 1
        menu.addItem(enableItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Sensitivity submenu
        menu.addItem(createSensitivityMenu())
        
        // Advanced settings submenu
        menu.addItem(createAdvancedMenu())
        
        menu.addItem(NSMenuItem.separator())
        
        // Preferences and about
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About MiddleDrag", action: #selector(showAbout), keyEquivalent: ""))
        
        // Launch at login
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.state = launchAtLogin ? .on : .off
        launchItem.tag = 2
        menu.addItem(launchItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Help and quit
        menu.addItem(NSMenuItem(title: "Quick Setup", action: #selector(showQuickSetup), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    private func createSensitivityMenu() -> NSMenuItem {
        let sensitivityItem = NSMenuItem(title: "Drag Sensitivity", action: nil, keyEquivalent: "")
        let sensitivityMenu = NSMenu()
        
        let sensitivities: [(String, Float, Int)] = [
            ("Slow (0.5x)", 0.5, 1),
            ("Precision (0.75x)", 0.75, 2),
            ("Normal (1x)", 1.0, 3),
            ("Fast (1.5x)", 1.5, 4),
            ("Very Fast (2x)", 2.0, 5)
        ]
        
        for (title, value, tag) in sensitivities {
            let item = NSMenuItem(title: title, action: #selector(setSensitivity(_:)), keyEquivalent: "")
            item.tag = tag
            item.representedObject = value
            if abs(Float(dragSensitivity) - value) < 0.01 {
                item.state = .on
            }
            sensitivityMenu.addItem(item)
        }
        
        sensitivityItem.submenu = sensitivityMenu
        return sensitivityItem
    }
    
    private func createAdvancedMenu() -> NSMenuItem {
        let advancedItem = NSMenuItem(title: "Advanced", action: nil, keyEquivalent: "")
        let advancedMenu = NSMenu()
        
        // Tap timing
        let tapItem = NSMenuItem(title: "Tap Speed: \(String(format: "%.0fms", tapThreshold * 1000))", action: nil, keyEquivalent: "")
        tapItem.isEnabled = false
        advancedMenu.addItem(tapItem)
        
        let tapSpeeds: [(String, Double)] = [
            ("Faster (100ms)", 0.10),
            ("Normal (150ms)", 0.15),
            ("Slower (200ms)", 0.20)
        ]
        
        for (title, value) in tapSpeeds {
            let item = NSMenuItem(title: "  " + title, action: #selector(setTapSpeed(_:)), keyEquivalent: "")
            item.representedObject = value
            if abs(tapThreshold - value) < 0.01 {
                item.state = .on
            }
            advancedMenu.addItem(item)
        }
        
        advancedMenu.addItem(NSMenuItem.separator())
        
        // Smoothing
        let smoothItem = NSMenuItem(title: "Smoothing: \(String(format: "%.0f%%", smoothingFactor * 100))", action: nil, keyEquivalent: "")
        smoothItem.isEnabled = false
        advancedMenu.addItem(smoothItem)
        
        let smoothLevels: [(String, Float)] = [
            ("Low (20%)", 0.2),
            ("Medium (30%)", 0.3),
            ("High (50%)", 0.5)
        ]
        
        for (title, value) in smoothLevels {
            let item = NSMenuItem(title: "  " + title, action: #selector(setSmoothing(_:)), keyEquivalent: "")
            item.representedObject = value
            if abs(Float(smoothingFactor) - value) < 0.01 {
                item.state = .on
            }
            advancedMenu.addItem(item)
        }
        
        advancedMenu.addItem(NSMenuItem.separator())
        
        // Finger requirement
        let fingerItem = NSMenuItem(title: "Require Exactly 3 Fingers", action: #selector(toggleFingerRequirement), keyEquivalent: "")
        fingerItem.state = requiresExactlyThreeFingers ? .on : .off
        advancedMenu.addItem(fingerItem)
        
        // System gesture blocking (experimental)
        let blockItem = NSMenuItem(title: "Block System Gestures (Experimental)", action: #selector(toggleSystemGestureBlocking), keyEquivalent: "")
        blockItem.state = blockSystemGestures ? .on : .off
        advancedMenu.addItem(blockItem)
        
        advancedItem.submenu = advancedMenu
        return advancedItem
    }
    
    // MARK: - Multitouch Manager
    
    private func initializeMultitouchManager() {
        multitouchManager = MultitouchManager()
        
        // Apply saved preferences
        multitouchManager?.sensitivity = Float(dragSensitivity)
        multitouchManager?.tapThreshold = tapThreshold
        multitouchManager?.smoothingFactor = Float(smoothingFactor)
        multitouchManager?.requiresThreeFingerDrag = requiresExactlyThreeFingers
        multitouchManager?.blockSystemGestures = blockSystemGestures
        
        // Start monitoring
        multitouchManager?.start()
    }
    
    // MARK: - Menu Actions
    
    @objc func toggleEnabled() {
        multitouchManager?.toggleEnabled()
        
        let isEnabled = multitouchManager?.isEnabled ?? false
        
        if let menu = statusItem.menu,
           let item = menu.item(withTag: 1) {
            item.state = isEnabled ? .on : .off
        }
        
        updateStatusIcon(enabled: isEnabled)
    }
    
    @objc func setSensitivity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Float else { return }
        
        // Update UI
        if let menu = sender.menu {
            for item in menu.items {
                item.state = item == sender ? .on : .off
            }
        }
        
        // Update manager
        multitouchManager?.setSensitivity(value)
        dragSensitivity = Double(value)
    }
    
    @objc func setTapSpeed(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        
        // Update UI
        if let menu = sender.menu {
            for item in menu.items where item.representedObject != nil {
                item.state = item == sender ? .on : .off
            }
            // Update header
            if let header = menu.items.first {
                header.title = "Tap Speed: \(String(format: "%.0fms", value * 1000))"
            }
        }
        
        // Update manager
        multitouchManager?.setTapThreshold(value)
        tapThreshold = value
    }
    
    @objc func setSmoothing(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Float else { return }
        
        // Update UI
        if let menu = sender.menu {
            for item in menu.items where item.representedObject != nil {
                item.state = item == sender ? .on : .off
            }
            // Find and update header
            for item in menu.items where item.title.starts(with: "Smoothing:") {
                item.title = "Smoothing: \(String(format: "%.0f%%", value * 100))"
                break
            }
        }
        
        // Update manager
        multitouchManager?.setSmoothingFactor(value)
        smoothingFactor = Double(value)
    }
    
    @objc func toggleFingerRequirement() {
        requiresExactlyThreeFingers.toggle()
        multitouchManager?.requiresThreeFingerDrag = requiresExactlyThreeFingers
        
        // Update menu
        if let menu = statusItem.menu {
            for item in menu.items {
                if let submenu = item.submenu {
                    for subItem in submenu.items where subItem.title == "Require Exactly 3 Fingers" {
                        subItem.state = requiresExactlyThreeFingers ? .on : .off
                    }
                }
            }
        }
    }
    
    @objc func toggleSystemGestureBlocking() {
        blockSystemGestures.toggle()
        multitouchManager?.blockSystemGestures = blockSystemGestures
        
        // Restart the manager to apply changes
        multitouchManager?.stop()
        multitouchManager?.start()
        
        // Update menu
        if let menu = statusItem.menu {
            for item in menu.items {
                if let submenu = item.submenu {
                    for subItem in submenu.items where subItem.title.starts(with: "Block System Gestures") {
                        subItem.state = blockSystemGestures ? .on : .off
                    }
                }
            }
        }
        
        if blockSystemGestures {
            showSystemGestureWarning()
        }
    }
    
    @objc func toggleLaunchAtLogin() {
        launchAtLogin.toggle()
        configureLaunchAtLogin(enabled: launchAtLogin)
        
        if let menu = statusItem.menu,
           let item = menu.item(withTag: 2) {
            item.state = launchAtLogin ? .on : .off
        }
    }
    
    @objc func showPreferences() {
        // Create a simple preferences window
        if preferencesWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "MiddleDrag Preferences"
            window.center()
            preferencesWindow = window
        }
        
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "MiddleDrag"
        alert.icon = NSImage(systemSymbolName: "hand.raised.fingers.spread", accessibilityDescription: nil)
        alert.informativeText = """
        Three-finger drag for middle mouse button emulation.
        Works alongside your system gestures!
        
        Version 2.0.0
        
        ✨ Features:
        • Works WITH system gestures enabled
        • Three-finger drag → Middle mouse drag
        • Three-finger tap → Middle mouse click
        • Smart gesture detection
        • Minimal CPU usage
        
        💡 Tips:
        • No need to disable system gestures
        • Adjust sensitivity for your workflow
        • Enable gesture blocking only if needed
        
        Created for engineers, designers, and makers.
        Open source: github.com/kmohindroo/MiddleDrag
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open GitHub")
        
        let response = alert.runModal()
        
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/kmohindroo/MiddleDrag") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc func showQuickSetup() {
        let setupAlert = NSAlert()
        setupAlert.messageText = "MiddleDrag Quick Setup"
        setupAlert.informativeText = """
        ✅ MiddleDrag works WITH your existing trackpad gestures!
        
        No configuration needed - just use:
        • Three fingers drag = Middle mouse drag
        • Three-finger tap = Middle click
        
        Optional optimizations:
        • If you experience conflicts, you can disable system three-finger gestures in Trackpad settings
        • Enable "Block System Gestures" in Advanced menu for exclusive control
        
        That's it! MiddleDrag uses Apple's multitouch framework to detect gestures before the system processes them.
        """
        setupAlert.alertStyle = .informational
        setupAlert.addButton(withTitle: "Got it!")
        setupAlert.addButton(withTitle: "Open Trackpad Settings")
        
        if setupAlert.runModal() == .alertSecondButtonReturn {
            openTrackpadSettings()
        }
    }
    
    private func showSystemGestureWarning() {
        let alert = NSAlert()
        alert.messageText = "Experimental Feature"
        alert.informativeText = """
        System gesture blocking is experimental and may:
        • Disable Mission Control gestures while dragging
        • Cause unexpected behavior with some apps
        
        This is usually not needed - MiddleDrag works alongside system gestures.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    // MARK: - Helper Functions
    
    private func checkAccessibilityPermissions() -> Bool {
        if !AXIsProcessTrusted() {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
            MiddleDrag needs accessibility permissions to:
            • Detect three-finger trackpad gestures
            • Simulate middle mouse button events
            
            After granting permission, please restart MiddleDrag.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")
            
            if alert.runModal() == .alertFirstButtonReturn {
                // Open accessibility settings
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
                
                // Also trigger the system prompt
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                AXIsProcessTrustedWithOptions(options as CFDictionary)
            }
            
            // Quit after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSApplication.shared.terminate(nil)
            }
            
            return false
        }
        
        return true
    }
    
    private func openTrackpadSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.trackpad") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func configureLaunchAtLogin(enabled: Bool) {
        // For macOS 13+, use the new Service Management API
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to configure launch at login: \(error)")
            }
        } else {
            // For older macOS versions, use LSSharedFileList
            // This would require additional implementation
        }
    }
    
    // MARK: - App Lifecycle
    
    func applicationWillTerminate(_ notification: Notification) {
        multitouchManager?.stop()
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
