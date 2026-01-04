import AppKit
import Foundation

/// Manages accessibility permission polling and app handling
class AccessibilityMonitor {

    // MARK: - Properties

    private var timer: Timer?
    private let permissionChecker: AccessibilityPermissionChecking
    private let appController: AppLifecycleControlling
    private let notificationCenter: NotificationCenter

    private var lastKnownState: Bool = false

    /// Called when permission is granted (transition from false to true)
    var onGrant: (() -> Void)?

    /// Called when permission is revoked (transition from true to false)
    var onRevocation: (() -> Void)?

    // MARK: - Initialization

    init(
        permissionChecker: AccessibilityPermissionChecking = SystemAccessibilityPermissionChecker(),
        appController: AppLifecycleControlling = SystemAppLifecycleController(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.permissionChecker = permissionChecker
        self.appController = appController
        self.notificationCenter = notificationCenter
        self.lastKnownState = permissionChecker.isTrusted
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Public API

    /// Checks current permission status
    var isGranted: Bool {
        permissionChecker.isTrusted
    }

    /// Starts monitoring for accessibility permission changes
    func startMonitoring(interval: TimeInterval = 1.0) {
        stopMonitoring()

        Log.info("Starting accessibility permission monitoring", category: .app)

        // Update initial state
        lastKnownState = isGranted

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }

        // Add to main run loop with common mode to ensure it fires during UI interactions
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops monitoring
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private Methods

    private func checkPermission() {
        let currentState = permissionChecker.isTrusted

        if currentState != lastKnownState {
            if currentState {
                // False -> True: Granted
                Log.info("Accessibility permission granted", category: .app)
                onGrant?()

                // Default behavior handles relaunch in the callback, or we can provide a default if needed.
                // But for flexibility, we'll let the delegate/closure handle the action.
                // However, to maintain backward compatibility with the "auto restart" idea,
                // we can default to relaunching in the closure setup in AppDelegate.
            } else {
                // True -> False: Revoked
                Log.warning("Accessibility permission revoked!", category: .app)
                onRevocation?()
            }
            lastKnownState = currentState
        }
    }

    /// Helper to trigger relaunch (exposed for the closure to use if needed)
    func triggerRelaunch() {
        Log.info("Restarting app to apply permissions...", category: .app)
        appController.relaunch()
    }
}
