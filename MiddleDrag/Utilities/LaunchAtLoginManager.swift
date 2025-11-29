import ServiceManagement
import Cocoa

/// Manages launch at login functionality
class LaunchAtLoginManager {
    
    static let shared = LaunchAtLoginManager()
    
    private init() {}
    
    /// Configure launch at login
    func setLaunchAtLogin(_ enabled: Bool) {
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
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to configure launch at login: \(error)")
        }
    }
    
    private func configureLaunchAtLoginLegacy(_ enabled: Bool) {
        // For older macOS versions, we would use LSSharedFileList
        // or SMLoginItemSetEnabled, but these are deprecated
        // For simplicity, we'll just log a message
        print("Launch at login configuration not available on macOS < 13.0")
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
