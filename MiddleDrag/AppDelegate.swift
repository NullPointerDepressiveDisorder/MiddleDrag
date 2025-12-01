import Cocoa

/// Main application delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private let multitouchManager = MultitouchManager.shared
    private var menuBarController: MenuBarController?
    private var preferences: UserPreferences!
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)
        
        // Defer initialization to ensure app is fully ready
        DispatchQueue.main.async { [weak self] in
            self?.initializeApp()
        }
    }
    
    private func initializeApp() {
        // Check Accessibility permissions (required for CGEvent posting)
        if !AXIsProcessTrusted() {
            // Prompt user to grant Accessibility permission
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            // Show additional guidance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "MiddleDrag needs Accessibility permission to simulate mouse clicks.\n\nPlease enable MiddleDrag in:\nSystem Settings → Privacy & Security → Accessibility\n\nThen restart the app."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Quit")
                alert.runModal()
                NSApplication.shared.terminate(nil)
            }
            return
        }
        
        // Load preferences
        preferences = PreferencesManager.shared.loadPreferences()
        
        // Configure and start multitouch manager
        multitouchManager.updateConfiguration(preferences.gestureConfig)
        multitouchManager.start()
        
        // Set up menu bar UI after starting (so isEnabled is true)
        menuBarController = MenuBarController(
            multitouchManager: multitouchManager,
            preferences: preferences
        )
        
        // Set up notification observers
        setupNotifications()
        
        // Configure launch at login
        if preferences.launchAtLogin {
            LaunchAtLoginManager.shared.setLaunchAtLogin(true)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        multitouchManager.stop()
        
        if preferences != nil {
            PreferencesManager.shared.savePreferences(preferences)
        }
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    // MARK: - Setup
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged(_:)),
            name: .preferencesChanged,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(launchAtLoginChanged(_:)),
            name: .launchAtLoginChanged,
            object: nil
        )
    }
    
    // MARK: - Notification Handlers
    
    @objc private func preferencesChanged(_ notification: Notification) {
        if let newPreferences = notification.object as? UserPreferences {
            preferences = newPreferences
            PreferencesManager.shared.savePreferences(preferences)
            multitouchManager.updateConfiguration(preferences.gestureConfig)
        }
    }
    
    @objc private func launchAtLoginChanged(_ notification: Notification) {
        if let enabled = notification.object as? Bool {
            LaunchAtLoginManager.shared.setLaunchAtLogin(enabled)
        }
    }
}
