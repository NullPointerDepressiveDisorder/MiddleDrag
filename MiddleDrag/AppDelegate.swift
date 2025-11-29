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
        // Check Input Monitoring permissions
        if !checkInputMonitoringPermissions() {
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
    
    private func checkInputMonitoringPermissions() -> Bool {
        // Test if we can create an event tap (requires Input Monitoring permission)
        let testTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.mouseMoved.rawValue),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        
        if testTap != nil {
            // Permission granted, clean up test tap
            CFMachPortInvalidate(testTap!)
            return true
        }
        
        // Show custom alert for Input Monitoring permission
        let result = AlertHelper.showInputMonitoringPermissionRequired()
        
        if result {
            // User chose to open settings - quit so they can grant permission
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        } else {
            NSApplication.shared.terminate(nil)
        }
        
        return false
    }
    
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
