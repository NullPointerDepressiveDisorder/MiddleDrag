import AppKit
import Foundation

/// Protocol for checking accessibility permissions (for testing)
public protocol AccessibilityPermissionChecking {
    var isTrusted: Bool { get }
}

/// Default implementation wrapping system API
public class SystemAccessibilityPermissionChecker: AccessibilityPermissionChecking {
    public init() {}
    public var isTrusted: Bool {
        AXIsProcessTrusted()
    }
}

/// Protocol for app control (relaunching/termination) (for testing)
public protocol AppLifecycleControlling {
    func relaunch()
    @MainActor func terminate()
}

/// Default implementation using NSWorkspace and NSApp
/// Protocol to mock Process for testing
protocol AppLifecycleProcessRunner {
    var executableURL: URL? { get set }
    var arguments: [String]? { get set }
    func run() throws
}

extension Process: AppLifecycleProcessRunner {}

/// Controller for app lifecycle operations (relaunch, terminate)
/// Marked @unchecked Sendable as it's only used for simple fire-and-forget operations
/// with no meaningful shared mutable state that could race
public class SystemAppLifecycleController: AppLifecycleControlling, @unchecked Sendable {
    public init() {}

    // Factory for creating processes, can be overridden for testing
    internal var processFactory: () -> AppLifecycleProcessRunner = { Process() }

    public func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        var task = processFactory()

        // Use executableURL instead of deprecated launchPath
        task.executableURL = URL(fileURLWithPath: "/bin/sh")

        // Pass bundle path as an argument to avoid shell injection
        // $0 will be the bundlePath passed as the first argument after the command string
        task.arguments = [
            "-c",
            "sleep 0.5 && open -n \"$0\"",
            bundlePath,
        ]

        do {
            try task.run()

            // Wait a moment to ensure the process has actually started
            // Note: run() is synchronous in starting the process, but the shell command runs async
            // To prevent race conditions where we terminate too early, we'll delay slightly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                MainActor.assumeIsolated {
                    self?.terminate()
                }
            }
        } catch {
            Log.error(
                "Failed to schedule app relaunch: \(error.localizedDescription)", category: .app)
            fallbackRelaunch()
        }
    }

    // Closure for opening applications, can be overridden for testing
    internal var workspaceAppOpener:
        @Sendable (URL, NSWorkspace.OpenConfiguration, @escaping @Sendable (NSRunningApplication?, Error?) -> Void) ->
            Void = { url, config, completion in
                NSWorkspace.shared.openApplication(
                    at: url, configuration: config, completionHandler: completion)
            }

    private func fallbackRelaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true

        workspaceAppOpener(url, config) { [weak self] _, error in
            if let error = error {
                Log.error("Failed to restart app: \(error.localizedDescription)", category: .app)
            } else {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.terminate()
                    }
                }
            }
        }
    }

    @MainActor
    public func terminate() {
        NSApp.terminate(nil)
    }
}
