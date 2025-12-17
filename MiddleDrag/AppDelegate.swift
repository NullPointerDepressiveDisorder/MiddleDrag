import Cocoa

/// Main application delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private let multitouchManager = MultitouchManager.shared
    private var menuBarController: MenuBarController?
    private var preferences: UserPreferences!
    private var accessibilityAlertWorkItem: DispatchWorkItem?
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize crash reporting only if user has opted in (offline by default)
        CrashReporter.shared.initializeIfEnabled()
        
        Log.info("MiddleDrag starting...", category: .app)
        
        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)
        
        // Close any windows that SwiftUI might have created
        closeAllWindows()
        
        // Defer initialization to ensure app is fully ready
        DispatchQueue.main.async { [weak self] in
            self?.initializeApp()
        }
    }
    
    private func initializeApp() {
        // Close any windows again (in case they appeared during init)
        closeAllWindows()
        
        // Load preferences
        preferences = PreferencesManager.shared.loadPreferences()
        Log.info("Preferences loaded", category: .app)
        
        // Check Accessibility permission BEFORE starting multitouch manager
        // This prevents the event tap from being set up without permissions, which causes hangs
        let hasAccessibilityPermission = AXIsProcessTrusted()
        
        // Configure multitouch manager (always configure, regardless of permission)
        multitouchManager.updateConfiguration(preferences.gestureConfig)
        
        if hasAccessibilityPermission {
            Log.info("Accessibility permission granted", category: .app)
            
            // Start multitouch manager (only if we have permission)
            multitouchManager.start()
            Log.info("Multitouch manager started", category: .app)
        } else {
            Log.warning("Accessibility permission not granted", category: .app)
        }
        
        // Set up menu bar UI (always initialize, even without permission)
        // This way the menu bar icon appears and users can interact with the app
        menuBarController = MenuBarController(
            multitouchManager: multitouchManager,
            preferences: preferences
        )
        Log.info("Menu bar controller initialized", category: .app)
        
        // Set up notification observers
        setupNotifications()
        
        // Configure launch at login
        if preferences.launchAtLogin {
            LaunchAtLoginManager.shared.setLaunchAtLogin(true)
        }
        
        // Final cleanup of any stray windows
        closeAllWindows()
        
        Log.info("MiddleDrag initialization complete", category: .app)
        
        // Show alert if permission is missing
        if !hasAccessibilityPermission {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self, 
                    self.accessibilityAlertWorkItem?.isCancelled == false
                else { return }
                
                self.showAccessibilityAlert()
            }

            self.accessibilityAlertWorkItem = workItem

            DispatchQueue.main.async(execute: workItem)
        }
    }
    
    private func showAccessibilityAlert() {
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
    }
    
    /// Close all windows - menu bar apps shouldn't have any visible windows
    private func closeAllWindows() {
        for window in NSApp.windows {
            // Don't close status bar or menu-related windows
            let className = window.className
            if !className.contains("NSStatusBar") && !className.contains("NSMenu") {
                window.close()
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Log.info("MiddleDrag terminating", category: .app)

        accessibilityAlertWorkItem?.cancel()
        accessibilityAlertWorkItem = nil
        
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
            Log.info("Preferences updated", category: .app)
        }
    }
    
    @objc private func launchAtLoginChanged(_ notification: Notification) {
        if let enabled = notification.object as? Bool {
            LaunchAtLoginManager.shared.setLaunchAtLogin(enabled)
        }
    }
}
