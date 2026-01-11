import Cocoa

/// Main application delegate
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    private let multitouchManager = MultitouchManager.shared
    private var menuBarController: MenuBarController?
    private var preferences: UserPreferences!

    private var accessibilityMonitor: AccessibilityMonitor?

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

        // Configure multitouch manager (always configure, regardless of permission)
        multitouchManager.updateConfiguration(preferences.gestureConfig)

        // Check Accessibility permission
        // First check WITHOUT prompting to avoid showing dialog on every relaunch
        var hasAccessibilityPermission = AXIsProcessTrusted()
        
        // Only show the system prompt if we don't already have permission
        if !hasAccessibilityPermission {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
        }

        if hasAccessibilityPermission {
            Log.info("Accessibility permission granted", category: .app)

            // Start multitouch manager (only if we have permission)
            multitouchManager.start()
            if multitouchManager.isMonitoring {
                Log.info("Multitouch manager started", category: .app)
            } else {
                Log.warning(
                    "Multitouch manager inactive: no compatible multitouch hardware detected.",
                    category: .device)
            }
        } else {
            Log.warning("Accessibility permission not granted", category: .app)
        }

        // Initialize monitor for continuous checking (granted <-> revoked)
        // Pass the state we observed so the monitor can detect if it changes immediately (race condition handling)
        accessibilityMonitor = AccessibilityMonitor(initialState: hasAccessibilityPermission)

        accessibilityMonitor?.onRevocation = { [weak self] in
            Log.warning("Permission revoked - stopping multitouch manager", category: .app)
            self?.multitouchManager.stop()
        }

        accessibilityMonitor?.onGrant = { [weak self] in
            // Using re-launch strategy for clean state
            self?.accessibilityMonitor?.triggerRelaunch()
        }

        accessibilityMonitor?.startMonitoring()

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

        // Check for gesture conflicts and show prompt on first launch if needed
        checkAndPromptForGestureConfiguration()

        // Final cleanup of any stray windows
        closeAllWindows()

        Log.info("MiddleDrag initialization complete", category: .app)
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

        accessibilityMonitor?.stopMonitoring()
        accessibilityMonitor = nil

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

    // MARK: - Gesture Configuration

    /// Check for gesture conflicts and prompt user if needed (only on first launch)
    private func checkAndPromptForGestureConfiguration() {
        // Only show on first launch if we haven't shown it before
        let hasShownPrompt = PreferencesManager.shared.hasShownGestureConfigurationPrompt
        guard !hasShownPrompt else { return }

        // Only show if there are actual conflicts
        guard SystemGestureHelper.hasConflictingSettings() else { return }

        // Delay slightly to ensure UI is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showGestureConfigurationPromptOnFirstLaunch()
        }
    }

    /// Show gesture configuration prompt on first launch
    private func showGestureConfigurationPromptOnFirstLaunch() {
        // Mark as shown regardless of user action to avoid showing again
        PreferencesManager.shared.markGestureConfigurationPromptShown()

        // Show prompt with first launch messaging
        if AlertHelper.showGestureConfigurationPrompt(isFirstLaunch: true) {
            // User chose to apply changes
            if SystemGestureHelper.applyRecommendedSettings() {
                AlertHelper.showGestureConfigurationSuccess()
            } else {
                AlertHelper.showGestureConfigurationFailure()
            }
        }
        // If user dismissed, we've already marked it as shown so it won't appear again
    }
}
