import ServiceManagement
import Cocoa

/// Manages launch at login functionality
/// Thread-safety: Uses ServiceManagement APIs which are thread-safe
public final class LaunchAtLoginManager: @unchecked Sendable {
    
    public static let shared = LaunchAtLoginManager()
    
    private init() {}
    
    /// Configure launch at login
    public func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            configureLaunchAtLoginModern(enabled)
        } else {
            configureLaunchAtLoginLegacy(enabled)
        }
    }
    
    @available(macOS 13.0, *)
    private func configureLaunchAtLoginModern(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                Log.info("Launch at login enabled", category: .app)
            } else {
                try SMAppService.mainApp.unregister()
                Log.info("Launch at login disabled", category: .app)
            }
        } catch {
            Log.error("Failed to configure launch at login: \(error.localizedDescription)", category: .app, error: error)
        }
    }
    
    private func configureLaunchAtLoginLegacy(_ enabled: Bool) {
        // For older macOS versions, we would use LSSharedFileList
        // or SMLoginItemSetEnabled, but these are deprecated
        Log.warning("Launch at login not available on macOS < 13.0", category: .app)
    }
    
    /// Check if launch at login is enabled
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return false
        }
    }
}
