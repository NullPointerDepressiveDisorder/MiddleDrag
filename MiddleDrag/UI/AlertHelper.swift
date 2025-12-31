import Cocoa

/// Helper for displaying alerts and dialogs
class AlertHelper {

    static func showAbout() {
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
            • Enable gesture blocking only if needed

            Created for engineers, designers, and makers.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open GitHub")

        if alert.runModal() == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/NullPointerDepressiveDisorder/MiddleDrag")
            {
                NSWorkspace.shared.open(url)
            }
        }
    }

    static func showQuickSetup() {
        let alert = NSAlert()
        alert.messageText = "MiddleDrag Quick Setup"
        alert.informativeText = """
            ✅ MiddleDrag works WITH your existing trackpad gestures!

            No configuration needed - just use:
            • Three fingers drag = Middle mouse drag
            • Three-finger tap = Middle click

            Optional optimizations:
            • If you experience conflicts, you can disable system three-finger gestures
            • Enable "Block System Gestures" in Advanced menu for exclusive control

            That's it! MiddleDrag uses Apple's multitouch framework to detect gestures before the system processes them.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it!")
        alert.addButton(withTitle: "Open Trackpad Settings")

        if alert.runModal() == .alertSecondButtonReturn {
            openTrackpadSettings()
        }
    }

    /// Show dialog for configuring system gestures when they're already optimal
    static func showGestureConfigurationAlreadyOptimal() {
        let alert = NSAlert()
        alert.messageText = "System Gestures Already Configured"
        alert.informativeText = """
            ✅ Your trackpad is already configured for optimal MiddleDrag compatibility!

            3-finger system gestures are disabled, allowing MiddleDrag to use three-finger gestures without conflicts.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Show dialog explaining gesture conflict and offering to apply changes
    /// - Returns: true if user wants to apply the recommended changes
    static func showGestureConfigurationPrompt() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Configure System Gestures"
        alert.informativeText = """
            MiddleDrag uses 3-finger gestures which can conflict with macOS system gestures.

            Current conflicting settings:
            \(SystemGestureHelper.describeCurrentSettings())

            Would you like to automatically:
            • Disable 3-finger system gestures
            • Enable 4-finger gestures instead

            This preserves Mission Control and Spaces functionality while freeing up 3-finger gestures for MiddleDrag.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Apply Changes")
        alert.addButton(withTitle: "Open Trackpad Settings")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertSecondButtonReturn {
            openTrackpadSettings()
            return false
        }

        return response == .alertFirstButtonReturn
    }

    /// Show success feedback after applying changes
    static func showGestureConfigurationSuccess() {
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
        alert.runModal()
    }

    /// Show failure feedback if changes couldn't be applied
    static func showGestureConfigurationFailure() {
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

        if alert.runModal() == .alertFirstButtonReturn {
            openTrackpadSettings()
        }
    }

    private static func openTrackpadSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.trackpad") {
            NSWorkspace.shared.open(url)
        }
    }
}
