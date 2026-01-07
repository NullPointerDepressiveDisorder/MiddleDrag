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
        let bundlePath = Bundle.main.bundlePath
        
        // Use a shell command to relaunch after this process terminates
        // This ensures clean handoff without overlapping instances
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = [
            "-c",
            // Wait briefly for current process to fully terminate, then open the app
            "sleep 0.5 && open \"\(bundlePath)\""
        ]
        
        do {
            try task.run()
            // Terminate after launching the background relaunch task
            DispatchQueue.main.async {
                self.terminate()
            }
        } catch {
            Log.error("Failed to schedule app relaunch: \(error.localizedDescription)", category: .app)
            // Fall back to direct launch if shell approach fails
            fallbackRelaunch()
        }
    }
    
    private func fallbackRelaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            if let error = error {
                Log.error("Failed to restart app: \(error.localizedDescription)", category: .app)
            } else {
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
