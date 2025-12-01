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
        // Load preferences
        preferences = PreferencesManager.shared.loadPreferences()
        
        // Configure and start multitouch manager
        multitouchManager.updateConfiguration(preferences.gestureConfig)
        multitouchManager.start()
        
        // Set up menu bar UI
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
        
        // Check Accessibility permission AFTER UI is set up
        // This way the menu bar icon appears even if permission is missing
        if !AXIsProcessTrusted() {
            // Show our custom alert only - don't use the system prompt
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = """
            MiddleDrag needs Accessibility permission to simulate mouse clicks.
            
            To grant permission:
            1. Click "Open System Settings" below
            2. Click the "+" button
            3. Navigate to this app and add it
            4. Make sure the checkbox is enabled
            5. Restart MiddleDrag
            
            Note: You may need to remove and re-add the app if you downloaded a new version.
            """
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Continue Anyway")
            
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            // Don't quit - let user continue and see the menu bar icon
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
