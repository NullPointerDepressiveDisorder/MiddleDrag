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
        // Debug logging to file for release debugging
        let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("middledrag_debug.log")
        func log(_ message: String) {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
            print(message)
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logPath.path) {
                    if let handle = try? FileHandle(forWritingTo: logPath) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: logPath)
                }
            }
        }
        
        log("MiddleDrag starting...")
        log("Bundle path: \(Bundle.main.bundlePath)")
        
        // Load preferences
        preferences = PreferencesManager.shared.loadPreferences()
        log("Preferences loaded")
        
        // Configure and start multitouch manager
        multitouchManager.updateConfiguration(preferences.gestureConfig)
        log("About to start multitouch manager")
        multitouchManager.start()
        log("Multitouch manager started, isEnabled: \(multitouchManager.isEnabled)")
        
        // Check if we actually started successfully
        if !multitouchManager.isEnabled {
            log("ERROR: Multitouch manager failed to start")
            // Show permission alert
            let result = AlertHelper.showInputMonitoringPermissionRequired()
            if result {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApplication.shared.terminate(nil)
                }
            } else {
                NSApplication.shared.terminate(nil)
            }
            return
        }
        
        log("Setting up menu bar")
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
        log("Initialization complete")
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
