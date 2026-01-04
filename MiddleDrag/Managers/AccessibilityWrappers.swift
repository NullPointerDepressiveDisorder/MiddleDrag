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
