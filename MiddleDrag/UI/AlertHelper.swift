import Cocoa

/// Helper for displaying alerts and dialogs
class AlertHelper {
    
    static func showAbout() {
        let alert = NSAlert()
        alert.messageText = "MiddleDrag"
        alert.icon = NSImage(systemSymbolName: "hand.raised.fingers.spread", accessibilityDescription: nil)
        alert.informativeText = """
        Three-finger drag for middle mouse button emulation.
        Works alongside your system gestures!
        
        Version 2.0.0
        
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
        Open source: github.com/kmohindroo/MiddleDrag
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open GitHub")
        
        if alert.runModal() == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/kmohindroo/MiddleDrag") {
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
    
    static func showSystemGestureWarning() {
        let alert = NSAlert()
        alert.messageText = "Experimental Feature"
        alert.informativeText = """
        System gesture blocking is experimental and may:
        • Disable Mission Control gestures while dragging
        • Cause unexpected behavior with some apps
        
        This is usually not needed - MiddleDrag works alongside system gestures.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    static func showAccessibilityPermissionRequired() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        MiddleDrag needs accessibility permissions to:
        • Detect three-finger trackpad gestures
        • Simulate middle mouse button events
        
        After granting permission, please restart MiddleDrag.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        
        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
            
            // Trigger system prompt
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            
            return true
        }
        
        return false
    }
    
    private static func openTrackpadSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.trackpad") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
