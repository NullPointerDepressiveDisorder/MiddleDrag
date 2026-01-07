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
/// Protocol to mock Process for testing
protocol AppLifecycleProcessRunner {
    var executableURL: URL? { get set }
    var arguments: [String]? { get set }
    func run() throws
}

extension Process: AppLifecycleProcessRunner {}

class SystemAppLifecycleController: AppLifecycleControlling {

    // Factory for creating processes, can be overridden for testing
    internal var processFactory: () -> AppLifecycleProcessRunner = { Process() }

    func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        var task = processFactory()

        // Use executableURL instead of deprecated launchPath
        task.executableURL = URL(fileURLWithPath: "/bin/sh")

        // Pass bundle path as an argument to avoid shell injection
        // $0 will be the bundlePath passed as the first argument after the command string
        task.arguments = [
            "-c",
            "sleep 0.5 && open \"$0\"",
            bundlePath,
        ]

        do {
            try task.run()

            // Wait a moment to ensure the process has actually started
            // Note: run() is synchronous in starting the process, but the shell command runs async
            // To prevent race conditions where we terminate too early, we'll delay slightly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.terminate()
            }
        } catch {
            Log.error(
                "Failed to schedule app relaunch: \(error.localizedDescription)", category: .app)
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
