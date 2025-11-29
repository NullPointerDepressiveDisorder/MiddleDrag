import Cocoa

/// Main application delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // Core components
    private let multitouchManager = MultitouchManager.shared
    private var menuBarController: MenuBarController!
    private var preferences: UserPreferences!
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon (menu bar app)
        NSApp.setActivationPolicy(.accessory)
        
        // Check accessibility permissions
        if !checkAccessibilityPermissions() {
            // App will quit after showing dialog
            return
        }
        
        // Load preferences
        preferences = PreferencesManager.shared.loadPreferences()
        
        // Configure multitouch manager
        configureMultitouchManager()
        
        // Set up menu bar UI
        menuBarController = MenuBarController(
            multitouchManager: multitouchManager,
            preferences: preferences
        )
        
        // Set up notifications
        setupNotifications()
        
        // Start monitoring
        multitouchManager.start()
        
        // Configure launch at login if needed
        if preferences.launchAtLogin {
            LaunchAtLoginManager.shared.setLaunchAtLogin(true)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean shutdown
        multitouchManager.stop()
        
        // Save preferences
        PreferencesManager.shared.savePreferences(preferences)
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    // MARK: - Setup
    
    private func checkAccessibilityPermissions() -> Bool {
        if !AXIsProcessTrusted() {
            if AlertHelper.showAccessibilityPermissionRequired() {
                // User chose to open settings
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    NSApplication.shared.terminate(nil)
                }
            } else {
                // User chose to quit
                NSApplication.shared.terminate(nil)
            }
            return false
        }
        return true
    }
    
    private func configureMultitouchManager() {
        // Apply configuration from preferences
        multitouchManager.updateConfiguration(preferences.gestureConfig)
    }
    
    private func setupNotifications() {
        // Listen for preference changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged(_:)),
            name: .preferencesChanged,
            object: nil
        )
        
        // Listen for launch at login changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(launchAtLoginChanged(_:)),
            name: .launchAtLoginChanged,
            object: nil
        )
    }
    
    // MARK: - Notifications
    
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
