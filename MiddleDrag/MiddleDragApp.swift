import SwiftUI
import Cocoa

@main
struct MiddleDragApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // We only need a menu bar app, no window
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var multitouchManager: MultitouchManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon since this is a menu bar app
        NSApp.setActivationPolicy(.accessory)
        
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "hand.raised.fingers.spread", 
                                  accessibilityDescription: "MiddleDrag")
            button.image?.isTemplate = true
        }
        
        setupMenu()
        
        // Request accessibility permissions
        requestAccessibilityPermissions()
        
        // Initialize multitouch monitoring
        multitouchManager = MultitouchManager()
        multitouchManager?.start()
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        let enableItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enableItem.state = multitouchManager?.isEnabled ?? true ? .on : .off
        enableItem.tag = 1
        menu.addItem(enableItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Sensitivity submenu
        let sensitivityItem = NSMenuItem(title: "Drag Sensitivity", action: nil, keyEquivalent: "")
        let sensitivityMenu = NSMenu()
        
        let lowSensitivity = NSMenuItem(title: "Low (Precision)", action: #selector(setSensitivity(_:)), keyEquivalent: "")
        lowSensitivity.tag = 1
        sensitivityMenu.addItem(lowSensitivity)
        
        let mediumSensitivity = NSMenuItem(title: "Medium", action: #selector(setSensitivity(_:)), keyEquivalent: "")
        mediumSensitivity.tag = 2
        mediumSensitivity.state = .on // Default
        sensitivityMenu.addItem(mediumSensitivity)
        
        let highSensitivity = NSMenuItem(title: "High (Fast)", action: #selector(setSensitivity(_:)), keyEquivalent: "")
        highSensitivity.tag = 3
        sensitivityMenu.addItem(highSensitivity)
        
        sensitivityItem.submenu = sensitivityMenu
        menu.addItem(sensitivityItem)
        
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "About MiddleDrag", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc func toggleEnabled() {
        multitouchManager?.toggleEnabled()
        
        if let menu = statusItem.menu,
           let item = menu.item(withTag: 1) {
            item.state = (multitouchManager?.isEnabled ?? true) ? .on : .off
        }
        
        // Update icon to show enabled/disabled state
        updateStatusIcon()
    }
    
    @objc func setSensitivity(_ sender: NSMenuItem) {
        // Clear all checkmarks
        if let menu = sender.menu {
            for item in menu.items {
                item.state = .off
            }
        }
        sender.state = .on
        
        let sensitivity: Float = [1: 0.5, 2: 1.0, 3: 2.0][sender.tag] ?? 1.0
        multitouchManager?.sensitivity = sensitivity
    }
    
    @objc func toggleLaunchAtLogin() {
        // This would implement launch at login functionality
        // For now, just toggle the checkmark
        if let menu = statusItem.menu,
           let item = menu.item(withTitle: "Open at Login") {
            item.state = item.state == .on ? .off : .on
        }
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "MiddleDrag"
        alert.informativeText = """
        Three-finger drag for middle mouse button emulation.
        Perfect for CAD software navigation on Mac trackpads.
        
        Version 1.0.0
        
        Instructions:
        1. Disable conflicting three-finger gestures in System Settings
        2. Use three fingers to drag (middle mouse drag)
        3. Three-finger tap for middle click
        
        Created for engineers, designers, and makers.
        Open source: github.com/yourusername/MiddleDrag
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "System Settings")
        
        if alert.runModal() == .alertSecondButtonReturn {
            // Open trackpad settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.trackpad") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    func requestAccessibilityPermissions() {
        if !AXIsProcessTrusted() {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
            MiddleDrag needs accessibility permissions to simulate mouse events.
            
            Click OK to open System Settings, then:
            1. Go to Privacy & Security > Accessibility
            2. Enable MiddleDrag
            3. Restart the app
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            
            // Trigger the system prompt
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            // Quit after a delay to let user grant permissions
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    func updateStatusIcon() {
        if let button = statusItem.button {
            let iconName = (multitouchManager?.isEnabled ?? true) 
                ? "hand.raised.fingers.spread" 
                : "hand.raised.slash"
            button.image = NSImage(systemSymbolName: iconName, 
                                  accessibilityDescription: "MiddleDrag")
            button.image?.isTemplate = true
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        multitouchManager?.stop()
    }
}
