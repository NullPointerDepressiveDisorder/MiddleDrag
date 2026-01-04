import AppKit
import Foundation

/// Protocol for checking accessibility permissions (for testing)
protocol AccessibilityPermissionChecking {
    var isTrusted: Bool { get }
}

/// Default implementation wrapping system API
class SystemAccessibilityPermissionChecker: AccessibilityPermissionChecking {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }
}

/// Protocol for app control (relaunching/termination) (for testing)
protocol AppLifecycleControlling {
    func relaunch()
    func terminate()
}

/// Default implementation using NSWorkspace and NSApp
class SystemAppLifecycleController: AppLifecycleControlling {
    func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            if let error = error {
                Log.error("Failed to restart app: \(error.localizedDescription)", category: .app)
            } else {
                // Terminate only after successful launch request
                DispatchQueue.main.async {
                    self?.terminate()
                }
            }
        }
    }

    func terminate() {
        NSApp.terminate(nil)
    }
}

/// Manages accessibility permission polling and app handling
class AccessibilityMonitor {

    // MARK: - Properties

    private var timer: Timer?
    private let permissionChecker: AccessibilityPermissionChecking
    private let appController: AppLifecycleControlling
    private let notificationCenter: NotificationCenter

    // MARK: - Initialization

    init(
        permissionChecker: AccessibilityPermissionChecking = SystemAccessibilityPermissionChecker(),
        appController: AppLifecycleControlling = SystemAppLifecycleController(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.permissionChecker = permissionChecker
        self.appController = appController
        self.notificationCenter = notificationCenter
    }

    deinit {
        stopPolling()
    }

    // MARK: - Public API

    /// Checks current permission status
    var isGranted: Bool {
        permissionChecker.isTrusted
    }

    /// Starts polling for accessibility permissions
    /// If granted, re-launches the app
    func startPolling(interval: TimeInterval = 1.0) {
        stopPolling()

        Log.info("Starting accessibility permission polling", category: .app)

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }

        // Add to main run loop with common mode to ensure it fires during UI interactions
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops polling
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private Methods

    private func checkPermission() {
        if permissionChecker.isTrusted {
            Log.info("Accessibility permission detected during polling", category: .app)
            handlePermissionGranted()
        }
    }

    private func handlePermissionGranted() {
        // Stop polling immediately to prevent multiple checking
        stopPolling()

        Log.info("Restarting app to apply permissions...", category: .app)
        appController.relaunch()
    }
}
