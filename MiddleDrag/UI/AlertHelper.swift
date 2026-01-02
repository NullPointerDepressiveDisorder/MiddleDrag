import Cocoa

// MARK: - Protocols for Dependency Injection

/// Protocol for presenting alerts and opening URLs, enabling testability
protocol AlertPresenter {
    func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse
    func openURL(_ url: URL)
}

/// Default implementation using NSAlert and NSWorkspace
class DefaultAlertPresenter: AlertPresenter {
    func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        return alert.runModal()
    }

    func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// Helper for displaying alerts and dialogs
class AlertHelper {

    // MARK: - Dependency Injection

    /// Injectable presenter for testing
    static var presenter: AlertPresenter = DefaultAlertPresenter()

    // MARK: - Alert Configuration (Testable)

    /// Creates and returns a configured About alert without presenting it
    static func createAboutAlert() -> NSAlert {
        let version =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

        let alert = NSAlert()
        alert.messageText = "MiddleDrag"
        alert.icon = NSImage(
            systemSymbolName: "hand.raised.fingers.spread", accessibilityDescription: nil)
        alert.informativeText = """
            Three-finger drag for middle mouse button emulation.
            Works alongside your system gestures!

            Version \(version)

            ✨ Features:
            • Works WITH system gestures enabled
            • Three-finger drag → Middle mouse drag
            • Three-finger tap → Middle mouse click
            • Smart gesture detection
            • Minimal CPU usage

            💡 Tips:
            • No need to disable system gestures
            • Adjust sensitivity for your workflow
            • Use "Configure System Gestures..." for advanced control

            Created for engineers, designers, and makers.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open GitHub")
        return alert
    }

    /// Creates and returns a configured Quick Setup alert without presenting it
    static func createQuickSetupAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "MiddleDrag Quick Setup"
        alert.informativeText = """
            ✅ MiddleDrag works WITH your existing trackpad gestures!

            No configuration needed - just use:
            • Three fingers drag = Middle mouse drag
            • Three-finger tap = Middle click

            Optional optimizations:
            • If you experience conflicts, you can disable system three-finger gestures
            • Use "Configure System Gestures..." in the Advanced menu for optimal control

            That's it! MiddleDrag uses Apple's multitouch framework to detect gestures before the system processes them.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it!")
        alert.addButton(withTitle: "Open Trackpad Settings")
        return alert
    }

    /// Creates and returns a configured Already Optimal alert without presenting it
    static func createGestureConfigurationAlreadyOptimalAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "System Gestures Already Configured"
        alert.informativeText = """
            ✅ Your trackpad is already configured for optimal MiddleDrag compatibility!

            3-finger system gestures are disabled, allowing MiddleDrag to use three-finger gestures without conflicts.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        return alert
    }

    /// Creates and returns a configured Gesture Configuration Prompt alert without presenting it
    static func createGestureConfigurationPromptAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Configure System Gestures"
        alert.informativeText = """
            MiddleDrag uses 3-finger gestures which can conflict with macOS system gestures.

            Current conflicting settings:
            \(SystemGestureHelper.describeConflictingSettings())

            Would you like to automatically:
            • Disable 3-finger system gestures
            • Enable 4-finger gestures instead

            This preserves Mission Control and Spaces functionality while freeing up 3-finger gestures for MiddleDrag.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Apply Changes")
        alert.addButton(withTitle: "Open Trackpad Settings")
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    /// Creates and returns a configured Success alert without presenting it
    static func createGestureConfigurationSuccessAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Settings Applied"
        alert.informativeText = """
            ✅ System gesture settings have been updated!

            Changes applied:
            • 3-finger Mission Control → 4-finger
            • 3-finger Spaces swipe → 4-finger

            The Dock has been restarted to apply changes.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        return alert
    }

    /// Creates and returns a configured Failure alert without presenting it
    static func createGestureConfigurationFailureAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Failed to Apply Settings"
        alert.informativeText = """
            ⚠️ Some settings could not be applied automatically.

            Please configure manually:
            1. Open System Settings → Trackpad → More Gestures
            2. Set Mission Control to "Swipe Up with Four Fingers"
            3. Set "Swipe between full-screen applications" to "Swipe Left or Right with Four Fingers"
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Trackpad Settings")
        alert.addButton(withTitle: "Cancel")
        return alert
    }

    // MARK: - URL Constants

    /// GitHub project URL
    static let gitHubURL = URL(
        string: "https://github.com/NullPointerDepressiveDisorder/MiddleDrag")

    /// Trackpad settings URL
    static let trackpadSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.trackpad")

    // MARK: - Public Methods (Present Alerts)

    static func showAbout() {
        let alert = createAboutAlert()
        if presenter.runModal(alert) == .alertSecondButtonReturn {
            if let url = gitHubURL {
                presenter.openURL(url)
            }
        }
    }

    static func showQuickSetup() {
        let alert = createQuickSetupAlert()
        if presenter.runModal(alert) == .alertSecondButtonReturn {
            openTrackpadSettings()
        }
    }

    /// Show dialog for configuring system gestures when they're already optimal
    static func showGestureConfigurationAlreadyOptimal() {
        let alert = createGestureConfigurationAlreadyOptimalAlert()
        _ = presenter.runModal(alert)
    }

    /// Show dialog explaining gesture conflict and offering to apply changes
    /// - Returns: true if user wants to apply the recommended changes
    static func showGestureConfigurationPrompt() -> Bool {
        let alert = createGestureConfigurationPromptAlert()
        let response = presenter.runModal(alert)

        if response == .alertSecondButtonReturn {
            openTrackpadSettings()
            return false
        }

        return response == .alertFirstButtonReturn
    }

    /// Show success feedback after applying changes
    static func showGestureConfigurationSuccess() {
        let alert = createGestureConfigurationSuccessAlert()
        _ = presenter.runModal(alert)
    }

    /// Show failure feedback if changes couldn't be applied
    static func showGestureConfigurationFailure() {
        let alert = createGestureConfigurationFailureAlert()
        if presenter.runModal(alert) == .alertFirstButtonReturn {
            openTrackpadSettings()
        }
    }

    private static func openTrackpadSettings() {
        if let url = trackpadSettingsURL {
            presenter.openURL(url)
        }
    }
}
